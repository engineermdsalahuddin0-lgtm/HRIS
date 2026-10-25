-- =============================================================================
-- Onboarding process R1 golden tests: workload, headcount, vacancies.
-- Expected numbers were worked out by hand first (architecture.md section 6).
--
-- A. The 10 demo cases (capacity 200 h per person, sustain 2 months):
--    1 Sewing 10,800 h / 50 -> 1.08 watch, need 54, gap 4, vacancy 5 -> backfill 4, hold 1
--    2 Cutting 2,400 / 10, 2nd month -> 1.20 overload, need 12 -> new +2
--    3 Quality 3,150 / 15 -> 1.05, gap 0.75, vacancy 1 -> backfill 1
--    4 Finishing 4,200 / 25 -> 0.84 underloaded, gap -4 -> hold 2
--    5 Accounts 1,800 / 8, 2nd month -> 1.125, need 9 = sanctioned -> backfill 1, new 0
--    6 HR 1,700 (850 / 100 x 200) / 6 -> 1.417 critical, need 8.5 -> backfill 2, new +1
--    7 Sales 2,640 / 12, 1st month -> 1.10 overload not sustained -> watch only
--    8 Customer service 1,500 / 6 -> 1.25 critical -> backfill 2; attrition 2 / 7 = 28.6 %
--    9 IT 1,000 / 5 -> 1.00 balanced
--   10 Store 2,400 / 10, 2nd month, seat 18,000, budget left 25,000 -> 1 ok, 1 blocked
-- B. Real data (company Alpha, capacity 200 h, availability fixed 100 %):
--    Sewing: 6 operators sanctioned, pay 10,000 each, budget 60,000; S6 leaves 20 Aug
--      -> replacement drafted at once. Aug: 4,800 pcs x 15 min = 1,200 h / 5 people
--      = 1.20 overload (1st month), backfill 1 (already drafted), budget left 10,000
--      -> ok. Attrition 1 / ((6 + 6 + 5) / 3 = 5.67) = 17.6 %.
--      Sep: 5,600 x 15 = 1,400 h -> 1.40 critical, need 7 -> new position +1;
--      2 seats, budget fits 1 -> the new position is drafted budget blocked.
--    Accounts: 1,200 vouchers x 15 min = 300 h / 2 people = 0.75 underloaded.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R1 WORKFORCE CHECKS PASSED".
-- =============================================================================
begin;

-- ======================================================= A. the calculation
do $$
declare
  f jsonb;
  v_bands jsonb := '{"underload":0.85,"watch":1.00,"overload":1.10,"critical":1.25,"sustain_months":2,"attrition_flag_percent":20}';
