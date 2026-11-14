-- 백엔드 요청 2-12 ~ 2-16, 2-18 (docs/backend-requests.md)
-- 2-12 익명 제한 · 2-13 가입 동의 · 2-14 상태 버튼 · 2-15 해결 확인 알림 · 2-16 제보 신고 · 2-18 내 정보 개편

-- ─────────────────────────────────────────────
-- 설정 (임시값)
-- ─────────────────────────────────────────────
alter table public.app_settings
  add column block_anonymous_writes boolean not null default true,  -- 2-12 익명은 둘러보기만
  add column require_consent boolean not null default true,         -- 2-13 필수 동의 없으면 쓰기 막기
  add column consent_version text not null default '2026-11-14',    -- 2-13 지금 약관 버전 (임시)
  add column gone_alert_threshold int not null default 3,           -- 2-14 '치워졌어요' 표시가 이만큼이면 운영진 확인 (임시)
  add column dispute_threshold int not null default 2,              -- 2-15 '아직이에요' 이만큼이면 운영진 검토 (임시)
  add column flag_hide_threshold int not null default 3;            -- 2-16 신고 이만큼이면 자동 숨김 (임시)

-- ─────────────────────────────────────────────
-- 컬럼
-- ─────────────────────────────────────────────
alter table public.reports
  add column spot text check (char_length(spot) <= 30),   -- 2-18 위치 설명 ("○○편의점 앞 전봇대 밑")
  add column hidden_at timestamptz,                       -- 2-16 신고 누적으로 숨김
  add column gone_flagged_at timestamptz;                 -- 2-14 '치워졌어요' 누적 표시
alter table public.quests
  add column spot text check (char_length(spot) <= 30),   -- 2-18 승격 시 제보에서 복사
  add column disputed_at timestamptz;                     -- 2-15 '아직이에요' 누적
alter table public.profiles
  add column title_key text;                              -- 2-18 고른 칭호 ('lv:3' / 'ach:first')
grant insert (spot) on public.reports to authenticated;

-- ─────────────────────────────────────────────
-- 2-13 가입 동의 기록 (저장할 때마다 한 줄씩 쌓임)
-- ─────────────────────────────────────────────
create table public.consent_records (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  items jsonb not null,          -- {"age":true,"terms":true,"privacy":true,"location":true,"push":false}
  version text not null,
  created_at timestamptz not null default now()
);
create index consent_records_user_idx on public.consent_records (user_id, created_at desc);

-- ─────────────────────────────────────────────
-- 2-14 상태 버튼 (한 사람이 제보 하나에 하나)
-- ─────────────────────────────────────────────
create table public.report_marks (
  report_id bigint not null references public.reports(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  mark text not null check (mark in ('still','gone','worse')),
  updated_at timestamptz not null default now(),
  primary key (report_id, user_id)
);

-- ─────────────────────────────────────────────
-- 2-15 해결 확인 알림
-- ─────────────────────────────────────────────
create table public.resolve_notices (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,  -- 받는 사람
  report_id bigint references public.reports(id) on delete set null,
  quest_id bigint not null references public.quests(id) on delete cascade,
  claim_id bigint references public.quest_claims(id) on delete set null,
  title text not null,
  solver text not null default '',
  before_path text,
  after_path text,
  single boolean not null default false,
  answer text check (answer in ('ok','not')),
  answered_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, quest_id)
);
create index resolve_notices_user_idx on public.resolve_notices (user_id, created_at desc);

-- ─────────────────────────────────────────────
-- 2-16 제보 신고, 2-18 프로필 사진 신고
-- ─────────────────────────────────────────────
create table public.report_flags (
  report_id bigint not null references public.reports(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('photo','fake','privacy','danger','etc')),
  status text not null default 'pending' check (status in ('pending','resolved','dismissed')),
  created_at timestamptz not null default now(),
  primary key (report_id, user_id)
);
create table public.avatar_flags (
  target_user uuid not null references public.profiles(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('photo','privacy','etc')),
  status text not null default 'pending' check (status in ('pending','resolved','dismissed')),
  created_at timestamptz not null default now(),
  primary key (target_user, user_id)
);

-- ─────────────────────────────────────────────
-- 2-18 도전과제 (frontend/src/lib/achievements.js 와 같은 조건, 숫자 임시)
-- ─────────────────────────────────────────────
create table public.achievements (
  id text primary key,
  metric text not null check (metric in ('completed','hearts','reports','rewards','streak','crew','places','issues')),
  goal int not null
);
insert into public.achievements (id, metric, goal) values
  ('first','completed',1), ('ten','completed',10), ('thirty','completed',30),
  ('heart10','hearts',10), ('heart50','hearts',50),
  ('report1','reports',1), ('report10','reports',10),
  ('streak2','streak',2), ('streak4','streak',4),
  ('crew','crew',1), ('places','places',5), ('issues','issues',5), ('reward','rewards',1);

