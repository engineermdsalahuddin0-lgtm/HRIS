-- =============================================================================
-- Part 3C + PMS golden tests: TDS (projection method), provident fund,
-- gratuity, the tax calculator and manual performance scoring.
-- Every expected amount was calculated by hand first (FY 2026-27 tables):
--   tax-free threshold 400,000; then 10% / 300,000, 15% / 400,000, ...
--   exempt = min(income / 3, 500,000); rebate = min(3% taxable, 10% investment,
--   750,000); minimum tax 5,000 (new taxpayer 1,000).
--
-- X1 "Exec": basic 100,000, PF 10% + 10%, TIN, declared investment 100,000.
--   July (12 months left): projected 1,200,000 -> exempt 400,000 -> taxable
--   800,000 -> tax 30,000 + 15,000 = 45,000; investment 100,000 + PF
--   20,000 x 12 = 340,000 -> rebate min(24,000, 34,000) = 24,000 -> 21,000.
--   TDS 21,000 / 12 = 1,750; net 100,000 - 10,000 - 1,750 = 88,250.
--   August (+ bonus 50,000, 11 months left): projected 100,000 + 150,000 +
--   10 x 100,000 = 1,250,000 -> exempt 416,666.67 -> taxable 833,333.33 ->
--   tax 30,000 + 20,000 = 50,000; rebate min(25,000, 34,000) = 25,000 ->
--   25,000; TDS (25,000 - 1,750) / 11 = 2,113.64; net 137,886.36 -> 137,886.
-- X2 "Low": 20,000 -> projected 240,000 -> taxable 160,000 -> no tax.
-- X3 "No TIN": 100,000, no profile, no PF -> tax 45,000 (no rebate) ->
--   TDS 3,750; net 96,250; warning missing_tin.
-- Gratuity (30 days / year, 45 days when more than 10 counted years):
--   G1 joined 2014-01-01, basic 60,000, leaves 2026-07-31: 12y 7m -> 13 years
--   -> 2,000 x 45 x 13 = 1,170,000. G2 joined 2023-03-01, basic 10,000:
--   3y 5m -> 3 years -> 333.33.. x 30 x 3 = 30,000. G3 7 months -> 0.
--   July provision for X1 (7 months -> 1 counted year): 100,000/30 x 30/12 = 8,333.33.
-- PF: X1 ledger 10,000 + 10,000; interest 5% -> 1,000; withdrawal with
--   0 years (0% vested) = 10,000 + 0 + 1,000 = 11,000.
-- PMS: weights 40/30/30, scores 5/4/3 -> (200 + 120 + 90) / 100 = 4.10.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL PART 3C CHECKS PASSED".
-- =============================================================================
begin;

-- ------------------------------------------------------------------ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000003c1', 'authenticated', 'authenticated', 'p3cplatform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003c2', 'authenticated', 'authenticated', 'p3cowner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003c3', 'authenticated', 'authenticated', 'p3cowner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000003c1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Statutory', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Statutory', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c1","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org_a', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003c2'))::text, true);
  perform set_config('t.org_b', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003c3'))::text, true);
end $$;

-- Alpha admin: templates, people, pay, logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c2","role":"authenticated"}', true);
do $$
declare
  v_dept     uuid;
  v_operator uuid;
  v_branch   uuid;
  v_office   uuid;
  v_template uuid;
  v_common   jsonb;
begin
  insert into public.departments (name) values ('Finance') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'MS1'), 'Officer') returning id into v_operator;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;

  -- Basic only: gross = basic, everything taxable.
  v_template := public.save_salary_template(null, jsonb_build_object('name', 'Basic only', 'basic_amount', 10000,
                                                                     'lines', '[]'::jsonb));
  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_dept, 'designation_id', v_operator,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  perform set_config('t.hr', public.create_employee(v_common || '{"full_name":"HR Person"}')::text, true);
  perform set_config('t.mgr', public.create_employee(v_common || '{"full_name":"Team Manager"}')::text, true);
  perform set_config('t.x1', public.create_employee(v_common || '{"full_name":"X1 Exec"}')::text, true);
  perform set_config('t.x2', public.create_employee(v_common || '{"full_name":"X2 Low"}')::text, true);
  perform set_config('t.x3', public.create_employee(v_common || '{"full_name":"X3 No TIN"}')::text, true);
  perform set_config('t.g1', public.create_employee(v_common || '{"full_name":"G1 Long Service","join_date":"2014-01-01"}')::text, true);
  perform set_config('t.g2', public.create_employee(v_common || '{"full_name":"G2 Three Years","join_date":"2023-03-01"}')::text, true);

  perform public.set_initial_compensation(current_setting('t.hr')::uuid, v_template, 30000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.mgr')::uuid, v_template, 30000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.x1')::uuid, v_template, 100000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.x2')::uuid, v_template, 20000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.x3')::uuid, v_template, 100000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.g1')::uuid, v_template, 60000, null, null, 'Start');
  perform public.set_initial_compensation(current_setting('t.g2')::uuid, v_template, 10000, null, null, 'Start');

  perform public.set_reporting_line(current_setting('t.x3')::uuid, 'reporting_manager', current_setting('t.mgr')::uuid, '2026-01-01');

  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.hr')::uuid, 'hr@p3c.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(current_setting('t.mgr')::uuid, 'mgr@p3c.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_x2', public.grant_portal_access(current_setting('t.x2')::uuid, 'x2@p3c.test', null, 'Passw0rd1', null)::text, true);
  raise notice 'PASS setup: basic-only template, seven people, HR / manager / employee logins';
