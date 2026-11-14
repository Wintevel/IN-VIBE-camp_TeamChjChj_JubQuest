# 테이블·API

프론트(한재준)와 백엔드(장연우)의 계약 문서입니다. 확정된 스키마의 기준은 `supabase/migrations/` 이고, 이 문서는 그것과 같게 유지합니다. `?` 표시는 아직 정해지지 않은 부분입니다.

프론트는 별도 서버 없이 `supabase-js` 로 호출합니다. 읽기는 대부분 RPC(화면에 맞춘 모양으로 반환), 쓰기는 단순한 것만 테이블 insert 이고 판정이 필요한 것은 전부 RPC 입니다. 승격·포인트·XP·하루 상한·위치 검증은 전부 서버가 결정합니다.

> 2026-11-14 갱신: `docs/backend-requests.md` 1~3번 반영(마이그레이션 `20261113194340`, `…194636`, `…194800`). 프론트 `src/api/remote.js` 는 아래 이름으로 다시 써야 합니다(예전 `toggle_like`, `submit_proof`, `photos` 버킷, `reward_items` 는 서버에 없습니다).

## MVP 범위
| 화면 | 백엔드 |
|---|---|
| 의뢰판 | `quests_nearby`, `reports_nearby`, `area_stats`(상단 띠) |
| 의뢰 상세 시트 | `quests_nearby` 행 그대로, 수락 `accept_quest` |
| 인증 | Storage `claim-photos` 업로드 → `approve_claim` |
| 제보하기 | Storage `report-photos` 업로드 → `reports` insert |
| 하트 | `give_heart` (또는 `report_hearts` insert). 취소 없음 |
| 동네 지도 | `map_overview` |
| 크루 랭킹 / 내 크루 / 크루 찾기 | `current_season`, `crew_ranking`, `my_crew`, `crews_to_join` |
| 크루 만들기·가입·탈퇴 | `create_crew`, `join_crew`, `leave_crew` |
| 크루 의뢰 올리기 | `quests` insert (`kind='crew'`, 크루원만) |
| 내 정보 | `my_profile`, `my_cleaned` |
| 상점 | `shop_items` 조회, `redeem_item` |
| 프로필 꾸미기 | `cosmetics_list`, `buy_cosmetic`, `equip_cosmetic` |
| 설정 | `profiles` update (nickname, avatar_url, home_area), 로그아웃 |
| 제휴업체 웹 | `partner_me`, `partner_register`, `partner_quests`, `partner_create_quest`, `partner_cancel_quest`, `partner_report` |
| 로그인 | 카카오·구글·이메일로 확정(2026-11-14). 익명 계정은 보기만 가능. 서버는 아직 익명 로그인이며 `docs/backend-requests.md` 2-12 에서 바꿉니다 |

**하트와 승격 표시 원칙**: 승격은 서버가 자동으로 처리하고, 앱은 승격이라는 말이나 기준을 보여주지 않습니다. 승격 기준값은 서버 내부(`app_settings`, 클라이언트 접근 불가)에만 있습니다. 승격된 제보는 의뢰(`kind='report'`)가 되고 라벨은 "주민 제보"로 내려갑니다.

## 확정 규칙
숫자 중 "임시"는 `app_settings` 에 있고 마이그레이션 한 줄로 바꿀 수 있습니다.

**제보**
- 올리고 **3분 뒤** 다른 사람에게 공개됩니다. 그 전에는 올린 사람에게만 `pending_until`(공개 시각)과 함께 보이고, 하트·수락 불가(`REPORT_PENDING`)
- 문제 유형 `issue_type`: `litter` 쓰레기 · `dumping` 무단 투기 · `bin` 넘친 쓰레기통 · `drain` 빗물받이 막힘 · `graffiti` 낙서 (기본 `litter`, 목록 임시)
- 필요 인원 `required_members`: 1(혼자) 또는 2 이상(여럿). 2 이상이면 크루 의뢰처럼 크루 XP 배수가 붙습니다
- 사진은 본인 폴더(`{user id}/…`)에 실제로 올라간 파일이어야 함(`INVALID_PHOTO`)

**하트·승격**
- 한 사람이 한 제보에 1번, **취소 없음**(클라이언트 delete 권한 없음). 앱도 되돌리기 없이 누르는 즉시 보냅니다(2026-11-14 변경)
- **하루 10개**(KST 0시 기준). 11번째는 `HEART_DAILY_LIMIT`
- 하트를 누른 사람은 **1점**(임시). 같은 제보에는 한 번만
- (5-2) 승격 문턱은 없습니다. 제보는 올리는 즉시 같은 위치에 `kind='report'` 의뢰가 되고, 3분 뒤 공개되면 수락할 수 있습니다. 그래서 `reports_nearby` 는 거의 비어 있고 주민 제보는 `quests_nearby` 에 나옵니다
- **제보자는 포인트를 받지 않습니다.** 제보를 치운 사람(해결자)만 **하트 3개마다 5점**(`floor(하트 수 / 3) × 5`, 최대 100점)을 받습니다. 하트 0~2개면 포인트 0, XP 만
- 본인 제보에는 하트 불가(`CANNOT_LIKE_OWN_REPORT`), 본인 제보는 본인이 해결 불가(`OWN_REPORT`). 단, 필요 인원 2명 이상인 의뢰는 올린 사람도 참여

