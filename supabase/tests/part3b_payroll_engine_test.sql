-- =============================================================================
-- Part 3B golden tests: payroll engine (Part 3 architecture, section 6).
-- Every expected amount was calculated by hand before the code ran. All pay is
-- the "Worker" template: basic 10,000 + house rent 5,000 + 750 + 450 + 1,250
-- = gross 17,450. Daily rate on basic = 10,000 / 30 = 333.333…;
-- hourly overtime rate = 10,000 / 208 = 48.0769….
--
-- Covers tests 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 15, 16, 17, 18, 19, 20, 21.
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL PART 3B CHECKS PASSED".
-- =============================================================================
begin;

-- ------------------------------------------------------------------ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000003b1', 'authenticated', 'authenticated', 'p3bplatform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003b2', 'authenticated', 'authenticated', 'p3bowner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003b3', 'authenticated', 'authenticated', 'p3bowner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000003b1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Payroll', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Payroll', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b1","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org_a', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003b2'))::text, true);
  perform set_config('t.org_b', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003b3'))::text, true);
end $$;

-- Alpha admin: structure, template, people, pay, logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
do $$
declare
  v_dept     uuid;
  v_operator uuid;
  v_manager  uuid;
  v_director uuid;
  v_branch   uuid;
  v_office   uuid;
  v_template uuid;
  v_common   jsonb;
  v_key      text;
begin
  insert into public.departments (name) values ('Production') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'EM1'), 'Operator') returning id into v_operator;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'MS1'), 'Line Manager') returning id into v_manager;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'OWNER01'), 'Director') returning id into v_director;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;

  v_template := public.save_salary_template(null, jsonb_build_object(
    'name', 'Worker', 'basic_amount', 10000,
    'lines', (select jsonb_agg(jsonb_build_object('component_id', id, 'calc', calc, 'value', default_value))
              from public.salary_components where not is_basic)));
  perform set_config('t.tpl', v_template::text, true);

  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_dept, 'designation_id', v_operator,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2025-01-01');
  perform set_config('t.hr', public.create_employee(v_common || '{"full_name":"HR Person"}')::text, true);
  perform set_config('t.e1', public.create_employee(v_common || '{"full_name":"E1 Full Month"}')::text, true);
  perform set_config('t.e2', public.create_employee(v_common || '{"full_name":"E2 Absent Two"}')::text, true);
  perform set_config('t.e3', public.create_employee(v_common || '{"full_name":"E3 March Joiner","join_date":"2026-03-16"}')::text, true);
  perform set_config('t.e4', public.create_employee(v_common || '{"full_name":"E4 March Leaver"}')::text, true);
  perform set_config('t.e5', public.create_employee(v_common || jsonb_build_object('full_name', 'E5 Manager Overtime',
                                                                                    'designation_id', v_manager))::text, true);
  perform set_config('t.e6', public.create_employee(v_common || '{"full_name":"E6 Late Half"}')::text, true);
  perform set_config('t.e7', public.create_employee(v_common || '{"full_name":"E7 Arrears"}')::text, true);
  perform set_config('t.e8', public.create_employee(v_common || '{"full_name":"E8 Negative Net"}')::text, true);
  perform set_config('t.dir', public.create_employee(v_common || jsonb_build_object('full_name', 'Director Overtime',
                                                                                    'designation_id', v_director))::text, true);

  -- Everyone gets the Worker pay (the org owner joined today, so is not in
  -- these months). E7 from 1 Jan 2026 so the February increment is back-dated
  -- against a paid month.
  foreach v_key in array array['t.dir', 't.hr', 't.e1', 't.e2', 't.e3', 't.e4', 't.e5', 't.e6', 't.e8'] loop
    perform public.set_initial_compensation(current_setting(v_key)::uuid, v_template, 10000, null, null, 'Starting pay');
  end loop;
  perform public.set_initial_compensation(current_setting('t.e7')::uuid, v_template, 10000, null, '2026-01-01', 'Starting pay');

  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.hr')::uuid, 'hr@p3b.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_e1', public.grant_portal_access(current_setting('t.e1')::uuid, 'e1@p3b.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_e5', public.grant_portal_access(current_setting('t.e5')::uuid, 'e5@p3b.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  raise notice 'PASS setup: template (gross 17,450), nine paid employees, HR / employee / manager logins';
