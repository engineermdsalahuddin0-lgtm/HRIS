-- =============================================================================
-- TMS T2 tests: trips.
--
-- Alpha: Owner (Admin), Hana (HR Manager: desk), Mona (Manager, Sales: approves Sales), Sam (Sales employee:
-- requests), Dave (Admin-dept employee: a driver with a login). Beta: another company.
--   1. Sam requests; Mona approves (Sam cannot); a refusal needs a reason; the desk's own trips are approved at once.
--   2. Assignment refuses a vehicle in maintenance, a licence class too low, and a time clash.
--   3. Dave starts and ends: odometer never below the last reading; GPS points only at start / end; distance;
--      expenses by the driver only.
--   4. Cancelling: the requester before the start; never after; other companies see nothing.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL TMS T2 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000e2001', 'authenticated', 'authenticated', 't2platform@olympus.test', now(), '{"full_name":"T2 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e2002', 'authenticated', 'authenticated', 't2owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e2003', 'authenticated', 'authenticated', 't2owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000e2001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e2002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Trips', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e2003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Trips', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e2001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e2002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e2003'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e2002","role":"authenticated"}', true);
do $$
declare
  v_adm uuid; v_sales uuid; v_des_a uuid; v_des_s uuid; v_branch uuid; v_office uuid; v_base jsonb;
begin
  insert into public.departments (name, code) values ('Admin', 'ADM') returning id into v_adm;
  insert into public.departments (name, code) values ('Sales', 'SAL') returning id into v_sales;
  insert into public.designations (department_id, grade_id, name) values (v_adm, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des_a;
  insert into public.designations (department_id, grade_id, name) values (v_sales, (select id from public.grades where code = 'EM1'), 'Sales Officer') returning id into v_des_s;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  v_base := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_base || jsonb_build_object('full_name', 'Hana HR', 'department_id', v_adm, 'designation_id', v_des_a)),
      'hana@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(public.create_employee(v_base || jsonb_build_object('full_name', 'Mona Manager', 'department_id', v_sales, 'designation_id', v_des_s)),
      'mona@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(v_base || jsonb_build_object('full_name', 'Sam Sales', 'department_id', v_sales, 'designation_id', v_des_s)),
      'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.e_dave', public.create_employee(v_base || jsonb_build_object('full_name', 'Dave Driver', 'department_id', v_adm, 'designation_id', v_des_a))::text, true);
  perform set_config('t.u_dave', public.grant_portal_access(current_setting('t.e_dave')::uuid, 'dave@alpha.test', null, 'Passw0rd1', null)::text, true);
end $$;