**포인트와 XP**
- **포인트**: 상점·꾸미기에 쓰면 줄어드는 값(`points`). 받는 곳: 의뢰 해결, 하트 누르기
- **XP**: 쌓이기만 하는 값(`xp`). 의뢰를 해결하면 장소 유형별로 빗물받이 100 · 버스정류장 80 · 공원 150 · 골목·거리 80 · 기타 50 (임시)
- **개인 레벨** = XP 300마다 1레벨(임시). 칭호는 프론트가 레벨 숫자로 붙입니다
- 크루 만들기는 레벨 3부터(5-1, `CREW_LEVEL_TOO_LOW`). 가입은 제한 없음
- 의뢰 보상 포인트: 주민 제보 = floor(하트 수 / 3) × 5(최대 100), 제휴 = `reward_points`, 크루 의뢰 = 50(임시)

**크루**
- 1인 1크루(확정 대기 ?). 바로 가입(초대·승인 없음)
- 크루원이 의뢰를 해결하면 **크루 XP** = 그 의뢰의 XP. 크루 의뢰(`kind='crew'`)나 필요 인원 2명 이상 의뢰는 **2배**(임시)
- 크루 레벨 = 누적 크루 XP 500마다 1레벨(임시). 시즌 랭킹 점수 = 시즌 기간의 크루 XP 합
- 크루장이 나가면 가장 먼저 들어온 크루원이 크루장, 마지막 크루원이 나가면 크루가 사라짐
- 크루 활동 알림(`feed`)은 서버가 자동으로 남깁니다: 만들기·가입·탈퇴·크루 의뢰 올림·의뢰 완료

**수락·인증**
- 수락 후 24시간 안에 인증해야 하고, 지나면 자동 만료(5분마다 정리)
- 주민 제보·크루 의뢰는 **필요 인원이 다 모여야 인증 가능**(`REPORT_NOT_IN_PROGRESS`), 인원이 찼으면 추가 수락 거절(`REPORT_FULL`). 필요 인원만큼 완료되면 마감
- 제휴 의뢰는 마감일까지 여러 명이 각자 한 번씩 가능(인원 제한 없음)
- 인증 방식 `proof_mode`: `before_after`(치우기 전·후 두 장) / `single`(사진 한 장, 예: "망가진 벤치 사진 찍기"). `single` 은 `p_before_*` 만 보냅니다
- 검사를 통과하면 바로 승인하지 않고 **확인 대기(`submitted`)**. 포인트·XP 는 확인이 끝나야 지급됩니다(아래 "인증 확인")

## 악용 방지 규칙 (서버 `approve_claim` 에서 판정)
1. **하루 3개 상한**: 승인 기준, KST 0시. 같은 사용자의 인증 요청은 한 번에 하나씩 처리해서 동시에 보내도 3개를 넘지 않음 → `DAILY_LIMIT`
2. **카메라 촬영 + 위치 검증**
   - 사진이 모두 의뢰 위치에서 **100m 이내** → `TOO_FAR`
   - 전·후 촬영 위치끼리도 100m 이내 → `PHOTOS_TOO_FAR_APART`
   - 촬영 시각: 수락 이후, 전 ≤ 후, 미래 불가. 업로드 시각도 수락 이후 → `INVALID_TIME`
   - Android 모의 위치(`mocked`)면 거절 → `MOCK_LOCATION`
3. **사진 파일**: `claim-photos` 의 본인 폴더에 실제로 올라간 파일만 → `INVALID_PHOTO`
4. **사진 해시 중복**: 전·후 해시가 같거나, 다른 인증에서 쓴 해시면 거절 → `DUPLICATE_PHOTO`
5. **찍고 바로 완료 막기**
   - 치우기 전 사진과 후 사진의 **업로드 시각**(서버 기록)과 촬영 시각이 모두 **1분 이상**(임시) 차이 → `TOO_FAST`. 그래서 **치우기 전 사진은 찍자마자 업로드**해 주세요
   - 앱이 32×32 미리보기(`p_before_thumb`, `p_after_thumb`)를 보내면 평균 밝기 차이가 4 미만일 때 거절 → `NO_CHANGE`. 보내지 않으면 이 검사는 건너뜁니다

**한계**: 해시·촬영 위치·촬영 시각·`mocked`·미리보기는 앱이 보낸 값이라 조작된 앱이면 속일 수 있습니다. 서버가 직접 확인하는 것은 업로드 파일의 존재·폴더·업로드 시각, 거리 계산, 하루 상한입니다. 사진 내용을 서버가 직접 판별하는 것(Edge Function + 이미지 판별 모델)은 한재준 결정 대기입니다(`backend-requests.md` 3-6).

크루 의뢰처럼 위치가 없는 의뢰는 "의뢰 위치 반경"만 건너뛰고 나머지는 동일하게 검사합니다.

