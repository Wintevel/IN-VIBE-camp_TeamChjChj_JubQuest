-- 인증 확인 투표(장연우 결정 2026-11-15) + 백엔드 요청 5-1 ~ 5-5
--
-- 인증 확인 (주민 제보·크루 의뢰)
--   인증 사진을 올리면 바로 승인하지 않고 '확인 대기(submitted)'. 포인트·XP 는 보류.
--   의뢰를 올린 사람 50% + 하트 누른 사람(크루 의뢰는 다른 크루원) 50% 를 똑같이 나눠 투표.
--   '치워졌어요' 합계가 60% 이상이면 승인. 올린 사람이 '아직이에요'면 바로 반려.
--   올린 사람이 없거나 본인이 해결자면 나머지가 100%, 투표할 사람이 아무도 없으면 운영진 검토.
--   48시간 안에 결론이 안 나면 운영진 검토(staff_review).
-- 인증 확인 (제휴 의뢰): 업체 담당자(현장 파견 인원)가 승인/반려. 업체 계정이 없거나 48시간 지나면 운영진 검토.
-- 하루 3개 상한은 인증을 제출한 시점으로 셉니다(확인 대기 포함).

-- ─────────────────────────────────────────────
-- 설정
-- ─────────────────────────────────────────────
alter table public.app_settings
  add column verify_threshold numeric not null default 60,              -- 승인 기준(%)
  add column verify_timeout interval not null default interval '48 hours', -- 이 안에 결론 없으면 운영진 검토
  add column crew_create_level int not null default 3,                  -- 5-1
  add column hearts_per_step int not null default 3;                    -- 5-2 하트 3개마다 points_per_heart(5)점

-- ─────────────────────────────────────────────
-- 인증 상태
-- ─────────────────────────────────────────────
alter table public.quest_claims drop constraint quest_claims_status_check;
alter table public.quest_claims add constraint quest_claims_status_check
  check (status in ('accepted','submitted','staff_review','approved','rejected','cancelled','expired'));
alter table public.quest_claims
  add column submitted_at timestamptz,
  add column decided_at timestamptz,
  add column decided_by text check (decided_by in ('vote','partner','staff')),
  add column reject_reason text;
drop index public.quest_claims_one_active_idx;
create unique index quest_claims_one_active_idx on public.quest_claims (quest_id, user_id)
  where status in ('accepted','submitted','staff_review');

-- 투표는 해결 확인 알림(resolve_notices)을 그대로 씁니다. 인증마다 한 사람 한 표.
alter table public.resolve_notices drop constraint resolve_notices_user_id_quest_id_key;
alter table public.resolve_notices
  add column role text not null default 'heart' check (role in ('author','heart','crew')),
  add column weight numeric not null default 0;
create unique index resolve_notices_user_claim_idx on public.resolve_notices (user_id, claim_id);
create index resolve_notices_claim_idx on public.resolve_notices (claim_id);

-- ─────────────────────────────────────────────
-- 5-3 도전과제 보상
-- ─────────────────────────────────────────────
alter table public.achievements
  add column points int not null default 0,
  add column xp int not null default 0;
update public.achievements a set points = v.p, xp = v.x
from (values ('first',10,30), ('ten',50,150), ('thirty',150,400), ('heart10',10,30), ('heart50',30,100),
             ('report1',10,30), ('report10',30,100), ('streak2',20,60), ('streak4',50,150), ('crew',10,30),
             ('places',50,150), ('issues',50,150), ('reward',10,30)) v(id, p, x)
where a.id = v.id;

alter table public.cosmetics add column feat text references public.achievements(id);  -- 도전과제로만 받는 품목
insert into public.cosmetics (id, kind, name, style, colors, cost, level, sort, feat) values
  ('frame-ember', 'frame', '열 번 찍은 불꽃', 'stars', array['#FF9F1A','#F04452','#FFD43B','#FF9F1A'], 0, 1, 7, 'ten'),
  ('frame-month', 'frame', '개근상 리본',     'neon',  array['#3DD68C','#FFD43B','#3DD68C'], 0, 1, 8, 'streak4'),
  ('name-rose',   'name',  '장미 닉네임',     null,    array['#FF7EB6'], 0, 1, 4, 'places');

create table public.user_feats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  feat_id text not null references public.achievements(id) on delete cascade,
  claimed_at timestamptz not null default now(),
  primary key (user_id, feat_id)
);
alter table public.user_feats enable row level security;
revoke insert, update, delete, truncate on public.user_feats from anon, authenticated;
create policy "own read" on public.user_feats for select to authenticated using (user_id = (select auth.uid()));

alter table public.point_ledger drop constraint point_ledger_reason_check;
alter table public.point_ledger add constraint point_ledger_reason_check check (reason in (
  'report_promoted','report_heart','heart_given','quest_approved','crew_quest',
  'shop_redeem','cosmetic_buy','feat_reward','seed'));

-- ─────────────────────────────────────────────
-- 5-2 해결 보상: 하트 3개마다 5점(상한 report_points_cap), 승격 문턱 없음
-- 제보는 올리는 즉시 의뢰가 됩니다(공개는 3분 뒤 그대로).
-- ─────────────────────────────────────────────
create or replace function public.report_point_value(p_heart_count integer)
returns integer language sql stable security definer set search_path = '' as $$
  select least((coalesce(p_heart_count, 0) / s.hearts_per_step) * s.points_per_heart, s.report_points_cap)
  from public.app_settings s
