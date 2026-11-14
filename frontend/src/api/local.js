import AsyncStorage from '@react-native-async-storage/async-storage'
import { Platform } from 'react-native'
import { errorText } from './errors'
import { ACHIEVEMENTS, statsOf } from '../lib/achievements'

// 기기 저장소 구현. 서버가 준비되기 전까지 앱 기능을 이 기기 안에서 실제로 동작시킵니다.
// 응답 모양은 백엔드 API 가이드와 같게 맞췄고, 규칙은 docs/api.md 를 따릅니다
// (하루 완료 3개·하트 10개 상한, KST 0시 기준, 인증 사진은 의뢰 위치 100m 이내).
// 포인트 규칙(2026-11-12 확정): 의뢰를 올린 사람은 포인트가 없고 해결한 사람만 받습니다. 하트를 누른 사람은 소량을 받습니다.
// 한계: 데이터가 이 기기에만 있어 다른 사람과 공유되지 않고, 하트·승격·포인트 판정은 서버가 있어야 의미가 있습니다.

const KEY = 'jubquest:v1'
const PLACE = {
  drain: ['빗물받이', 100],
  bus_stop: ['버스정류장', 80],
  park: ['공원', 150],
  street: ['골목·거리', 80],
  etc: ['기타', 50],
}
const XP_PER_LEVEL = 300
const DAILY_LIMIT = 3
const PROOF_RADIUS_M = 100
const REPORT_DELAY_MS = 3 * 60 * 1000 // 제보는 올리고 3분 뒤에 의뢰판에 공개됩니다(연달아 올리고 바로 수락하는 것을 막음)
const PROOF_APART_M = 100 // 전·후 사진 촬영 위치 사이 거리 상한
const PROOF_MIN_GAP_MS = 60 * 1000 // 임시값: 치우기 전 사진을 찍고 최소 이만큼 지나야 치운 뒤 사진을 받습니다
const DAY = 24 * 3600 * 1000
const HEART_DAILY_LIMIT = 10
// 아래 세 값은 임시값입니다. 서버가 생기면 서버가 정합니다.
const HEARTS_PER_STEP = 3 // 하트가 이만큼 모일 때마다
const POINTS_PER_STEP = 5 // 해결 보상에 이만큼 포인트가 붙습니다
const CREW_CREATE_LEVEL = 3 // 크루를 만들 수 있는 최소 레벨
const HEART_GIVER_POINTS = 1 // 하트를 누른 사람이 받는 포인트
const CREW_XP_PER_LEVEL = 500
const pointsOf = (r) => Math.floor(r.likes.length / HEARTS_PER_STEP) * POINTS_PER_STEP

// 포인트 교환 상점(예시 상품). 실제 쿠폰 발급은 연결되어 있지 않습니다.
const SHOP = [
  { id: 1, name: '종량제 봉투 10L 5장', cost: 500 },
  { id: 2, name: '편의점 1,000원 쿠폰', cost: 1000 },
  { id: 3, name: '카페 아메리카노', cost: 3000 },
  { id: 4, name: '충주사랑상품권 5,000원', cost: 5000 },
]