## 테이블
| 테이블 | 주요 컬럼 | 클라이언트 권한 |
|---|---|---|
| `profiles` | id(=auth.users.id), nickname, avatar_url, home_area, points(보유), total_earned(누적 획득), xp, frame_id, name_color_id, created_at | 전체 읽기, 본인 nickname·avatar_url·home_area 수정. 가입 시 자동 생성 |
| `reports` | id, author_id, title, description, category(`빗물받이`/`버스정류장`/`공원`/`골목·거리`/`기타`), issue_type, required_members, photo_url, lat, lng, address, status(`open`/`promoted`/`rejected`), heart_count, est_minutes, visible_at, is_demo, created_at | 전체 읽기, insert(title, description, category, issue_type, required_members, photo_url, lat, lng, address) |
| `report_hearts` | report_id, user_id, created_at | 전체 읽기, 본인 insert(report_id). delete 없음 |
| `quests` | id, kind(`partner`/`crew`/`report`), report_id, partner_id, crew_id, title, description, org_name, category, issue_type, lat, lng, address, est_minutes, time_label, goal, tools, reward_points, reward_text, reward_label, reward_value, reward_unit, proof_mode, proof_label, hot, required_members, starts_at, expires_at, status(`review`/`scheduled`/`open`/`done`/`expired`/`rejected`), is_demo, 제휴업체 입력값(place_name, reward_type, reward_amount, capacity, reject_reason, reviewed_at, created_by) | 전체 읽기(검토 중·반려는 그 업체만), 크루원만 `kind='crew'` insert. 앱 목록에는 `open` 만 나옴 |
| `quest_claims` | id, quest_id, user_id, status(`accepted`/`approved`/`cancelled`/`expired`), accepted_at, 전·후 photo_url/lat/lng/accuracy_m/taken_at/photo_hash, points_awarded, xp_awarded, crew_xp_awarded, reward_label, approved_at | 본인 것만 읽기. 쓰기는 RPC 로만 |
| `point_ledger` | id, user_id, amount(포인트 증감), xp, crew_id, crew_score(크루 XP), reason, quest_id, report_id, created_at | 본인 것만 읽기 |
| `partners` | id, name, logo_url, kind(`brand`/`gov`/`shop`/`org`), is_demo, manager_name, created_at | 전체 읽기(manager_name 제외) |
| `partner_members` | partner_id, user_id(유일 = 계정 하나에 업체 하나), role, created_at | 본인 것만 읽기. 등록은 `partner_register` |
| `crews` | id, name, area, owner_id, is_demo | 전체 읽기 |
| `crew_members` | crew_id, user_id(유일 = 1인 1크루), role(`owner`/`member`), joined_at | 전체 읽기, 본인 insert(crew_id)/delete (RPC 권장) |
| `crew_events` | id, crew_id, type(`create`/`join`/`leave`/`quest`/`complete`), nickname, title, crew_xp, points, is_crew_quest, created_at | 같은 크루원만 읽기 |
| `seasons` | id, label, period, note, starts_at, ends_at | 전체 읽기. 다음 시즌은 매일 자동 생성 |
| `shop_items` | id, name, cost, active, sort | 전체 읽기(active 만) |
| `coupons` | id, user_id, item_id, name, cost, code, created_at | 본인 것만 읽기 |
| `cosmetics` | id, kind(`frame`/`name`), name, style, colors, cost(0 이면 레벨로만), level, sort | 전체 읽기 |
| `user_cosmetics` | user_id, cosmetic_id, created_at | 본인 것만 읽기 |
| `consent_records` | id, user_id, items(jsonb), version, created_at | 본인 것만 읽기. 쓰기는 `save_consent` |
| `report_marks` | report_id, user_id, mark(`still`/`gone`/`worse`), updated_at | 본인 것만 읽기. 쓰기는 `set_mark` |
| `resolve_notices` | id, user_id(받는 사람), report_id, quest_id, title, solver, before_path, after_path, single, answer, answered_at | 본인 것만 읽기 |
| `report_flags` / `avatar_flags` | 대상, user_id, reason, status, created_at | 본인 것만 읽기 |
| `achievements` | id, metric, goal | 전체 읽기 |

`point_ledger.reason`: `heart_given`(하트 누름), `quest_approved`, `crew_quest`, `shop_redeem`·`cosmetic_buy`(amount 음수), `seed`. `report_promoted`·`report_heart` 는 예전 기록용입니다.

`is_demo`: `seed.sql` 에서 넣은 시연용 데이터(가짜 크루 점수 포함)는 `true` 입니다. 목록 RPC 가 같이 내려 주므로 화면에서 "예시" 표시를 하거나 숨길 수 있습니다.

Storage 버킷: `report-photos`, `claim-photos`, `avatars` (공개 읽기). 업로드 경로는 반드시 `{내 user id}/파일명`.

## 연결
```js
// frontend/.env
EXPO_PUBLIC_SUPABASE_URL=https://ziyycebeszrrwnhtpqmr.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=(백엔드 담당에게 받기, publishable/anon key)

// 앱 시작 시 세션이 없으면 익명 로그인 (대시보드에서 Anonymous sign-ins 켜 둠)
const { data: { session } } = await supabase.auth.getSession()
if (!session) await supabase.auth.signInAnonymously()
```
에러는 `error.message` 에 아래 코드 문자열로 옵니다. 코드 이름은 `frontend/src/api/errors.js` 와 맞췄습니다.

## API