$$;

create or replace function public.promote_report(p_report bigint)
returns void language plpgsql security definer set search_path = '' as $$
declare r public.reports; v_nick text;
begin
  update public.reports set status = 'promoted', promoted_at = now()
    where id = p_report and status = 'open' returning * into r;
  if r.id is null then return; end if;
  select nickname into v_nick from public.profiles where id = r.author_id;
  insert into public.quests (kind, report_id, requester_id, title, description, org_name,
                             lat, lng, address, spot, est_minutes, category, issue_type, required_members, is_demo)
  values ('report', r.id, r.author_id, r.title, r.description, coalesce(v_nick, '이웃주민'),
          r.lat, r.lng, r.address, r.spot, r.est_minutes, r.category, r.issue_type, r.required_members, r.is_demo);
end $$;

create or replace function public.on_report_added()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.promote_report(new.id);
  return new;
end $$;
create trigger reports_after_insert after insert on public.reports
  for each row execute function public.on_report_added();

-- 하트: 수 증가 + 누른 사람 포인트만 (승격은 제보 시점에 이미 됨)
create or replace function public.on_heart_added()
returns trigger language plpgsql security definer set search_path = '' as $$
declare s public.app_settings;
begin
  select * into s from public.app_settings;
  update public.reports set heart_count = heart_count + 1 where id = new.report_id;
  if s.heart_giver_points > 0 and not exists (
       select 1 from public.point_ledger
       where user_id = new.user_id and report_id = new.report_id and reason = 'heart_given') then
    perform public.credit_points(new.user_id, s.heart_giver_points, 0, 0, 'heart_given', null, new.report_id);
  end if;
  return new;
end $$;

-- 기존에 승격 안 된 제보도 의뢰로
select public.promote_report(id) from public.reports where status = 'open';

-- ─────────────────────────────────────────────
-- 5-5 교환 상점 가격 10배
-- ─────────────────────────────────────────────
update public.shop_items set cost = cost * 10;

-- ─────────────────────────────────────────────
-- 하루 상한: 제출 기준
-- ─────────────────────────────────────────────
create or replace function public.my_daily_remaining()
returns integer language sql stable security definer set search_path = '' as $$
  select greatest(0, s.daily_claim_limit - (
    select count(*)::int from public.quest_claims c
    where c.user_id = auth.uid() and c.status in ('submitted','staff_review','approved')
      and coalesce(c.submitted_at, c.approved_at) >= public.kst_today_start()))
  from public.app_settings s
$$;

-- ─────────────────────────────────────────────
-- 인증 확인 투표
-- ─────────────────────────────────────────────

-- 투표할 사람 만들기. 만든 표 수를 돌려줍니다(0 이면 운영진 검토).
create or replace function public.create_claim_votes(p_claim bigint)
returns int language plpgsql security definer set search_path = '' as $$
declare c public.quest_claims; q public.quests; v_author uuid; v_group uuid[]; v_n int;
        v_aw numeric; v_gw numeric; v_solver text; v_report bigint;
begin
  select * into c from public.quest_claims where id = p_claim;
  select * into q from public.quests where id = c.quest_id;
  if q.kind = 'report' then
    select author_id into v_author from public.reports where id = q.report_id;
    select coalesce(array_agg(h.user_id), '{}') into v_group from public.report_hearts h
      where h.report_id = q.report_id and h.user_id <> c.user_id and h.user_id is distinct from v_author;
    v_report := q.report_id;
  elsif q.kind = 'crew' then
    v_author := q.requester_id;
    select coalesce(array_agg(m.user_id), '{}') into v_group from public.crew_members m
      where m.crew_id = q.crew_id and m.user_id <> c.user_id and m.user_id is distinct from v_author;
  else
    return 0;
  end if;
  if v_author = c.user_id then v_author := null; end if;
  v_n := cardinality(v_group);
  if v_author is null and v_n = 0 then return 0; end if;
  v_aw := case when v_author is null then 0 when v_n = 0 then 100 else 50 end;
  v_gw := case when v_n = 0 then 0 when v_author is null then 100.0 / v_n else 50.0 / v_n end;
  select nickname into v_solver from public.profiles where id = c.user_id;

  insert into public.resolve_notices (user_id, report_id, quest_id, claim_id, title, solver,
                                      before_path, after_path, single, role, weight)
  select x.uid, v_report, q.id, c.id, q.title, coalesce(v_solver, ''),
         c.before_photo_url, c.after_photo_url, q.proof_mode = 'single', x.role, x.w
  from (select v_author as uid, 'author' as role, v_aw as w where v_author is not null
        union all
        select g, case when q.kind = 'crew' then 'crew' else 'heart' end, v_gw from unnest(v_group) g) x
  on conflict (user_id, claim_id) do nothing;
  return (v_author is not null)::int + v_n;
end $$;