end $$;

-- ============================================================ settings
do $$
begin
  -- Switching on without confirming the values is refused.
  begin
    perform public.save_statutory_settings('{"auto_tds": true}'::jsonb);
    raise exception 'FAIL: switched on without confirmation';
  exception when check_violation then null;
  end;
  perform public.save_statutory_settings(jsonb_build_object(
    'auto_tds', true, 'pf_enabled', true, 'gratuity_enabled', true, 'confirm', true,
    'pf', jsonb_build_object('employee_rate', 10, 'employer_rate', 10, 'basis', 'basic', 'min_service_months', 0,
                             'interest_rate', 5, 'is_recognised', true,
                             'vesting', '[{"min_years":0,"percent":0},{"min_years":3,"percent":50},{"min_years":5,"percent":100}]'::jsonb),
    'gratuity', jsonb_build_object('basis', 'last_basic', 'min_service_months', 12, 'partial_year_months', 6,
                                   'provision_enabled', true,
                                   'bands', '[{"min_years":1,"days":30},{"min_years":11,"days":45}]'::jsonb)));
  assert (public.get_statutory_settings() -> 'pf' ->> 'confirmed_at') is not null, 'PF values confirmed';
  raise notice 'PASS: statutory switches need confirmation; settings saved';
end $$;

-- HR: cannot change the switches; keeps tax profiles and PF members.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.save_statutory_settings('{"auto_tds": false}'::jsonb);
    raise exception 'FAIL: HR changed statutory settings';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_tax_profile(current_setting('t.x1')::uuid, '{"tin":"12345"}'::jsonb);
    raise exception 'FAIL: short TIN accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_tax_profile(current_setting('t.x1')::uuid,
    '{"tin":"123456789012","taxpayer_type":"general","declared_investment":100000}'::jsonb);
  perform public.set_pf_membership(current_setting('t.x1')::uuid, '2026-01-01', 'active');
  perform public.save_bonus(null, jsonb_build_object(
    'name', 'Performance bonus', 'type', 'performance', 'basis', 'fixed', 'amount', 50000, 'payment_month', '2026-08-01',
    'min_service_months', 0, 'scope', 'employees', 'employee_ids', jsonb_build_array(current_setting('t.x1'))));
  raise notice 'PASS: HR keeps tax profiles and PF members, not the switches';
end $$;

-- ============================================================ tax calculator
do $$
declare
  v jsonb;
begin
  v := public.preview_tax('{"annual_income":1200000,"investment":100000}'::jsonb);
  assert (v ->> 'exempt')::numeric = 400000 and (v ->> 'taxable_income')::numeric = 800000, 'calc: exempt and taxable';
  assert (v ->> 'gross_tax')::numeric = 45000, 'calc: slabs 45,000';
  assert (v -> 'rebate' ->> 'applied')::numeric = 10000, 'calc: rebate 10% of investment';
  assert (v ->> 'annual_tax')::numeric = 35000 and (v ->> 'monthly_tds')::numeric = 2916.67, 'calc: 35,000 / 2,916.67';

  v := public.preview_tax('{"annual_income":1200000,"investment":100000,"taxpayer_type":"woman_senior"}'::jsonb);
  assert (v ->> 'annual_tax')::numeric = 27500, 'calc: woman / 65+ threshold 450,000 -> 27,500';

  v := public.preview_tax('{"annual_income":500000}'::jsonb);
  assert (v ->> 'annual_tax')::numeric = 0, 'calc: below the threshold pays nothing';

  v := public.preview_tax('{"annual_income":650000}'::jsonb);
  assert (v ->> 'gross_tax')::numeric = 3333.33 and (v ->> 'annual_tax')::numeric = 5000, 'calc: minimum tax 5,000';
  v := public.preview_tax('{"annual_income":650000,"is_new_taxpayer":true}'::jsonb);
  assert (v ->> 'annual_tax')::numeric = 3333.33, 'calc: new taxpayer minimum 1,000 does not bite';
  raise notice 'PASS: tax calculator (slabs, rebate, thresholds, minimum tax)';