end $$;

-- HR: bonus, loan, payment account.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  perform public.save_bonus(null, jsonb_build_object(
    'name', 'Eid bonus', 'type', 'festival', 'basis', 'fixed', 'amount', 5000, 'payment_month', '2026-03-01',
    'min_service_months', 6, 'scope', 'employees',
    'employee_ids', jsonb_build_array(current_setting('t.e1'), current_setting('t.e3'))));
  perform set_config('t.loan', public.create_deduction(jsonb_build_object(
    'employee_id', current_setting('t.e1'), 'type', 'loan', 'total', 1500, 'installment', 1000,
    'start_month', '2026-03-01'))::text, true);
  perform public.save_payment_account(null, jsonb_build_object(
    'employee_id', current_setting('t.e1'), 'method', 'bank', 'bank_name', 'Dutch-Bangla Bank',
    'account_number', '1234567890123', 'is_primary', true));
end $$;

-- Attendance and approved overtime (inserted directly, as the Part 2 engine would).
reset role;
do $$
declare
  v_org uuid := current_setting('t.org_a')::uuid;
begin
  insert into public.attendance_records (org_id, employee_id, work_date, day_type, status, is_late, late_minutes) values
    (v_org, current_setting('t.e2')::uuid, '2026-02-03', 'workday', 'absent', false, 0),
    (v_org, current_setting('t.e2')::uuid, '2026-02-04', 'workday', 'absent', false, 0),
    (v_org, current_setting('t.e2')::uuid, '2026-03-03', 'workday', 'absent', false, 0),
    (v_org, current_setting('t.e2')::uuid, '2026-03-04', 'workday', 'absent', false, 0),
    (v_org, current_setting('t.e6')::uuid, '2026-03-02', 'workday', 'late', true, 20),
    (v_org, current_setting('t.e6')::uuid, '2026-03-03', 'workday', 'late', true, 25),
    (v_org, current_setting('t.e6')::uuid, '2026-03-05', 'workday', 'late', true, 15),
    (v_org, current_setting('t.e6')::uuid, '2026-03-08', 'workday', 'half_day', false, 0);
  insert into public.overtime_records (org_id, employee_id, work_date, minutes, day_type, multiplier, status, source) values
    (v_org, current_setting('t.e5')::uuid, '2026-03-10', 120, 'workday', 2.00, 'approved', 'manual'),
    (v_org, current_setting('t.e5')::uuid, '2026-03-06', 300, 'weekend', 2.00, 'approved', 'manual'),
    (v_org, current_setting('t.e5')::uuid, '2026-03-26', 240, 'holiday', 3.00, 'approved', 'manual'),
    (v_org, current_setting('t.dir')::uuid, '2026-03-11', 120, 'workday', 2.00, 'approved', 'manual'),
    -- Pending overtime is never paid.
    (v_org, current_setting('t.e6')::uuid, '2026-03-12', 120, 'workday', 2.00, 'pending', 'auto');
end $$;
set local role authenticated;

-- ============================================================ February run
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_run   uuid;
  v_slips jsonb;