-- 결론 내기: 승인이면 보류해 둔 포인트·XP 지급
create or replace function public.finalize_claim(p_claim bigint, p_ok boolean, p_by text, p_reason text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.quest_claims; q public.quests; v_crew bigint; v_approved int;
begin
  select * into c from public.quest_claims where id = p_claim for update;
  if c.id is null or c.status not in ('submitted','staff_review') then return c.status; end if;
  select * into q from public.quests where id = c.quest_id for update;

  if not p_ok then
    update public.quest_claims set status = 'rejected', decided_at = now(), decided_by = p_by,
                                   reject_reason = p_reason
      where id = c.id;
    return 'rejected';
  end if;

  update public.quest_claims set status = 'approved', approved_at = now(), decided_at = now(), decided_by = p_by
    where id = c.id;
  v_crew := public.credit_points(c.user_id, c.points_awarded, c.xp_awarded, c.crew_xp_awarded,
    case when q.kind = 'crew' then 'crew_quest' else 'quest_approved' end, q.id, q.report_id);
  if v_crew is not null then
    perform public.crew_event(v_crew, 'complete', c.user_id, q.id, q.title, c.crew_xp_awarded, c.points_awarded,
                              q.kind = 'crew' or q.required_members > 1);
  end if;
  -- 주민 제보·크루 의뢰는 필요 인원만큼 승인되면 마감 (제휴 의뢰 모집 인원은 트리거가 처리)
  if q.kind in ('report','crew') then
    select count(*) into v_approved from public.quest_claims where quest_id = q.id and status = 'approved';
    if v_approved >= q.required_members then
      update public.quests set status = 'done' where id = q.id and status = 'open';
      update public.quest_claims set status = 'cancelled' where quest_id = q.id and status = 'accepted';
    end if;
  end if;
  return 'approved';
end $$;

-- 투표 집계
create or replace function public.evaluate_claim(p_claim bigint)
returns text language plpgsql security definer set search_path = '' as $$
declare v_ok numeric; v_pending numeric; v_author_not boolean; v_th numeric; v_status text;
begin
  select status into v_status from public.quest_claims where id = p_claim;
  if v_status is distinct from 'submitted' then return v_status; end if;
  select coalesce(sum(weight) filter (where answer = 'ok'), 0),
         coalesce(sum(weight) filter (where answer is null), 0),
         coalesce(bool_or(role = 'author' and answer = 'not'), false)
    into v_ok, v_pending, v_author_not
    from public.resolve_notices where claim_id = p_claim;
  v_th := (select verify_threshold from public.app_settings);
  if v_author_not then
    return public.finalize_claim(p_claim, false, 'vote', '의뢰를 올린 사람이 "아직이에요"를 골랐어요');
  elsif v_ok >= v_th - 0.0001 then
    return public.finalize_claim(p_claim, true, 'vote');
  elsif v_ok + v_pending < v_th - 0.0001 then
    return public.finalize_claim(p_claim, false, 'vote', '이웃 확인에서 "아직이에요"가 많았어요');
  end if;
  return 'submitted';
end $$;

-- 운영진 검토로 넘기기
create or replace function public.to_staff_review(p_claim bigint, p_why text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_title text;
begin
  update public.quest_claims set status = 'staff_review' where id = p_claim and status = 'submitted';
  if found then
    select q.title into v_title from public.quest_claims c join public.quests q on q.id = c.quest_id where c.id = p_claim;
    perform public.notify_staff(format('[집게표] 인증 운영진 검토 필요 · 인증 #%s %s (%s)', p_claim, v_title, p_why));
  end if;
end $$;

-- 해결 확인 답하기 = 투표
create or replace function public.answer_notice(p_notice_id bigint, p_answer text)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); n public.resolve_notices; v_status text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_answer not in ('ok','not') then raise exception 'INVALID_INPUT'; end if;
  update public.resolve_notices set answer = p_answer, answered_at = now()
    where id = p_notice_id and user_id = v_uid and answer is null
    returning * into n;
  if n.id is null then raise exception 'NOTICE_NOT_FOUND'; end if;
  if n.claim_id is not null then
    perform pg_advisory_xact_lock(hashtext('verify:' || n.claim_id::text));
    v_status := public.evaluate_claim(n.claim_id);
  end if;
  return json_build_object('id', n.id, 'answer', n.answer, 'claim_status', v_status);
end $$;

create or replace function public.my_notices()
returns json language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
           'id', n.id, 'claim_id', n.claim_id, 'report_id', n.report_id, 'quest_id', n.quest_id,
           'title', n.title, 'solver', n.solver,
           'before_path', n.before_path, 'after_path', n.after_path, 'single', n.single,
           'role', n.role, 'weight', round(n.weight, 1),
           'claim_status', c.status,
           'at', n.created_at, 'answer', n.answer, 'answered_at', n.answered_at)
         order by n.created_at desc, n.id desc), '[]'::json)
  from public.resolve_notices n left join public.quest_claims c on c.id = n.claim_id
  where n.user_id = auth.uid()
$$;

