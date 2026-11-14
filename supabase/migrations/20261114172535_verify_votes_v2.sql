-- 인증 확인 방식 수정 (장연우 결정 2026-11-15 02:23)
-- 1. 주민 제보: 올린 사람 40% + 하트 누른 사람 30%(나눔) + 의뢰와 관련 없는 이웃 30%(무작위 3명, 나눔)
--    '치워졌어요' 합계 50% 이상이면 승인, 아니면 반려. 올린 사람 표만으로 바로 반려하지 않음.
--    (비율 나눔은 20261114172735 에서 고정 비율로 바뀜)
--    48시간이 지나면 그때까지의 결과로 결정(50% 이상 승인, 아니면 반려).
-- 2. 해결한 본인은 투표에서 제외 (그대로)
-- 3. 크루 의뢰: 크루장 50% + 의뢰를 올린 사람 50%. 같은 사람이면 그 사람 100%. 둘 다 해결자 본인이면 운영진 검토.
-- 4. 제휴 의뢰: 판단 기한 없음. 업체가 반드시 판단(48시간 운영진 넘김 없음).
-- 5. 하루 3개 상한: 제출 시점 기준 (그대로)

alter table public.app_settings
  add column verify_w_author numeric not null default 40,
  add column verify_w_heart numeric not null default 30,
  add column verify_w_random numeric not null default 30,
  add column verify_random_count int not null default 3;   -- 무작위 이웃 수 (임시)
update public.app_settings set verify_threshold = 50;

alter table public.resolve_notices drop constraint resolve_notices_role_check;
alter table public.resolve_notices add constraint resolve_notices_role_check
  check (role in ('author','heart','random','owner','crew'));

-- 투표할 사람 만들기
create or replace function public.create_claim_votes(p_claim bigint)
returns int language plpgsql security definer set search_path = '' as $$
declare
  c public.quest_claims; q public.quests; s public.app_settings;
  v_author uuid; v_owner uuid; v_hearts uuid[] := '{}'; v_random uuid[] := '{}';
  w_a numeric := 0; w_h numeric := 0; w_r numeric := 0; w_o numeric := 0; v_total numeric;
  v_solver text; v_report bigint; v_n int;