-- ─────────────────────────────────────────────
-- 권한
-- ─────────────────────────────────────────────
alter table public.consent_records enable row level security;
alter table public.report_marks enable row level security;
alter table public.resolve_notices enable row level security;
alter table public.report_flags enable row level security;
alter table public.avatar_flags enable row level security;
alter table public.achievements enable row level security;
revoke insert, update, delete, truncate on public.consent_records, public.report_marks, public.resolve_notices,
  public.report_flags, public.avatar_flags, public.achievements from anon, authenticated;
create policy "own read" on public.consent_records for select to authenticated using (user_id = (select auth.uid()));
create policy "own read" on public.report_marks for select to authenticated using (user_id = (select auth.uid()));
create policy "own read" on public.resolve_notices for select to authenticated using (user_id = (select auth.uid()));
create policy "own read" on public.report_flags for select to authenticated using (user_id = (select auth.uid()));
create policy "own read" on public.avatar_flags for select to authenticated using (user_id = (select auth.uid()));
create policy "public read" on public.achievements for select to anon, authenticated using (true);

-- 2-18 프로필 사진 버킷 (공개 읽기, 본인 폴더만 쓰기)
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
drop policy "upload own folder" on storage.objects;
create policy "upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id in ('report-photos','claim-photos','avatars')
              and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ─────────────────────────────────────────────
-- 2-12, 2-13 쓰기 기능 공통 검사
-- 익명(둘러보기) 계정 → LOGIN_REQUIRED, 필수 동의 없음 → CONSENT_REQUIRED
-- 서버 내부 실행(auth.uid() 없음)은 통과. 설정 두 개로 끌 수 있습니다.
-- ─────────────────────────────────────────────
create or replace function public.has_required_consent(p_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select (c.items->>'age')::boolean and (c.items->>'terms')::boolean
       and (c.items->>'privacy')::boolean and (c.items->>'location')::boolean
    from public.consent_records c where c.user_id = p_user
    order by c.created_at desc, c.id desc limit 1), false)
$$;

create or replace function public.require_member()
returns void language plpgsql stable security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); s public.app_settings;
begin
  if v_uid is null then return; end if;
  select * into s from public.app_settings;
  if s.block_anonymous_writes and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) then
    raise exception 'LOGIN_REQUIRED';
  end if;
  if s.require_consent and not public.has_required_consent(v_uid) then
    raise exception 'CONSENT_REQUIRED';
  end if;
end $$;

create or replace function public.save_consent(p_items jsonb, p_version text default null)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_version text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if jsonb_typeof(p_items) <> 'object' then raise exception 'INVALID_INPUT'; end if;
  if not (coalesce((p_items->>'age')::boolean, false) and coalesce((p_items->>'terms')::boolean, false)
          and coalesce((p_items->>'privacy')::boolean, false) and coalesce((p_items->>'location')::boolean, false)) then
    raise exception 'CONSENT_REQUIRED';
  end if;
  v_version := coalesce(nullif(btrim(coalesce(p_version, '')), ''), (select consent_version from public.app_settings));
  insert into public.consent_records (user_id, items, version)
  values (v_uid, jsonb_build_object(
            'age', true, 'terms', true, 'privacy', true, 'location', true,
            'push', coalesce((p_items->>'push')::boolean, false)), v_version);
  return public.my_consent();
end $$;

create or replace function public.my_consent()
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object('items', c.items, 'version', c.version, 'at', c.created_at,
                           'current_version', s.consent_version,
                           'ok', public.has_required_consent(c.user_id))
  from public.consent_records c cross join public.app_settings s
  where c.user_id = auth.uid()
  order by c.created_at desc, c.id desc limit 1
$$;

-- ─────────────────────────────────────────────
-- 쓰기 경로마다 검사 붙이기 (테이블 트리거라 RPC·직접 insert 모두 막힘)
-- ─────────────────────────────────────────────

-- 제보: 공개 시각, 사진 확인, 회원 검사
create or replace function public.on_report_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  perform public.require_member();
  new.visible_at := now() + (select report_publish_delay from public.app_settings);
  new.spot := nullif(btrim(coalesce(new.spot, '')), '');
  if v_uid is not null and new.photo_url is not null
     and public.own_upload_at('report-photos', new.photo_url, v_uid) is null then
    raise exception 'INVALID_PHOTO';
  end if;
  return new;
end $$;

-- 하트: 회원 검사 + 숨김 제보 불가
create or replace function public.on_heart_before()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r public.reports; v_today int;
begin
  perform public.require_member();
  perform pg_advisory_xact_lock(hashtext('heart:' || new.user_id::text));
  select * into r from public.reports where id = new.report_id;
  if not found or r.status = 'rejected' or r.hidden_at is not null then raise exception 'REPORT_NOT_OPEN'; end if;
  if r.author_id = new.user_id then raise exception 'CANNOT_LIKE_OWN_REPORT'; end if;
  if r.visible_at is not null and r.visible_at > now() then raise exception 'REPORT_PENDING'; end if;
  select count(*) into v_today from public.report_hearts
    where user_id = new.user_id and created_at >= public.kst_today_start();
  if v_today >= (select heart_daily_limit from public.app_settings) then
    raise exception 'HEART_DAILY_LIMIT';
  end if;
  return new;