### 의뢰판
```js
// 의뢰 목록 (제휴 / 내 크루 의뢰 / 승격된 주민 제보), 가까운 순
supabase.rpc('quests_nearby', { p_lat, p_lng, p_radius_m: 1500, p_kind: null }) // p_kind: 'partner'|'crew'|'report'|null
```
반환 행: `id` · `code`(Q-0012) · `kind` · `label`(제휴 의뢰/크루 의뢰/주민 제보) · `title` · `org` · `description` · `goal` · `tools` · `time_label` · `point`(해결 포인트) · `reward` · `hot` · `lat` · `lng` · `address` · `distance_m` · `dist`(320m/1.1km) · `near`(500m 이내) · `required_members` · `current_members` · `hearts`/`hearted`(report 만) · `my_status`(`accepted`/`approved`/…) · `my_claim_id`(수락 중인 내 claim) · `cleared`(내가 완료) · `status` · `expires_at` · `report_id`·`photo_url`(승격된 제보의 원래 사진, report 만) · `category` · `issue_type` · `is_mine`(내 제보에서 나온 의뢰) · `proof_mode` · `proof_label` · `reward_label`·`reward_value`·`reward_unit`(제휴 보상) · `reward_xp` · `reward_crew_xp`(내가 크루원일 때 받을 크루 XP, 아니면 0) · `is_demo`.
크루 의뢰는 내 크루 것만 내려옵니다. 내가 완료한 의뢰는 마감돼도 `cleared: true` 로 같이 내려옵니다. 승격된 제보에 하트를 더 누를 때는 `report_id` 를 씁니다.

```js
// 주민 제보 (아직 승격 안 된 것). 공개된 것 + 내 것(공개 전 포함)
supabase.rpc('reports_nearby', { p_lat, p_lng, p_radius_m: 1500 })
```
반환: `id` · `code`(R-0003) · `title` · `author` · `description` · `category` · `issue_type` · `photo_url` · `lat` · `lng` · `address` · `distance_m` · `dist` · `near` · `time_label` · `hearts` · `point`(지금 승격되면 해결 포인트) · `reward_xp` · `required_members` · `hearted` · `mine`(내 제보면 하트 버튼 숨기기) · `pending_until`(공개 전이면 공개 시각, 아니면 null) · `is_demo` · `created_at`.

```js
// 상단 띠
supabase.rpc('area_stats', { p_lat, p_lng, p_radius_m: 1500 })
// { open_quests, done_today, new_reports, ticker: '오늘 이 동네 의뢰 3건 · 완료 1건 · 새 제보 2건' }
```

### 하트
```js
const { data } = await supabase.rpc('give_heart', { p_report_id })
// { liked: true, like_count, points_gained, hearts_today, hearts_left }
// 에러: HEART_FINAL(이미 누름), HEART_DAILY_LIMIT, REPORT_PENDING, CANNOT_LIKE_OWN_REPORT, REPORT_NOT_OPEN
```
`from('report_hearts').insert({ report_id })` 도 같은 검사를 거칩니다(이미 누른 경우는 23505). 취소(delete)는 없습니다. 하트 5개째에 제보가 `reports_nearby` 에서 빠지고 `quests_nearby` 에 `kind='report'` 로 나타납니다.

### 제보하기
```js
const path = `${user.id}/${Date.now()}.jpg`
await supabase.storage.from('report-photos').upload(path, file, { contentType: 'image/jpeg' })
await supabase.from('reports').insert({
  title, category,                // category 는 장소 유형 한글 값 그대로
  issue_type,                     // 'litter'|'dumping'|'bin'|'drain'|'graffiti', 생략하면 litter
  required_members,               // 1 또는 2 이상, 생략하면 1
  photo_url: path, lat, lng,      // 촬영 위치
  address, description,           // 선택
  spot,                           // 선택, 30자: 위치 설명("○○편의점 앞 전봇대 밑"). 승격되면 의뢰에도 spot 으로 내려감
})
// 에러: INVALID_PHOTO (내 폴더에 올라간 파일이 아님)
```
올린 직후에는 나에게만 `pending_until` 과 함께 보이고, 3분 뒤 공개됩니다.

### 수락 / 인증
```js
const { data } = await supabase.rpc('accept_quest', { p_quest_id: quest.id })
// { claim_id, deadline_at, current_members, required_members, status: 'open'|'in_progress', daily_remaining }
// 에러: QUEST_CLOSED, REPORT_PENDING, OWN_REPORT, NOT_CREW_MEMBER, ALREADY_ACCEPTED, ALREADY_CLEARED, REPORT_FULL

await supabase.rpc('cancel_claim', { p_claim_id })
const { data: active } = await supabase.rpc('my_claims')     // 진행 중인 내 의뢰
const { data: left } = await supabase.rpc('my_daily_remaining') // 오늘 남은 인증 수(안내용)
```

