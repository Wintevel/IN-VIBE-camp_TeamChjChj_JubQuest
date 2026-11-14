import { useState } from 'react'
import { StyleSheet, Text, View } from 'react-native'
import Button from '../components/Button'
import { PointIcon, XpIcon } from '../components/Icons'
import { Card } from '../components/ListRows'
import { Appear, Bar } from '../components/Motion'
import Screen from '../components/Screen'
import ScreenHeader from '../components/ScreenHeader'
import Toast from '../components/Toast'
import { progress, statsOf } from '../lib/achievements'
import { useApp } from '../state/AppState'
import { colors, radius, text } from '../theme'

// 도전과제. 달성하면 포인트·XP(가끔 꾸미기 품목)를 받고, 이름을 칭호로 쓸 수 있습니다. 포인트(노랑)와 구분되게 보라색을 씁니다.
export default function CollectionScreen({ navigation }) {
  const app = useApp()
  const [busy, setBusy] = useState(null)
  const feats = progress(statsOf(app.profile, app.myCrew), app.profile?.feats_claimed)
  const rank = (a) => (a.done && !a.claimed ? 0 : a.claimed ? 2 : 1)
  // 받을 보상이 있는 것을 맨 위로, 그다음 진행 중(많이 된 순), 받은 것은 아래로
  const sorted = [...feats].sort((a, b) => rank(a) - rank(b) || b.now / b.goal - a.now / a.goal)
  const claim = async (a) => {
    setBusy(a.id)
    await app.claimFeat(a)
    setBusy(null)
  }

  return (
    <View style={{ flex: 1 }}>
      <Screen>
        <ScreenHeader title="도전과제" sub={`${feats.filter((a) => a.done).length}/${feats.length} 달성 · 달성한 이름은 칭호로 쓸 수 있어요`} action="닫기" onAction={() => navigation.goBack()} />
        {sorted.map((a, i) => (
          <Appear key={a.id} index={i}>
            <Card style={[styles.feat, a.done && !a.claimed && { borderColor: colors.purple, backgroundColor: 'rgba(169,124,255,0.10)' }]}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
                <View style={[styles.medal, a.done && { backgroundColor: colors.purple }]}>
                  <Text style={[text.num, { color: a.done ? colors.ink : colors.disabled }]}>{a.done ? '✓' : '?'}</Text>
                </View>
                <View style={{ flex: 1, gap: 3 }}>
                  <Text style={[text.section, !a.done && { color: colors.sub }]}>{a.name}</Text>
                  <Text style={text.caption}>{a.desc}</Text>
                </View>
                {a.claimed ? (
                  <Text style={[text.caption, { color: colors.purple }]}>받음</Text>
                ) : a.done ? (
                  <Button compact disabled={busy === a.id} onPress={() => claim(a)} style={{ backgroundColor: colors.purple }}>
                    {busy === a.id ? '받는 중…' : '보상 받기'}
                  </Button>
                ) : null}
              </View>
              {a.done ? null : (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                  <Bar ratio={a.now / a.goal} color={colors.purple} track={colors.panel2} style={{ flex: 1 }} />
                  <Text style={text.caption}>
                    {a.now}/{a.goal}
                  </Text>
                </View>
              )}
              <View style={[styles.rewards, a.claimed && { opacity: 0.45 }]}>
                <Text style={text.caption}>보상</Text>
                <View style={styles.reward}>
                  <PointIcon size={14} />
                  <Text style={[text.chip, { color: colors.tape }]}>{a.points}</Text>
                </View>
                <View style={styles.reward}>
                  <XpIcon size={14} />
                  <Text style={[text.chip, { color: colors.blue }]}>{a.xp}XP</Text>
                </View>
                {a.gift ? (
                  <View style={[styles.reward, { backgroundColor: 'rgba(169,124,255,0.18)' }]}>
                    <Text style={[text.chip, { color: colors.purple }]}>{a.gift}</Text>
                  </View>
                ) : null}
              </View>
            </Card>
          </Appear>
        ))}
        {app.localMode ? <Text style={text.caption}>조건과 보상 숫자는 예시예요.</Text> : null}
      </Screen>
      <Toast />
    </View>
  )
}

const styles = StyleSheet.create({
  feat: { gap: 10, padding: 12 },
  medal: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.panel2, alignItems: 'center', justifyContent: 'center' },
  rewards: { flexDirection: 'row', alignItems: 'center', gap: 6, flexWrap: 'wrap' },
  reward: { flexDirection: 'row', alignItems: 'center', gap: 4, backgroundColor: colors.panel2, paddingHorizontal: 8, paddingVertical: 4, borderRadius: radius.pill },
})