end $$;

-- 승격 시 위치 설명(spot)도 의뢰로 복사
create or replace function public.on_heart_added()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r public.reports; s public.app_settings; v_nick text;
begin
  select * into s from public.app_settings;
  update public.reports set heart_count = heart_count + 1 where id = new.report_id returning * into r;

  if r.status = 'open' and r.heart_count >= s.promote_heart_threshold then
    update public.reports set status = 'promoted', promoted_at = now() where id = r.id returning * into r;
    select nickname into v_nick from public.profiles where id = r.author_id;
    insert into public.quests (kind, report_id, requester_id, title, description, org_name,
                               lat, lng, address, spot, est_minutes, category, issue_type, required_members, is_demo)
    values ('report', r.id, r.author_id, r.title, r.description, coalesce(v_nick, '이웃주민'),
            r.lat, r.lng, r.address, r.spot, r.est_minutes, r.category, r.issue_type, r.required_members, r.is_demo);
  end if;

  if s.heart_giver_points > 0 and not exists (
       select 1 from public.point_ledger
       where user_id = new.user_id and report_id = new.report_id and reason = 'heart_given') then
    perform public.credit_points(new.user_id, s.heart_giver_points, 0, 0, 'heart_given', null, new.report_id);
  end if;
  return new;
end $$;

-- 크루 의뢰 올리기
create or replace function public.on_crew_quest_insert()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_points int;
begin
  if new.kind = 'crew' then
    perform public.require_member();
    v_points := (select crew_quest_points from public.app_settings);
    select name into new.org_name from public.crews where id = new.crew_id;
    new.reward_points := v_points;
    new.reward_text := coalesce(new.reward_text, '에코포인트 ' || v_points || ' + 크루 XP');
    new.expires_at := coalesce(new.expires_at, coalesce(new.starts_at, now()) + interval '1 day');
    if new.required_members < 2 then new.required_members := 2; end if;
  end if;
  return new;
end $$;

-- 수락: 회원 검사 + 제휴 의뢰 모집 인원
create or replace function public.on_claim_before()
returns trigger language plpgsql security definer set search_path = '' as $$
declare q public.quests;
begin
  perform public.require_member();
  select * into q from public.quests where id = new.quest_id;
  if q.kind = 'partner' and q.capacity is not null
     and (select count(*) from public.quest_claims where quest_id = q.id and status in ('accepted','approved')) >= q.capacity then
    raise exception 'REPORT_FULL';
  end if;
  return new;
end $$;

-- 인증 승인 직전: 회원 검사
create or replace function public.on_claim_approving()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'approved' and old.status <> 'approved' then
    perform public.require_member();
  end if;
  return new;
end $$;
create trigger quest_claims_before_update before update of status on public.quest_claims
  for each row execute function public.on_claim_approving();

-- 인증 승인 뒤: 제휴 모집 인원 마감 + 2-15 해결 확인 알림 (제보자·하트 누른 사람, 해결한 본인 제외)
create or replace function public.on_claim_approved()
returns trigger language plpgsql security definer set search_path = '' as $$
declare q public.quests; v_solver text;
begin
  if new.status = 'approved' and old.status <> 'approved' then
    select * into q from public.quests where id = new.quest_id;
    if q.kind = 'partner' and q.capacity is not null
       and (select count(*) from public.quest_claims where quest_id = q.id and status = 'approved') >= q.capacity then
      update public.quests set status = 'done' where id = q.id;
      update public.quest_claims set status = 'cancelled' where quest_id = q.id and status = 'accepted';
    end if;
    if q.kind = 'report' and q.report_id is not null then
      select nickname into v_solver from public.profiles where id = new.user_id;
      insert into public.resolve_notices (user_id, report_id, quest_id, claim_id, title, solver,
                                          before_path, after_path, single)
      select w.uid, q.report_id, q.id, new.id, q.title, coalesce(v_solver, ''),
             new.before_photo_url, new.after_photo_url, q.proof_mode = 'single'
      from (select author_id as uid from public.reports where id = q.report_id
            union select user_id from public.report_hearts where report_id = q.report_id) w
      where w.uid is not null and w.uid <> new.user_id
      on conflict (user_id, quest_id) do nothing;
    end if;
  end if;
  return new;
end $$;

-- 크루 가입, 상점 교환, 꾸미기 구매
create or replace function public.on_member_write()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_member();
  return new;
end $$;
create trigger crew_members_before_insert before insert on public.crew_members
  for each row execute function public.on_member_write();
