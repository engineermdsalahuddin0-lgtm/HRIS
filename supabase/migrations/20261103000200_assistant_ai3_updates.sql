-- =============================================================================
-- AI assistant AI3: the widget's config and the Updates digest.
-- Design: docs/Part04Architecture.md (sections 5.2, 8.3, 12).
--
-- assistant_my_config: is the assistant on for me, greeting, suggestions,
-- notice, questions left today, and whether Ask can work (keys tested, plan,
-- something indexed). Updates never need a key (D1).
-- assistant_updates: short items built from the same tables the dashboard
-- uses, kept only for topics allowed to my role (tick AND permission). Counts
-- and statuses only: no amounts, no other people's names. The model receives
-- exactly this list as text (AI5), nothing else from the business tables.
-- Plans (D5): Ask on TRIAL, PRO and ENTERPRISE (the trial tries everything);
-- Updates on every plan.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.assistant_settings') is null then
    raise exception 'Apply 20261103000100_assistant_ai1_foundation.sql first, then run this file again';
  end if;
end;
$guard$;

create or replace function private.assistant_plan_allows_ask(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.code in ('TRIAL', 'PRO', 'ENTERPRISE') and s.status in ('trial', 'active', 'past_due')
    from public.org_subscriptions s join public.platform_plans p on p.id = s.plan_id
    where s.org_id = p_org_id), false)
$$;

-- Readable for this role: ready, topic allowed, audience empty or containing the role.
create or replace function private.assistant_can_read_resource(r public.assistant_resources, p_role_id uuid, p_allowed text[])
returns boolean
language sql
stable
set search_path = ''
as $$
  select r.status = 'ready' and r.topic_key = any (p_allowed)
     and (cardinality(r.audience_role_ids) = 0 or p_role_id = any (r.audience_role_ids)
          or exists (select 1 from public.roles x where x.id = p_role_id and x.system_key = 'admin'))
$$;

