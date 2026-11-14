-- 빈 그룹이 있을 때 0으로 나누는 오류 수정
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
    select h, 'heart', w_h * 100 / v_total / nullif(cardinality(v_hearts), 0) from unnest(v_hearts) h
    union all
    select r, 'random', w_r * 100 / v_total / nullif(cardinality(v_random), 0) from unnest(v_random) r
  ) x
  on conflict (user_id, claim_id) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
