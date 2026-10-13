-- =============================================================================
-- Part 2 acceptance checks (Part 2 architecture doc, Section 6).
-- Devices (tests 6-7) and live tracking (test 15) are deferred: no devices yet,
-- tracking comes with the mobile app. Test 8 (late old batch) is covered with
-- back-dated punches through the same intake function devices will use.
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL PART 2 CHECKS PASSED".
-- =============================================================================
begin;

-- ------------------------------------------------------------------ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'authenticated', 'authenticated', 'p2platform@olympus.test', now(), '{"full_name":"P2 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000e2', 'authenticated', 'authenticated', 'p2owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000e3', 'authenticated', 'authenticated', 'p2owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000e1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Apparels', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Knit', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e1","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org_a', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000e2'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000e3'));
end $$;

-- Alpha admin builds the structure, people and logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_op uuid; v_sup uuid; v_dhaka uuid; v_gaz uuid; v_hq uuid; v_f1 uuid; v_night uuid;
  v_hr_role uuid := (select id from public.roles where system_key = 'hr_manager');
  v_mgr_role uuid := (select id from public.roles where system_key = 'manager');
  v_common jsonb;
begin
  assert (select count(*) from public.shifts) = 1, 'a General shift is seeded';
  assert (select count(*) from public.leave_types) = 5, 'leave types are seeded';
  assert (select labor_regime from public.org_work_settings) = 'bd_labour_act', 'default law is the Labour Act';
  assert (select month_days from public.org_work_settings) = 30, 'salary month is 30 days';
  assert exists (select 1 from public.holidays where date = date '2026-03-26'), 'Independence Day is seeded';

  insert into public.departments (name) values ('Production') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'EM1'), 'Operator') returning id into v_op;
  insert into public.designations (department_id, grade_id, name)
    values (v_dept, (select id from public.grades where code = 'MS1'), 'Line Manager') returning id into v_sup;
  insert into public.branches (name) values ('Dhaka') returning id into v_dhaka;
  insert into public.branches (name) values ('Gazipur') returning id into v_gaz;
  insert into public.offices (branch_id, name) values (v_dhaka, 'HQ') returning id into v_hq;
  insert into public.offices (branch_id, name) values (v_gaz, 'Factory 1') returning id into v_f1;
  insert into public.shifts (name, code, start_time, end_time, break_minutes) values ('Night', 'NIGHT', '22:00', '06:00', 30)
    returning id into v_night;
  insert into public.geofences (office_id, name, latitude, longitude, radius_meters) values (v_hq, 'HQ gate', 23.810300, 90.412500, 150);

  perform set_config('t.hq', v_hq::text, true);
  perform set_config('t.f1', v_f1::text, true);
  perform set_config('t.night', v_night::text, true);

  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
                                 'department_id', v_dept, 'designation_id', v_op, 'branch_id', v_dhaka, 'office_id', v_hq);
  perform set_config('t.w', public.create_employee(v_common || '{"full_name":"Worker Day"}')::text, true);
  perform set_config('t.n', public.create_employee(v_common || jsonb_build_object(
    'full_name', 'Worker Night', 'branch_id', v_gaz, 'office_id', v_f1))::text, true);
  perform set_config('t.m', public.create_employee(v_common || jsonb_build_object(
    'full_name', 'Line Manager', 'designation_id', v_sup))::text, true);
  perform set_config('t.h', public.create_employee(v_common || '{"full_name":"HR Person"}')::text, true);
  perform set_config('t.o', public.create_employee(v_common || '{"full_name":"Other Team"}')::text, true);

  perform public.set_reporting_line(current_setting('t.w')::uuid, 'reporting_manager', current_setting('t.m')::uuid, '2026-01-01');
  perform public.set_reporting_line(current_setting('t.n')::uuid, 'reporting_manager', current_setting('t.m')::uuid, '2026-01-01');

  perform set_config('t.u_w', public.grant_portal_access(current_setting('t.w')::uuid, 'w@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_n', public.grant_portal_access(current_setting('t.n')::uuid, 'n@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_m', public.grant_portal_access(current_setting('t.m')::uuid, 'm@alpha.test', null, 'Passw0rd1', v_mgr_role)::text, true);
  perform set_config('t.u_h', public.grant_portal_access(current_setting('t.h')::uuid, 'h@alpha.test', null, 'Passw0rd1', v_hr_role)::text, true);
  perform set_config('t.u_o', public.grant_portal_access(current_setting('t.o')::uuid, 'o@alpha.test', null, 'Passw0rd1', null)::text, true);
  raise notice 'PASS setup: seeds (shift, leave types, 30-day month, Labour Act, holidays), people and logins';
end $$;

-- HR: rosters (overlap refused)
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  insert into public.shift_rosters (employee_id, shift_id, date_from, date_to)
  values (current_setting('t.n')::uuid, current_setting('t.night')::uuid, '2026-03-01', '2026-12-31');
  begin
    insert into public.shift_rosters (employee_id, shift_id, date_from, date_to)
    values (current_setting('t.n')::uuid, current_setting('t.night')::uuid, '2026-03-15', '2026-03-20');
    raise exception 'FAIL: overlapping roster accepted';
  exception when exclusion_violation then null;
  end;
  raise notice 'PASS roster: one shift per employee per date (overlap refused)';
end $$;

-- ---------------------------------------- back-dated punches (device-style intake)
reset role;
do $$
declare
  w uuid := current_setting('t.w')::uuid;
  n uuid := current_setting('t.n')::uuid;
  hq uuid := current_setting('t.hq')::uuid;
  f1 uuid := current_setting('t.f1')::uuid;
  p record;
begin
  for p in select * from (values
    -- day shift 09:00-18:00, grace 10, Friday off
    (w, '2026-03-02 09:05+06'), (w, '2026-03-02 18:02+06'),   -- present
    (w, '2026-03-03 09:30+06'), (w, '2026-03-03 18:00+06'),   -- late (30 min)
    (w, '2026-03-05 09:00+06'), (w, '2026-03-05 15:00+06'),   -- early out
    (w, '2026-03-08 09:00+06'), (w, '2026-03-08 12:00+06'),   -- half day
    (w, '2026-03-10 09:00+06'), (w, '2026-03-10 20:00+06'),   -- weekday overtime (capped 120)
    (w, '2026-03-06 09:00+06'), (w, '2026-03-06 15:00+06'),   -- Friday = weekend overtime
    (w, '2026-03-26 09:00+06'), (w, '2026-03-26 13:00+06'),   -- Independence Day = holiday overtime
    (w, '2026-03-12 09:25+06'), (w, '2026-03-12 18:00+06'),   -- late
    (w, '2026-03-15 09:40+06'), (w, '2026-03-15 18:00+06'),   -- late (3rd)
    -- night shift 22:00-06:00: the morning punch belongs to the start date
    (n, '2026-03-02 22:00+06'), (n, '2026-03-03 06:30+06')
  ) as x(emp, at) loop
    perform private.record_punch(p.emp, p.at::timestamptz, 'biometric', 'normal', null, hq,
                                 null, null, null, false, null, null, null);
  end loop;
  -- Two offices of the same company on one day: both accepted, office recorded.
  perform private.record_punch(w, '2026-03-09 09:00+06', 'web', 'normal', null, hq, null, null, null, false, null, null, null);
  perform private.record_punch(w, '2026-03-09 17:59+06', 'web', 'normal', null, f1, null, null, null, false, null, null, null);
  -- The same push twice changes nothing.
  perform private.record_punch(w, '2026-03-02 09:05+06', 'biometric', 'normal', null, hq, null, null, null, false, null, null, null);
  -- Close the days without punches.
  perform private.close_day_for_org(current_setting('t.org_a')::uuid, '2026-03-04');
  perform private.close_day_for_org(current_setting('t.org_a')::uuid, '2026-03-11');
end $$;

do $$
declare
  w uuid := current_setting('t.w')::uuid;
  r public.attendance_records;
begin
  select * into r from public.attendance_records where employee_id = w and work_date = '2026-03-02';
  assert r.status = 'present' and not r.is_late, 'test 3: 09:05 within grace is present, got ' || r.status;
  assert (select count(*) from public.attendance_punches where employee_id = w and punched_at = '2026-03-02 09:05+06') = 1,
    'test 6: duplicate push stored once';
  select * into r from public.attendance_records where employee_id = w and work_date = '2026-03-03';
  assert r.status = 'late' and r.late_minutes = 30, 'test 3: late 30 minutes, got ' || r.status || ' ' || r.late_minutes;
  assert (select status from public.attendance_records where employee_id = w and work_date = '2026-03-04') = 'absent',
    'test 3: no punch after the cut-off is absent';
  select * into r from public.attendance_records where employee_id = w and work_date = '2026-03-05';
  assert r.status = 'early_out' and r.early_out_minutes = 180, 'test 3: early out 180, got ' || r.status;
  assert (select status from public.attendance_records where employee_id = w and work_date = '2026-03-08') = 'half_day',
    'half day below the threshold';
  raise notice 'PASS test 3: present / late / absent / early out / half day';

  select * into r from public.attendance_records where employee_id = current_setting('t.n')::uuid and work_date = '2026-03-02';
  assert r.check_out_at = '2026-03-03 06:30+06', 'test 4: night check-out belongs to the start date';
  assert not exists (select 1 from public.attendance_records
                     where employee_id = current_setting('t.n')::uuid and work_date = '2026-03-03' and check_in_at is not null),
    'test 4: no check-in invented on the next day';
  assert r.overtime_minutes = 30, 'night overtime 30, got ' || r.overtime_minutes;
  raise notice 'PASS test 4: night shift punch after midnight counts on the start date';

  select * into r from public.attendance_records where employee_id = w and work_date = '2026-03-09';
  assert r.office_id = current_setting('t.hq')::uuid, 'test 5: record office = check-in office';
  assert (select count(distinct office_id) from public.attendance_punches
          where employee_id = w and punched_at::date between '2026-03-09' and '2026-03-10') = 2,
    'test 5: punches at two offices both kept';
  raise notice 'PASS test 5: punches at different offices accepted, office recorded';

  assert (select minutes from public.overtime_records where employee_id = w and work_date = '2026-03-10') = 120,
    'test 12: weekday overtime capped at 120';
  assert (select minutes || '/' || day_type || '/' || multiplier from public.overtime_records
          where employee_id = w and work_date = '2026-03-06') = '300/weekend/2.00',
    'test 12: weekend overtime = worked time';
  assert (select minutes || '/' || day_type from public.overtime_records
          where employee_id = w and work_date = '2026-03-26') = '240/holiday',
    'test 12: holiday overtime = worked time';
  raise notice 'PASS test 12: overtime for weekday, weekend and holiday';

  -- Test 8: an old batch arrives after the day was closed as absent.
  assert (select status from public.attendance_records where employee_id = w and work_date = '2026-03-11') = 'absent';
  perform private.record_punch(w, '2026-03-11 08:58+06', 'biometric', 'normal', null, current_setting('t.hq')::uuid,
                               null, null, null, false, null, null, null);
  perform private.record_punch(w, '2026-03-11 18:05+06', 'biometric', 'normal', null, current_setting('t.hq')::uuid,
                               null, null, null, false, null, null, null);
  assert (select status from public.attendance_records where employee_id = w and work_date = '2026-03-11') = 'present',
    'test 8: late batch rebuilds the day';
  raise notice 'PASS test 8: a late-arriving old batch rebuilds the correct day';

  -- Test 16: the close job twice gives the same result.
  perform set_config('t.snap', (select jsonb_agg(to_jsonb(r2) order by r2.work_date)::text
                                from public.attendance_records r2 where r2.employee_id = w), true);
  perform private.close_day_for_org(current_setting('t.org_a')::uuid, '2026-03-04');
  perform private.close_day_for_org(current_setting('t.org_a')::uuid, '2026-03-04');
  assert (select jsonb_agg(to_jsonb(r2) order by r2.work_date)::text from public.attendance_records r2 where r2.employee_id = w)
         = current_setting('t.snap'), 'test 16: re-running the close job changes nothing';
  raise notice 'PASS test 16: daily close is idempotent';

  begin
    update public.attendance_punches set note = 'tampered' where employee_id = w;
    raise exception 'FAIL: raw punch edited';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.attendance_punches where employee_id = w;
    raise exception 'FAIL: raw punch deleted';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 14: raw punches cannot be edited or deleted (even by the owner)';
end $$;

-- ------------------------------------------------------------ visibility
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w')), true);
do $$
begin
  assert (select count(distinct employee_id) from public.attendance_v) = 1, 'test 2: employee sees only own attendance';
  assert (select bool_and(is_self) from public.attendance_v), 'test 2: only own rows';
  begin
    insert into public.shifts (name, code, start_time, end_time) values ('X', 'X', '08:00', '17:00');
    raise exception 'FAIL: employee created a shift';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 2: employee sees only their own records';
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
begin
  assert (select count(distinct employee_id) from public.attendance_v where not is_self) = 2, 'manager sees the two team members';
  assert not exists (select 1 from public.attendance_v where employee_id in (current_setting('t.o')::uuid, current_setting('t.h')::uuid)),
    'manager does not see people outside the team';
  assert (select count(*) from public.overtime_v) > 0, 'manager sees team overtime';
  raise notice 'PASS: manager sees their reporting team, not the whole company';
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
declare
  v_sum jsonb;
  v_w   jsonb;
begin
  assert (select count(distinct employee_id) from public.attendance_v) >= 2, 'HR sees everyone';
  -- Late deduction: 3 lates in March -> 1 day (default 3 lates = 1 day).
  v_sum := public.get_attendance_summary('2026-03-01');
  select x into v_w from jsonb_array_elements(v_sum -> 'rows') x where x ->> 'employee_id' = current_setting('t.w');
  assert (v_w ->> 'late_count')::int = 3, 'three lates, got ' || (v_w ->> 'late_count');
  assert (v_w ->> 'late_deduction_days')::numeric = 1, 'three lates = one day deducted';
  assert (v_sum ->> 'month_days')::int = 30, 'month is 30 days';
  update public.org_work_settings set late_deduction_mode = 'amount_per_late', late_amount_per_late = 200;
  select x into v_w from jsonb_array_elements(public.get_attendance_summary('2026-03-01') -> 'rows') x
   where x ->> 'employee_id' = current_setting('t.w');
  assert (v_w ->> 'late_deduction_amount')::numeric = 600, '3 lates x 200 taka = 600';
  raise notice 'PASS: late deduction policy (days per N lates, or taka per late) on a 30-day month';

  -- Test 13: manual fix needs a reason, is audited, cannot be done on yourself.
  begin
    perform public.adjust_attendance(current_setting('t.w')::uuid, '2026-03-04', '2026-03-04 09:00+06', '2026-03-04 18:00+06', '');
    raise exception 'FAIL: fix without reason';
  exception when not_null_violation then null;
  end;
  perform public.adjust_attendance(current_setting('t.w')::uuid, '2026-03-04', '2026-03-04 09:00+06', '2026-03-04 18:00+06',
                                   'Forgot to punch, confirmed by manager');
  assert (select status || '/' || source_in from public.attendance_v
          where employee_id = current_setting('t.w')::uuid and work_date = '2026-03-04') = 'present/manual',
    'manual fix sets source manual';
  begin
    perform public.adjust_attendance(current_setting('t.h')::uuid, '2026-03-04', '2026-03-04 09:00+06', null, 'self');
    raise exception 'FAIL: self fix accepted';
  exception when insufficient_privilege then null;
  end;

  -- Geofence admin and labour law switch.
  perform public.apply_labor_regime_defaults('bd_epz_labour_act');
  assert (select labor_regime from public.org_work_settings) = 'bd_epz_labour_act', 'EPZ law applied';
  raise notice 'PASS test 13 (part): manual fix needs a reason, is not allowed on yourself; law switch works';
end $$;

reset role;
do $$
begin
  assert exists (select 1 from public.audit_logs where action = 'attendance.adjusted'), 'test 13: fix written to the audit log';
end $$;

-- ------------------------------------------------------------- live punches
set local role authenticated;
-- Test 9: GPS outside the radius is flagged, not blocked.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w')), true);
do $$
declare
  v jsonb;
begin
  v := public.punch('gps', 23.900000, 90.500000, 20);
  assert (v ->> 'outside_geofence')::boolean, 'test 9: far away is flagged';
  begin
    perform public.punch('web');
    raise exception 'FAIL: double punch accepted';
  exception when unique_violation then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_o')), true);
do $$
declare
  v jsonb;
begin
  v := public.punch('gps', 23.810350, 90.412550, 15);
  assert not (v ->> 'outside_geofence')::boolean, 'test 9: inside the radius is not flagged';
  assert (v ->> 'office_id')::uuid = current_setting('t.hq')::uuid, 'office comes from the geofence';
  raise notice 'PASS test 9: GPS outside the radius is flagged, not blocked';
end $$;

-- QR: issue, use once, reuse refused, expired refused.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  perform set_config('t.qr', public.issue_qr_code(current_setting('t.hq')::uuid) ->> 'code', true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_n')), true);
do $$
begin
  perform public.punch('qr', null, null, null, current_setting('t.qr'));
  begin
    perform public.punch('qr', null, null, null, current_setting('t.qr'));
    raise exception 'FAIL: reused QR accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;
reset role;
insert into public.qr_checkin_codes (org_id, office_id, code_hash, valid_from, valid_until)
values (current_setting('t.org_a')::uuid, current_setting('t.hq')::uuid,
        encode(extensions.digest('expired-code', 'sha256'), 'hex'), now() - interval '10 minutes', now() - interval '9 minutes');
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
begin
  begin
    perform public.punch('qr', null, null, null, 'expired-code');
    raise exception 'FAIL: expired QR accepted';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS test 9: a reused or expired QR code is rejected';
end $$;

-- ------------------------------------------------------------------ leave
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w')), true);
do $$
declare
  v_cl uuid := (select id from public.leave_types where code = 'CL');
  v_b  jsonb;
begin
  perform set_config('t.leave', public.request_leave(v_cl, '2026-11-02', '2026-11-03', false, 'Family event')::text, true);
  select x into v_b from jsonb_array_elements(public.get_leave_balances(null, 2026)) x where x ->> 'code' = 'CL';
  assert (v_b ->> 'pending')::numeric = 2 and (v_b ->> 'available')::numeric = 8, 'test 10: request reserves 2 days';
  begin
    perform public.request_leave(v_cl, '2026-11-03', '2026-11-03', false, null);
    raise exception 'FAIL: overlapping leave accepted';
  exception when exclusion_violation then null;
  end;
  begin
    perform public.request_leave(v_cl, '2026-12-01', '2026-12-20', false, null);
    raise exception 'FAIL: over-balance accepted';
  exception when check_violation then null;
  end;
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
declare
  v_cl uuid := (select id from public.leave_types where code = 'CL');
begin
  perform public.decide_leave(current_setting('t.leave')::uuid, true, 'OK');
  assert (select status from public.attendance_v where employee_id = current_setting('t.w')::uuid and work_date = '2026-11-02') = 'on_leave',
    'test 10: approval sets on_leave';
  -- Test 11: the manager cannot approve their own leave.
  perform set_config('t.leave_m', public.request_leave(v_cl, '2026-11-10', '2026-11-10', false, null)::text, true);
  begin
    perform public.decide_leave(current_setting('t.leave_m')::uuid, true, null);
    raise exception 'FAIL: self approval';
  exception when insufficient_privilege then null;
  end;
  -- Manager approves team overtime, not their own.
  perform public.decide_overtime((select id from public.overtime_v
                                  where employee_id = current_setting('t.w')::uuid and work_date = '2026-03-10'), true, null);
  raise notice 'PASS test 11: nobody approves their own request';
end $$;

-- Other team's leave cannot be decided by this manager; HR can.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_o')), true);
do $$
begin
  perform set_config('t.leave_o', public.request_leave((select id from public.leave_types where code = 'SL'),
                                                       '2026-11-12', '2026-11-12', false, 'Doctor note #42')::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
begin
  begin
    perform public.decide_leave(current_setting('t.leave_o')::uuid, true, null);
    raise exception 'FAIL: manager decided outside the team';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  perform public.decide_leave(current_setting('t.leave_m')::uuid, true, 'HR approves manager');
  perform public.decide_leave(current_setting('t.leave_o')::uuid, false, 'Need the document');
  raise notice 'PASS: approvals follow the reporting chain; HR can decide for anyone else';
end $$;

-- Cancellation restores balance and attendance.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w')), true);
do $$
declare
  v_b jsonb;
begin
  perform public.cancel_leave(current_setting('t.leave')::uuid, 'Plans changed');
  select x into v_b from jsonb_array_elements(public.get_leave_balances(null, 2026)) x where x ->> 'code' = 'CL';
  assert (v_b ->> 'used')::numeric = 0 and (v_b ->> 'available')::numeric = 10, 'test 10: cancel restores the balance';
  assert not exists (select 1 from public.attendance_v where work_date = '2026-11-02' and status = 'on_leave'),
    'test 10: cancel restores attendance';
  raise notice 'PASS test 10: reserve -> approve (on_leave) -> cancel restores both';

  -- Shift swap: day worker <-> night worker on 4 Nov.
  perform set_config('t.swap', public.request_shift_swap(current_setting('t.n')::uuid, '2026-11-04', 'Exam')::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_n')), true);
select public.respond_shift_swap(current_setting('t.swap')::uuid, true);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
select public.decide_shift_swap(current_setting('t.swap')::uuid, true, null);
reset role;
do $$
begin
  assert private.resolve_shift_id(current_setting('t.w')::uuid, '2026-11-04') = current_setting('t.night')::uuid,
    'approved swap changes the roster for that date';
  assert private.resolve_shift_id(current_setting('t.w')::uuid, '2026-11-05') <> current_setting('t.night')::uuid,
    'only that date';
  raise notice 'PASS: shift swap request -> peer accept -> manager approve -> roster override';
end $$;

-- --------------------------------------------------------------- files
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w')), true);
do $$
declare
  base text := current_setting('t.org_a') || '/' || current_setting('t.w') || '/';
begin
  assert private.employee_file_access(base || 'photo', true), 'own photo upload allowed';
  assert private.employee_file_access(base || 'nid', false), 'own NID readable';
  assert not private.employee_file_access(base || 'nid', true), 'employee cannot replace own NID scan';
  assert not private.employee_file_access(current_setting('t.org_a') || '/' || current_setting('t.o') || '/photo', false),
    'employee cannot read a colleague''s photo';
  assert not private.employee_file_access(base || '../x', false), 'bad paths refused';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
declare
  base text := current_setting('t.org_a') || '/' || current_setting('t.w') || '/';
begin
  assert private.employee_file_access(base || 'photo', false), 'manager (employees.view) sees photos';
  assert not private.employee_file_access(base || 'nid', false), 'manager does not see NID scans';
  assert not private.org_asset_access(current_setting('t.org_a') || '/logo', true), 'manager cannot change the logo';
  assert private.org_asset_access(current_setting('t.org_a') || '/logo', false), 'everyone in the org sees the logo';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e3","role":"authenticated"}', true);
do $$
begin
  assert not private.employee_file_access(current_setting('t.org_a') || '/' || current_setting('t.w') || '/photo', false),
    'test 1: another company cannot read files';
  assert not private.org_asset_access(current_setting('t.org_a') || '/logo', false), 'test 1: nor the logo';
  assert (select count(*) from public.attendance_v) = 0, 'test 1: Beta sees no Alpha attendance';
  assert (select count(*) from public.leave_requests_v) = 0, 'test 1: Beta sees no Alpha leave';
  assert (select count(*) from public.overtime_v) = 0, 'test 1: Beta sees no Alpha overtime';
  begin
    perform public.decide_leave(current_setting('t.leave_m')::uuid, false, null);
    raise exception 'FAIL: Beta decided Alpha leave';
  exception when no_data_found then null;
  end;
  raise notice 'PASS test 1: no attendance, leave, overtime or file crosses companies; file access follows roles';
end $$;

-- ------------------------------------------------------------- period lock
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e2","role":"authenticated"}', true);
select public.set_period_lock('2026-03-01', '2026-03-31', true, 'March payroll');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  begin
    perform public.adjust_attendance(current_setting('t.w')::uuid, '2026-03-05', '2026-03-05 09:00+06', '2026-03-05 18:00+06', 'late fix');
    raise exception 'FAIL: locked period changed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_period_lock('2026-03-01', '2026-03-31', false, null);
    raise exception 'FAIL: HR unlocked a period';
  exception when insufficient_privilege then null;
  end;
  assert (select bool_and(locked) from public.attendance_v where work_date between '2026-03-01' and '2026-03-31'),
    'records in the period are locked';
  raise notice 'PASS test 13: a locked payroll period refuses fixes; only Admin can lock/unlock';
end $$;

reset role;
do $$
begin
  -- Rebuild must not touch locked rows.
  perform private.rebuild_attendance_day(current_setting('t.w')::uuid, '2026-03-05');
  assert (select status from public.attendance_records where employee_id = current_setting('t.w')::uuid and work_date = '2026-03-05') = 'early_out',
    'locked rows are never rebuilt';
end $$;

do $$ begin raise notice '==== ALL PART 2 CHECKS PASSED ===='; end $$;
select '==== ALL PART 2 CHECKS PASSED ====' as result;
rollback;