end $$;

-- ============================================================ July run
do $$
declare
  v_run uuid;
begin
  v_run := public.create_payroll_run('2026-07-01');
  perform set_config('t.run_jul', v_run::text, true);
  perform public.calculate_payroll_run(v_run);
end $$;

reset role;
select set_config('t.slip_x1_jul', (select id::text from public.payroll_slips
                                     where run_id = current_setting('t.run_jul')::uuid and employee_id = current_setting('t.x1')::uuid), true);
do $$
declare
  v_run  uuid := current_setting('t.run_jul')::uuid;
  v_x1   public.payroll_slips;
  v_x2   public.payroll_slips;
  v_x3   public.payroll_slips;
begin
  select * into v_x1 from public.payroll_slips where run_id = v_run and employee_id = current_setting('t.x1')::uuid;
  select * into v_x2 from public.payroll_slips where run_id = v_run and employee_id = current_setting('t.x2')::uuid;
  select * into v_x3 from public.payroll_slips where run_id = v_run and employee_id = current_setting('t.x3')::uuid;

  assert (select amount from public.payroll_slip_lines where slip_id = v_x1.id and code = 'PF_EE') = 10000, 'X1 PF 10,000';
  assert v_x1.employer_pf = 10000, 'X1 employer PF 10,000 (cost, not deducted)';
  assert (v_x1.tax_detail ->> 'annual_tax')::numeric = 21000, 'X1 annual tax 21,000';
  assert (v_x1.tax_detail -> 'projection' ->> 'pf_investment')::numeric = 240000, 'X1 PF counts as investment';
  assert (select amount from public.payroll_slip_lines where slip_id = v_x1.id and code = 'TDS') = 1750, 'X1 TDS 1,750';
  assert v_x1.net = 88250, 'X1 July net 88,250';
  raise notice 'PASS: TDS by projection with PF and rebate (X1 88,250)';

  assert not exists (select 1 from public.payroll_slip_lines where slip_id = v_x2.id and code in ('TDS', 'PF_EE')),
    'X2 has no TDS and no PF';
  assert v_x2.tds_preview = 0 and v_x2.net = 20000, 'X2 zero tax, net 20,000';
  raise notice 'PASS: a person below the threshold pays no tax';

  assert (select amount from public.payroll_slip_lines where slip_id = v_x3.id and code = 'TDS') = 3750, 'X3 TDS 3,750';
  assert v_x3.net = 96250, 'X3 net 96,250';
  assert v_x3.warnings @> '[{"code":"missing_tin"}]', 'X3 warns about the missing TIN';
  raise notice 'PASS: missing TIN warns; no investment means no rebate';
end $$;
set local role authenticated;

-- HR reviews, the Admin approves; the employee sees the tax working on the slip.
select public.review_payroll_run(current_setting('t.run_jul')::uuid);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c2","role":"authenticated"}', true);
select public.approve_payroll_run(current_setting('t.run_jul')::uuid);
do $$
begin
  assert jsonb_array_length(public.get_run_statutory_summary(current_setting('t.run_jul')::uuid)) >= 7, 'run statutory summary';
end $$;

-- ============================================================ August run (bonus)
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_run uuid;
begin
  v_run := public.create_payroll_run('2026-08-01');
  perform set_config('t.run_aug', v_run::text, true);
  perform public.calculate_payroll_run(v_run);
end $$;
reset role;
do $$
declare
  v_x1 public.payroll_slips;
begin
  select * into v_x1 from public.payroll_slips
   where run_id = current_setting('t.run_aug')::uuid and employee_id = current_setting('t.x1')::uuid;
  assert (v_x1.tax_detail -> 'projection' ->> 'projected_income')::numeric = 1250000, 'August projection 1,250,000';
  assert (v_x1.tax_detail ->> 'annual_tax')::numeric = 25000, 'August annual tax 25,000';
  assert (v_x1.tax_detail ->> 'ytd_tds')::numeric = 1750, 'July TDS counted';
  assert (select amount from public.payroll_slip_lines where slip_id = v_x1.id and code = 'TDS') = 2113.64, 'August TDS 2,113.64';
  assert v_x1.net = 137886, 'August net 137,886';
  raise notice 'PASS: a bonus month recomputes TDS for the rest of the year';