begin
  v_run := public.create_payroll_run('2026-02-01');
  perform set_config('t.run_feb', v_run::text, true);
  perform public.calculate_payroll_run(v_run);

  -- Test 3: a full month with no events = gross exactly.
  v_slips := public.get_payroll_run(v_run) -> 'slips';
  assert (select (x ->> 'net')::numeric from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e1')) = 17450,
    'test 3: full month pays 17,450';
  -- Test 4: 2 absent days in February (28 days): 17,450 - 666.67 = 16,783.33 -> 16,783.
  assert (select (x ->> 'net')::numeric from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e2')) = 16783,
    'test 4: February absence 16,783';
  assert not exists (select 1 from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e3')),
    'a March joiner is not in February';
  -- 8 x 17,450 + 16,783 = 156,383.
  assert (public.get_payroll_run(v_run) -> 'run' ->> 'total_net')::numeric = 156383, 'February total 156,383';
  assert (public.get_payroll_run(v_run) -> 'run' -> 'run_warnings') @> '[{"code":"attendance_not_locked"}]',
    'run warns that attendance is not locked';
  perform public.review_payroll_run(v_run);
  raise notice 'PASS test 3/4: full month = gross; February absence on the 30-day basis';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.approve_payroll_run(current_setting('t.run_feb')::uuid);

-- After February: a back-dated increment for E7, a deduction adjustment for
-- E8, and E4 leaves on 20 March.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  perform set_config('t.increment', public.request_increment(current_setting('t.e7')::uuid, jsonb_build_object(
    'type', 'increment', 'new_gross', 20000, 'effective_date', '2026-02-16', 'reason', 'Annual review'))::text, true);
  perform set_config('t.adjust', public.create_payroll_adjustment(jsonb_build_object(
    'employee_id', current_setting('t.e8'), 'apply_month', '2026-03-01', 'type', 'manual', 'direction', 'deduction',
    'amount', 20000, 'reason', 'Advance recovery'))::text, true);
  begin
    perform public.decide_payroll_adjustment(current_setting('t.adjust')::uuid, true);
    raise exception 'FAIL: HR approved an adjustment';
  exception when insufficient_privilege then null;
  end;
  perform public.deactivate_employee(current_setting('t.e4')::uuid, 'inactive', '2026-03-20', 'Resigned');
  begin
    perform public.create_payroll_adjustment(jsonb_build_object(
      'employee_id', current_setting('t.e1'), 'apply_month', '2026-02-01', 'type', 'correction', 'direction', 'earning',
      'amount', 100, 'reason', 'Late fix'));
    raise exception 'FAIL: adjustment into an approved month';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.decide_increment(current_setting('t.increment')::uuid, true, 'Approved');
select public.decide_payroll_adjustment(current_setting('t.adjust')::uuid, true);

-- =============================================================== March run
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_run uuid;
begin
  v_run := public.create_payroll_run('2026-03-01');
  perform set_config('t.run_mar', v_run::text, true);
  perform public.calculate_payroll_run(v_run);
end $$;

reset role;
-- Scratch tables live in private (the SQL Editor does not keep temp tables
-- visible across statements); the final rollback removes them.
create table private.test_march_net as
  select e.full_name, s.employee_id, s.net, s.gross_earnings, s.total_deductions, s.carry_forward_out, s.id as slip_id
  from public.payroll_slips s join public.employees e on e.id = s.employee_id
  where s.run_id = current_setting('t.run_mar')::uuid;

do $$
declare
  v_line numeric;
begin
  -- Test 3 / 10 / 14: 17,450 + bonus 5,000 - loan 1,000 = 21,450.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e1')::uuid) = 21450, 'E1 March 21,450';
  -- Test 4: two absent days in a 31-day month = same as February: 16,783.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e2')::uuid) = 16783, 'test 4: March = February';
  -- Test 5: joiner on 16 March: 15 days not employed -> 17,450 x 15 / 30 = 8,725.00 off; bonus refused (0 months).
  assert (select net from private.test_march_net where employee_id = current_setting('t.e3')::uuid) = 8725, 'test 5: joiner 8,725';
  -- Test 5: leaver on 20 March: 10 days -> 5,816.67 off -> 11,633.33 -> 11,633.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e4')::uuid) = 11633, 'test 5: leaver 11,633';
  -- Test 7: manager (MS grade) overtime: 2 h x 48.0769 x 2 = 192.31; 5 h x 2 = 480.77; 4 h x 3 = 576.92
  --         = 1,250.00 -> 18,700.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e5')::uuid) = 18700, 'test 7: MS overtime 18,700';
  select amount into v_line from public.payroll_slip_lines
   where slip_id = (select slip_id from private.test_march_net where employee_id = current_setting('t.e5')::uuid) and code = 'OT_HOLIDAY';
  assert v_line = 576.92, 'holiday overtime line 576.92';
  -- OWNER-grade overtime is paid the same way: 17,450 + 192.31 = 17,642.31 -> 17,642.
  assert (select net from private.test_march_net where employee_id = current_setting('t.dir')::uuid) = 17642, 'test 7: OWNER-grade overtime';
  -- Test 6: 3 lates = 1 day (333.33) + 1 half day at 50% (166.67) = 500.00 -> 16,950. Pending overtime is ignored.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e6')::uuid) = 16950, 'test 6: late + half day 16,950';
  -- Test 9: increment to 20,000 from 16 Feb: February paid 17,450, arrears = 2,550 x 15 / 30 = 1,275.00 -> 21,275.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e7')::uuid) = 21275, 'test 9: arrears 21,275';
  -- Test 15: 17,450 - 20,000 = -2,550 -> net 0, 2,550 carried.
  assert (select net from private.test_march_net where employee_id = current_setting('t.e8')::uuid) = 0
     and (select carry_forward_out from private.test_march_net where employee_id = current_setting('t.e8')::uuid) = 2550,
    'test 15: negative net -> 0 and carry 2,550';
  assert (select warnings @> '[{"code":"large_change"}]' from public.payroll_slips
          where id = (select slip_id from private.test_march_net where employee_id = current_setting('t.e4')::uuid)),
    'a large change from last month is flagged';
  assert (select warnings @> '[{"code":"missing_payment_account"}]' from public.payroll_slips
          where id = (select slip_id from private.test_march_net where employee_id = current_setting('t.e2')::uuid)),
    'a missing payment account is flagged';
  raise notice 'PASS tests 4/5/6/7/9/10/14/15: March golden nets';
end $$;

-- Test 18 setup: a snapshot of every slip and line (no ids or timestamps).
create table private.test_march_snapshot as
  select s.employee_id,
         to_jsonb(s) - array['id', 'created_at', 'updated_at'] as slip,
         (select jsonb_agg(to_jsonb(l) - array['id', 'slip_id'] order by l.sort_order, l.code, l.amount)
          from public.payroll_slip_lines l where l.slip_id = s.id) as lines
  from public.payroll_slips s where s.run_id = current_setting('t.run_mar')::uuid;

-- Stale inputs: approved overtime added after calculation blocks the review.
do $$
begin
  insert into public.overtime_records (org_id, employee_id, work_date, minutes, day_type, multiplier, status, source)
  values (current_setting('t.org_a')::uuid, current_setting('t.hr')::uuid, '2026-03-25', 60, 'workday', 2, 'approved', 'manual');
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
  begin
    perform public.review_payroll_run(current_setting('t.run_mar')::uuid);
    raise exception 'FAIL: stale run reviewed';
  exception when invalid_parameter_value then null;
  end;
  delete from public.overtime_records where employee_id = current_setting('t.hr')::uuid and work_date = '2026-03-25';
  raise notice 'PASS: changing an input after calculation makes the run stale';
end $$;

set local role authenticated;
-- Test 18 and 17: the Admin recalculates (now the preparer) -> identical slips; then cannot approve.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.calculate_payroll_run(current_setting('t.run_mar')::uuid);
reset role;
do $$
begin
  assert (select count(*) from private.test_march_snapshot) = (select count(*) from public.payroll_slips where run_id = current_setting('t.run_mar')::uuid),
    'same number of slips';
  assert not exists (
    select 1 from private.test_march_snapshot m
    join public.payroll_slips s on s.employee_id = m.employee_id and s.run_id = current_setting('t.run_mar')::uuid
    where m.slip <> to_jsonb(s) - array['id', 'created_at', 'updated_at']
       or m.lines is distinct from (select jsonb_agg(to_jsonb(l) - array['id', 'slip_id'] order by l.sort_order, l.code, l.amount)
                                    from public.payroll_slip_lines l where l.slip_id = s.id)),
    'test 18: recalculation gives identical slips and lines';
  raise notice 'PASS test 18: recalculating gives identical slips';
end $$;

set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_payroll_run(current_setting('t.run_mar')::uuid);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.approve_payroll_run(current_setting('t.run_mar')::uuid);
    raise exception 'FAIL: preparer approved their own run';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 17: the preparer cannot approve their own run';
end $$;

-- HR recalculates (becomes the preparer again), reviews; the Admin approves.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.calculate_payroll_run(current_setting('t.run_mar')::uuid);
select public.review_payroll_run(current_setting('t.run_mar')::uuid);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.approve_payroll_run(current_setting('t.run_mar')::uuid);

reset role;
do $$
begin
  assert (select remaining from public.employee_deductions where id = current_setting('t.loan')::uuid) = 500,
    'loan balance 1,500 - 1,000 = 500 after approval';
  assert (select arrears_slip_id is not null from public.salary_increments where id = current_setting('t.increment')::uuid),
    'arrears marked as paid';
  assert (select status from public.payroll_adjustments where id = current_setting('t.adjust')::uuid) = 'applied',
    'adjustment applied';
  begin
    update public.payroll_slips set net = 1 where run_id = current_setting('t.run_mar')::uuid;
    raise exception 'FAIL: approved slip edited';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Test 19: approved runs are frozen; reopening needs a reason, reverses postings, is audited.
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.calculate_payroll_run(current_setting('t.run_mar')::uuid);
    raise exception 'FAIL: approved run recalculated';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.reopen_payroll_run(current_setting('t.run_mar')::uuid, '');
    raise exception 'FAIL: reopened without a reason';
  exception when not_null_violation then null;
  end;
  perform public.reopen_payroll_run(current_setting('t.run_mar')::uuid, 'Bonus list correction requested by HR');
end $$;
reset role;
do $$
begin
  assert (select remaining from public.employee_deductions where id = current_setting('t.loan')::uuid) = 1500,
    'reopen restores the loan balance';
  assert (select status from public.payroll_adjustments where id = current_setting('t.adjust')::uuid) = 'approved',
    'reopen restores the adjustment';
  assert exists (select 1 from public.audit_logs where action = 'payroll.reopened'), 'reopen is audited';
  raise notice 'PASS test 19: approved run frozen; reopen needs a reason, reverses postings, audited';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.calculate_payroll_run(current_setting('t.run_mar')::uuid);
select public.review_payroll_run(current_setting('t.run_mar')::uuid);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.approve_payroll_run(current_setting('t.run_mar')::uuid);

-- Recalculation created new slips; refresh the slip ids used below.
reset role;
truncate private.test_march_net;
insert into private.test_march_net
  select e.full_name, s.employee_id, s.net, s.gross_earnings, s.total_deductions, s.carry_forward_out, s.id
  from public.payroll_slips s join public.employees e on e.id = s.employee_id
  where s.run_id = current_setting('t.run_mar')::uuid;
-- Session temp tables are not visible to the authenticated role on Supabase,
-- so the slip ids used by the payslip checks travel as settings instead.
select set_config('t.slip_e1', (select slip_id::text from private.test_march_net where employee_id = current_setting('t.e1')::uuid), true),
       set_config('t.slip_e2', (select slip_id::text from private.test_march_net where employee_id = current_setting('t.e2')::uuid), true);
set local role authenticated;

-- Test 21: payment sheets.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.get_payment_sheet((select (b ->> 'id')::uuid
      from jsonb_array_elements(public.get_payroll_run(current_setting('t.run_mar')::uuid) -> 'batches') b
      where b ->> 'method' = 'bank'));
    raise exception 'FAIL: HR exported a payment sheet without payment.export';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
do $$
declare
  v_run   jsonb := public.get_payroll_run(current_setting('t.run_mar')::uuid);
  v_sheet jsonb;
begin
  assert (select sum((b ->> 'total')::numeric) from jsonb_array_elements(v_run -> 'batches') b)
         = (v_run -> 'run' ->> 'total_net')::numeric, 'test 21: batch totals equal the run net';
  v_sheet := public.get_payment_sheet((select (b ->> 'id')::uuid from jsonb_array_elements(v_run -> 'batches') b
                                       where b ->> 'method' = 'bank'));
  assert (v_sheet ->> 'total')::numeric = 21450, 'bank sheet total = E1 net';
  assert v_sheet -> 'rows' -> 0 ->> 'account_number' = '1234567890123', 'export has the full number';
  assert (public.get_payslip(current_setting('t.slip_e1')::uuid)
          -> 'payment' ->> 'masked_number') = '•••• 0123', 'the payslip shows the number masked';
  raise notice 'PASS test 21: payment sheet totals = slip nets; full numbers only in the export';
end $$;

-- Test 2: employee sees only their own released slips; manager sees no payroll.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_e1')), true);
do $$
begin
  assert jsonb_array_length(public.list_my_payslips()) = 2, 'E1 sees February and March';
  assert (public.get_payslip(current_setting('t.slip_e1')::uuid)
          -> 'slip' ->> 'net')::numeric = 21450, 'E1 opens their own slip';
  begin
    perform public.get_payslip(current_setting('t.slip_e2')::uuid);
    raise exception 'FAIL: employee opened a colleague''s slip';
  exception when no_data_found then null;
  end;
  begin
    perform public.list_payroll_runs();
    raise exception 'FAIL: employee listed runs';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_e5')), true);
do $$
begin
  begin
    perform public.get_payroll_run(current_setting('t.run_mar')::uuid);
    raise exception 'FAIL: manager read a payroll run';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 2: employee sees only own released slips; a manager sees no payroll';
end $$;

-- Test 20: pay every batch, lock the run -> the month is locked in Part 2.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
do $$
declare
  v_batch jsonb;
begin
  for v_batch in select b from jsonb_array_elements(public.get_payroll_run(current_setting('t.run_mar')::uuid) -> 'batches') b loop
    perform public.mark_payment_batch_paid((v_batch ->> 'id')::uuid, 'BANK-REF-03');
  end loop;
  assert (public.get_payroll_run(current_setting('t.run_mar')::uuid) -> 'run' ->> 'status') = 'paid', 'run paid';
  perform public.lock_payroll_run(current_setting('t.run_mar')::uuid);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.adjust_attendance(current_setting('t.e2')::uuid, '2026-03-10', '2026-03-10 09:00+06', '2026-03-10 18:00+06',
                                     'Late correction');
    raise exception 'FAIL: locked month changed';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 20: locking the run locks the month''s attendance';
end $$;

-- =============================================================== April run
do $$
declare
  v_run   uuid := public.create_payroll_run('2026-04-01');
  v_slips jsonb;
begin
  perform set_config('t.run_apr', v_run::text, true);
  perform public.calculate_payroll_run(v_run);
  v_slips := public.get_payroll_run(v_run) -> 'slips';
  -- Last installment is only what is left: 500 -> 16,950.
  assert (select (x ->> 'net')::numeric from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e1')) = 16950,
    'test 14: last installment 500';
  -- Carried shortfall: 17,450 - 2,550 = 14,900.
  assert (select (x ->> 'net')::numeric from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e8')) = 14900,
    'test 15: carry recovered next month';
  -- New pay, no second arrears.
  assert (select (x ->> 'net')::numeric from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e7')) = 20000,
    'test 9: arrears paid only once';
  assert not exists (select 1 from jsonb_array_elements(v_slips) x where x ->> 'employee_id' = current_setting('t.e4')),
    'the leaver is not paid after leaving';
  perform public.review_payroll_run(v_run);
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b2","role":"authenticated"}', true);
select public.approve_payroll_run(current_setting('t.run_apr')::uuid);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_run uuid := public.create_payroll_run('2026-05-01');
begin
  perform public.calculate_payroll_run(v_run);
  assert not exists (select 1 from jsonb_array_elements(public.get_payroll_run(v_run) -> 'slips') x
                     cross join jsonb_array_elements(public.get_payslip((x ->> 'id')::uuid) -> 'lines') l
                     where l ->> 'line_type' = 'loan'), 'test 14: no installment after the loan is repaid';
  raise notice 'PASS tests 9/14/15: April installment 500, carry recovered, arrears once; May has no installment';
end $$;
reset role;
do $$
begin
  assert (select remaining || '/' || status from public.employee_deductions where id = current_setting('t.loan')::uuid) = '0.00/completed',
    'test 14: the loan reaches zero and completes';
end $$;

-- ============================================ Beta: other rules (tests 6, 8, 16, 1)
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003b3","role":"authenticated"}', true);
do $$
declare
  v_dept     uuid;
  v_des      uuid;
  v_branch   uuid;
  v_office   uuid;
  v_template uuid;
begin
  -- Test 1: Beta cannot see Alpha payroll.
  begin
    perform public.get_payroll_run(current_setting('t.run_mar')::uuid);
    raise exception 'FAIL: Beta read Alpha run';
  exception when no_data_found then null;
  end;
  begin
    perform public.get_payslip(current_setting('t.slip_e1')::uuid);
    raise exception 'FAIL: Beta read Alpha slip';
  exception when no_data_found then null;
  end;
  assert jsonb_array_length(public.list_payroll_runs()) = 0, 'Beta sees no Alpha runs';

  insert into public.departments (name) values ('Knitting') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'EM1'), 'Knitter') returning id into v_des;
  insert into public.branches (name) values ('Gazipur') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Unit 1') returning id into v_office;
  v_template := public.save_salary_template(null, jsonb_build_object(
    'name', 'Worker', 'basic_amount', 10000,
    'lines', (select jsonb_agg(jsonb_build_object('component_id', id, 'calc', calc, 'value', default_value))
              from public.salary_components where not is_basic)));
  perform set_config('t.e9', public.create_employee(jsonb_build_object(
    'full_name', 'E9 Beta Worker', 'join_date', '2025-01-01', 'employment_type', 'permanent', 'department_id', v_dept,
    'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office))::text, true);
  perform public.set_initial_compensation(current_setting('t.e9')::uuid, v_template, 10000, null, null, 'Starting pay');

  -- Beta: deduction base gross, 200 taka per late, net rounded down.
  update public.payroll_settings set deduct_base = 'gross', net_rounding = 'down_taka';
  update public.org_work_settings set late_deduction_mode = 'amount_per_late', late_amount_per_late = 200;
end $$;

reset role;
insert into public.attendance_records (org_id, employee_id, work_date, day_type, status, is_late, late_minutes) values
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-03', 'workday', 'absent', false, 0),
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-04', 'workday', 'absent', false, 0),
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-05', 'workday', 'late', true, 30),
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-08', 'workday', 'late', true, 30),
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-09', 'workday', 'late', true, 30);
insert into public.overtime_records (org_id, employee_id, work_date, minutes, day_type, multiplier, status, source) values
  (current_setting('t.org_b')::uuid, current_setting('t.e9')::uuid, '2026-03-10', 120, 'workday', 2.00, 'approved', 'manual');
set local role authenticated;

do $$
declare
  v_run     uuid := public.create_payroll_run('2026-03-01');
  v_payslip jsonb;
begin
  perform public.calculate_payroll_run(v_run);
  v_payslip := public.get_payslip((select (x ->> 'id')::uuid from jsonb_array_elements(public.get_payroll_run(v_run) -> 'slips') x
                                   where x ->> 'employee_id' = current_setting('t.e9')));
  -- Test 8: daily rate on GROSS without overtime: 17,450 / 30 x 2 = 1,163.33 (Alpha on basic: 666.67).
  assert (select (l ->> 'amount')::numeric from jsonb_array_elements(v_payslip -> 'lines') l where l ->> 'line_type' = 'absence') = 1163.33,
    'test 8: absence on gross 1,163.33';
  -- Test 6: Beta's rule, 3 lates x 200 = 600.
  assert (select (l ->> 'amount')::numeric from jsonb_array_elements(v_payslip -> 'lines') l where l ->> 'line_type' = 'late') = 600,
    'test 6: Beta late penalty 600';
  -- Test 16: 17,450 + 192.31 - 1,163.33 - 600 = 15,878.98 -> rounded down 15,878.
  assert (v_payslip -> 'slip' ->> 'net_before_rounding')::numeric = 15878.98
     and (v_payslip -> 'slip' ->> 'net')::numeric = 15878, 'test 16: down-rounding 15,878';
  raise notice 'PASS tests 1/6/8/16: isolation; per-company late rule; gross base excludes overtime; rounding rule';
end $$;

reset role;
do $$ begin raise notice '==== ALL PART 3B CHECKS PASSED ===='; end $$;
select '==== ALL PART 3B CHECKS PASSED ====' as result;
rollback;
