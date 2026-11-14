import { StyleSheet, Text, View } from 'react-native'
import AvatarFrame from '../components/AvatarFrame'
import { Card } from '../components/ListRows'
import { Appear, PressScale } from '../components/Motion'
import Screen from '../components/Screen'
import ScreenHeader from '../components/ScreenHeader'
import Toast from '../components/Toast'
import { titleText } from '../lib/achievements'
import { useApp } from '../state/AppState'
import { colors, radius, text } from '../theme'

// 프로필 꾸미기: 지금 적용된 네 가지(프로필 사진, 테두리, 칭호, 닉네임 색)를 보여 주고, 누르면 고르는 화면으로 갑니다.
export default function StyleScreen({ navigation }) {
  const app = useApp()
  const p = app.profile || {}
  const letter = (p.nickname || '줍').slice(0, 1)
  const title = titleText(p, app.myCrew)
  const worn = (kind) => app.cosmetics.find((c) => c.kind === kind && c.equipped)
  const tiles = [
    ['photo', '프로필 사진', p.avatar_url ? '내 사진' : '기본', <AvatarFrame key="p" frame={{ style: 'plain', colors: [colors.line] }} size={64} letter={letter} uri={p.avatar_url} letterColor={colors.sub} />],
    ['frame', '테두리', worn('frame')?.name || '기본', <AvatarFrame key="f" frame={p.frame} size={64} letter="" />],
    ['title', '칭호', title || '착용 안 함', <Text key="t" numberOfLines={2} style={[text.section, { textAlign: 'center', color: title ? colors.tape : colors.disabled }]}>{title || '없음'}</Text>],
    ['name', '닉네임 색', worn('name')?.name || '기본', <Text key="n" numberOfLines={1} style={[text.cardTitle, { fontSize: 20, color: p.name_color || colors.fg }]}>{p.nickname}</Text>],
  ]
  return (
    <View style={{ flex: 1 }}>
      <Screen>
        <ScreenHeader title="프로필 꾸미기" sub="바꿀 항목을 눌러 주세요" action="닫기" onAction={() => navigation.goBack()} />
        <Card style={styles.preview}>
          <AvatarFrame frame={p.frame} size={84} letter={letter} uri={p.avatar_url} />
          <View style={{ flex: 1, gap: 4 }}>
            <Text style={[text.cardTitle, { fontSize: 20 }, p.name_color && { color: p.name_color }]}>{p.nickname}</Text>
            {title ? <Text style={[text.chip, { color: colors.tape }]}>{title}</Text> : <Text style={text.caption}>칭호 없음</Text>}
          </View>
        </Card>
        <View style={styles.grid}>
          {tiles.map(([kind, label, now, art], i) => (
            <Appear key={kind} index={i} from="bottom" style={styles.slot}>
            <PressScale onPress={() => navigation.navigate('StylePick', { kind })} accessibilityRole="button" accessibilityLabel={`${label} 바꾸기, 지금 ${now}`} style={styles.tile}>
              <View style={styles.art}>{art}</View>
              <Text style={text.section}>{label}</Text>
              <Text numberOfLines={1} style={text.caption}>
                {now}
              </Text>
            </PressScale>
            </Appear>
          ))}
        </View>
      </Screen>
      <Toast />
    </View>
  )
}

const styles = StyleSheet.create({
  preview: { flexDirection: 'row', alignItems: 'center', gap: 22, paddingLeft: 26, paddingVertical: 22 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  slot: { width: '48%', flexGrow: 1 },
  tile: { alignItems: 'center', gap: 4, padding: 14, borderRadius: radius.lg, backgroundColor: colors.panel, borderWidth: 1, borderColor: colors.line },
  art: { height: 96, alignSelf: 'stretch', alignItems: 'center', justifyContent: 'center' },
})