create trigger coupons_before_insert before insert on public.coupons
  for each row execute function public.on_member_write();
create trigger user_cosmetics_before_insert before insert on public.user_cosmetics
  for each row execute function public.on_member_write();

-- ─────────────────────────────────────────────
-- 2-14 상태 버튼
-- ─────────────────────────────────────────────
create or replace function public.report_marks_json(p_report bigint)
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'still', count(*) filter (where mark = 'still'),
    'gone', count(*) filter (where mark = 'gone'),
    'worse', count(*) filter (where mark = 'worse'))
  from public.report_marks where report_id = p_report
$$;

-- 같은 걸 다시 누르면 해제, 다른 걸 누르면 바꿈
create or replace function public.set_mark(p_report_id bigint, p_mark text)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); r public.reports; v_old text; v_gone int; s public.app_settings;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.require_member();
  if p_mark not in ('still','gone','worse') then raise exception 'INVALID_INPUT'; end if;
  select * into r from public.reports where id = p_report_id;
  if not found or r.hidden_at is not null or r.status = 'rejected'
     or (r.visible_at > now() and r.author_id is distinct from v_uid) then
    raise exception 'REPORT_NOT_OPEN';
  end if;
  select mark into v_old from public.report_marks where report_id = r.id and user_id = v_uid;
  if v_old = p_mark then
    delete from public.report_marks where report_id = r.id and user_id = v_uid;
  else
    insert into public.report_marks (report_id, user_id, mark) values (r.id, v_uid, p_mark)
    on conflict (report_id, user_id) do update set mark = excluded.mark, updated_at = now();
  end if;
  -- '치워졌어요'가 기준만큼 모이면 운영진이 볼 수 있게 표시 (자동 종료는 결정 대기)
  select * into s from public.app_settings;
  select count(*) into v_gone from public.report_marks where report_id = r.id and mark = 'gone';
  if v_gone >= s.gone_alert_threshold and r.gone_flagged_at is null then
    update public.reports set gone_flagged_at = now() where id = r.id;
    perform public.notify_staff(format('[집게표] "치워졌어요" %s건 · 제보 #%s %s', v_gone, r.id, r.title));
  end if;
  return json_build_object('marks', public.report_marks_json(r.id),
                           'my_mark', (select mark from public.report_marks where report_id = r.id and user_id = v_uid));
end $$;

-- ─────────────────────────────────────────────
-- 2-15 해결 확인 알림
-- ─────────────────────────────────────────────
create or replace function public.my_notices()
returns json language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
           'id', n.id, 'report_id', n.report_id, 'quest_id', n.quest_id, 'title', n.title, 'solver', n.solver,
           'before_path', n.before_path, 'after_path', n.after_path, 'single', n.single,
           'at', n.created_at, 'answer', n.answer, 'answered_at', n.answered_at)
         order by n.created_at desc, n.id desc), '[]'::json)
  from public.resolve_notices n where n.user_id = auth.uid()
$$;

create or replace function public.answer_notice(p_notice_id bigint, p_answer text)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); n public.resolve_notices; v_not int; q public.quests;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_answer not in ('ok','not') then raise exception 'INVALID_INPUT'; end if;
  update public.resolve_notices set answer = p_answer, answered_at = now()
    where id = p_notice_id and user_id = v_uid and answer is null
    returning * into n;
  if n.id is null then raise exception 'NOTICE_NOT_FOUND'; end if;
  select count(*) into v_not from public.resolve_notices where quest_id = n.quest_id and answer = 'not';
  if p_answer = 'not' and v_not >= (select dispute_threshold from public.app_settings) then
    update public.quests set disputed_at = now() where id = n.quest_id and disputed_at is null returning * into q;
    if q.id is not null then
      perform public.notify_staff(format('[집게표] 해결 이의 "아직이에요" %s건 · 의뢰 #%s %s', v_not, q.id, q.title));
    end if;
  end if;
  return json_build_object('id', n.id, 'answer', n.answer, 'not_count', v_not);
end $$;

-- ─────────────────────────────────────────────
-- 2-16 제보 신고, 2-18 프로필 사진 신고
-- ─────────────────────────────────────────────
create or replace function public.flag_report(p_report_id bigint, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); r public.reports; v_n int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.require_member();
  if p_reason not in ('photo','fake','privacy','danger','etc') then raise exception 'INVALID_INPUT'; end if;
  select * into r from public.reports where id = p_report_id;
  if not found then raise exception 'REPORT_NOT_OPEN'; end if;
  insert into public.report_flags (report_id, user_id, reason) values (r.id, v_uid, p_reason)
  on conflict (report_id, user_id) do nothing;
  if not found then return; end if;  -- 이미 신고함
  select count(*) into v_n from public.report_flags where report_id = r.id and status = 'pending';
  perform public.notify_staff(format('[집게표] 제보 신고(%s) · 제보 #%s %s · 누적 %s건', p_reason, r.id, r.title, v_n));
  if v_n >= (select flag_hide_threshold from public.app_settings) and r.hidden_at is null then
    update public.reports set hidden_at = now() where id = r.id;
    perform public.notify_staff(format('[집게표] 신고 누적으로 제보 #%s 자동 숨김', r.id));
  end if;