create or replace function private.assistant_questions_today(p_user_id uuid, p_org_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer from public.assistant_query_log q
  where q.user_id = p_user_id and q.org_id = p_org_id
    and (q.asked_at at time zone (select timezone from public.organizations where id = p_org_id))::date = private.org_today(p_org_id)
$$;

-- The digest for the caller (also used by the answer step in AI5).
create or replace function private.assistant_digest()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_me      uuid := private.current_employee_id();
  v_role    uuid := private.current_role_id();
  v_allowed text[] := private.assistant_allowed_topics(private.current_role_id());
  v_today   date;
  v_items   jsonb := '[]'::jsonb;
  v_rec     public.attendance_records;
  v_off     smallint[];
  v_n1      integer;
  v_n2      integer;
  v_n3      integer;
  v_text    text;
  v_month   date;
  v_status  text;
  r         record;
begin
  if v_org is null then
    return '[]'::jsonb;
  end if;
  v_today := private.org_today(v_org);

  if 'up.my_day' = any (v_allowed) and v_me is not null then
    select * into v_rec from public.attendance_records where employee_id = v_me and work_date = v_today;
    v_off := coalesce((select weekly_off_days from public.org_work_settings where org_id = v_org), '{5}');
    if v_rec.check_in_at is not null then
      v_items := v_items || jsonb_build_object('key', 'my_day', 'topic', 'up.my_day',
        'title', 'You checked in at ' || to_char(v_rec.check_in_at at time zone (select timezone from public.organizations where id = v_org), 'HH24:MI'),
        'detail', case when v_rec.is_late then 'Late by ' || v_rec.late_minutes || ' min' else 'On time' end,
        'link', '/attendance/me', 'tone', case when v_rec.is_late then 'action' else 'good' end);
    elsif extract(dow from v_today)::smallint <> all (v_off)
          and not exists (select 1 from public.holidays h where h.org_id = v_org and h.date = v_today and h.status = 'active')
          and coalesce(v_rec.status, '') not in ('on_leave', 'holiday', 'weekend') then
      v_items := v_items || jsonb_build_object('key', 'my_day', 'topic', 'up.my_day', 'title', 'You have not checked in today',
        'detail', 'Open My attendance to check in', 'link', '/attendance/me', 'tone', 'action');
    end if;
  end if;

  if 'up.my_leave' = any (v_allowed) and v_me is not null then
    select string_agg(lt.code || ' ' || trim(to_char(greatest(b.entitled + b.carried_forward - b.used - b.pending, 0), 'FM999990.0')), ' · ' order by lt.code)
      into v_text
    from public.leave_balances b join public.leave_types lt on lt.id = b.leave_type_id
    where b.employee_id = v_me and b.year = extract(year from v_today)::int and lt.days_per_year is not null;
    select count(*) into v_n1 from public.leave_requests where employee_id = v_me and status = 'pending';
    if v_text is not null or v_n1 > 0 then
      v_items := v_items || jsonb_build_object('key', 'my_leave', 'topic', 'up.my_leave',
        'title', coalesce('Leave left: ' || v_text, 'Your leave'),
        'detail', case when v_n1 > 0 then v_n1 || ' request' || case when v_n1 = 1 then '' else 's' end || ' waiting for approval' else 'No pending requests' end,
        'link', '/leave', 'tone', 'info');
    end if;
  end if;

  if 'up.my_payslip' = any (v_allowed) and v_me is not null then
    select s.period_month into v_month from public.payroll_slips s join public.payroll_runs pr on pr.id = s.run_id
    where s.employee_id = v_me and pr.status in ('approved', 'paid', 'locked') and s.period_month >= v_today - 62
    order by s.period_month desc limit 1;
    if v_month is not null then
      v_items := v_items || jsonb_build_object('key', 'my_payslip', 'topic', 'up.my_payslip',
        'title', 'Your ' || to_char(v_month, 'FMMonth YYYY') || ' payslip is ready', 'detail', 'Open it to see the details',
        'link', '/payslips', 'tone', 'good');
    end if;
  end if;

  if 'up.team_today' = any (v_allowed) then
    select count(*) filter (where a.status in ('present', 'late', 'half_day', 'early_out')),
           count(*) filter (where a.is_late), count(*) filter (where a.status = 'absent')
      into v_n1, v_n2, v_n3
    from public.attendance_records a
    where a.org_id = v_org and a.work_date = v_today
      and (private.has_permission('attendance.view_all') or a.employee_id in (select private.team_employee_ids()));
    v_items := v_items || jsonb_build_object('key', 'team_today', 'topic', 'up.team_today',
      'title', case when private.has_permission('attendance.view_all') then 'Today: ' else 'Team today: ' end || v_n1 || ' present',
      'detail', v_n2 || ' late · ' || v_n3 || ' absent', 'link', '/attendance', 'tone', case when v_n3 > 0 then 'action' else 'info' end);
  end if;

  if 'up.approvals' = any (v_allowed) and v_me is not null then
    v_n1 := case when private.has_permission('leave.approve')
                 then (select count(*) from public.leave_requests where org_id = v_org and status = 'pending' and approver_employee_id = v_me) else 0 end;
    v_n2 := case when private.has_permission('overtime.approve')
                 then (select count(*) from public.overtime_records o where o.org_id = v_org and o.status = 'pending'
                         and o.employee_id <> v_me and o.employee_id in (select private.team_employee_ids())) else 0 end;
    v_n3 := case when private.has_permission('swaps.approve')
                 then (select count(*) from public.shift_swaps s where s.org_id = v_org and s.status = 'peer_accepted'
                         and s.requester_employee_id in (select private.team_employee_ids())) else 0 end;
    if v_n1 + v_n2 + v_n3 > 0 then
      v_items := v_items || jsonb_build_object('key', 'approvals', 'topic', 'up.approvals',
        'title', (v_n1 + v_n2 + v_n3) || ' request' || case when v_n1 + v_n2 + v_n3 = 1 then '' else 's' end || ' wait for you',
        'detail', concat_ws(' · ', case when v_n1 > 0 then v_n1 || ' leave' end, case when v_n2 > 0 then v_n2 || ' overtime' end,
                                   case when v_n3 > 0 then v_n3 || ' shift swap' || case when v_n3 = 1 then '' else 's' end end),
        'link', case when v_n1 > 0 then '/leave' when v_n2 > 0 then '/overtime' else '/attendance' end, 'tone', 'action');
    end if;
  end if;

  if 'up.headcount' = any (v_allowed) then
    select count(*) filter (where status = 'active'), count(*) filter (where status = 'active' and join_date >= date_trunc('month', v_today)::date)
      into v_n1, v_n2 from public.employees where org_id = v_org;
    v_items := v_items || jsonb_build_object('key', 'headcount', 'topic', 'up.headcount', 'title', v_n1 || ' active employees',
      'detail', v_n2 || ' joined this month', 'link', '/employees', 'tone', 'info');
  end if;

  if 'up.payroll_status' = any (v_allowed) then
    select period_month, status into v_month, v_status from public.payroll_runs
    where org_id = v_org and status <> 'cancelled' order by period_month desc, created_at desc limit 1;
    if v_month is not null then
      v_items := v_items || jsonb_build_object('key', 'payroll', 'topic', 'up.payroll_status',
        'title', to_char(v_month, 'FMMonth YYYY') || ' payroll: ' || v_status, 'detail', 'Status only; open the run for figures',
        'link', '/payroll', 'tone', case when v_status = 'locked' then 'good' else 'action' end);
    end if;
  end if;

  if 'up.hiring' = any (v_allowed) then
    select count(*) into v_n1 from public.vacancies where org_id = v_org and status = 'approved';
    select count(*) into v_n2 from public.applicants where org_id = v_org and status = 'applied' and purged_at is null;
    v_items := v_items || jsonb_build_object('key', 'hiring', 'topic', 'up.hiring',
      'title', v_n1 || ' open ' || case when v_n1 = 1 then 'vacancy' else 'vacancies' end,
      'detail', v_n2 || ' applicant' || case when v_n2 = 1 then '' else 's' end || ' waiting for screening', 'link', '/job-posts', 'tone', 'info');
  end if;

  if 'up.new_resources' = any (v_allowed) then
    for r in
      select x.id, x.name from public.assistant_resources x
      where x.org_id = v_org and x.updated_at > now() - interval '14 days' and private.assistant_can_read_resource(x, v_role, v_allowed)
      order by x.updated_at desc limit 3
    loop
      v_items := v_items || jsonb_build_object('key', 'res_' || r.id, 'topic', 'up.new_resources', 'title', 'New: ' || r.name,
        'detail', 'Ask me anything about it', 'link', '', 'tone', 'info');
    end loop;
  end if;
  return v_items;
end;
$$;

-- -----------------------------------------------------------------------------
-- API (everyone)
-- -----------------------------------------------------------------------------
create or replace function public.assistant_my_config()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_role  uuid := private.current_role_id();
  s       public.assistant_settings;
  rs      public.assistant_role_settings;
  e       record;
  v_used  integer;
  v_chat  boolean;
  v_why   text;
  v_month integer;
begin
  if v_org is null then
    return jsonb_build_object('enabled', false);
  end if;
  perform private.seed_assistant_defaults(v_org);
  select * into s from public.assistant_settings where org_id = v_org;
  select * into rs from public.assistant_role_settings where role_id = v_role;
  select * into e from private.assistant_embed_source(v_org);
  v_used := private.assistant_questions_today(auth.uid(), v_org);
  v_chat := exists (select 1 from public.org_integrations where org_id = v_org and kind = 'assistant_chat' and test_status = 'ok' and secret_enc is not null);
  v_month := coalesce((select sum(tokens_in + tokens_out) from public.assistant_query_log
                       where org_id = v_org and asked_at >= date_trunc('month', now())), 0);
  v_why := case
    when not private.assistant_plan_allows_ask(v_org) then 'Asking questions needs the Professional or Enterprise plan. Updates still work.'
    when not v_chat or not coalesce(e.ready, false) then 'The company has not connected its AI keys yet. Updates still work.'
    when not exists (select 1 from public.assistant_chunks c where c.org_id = v_org) then 'Nothing is indexed yet. HR is setting up the assistant.'
    when s.monthly_token_cap is not null and v_month >= s.monthly_token_cap then 'The company''s monthly AI limit is reached.'
  end;
  return jsonb_build_object(
    'enabled', s.enabled and coalesce(rs.enabled, false),
    'name', s.name, 'language_mode', s.language_mode,
    'greeting', rs.greeting, 'suggestions', to_jsonb(rs.suggestions), 'notice', rs.notice, 'not_allowed', rs.not_allowed_message,
    'daily_limit', rs.daily_limit, 'used_today', v_used,
    'left', case when rs.daily_limit is null then null else greatest(rs.daily_limit - v_used, 0) end,
    'can_ask', v_why is null, 'ask_blocked_reason', v_why);
end;
$$;

-- Volatile: it may seed defaults for a new company.
create or replace function public.assistant_updates()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if v_org is null then
    return '[]'::jsonb;
  end if;
  perform private.seed_assistant_defaults(v_org);
  return private.assistant_digest();
end;
$$;

revoke all on function public.assistant_my_config(), public.assistant_updates() from public, anon;
grant execute on function public.assistant_my_config(), public.assistant_updates() to authenticated;
revoke all on function
  private.assistant_plan_allows_ask(uuid), private.assistant_can_read_resource(public.assistant_resources, uuid, text[]),
  private.assistant_questions_today(uuid, uuid), private.assistant_digest()
from public, anon, authenticated;