-- ─────────────────────────────────────────────
-- 인증 제출 (예전 이름 approve_claim 유지): 검사 통과 → 확인 대기
-- ─────────────────────────────────────────────
create or replace function public.approve_claim(
  p_claim_id bigint,
  p_before_photo_url text, p_before_lat double precision, p_before_lng double precision,
  p_before_accuracy_m real, p_before_taken_at timestamptz, p_before_photo_hash text,
  p_after_photo_url text default null, p_after_lat double precision default null, p_after_lng double precision default null,
  p_after_accuracy_m real default null, p_after_taken_at timestamptz default null, p_after_photo_hash text default null,
  p_mocked boolean default false,
  p_before_thumb text default null, p_after_thumb text default null
) returns json language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  s public.app_settings; c public.quest_claims; q public.quests;
  v_single boolean;
  v_before extensions.geography; v_after extensions.geography;
  v_before_up timestamptz; v_after_up timestamptz;
  v_count int; v_diff numeric;
  v_points int := 0; v_xp int; v_crew_xp int := 0; v_crew bigint; v_crewish boolean;
  v_status text := 'submitted'; v_voters int := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform pg_advisory_xact_lock(hashtext('claim:' || v_uid::text));

  select * into s from public.app_settings;
  select * into c from public.quest_claims where id = p_claim_id and user_id = v_uid for update;
  if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
  if c.status <> 'accepted' then raise exception 'CLAIM_NOT_ACTIVE'; end if;
  if c.accepted_at + s.claim_time_limit < now() then
    update public.quest_claims set status = 'expired' where id = c.id;
    raise exception 'CLAIM_EXPIRED';
  end if;
  select * into q from public.quests where id = c.quest_id for update;
  if q.status <> 'open' then raise exception 'QUEST_CLOSED'; end if;
  v_single := q.proof_mode = 'single';

  if public.my_daily_remaining() <= 0 then raise exception 'DAILY_LIMIT'; end if;

  if q.kind in ('report','crew') and q.required_members > 1 then
    select count(*) into v_count from public.quest_claims
      where quest_id = q.id and status in ('accepted','submitted','staff_review','approved');
    if v_count < q.required_members then raise exception 'REPORT_NOT_IN_PROGRESS'; end if;
  end if;

  if coalesce(p_mocked, false) then raise exception 'MOCK_LOCATION'; end if;
  if p_before_photo_url is null or p_before_lat is null or p_before_lng is null
     or p_before_taken_at is null or p_before_photo_hash is null then
    raise exception 'MISSING_PROOF';
  end if;
  if not v_single and (p_after_photo_url is null or p_after_lat is null or p_after_lng is null
                       or p_after_taken_at is null or p_after_photo_hash is null) then
    raise exception 'MISSING_PROOF';
  end if;

  v_before_up := public.own_upload_at('claim-photos', p_before_photo_url, v_uid);
  if v_before_up is null then raise exception 'INVALID_PHOTO'; end if;
  if not v_single then
    v_after_up := public.own_upload_at('claim-photos', p_after_photo_url, v_uid);
    if v_after_up is null then raise exception 'INVALID_PHOTO'; end if;
  end if;

  if p_before_taken_at < c.accepted_at - interval '5 minutes'
     or v_before_up < c.accepted_at
     or p_before_taken_at > now() + interval '5 minutes'
     or (not v_single and (p_after_taken_at < p_before_taken_at or p_after_taken_at > now() + interval '5 minutes')) then
    raise exception 'INVALID_TIME';
  end if;

  if not v_single and (v_after_up - v_before_up < s.proof_min_gap
                       or p_after_taken_at - p_before_taken_at < s.proof_min_gap) then
    raise exception 'TOO_FAST';
  end if;

  v_before := extensions.st_setsrid(extensions.st_makepoint(p_before_lng, p_before_lat), 4326)::extensions.geography;
  if q.location is not null and extensions.st_distance(q.location, v_before) > s.claim_radius_m then
    raise exception 'TOO_FAR';
  end if;
  if not v_single then
    v_after := extensions.st_setsrid(extensions.st_makepoint(p_after_lng, p_after_lat), 4326)::extensions.geography;
    if q.location is not null and extensions.st_distance(q.location, v_after) > s.claim_radius_m then
      raise exception 'TOO_FAR';
    end if;
    if extensions.st_distance(v_before, v_after) > s.claim_radius_m then
      raise exception 'PHOTOS_TOO_FAR_APART';
    end if;
  end if;

  if (not v_single and p_before_photo_hash = p_after_photo_hash)
     or exists (select 1 from public.quest_claims x
                where x.id <> c.id
                  and (x.before_photo_hash in (p_before_photo_hash, coalesce(p_after_photo_hash, p_before_photo_hash))
                       or x.after_photo_hash in (p_before_photo_hash, coalesce(p_after_photo_hash, p_before_photo_hash)))) then
    raise exception 'DUPLICATE_PHOTO';
  end if;

  if not v_single then
    v_diff := public.thumb_diff(p_before_thumb, p_after_thumb);
    if v_diff is not null and v_diff < 4 then raise exception 'NO_CHANGE'; end if;
  end if;

  -- 받을 보상 계산 (확인되면 지급)
  if q.kind = 'report' then
    select public.report_point_value(r.heart_count) into v_points from public.reports r where r.id = q.report_id;
  else
    v_points := q.reward_points;
  end if;
  v_xp := public.category_xp(q.category);
  v_crewish := q.kind = 'crew' or q.required_members > 1;
  select crew_id into v_crew from public.crew_members where user_id = v_uid;
  if v_crew is not null then
    v_crew_xp := v_xp * case when v_crewish then s.crew_quest_xp_multiplier else 1 end;
  end if;

  update public.quest_claims set
    status = 'submitted', submitted_at = now(),
    before_photo_url = p_before_photo_url, before_lat = p_before_lat, before_lng = p_before_lng,
    before_accuracy_m = p_before_accuracy_m, before_taken_at = p_before_taken_at, before_photo_hash = p_before_photo_hash,
    after_photo_url = p_after_photo_url, after_lat = p_after_lat, after_lng = p_after_lng,
    after_accuracy_m = p_after_accuracy_m, after_taken_at = p_after_taken_at, after_photo_hash = p_after_photo_hash,
    points_awarded = v_points, xp_awarded = v_xp, crew_xp_awarded = v_crew_xp,
    reward_label = q.reward_label
  where id = c.id;

  -- 누가 확인하나
  if q.kind = 'partner' then
    if not exists (select 1 from public.partner_members m where m.partner_id = q.partner_id) then
      perform public.to_staff_review(c.id, '업체 계정 없음');
      v_status := 'staff_review';
    end if;
  else
    v_voters := public.create_claim_votes(c.id);
    if v_voters = 0 then
      perform public.to_staff_review(c.id, '확인할 이웃 없음');
      v_status := 'staff_review';
    end if;
  end if;

  return json_build_object(
    'status', v_status, 'title', q.title,
    'points_pending', v_points, 'xp_pending', v_xp, 'crew_xp_pending', v_crew_xp,
    'reward_label', q.reward_label, 'voters', v_voters,
    'verify_deadline', now() + s.verify_timeout,
    'daily_remaining', public.my_daily_remaining());
