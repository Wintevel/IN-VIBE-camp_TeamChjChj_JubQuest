import { useEffect, useRef, useState } from 'react'
import { Animated, StyleSheet, Text, View } from 'react-native'
import * as ImagePicker from 'expo-image-picker'
import AvatarFrame from '../components/AvatarFrame'
import Button from '../components/Button'
import { LockIcon, PointIcon } from '../components/Icons'
import { Appear, ND, PressScale, reduced } from '../components/Motion'
import { Card, SectionTitle } from '../components/ListRows'
import Screen from '../components/Screen'
import ScreenHeader from '../components/ScreenHeader'
import Toast from '../components/Toast'
import { ACHIEVEMENTS, statsOf, titleOptions, titleText } from '../lib/achievements'
import { useApp } from '../state/AppState'
import { colors, radius, text } from '../theme'

const NAMES = { photo: '프로필 사진', frame: '테두리', title: '칭호', name: '닉네임 색' }

// 꾸미기 한 종류를 고르는 화면. 위에는 착용했을 때 모습, 아래에는 내 것과 잠긴 것을 나눠 보여 줍니다.
// 칸을 누르면 미리보기만 바뀌고, 아래 버튼을 눌러야 적용(또는 구매)됩니다.
export default function StylePickScreen({ navigation, route }) {
  const kind = route.params?.kind || 'frame'
  const app = useApp()
  const p = app.profile || {}
  const points = p.points || 0
  const letter = (p.nickname || '줍').slice(0, 1)
  const [busy, setBusy] = useState(false)
  const [picked, setPicked] = useState(null) // 고른 칸의 key
  const [photo, setPhoto] = useState(undefined) // 갤러리에서 새로 고른 사진

  // 종류마다 칸 목록을 같은 모양으로 만듭니다: { key, label, open, on, how, cost, item }
  let cells = []
  if (kind === 'title') {
    const now = titleText(p, app.myCrew)
    cells = [{ key: 'none', label: '착용 안 함', open: true, on: !now, how: '칭호를 보이지 않아요', value: null }, ...titleOptions(statsOf(p, app.myCrew)).map((t) => ({ key: t.key, label: t.label, open: t.open, on: t.label === now, how: t.open ? '열린 칭호예요' : t.how, value: t.key }))]
  } else if (kind === 'photo') {
    cells = [
      { key: 'none', label: '기본', open: true, on: !p.avatar_url, how: '닉네임 첫 글자를 보여 줘요' },
      ...(p.avatar_url ? [{ key: 'mine', label: '지금 사진', open: true, on: true, how: '지금 쓰는 사진이에요' }] : []),
      { key: 'pick', label: '갤러리에서 고르기', open: true, on: false, how: photo ? '고른 사진이에요. 적용을 눌러 주세요' : '폰에 있는 사진을 골라요' },
    ]
  } else {
    cells = app.cosmetics
      .filter((c) => c.kind === kind)
      .map((c) => {
        const feat = c.feat && ACHIEVEMENTS.find((a) => a.id === c.feat)
        const how = c.owned ? '가지고 있어요' : feat ? `도전과제 "${feat.name}" 보상` : c.locked ? `레벨 ${c.level}이 되면 열려요` : `${c.cost.toLocaleString()} 포인트로 살 수 있어요`
        return { key: c.id, label: c.name, open: c.owned, on: c.equipped, how, cost: !c.owned && !c.locked && c.cost > 0 ? c.cost : 0, item: c }
      })
  }
  const sel = cells.find((c) => c.key === picked) || cells.find((c) => c.on) || cells[0]
  const mine = cells.filter((c) => c.open)
  const locked = cells.filter((c) => !c.open)

  // 미리보기: 고른 칸을 입혀 본 모습
  const frame = kind === 'frame' ? sel.item : p.frame
  const nameColor = kind === 'name' ? sel.item.colors[0] : p.name_color
  const title = kind === 'title' ? (sel.value ? sel.label : '') : titleText(p, app.myCrew)
  const uri = kind === 'photo' ? (sel.key === 'pick' ? photo : sel.key === 'none' ? null : p.avatar_url) : p.avatar_url

  const pick = async (c) => {
    setPicked(c.key)
    if (c.key !== 'pick') return
    try {
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: true, aspect: [1, 1], quality: 0.5 })
      if (!res.canceled && res.assets?.[0]?.uri) setPhoto(res.assets[0].uri)
    } catch {
      app.showToast('사진을 불러오지 못했어요. 사진 접근 권한을 확인해 주세요')
    }
  }

  const short = sel.cost > points
  const can = kind === 'photo' ? (sel.key === 'pick' ? !!photo : !sel.on) : sel.cost ? !short : sel.open && !sel.on
  const label = sel.on && sel.key !== 'pick' ? '적용 중' : sel.cost ? (short ? `${(sel.cost - points).toLocaleString()} 포인트 부족` : `${sel.cost.toLocaleString()} 포인트로 구매`) : !sel.open ? '잠겨 있어요' : '적용'
  const apply = async () => {
    setBusy(true)
    const ok = kind === 'title' ? await app.saveTitle(sel.value, sel.label) : kind === 'photo' ? await app.saveAvatar(sel.key === 'pick' ? photo : null) : await app.wearCosmetic(sel.item)
    setBusy(false)
    if (ok) navigation.goBack()
  }

  // 칸을 바꿀 때마다 미리보기가 살짝 커졌다 돌아옵니다.
  const pop = useRef(new Animated.Value(1)).current
  useEffect(() => {
    if (reduced() || picked == null) return
    pop.setValue(0.86)
    Animated.spring(pop, { toValue: 1, speed: 18, bounciness: 14, useNativeDriver: ND }).start()
  }, [picked, photo, pop])

  const Cell = (c, i) => {
    const active = c.key === sel.key
    return (
      <Appear key={c.key} index={i} from="bottom" style={kind === 'title' ? styles.slotWide : styles.slot}>
      <PressScale onPress={() => pick(c)} accessibilityRole="button" accessibilityState={{ selected: active }} accessibilityLabel={`${c.label}${c.open ? '' : ', 잠김'}${c.on ? ', 적용 중' : ''}`} style={[styles.cell, kind === 'title' && styles.cellWide, active && styles.cellOn, !c.open && kind !== 'title' && { opacity: 0.6 }]}>
        {kind === 'frame' ? (
          <AvatarFrame frame={c.item} size={48} letter="" />
        ) : kind === 'name' ? (
          <Text style={[text.title, { color: c.item.colors[0] }]}>가</Text>
        ) : kind === 'photo' ? (
          c.key === 'pick' && !photo ? (
            <Text style={[text.h1, { color: colors.sub }]}>＋</Text>
          ) : (
            <AvatarFrame frame={{ style: 'plain', colors: [colors.line] }} size={48} letter={letter} letterColor={colors.sub} uri={c.key === 'pick' ? photo : c.key === 'mine' ? p.avatar_url : null} />
          )
        ) : null}
        <Text numberOfLines={2} style={[text.chip, { textAlign: 'center', color: c.open ? colors.fg : colors.sub }, kind === 'title' && !c.open && { paddingHorizontal: 14 }]}>
          {c.label}
        </Text>
        {c.on ? <Text style={styles.badge}>적용 중</Text> : null}
        {!c.open ? (
          c.cost ? (
            <Text style={[styles.badge, styles.lock]}>{c.cost}P</Text>
          ) : (
            <View style={styles.lockDot}>
              <LockIcon size={12} />
            </View>
          )
        ) : null}
      </PressScale>
      </Appear>
    )
  }

  return (
    <View style={{ flex: 1 }}>
      <Screen bottomPad={110}>
        <ScreenHeader title={NAMES[kind]} action="닫기" onAction={() => navigation.goBack()} />
        <Card style={styles.preview}>
          <Animated.View style={{ alignItems: 'center', transform: [{ scale: pop }] }}>
            <AvatarFrame frame={frame} size={96} letter={letter} uri={uri} />
            <Text style={[text.cardTitle, { fontSize: 20, marginTop: 14 }, nameColor && { color: nameColor }]}>
              {p.nickname}
              {title ? <Text style={[text.chip, { color: colors.tape }]}> · {title}</Text> : null}
            </Text>
          </Animated.View>
          <View style={styles.info}>
            <Text style={text.section}>{sel.label}</Text>
            <Text style={text.caption}>{sel.how}</Text>
          </View>
        </Card>

        <SectionTitle>내 것</SectionTitle>
        <View style={styles.grid}>{mine.map(Cell)}</View>
        {locked.length > 0 ? (
          <>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <SectionTitle>잠긴 것</SectionTitle>
              {kind !== 'title' ? (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5 }}>
                  <PointIcon size={14} />
                  <Text style={text.caption}>내 포인트 {points.toLocaleString()}</Text>
                </View>
              ) : null}
            </View>
            <View style={styles.grid}>{locked.map(Cell)}</View>
          </>
        ) : null}
        {kind === 'photo' ? <Text style={text.caption}>사진은 다른 이웃에게도 보여요. 얼굴이 나온 사진은 신중하게 골라 주세요.</Text> : null}
      </Screen>
      <View style={styles.bar}>
        <Button type="ghost" onPress={() => navigation.goBack()}>
          취소
        </Button>
        <Button disabled={!can || busy} onPress={apply} style={{ flex: 2 }}>
          {busy ? '적용하는 중…' : label}
        </Button>
      </View>
      <Toast />
    </View>
  )
}

