# supabase

백엔드(DB·인증·스토리지) 설정 자리입니다. 담당: 백엔드 팀원.

## 규칙
- 테이블 변경은 대시보드에서 직접 고치지 말고 `migrations/` 의 SQL 파일로 남깁니다. 그래야 프론트가 같은 스키마를 로컬에서 재현할 수 있습니다.
- 파일 이름은 `YYYYMMDDHHMMSS_설명.sql` (Supabase CLI 규칙, 예: `20261112000000_create_reports.sql`).
- 모든 테이블에 RLS(행 수준 보안)를 켭니다. 프론트에 노출되는 anon key 는 공개 키라서 RLS 가 유일한 방어선입니다.
- `service_role` 키와 DB 비밀번호는 절대 커밋하지 않습니다. 필요하면 `.env` 로만 공유합니다.

## Supabase CLI 시작 (선택)
```bash
npm i -D supabase        # 또는 npx supabase
npx supabase init        # supabase/config.toml 생성
npx supabase link --project-ref <프로젝트 ref>
npx supabase db push     # migrations/ 를 원격에 적용
```

테이블·API 는 [`../docs/api.md`](../docs/api.md) 에 있습니다. 이 폴더의 마이그레이션이 기준입니다.

## 현재 상태
- 원격 프로젝트 ref: `ziyycebeszrrwnhtpqmr` (IN:VIBE CAMP). `migrations/` 의 파일이 원격에 적용돼 있고, 파일 이름의 버전이 원격 마이그레이션 기록과 같습니다.
  - `20261111…`: 처음 스키마·함수 (PR #5)
  - `20261113194340_requests_schema`, `…194636_requests_functions`, `…194800_requests_data`: `docs/backend-requests.md` 1~3번 반영 (2026-11-14)
  - `20261114101545_partner_web`, `…101618_partner_web_description_fix`: 제휴업체 웹 연결 (2-17)
  - `20261114105452_requests_2`: 익명 제한·가입 동의·상태 버튼·해결 확인 알림·신고·내 정보 개편 (2-12 ~ 2-16, 2-18)
- 시연용 데이터는 `seed.sql` (원격에는 이미 넣어 둠, `is_demo = true`). 로컬은 `supabase db reset` 시 자동 실행됩니다.
- 대시보드 설정: Authentication > Anonymous sign-ins 켜 둠.
- 서버 내부 값(승격 기준 하트 수, 하트당 점수, 하트 하루 상한, XP·레벨 기준, 인증 반경, 하루 상한, 제보 공개 지연 등)은 `public.app_settings` 한 줄에 있고 클라이언트는 읽을 수 없습니다. 값을 바꿀 땐 마이그레이션으로 update 합니다.
- 운영진 알림: Vault 에 `discord_webhook_url` 를 넣으면 제휴 의뢰 검토 요청·업체 등록 때 디스코드로 알림(pg_net). 제휴 의뢰 승인·반려는 `docs/api.md` "제휴업체 웹" 의 SQL.
- 운영진 확인 목록: `select * from public.staff_attention;` (숨김 제보, 신고, "치워졌어요" 누적, 해결 이의, 프로필 사진 신고)
- 익명 쓰기 막기·필수 동의 검사는 `app_settings.block_anonymous_writes`, `require_consent` 로 켜고 끕니다(기본 켜짐).
- 예약 작업(pg_cron): `jubquest-expire-stale`(5분마다 만료 정리), `jubquest-next-season`(매일 00:05 KST 다음 시즌 생성).