end $$;
set local role authenticated;

-- ============================================================ lock July -> ledgers
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c2","role":"authenticated"}', true);
do $$
declare
  v_batch jsonb;
begin
  for v_batch in select * from jsonb_array_elements(public.get_payroll_run(current_setting('t.run_jul')::uuid) -> 'batches') loop
    perform public.mark_payment_batch_paid((v_batch ->> 'id')::uuid, 'BANK-REF-1');
  end loop;
  perform public.lock_payroll_run(current_setting('t.run_jul')::uuid);
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_ledger    jsonb;
  v_member    jsonb;
  v_gratuity  jsonb;
  v_preview   jsonb;
begin
  v_ledger := public.list_tds_ledger('2026-27');
  assert (select (x ->> 'tds_amount')::numeric from jsonb_array_elements(v_ledger) x
          where x ->> 'employee_id' = current_setting('t.x1')) = 1750, 'TDS ledger: X1 1,750';
  assert public.set_tds_challan(array(select (x ->> 'id')::uuid from jsonb_array_elements(v_ledger) x),
                                'CH-2026-07', '2026-08-10') = jsonb_array_length(v_ledger), 'challan recorded';

  select x into v_member from jsonb_array_elements(public.list_pf_members()) x
   where x ->> 'employee_id' = current_setting('t.x1');
  assert (v_member ->> 'employee_total')::numeric = 10000 and (v_member ->> 'employer_total')::numeric = 10000,
    'PF ledger: 10,000 + 10,000';

  select x into v_gratuity from jsonb_array_elements(public.list_gratuity_liability()) x
   where x ->> 'employee_id' = current_setting('t.x1');
  assert (v_gratuity ->> 'provisioned')::numeric = 8333.33, 'gratuity provision 8,333.33';
  raise notice 'PASS: locking posts the TDS, PF and gratuity ledgers';

  assert public.post_pf_interest('2026-07-31') >= 1, 'interest posted';
  assert (select (r ->> 'balance')::numeric from jsonb_array_elements(public.get_pf_statement(current_setting('t.x1')::uuid) -> 'rows') r
          order by r ->> 'period_month' desc, r ->> 'entry_type' desc limit 1) = 21000, 'PF balance 21,000';
  v_preview := public.preview_pf_withdrawal(current_setting('t.x1')::uuid, '2026-08-31');
  assert (v_preview ->> 'vested_percent')::numeric = 0 and (v_preview ->> 'total')::numeric = 11000, 'PF withdrawal 11,000';
  raise notice 'PF: interest and withdrawal with the vesting schedule';

  v_preview := public.preview_gratuity(current_setting('t.g1')::uuid, '2026-07-31');
  assert (v_preview ->> 'counted_years')::int = 13 and (v_preview ->> 'days_per_year')::numeric = 45, 'G1 13 years at 45 days';
  assert (v_preview ->> 'amount')::numeric = 1170000, 'G1 gratuity 1,170,000';
  assert (public.preview_gratuity(current_setting('t.g2')::uuid, '2026-07-31') ->> 'amount')::numeric = 30000, 'G2 30,000';
  v_preview := public.preview_gratuity(current_setting('t.x1')::uuid, '2026-07-31');
  assert (v_preview ->> 'amount')::numeric = 0 and v_preview ->> 'not_eligible_reason' is not null, 'under 12 months: none';
  raise notice 'PASS: gratuity bands (30 / 45 days), part-year rule and minimum service';
end $$;

-- Employees and other companies see none of it.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_x2')), true);
do $$
begin
  begin
    perform public.list_tax_profiles();
    raise exception 'FAIL: employee listed tax profiles';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.preview_gratuity(current_setting('t.g1')::uuid, '2026-07-31');
    raise exception 'FAIL: employee previewed gratuity';
  exception when insufficient_privilege then null;
  end;
  assert jsonb_array_length(public.list_statutory_references()) >= 15, 'references are readable';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003c3","role":"authenticated"}', true);