```js
// 1) 치우기 전 사진: 찍자마자 업로드 (서버가 업로드 시각으로 TOO_FAST 를 판정)
await supabase.storage.from('claim-photos').upload(`${user.id}/${claimId}-before.jpg`, beforeFile)
// 2) 치운 뒤 사진: 1분 이상 지난 뒤 촬영·업로드
await supabase.storage.from('claim-photos').upload(`${user.id}/${claimId}-after.jpg`, afterFile)

const { data, error } = await supabase.rpc('approve_claim', {
  p_claim_id: claimId,
  p_before_photo_url, p_before_lat, p_before_lng, p_before_accuracy_m, p_before_taken_at, p_before_photo_hash,
  p_after_photo_url,  p_after_lat,  p_after_lng,  p_after_accuracy_m,  p_after_taken_at,  p_after_photo_hash,
  p_mocked: before.mocked || after.mocked,
  p_before_thumb, p_after_thumb,  // 선택: 32×32 RGB 픽셀(3072바이트)을 base64 로. 있으면 NO_CHANGE 검사
})
// single(사진 한 장) 의뢰는 p_before_* 와 p_mocked 만 보내면 됩니다.
// 성공(제출됨): { status: 'submitted'|'staff_review', title, points_pending, xp_pending, crew_xp_pending,
//                reward_label, voters, verify_deadline, daily_remaining }   ← 포인트는 아직 지급 전
// 실패: DAILY_LIMIT, REPORT_NOT_IN_PROGRESS, TOO_FAR, PHOTOS_TOO_FAR_APART, INVALID_TIME, TOO_FAST, NO_CHANGE,
//       MOCK_LOCATION, INVALID_PHOTO, DUPLICATE_PHOTO, MISSING_PROOF, CLAIM_EXPIRED, QUEST_CLOSED, CLAIM_NOT_ACTIVE
```
해시는 촬영 파일 내용의 SHA-256 입니다. 검사에서 실패해도 claim 은 `accepted` 로 남아서 다시 찍어 올릴 수 있습니다(만료 제외).

### 인증 확인 (2026-11-15 장연우 결정)
인증 상태: `accepted`(수락) → `submitted`(확인 대기) → `approved`(승인, 이때 포인트·XP·크루 XP 지급) 또는 `rejected`(반려, 의뢰는 다시 열림). 결론이 안 나면 `staff_review`(운영진 검토).

**주민 제보·크루 의뢰: 이웃 투표**
- 의뢰를 올린 사람 **50%** + 하트 누른 사람(크루 의뢰는 다른 크루원) **50% 를 똑같이 나눔**. 해결한 본인은 투표에서 빠집니다.
- "치워졌어요" 합계가 **60% 이상**이면 승인. 올린 사람이 "아직이에요"면 바로 반려. 남은 표를 다 받아도 60% 가 안 되면 반려.
- 올린 사람이 없거나 본인이 해결자면 나머지가 100% 를 나눕니다. 하트가 하나도 없으면 올린 사람 혼자 100%. 투표할 사람이 아무도 없으면 운영진 검토.
- 투표 대상은 인증을 제출한 순간 정해집니다. 48시간 안에 결론이 안 나면 운영진 검토.
- 투표는 아래 "해결 확인 알림"(`my_notices`, `answer_notice`) 그대로입니다.

**제휴 의뢰: 업체 담당자 확인** (업체가 현장에 1명 이상 파견)
```js
supabase.rpc('partner_claims')  // 업체 웹: [{ id, quest_id, title, user, before, after, single, lat, lng, submitted_at, deadline, status, reject_reason, decided_at }]
await supabase.rpc('partner_review_claim', { p_claim_id, p_approve: true, p_reason: null })  // 'approved'|'rejected'
```
업체 계정이 없는 의뢰(시드 등)는 바로 운영진 검토, 48시간 안에 판단이 없으면 운영진 검토입니다.

**하루 3개 상한**은 인증을 제출한 시점에 셉니다(확인 대기 포함). `my_claims` 는 수락 중·확인 대기·운영진 검토·최근 3일 반려를 내려 줍니다:
`{ claim_id, quest_id, title, kind, status, accepted_at, deadline_at, submitted_at, verify_deadline, ok_percent, voters, answered, reject_reason, points_pending, xp_pending, lat, lng, address }`.

운영진 결정: 대시보드 SQL 에디터에서 `select public.staff_review_claim(12, true);` / `select public.staff_review_claim(12, false, '사유');`. 목록은 `staff_attention` 의 `claim_review`.

### 로그인·가입 동의 (2-12, 2-13)
- 로그인 수단은 카카오·구글·이메일(Supabase Auth). 제공자 설정(클라이언트 ID 등)은 백엔드 담당이 대시보드에서 합니다.
- **익명(둘러보기) 계정**은 의뢰판·지도·랭킹 읽기만 됩니다. 제보·하트·상태 버튼·신고·수락·인증·크루 가입·크루 의뢰·상점·꾸미기 구매는 `LOGIN_REQUIRED`.
- **필수 동의**(만 14세 이상·이용약관·개인정보·위치정보)가 서버에 없는 계정도 같은 기능이 `CONSENT_REQUIRED`.
- 두 검사는 `app_settings.block_anonymous_writes`, `require_consent` 로 끌 수 있습니다(서버 설정, 백엔드 담당).
```js
await supabase.rpc('save_consent', { p_items: { age: true, terms: true, privacy: true, location: true, push: false }, p_version: '2026-11-14' })
// p_version 생략 시 서버의 현재 약관 버전. 필수 항목이 빠지면 CONSENT_REQUIRED. 반환은 my_consent 와 같음
await supabase.rpc('my_consent') // { items, version, at, current_version, ok } 또는 null(기록 없음)
```