begin
  select * into c from public.quest_claims where id = p_claim;
  select * into q from public.quests where id = c.quest_id;
  select * into s from public.app_settings;
  select nickname into v_solver from public.profiles where id = c.user_id;

  if q.kind = 'report' then
    v_report := q.report_id;
    select author_id into v_author from public.reports where id = q.report_id;
    if v_author = c.user_id then v_author := null; end if;
    select coalesce(array_agg(h.user_id), '{}') into v_hearts from public.report_hearts h
      where h.report_id = q.report_id and h.user_id <> c.user_id and h.user_id is distinct from v_author;
    -- 의뢰와 관련 없는 이웃: 익명이 아니고, 필수 동의를 했고, 최근 30일 안에 로그인한 사람 중 무작위
    select coalesce(array_agg(x.id), '{}') into v_random from (
      select p.id from public.profiles p join auth.users u on u.id = p.id
      where p.id <> c.user_id and p.id is distinct from v_author and not (p.id = any(v_hearts))
        and not coalesce(u.is_anonymous, false)
        and coalesce(u.last_sign_in_at, u.created_at) > now() - interval '30 days'
        and public.has_required_consent(p.id)
      order by random() limit s.verify_random_count) x;
    w_a := case when v_author is null then 0 else s.verify_w_author end;
    w_h := case when cardinality(v_hearts) = 0 then 0 else s.verify_w_heart end;
    w_r := case when cardinality(v_random) = 0 then 0 else s.verify_w_random end;
  elsif q.kind = 'crew' then
    v_author := q.requester_id;
    select owner_id into v_owner from public.crews where id = q.crew_id;
    if v_owner = v_author then v_owner := null; end if;
    if v_author = c.user_id then v_author := null; end if;
    if v_owner = c.user_id then v_owner := null; end if;
    w_a := case when v_author is null then 0 else 50 end;
    w_o := case when v_owner is null then 0 else 50 end;
  else
    return 0;
  end if;

  v_total := w_a + w_h + w_r + w_o;
  if v_total = 0 then return 0; end if;

  insert into public.resolve_notices (user_id, report_id, quest_id, claim_id, title, solver,
                                      before_path, after_path, single, role, weight)
  select x.uid, v_report, q.id, c.id, q.title, coalesce(v_solver, ''),
         c.before_photo_url, c.after_photo_url, q.proof_mode = 'single', x.role, x.w
  from (
    select v_author as uid, 'author' as role, w_a * 100 / v_total as w where v_author is not null
    union all
    select v_owner, 'owner', w_o * 100 / v_total where v_owner is not null
    union all
    select h, 'heart', w_h * 100 / v_total / cardinality(v_hearts) from unnest(v_hearts) h
    union all
    select r, 'random', w_r * 100 / v_total / cardinality(v_random) from unnest(v_random) r
  ) x
  on conflict (user_id, claim_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- 집계: 50% 이상이면 승인, 남은 표를 다 받아도 못 넘으면 반려. p_final 이면 지금 결과로 결정(기한 만료).
drop function if exists public.evaluate_claim(bigint);
create or replace function public.evaluate_claim(p_claim bigint, p_final boolean default false)
returns text language plpgsql security definer set search_path = '' as $$
declare v_ok numeric; v_pending numeric; v_th numeric; v_status text;
begin
  select status into v_status from public.quest_claims where id = p_claim;
  if v_status is distinct from 'submitted' then return v_status; end if;
  select coalesce(sum(weight) filter (where answer = 'ok'), 0),
         coalesce(sum(weight) filter (where answer is null), 0)
    into v_ok, v_pending
    from public.resolve_notices where claim_id = p_claim;
  v_th := (select verify_threshold from public.app_settings);
  if v_ok >= v_th - 0.0001 then
    return public.finalize_claim(p_claim, true, 'vote');
  elsif p_final or v_ok + v_pending < v_th - 0.0001 then
    return public.finalize_claim(p_claim, false, 'vote', '이웃 확인에서 "치워졌어요"가 절반을 넘지 못했어요');
  end if;
  return 'submitted';
end $$;

-- 만료 정리: 투표 인증은 48시간이 지나면 그때 결과로 결정. 제휴 의뢰는 기한 없음.
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
  for v_id in select c.id from public.quest_claims c join public.quests q on q.id = c.quest_id
              where c.status = 'submitted' and q.kind in ('report','crew')
                and c.submitted_at + (select verify_timeout from public.app_settings) < now() loop
    perform public.evaluate_claim(v_id, true);
  end loop;
end $$;

-- 진행 중인 내 의뢰: 기한은 투표 인증만
create or replace function public.my_claims()
returns table (claim_id bigint, quest_id bigint, title text, kind text, status text,
               accepted_at timestamptz, deadline_at timestamptz, submitted_at timestamptz, verify_deadline timestamptz,
               ok_percent numeric, voters int, answered int, reject_reason text,
               points_pending int, xp_pending int, lat double precision, lng double precision, address text)
language sql stable security definer set search_path = '' as $$
  select c.id, q.id, q.title, q.kind, c.status, c.accepted_at,
         c.accepted_at + s.claim_time_limit,
         c.submitted_at,
         case when c.submitted_at is not null and q.kind in ('report','crew') then c.submitted_at + s.verify_timeout end,
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

-- 업체 화면: 기한 없음
create or replace function public.partner_claims()
returns json language sql stable security definer set search_path = '' as $$
  select coalesce(json_agg(json_build_object(
           'id', c.id, 'quest_id', q.id, 'title', q.title, 'user', p.nickname,
           'before', c.before_photo_url, 'after', c.after_photo_url, 'single', q.proof_mode = 'single',
           'lat', c.before_lat, 'lng', c.before_lng,
           'submitted_at', c.submitted_at,
           'status', c.status, 'reject_reason', c.reject_reason, 'decided_at', c.decided_at)
         order by (c.status = 'submitted') desc, c.submitted_at desc), '[]'::json)
  from public.quest_claims c
  join public.quests q on q.id = c.quest_id
  left join public.profiles p on p.id = c.user_id
  where q.kind = 'partner' and q.partner_id = public.my_partner_id()
    and c.status in ('submitted','staff_review','approved','rejected')
    and c.submitted_at > now() - interval '30 days'
$$;

revoke execute on function public.evaluate_claim(bigint, boolean) from public, anon, authenticated;