do $$
begin
  assert jsonb_array_length(public.list_tax_profiles()) = 0 or not exists (
    select 1 from jsonb_array_elements(public.list_tax_profiles()) x where x ->> 'employee_id' = current_setting('t.x1')),
    'Beta cannot see Alpha tax profiles';
  assert jsonb_array_length(public.get_pf_statement(current_setting('t.x1')::uuid) -> 'rows') = 0, 'Beta sees no Alpha PF rows';
  begin
    perform public.preview_gratuity(current_setting('t.g1')::uuid, '2026-07-31');
    raise exception 'FAIL: Beta previewed Alpha gratuity';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: employees and other companies see no tax, PF or gratuity data';
end $$;

-- ============================================================ PMS manual scoring
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_cycle  uuid;
  v_detail jsonb;
  v_ids    uuid[];
begin
  begin
    perform public.save_performance_cycle(null, '{"name":"H2 2026","period_from":"2026-07-01","period_to":"2026-12-31",
      "criteria":[{"name":"Quality","weight":40},{"name":"Teamwork","weight":50}]}'::jsonb);
    raise exception 'FAIL: weights of 90 accepted';
  exception when check_violation then null;
  end;
  v_cycle := public.save_performance_cycle(null, '{"name":"H2 2026","period_from":"2026-07-01","period_to":"2026-12-31",
    "criteria":[{"name":"Quality of work","weight":40},{"name":"Teamwork","weight":30},{"name":"Attendance","weight":30}]}'::jsonb);
  perform set_config('t.cycle', v_cycle::text, true);
  perform public.set_performance_cycle_status(v_cycle, 'open');

  select array_agg((c ->> 'id')::uuid order by (c ->> 'weight')::numeric desc, c ->> 'name')
    into v_ids
  from jsonb_array_elements((select c -> 'criteria' from jsonb_array_elements(public.list_performance_cycles()) c
                             where c ->> 'id' = v_cycle::text)) c;
  -- v_ids: Quality (40), Attendance (30), Teamwork (30)

  begin
    perform public.save_performance_review(v_cycle, current_setting('t.x2')::uuid, jsonb_build_object(
      'scores', jsonb_build_array(jsonb_build_object('criterion_id', v_ids[1], 'score', 5)), 'submit', true));
    raise exception 'FAIL: submitted with criteria missing';
  exception when not_null_violation then null;
  end;
  begin
    perform public.save_performance_review(v_cycle, current_setting('t.hr')::uuid, '{"scores":[]}'::jsonb);
    raise exception 'FAIL: reviewed self';
  exception when insufficient_privilege then null;
  end;

  v_detail := public.save_performance_review(v_cycle, current_setting('t.x2')::uuid, jsonb_build_object(
    'scores', jsonb_build_array(jsonb_build_object('criterion_id', v_ids[1], 'score', 5),
                                jsonb_build_object('criterion_id', v_ids[2], 'score', 3),
                                jsonb_build_object('criterion_id', v_ids[3], 'score', 4)),
    'strengths', 'Careful work', 'submit', true));
  assert (v_detail -> 'review' ->> 'overall_score')::numeric = 4.10, 'weighted score 4.10';
  assert v_detail -> 'review' ->> 'rating' = 'Exceeds expectations', 'rating band';
  raise notice 'PASS: weighted manual scoring (4.10, Exceeds expectations)';
end $$;

-- A manager scores only the own team.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  assert jsonb_array_length(public.get_performance_cycle(current_setting('t.cycle')::uuid) -> 'people') = 1, 'manager sees one person';
  begin
    perform public.save_performance_review(current_setting('t.cycle')::uuid, current_setting('t.x2')::uuid, '{"scores":[]}'::jsonb);
    raise exception 'FAIL: manager scored outside the team';
  exception when insufficient_privilege then null;
  end;
  perform public.save_performance_review(current_setting('t.cycle')::uuid, current_setting('t.x3')::uuid, '{"scores":[]}'::jsonb);
  raise notice 'PASS: managers score their own team only';
end $$;

-- The employee sees and acknowledges the submitted review.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_x2')), true);
do $$
declare
  v_reviews jsonb := public.list_my_performance_reviews();
begin
  assert jsonb_array_length(v_reviews) = 1, 'employee sees one review';
  perform public.acknowledge_performance_review((v_reviews -> 0 -> 'review' ->> 'id')::uuid, 'Thank you');
  assert public.list_my_performance_reviews() -> 0 -> 'review' ->> 'status' = 'acknowledged', 'acknowledged';
  begin
    perform public.list_performance_cycles();
    raise exception 'FAIL: employee listed cycles';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: employee sees and acknowledges own review';
end $$;

reset role;
do $$ begin raise notice '==== ALL PART 3C CHECKS PASSED ===='; end $$;
select '==== ALL PART 3C CHECKS PASSED ====' as result;
rollback;
