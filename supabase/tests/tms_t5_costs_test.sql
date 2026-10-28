-- =============================================================================
-- TMS T5 tests: cost dashboard.
--
-- Alpha: Owner (Admin: sees costs), Hana (HR Manager: desk, no tms.view_costs), Dave (driver).
-- Car this month: trip 1,000 → 1,100 km with a ৳100 toll; fuel 10 L × ৳130 at 1,050 km; a closed job card with
-- ৳500 labour + ৳200 outside parts + 2 × ৳300 parts from stock = ৳1,300.
--   1. Total ৳2,700 over 100 km = ৳27 per km; fuel quantity per unit; a disputed fill is left out.
--   2. The live view lists a vehicle on a trip with its last GPS point.
--   3. The desk without tms.view_costs cannot open costs.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL TMS T5 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000e5001', 'authenticated', 'authenticated', 't5platform@olympus.test', now(), '{"full_name":"T5 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e5002', 'authenticated', 'authenticated', 't5owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000e5001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e5002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Costs', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e5001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e5002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e5002","role":"authenticated"}', true);
do $$
declare
  v_adm uuid; v_des uuid; v_branch uuid; v_office uuid; v_base jsonb;
begin
  insert into public.departments (name, code) values ('Admin', 'ADM') returning id into v_adm;
  insert into public.designations (department_id, grade_id, name) values (v_adm, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  v_base := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office,
                               'department_id', v_adm, 'designation_id', v_des);
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_base || '{"full_name":"Hana HR"}'),
      'hana@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.e_dave', public.create_employee(v_base || '{"full_name":"Dave Driver"}')::text, true);
end $$;

-- The desk runs a month of transport.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v_driver uuid; v_car uuid; v_trip uuid; v_job uuid; v_part uuid; v_trip2 uuid; f jsonb;
begin
  v_driver := public.save_tms_driver(null, jsonb_build_object('employee_id', current_setting('t.e_dave'), 'licence_no', 'DK5555555L',
                'licence_class', 'light', 'licence_expiry', (current_date + 300)::text));
  v_car := public.save_tms_vehicle(null, jsonb_build_object('reg_no', 'Dhaka Metro-GA 55-0001', 'vtype', 'car', 'fuel', 'octane', 'tank_l', 40,
             'odometer_km', 1000, 'driver_id', v_driver));
  perform set_config('t.v_car', v_car::text, true);
  perform public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-GA 55-0002","vtype":"car","fuel":"octane"}');
  v_trip := public.create_tms_trip(jsonb_build_object('purpose', 'Client', 'from_place', 'HQ', 'to_place', 'Uttara',
              'planned_start', (now() + interval '1 hour')::text, 'planned_end', (now() + interval '5 hours')::text));
  perform public.assign_tms_trip(v_trip, v_car, v_driver);
  perform public.start_tms_trip(v_trip, '{"odometer_km":1000}');
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', v_car, 'fuel', 'octane', 'quantity', 10, 'unit_price', 130, 'odometer_km', 1050, 'trip_id', v_trip));
  perform public.add_tms_trip_expense(v_trip, '{"kind":"toll","amount":100}');
  perform public.end_tms_trip(v_trip, '{"odometer_km":1100}');
  -- A disputed fill does not count.
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', v_car, 'fuel', 'octane', 'quantity', 30, 'unit_price', 130, 'odometer_km', 1100, 'full_tank', false));
  perform public.review_tms_fuel((f ->> 'id')::uuid, false, 'Not our car that day');
  v_job := public.open_tms_job_card(jsonb_build_object('vehicle_id', v_car, 'kind', 'repair', 'description', 'Brake pads'));
  v_part := public.save_tms_part(null, '{"code":"BRK-01","name":"Brake pad","unit":"pcs"}');
  perform public.tms_stock_move(jsonb_build_object('part_id', v_part, 'kind', 'receive', 'qty', 4, 'unit_cost', 300));
  perform public.tms_stock_move(jsonb_build_object('part_id', v_part, 'kind', 'issue', 'qty', 2, 'job_card_id', v_job));
  perform public.close_tms_job_card(v_job, '{"labour_cost":500,"outside_parts_cost":200}');
  -- A second trip running now, for the live view.
  v_trip2 := public.create_tms_trip(jsonb_build_object('purpose', 'Bank', 'from_place', 'HQ', 'to_place', 'Motijheel',
              'planned_start', (now() + interval '6 hours')::text, 'planned_end', (now() + interval '8 hours')::text));
  perform public.assign_tms_trip(v_trip2, v_car, v_driver);
  perform public.start_tms_trip(v_trip2, '{"odometer_km":1100,"lat":23.7330,"lng":90.4172}');
  -- ======================================================= 3. the desk alone cannot see money totals
  begin
    perform public.get_tms_costs(null, null);
    raise exception 'FAIL: the desk opened costs without tms.view_costs';
  exception when insufficient_privilege then null;
  end;
end $$;

-- ======================================================= 1–2. the owner's dashboard
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e5002","role":"authenticated"}', true);
do $$
declare
  c jsonb := public.get_tms_costs(null, null);
  v jsonb := (select x from jsonb_array_elements(c -> 'vehicles') x where x ->> 'id' = current_setting('t.v_car'));
begin
  assert (v ->> 'distance_km')::numeric = 100, 'distance from odometer readings ' || v::text;
  assert (v ->> 'fuel_cost')::numeric = 1300 and (v -> 'fuel_qty' ->> 'l')::numeric = 10, 'fuel without the disputed fill ' || v::text;
  assert (v ->> 'repair_cost')::numeric = 1300 and (v ->> 'trip_cost')::numeric = 100, 'repairs and trip costs ' || v::text;
  assert (v ->> 'total_cost')::numeric = 2700 and (v ->> 'cost_per_km')::numeric = 27, 'total and per km ' || v::text;
  assert (c -> 'totals' ->> 'total_cost')::numeric = 2700 and jsonb_array_length(c -> 'vehicles') = 2, 'fleet totals ' || (c -> 'totals')::text;
  assert jsonb_array_length(c -> 'live') = 1 and (c #>> '{live,0,last_point,lat}')::numeric = 23.733, 'on the road now ' || (c -> 'live')::text;
  raise notice 'PASS: cost per vehicle and per km from fuel, repairs and trip costs; disputed fuel left out; live view';
end $$;

select '==== ALL TMS T5 CHECKS PASSED ====' as result;
rollback;