end $$;

-- 제출 시 회원 검사 (2-12, 2-13). 승인은 투표·업체·운영진이 하므로 검사하지 않음
create or replace function public.on_claim_approving()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'submitted' and old.status <> 'submitted' then
    perform public.require_member();
  end if;
  return new;
end $$;

-- 승인 뒤: 제휴 의뢰 모집 인원 마감 (해결 확인 알림은 제출 시점에 투표로 만듦)
create or replace function public.on_claim_approved()
returns trigger language plpgsql security definer set search_path = '' as $$
declare q public.quests;
begin
  if new.status = 'approved' and old.status <> 'approved' then
    select * into q from public.quests where id = new.quest_id;
    if q.kind = 'partner' and q.capacity is not null
       and (select count(*) from public.quest_claims where quest_id = q.id and status = 'approved') >= q.capacity then
      update public.quests set status = 'done' where id = q.id;
      update public.quest_claims set status = 'cancelled' where quest_id = q.id and status = 'accepted';
    end if;
  end if;
  return new;
end $$;

-- 모집 인원: 진행 중인 인증(확인 대기·운영진 검토)도 자리를 차지
create or replace function public.on_claim_before()
returns trigger language plpgsql security definer set search_path = '' as $$
declare q public.quests;
begin
  perform public.require_member();
  select * into q from public.quests where id = new.quest_id;
  if q.kind = 'partner' and q.capacity is not null
     and (select count(*) from public.quest_claims where quest_id = q.id
          and status in ('accepted','submitted','staff_review','approved')) >= q.capacity then
    raise exception 'REPORT_FULL';
  end if;
  return new;
end $$;

create or replace function public.accept_quest(p_quest_id bigint)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); q public.quests; r public.reports; v_claim bigint; v_deadline timestamptz; v_count int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.expire_stale();
  select * into q from public.quests where id = p_quest_id for update;
  if not found then raise exception 'QUEST_NOT_FOUND'; end if;
  if q.status <> 'open' then raise exception 'QUEST_CLOSED'; end if;
  if q.kind = 'report' then
    select * into r from public.reports where id = q.report_id;
    if r.visible_at is not null and r.visible_at > now() then raise exception 'REPORT_PENDING'; end if;
    if r.hidden_at is not null then raise exception 'QUEST_CLOSED'; end if;
    if r.author_id = v_uid and q.required_members <= 1 then raise exception 'OWN_REPORT'; end if;
  end if;
  if q.kind = 'crew' and not exists (select 1 from public.crew_members m where m.crew_id = q.crew_id and m.user_id = v_uid) then
    raise exception 'NOT_CREW_MEMBER';
  end if;
  if exists (select 1 from public.quest_claims where quest_id = p_quest_id and user_id = v_uid and status = 'approved') then
    raise exception 'ALREADY_CLEARED';
  end if;
  if exists (select 1 from public.quest_claims where quest_id = p_quest_id and user_id = v_uid
             and status in ('accepted','submitted','staff_review')) then
    raise exception 'ALREADY_ACCEPTED';
  end if;
  if q.kind in ('report','crew') then
    select count(*) into v_count from public.quest_claims
      where quest_id = q.id and status in ('accepted','submitted','staff_review','approved');
    if v_count >= q.required_members then raise exception 'REPORT_FULL'; end if;
  end if;

  insert into public.quest_claims (quest_id, user_id) values (p_quest_id, v_uid)
    returning id, accepted_at + (select claim_time_limit from public.app_settings) into v_claim, v_deadline;
  select count(*) into v_count from public.quest_claims
    where quest_id = q.id and status in ('accepted','submitted','staff_review','approved');
  return json_build_object('claim_id', v_claim, 'deadline_at', v_deadline,
                           'current_members', v_count, 'required_members', q.required_members,
                           'status', case when q.kind in ('report','crew') and v_count >= q.required_members
                                          then 'in_progress' else 'open' end,
                           'daily_remaining', public.my_daily_remaining());
end $$;

-- 진행 중인 내 의뢰: 수락 중, 확인 대기, 운영진 검토, 최근 3일 반려
drop function if exists public.my_claims();
create or replace function public.my_claims()
returns table (claim_id bigint, quest_id bigint, title text, kind text, status text,
               accepted_at timestamptz, deadline_at timestamptz, submitted_at timestamptz, verify_deadline timestamptz,
               ok_percent numeric, voters int, answered int, reject_reason text,
               points_pending int, xp_pending int, lat double precision, lng double precision, address text)