### 상태 버튼 (2-14)
```js
const { data } = await supabase.rpc('set_mark', { p_report_id, p_mark: 'still' }) // 'still'|'gone'|'worse'
// { marks: { still, gone, worse }, my_mark }   같은 걸 다시 보내면 해제(my_mark: null)
```
`reports_nearby` 행과 `quests_nearby` 의 주민 제보 행에 `marks`, `my_mark` 가 같이 내려갑니다(승격된 의뢰는 원래 제보 기준). 포인트는 없습니다. `gone` 이 3개(임시) 모이면 운영진 목록(`staff_attention`)에 올라가고 디스코드 알림이 갑니다. 자동 종료는 하지 않습니다(결정 대기).

### 해결 확인 알림 (2-15)
주민 제보·크루 의뢰의 인증이 **제출되면** 투표할 사람(올린 사람, 하트 누른 사람 또는 크루원, 해결한 본인 제외)에게 알림이 하나씩 생깁니다. 답이 곧 투표입니다.
```js
supabase.rpc('my_notices')
// [{ id, claim_id, report_id, quest_id, title, solver, before_path, after_path, single,
//    role: 'author'|'heart'|'crew', weight(%), claim_status, at, answer: null|'ok'|'not', answered_at }]
// 사진 경로는 claim-photos 버킷 공개 경로
await supabase.rpc('answer_notice', { p_notice_id, p_answer: 'ok' })  // 'ok'(치워졌어요) | 'not'(아직이에요). 한 번만
// { id, answer, claim_status }   에러: NOTICE_NOT_FOUND(없거나 이미 답함)
```
집계 규칙은 위 "인증 확인". 이미 결론 난 인증에 늦게 답해도 결과는 바뀌지 않습니다. 푸시 알림은 없습니다(앱 안 목록만).

### 제보 신고·프로필 사진 신고 (2-16, 2-18)
```js
await supabase.rpc('flag_report', { p_report_id, p_reason: 'fake' }) // photo|fake|privacy|danger|etc. 같은 제보는 한 번만(두 번째는 조용히 무시)
await supabase.rpc('flag_avatar', { p_user_id, p_reason: 'photo' })  // photo|privacy|etc
```
신고한 사람의 목록(`reports_nearby`, `quests_nearby`)에서는 그 제보가 바로 빠집니다. 신고가 3건(임시) 모이면 제보는 모두에게서 숨겨지고(`hidden_at`), 프로필 사진은 기본으로 돌아갑니다. 새 신고마다 운영진 디스코드 알림이 갑니다.

### 내 정보 / 설정
```js
supabase.rpc('my_profile')
// { id, nickname, initial, avatar_url, home_area, frame: { id, style, colors }, name_color, joined_days,
//   points, total_earned, xp, level, xp_in_level, xp_for_next_level, crew,
//   hearts_today, hearts_limit, completes_today, completes_limit, daily_remaining,
//   title_key, weekly: [8개 숫자, 오래된 주부터], stats: { completed, hearts, reports, rewards, places: {drain: 2, ...}, issues: {litter: 1, ...} },
//   completed_count, streak_weeks, active_this_week,
//   cleaned: [{ id, at, title, place_label, issue_type }],   // 내가 치운 곳 최근 10건
//   rewards: [{ label, from, at }],                           // 받은 제휴 보상
//   coupons: [{ name, code, at }],                            // 상점 쿠폰
//   records: [[라벨, 값]] }
supabase.rpc('my_cleaned', { p_limit: 20, p_before: null }) // 치운 곳 더 보기 (p_before 에 마지막 at 을 넣으면 다음 쪽)
await supabase.from('profiles').update({ nickname, home_area }).eq('id', me)
await supabase.auth.signOut()
```

```js
// 2-18 프로필 사진: avatars 버킷 본인 폴더에 올린 뒤 경로를 저장 (다른 경로면 INVALID_PHOTO)
await supabase.storage.from('avatars').upload(`${user.id}/avatar.jpg`, file, { upsert: true })
await supabase.from('profiles').update({ avatar_url: `${user.id}/avatar.jpg` }).eq('id', me)  // null 이면 기본
// 2-18 칭호 고르기: 'lv:3'(레벨 3 이상, 레벨 칭호는 2부터) 또는 'ach:first'(도전과제 달성). null 이면 칭호 없음(5-4)
await supabase.rpc('set_title', { p_key: 'ach:first' })   // 에러: TITLE_LOCKED, INVALID_INPUT
```
```js
// 5-3 도전과제 보상 받기 (달성 여부는 서버가 판정)
await supabase.rpc('claim_feat', { p_id: 'ten' })
// { points_gained, xp_gained, cosmetic(받은 꾸미기 이름 또는 null), leveled_up, level }
// 에러: FEAT_NOT_FOUND, FEAT_CLAIMED, FEAT_NOT_DONE.  my_profile.feats_claimed = 받은 도전과제 id 배열
```
도전과제 보상 품목(`frame-ember`, `frame-month`, `name-rose`)은 상점에서 살 수 없고(`LEVEL_TOO_LOW`), `cosmetics_list` 에 `feat` 로 표시됩니다.
`stats.places` 의 키는 웹·앱 장소 키(`drain`/`bus_stop`/`park`/`street`/`etc`), `stats.issues` 는 문제 유형 키입니다. 도전과제 조건은 서버 `achievements` 테이블에도 같은 숫자로 있습니다(`frontend/src/lib/achievements.js` 를 바꾸면 같이 바꿔야 함).

