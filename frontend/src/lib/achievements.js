import { TITLES } from './format'

// 도전과제. 달성하면 보상(포인트·XP, 일부는 꾸미기 품목)을 받고, 이름을 칭호로 쓸 수 있습니다.
// 조건과 보상 숫자는 임시값입니다. 꾸미기 보상은 api/local.js 의 COSMETICS 에서 feat 로 연결합니다.
// value(s) 는 지금 값, goal 은 목표. s 는 프로필의 stats 에 level·streak·crew 를 더한 것(statsOf).
export const ACHIEVEMENTS = [
  { id: 'first', name: '첫 줍', desc: '의뢰를 처음 해결하기', goal: 1, points: 10, xp: 30, value: (s) => s.completed },
  { id: 'ten', name: '열 번 찍어 안 치워지는 길 없다', desc: '의뢰 10건 해결하기', goal: 10, points: 50, xp: 150, gift: '테두리 "열 번 찍은 불꽃"', value: (s) => s.completed },
  { id: 'thirty', name: '이쯤 되면 직업', desc: '의뢰 30건 해결하기', goal: 30, points: 150, xp: 400, value: (s) => s.completed },
  { id: 'heart10', name: '하트 인플루언서', desc: '하트 10개 누르기', goal: 10, points: 10, xp: 30, value: (s) => s.hearts },
  { id: 'heart50', name: '공감 능력 만렙', desc: '하트 50개 누르기', goal: 50, points: 30, xp: 100, value: (s) => s.hearts },
  { id: 'report1', name: '동네 파수꾼', desc: '제보를 처음 올리기', goal: 1, points: 10, xp: 30, value: (s) => s.reports },
  { id: 'report10', name: '프로 제보러', desc: '제보 10건 올리기', goal: 10, points: 30, xp: 100, value: (s) => s.reports },
  { id: 'streak2', name: '작심삼일 탈출', desc: '2주 연속 활동하기', goal: 2, points: 20, xp: 60, value: (s) => s.streak },
  { id: 'streak4', name: '한 달째 출근 중', desc: '4주 연속 활동하기', goal: 4, points: 50, xp: 150, gift: '테두리 "개근상 리본"', value: (s) => s.streak },
  { id: 'crew', name: '혼자가 아니야', desc: '크루에 들어가기', goal: 1, points: 10, xp: 30, value: (s) => (s.crew ? 1 : 0) },
  { id: 'places', name: '동네 한 바퀴', desc: '모든 장소 종류에서 한 번씩 해결하기', goal: 5, points: 50, xp: 150, gift: '닉네임 색 "장미 닉네임"', value: (s) => Object.keys(s.places).length },
  { id: 'issues', name: '편식 없는 집게', desc: '모든 문제 유형을 한 번씩 해결하기', goal: 5, points: 50, xp: 150, value: (s) => Object.keys(s.issues).length },
  { id: 'reward', name: '상품권 사냥꾼', desc: '제휴 보상을 처음 받기', goal: 1, points: 10, xp: 30, value: (s) => s.rewards },
]

const EMPTY = { completed: 0, hearts: 0, reports: 0, rewards: 0, places: {}, issues: {} }
export const statsOf = (profile, myCrew) => ({ ...EMPTY, ...(profile?.stats || {}), level: profile?.level || 1, streak: profile?.streak_weeks || 0, crew: !!myCrew })

// 도전과제마다 지금 값, 달성 여부, 보상 수령 여부
export const progress = (s, claimed = []) => ACHIEVEMENTS.map((a) => ({ ...a, now: Math.min(a.goal, a.value(s)), done: a.value(s) >= a.goal, claimed: claimed.includes(a.id) }))

// 고를 수 있는 칭호. 처음에는 아무것도 열려 있지 않습니다.
// 레벨 2부터 레벨 칭호가, 도전과제를 달성하면 그 이름이 열립니다. 잠긴 것도 조건과 함께 보여 줍니다.
export function titleOptions(s) {
  const levels = [...TITLES]
    .reverse()
    .filter(([min]) => min >= 2)
    .map(([min, label]) => ({ key: `lv:${min}`, label, open: s.level >= min, how: `레벨 ${min}이 되면 열려요` }))
  const feats = progress(s).map((a) => ({ key: `ach:${a.id}`, label: a.name, open: a.done, how: `도전과제: ${a.desc}` }))
  return [...levels, ...feats]
}
// 화면에 보일 칭호. 고르지 않았거나 더는 쓸 수 없으면 빈 문자열(칭호 없음).
export function titleText(profile, myCrew) {
  const s = statsOf(profile, myCrew)
  const picked = profile?.title_key && titleOptions(s).find((t) => t.key === profile.title_key && t.open)
  return picked ? picked.label : ''
}