-- The desk sets up the fleet.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  perform set_config('t.d_dave', public.save_tms_driver(null, jsonb_build_object('employee_id', current_setting('t.e_dave'),
    'licence_no', 'DK1111111L', 'licence_class', 'light', 'licence_expiry', (current_date + 300)::text))::text, true);
  perform set_config('t.v_car', public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-GA 12-0001","vtype":"car","fuel":"octane","odometer_km":1000}')::text, true);
  perform set_config('t.v_car2', public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-GA 12-0002","vtype":"car","fuel":"octane"}')::text, true);
  perform set_config('t.v_truck', public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-TA 11-0003","vtype":"truck","fuel":"diesel"}')::text, true);
  perform public.save_tms_vehicle(current_setting('t.v_car2')::uuid, '{"reg_no":"Dhaka Metro-GA 12-0002","status":"in_maintenance"}');
end $$;

-- ======================================================= 1. request and approval
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  perform set_config('t.trip1', public.create_tms_trip(jsonb_build_object('purpose', 'Client visit at Gulshan', 'from_place', 'HQ',
    'to_place', 'Gulshan 2', 'planned_start', (now() + interval '1 day')::text, 'planned_end', (now() + interval '1 day 4 hours')::text,
    'passengers', 2))::text, true);
  perform set_config('t.trip_x', public.create_tms_trip(jsonb_build_object('purpose', 'Weekend trip', 'from_place', 'HQ',
    'to_place', 'Cox''s Bazar', 'planned_start', (now() + interval '3 days')::text, 'planned_end', (now() + interval '5 days')::text))::text, true);
  assert (public.get_tms_trip(current_setting('t.trip1')::uuid) ->> 'status') = 'requested', 'waits for approval';
  begin
    perform public.decide_tms_trip(current_setting('t.trip1')::uuid, true, null);
    raise exception 'FAIL: approved own request';
  exception when insufficient_privilege or check_violation then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  assert jsonb_array_length(public.list_tms_trips('{"scope":"approve"}')) = 2, 'Mona sees Sales requests';
  begin
    perform public.decide_tms_trip(current_setting('t.trip_x')::uuid, false, '');
    raise exception 'FAIL: refused without a reason';
  exception when invalid_parameter_value then null;
  end;
  perform public.decide_tms_trip(current_setting('t.trip_x')::uuid, false, 'Not a business trip');
  perform public.decide_tms_trip(current_setting('t.trip1')::uuid, true, null);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  perform set_config('t.trip2', public.create_tms_trip(jsonb_build_object('kind', 'delivery', 'purpose', 'Deliver samples', 'from_place', 'HQ',
    'to_place', 'Tongi', 'cargo', '3 cartons', 'customer', 'Acme Ltd', 'planned_start', (now() + interval '1 day 1 hour')::text,
    'planned_end', (now() + interval '1 day 3 hours')::text))::text, true);
  assert (public.get_tms_trip(current_setting('t.trip2')::uuid) ->> 'status') = 'approved', 'the desk''s own trip is approved at once';
  raise notice 'PASS: requests wait for the department manager; no self-approval; a refusal has a reason; desk trips go straight';
end $$;

-- ======================================================= 2. assignment checks
do $$
begin
  begin
    perform public.assign_tms_trip(current_setting('t.trip1')::uuid, current_setting('t.v_car2')::uuid, current_setting('t.d_dave')::uuid);
    raise exception 'FAIL: a vehicle in maintenance';
  exception when check_violation then assert sqlerrm like '%in maintenance%', sqlerrm;
  end;
  begin
    perform public.assign_tms_trip(current_setting('t.trip1')::uuid, current_setting('t.v_truck')::uuid, current_setting('t.d_dave')::uuid);
    raise exception 'FAIL: a light licence on a truck';
  exception when check_violation then assert sqlerrm like '%does not cover%', sqlerrm;
  end;
  perform public.assign_tms_trip(current_setting('t.trip1')::uuid, current_setting('t.v_car')::uuid, current_setting('t.d_dave')::uuid);
  begin
    perform public.assign_tms_trip(current_setting('t.trip2')::uuid, current_setting('t.v_car')::uuid, current_setting('t.d_dave')::uuid);
    raise exception 'FAIL: double booking';
  exception when check_violation then assert sqlerrm like '%booked for another trip%' and sqlerrm like '%another trip at that time%', sqlerrm;
  end;
  assert (select jsonb_array_length(x -> 'problems') from jsonb_array_elements(public.tms_assign_options(current_setting('t.trip2')::uuid) -> 'vehicles') x
          where x ->> 'id' = current_setting('t.v_car')) = 1, 'the dialog says why the car is not free';
  raise notice 'PASS: assignment refuses vehicles in maintenance, low licence classes and time clashes';
end $$;

-- ======================================================= 3. the driver starts and ends
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.start_tms_trip(current_setting('t.trip1')::uuid, '{"odometer_km":1010}');
    raise exception 'FAIL: the requester started the trip';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_dave')), true);
do $$
declare
  t jsonb;
begin
  assert (public.get_tms_me() ->> 'my_open_trips')::int = 1, 'Dave has one trip';
  begin
    perform public.start_tms_trip(current_setting('t.trip1')::uuid, '{"odometer_km":900}');
    raise exception 'FAIL: odometer went back';
  exception when check_violation then null;
  end;
  t := public.start_tms_trip(current_setting('t.trip1')::uuid, '{"odometer_km":1010,"lat":23.7806,"lng":90.4070,"accuracy_m":12}');
  assert t ->> 'status' = 'in_progress', 'started';
  perform public.add_tms_trip_expense(current_setting('t.trip1')::uuid, '{"kind":"toll","amount":100,"note":"Flyover"}');
  begin
    perform public.end_tms_trip(current_setting('t.trip1')::uuid, '{"odometer_km":1005}');
    raise exception 'FAIL: end below start';
  exception when check_violation then null;
  end;
  t := public.end_tms_trip(current_setting('t.trip1')::uuid, '{"odometer_km":1042.5,"lat":23.7925,"lng":90.4078}');
  assert (t ->> 'distance_km')::numeric = 32.5 and (t ->> 'expenses_total')::numeric = 100, 'distance and expenses ' || t::text;
  assert jsonb_array_length(public.get_tms_trip(current_setting('t.trip1')::uuid) -> 'points') = 2, 'GPS only at start and end';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  assert (public.get_tms_vehicle(current_setting('t.v_car')::uuid) ->> 'odometer_km')::numeric = 1042.5, 'the vehicle odometer follows the trip';
  raise notice 'PASS: the driver starts and ends with odometer and GPS; distance and expenses are on the trip';
end $$;

-- ======================================================= 4. cancelling, isolation
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.cancel_tms_trip(current_setting('t.trip1')::uuid, 'Changed plans');
    raise exception 'FAIL: cancelled a finished trip';
  exception when check_violation then null;
  end;
  perform set_config('t.trip3', public.create_tms_trip(jsonb_build_object('purpose', 'Bank visit', 'from_place', 'HQ', 'to_place', 'Motijheel',
    'planned_start', (now() + interval '2 days')::text, 'planned_end', (now() + interval '2 days 2 hours')::text))::text, true);
  perform public.cancel_tms_trip(current_setting('t.trip3')::uuid, 'No longer needed');
  assert (public.get_tms_trip(current_setting('t.trip3')::uuid) ->> 'status') = 'cancelled', 'cancelled';
  assert jsonb_array_length(public.list_tms_trips('{"scope":"mine"}')) = 3, 'Sam lists his requests';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e2003","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_tms_trip(current_setting('t.trip1')::uuid);
    raise exception 'FAIL: Beta opened an Alpha trip';
  exception when no_data_found then null;
  end;
  assert jsonb_array_length(public.list_tms_trips('{"scope":"all"}')) = 0, 'Beta sees no Alpha trip';
  raise notice 'PASS: the requester cancels before the start, never after; other companies see nothing';
end $$;

select '==== ALL TMS T2 CHECKS PASSED ====' as result;
rollback;