language sql stable security definer set search_path = '' as $$
  select c.id, q.id, q.title, q.kind, c.status, c.accepted_at,
         c.accepted_at + s.claim_time_limit,
         c.submitted_at,
         case when c.submitted_at is not null then c.submitted_at + s.verify_timeout end,
         (select round(coalesce(sum(n.weight) filter (where n.answer = 'ok'), 0), 1)
            from public.resolve_notices n where n.claim_id = c.id),
         (select count(*)::int from public.resolve_notices n where n.claim_id = c.id),
         (select count(*)::int from public.resolve_notices n where n.claim_id = c.id and n.answer is not null),
         c.reject_reason, c.points_awarded, c.xp_awarded,
         q.lat, q.lng, q.address
  from public.quest_claims c join public.quests q on q.id = c.quest_id cross join public.app_settings s
  where c.user_id = auth.uid()
    and (c.status in ('accepted','submitted','staff_review')
         or (c.status = 'rejected' and c.decided_at > now() - interval '3 days'))
  order by coalesce(c.submitted_at, c.accepted_at) desc
$$;

-- 만료 정리 + 결론 안 난 인증은 운영진 검토로
create or replace function public.expire_stale()
returns void language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  update public.quest_claims c set status = 'expired'
    where c.status = 'accepted'
      and c.accepted_at + (select claim_time_limit from public.app_settings) < now();
  update public.quests set status = 'open'
    where status = 'scheduled' and (starts_at is null or starts_at <= now());
  update public.quests set status = 'expired'
    where status in ('open','scheduled') and expires_at is not null and expires_at < now();
  for v_id in select id from public.quest_claims
              where status = 'submitted' and submitted_at + (select verify_timeout from public.app_settings) < now() loop
    perform public.to_staff_review(v_id, '48시간 안에 확인이 끝나지 않음');
  end loop;
end $$;

-- ─────────────────────────────────────────────
-- 제휴 의뢰 인증: 업체 담당자가 확인
-- ─────────────────────────────────────────────
create or replace function public.partner_claims()
returns json language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
           'id', c.id, 'quest_id', q.id, 'title', q.title, 'user', p.nickname,
           'before', c.before_photo_url, 'after', c.after_photo_url, 'single', q.proof_mode = 'single',
           'lat', c.before_lat, 'lng', c.before_lng,
           'submitted_at', c.submitted_at, 'deadline', c.submitted_at + s.verify_timeout,
           'status', c.status, 'reject_reason', c.reject_reason, 'decided_at', c.decided_at)
         order by (c.status = 'submitted') desc, c.submitted_at desc), '[]'::json)
  from public.quest_claims c
  join public.quests q on q.id = c.quest_id
  left join public.profiles p on p.id = c.user_id
  cross join public.app_settings s
  where q.kind = 'partner' and q.partner_id = public.my_partner_id()
    and c.status in ('submitted','staff_review','approved','rejected')
    and c.submitted_at > now() - interval '30 days'
$$;