end $$;

create or replace function public.flag_avatar(p_user_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_n int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.require_member();
  if p_reason not in ('photo','privacy','etc') then raise exception 'INVALID_INPUT'; end if;
  if p_user_id = v_uid or not exists (select 1 from public.profiles where id = p_user_id and avatar_url is not null) then
    raise exception 'INVALID_INPUT';
  end if;
  insert into public.avatar_flags (target_user, user_id, reason) values (p_user_id, v_uid, p_reason)
  on conflict (target_user, user_id) do nothing;
  if not found then return; end if;
  select count(*) into v_n from public.avatar_flags where target_user = p_user_id and status = 'pending';
  perform public.notify_staff(format('[집게표] 프로필 사진 신고(%s) · 사용자 %s · 누적 %s건', p_reason, p_user_id, v_n));
  if v_n >= (select flag_hide_threshold from public.app_settings) then
    update public.profiles set avatar_url = null where id = p_user_id;  -- 기본(닉네임 첫 글자)으로
  end if;
end $$;

-- ─────────────────────────────────────────────
-- 2-18 프로필 사진·칭호
-- ─────────────────────────────────────────────

-- 프로필 사진은 avatars 버킷의 본인 폴더 파일만
create or replace function public.on_profile_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is not null and new.avatar_url is distinct from old.avatar_url and new.avatar_url is not null
     and public.own_upload_at('avatars', new.avatar_url, v_uid) is null then
    raise exception 'INVALID_PHOTO';
  end if;
  return new;
end $$;
create trigger profiles_before_update before update of avatar_url on public.profiles
  for each row execute function public.on_profile_update();

-- 도전과제·도감 계산용 누적 값
create or replace function public.user_stats(p_user uuid)
returns json language sql stable security definer set search_path = '' as $$
  with done as (
    select q.category, q.issue_type
    from public.quest_claims c join public.quests q on q.id = c.quest_id
    where c.user_id = p_user and c.status = 'approved'
  )
  select json_build_object(
    'completed', (select count(*) from done),
    'hearts', (select count(*) from public.report_hearts where user_id = p_user),
    'reports', (select count(*) from public.reports where author_id = p_user),
    'rewards', (select count(*) from public.quest_claims where user_id = p_user and status = 'approved' and reward_label is not null),
    'places', coalesce((select json_object_agg(k, n) from (select public.category_place(category) k, count(*) n from done group by 1) x), '{}'::json),
    'issues', coalesce((select json_object_agg(k, n) from (select issue_type k, count(*) n from done where issue_type is not null group by 1) x), '{}'::json))
$$;

-- 칭호 고르기. 'lv:N' 은 레벨 N 이상, 'ach:id' 는 도전과제 달성. null 이면 지금 레벨 칭호.
create or replace function public.set_title(p_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_st json; v_level int; a public.achievements; v_val int; v_min int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_key is null or p_key = '' then
    update public.profiles set title_key = null where id = v_uid;
    return;
  end if;
  select public.level_of(xp) into v_level from public.profiles where id = v_uid;
  if p_key like 'lv:%' then
    v_min := nullif(regexp_replace(p_key, '^lv:(\d+)$', '\1'), p_key)::int;
    if v_min is null or v_min not in (1,2,3,4,5,6,7,8,9,10,12,15,20) then raise exception 'INVALID_INPUT'; end if;
    if v_level < v_min then raise exception 'TITLE_LOCKED'; end if;
  elsif p_key like 'ach:%' then
    select * into a from public.achievements where id = substr(p_key, 5);
    if not found then raise exception 'INVALID_INPUT'; end if;
    v_st := public.user_stats(v_uid);
    v_val := case a.metric
      when 'streak' then public.streak_weeks(v_uid)
      when 'crew' then (select count(*) from public.crew_members where user_id = v_uid)::int
      when 'places' then (select count(*) from json_object_keys(v_st -> 'places'))::int
      when 'issues' then (select count(*) from json_object_keys(v_st -> 'issues'))::int
      else (v_st ->> a.metric)::int end;
    if v_val < a.goal then raise exception 'TITLE_LOCKED'; end if;
  else
    raise exception 'INVALID_INPUT';
  end if;
  update public.profiles set title_key = p_key where id = v_uid;
end $$;

-- 내 정보: 2-18 값(title_key, weekly, stats) 추가
create or replace function public.my_profile()
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); p public.profiles; s public.app_settings;
  v_level int; v_completed int; v_hearts int; v_dones int; v_crew text; v_look json; v_week date;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into p from public.profiles where id = v_uid;
  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;
  select * into s from public.app_settings;
  v_level := public.level_of(p.xp);
  v_week := date_trunc('week', now() at time zone 'Asia/Seoul')::date;
  select count(*) into v_completed from public.quest_claims where user_id = v_uid and status = 'approved';
  select count(*) into v_dones from public.quest_claims
    where user_id = v_uid and status = 'approved' and approved_at >= public.kst_today_start();
  select count(*) into v_hearts from public.report_hearts
    where user_id = v_uid and created_at >= public.kst_today_start();
  select c.name into v_crew from public.crew_members m join public.crews c on c.id = m.crew_id where m.user_id = v_uid;
  v_look := public.look_of(p.frame_id, p.name_color_id);

  return json_build_object(
    'id', p.id, 'nickname', p.nickname, 'initial', left(p.nickname, 1),
    'avatar_url', p.avatar_url, 'home_area', p.home_area, 'title_key', p.title_key,
    'frame', v_look -> 'frame', 'name_color', v_look ->> 'name_color',
    'joined_days', ((now() at time zone 'Asia/Seoul')::date - (p.created_at at time zone 'Asia/Seoul')::date) + 1,
    'points', p.points, 'total_earned', p.total_earned,
    'xp', p.xp, 'level', v_level,
    'xp_in_level', p.xp % s.xp_per_level, 'xp_for_next_level', s.xp_per_level,
    'crew', v_crew,
    'hearts_today', v_hearts, 'hearts_limit', s.heart_daily_limit,
    'completes_today', v_dones, 'completes_limit', s.daily_claim_limit,
    'daily_remaining', greatest(0, s.daily_claim_limit - v_dones),
    'completed_count', v_completed,
    'streak_weeks', public.streak_weeks(v_uid),
    'active_this_week', exists (select 1 from public.quest_claims where user_id = v_uid and status = 'approved'
                                and approved_at >= v_week::timestamp at time zone 'Asia/Seoul'),
    -- 최근 8주 주마다 해결한 수 (오래된 주부터, KST 월요일 시작)
    'weekly', (select json_agg(coalesce(x.n, 0) order by w.i) from generate_series(0, 7) w(i)
               left join (select date_trunc('week', approved_at at time zone 'Asia/Seoul')::date as wk, count(*) as n
                          from public.quest_claims where user_id = v_uid and status = 'approved'
                            and approved_at >= (v_week - 49)::timestamp at time zone 'Asia/Seoul'
                          group by 1) x on x.wk = v_week - (7 - w.i) * 7),
    'stats', public.user_stats(v_uid),
    'cleaned', coalesce((select json_agg(x) from (
        select q.id, c.approved_at as at, q.title, q.category as place_label, q.issue_type
        from public.quest_claims c join public.quests q on q.id = c.quest_id
        where c.user_id = v_uid and c.status = 'approved'
        order by c.approved_at desc limit 10) x), '[]'::json),
    'rewards', coalesce((select json_agg(x) from (
        select c.reward_label as label, q.org_name as "from", c.approved_at as at
        from public.quest_claims c join public.quests q on q.id = c.quest_id
        where c.user_id = v_uid and c.status = 'approved' and c.reward_label is not null
        order by c.approved_at desc) x), '[]'::json),
    'coupons', coalesce((select json_agg(x) from (
        select name, code, created_at as at from public.coupons where user_id = v_uid order by created_at desc) x), '[]'::json),
    'records', json_build_array(
      json_build_array('완료한 의뢰', v_completed || '건'),
      json_build_array('올린 제보', (select count(*) from public.reports where author_id = v_uid) || '건'),
      json_build_array('누적 포인트', p.total_earned || '점')));
end $$;

-- ─────────────────────────────────────────────
-- 목록: spot, 상태 버튼 개수, 숨김·내가 신고한 제보 제외
-- ─────────────────────────────────────────────
drop function if exists public.quests_nearby(double precision, double precision, int, text);
create or replace function public.quests_nearby(
  p_lat double precision, p_lng double precision, p_radius_m int default 1500, p_kind text default null
) returns table (
  id bigint, code text, kind text, label text, title text, org text, description text,
  goal text, tools text, time_label text, point int, reward text, hot boolean,
  lat double precision, lng double precision, address text, spot text,
  distance_m int, dist text, near boolean,
  required_members int, current_members int,
  hearts int, hearted boolean, marks json, my_mark text,
  my_status text, my_claim_id bigint, cleared boolean, status text, expires_at timestamptz,
  report_id bigint, photo_url text, category text, issue_type text, is_mine boolean,
  proof_mode text, proof_label text, reward_label text, reward_value text, reward_unit text,
  reward_xp int, reward_crew_xp int, is_demo boolean
) language sql stable security definer set search_path = '' as $$
  with me as (
    select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography as pt,
           (select crew_id from public.crew_members where user_id = (select auth.uid())) as my_crew,
           (select crew_quest_xp_multiplier from public.app_settings) as mult
  ), q as (
    select q.*, rp.heart_count, rp.photo_url as report_photo, rp.author_id, rp.visible_at,
           case when q.location is null then null else extensions.st_distance(q.location, me.pt) end as d,
           exists (select 1 from public.quest_claims c
                   where c.quest_id = q.id and c.user_id = (select auth.uid()) and c.status = 'approved') as cleared_by_me,
           public.category_xp(q.category) as xp,
           me.my_crew, me.mult
    from public.quests q
    cross join me
    left join public.reports rp on rp.id = q.report_id
    where (p_kind is null or q.kind = p_kind)
      and (q.kind <> 'crew' or q.crew_id = me.my_crew)
      and (q.location is null or extensions.st_dwithin(q.location, me.pt, p_radius_m))
      and (rp.id is null or rp.visible_at is null or rp.visible_at <= now() or rp.author_id = (select auth.uid()))
      and (rp.id is null or rp.hidden_at is null)
      and (rp.id is null or not exists (select 1 from public.report_flags f
                                        where f.report_id = rp.id and f.user_id = (select auth.uid())))
  )
  select q.id,
         'Q-' || lpad(q.id::text, 4, '0'),
         q.kind,
         case q.kind when 'partner' then '제휴 의뢰' when 'crew' then '크루 의뢰' else '주민 제보' end,
         q.title, q.org_name, q.description, q.goal, q.tools,
         coalesce(q.time_label, '약 ' || coalesce(q.est_minutes, 15) || '분'),
         case when q.kind = 'report' then public.report_point_value(q.heart_count) else q.reward_points end,
         coalesce(q.reward_text,
                  '에코포인트 ' || case when q.kind = 'report' then public.report_point_value(q.heart_count) else q.reward_points end),
         q.hot or coalesce(q.heart_count, 0) >= 10,
         q.lat, q.lng, q.address, q.spot,
         round(q.d)::int, public.dist_label(q.d), coalesce(q.d <= 500, false),
         q.required_members,
         (select count(*)::int from public.quest_claims c where c.quest_id = q.id and c.status in ('accepted','approved')),
         q.heart_count,
         case when q.report_id is null then null
              else exists (select 1 from public.report_hearts h where h.report_id = q.report_id and h.user_id = (select auth.uid())) end,
         case when q.report_id is null then null else public.report_marks_json(q.report_id) end,
         case when q.report_id is null then null
              else (select m.mark from public.report_marks m where m.report_id = q.report_id and m.user_id = (select auth.uid())) end,
         (select c.status from public.quest_claims c
           where c.quest_id = q.id and c.user_id = (select auth.uid())
           order by c.created_at desc limit 1),
         (select c.id from public.quest_claims c
           where c.quest_id = q.id and c.user_id = (select auth.uid()) and c.status = 'accepted'
           order by c.created_at desc limit 1),
         q.cleared_by_me, q.status, q.expires_at,
         q.report_id, q.report_photo, q.category, q.issue_type,
         coalesce(q.author_id = (select auth.uid()), false),
         q.proof_mode, q.proof_label, q.reward_label, q.reward_value, q.reward_unit,
         q.xp,
         case when q.my_crew is null then 0
              when q.kind = 'crew' or q.required_members > 1 then q.xp * q.mult else q.xp end,
         q.is_demo
  from q
  where q.status = 'open' or q.cleared_by_me
  order by q.d nulls last, q.created_at desc
$$;

drop function if exists public.reports_nearby(double precision, double precision, int);
create or replace function public.reports_nearby(
  p_lat double precision, p_lng double precision, p_radius_m int default 1500
) returns table (
  id bigint, code text, title text, author text, description text, category text, issue_type text, photo_url text,
  lat double precision, lng double precision, address text, spot text,
  distance_m int, dist text, near boolean, time_label text,
  hearts int, point int, reward_xp int, required_members int,
  hearted boolean, marks json, my_mark text, mine boolean, pending_until timestamptz, is_demo boolean, created_at timestamptz
) language sql stable security definer set search_path = '' as $$
  with me as (
    select extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography as pt
  )
  select r.id, 'R-' || lpad(r.id::text, 4, '0'), r.title, coalesce(p.nickname, '이웃주민'),
         r.description, r.category, r.issue_type, r.photo_url, r.lat, r.lng, r.address, r.spot,
         round(extensions.st_distance(r.location, me.pt))::int,
         public.dist_label(extensions.st_distance(r.location, me.pt)),
         extensions.st_distance(r.location, me.pt) <= 500,
         '약 ' || r.est_minutes || '분',
         r.heart_count, public.report_point_value(r.heart_count), public.category_xp(r.category), r.required_members,
         exists (select 1 from public.report_hearts h where h.report_id = r.id and h.user_id = (select auth.uid())),
         public.report_marks_json(r.id),
         (select m.mark from public.report_marks m where m.report_id = r.id and m.user_id = (select auth.uid())),
         coalesce(r.author_id = (select auth.uid()), false),
         case when r.visible_at > now() then r.visible_at end,
         r.is_demo,
         r.created_at
  from public.reports r
  cross join me
  left join public.profiles p on p.id = r.author_id
  where r.status = 'open'
    and r.hidden_at is null
    and (r.visible_at is null or r.visible_at <= now() or r.author_id = (select auth.uid()))
    and not exists (select 1 from public.report_flags f where f.report_id = r.id and f.user_id = (select auth.uid()))
    and extensions.st_dwithin(r.location, me.pt, p_radius_m)
  order by extensions.st_distance(r.location, me.pt)
$$;

-- ─────────────────────────────────────────────
-- 운영진이 볼 목록 (대시보드 SQL 에디터에서 select * from public.staff_attention;)
-- ─────────────────────────────────────────────
create or replace view public.staff_attention with (security_invoker = true) as
  select 'hidden_report'::text as kind, r.id, r.title, r.hidden_at as at,
         (select count(*) from public.report_flags f where f.report_id = r.id and f.status = 'pending') as count
  from public.reports r where r.hidden_at is not null
  union all
  select 'flagged_report', r.id, r.title, max(f.created_at), count(*)
  from public.report_flags f join public.reports r on r.id = f.report_id
  where f.status = 'pending' and r.hidden_at is null group by r.id, r.title
  union all
  select 'gone_report', r.id, r.title, r.gone_flagged_at,
         (select count(*) from public.report_marks m where m.report_id = r.id and m.mark = 'gone')
  from public.reports r where r.gone_flagged_at is not null
  union all
  select 'disputed_quest', q.id, q.title, q.disputed_at,
         (select count(*) from public.resolve_notices n where n.quest_id = q.id and n.answer = 'not')
  from public.quests q where q.disputed_at is not null
  union all
  select 'flagged_avatar', null, p.nickname, max(a.created_at), count(*)
  from public.avatar_flags a join public.profiles p on p.id = a.target_user
  where a.status = 'pending' group by p.id, p.nickname;
revoke all on public.staff_attention from anon, authenticated;

-- ─────────────────────────────────────────────
-- 실행 권한
-- ─────────────────────────────────────────────
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.quests_nearby(double precision, double precision, int, text) to anon, authenticated;
grant execute on function public.reports_nearby(double precision, double precision, int) to anon, authenticated;
grant execute on function public.area_stats(double precision, double precision, int) to anon, authenticated;
grant execute on function public.map_overview(double precision, double precision, int) to anon, authenticated;
grant execute on function public.current_season() to anon, authenticated;
grant execute on function public.crew_ranking() to anon, authenticated;
grant execute on function public.crews_to_join() to anon, authenticated;
grant execute on function public.cosmetics_list() to anon, authenticated;
grant execute on function public.accept_quest(bigint) to authenticated;
grant execute on function public.cancel_claim(bigint) to authenticated;
grant execute on function public.my_daily_remaining() to authenticated;
grant execute on function public.approve_claim(bigint, text, double precision, double precision, real, timestamptz, text,
                                               text, double precision, double precision, real, timestamptz, text, boolean,
                                               text, text) to authenticated;
grant execute on function public.my_claims() to authenticated;
grant execute on function public.my_profile() to authenticated;
grant execute on function public.my_cleaned(int, timestamptz) to authenticated;
grant execute on function public.my_crew() to authenticated;
grant execute on function public.give_heart(bigint) to authenticated;
grant execute on function public.create_crew(text, text) to authenticated;
grant execute on function public.join_crew(bigint) to authenticated;
grant execute on function public.leave_crew() to authenticated;
grant execute on function public.redeem_item(bigint) to authenticated;
grant execute on function public.buy_cosmetic(text) to authenticated;
grant execute on function public.equip_cosmetic(text) to authenticated;
grant execute on function public.partner_me() to authenticated;
grant execute on function public.partner_register(text, text) to authenticated;
grant execute on function public.partner_quests() to authenticated;
grant execute on function public.partner_create_quest(text, text, text, text, text, text, text, int, int, date, date,
                                                      double precision, double precision) to authenticated;
grant execute on function public.partner_cancel_quest(bigint) to authenticated;
grant execute on function public.partner_report() to authenticated;
-- 2-13 ~ 2-18
grant execute on function public.save_consent(jsonb, text) to authenticated;
grant execute on function public.my_consent() to authenticated;
grant execute on function public.set_mark(bigint, text) to authenticated;
grant execute on function public.my_notices() to authenticated;
grant execute on function public.answer_notice(bigint, text) to authenticated;
grant execute on function public.flag_report(bigint, text) to authenticated;
grant execute on function public.flag_avatar(uuid, text) to authenticated;
grant execute on function public.set_title(text) to authenticated;