// 프로필 꾸미기(예시 품목·가격). 포인트로 사는 것과 레벨로만 열리는 것을 나눕니다.
// kind: frame = 프로필 테두리(style 은 components/AvatarFrame.js 의 모양 이름), name = 닉네임 색
const COSMETICS = [
  { id: 'frame-tape', kind: 'frame', name: '노란 테이프', style: 'plain', colors: ['#FFD43B'], cost: 0, level: 1 },
  { id: 'frame-neon', kind: 'frame', name: '편의점 네온사인', style: 'neon', colors: ['#3182F6', '#7DF9FF', '#3182F6'], cost: 30, level: 1 },
  { id: 'frame-aurora', kind: 'frame', name: '새벽 청소차 오로라', style: 'spin', colors: ['#3DD68C', '#7DF9FF', '#A97CFF', '#3DD68C'], cost: 60, level: 1 },
  { id: 'frame-galaxy', kind: 'frame', name: '분리수거 은하수', style: 'stars', colors: ['#A97CFF', '#FF7EB6', '#3182F6', '#A97CFF'], cost: 120, level: 1 },
  { id: 'frame-gold', kind: 'frame', name: '황금 집게', style: 'royal', colors: ['#FFF3B0', '#FFD43B', '#FF9F1A', '#FFD43B'], cost: 0, level: 3 },
  { id: 'frame-legend', kind: 'frame', name: '전설의 줍줍러', style: 'legend', colors: ['#FF7EB6', '#FFD43B', '#3DD68C', '#7DF9FF', '#A97CFF', '#FF7EB6'], cost: 0, level: 6 },
  // 도전과제 보상으로만 받는 품목(feat = 도전과제 id). 살 수 없습니다.
  { id: 'frame-ember', kind: 'frame', name: '열 번 찍은 불꽃', style: 'stars', colors: ['#FF9F1A', '#F04452', '#FFD43B', '#FF9F1A'], cost: 0, level: 1, feat: 'ten' },
  { id: 'frame-month', kind: 'frame', name: '개근상 리본', style: 'neon', colors: ['#3DD68C', '#FFD43B', '#3DD68C'], cost: 0, level: 1, feat: 'streak4' },
  { id: 'name-white', kind: 'name', name: '기본 닉네임 색', colors: ['#F2F4F6'], cost: 0, level: 1 },
  { id: 'name-tape', kind: 'name', name: '노란 닉네임', colors: ['#FFD43B'], cost: 80, level: 1 },
  { id: 'name-mint', kind: 'name', name: '민트 닉네임', colors: ['#7DF9FF'], cost: 0, level: 4 },
  { id: 'name-rose', kind: 'name', name: '장미 닉네임', colors: ['#FF7EB6'], cost: 0, level: 1, feat: 'places' },
]
const MARKS = ['still', 'gone', 'worse']
// 내 것인지: 도전과제 보상·구매 품목은 보유 목록에 있어야 하고, 레벨 품목은 레벨이 되면 내 것입니다.
const has = (me, c) => (c.feat || c.cost > 0 ? (me.cosmetics || []).includes(c.id) : levelOf(me.xp) >= c.level)
const DEFAULT_LOOK = { frame: 'frame-tape', name: 'name-white' }
const item = (id) => COSMETICS.find((c) => c.id === id)
// 저장된 착용 품목이 목록에서 빠졌으면 기본으로 돌아갑니다.
const lookOf = (me) => {
  const look = { ...DEFAULT_LOOK, ...(me.look || {}) }
  for (const k of Object.keys(DEFAULT_LOOK)) if (!item(look[k])) look[k] = DEFAULT_LOOK[k]
  return look
}
const frameOf = (me) => {
  const c = item(lookOf(me).frame)
  return { style: c.style, colors: c.colors }
}

// 제휴 의뢰 예시 1건. 서버가 없어 제휴처가 올릴 경로가 없으므로 앱이 하나를 넣어 둡니다.
// 인증이 가능하도록 처음 받은 내 위치에서 약 60m 떨어진 곳에 둡니다. 보상 금액은 예시값입니다.
const PARTNER = {
  title: '망가진 공원 벤치 사진 찍기',
  description: '공원에서 부서지거나 망가진 벤치를 찾아 사진으로 알려 주세요. 확인되면 충주사랑상품권을 드려요.',
  place_type: 'park',
  proof_mode: 'single', // 치우는 의뢰가 아니라 사진 한 장으로 인증
  proof_label: '벤치 사진',
  partner_name: '충주시 제휴',
  reward_label: '충주사랑상품권 5,000원',
  reward_value: '5,000원',
  reward_unit: '상품권',
}

let cache = null
const listeners = new Set()

async function load() {
  if (!cache) {
    try {
      cache = JSON.parse(await AsyncStorage.getItem(KEY)) || null
    } catch {
      cache = null
    }
    cache = cache || { user: null, reports: [], nextId: 1 }
    cache.crews = cache.crews || []
  }
  return cache
}
const save = async () => {
  try {
    await AsyncStorage.setItem(KEY, JSON.stringify(cache))
  } catch {
    throw new Error('기기 저장 공간이 부족해요. 완료된 의뢰가 많다면 설정에서 기록을 지워 주세요')
  }
}