### 상점
```js
const { data: items } = await supabase.from('shop_items').select('id, name, cost').order('sort')
const { data } = await supabase.rpc('redeem_item', { p_item_id })
// { coupon_code: 'JQ-AB12-CD34', item, points }   에러: NOT_ENOUGH_POINTS, ITEM_NOT_FOUND
```
실제 쿠폰 발급 연동은 없습니다. 차감은 `point_ledger` 에 `shop_redeem` 으로 남습니다.

### 프로필 꾸미기
```js
supabase.rpc('cosmetics_list')
// [{ id, kind: 'frame'|'name', name, style, colors, cost, level, owned, locked, equipped }]
await supabase.rpc('buy_cosmetic', { p_id })   // 사고 바로 착용. { points, frame, name_color }
await supabase.rpc('equip_cosmetic', { p_id }) // 가진 것 착용
// 에러: NOT_ENOUGH_POINTS, LEVEL_TOO_LOW, COSMETIC_NOT_FOUND
```
`cost > 0` 은 포인트로 사서 보유, `cost = 0` 은 레벨이 되면 보유(살 수 없음). 품목·가격은 `frontend/src/api/local.js` 의 `COSMETICS` 와 같습니다(임시). 크루원 목록(`my_crew.members`)에도 `frame`·`name_color` 가 내려갑니다.

### 크루
```js
supabase.rpc('current_season')  // { label:'SEASON 11', period, note, title:'시즌 종료까지 20일', ... }
supabase.rpc('crew_ranking')
// [{ rank, crew_id, name, area, meta:'용현동 · 5명', member_count, score(시즌 크루 XP),
//    level, xp_in_level, xp_for_next_level, mine, is_demo }]
supabase.rpc('my_crew')
// null 이면 미가입 화면. { id, name, area, rank, score, member_count, level, xp_in_level, xp_for_next_level,
//   is_owner, stats:[[라벨, 값] x3],
//   members: [{ id, nickname, contribution(크루 XP), is_me, is_owner, frame, name_color }],
//   feed: [{ id, type:'create'|'join'|'leave'|'quest'|'complete', user, title, crew_xp, points, is_crew_quest, at }] }
supabase.rpc('crews_to_join')   // [{ id, name, meta }]

await supabase.rpc('create_crew', { p_name, p_area })  // 만든 사람이 크루장. 크루 id 반환
await supabase.rpc('join_crew', { p_crew_id })
await supabase.rpc('leave_crew')
// 에러: CREW_NAME_TAKEN, ALREADY_IN_CREW, CREW_NOT_FOUND, NOT_IN_CREW, INVALID_NAME

await supabase.from('quests').insert({                 // 크루 의뢰 올리기 (크루원만)
  kind: 'crew', crew_id, title, address: 모임장소, required_members, // 2 이상
  time_label, starts_at, lat, lng, category,           // 선택
})
```

### 동네 지도
```js
supabase.rpc('map_overview', { p_lat, p_lng, p_radius_m: 1500 })
// { stats: [['38%','우리 동네 정화율'], ['14','우리 크루 구역'], ['6','새 제보']],
//   points: [{ type:'cleared'|'quest'|'hot_report', lat, lng, crew:'mine'|'other'|'none'|null }] }
```
범례 매핑: cleared+mine = 우리 크루, cleared+other = 다른 크루, quest = 의뢰 있음, hot_report = 제보 많음.

### 제휴업체 웹 (`web/`)
`web/src/api.js` 의 함수와 1:1 입니다. 로그인한 계정(지금은 익명도 가능) 하나가 업체 하나에 연결됩니다.
```js
supabase.rpc('partner_me')                                   // api.partner(): { id, name, manager, joined_at } 또는 null
supabase.rpc('partner_register', { p_name, p_manager })      // api.start(): 업체 등록 후 partner_me 와 같은 값. 이미 있으면 그대로 반환
supabase.auth.signOut()                                      // api.leave()
supabase.rpc('partner_quests')                               // api.quests(): 내 업체 의뢰 배열 (최근 순)
supabase.rpc('partner_create_quest', {                       // api.create(input): 검토 요청 → 만든 의뢰 반환
  p_title, p_description, p_place_type, p_place_name, p_address, // place_type: park|street|drain|bus_stop|etc
  p_proof_mode, p_reward_type, p_reward_amount, p_capacity,      // reward_type: voucher|coupon|point
  p_starts_on, p_ends_on,                                        // 'YYYY-MM-DD'
  p_lat, p_lng,                                                  // 선택. 있으면 앱 인증 시 100m 반경 검사
})
supabase.rpc('partner_cancel_quest', { p_quest_id })         // api.cancel(id): 검토 중인 것만
supabase.rpc('partner_report')                               // api.report()
// 에러: NOT_PARTNER, INVALID_NAME, INVALID_INPUT, CANNOT_CANCEL
```
- 의뢰 한 건의 모양은 `web/src/api.js` 의 예시와 같습니다: `id, title, description, place_type, place_name, address, proof_mode, reward_type, reward_amount, capacity, starts_on, ends_on, status, reject_reason, created_at, joined, completed, daily(이번 주 월~일 완료 수 7칸), sample`.
- `status` 는 웹 기준 네 가지(`review`/`open`/`done`/`rejected`)로 내려갑니다. 승인됐지만 시작일 전이면 `open`, 기간이 지나 만료되면 `done` 입니다.
- `partner_report` 는 `{ quests, joined, completed, paid, daily, byPlace: [[place_type, 완료 수]], rows, photos: [{ quest_id, title, before, after, at }] }` 입니다. 사진 경로는 `claim-photos` 버킷 공개 경로이고 화면에서 `getPublicUrl` 로 바꿉니다.
- 검토 흐름: 등록하면 `review` → 운영진 승인 시 시작일 전이면 `scheduled`(웹에는 `open`), 시작일이 되면 `open` 으로 앱 의뢰판에 올라감 → 기간이 끝나거나 인증 완료가 모집 인원에 닿으면 종료. 반려하면 `rejected` 와 `reject_reason`.
- 모집 인원(`capacity`)이 차면 앱에서 추가 수락이 `REPORT_FULL` 로 막힙니다.
- 보상: `voucher`·`coupon` 은 앱에 `reward_label`(예: "지역 상품권 3,000원")로 보이고 포인트는 0, `point` 는 그 금액만큼 에코포인트로 지급합니다. 실제 상품권 지급과 업체 정산은 운영진이 따로 합니다.
- 위치가 없는 의뢰는 앱 인증 시 "의뢰 위치 반경" 검사를 건너뜁니다. 웹에 지도 핀(위도·경도)을 붙이면 `p_lat`, `p_lng` 로 보내 주세요.