begin
  f := private.workload_figures(jsonb_build_object('demand_hours', 10800, 'capacity_per_fte', 200, 'active', 50,
                                                   'sanctioned', 55, 'separations', 3, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.08 and f ->> 'band' = 'watch', 'case 1 index ' || f::text;
  assert (f ->> 'required_fte')::numeric = 54 and (f ->> 'gap')::numeric = 4, 'case 1 gap';
  assert (f ->> 'backfill_seats')::int = 4 and (f ->> 'hold_seats')::int = 1 and (f ->> 'new_positions')::int = 0, 'case 1 seats';
  assert f ->> 'action' = 'hire', 'case 1 action';

  f := private.workload_figures(jsonb_build_object('demand_hours', 2400, 'capacity_per_fte', 200, 'active', 10,
                                                   'sanctioned', 10, 'prior_overload_months', 1, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.2 and f ->> 'band' = 'overload' and (f ->> 'overload_rule')::boolean, 'case 2 rule';
  assert (f ->> 'new_positions')::int = 2 and (f ->> 'backfill_seats')::int = 0, 'case 2 seats';

  f := private.workload_figures(jsonb_build_object('demand_hours', 3150, 'capacity_per_fte', 200, 'active', 15,
                                                   'sanctioned', 16, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.05 and (f ->> 'gap')::numeric = 0.75 and (f ->> 'backfill_seats')::int = 1, 'case 3';

  f := private.workload_figures(jsonb_build_object('demand_hours', 4200, 'capacity_per_fte', 200, 'active', 25,
                                                   'sanctioned', 27, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 0.84 and f ->> 'band' = 'underloaded', 'case 4 band';
  assert (f ->> 'gap')::numeric = -4 and (f ->> 'backfill_seats')::int = 0 and (f ->> 'hold_seats')::int = 2
         and f ->> 'action' = 'hold', 'case 4 hold';

  f := private.workload_figures(jsonb_build_object('demand_hours', 1800, 'capacity_per_fte', 200, 'active', 8,
                                                   'sanctioned', 9, 'prior_overload_months', 1, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.125 and (f ->> 'overload_rule')::boolean, 'case 5 rule';
  assert (f ->> 'backfill_seats')::int = 1 and (f ->> 'new_positions')::int = 0, 'case 5 seats';

  f := private.workload_figures(jsonb_build_object('demand_hours', 850.0 / 100 * 200, 'capacity_per_fte', 200, 'active', 6,
                                                   'sanctioned', 8, 'separations', 1, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.417 and f ->> 'band' = 'critical', 'case 6 band';
  assert (f ->> 'required_fte')::numeric = 8.5 and (f ->> 'backfill_seats')::int = 2 and (f ->> 'new_positions')::int = 1, 'case 6 seats';

  f := private.workload_figures(jsonb_build_object('demand_hours', 2640, 'capacity_per_fte', 200, 'active', 12,
                                                   'sanctioned', 12, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.1 and f ->> 'band' = 'overload' and not (f ->> 'overload_rule')::boolean, 'case 7 rule';
  assert (f ->> 'seats_total')::int = 0 and f ->> 'action' = 'watch', 'case 7 watch';

  f := private.workload_figures(jsonb_build_object('demand_hours', (9000 * 6 + 3000 * 12) / 60.0, 'capacity_per_fte', 200,
                                                   'active', 6, 'sanctioned', 8, 'separations', 2, 'avg_headcount', 7,
                                                   'bands', v_bands));
  assert (f ->> 'index')::numeric = 1.25 and f ->> 'band' = 'critical', 'case 8 band';
  assert (f ->> 'backfill_seats')::int = 2 and (f ->> 'new_positions')::int = 0, 'case 8 seats';
  assert (f ->> 'attrition_percent')::numeric = 28.6 and (f ->> 'attrition_flag')::boolean, 'case 8 attrition';

  f := private.workload_figures(jsonb_build_object('demand_hours', 1000, 'capacity_per_fte', 200, 'active', 5,
                                                   'sanctioned', 5, 'bands', v_bands));
  assert (f ->> 'index')::numeric = 1 and f ->> 'band' = 'balanced' and f ->> 'action' = 'balanced', 'case 9';

  f := private.workload_figures(jsonb_build_object('demand_hours', 2400, 'capacity_per_fte', 200, 'active', 10,
                                                   'sanctioned', 12, 'prior_overload_months', 1, 'cost_per_seat', 18000,
                                                   'budget_remaining', 25000, 'bands', v_bands));
  assert (f ->> 'backfill_seats')::int = 2 and (f ->> 'new_positions')::int = 0, 'case 10 seats';
  assert f ->> 'budget_status' = 'blocked' and (f ->> 'budget_ok_seats')::int = 1
         and (f ->> 'budget_blocked_seats')::int = 1, 'case 10 budget ' || f::text;
  raise notice 'PASS: the 10 demo cases give the hand-calculated figures';
end $$;

-- ================================================================ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000004a1', 'authenticated', 'authenticated', 'r1platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000004a2', 'authenticated', 'authenticated', 'r1owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000004a3', 'authenticated', 'authenticated', 'r1owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000004a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Workforce', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Workforce', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000004a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000004a3'));
end $$;

-- Alpha admin: structure, people, pay, plan, logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a2","role":"authenticated"}', true);
do $$
declare
  v_sewing   uuid;
  v_accounts uuid;
  v_operator uuid;
  v_senior   uuid;
  v_branch   uuid;
  v_office   uuid;
  v_template uuid;
  v_common   jsonb;
  v_emp      uuid;
  i          integer;
begin
  insert into public.departments (name) values ('Sewing') returning id into v_sewing;
  insert into public.departments (name) values ('Accounts') returning id into v_accounts;
  insert into public.designations (department_id, grade_id, name)
    values (v_sewing, (select id from public.grades where code = 'EM1'), 'Operator') returning id into v_operator;
  insert into public.designations (department_id, grade_id, name)
    values (v_accounts, (select id from public.grades where code = 'MS0'), 'Senior Executive') returning id into v_senior;
  insert into public.branches (name) values ('Gazipur') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Factory') returning id into v_office;
  perform set_config('t.sewing', v_sewing::text, true);
  perform set_config('t.accounts', v_accounts::text, true);
  perform set_config('t.operator', v_operator::text, true);
  perform set_config('t.senior', v_senior::text, true);

  v_template := public.save_salary_template(null, '{"name":"Basic only","basic_amount":10000,"lines":[]}'::jsonb);
  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_sewing, 'designation_id', v_operator,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  for i in 1..6 loop
    v_emp := public.create_employee(v_common || jsonb_build_object('full_name', 'Sewing Operator ' || i));
    perform public.set_initial_compensation(v_emp, v_template, 10000, null, null, 'Start');
    if i = 6 then
      perform set_config('t.s6', v_emp::text, true);
    end if;
  end loop;
  v_common := v_common || jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior);
  perform set_config('t.hr', public.create_employee(v_common || '{"full_name":"HR Person"}')::text, true);
  perform set_config('t.mgr', public.create_employee(v_common || '{"full_name":"Accounts Manager"}')::text, true);

  perform public.save_workforce_settings('{"capacity_hours":200,"availability_source":"fixed","fixed_availability_percent":100,"confirm":true}'::jsonb);
  perform public.save_headcount_plan(v_sewing, jsonb_build_array(jsonb_build_object('designation_id', v_operator, 'sanctioned', 6)));
  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 2)));
  perform public.save_department_workforce(v_sewing, '{"method":"output_smv","monthly_budget":60000}'::jsonb);
  perform public.save_department_workforce(v_accounts, '{"method":"volume_std"}'::jsonb);

  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.hr')::uuid, 'hr@r1.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(current_setting('t.mgr')::uuid, 'mgr@r1.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  raise notice 'PASS setup: Sewing (6 operators, budget 60,000), Accounts (2), HR and manager logins';
end $$;

-- ============================================== B1. settings and permissions
do $$
begin
  begin
    perform public.save_workforce_settings('{"band_overload":1.30}'::jsonb);
    raise exception 'FAIL: overload above critical accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.save_workload_inputs(current_setting('t.sewing')::uuid, (date_trunc('month', current_date) + interval '1 month')::date,
                                        '[]'::jsonb);
    raise exception 'FAIL: a future month accepted';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: bands must rise; future months are refused';
end $$;

-- The leaver: a replacement is drafted at once.
do $$
begin
  perform public.deactivate_employee(current_setting('t.s6')::uuid, 'inactive', '2026-08-20', 'Resigned');
  assert (select count(*) from public.list_vacancies() v) = 1, 'one vacancy after the separation';
  assert (select v ->> 'origin' from jsonb_array_elements(public.list_vacancies()) v) = 'separation', 'origin separation';
  assert (select v ->> 'reason' from jsonb_array_elements(public.list_vacancies()) v) = 'replacement', 'reason replacement';
  perform set_config('t.vac_sep', (select v ->> 'id' from jsonb_array_elements(public.list_vacancies()) v), true);
  raise notice 'PASS: a person in a sanctioned position leaves -> replacement vacancy drafted';
end $$;

-- HR: output figures and snapshots; no headcount or budget changes.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_result jsonb;
  f        jsonb;
begin
  begin
    perform public.save_headcount_plan(current_setting('t.sewing')::uuid,
                                       jsonb_build_array(jsonb_build_object('designation_id', current_setting('t.operator'), 'sanctioned', 9)));
    raise exception 'FAIL: HR changed the headcount plan';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_department_workforce(current_setting('t.sewing')::uuid, '{"monthly_budget":99000}'::jsonb);
    raise exception 'FAIL: HR changed a budget';
  exception when insufficient_privilege then null;
  end;

  perform public.save_workload_inputs(current_setting('t.sewing')::uuid, '2026-08-01',
                                      '[{"metric_key":"STYLE-A","label":"Polo shirt","quantity":4800,"std_minutes":15}]'::jsonb);
  perform public.save_workload_inputs(current_setting('t.accounts')::uuid, '2026-08-01',
                                      '[{"metric_key":"voucher","quantity":1200,"std_minutes":15}]'::jsonb);
  v_result := public.build_workload_snapshots('2026-08-01');
  assert (v_result ->> 'drafting')::boolean = false and (v_result ->> 'seats_drafted')::int = 0, 'August is history: ' || v_result::text;

  select d -> 'snapshot' into f from jsonb_array_elements(public.get_workforce_dashboard('2026-08-01') -> 'departments') d
   where d ->> 'name' = 'Sewing';
  assert (f ->> 'demand_hours')::numeric = 1200 and (f ->> 'active')::int = 5, 'Aug demand ' || f::text;
  assert (f ->> 'index')::numeric = 1.2 and f ->> 'band' = 'overload' and not (f ->> 'overload_rule')::boolean, 'Aug overload, 1st month';
  assert (f ->> 'backfill_seats')::int = 1 and (f ->> 'new_positions')::int = 0, 'Aug seats';
  assert (f ->> 'budget_remaining')::numeric = 10000 and (f ->> 'cost_per_seat')::numeric = 10000
         and f ->> 'budget_status' = 'ok', 'Aug budget';
  assert (f ->> 'separations')::int = 1 and (f ->> 'avg_headcount')::numeric = 5.67
         and (f ->> 'attrition_percent')::numeric = 17.6 and not (f ->> 'attrition_flag')::boolean, 'Aug attrition';

  select d -> 'snapshot' into f from jsonb_array_elements(public.get_workforce_dashboard('2026-08-01') -> 'departments') d
   where d ->> 'name' = 'Accounts';
  assert (f ->> 'index')::numeric = 0.75 and f ->> 'action' = 'underloaded', 'Accounts underloaded';

  perform public.save_workload_inputs(current_setting('t.sewing')::uuid, '2026-09-01',
                                      '[{"metric_key":"STYLE-A","quantity":5600,"std_minutes":15}]'::jsonb);
  v_result := public.build_workload_snapshots('2026-09-01');
  assert (v_result ->> 'seats_drafted')::int = 1, 'September drafts the new position only: ' || v_result::text;
  select d -> 'snapshot' into f from jsonb_array_elements(public.get_workforce_dashboard('2026-09-01') -> 'departments') d
   where d ->> 'name' = 'Sewing';
  assert (f ->> 'index')::numeric = 1.4 and f ->> 'band' = 'critical' and (f ->> 'overload_months')::int = 2, 'Sep critical';
  assert (f ->> 'new_positions')::int = 1 and (f ->> 'backfill_seats')::int = 1, 'Sep seats';
  assert (f ->> 'budget_ok_seats')::int = 1 and (f ->> 'budget_blocked_seats')::int = 1, 'Sep budget';

  v_result := public.build_workload_snapshots('2026-09-01');
  assert (v_result ->> 'seats_drafted')::int = 0, 'rebuilding drafts nothing new';
  assert (select count(*) from jsonb_array_elements(public.list_vacancies())) = 2, 'two vacancies in total';
  perform set_config('t.vac_new', (select v ->> 'id' from jsonb_array_elements(public.list_vacancies()) v
                                   where v ->> 'reason' = 'new_position'), true);
  assert (select v ->> 'budget_status' from jsonb_array_elements(public.list_vacancies()) v
          where v ->> 'reason' = 'new_position') = 'blocked', 'new position is budget blocked';
  raise notice 'PASS: snapshots from output figures, sustain rule, budget split, idempotent drafting';

  -- HR reviews; HR cannot approve.
  perform public.review_vacancy(current_setting('t.vac_sep')::uuid, 'forward', null);
  perform public.review_vacancy(current_setting('t.vac_new')::uuid, 'forward', null);
  begin
    perform public.decide_vacancy(current_setting('t.vac_sep')::uuid, 'approve');
    raise exception 'FAIL: HR approved a vacancy';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: HR forwards vacancies but cannot approve them';
end $$;

-- Manager: own department only, no dashboard.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  begin
    perform public.get_workforce_dashboard(null);
    raise exception 'FAIL: manager saw the workforce dashboard';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.draft_vacancy(jsonb_build_object('department_id', current_setting('t.sewing'),
                                                    'designation_id', current_setting('t.operator'), 'seats', 1));
    raise exception 'FAIL: manager drafted for another department';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.draft_vacancy(jsonb_build_object('department_id', current_setting('t.accounts'),
                                                    'designation_id', current_setting('t.senior'), 'seats', 1,
                                                    'reason', 'replacement'));
    raise exception 'FAIL: replacement without an open sanctioned position';
  exception when check_violation then null;
  end;
  perform set_config('t.vac_mgr', public.draft_vacancy(jsonb_build_object(
    'department_id', current_setting('t.accounts'), 'designation_id', current_setting('t.senior'), 'seats', 1,
    'reason', 'new_position', 'note', 'Month-close needs one more person'))::text, true);
  assert (select count(*) from jsonb_array_elements(public.list_vacancies())) = 1, 'manager sees only Accounts vacancies';
  raise notice 'PASS: manager drafts only for the own department and sees only its vacancies';
end $$;

-- Admin decides: maker-checker, budget override, sanction raised.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a2","role":"authenticated"}', true);
do $$
begin
  perform public.decide_vacancy(current_setting('t.vac_sep')::uuid, 'approve');
  begin
    perform public.decide_vacancy(current_setting('t.vac_new')::uuid, 'approve');
    raise exception 'FAIL: approved over budget without saying so';
  exception when check_violation then null;
  end;
  begin
    perform public.decide_vacancy(current_setting('t.vac_new')::uuid, 'approve', null, true);
    raise exception 'FAIL: over-budget approval without a reason';
  exception when not_null_violation then null;
  end;
  perform public.decide_vacancy(current_setting('t.vac_new')::uuid, 'approve', 'Peak season orders confirmed', true);
  assert (select d -> 'plan' -> 0 ->> 'sanctioned' from jsonb_array_elements(public.get_workforce_dashboard(null) -> 'departments') d
          where d ->> 'name' = 'Sewing')::int = 7, 'approved new position raised the sanction to 7';
  assert exists (select 1 from jsonb_array_elements(public.list_vacancies()) v, jsonb_array_elements(v -> 'events') e
                 where v ->> 'id' = current_setting('t.vac_new') and e ->> 'event' = 'approved_over_budget'), 'over-budget event';

  -- The admin forwards the manager's request and then may not approve it.
  perform public.review_vacancy(current_setting('t.vac_mgr')::uuid, 'forward', null);
  begin
    perform public.decide_vacancy(current_setting('t.vac_mgr')::uuid, 'approve');
    raise exception 'FAIL: reviewer approved own review';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.decide_vacancy(current_setting('t.vac_mgr')::uuid, 'reject', 'no');
    raise exception 'FAIL: reject without a real reason';
  exception when insufficient_privilege or not_null_violation then null;
  end;
  raise notice 'PASS: approver differs from reviewer, over-budget needs a reason, sanction raised';
end $$;

-- Beta sees nothing of Alpha.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000004a3","role":"authenticated"}', true);
do $$
begin
  assert public.list_vacancies() = '[]'::jsonb, 'Beta sees no Alpha vacancies';
  assert jsonb_array_length(public.get_workforce_dashboard(null) -> 'departments') = 0, 'Beta sees no Alpha departments';
  begin
    perform public.review_vacancy(current_setting('t.vac_mgr')::uuid, 'reject', 'Not ours at all');
    raise exception 'FAIL: Beta reviewed an Alpha vacancy';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: company isolation';
end $$;

select '==== ALL R1 WORKFORCE CHECKS PASSED ====' as result;
rollback;