// 웹은 사진이 data: 주소로 저장소(약 5MB)에 들어가므로 작게 줄여 둡니다.
async function keepPhoto(uri, max = 640) {
  if (Platform.OS !== 'web' || !uri?.startsWith('data:')) return uri
  try {
    const img = new Image()
    await new Promise((ok, no) => {
      img.onload = ok
      img.onerror = no
      img.src = uri
    })
    const scale = Math.min(1, max / Math.max(img.width, img.height))
    const c = document.createElement('canvas')
    c.width = Math.round(img.width * scale)
    c.height = Math.round(img.height * scale)
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height)
    return c.toDataURL('image/jpeg', 0.6)
  } catch {
    return uri
  }
}
// 두 사진이 거의 같은 장면인지(치우지 않고 연달아 찍었는지) 봅니다. 32×32 로 줄여 밝기 차이 평균을 냅니다.
// 웹에서만 계산할 수 있고, 폰과 서버 연결 뒤에는 서버가 판정해야 합니다(docs/backend-requests.md 3-6).
async function sameScene(a, b) {
  if (Platform.OS !== 'web' || typeof document === 'undefined') return false
  try {
    const px = async (uri) => {
      const img = new Image()
      await new Promise((ok, no) => {
        img.onload = ok
        img.onerror = no
        img.src = uri
      })
      const c = document.createElement('canvas')
      c.width = c.height = 32
      const g = c.getContext('2d')
      g.drawImage(img, 0, 0, 32, 32)
      return g.getImageData(0, 0, 32, 32).data
    }
    const [x, y] = [await px(a), await px(b)]
    let sum = 0
    for (let i = 0; i < x.length; i += 4) sum += Math.abs(x[i] - y[i]) + Math.abs(x[i + 1] - y[i + 1]) + Math.abs(x[i + 2] - y[i + 2])
    return sum / (32 * 32 * 3) < 4
  } catch {
    return false
  }
}
const fail = (code) => {
  throw new Error(errorText({ message: code }))
}