운영진 검토는 앱·웹에서 호출할 수 없고, Supabase 대시보드 SQL 에디터에서 합니다.
```sql
select * from public.partner_review_queue;                        -- 검토 대기 목록
select public.staff_review_quest(12, true);                       -- 승인
select public.staff_review_quest(12, false, '장소가 불분명해요');   -- 반려
```
검토 요청·업체 등록이 들어오면 운영진 디스코드로 알림이 갑니다. 웹훅 주소는 Supabase Vault 에 `discord_webhook_url` 이름으로 넣습니다(커밋하지 않음). 없으면 알림만 건너뜁니다.

## 시드 데이터
`supabase/seed.sql` 에 시연용 값(제휴 의뢰 3, 크루 의뢰 1, 주민 제보 3, 크루 5, 시즌 11)이 있고, 원격 DB 에는 사진 한 장 인증 예시(망가진 공원 벤치 사진 찍기, 충주사랑상품권 보상)도 있습니다. 모두 `is_demo = true` 입니다. 시연 좌표: lat 37.4520, lng 126.6560 (인하대 후문 근처). "인하대 후문 빗물받이 꽁초" 제보는 하트 1개만 더 받으면 승격됩니다.

## 프론트에 요청
- `remote.js` 를 이 문서의 RPC 이름으로 바꿔 주세요(위 2026-11-14 갱신 안내).
- 치우기 전 사진은 촬영 직후 바로 업로드해 주세요. 두 장을 마지막에 함께 올리면 `TOO_FAST` 입니다.
- 인증 시 사진 해시(SHA-256)를 같이 보내 주세요. 없으면 `MISSING_PROOF` 입니다. `NO_CHANGE` 검사를 쓰려면 32×32 미리보기도 보내 주세요(선택).
- 새 에러 코드 `INVALID_PHOTO`, `ITEM_NOT_FOUND`, `INVALID_NAME`, `ALREADY_ACCEPTED`, `QUEST_CLOSED`, `MOCK_LOCATION`, `MISSING_PROOF`, `CLAIM_EXPIRED` 문구가 `errors.js` 에 필요합니다.

## 프론트에 요청 (2-12 ~ 2-18)
- 서버에 연결하면 익명 계정은 쓰기 기능이 `LOGIN_REQUIRED` 입니다. 카카오·구글·이메일 로그인 화면과, 가입 동의 화면에서 `save_consent` 호출을 붙여 주세요(지금 동의는 기기에만 저장됨).
- 새 에러 코드 문구: `LOGIN_REQUIRED`, `CONSENT_REQUIRED`, `TITLE_LOCKED`, `NOTICE_NOT_FOUND`.
- 운영진용 목록은 대시보드 SQL 에디터에서 `select * from public.staff_attention;` (자동 숨김된 제보, 신고, "치워졌어요" 누적, 해결 이의, 프로필 사진 신고).

## 프론트에 요청 (제휴업체 웹)
- `web/src/api.js` 의 함수 안쪽을 위 RPC 로 바꿔 주세요. 웹에 Supabase 클라이언트와 로그인(지금은 익명도 됨, 업체 계정은 이메일 로그인 권장)이 필요합니다.

## 정해야 할 것
- (확정·서버 반영됨) 로그인은 카카오·구글·이메일, 익명 계정은 둘러보기만
- 1인 1크루 확정 여부 ? (지금 구현은 1인 1크루)
- 같은 위치 중복 제보 처리 ?
- 숫자 값(하트 1개당 해결 보상, 하트 누른 사람 포인트, XP·레벨 기준, 크루 의뢰 포인트, 상점·꾸미기 가격) ?
- 비 오는 날 배지 판정 방법 ?