const styles = StyleSheet.create({
  preview: { alignItems: 'center', paddingTop: 30, paddingBottom: 14 },
  info: { alignSelf: 'stretch', marginTop: 16, gap: 2, padding: 12, borderRadius: radius.md, backgroundColor: colors.panel2 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  slot: { width: '31.5%' },
  slotWide: { width: '48.5%' },
  cell: { minHeight: 112, alignItems: 'center', justifyContent: 'center', gap: 8, padding: 10, borderRadius: radius.cardSm, backgroundColor: colors.panel, borderWidth: 1.5, borderColor: colors.line },
  cellWide: { minHeight: 64 },
  cellOn: { borderColor: colors.blue, backgroundColor: colors.blueWeak },
  badge: { position: 'absolute', top: 6, right: 6, fontSize: 10, lineHeight: 14, color: colors.tapeInk, backgroundColor: colors.tape, paddingHorizontal: 6, borderRadius: radius.pill, overflow: 'hidden', fontWeight: '700' },
  lockDot: { position: 'absolute', top: 6, right: 6, width: 20, height: 20, borderRadius: 10, backgroundColor: colors.disabled, alignItems: 'center', justifyContent: 'center' },
  lock: { color: colors.fg, backgroundColor: colors.disabled },
  bar: { position: 'absolute', left: 0, right: 0, bottom: 0, flexDirection: 'row', gap: 8, padding: 16, paddingBottom: 24, backgroundColor: colors.ink, borderTopWidth: 1, borderTopColor: colors.line },
})