function meters(a, b) {
  const rad = (d) => (d * Math.PI) / 180
  const dLat = rad(b.lat - a.lat)
  const dLng = rad(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2
  return 6371000 * 2 * Math.asin(Math.sqrt(h))
}
// 한국 시간 기준 날짜(YYYY-MM-DD)
const kstDay = (t) => new Date(new Date(t).getTime() + 9 * 3600 * 1000).toISOString().slice(0, 10)
const kstWeek = (t) => Math.floor((new Date(t).getTime() + 9 * 3600 * 1000 - 4 * DAY) / (7 * DAY)) // 월요일 시작

const sessionOf = (user) => (user ? { user: { id: user.id } } : null)

export async function getSession() {
  const db = await load()
  return db.signedOut ? null : sessionOf(db.user)
}
export function onAuthChange(cb) {
  listeners.add(cb)
  return { unsubscribe: () => listeners.delete(cb) }
}
const emit = () => listeners.forEach((cb) => cb(cache.signedOut ? null : sessionOf(cache.user)))

export async function signInAnonymously() {
  const db = await load()
  if (!db.user) {
    const id = `local-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`
    db.user = { id, nickname: `줍줍이${Math.floor(1000 + Math.random() * 9000)}`, xp: 0, points: 0, completed: [], createdAt: new Date().toISOString() }
  }
  db.signedOut = false
  await save()
  emit()
  return sessionOf(db.user)
}
// 로그아웃해도 이 기기의 기록은 남겨 둡니다. 다시 시작하면 같은 계정으로 이어집니다.
export async function signOut() {
  const db = await load()
  db.signedOut = true
  await save()
  emit()
}
// 이 기기의 기록을 모두 지웁니다(서버가 없어 다시 불러올 수 없음).
export async function resetLocal() {
  cache = { user: null, reports: [], nextId: 1, crews: [] }
  await save()
  emit()
}

// 인증 시간이 지난 의뢰는 다시 모집 중으로 돌립니다.
function sweep(db) {
  for (const r of db.reports) {
    if (r.status === 'in_progress' && r.deadline_at && new Date(r.deadline_at).getTime() < Date.now()) {
      r.status = 'open'
      r.members = []
      r.deadline_at = null
    }
  }
}

function view(r, me, from) {
  const [label, xp] = PLACE[r.place_type] || PLACE.etc
  return {
    id: r.id,
    kind: r.kind || 'report',
    partner_name: r.partner_name || null,
    proof_mode: r.proof_mode || 'before_after',
    proof_label: r.proof_label || null,
    reward_label: r.reward_label || null,
    reward_value: r.reward_value || null,
    reward_unit: r.reward_unit || null,
    title: r.title,
    description: r.description,
    place_type: r.place_type,
    place_label: label,
    issue_type: r.issue_type || null,
    is_mine: r.reporter_id === me.id,
    // 이웃이 누르는 상태 버튼(1인 1개, 바꿀 수 있음): still 아직 있어요 · gone 치워졌어요 · worse 더 늘었어요
    marks: MARKS.reduce((o, k) => ({ ...o, [k]: Object.values(r.marks || {}).filter((v) => v === k).length }), {}),
    my_mark: (r.marks || {})[me.id] || null,
    // 공개 전(올리고 3분 안)이면 공개될 시각. 공개 전 제보는 올린 사람에게만 보입니다.
    pending_until: r.visible_at && new Date(r.visible_at).getTime() > Date.now() ? r.visible_at : null,
    lat: r.lat,
    lng: r.lng,
    address: r.address,
    spot: r.spot || '',
    dong: r.dong,
    photo_path: r.photo_path,
    status: r.status,
    is_promoted: false,
    like_count: r.likes.length,
    required_members: r.required_members,
    current_members: r.members.length,
    reward_xp: xp,
    reward_points: pointsOf(r),
    reward_crew_xp: r.required_members > 1 ? xp * 2 : 0, // 크루 의뢰는 크루 활동 경험치가 2배
    deadline_at: r.deadline_at,
    created_at: r.created_at,
    reporter_id: r.reporter_id,
    reporter_nickname: r.reporter_id === me.id ? me.nickname : r.reporter_nickname,
    distance_m: from ? meters(from, r) : null,
    liked_by_me: r.likes.includes(me.id),
    i_am_participating: r.members.includes(me.id),
  }
}

export async function getNearbyReports({ lat, lng, radiusM = 1500 }) {
  const db = await load()
  if (!db.partnerSeeded) {
    db.partnerSeeded = true
    db.reports.push({ ...PARTNER, id: db.nextId++, kind: 'partner', lat: lat + 0.0004, lng: lng + 0.0004, address: '내 위치 근처', dong: '', photo_path: null, status: 'open', likes: [], members: [], required_members: 1, deadline_at: null, created_at: new Date().toISOString(), reporter_id: 'partner', reporter_nickname: PARTNER.partner_name })
  }
  sweep(db)
  await save()
  return db.reports
    .filter((r) => !(db.user.flags || []).some((f) => f.report_id === r.id)) // 내가 신고한 제보는 내 목록에서 숨깁니다
    .filter((r) => r.reporter_id === db.user.id || !r.visible_at || new Date(r.visible_at).getTime() <= Date.now())
    .map((r) => view(r, db.user, { lat, lng }))
    .filter((r) => r.distance_m <= radiusM)
    .sort((a, b) => a.distance_m - b.distance_m)
}

async function find(id) {
  const db = await load()
  const r = db.reports.find((x) => x.id === id)
  if (!r) fail('REPORT_NOT_OPEN')
  return { db, r, me: db.user }
}

export async function toggleLike(id) {
  const { r, me } = await find(id)
  const on = r.likes.includes(me.id)
  let gained = 0
  // 한 번 누른 하트는 취소할 수 없습니다(눌렀다 떼기로 포인트·승격을 조작하지 못하게).
  if (on) fail('HEART_FINAL')
  {
    // 하루 10개까지.
    if (heartsToday(me) >= HEART_DAILY_LIMIT) fail('HEART_DAILY_LIMIT')
    r.likes = [...r.likes, me.id]
    ;(me.hearts = me.hearts || []).push({ id, at: new Date().toISOString() })
    // 같은 의뢰에는 처음 누를 때만 포인트를 줍니다.
    me.heartPaid = me.heartPaid || []
    if (!me.heartPaid.includes(id)) {
      me.heartPaid.push(id)
      me.points += HEART_GIVER_POINTS
      gained = HEART_GIVER_POINTS
    }
  }
  await save()
  return { liked: !on, like_count: r.likes.length, is_promoted: false, just_promoted: false, points_gained: gained, hearts_left: HEART_DAILY_LIMIT - heartsToday(me) }
}

export async function acceptReport(id) {
  const { r, me } = await find(id)
  if (r.status !== 'open') fail('REPORT_NOT_OPEN')
  if (r.visible_at && new Date(r.visible_at).getTime() > Date.now()) fail('REPORT_PENDING')
  // 내가 올린 제보는 내가 해결할 수 없습니다. 여럿이 하는 크루 의뢰는 올린 사람도 함께합니다.
  if (r.reporter_id === me.id && r.required_members <= 1) fail('OWN_REPORT')
  if (r.members.includes(me.id)) fail('ALREADY_JOINED')
  if (r.members.length >= r.required_members) fail('REPORT_FULL')
  r.members.push(me.id)
  r.accepted_at = { ...(r.accepted_at || {}), [me.id]: new Date().toISOString() }
  if (r.members.length >= r.required_members) {
    r.status = 'in_progress'
    r.deadline_at = new Date(Date.now() + DAY).toISOString()
  }
  await save()
  return { status: r.status, current_members: r.members.length, required_members: r.required_members, deadline_at: r.deadline_at }
}

export async function cancelParticipation(id) {
  const { r, me } = await find(id)
  if (!r.members.includes(me.id)) fail('NOT_PARTICIPATING')
  r.members = r.members.filter((u) => u !== me.id)
  if (r.status === 'in_progress') {
    r.status = 'open'
    r.deadline_at = null
  }
  await save()
}

const heartsToday = (me) => (me.hearts || []).filter((h) => kstDay(h.at) === kstDay(Date.now())).length
const donesToday = (me) => me.completed.filter((c) => kstDay(c.at) === kstDay(Date.now())).length
const levelOf = (xp) => Math.floor(xp / XP_PER_LEVEL) + 1

function streak(completed) {
  const weeks = new Set(completed.map((c) => kstWeek(c.at)))
  let w = kstWeek(Date.now())
  if (!weeks.has(w)) w -= 1 // 이번 주에 아직 안 했으면 지난주부터 셉니다
  let n = 0
  while (weeks.has(w)) {
    n += 1
    w -= 1
  }
  return n
}

export async function getMyProfile() {
  const db = await load()
  const me = db.user
  // 내가 해결한 의뢰 기록(최근 순). 완료된 의뢰는 지우지 않고 기록으로 남깁니다.
  const cleaned = [...me.completed].reverse().map((c) => {
    const r = db.reports.find((x) => x.id === c.id)
    return { id: c.id, at: c.at, issue_type: r?.issue_type || null, title: r?.title || '지워진 의뢰', place_label: r ? (PLACE[r.place_type] || PLACE.etc)[0] : null }
  })
  return {
    id: me.id,
    frame: frameOf(me),
    name_color: item(lookOf(me).name).colors[0],
    cleaned,
    avatar_url: me.avatar || null,
    title_key: me.title || null,
    // 최근 8주 동안 주마다 해결한 수(오래된 주부터). 내 정보의 활동 그래프에 씁니다.
    weekly: Array.from({ length: 8 }, (_, i) => {
      const w = kstWeek(Date.now()) - (7 - i)
      return me.completed.filter((c) => kstWeek(c.at) === w).length
    }),
    // 도전과제 계산에 쓰는 누적 값과 이미 보상을 받은 도전과제
    stats: statsRaw(db),
    feats_claimed: me.feats || [],
    nickname: me.nickname,
    xp: me.xp,
    points: me.points,
    level: levelOf(me.xp),
    xp_in_level: me.xp % XP_PER_LEVEL,
    xp_for_next_level: XP_PER_LEVEL,
    streak_weeks: streak(me.completed),
    active_this_week: me.completed.some((c) => kstWeek(c.at) === kstWeek(Date.now())),
    completed_count: me.completed.length,
    rewards: me.rewards || [],
    coupons: me.coupons || [],
    completes_today: donesToday(me),
    completes_limit: DAILY_LIMIT,
    hearts_today: heartsToday(me),
    hearts_limit: HEART_DAILY_LIMIT,
  }
}

const statsRaw = (db) => {
  const me = db.user
  const of = (key) => tally(me.completed.map((c) => db.reports.find((x) => x.id === c.id)?.[key]))
  return { completed: me.completed.length, hearts: (me.hearts || []).length, reports: db.reports.filter((r) => r.reporter_id === me.id).length, rewards: (me.rewards || []).length, places: of('place_type'), issues: of('issue_type') }
}

// 도전과제 보상 받기. 조건을 채웠는지 여기서 다시 확인하고 한 번만 줍니다. 보상: 포인트·XP, 일부는 꾸미기 품목.
export async function claimFeat(id) {
  const db = await load()
  const me = db.user
  const a = ACHIEVEMENTS.find((x) => x.id === id)
  if (!a) fail('FEAT_NOT_FOUND')
  me.feats = me.feats || []
  if (me.feats.includes(id)) fail('FEAT_CLAIMED')
  const s = statsOf({ stats: statsRaw(db), level: levelOf(me.xp), streak_weeks: streak(me.completed) }, (db.crews || []).find((c) => c.members.includes(me.id)))
  if (a.value(s) < a.goal) fail('FEAT_NOT_DONE')
  const was = levelOf(me.xp)
  me.feats.push(id)
  me.points += a.points
  me.xp += a.xp
  const gift = COSMETICS.find((c) => c.feat === id)
  if (gift) (me.cosmetics = me.cosmetics || []).push(gift.id)
  await save()
  return { points_gained: a.points, xp_gained: a.xp, cosmetic: gift ? gift.name : null, leveled_up: levelOf(me.xp) > was, level: levelOf(me.xp) }
}

const tally = (keys) => keys.filter(Boolean).reduce((m, k) => ((m[k] = (m[k] || 0) + 1), m), {})

// 프로필 사진. 웹은 작게 줄여 저장하고, 폰은 고른 사진의 파일 주소를 그대로 가리킵니다. null 이면 기본(닉네임 첫 글자).
export async function setAvatar(uri) {
  const db = await load()
  db.user.avatar = uri ? await keepPhoto(uri, 256) : null
  await save()
}

// 내가 고른 칭호. 'lv:3'(레벨 칭호) 또는 'ach:first'(도전과제 칭호). null 이면 칭호 없음(처음 상태).
export async function setTitle(key) {
  const db = await load()
  db.user.title = key || null
  await save()
}

export async function setNickname(nickname) {
  const db = await load()
  db.user.nickname = nickname
  await save()
}

// 사진은 촬영 결과 주소를 그대로 가리킵니다(웹은 data: 주소, 폰은 앱 캐시 파일).
export const photoUrl = (path) => path || null

export async function createReport(userId, { title, placeType, issueType, description, requiredMembers, shot, address, dong, spot }) {
  const db = await load()
  const photo = await keepPhoto(shot.uri)
  const id = db.nextId++
  db.reports.push({
    id,
    title,
    description,
    place_type: placeType,
    issue_type: issueType || 'litter',
    lat: shot.lat,
    lng: shot.lng,
    address,
    dong,
    spot: spot || '',
    photo_path: photo,
    status: 'open',
    likes: [],
    members: [],
    required_members: Math.max(1, requiredMembers || 1),
    deadline_at: null,
    created_at: new Date().toISOString(),
    visible_at: new Date(Date.now() + REPORT_DELAY_MS).toISOString(),
    reporter_id: userId,
    reporter_nickname: db.user.nickname,
  })
  const myCrew = db.crews.find((c) => c.members.includes(userId))
  if (myCrew && requiredMembers > 1) feed(myCrew, { type: 'quest', user: db.user.nickname, title })
  await save()
  return id
}

export async function submitProof(userId, id, before, after) {
  const { db, r, me } = await find(id)
  if (!r.members.includes(me.id)) fail('NOT_PARTICIPATING')
  if (r.status !== 'in_progress') fail('REPORT_NOT_IN_PROGRESS')
  if (r.deadline_at && new Date(r.deadline_at).getTime() < Date.now()) fail('DEADLINE_PASSED')
  if (donesToday(me) >= DAILY_LIMIT) fail('DAILY_LIMIT')
  if (meters(before, r) > PROOF_RADIUS_M || meters(after, r) > PROOF_RADIUS_M) fail('TOO_FAR')
  // 수락하기 전에 찍어 둔 사진은 받지 않습니다.
  const acceptedAt = r.accepted_at?.[me.id]
  if (acceptedAt && new Date(before.takenAt).getTime() < new Date(acceptedAt).getTime()) fail('INVALID_TIME')
  // 전·후 사진 인증은 "찍고 바로 완료"를 막습니다: 같은 사진 금지, 같은 자리, 최소 시간 간격, 거의 같은 장면 금지.
  if ((r.proof_mode || 'before_after') === 'before_after') {
    if (before.uri === after.uri) fail('DUPLICATE_PHOTO')
    if (meters(before, after) > PROOF_APART_M) fail('PHOTOS_TOO_FAR_APART')
    const gap = new Date(after.takenAt).getTime() - new Date(before.takenAt).getTime()
    if (!(gap >= 0)) fail('INVALID_TIME')
    if (gap < PROOF_MIN_GAP_MS) fail('TOO_FAST')
    if (await sameScene(before.uri, after.uri)) fail('NO_CHANGE')
  }

  const xp = (PLACE[r.place_type] || PLACE.etc)[1]
  const points = pointsOf(r)
  const was = levelOf(me.xp)
  me.xp += xp
  me.points += points
  if (r.reward_label) (me.rewards = me.rewards || []).push({ label: r.reward_label, from: r.partner_name, at: new Date().toISOString() })
  // 크루원이면 크루 활동 경험치가 쌓이고(크루 의뢰는 2배), 크루 방에 자동 알림이 올라갑니다.
  const crew = db.crews.find((c) => c.members.includes(me.id))
  const crewXp = crew ? xp * (r.required_members > 1 ? 2 : 1) : 0
  if (crew) {
    crew.score += crewXp
    crew.contrib = crew.contrib || {}
    crew.contrib[me.id] = (crew.contrib[me.id] || 0) + crewXp
    feed(crew, { type: 'complete', user: me.nickname, title: r.title, crew_xp: crewXp, points, is_crew_quest: r.required_members > 1 })
  }
  me.completed.push({ id, at: new Date().toISOString() })
  r.status = 'completed'
  r.deadline_at = null
  r.before_path = await keepPhoto(before.uri)
  r.after_path = await keepPhoto(after.uri)
  r.completed_at = new Date().toISOString()
  // 해결되면 제보한 사람과 하트를 누른 사람에게 알려 사진을 보고 확인하게 합니다(해결한 본인은 제외).
  const watchers = [...new Set([r.reporter_id, ...r.likes])].filter((u) => u && u !== me.id && u !== 'partner')
  db.notices = db.notices || []
  for (const u of watchers) db.notices.push({ id: db.nextId++, to: u, report_id: r.id, title: r.title, solver: me.nickname, before_path: r.before_path, after_path: r.after_path, single: r.proof_mode === 'single', at: r.completed_at, answer: null })
  await save()
  return { xp_gained: xp, points_gained: points, crew_xp_gained: crewXp, title: r.title, reward_label: r.reward_label || null, level: levelOf(me.xp), leveled_up: levelOf(me.xp) > was, xp: me.xp, points: me.points, streak_weeks: streak(me.completed) }
}

// ── 크루 ──────────────────────────────────────────────
// 한 사람은 크루 하나에만 가입합니다(docs/api.md 에서 아직 미정인 항목, 우선 이렇게 둠).
// 크루 방(feed)은 사람이 쓰는 채팅이 아니라 활동이 자동으로 올라오는 알림 기록입니다.
function feed(crew, event) {
  crew.feed = crew.feed || []
  crew.feed.push({ id: `${Date.now()}-${crew.feed.length}`, at: new Date().toISOString(), ...event })
  if (crew.feed.length > 100) crew.feed = crew.feed.slice(-100)
}

const crewView = (c, me, rank) => ({
  id: c.id,
  name: c.name,
  area: c.area,
  member_count: c.members.length,
  score: c.score,
  level: Math.floor(c.score / CREW_XP_PER_LEVEL) + 1,
  xp_in_level: c.score % CREW_XP_PER_LEVEL,
  xp_for_next_level: CREW_XP_PER_LEVEL,
  rank,
  is_mine: c.members.includes(me.id),
  is_owner: c.owner_id === me.id,
})

export async function getCrews() {
  const db = await load()
  return [...db.crews].sort((a, b) => b.score - a.score || a.id - b.id).map((c, i) => crewView(c, db.user, i + 1))
}

// 내 크루 상세: 크루원별 기여도와 활동 알림
export async function getMyCrew() {
  const db = await load()
  const me = db.user
  const ranked = [...db.crews].sort((a, b) => b.score - a.score || a.id - b.id)
  const c = ranked.find((x) => x.members.includes(me.id))
  if (!c) return null
  c.names = c.names || {}
  c.names[me.id] = me.nickname
  const members = c.members
    .map((id) => ({ id, nickname: c.names[id] || '크루원', contribution: (c.contrib || {})[id] || 0, is_me: id === me.id, is_owner: id === c.owner_id }))
    .sort((a, b) => b.contribution - a.contribution)
  return { ...crewView(c, me, ranked.indexOf(c) + 1), members, feed: [...(c.feed || [])].reverse() }
}

export async function createCrew({ name, area }) {
  const db = await load()
  if (levelOf(db.user.xp) < CREW_CREATE_LEVEL) fail('CREW_LEVEL_TOO_LOW')
  if (db.crews.some((c) => c.members.includes(db.user.id))) fail('ALREADY_IN_CREW')
  if (db.crews.some((c) => c.name === name)) fail('CREW_NAME_TAKEN')
  const id = (db.crews.reduce((m, c) => Math.max(m, c.id), 0) || 0) + 1
  const crew = { id, name, area, owner_id: db.user.id, members: [db.user.id], score: 0, contrib: {}, names: { [db.user.id]: db.user.nickname }, feed: [], created_at: new Date().toISOString() }
  feed(crew, { type: 'create', user: db.user.nickname })
  db.crews.push(crew)
  await save()
  return id
}

export async function joinCrew(id) {
  const db = await load()
  if (db.crews.some((c) => c.members.includes(db.user.id))) fail('ALREADY_IN_CREW')
  const c = db.crews.find((x) => x.id === id)
  if (!c) fail('CREW_NOT_FOUND')
  c.members.push(db.user.id)
  c.names = { ...(c.names || {}), [db.user.id]: db.user.nickname }
  feed(c, { type: 'join', user: db.user.nickname })
  await save()
}

// 마지막 크루원이 나가면 크루는 사라집니다.
export async function leaveCrew() {
  const db = await load()
  const c = db.crews.find((x) => x.members.includes(db.user.id))
  if (!c) fail('NOT_IN_CREW')
  c.members = c.members.filter((u) => u !== db.user.id)
  if (c.members.length === 0) db.crews = db.crews.filter((x) => x !== c)
  else {
    if (c.owner_id === db.user.id) c.owner_id = c.members[0]
    feed(c, { type: 'leave', user: db.user.nickname })
  }
  await save()
}

// ── 포인트 교환 상점 ──────────────────────────────────
export async function getShopItems() {
  return SHOP
}

export async function redeemItem(itemId) {
  const db = await load()
  const item = SHOP.find((x) => x.id === itemId)
  if (!item || db.user.points < item.cost) fail('NOT_ENOUGH_POINTS')
  db.user.points -= item.cost
  const code = `JQ-${Math.random().toString(36).slice(2, 6).toUpperCase()}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`
  ;(db.user.coupons = db.user.coupons || []).unshift({ name: item.name, code, at: new Date().toISOString() })
  await save()
  return { coupon_code: code, item: item.name, points: db.user.points }
}

// ── 프로필 꾸미기 ──────────────────────────────────────
export async function getCosmetics() {
  const { user: me } = await load()
  const owned = me.cosmetics || []
  const look = lookOf(me)
  const level = levelOf(me.xp)
  return COSMETICS.map((c) => ({
    ...c,
    // 포인트로 사는 품목은 산 뒤에, 레벨 품목은 레벨이 되면 내 것이 됩니다.
    owned: has(me, c),
    locked: level < c.level || (!!c.feat && !owned.includes(c.id)),
    equipped: look[c.kind] === c.id,
  }))
}

export async function buyCosmetic(id) {
  const db = await load()
  const me = db.user
  const c = COSMETICS.find((x) => x.id === id)
  if (!c) fail('COSMETIC_NOT_FOUND')
  if (levelOf(me.xp) < c.level || (c.feat && !has(me, c))) fail('LEVEL_TOO_LOW')
  me.cosmetics = me.cosmetics || []
  if (c.cost > 0 && !me.cosmetics.includes(id)) {
    if (me.points < c.cost) fail('NOT_ENOUGH_POINTS')
    me.points -= c.cost
    me.cosmetics.push(id)
  }
  me.look = { ...lookOf(me), [c.kind]: id } // 사면 바로 착용
  await save()
  return { points: me.points }
}

export async function equipCosmetic(id) {
  const db = await load()
  const me = db.user
  const c = COSMETICS.find((x) => x.id === id)
  if (!c) fail('COSMETIC_NOT_FOUND')
  const mine = has(me, c)
  if (!mine) fail('LEVEL_TOO_LOW')
  me.look = { ...lookOf(me), [c.kind]: id }
  await save()
}

// ── 상태 버튼 · 해결 확인 알림 · 신고 ───────────────────
export async function setMark(id, mark) {
  const { r, me } = await find(id)
  if (!MARKS.includes(mark)) fail('REPORT_NOT_OPEN')
  r.marks = r.marks || {}
  if (r.marks[me.id] === mark) delete r.marks[me.id] // 같은 걸 다시 누르면 해제
  else r.marks[me.id] = mark
  await save()
}

// 내가 제보했거나 하트를 누른 의뢰가 해결됐다는 알림. 사진을 보고 "치워졌어요 / 아직이에요"로 답합니다.
export async function getNotices() {
  const db = await load()
  return (db.notices || []).filter((n) => n.to === db.user.id).reverse()
}

export async function answerNotice(noticeId, answer) {
  const db = await load()
  const n = (db.notices || []).find((x) => x.id === noticeId && x.to === db.user.id)
  if (!n || n.answer) return
  n.answer = answer === 'ok' ? 'ok' : 'not'
  n.answered_at = new Date().toISOString()
  // "아직이에요"가 나오면 의뢰에 이의 표시를 남깁니다. 포인트 회수 같은 처리는 서버(운영진)가 정합니다.
  const r = db.reports.find((x) => x.id === n.report_id)
  if (r && n.answer === 'not') r.disputes = (r.disputes || 0) + 1
  await save()
}

export async function reportAbuse(id, reason) {
  const { me } = await find(id)
  me.flags = me.flags || []
  if (!me.flags.some((f) => f.report_id === id)) me.flags.push({ report_id: id, reason, at: new Date().toISOString() })
  await save()
}