create or replace function public.partner_review_claim(p_claim_id bigint, p_approve boolean, p_reason text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_partner bigint := public.my_partner_id();
begin
  if v_partner is null then raise exception 'NOT_PARTNER'; end if;
  if not exists (select 1 from public.quest_claims c join public.quests q on q.id = c.quest_id
                 where c.id = p_claim_id and q.kind = 'partner' and q.partner_id = v_partner and c.status = 'submitted') then
    raise exception 'CLAIM_NOT_ACTIVE';
  end if;
  return public.finalize_claim(p_claim_id, p_approve, 'partner', nullif(btrim(coalesce(p_reason, '')), ''));
end $$;

-- 운영진 결정 (대시보드 SQL 에디터: select public.staff_review_claim(12, true);)
create or replace function public.staff_review_claim(p_claim_id bigint, p_approve boolean, p_reason text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  v := public.finalize_claim(p_claim_id, p_approve, 'staff', p_reason);
  if coalesce(v, '') not in ('approved','rejected') then raise exception 'CLAIM_NOT_ACTIVE'; end if;
  return v;
end $$;

-- 업체 화면 의뢰 집계에 확인 대기 수 추가
create or replace function public.partner_quest_json(p_id bigint)
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'id', q.id, 'title', q.title, 'description', q.description,
    'place_type', public.category_place(q.category), 'place_name', q.place_name, 'address', q.address,
    'proof_mode', q.proof_mode, 'reward_type', q.reward_type, 'reward_amount', q.reward_amount,
    'capacity', q.capacity,
    'starts_on', (q.starts_at at time zone 'Asia/Seoul')::date,
    'ends_on', ((q.expires_at at time zone 'Asia/Seoul') - interval '1 day')::date,
    'status', public.partner_status(q.status), 'reject_reason', q.reject_reason,
    'created_at', q.created_at,
    'joined', (select count(distinct c.user_id) from public.quest_claims c
               where c.quest_id = q.id and c.status not in ('cancelled')),
    'completed', (select count(*) from public.quest_claims c where c.quest_id = q.id and c.status = 'approved'),
    'pending', (select count(*) from public.quest_claims c where c.quest_id = q.id and c.status in ('submitted','staff_review')),
    'daily', (select json_agg(coalesce(x.n, 0) order by d.i) from generate_series(0, 6) d(i)
              left join (select (extract(isodow from c.approved_at at time zone 'Asia/Seoul')::int - 1) as i, count(*) as n
                         from public.quest_claims c
                         where c.quest_id = q.id and c.status = 'approved'
                           and c.approved_at >= (date_trunc('week', now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul'
                         group by 1) x on x.i = d.i),
    'sample', q.is_demo)
  from public.quests q where q.id = p_id
$$;

-- ─────────────────────────────────────────────
-- 5-1 크루 만들기는 레벨 3부터
-- ─────────────────────────────────────────────
create or replace function public.create_crew(p_name text, p_area text default null)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_name text := btrim(coalesce(p_name, '')); v_id bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if char_length(v_name) not between 1 and 30 then raise exception 'INVALID_NAME'; end if;
  if (select public.level_of(xp) from public.profiles where id = v_uid) < (select crew_create_level from public.app_settings) then
    raise exception 'CREW_LEVEL_TOO_LOW';
  end if;
  if exists (select 1 from public.crew_members where user_id = v_uid) then raise exception 'ALREADY_IN_CREW'; end if;
  if exists (select 1 from public.crews where lower(name) = lower(v_name)) then raise exception 'CREW_NAME_TAKEN'; end if;
  insert into public.crews (name, area, owner_id) values (v_name, nullif(btrim(coalesce(p_area, '')), ''), v_uid)
    returning id into v_id;
  insert into public.crew_members (crew_id, user_id, role) values (v_id, v_uid, 'owner');
  return v_id;
end $$;

-- ─────────────────────────────────────────────
-- 5-3 도전과제 보상 받기, 5-4 칭호 (레벨 칭호는 2부터)
-- ─────────────────────────────────────────────
create or replace function public.feat_value(p_user uuid, p_metric text)
returns int language plpgsql stable security definer set search_path = '' as $$
declare v_st json;
begin
  if p_metric = 'streak' then return public.streak_weeks(p_user); end if;
  if p_metric = 'crew' then return (select count(*) from public.crew_members where user_id = p_user)::int; end if;
  v_st := public.user_stats(p_user);
  if p_metric in ('places','issues') then return (select count(*) from json_object_keys(v_st -> p_metric))::int; end if;
  return coalesce((v_st ->> p_metric)::int, 0);
end $$;

create or replace function public.claim_feat(p_id text)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); a public.achievements; v_old int; v_new int; g public.cosmetics;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public.require_member();
  select * into a from public.achievements where id = p_id;
  if not found then raise exception 'FEAT_NOT_FOUND'; end if;
  perform pg_advisory_xact_lock(hashtext('feat:' || v_uid::text));
  if exists (select 1 from public.user_feats where user_id = v_uid and feat_id = a.id) then raise exception 'FEAT_CLAIMED'; end if;
  if public.feat_value(v_uid, a.metric) < a.goal then raise exception 'FEAT_NOT_DONE'; end if;
  select public.level_of(xp) into v_old from public.profiles where id = v_uid;
  insert into public.user_feats (user_id, feat_id) values (v_uid, a.id);
  if a.points > 0 or a.xp > 0 then
    perform public.credit_points(v_uid, a.points, a.xp, 0, 'feat_reward');
  end if;
  select * into g from public.cosmetics where feat = a.id limit 1;
  if g.id is not null then
    insert into public.user_cosmetics (user_id, cosmetic_id) values (v_uid, g.id) on conflict do nothing;
  end if;
  select public.level_of(xp) into v_new from public.profiles where id = v_uid;
  return json_build_object('points_gained', a.points, 'xp_gained', a.xp, 'cosmetic', g.name,
                           'leveled_up', v_new > v_old, 'level', v_new);
end $$;

create or replace function public.set_title(p_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_level int; a public.achievements; v_min int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_key is null or p_key = '' then
    update public.profiles set title_key = null where id = v_uid;
    return;
  end if;
  select public.level_of(xp) into v_level from public.profiles where id = v_uid;
  if p_key like 'lv:%' then
    v_min := nullif(regexp_replace(p_key, '^lv:(\d+)$', '\1'), p_key)::int;
    if v_min is null or v_min not in (2,3,4,5,6,7,8,9,10,12,15,20) then raise exception 'INVALID_INPUT'; end if;
    if v_level < v_min then raise exception 'TITLE_LOCKED'; end if;
  elsif p_key like 'ach:%' then
    select * into a from public.achievements where id = substr(p_key, 5);
    if not found then raise exception 'INVALID_INPUT'; end if;
    if public.feat_value(v_uid, a.metric) < a.goal then raise exception 'TITLE_LOCKED'; end if;
  else
    raise exception 'INVALID_INPUT';
  end if;
  update public.profiles set title_key = p_key where id = v_uid;
end $$;
update public.profiles set title_key = null where title_key = 'lv:1';

-- 도전과제 품목은 받아야 내 것 (살 수 없음)
drop function if exists public.cosmetics_list();
create or replace function public.cosmetics_list()
returns table (id text, kind text, name text, style text, colors text[], cost int, level int,
               owned boolean, locked boolean, equipped boolean, feat text)
language sql stable security definer set search_path = '' as $$
  with me as (
    select p.id as uid, public.level_of(p.xp) as lv, p.frame_id, p.name_color_id
    from public.profiles p where p.id = auth.uid()
  )
  select c.id, c.kind, c.name, c.style, c.colors, c.cost, c.level,
         case when c.feat is not null or c.cost > 0
              then exists (select 1 from public.user_cosmetics u where u.user_id = me.uid and u.cosmetic_id = c.id)
              else coalesce(me.lv, 1) >= c.level end,
         coalesce(me.lv, 1) < c.level
           or (c.feat is not null and not exists (select 1 from public.user_cosmetics u where u.user_id = me.uid and u.cosmetic_id = c.id)),
         coalesce(case c.kind when 'frame' then me.frame_id = c.id else me.name_color_id = c.id end, false),
         c.feat
  from public.cosmetics c left join me on true
  order by c.kind, c.sort, c.id
$$;

create or replace function public.equip_cosmetic(p_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); c public.cosmetics; v_level int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into c from public.cosmetics where id = p_id;
  if not found then raise exception 'COSMETIC_NOT_FOUND'; end if;
  select public.level_of(xp) into v_level from public.profiles where id = v_uid;
  if v_level < c.level
     or ((c.cost > 0 or c.feat is not null)
         and not exists (select 1 from public.user_cosmetics where user_id = v_uid and cosmetic_id = c.id)) then
    raise exception 'LEVEL_TOO_LOW';
  end if;
  if c.kind = 'frame' then
    update public.profiles set frame_id = c.id where id = v_uid;
  else
    update public.profiles set name_color_id = c.id where id = v_uid;
  end if;
end $$;

create or replace function public.buy_cosmetic(p_id text)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); c public.cosmetics; p public.profiles;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  select * into c from public.cosmetics where id = p_id;
  if not found then raise exception 'COSMETIC_NOT_FOUND'; end if;
  select * into p from public.profiles where id = v_uid for update;
  if public.level_of(p.xp) < c.level
     or (c.feat is not null and not exists (select 1 from public.user_cosmetics where user_id = v_uid and cosmetic_id = c.id)) then
    raise exception 'LEVEL_TOO_LOW';
  end if;
  if c.cost > 0 and not exists (select 1 from public.user_cosmetics where user_id = v_uid and cosmetic_id = c.id) then
    if p.points < c.cost then raise exception 'NOT_ENOUGH_POINTS'; end if;
    insert into public.user_cosmetics (user_id, cosmetic_id) values (v_uid, c.id);
    perform public.credit_points(v_uid, -c.cost, 0, 0, 'cosmetic_buy');
  end if;
  perform public.equip_cosmetic(c.id);
  select * into p from public.profiles where id = v_uid;
  return json_build_object('points', p.points, 'frame', public.look_of(p.frame_id, p.name_color_id) -> 'frame',
                           'name_color', public.look_of(p.frame_id, p.name_color_id) ->> 'name_color');
end $$;

-- 내 정보: feats_claimed, 오늘 완료 수는 제출 기준, 확인 대기 수
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
    where user_id = v_uid and status in ('submitted','staff_review','approved')
      and coalesce(submitted_at, approved_at) >= public.kst_today_start();
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
    'pending_count', (select count(*) from public.quest_claims where user_id = v_uid and status in ('submitted','staff_review')),
    'completed_count', v_completed,
    'streak_weeks', public.streak_weeks(v_uid),
    'active_this_week', exists (select 1 from public.quest_claims where user_id = v_uid and status = 'approved'
                                and approved_at >= v_week::timestamp at time zone 'Asia/Seoul'),
    'weekly', (select json_agg(coalesce(x.n, 0) order by w.i) from generate_series(0, 7) w(i)
               left join (select date_trunc('week', approved_at at time zone 'Asia/Seoul')::date as wk, count(*) as n
                          from public.quest_claims where user_id = v_uid and status = 'approved'
                            and approved_at >= (v_week - 49)::timestamp at time zone 'Asia/Seoul'
                          group by 1) x on x.wk = v_week - (7 - w.i) * 7),
    'stats', public.user_stats(v_uid),
    'feats_claimed', coalesce((select json_agg(feat_id order by claimed_at) from public.user_feats where user_id = v_uid), '[]'::json),
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

-- 의뢰판 인원 표시: 확인 대기 중인 인증도 자리를 차지
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
         (select count(*)::int from public.quest_claims c where c.quest_id = q.id and c.status in ('accepted','submitted','staff_review','approved')),
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


-- 운영진 확인 목록에 인증 검토 추가
drop view public.staff_attention;
create view public.staff_attention with (security_invoker = true) as
  select 'claim_review'::text as kind, c.id, q.title, c.submitted_at as at, 1::bigint as count
  from public.quest_claims c join public.quests q on q.id = c.quest_id where c.status = 'staff_review'
  union all
  select 'hidden_report', r.id, r.title, r.hidden_at,
         (select count(*) from public.report_flags f where f.report_id = r.id and f.status = 'pending')
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
grant execute on function public.partner_claims() to authenticated;
grant execute on function public.partner_review_claim(bigint, boolean, text) to authenticated;
grant execute on function public.save_consent(jsonb, text) to authenticated;
grant execute on function public.my_consent() to authenticated;
grant execute on function public.set_mark(bigint, text) to authenticated;
grant execute on function public.my_notices() to authenticated;
grant execute on function public.answer_notice(bigint, text) to authenticated;
grant execute on function public.flag_report(bigint, text) to authenticated;
grant execute on function public.flag_avatar(uuid, text) to authenticated;
grant execute on function public.set_title(text) to authenticated;
grant execute on function public.claim_feat(text) to authenticated;
