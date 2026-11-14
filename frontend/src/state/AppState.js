import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react'
import AsyncStorage from '@react-native-async-storage/async-storage'
import * as Location from 'expo-location'
import * as api from '../api'

// 앱 상태. 데이터는 전부 서버(Supabase)에서 옵니다. 예시 데이터는 없습니다.
const Ctx = createContext(null)

// 위치를 못 받을 때 쓰는 기준점(인하대 주변).
const FALLBACK = { lat: 37.452, lng: 126.656 }
const SESSION_WAIT_MS = 5000
const TUTORIAL_KEY = 'jipgepyo:tutorial-seen'
const CONSENT_KEY = 'jipgepyo:consent' // 로그인 화면이 기기에 남기는 동의 기록

export function AppStateProvider({ children }) {
  const [session, setSession] = useState(undefined) // undefined: 확인 중, null: 로그아웃
  const [tutorialSeen, setTutorialSeen] = useState(undefined) // undefined: 확인 중
  const [coords, setCoords] = useState(null)
  const [located, setLocated] = useState(false) // 실제 위치를 받았는지
  const [reports, setReports] = useState([])
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState(null)
  const [profile, setProfile] = useState(null)
  const [crews, setCrews] = useState([])
  const [myCrew, setMyCrew] = useState(null)
  const [shop, setShop] = useState([])
  const [cosmetics, setCosmetics] = useState([])
  const [notices, setNotices] = useState([])
  const [dash, setDash] = useState(null) // 속도선 전환 연출 { id, then }
  const [celebrate, setCelebrate] = useState(null) // 의뢰 완료 연출에 쓸 보상 정보
  const [photos, setPhotos] = useState({}) // { [reportId]: { before, after } }
  const [draftPhoto, setDraftPhoto] = useState(null)
  const [sheet, setSheet] = useState({ id: null, visible: false })
  const [toast, setToast] = useState(null)
  const coordsRef = useRef(null)


  // action: { label, onPress } 를 주면 안내 안에 버튼이 붙습니다.
  const showToast = useCallback((message, { action = null, ms = 2600 } = {}) => {
    const id = Date.now() + Math.random()
    setToast({ id, message, action })
    setTimeout(() => setToast((t) => (t && t.id === id ? null : t)), ms)
  }, [])

  useEffect(() => {
    // 로그인 확인이 끝나지 않으면 빈 화면에 멈추므로, 몇 초 안에 답이 없으면 로그인 화면을 보여 줍니다.
    const giveUp = setTimeout(() => setSession((s) => (s === undefined ? null : s)), SESSION_WAIT_MS)
    api.getSession().then(setSession).catch(() => setSession(null))
    const sub = api.onAuthChange(setSession)
    return () => {
      clearTimeout(giveUp)
      sub.unsubscribe()
    }
  }, [])

  // 처음 안내를 봤는지는 기기에 저장합니다(계정과 무관).
  useEffect(() => {
    AsyncStorage.getItem(TUTORIAL_KEY)
      .then((v) => setTutorialSeen(v === '1'))
      .catch(() => setTutorialSeen(true))
  }, [])

  const locate = useCallback(async () => {
    try {
      const perm = await Location.requestForegroundPermissionsAsync()
      if (perm.status !== 'granted') throw new Error('denied')
      const pos = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced })
      const c = { lat: pos.coords.latitude, lng: pos.coords.longitude }
      setLocated(true)
      setCoords(c)
      coordsRef.current = c
      return c
    } catch {
      setLocated(false)
      setCoords(FALLBACK)
      coordsRef.current = FALLBACK
      return FALLBACK
    }
  }, [])

  const loadProfile = useCallback(async () => {
    try {
      setProfile(await api.getMyProfile())
      setCrews((await api.getCrews()) || [])
      setMyCrew(await api.getMyCrew())
      setShop((await api.getShopItems()) || [])
      setCosmetics((await api.cosmeticsApi.list()) || [])
      setNotices((await api.socialApi.notices()) || [])
    } catch {
      // 프로필은 다음 새로고침에서 다시 시도
    }
  }, [])

  const refresh = useCallback(
    async ({ relocate = false } = {}) => {
      setLoading(true)
      setLoadError(null)
      try {
        const c = !relocate && coordsRef.current ? coordsRef.current : await locate()
        setReports((await api.getNearbyReports(c)) || [])
      } catch (e) {
        setLoadError(e.message)
      } finally {
        setLoading(false)
      }
      loadProfile()
    },
    [locate, loadProfile],
  )

  const userId = session?.user?.id
  // 서버 모드의 둘러보기(익명) 계정. 읽기만 되고 쓰기는 서버가 막습니다.
  const guest = !api.isLocal && !!session?.user?.is_anonymous
  // 로그인한 계정의 가입 동의를 서버에 남깁니다. 서버는 필수 동의가 없으면 쓰기 기능을 막습니다.
  useEffect(() => {
    if (!api.authApi || !userId || guest) return
    ;(async () => {
      if ((await api.authApi.getConsent())?.ok) return // 이미 서버에 있음
      const v = await AsyncStorage.getItem(CONSENT_KEY)
      if (v) await api.authApi.saveConsent(JSON.parse(v).items || {})
    })().catch(() => {})
  }, [userId, guest])
  useEffect(() => {
    if (userId) refresh({ relocate: true })
    else {
      setReports([])
      setProfile(null)
      setCrews([])
      setMyCrew(null)
    }
  }, [userId, refresh])

  // 공개를 기다리는 내 제보가 있으면 공개 시각에 맞춰 목록을 새로 받습니다.
  useEffect(() => {
    const next = reports.map((r) => (r.pending_until ? new Date(r.pending_until).getTime() : 0)).filter(Boolean).sort((a, b) => a - b)[0]
    if (!next) return
    const t = setTimeout(() => refresh(), Math.max(1000, next - Date.now() + 500))
    return () => clearTimeout(t)
  }, [reports, refresh])

  const patch = (id, fields) => setReports((rs) => rs.map((r) => (r.id === id ? { ...r, ...fields } : r)))

  // 서버 호출을 감싸 실패하면 안내만 띄웁니다.
  const run = useCallback(
    async (fn) => {
      try {
        return await fn()
      } catch (e) {
        showToast(e.message)
        return null
      }
    },
    [showToast],
  )

  const value = useMemo(
    () => ({
      session,
      tutorialSeen,
      finishTutorial: () => {
        setTutorialSeen(true)
        AsyncStorage.setItem(TUTORIAL_KEY, '1').catch(() => {})
      },
      replayTutorial: () => setTutorialSeen(false),
      userId,
      guest,
      emailAuth: !!api.authApi,
      signInEmail: (email, password) => run(() => api.authApi.signIn(email, password)),
      // 메일 확인이 켜진 서버에서는 가입 직후 로그인되지 않습니다. 그때는 'confirm' 을 돌려줍니다.
      signUpEmail: (email, password) => run(async () => (await api.authApi.signUp(email, password)) || 'confirm'),
      coords,
      located,
      reports,
      loading,
      loadError,
      profile,
      crews,
      myCrew,
      shop,
      cosmetics,
      notices,
      social: !!api.socialApi,
      canStyle: !!api.profileApi,
      dash,
      // 화면을 가로지르는 속도선과 함께 다음 화면으로 넘어갑니다.
      dashTo: (then) => setDash({ id: Date.now(), then }),
      endDash: () => setDash(null),
      mark: (id, kind) =>
        run(async () => {
          await api.socialApi.mark(id, kind)
          await refresh()
        }),
      answerNotice: (id, answer) =>
        run(async () => {
          await api.socialApi.answer(id, answer)
          await loadProfile()
          showToast(answer === 'ok' ? '확인해 주셔서 고마워요' : '운영진이 다시 살펴볼게요')
        }),
      flag: (id, reason) =>
        run(async () => {
          await api.socialApi.flag(id, reason)
          await refresh()
          showToast('신고했어요. 운영진이 확인할게요')
          return true
        }),
      celebrate,
      dismissCelebrate: () => setCelebrate(null),
      localMode: api.isLocal,
      photos,
      draftPhoto,
      setDraftPhoto,
      toast,
      showToast,
      refresh,
      sheet,
      openSheet: (id) => setSheet({ id, visible: true }),
      hideSheet: () => setSheet((s) => ({ ...s, visible: false })),
      reopenSheet: () => setSheet((s) => (s.id ? { ...s, visible: true } : s)),
      signIn: () => run(api.signInAnonymously),
      signOut: () => api.signOut(),
      resetLocal: api.resetLocal ? () => api.resetLocal() : null,
      setPhoto: (id, slot, shot) => {
        setPhotos((p) => ({ ...p, [id]: { ...p[id], [slot]: shot } }))
        // 서버는 사진이 올라온 시각으로 "찍고 바로 완료"를 판정하므로 찍자마자 올립니다.
        if (api.uploadProofPhoto) run(() => api.uploadProofPhoto(userId, id, slot, shot))
      },
      // 하트는 누르면 바로 확정되고 취소할 수 없습니다.
      toggleHeart: (id) => {
        const r = reports.find((x) => x.id === id)
        if (!r) return
        if (r.liked_by_me) return showToast(api.errorText({ message: 'HEART_FINAL' }))
        if (profile && profile.hearts_today >= profile.hearts_limit) return showToast(api.errorText({ message: 'HEART_DAILY_LIMIT' }))
        const before = { liked_by_me: false, like_count: r.like_count ?? 0 }
        patch(id, { liked_by_me: true, like_count: before.like_count + 1 }) // 먼저 화면에 반영하고, 실패하면 되돌립니다
        return run(async () => {
          try {
            const d = await api.toggleLike(id)
            patch(id, { liked_by_me: d.liked, like_count: d.like_count, is_promoted: d.is_promoted })
            showToast(d.points_gained ? `하트를 눌러 +${d.points_gained}P 받았어요` : '하트를 눌렀어요')
            refresh() // 하트에 따라 보상이 달라지므로 목록을 새로 받습니다
          } catch (e) {
            patch(id, before)
            throw e
          }
        })
      },
      accept: (id) =>
        run(async () => {
          const d = await api.acceptReport(id)
          patch(id, { i_am_participating: true, status: d.status, current_members: d.current_members, required_members: d.required_members, deadline_at: d.deadline_at })
          showToast(d.status === 'in_progress' ? '의뢰를 수락했어요. 현장에서 사진을 찍어 주세요' : '참여했어요. 인원이 모이면 시작돼요')
          return d
        }),
      cancel: (id) =>
        run(async () => {
          await api.cancelParticipation(id)
          setPhotos((p) => ({ ...p, [id]: undefined }))
          showToast('수락을 취소했어요')
          await refresh()
          return true
        }),
      submitProof: (id) =>
        run(async () => {
          const p = photos[id] || {}
          const d = await api.submitProof(userId, id, p.before, p.after || p.before)
          setPhotos((x) => ({ ...x, [id]: undefined }))
          setCelebrate(d)
          await refresh()
          return d
        }),
      createReport: (input) =>
        run(async () => {
          const id = await api.createReport(userId, input)
          await refresh()
          return id ?? true
        }),
      createCrew: (input) =>
        run(async () => {
          await api.createCrew(input)
          await loadProfile()
          showToast(`${input.name} 크루를 만들었어요`)
          return true
        }),
      joinCrew: (crew) =>
        run(async () => {
          await api.joinCrew(crew.id)
          await loadProfile()
          showToast(`${crew.name} 크루에 가입했어요`)
          return true
        }),
      leaveCrew: () =>
        run(async () => {
          await api.leaveCrew()
          await loadProfile()
          showToast('크루에서 나왔어요')
          return true
        }),
      redeem: (item) =>
        run(async () => {
          const d = await api.redeemItem(item.id)
          await loadProfile()
          showToast(`${item.name} 교환 완료 · 쿠폰 ${d.coupon_code}`)
          return d
        }),
      // 꾸미기: 내 것이면 착용, 아니면 포인트로 사서 바로 착용합니다.
      wearCosmetic: (item) =>
        run(async () => {
          if (item.owned) await api.cosmeticsApi.equip(item.id)
          else await api.cosmeticsApi.buy(item.id)
          await loadProfile()
          showToast(item.owned ? `${item.name}(으)로 바꿨어요` : `${item.name} 구매 완료`)
          return true
        }),
      saveAvatar: (uri) =>
        run(async () => {
          await api.profileApi.setAvatar(uri)
          await loadProfile()
          showToast(uri ? '프로필 사진을 바꿨어요' : '기본 프로필로 돌아갔어요')
          return true
        }),
      claimFeat: (feat) =>
        run(async () => {
          const d = await api.profileApi.claimFeat(feat.id)
          await loadProfile()
          showToast([`+${d.points_gained}P · +${d.xp_gained}XP`, d.cosmetic ? `꾸미기 "${d.cosmetic}" 획득` : null, d.leveled_up ? `Lv.${d.level} 달성` : null].filter(Boolean).join(' · '))
          return d
        }),
      saveTitle: (key, label) =>
        run(async () => {
          await api.profileApi.setTitle(key)
          await loadProfile()
          showToast(key ? `칭호를 "${label}"(으)로 바꿨어요` : '칭호를 뺐어요')
          return true
        }),
      saveNickname: (nickname) =>
        run(async () => {
          await api.setNickname(nickname)
          await loadProfile()
          showToast('닉네임을 바꿨어요')
          return true
        }),
    }),
    [session, tutorialSeen, userId, guest, coords, located, reports, loading, loadError, profile, crews, myCrew, shop, cosmetics, notices, dash, celebrate, photos, draftPhoto, toast, sheet, showToast, refresh, run, loadProfile],
  )
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export const useApp = () => useContext(Ctx)
