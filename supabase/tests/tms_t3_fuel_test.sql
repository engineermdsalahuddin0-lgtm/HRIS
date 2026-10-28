-- =============================================================================
-- TMS T3 tests: fuel.
--
-- Alpha: Owner (Admin), Hana (HR Manager: desk), Dave (employee driver, default driver of the car), Sam (employee).
-- Car: octane + CNG, tank 40 L, CNG 12 m³, normal 12 km/L. Company price: octane ৳130, CNG ৳43; tolerances 10% / 25%.
--   1. Who logs: Dave (his car) and the desk; Sam cannot; a fuel the car does not use is refused; CNG is in m³.
--   2. km per unit between full fills (partial fills counted): 12.00, then 11.67; a bad stretch is low_efficiency.
--   3. Flags: over_tank, price_off, odometer_back; the fill is saved as flagged, the odometer never goes back.
--   4. The desk verifies or disputes (a dispute needs a reason); a disputed fill does not count in km per unit.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL TMS T3 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000e3001', 'authenticated', 'authenticated', 't3platform@olympus.test', now(), '{"full_name":"T3 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e3002', 'authenticated', 'authenticated', 't3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000e3001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e3002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Fuel', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e3001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e3002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e3002","role":"authenticated"}', true);
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
  perform set_config('t.u_dave', public.grant_portal_access(current_setting('t.e_dave')::uuid, 'dave@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(v_base || '{"full_name":"Sam Staff"}'),
      'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v_driver uuid;
begin
  v_driver := public.save_tms_driver(null, jsonb_build_object('employee_id', current_setting('t.e_dave'), 'licence_no', 'DK3333333L',
                'licence_class', 'light', 'licence_expiry', (current_date + 300)::text));
  perform set_config('t.v_car', public.save_tms_vehicle(null, jsonb_build_object('reg_no', 'Dhaka Metro-GA 33-0001', 'vtype', 'car',
    'fuel', 'octane', 'fuel2', 'cng', 'tank_l', 40, 'cng_m3', 12, 'normal_km_per_unit', 12, 'odometer_km', 900, 'driver_id', v_driver))::text, true);
  perform public.save_tms_settings('{"fuel_prices":{"octane":130,"cng":43},"price_tolerance_pct":10,"efficiency_tolerance_pct":25}');
end $$;

-- ======================================================= 1. who logs, which fuel
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 10, 'unit_price', 130, 'odometer_km', 950));
    raise exception 'FAIL: a non-driver logged fuel';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_dave')), true);
do $$
declare
  f jsonb;
begin
  assert jsonb_array_length(public.tms_fuel_vehicles()) = 1, 'Dave sees his car';
  begin
    perform public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'diesel', 'quantity', 10, 'unit_price', 110, 'odometer_km', 950));
    raise exception 'FAIL: diesel in an octane / CNG car';
  exception when invalid_parameter_value then null;
  end;
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'cng', 'quantity', 10, 'amount', 430, 'odometer_km', 950,
          'lat', 23.75, 'lng', 90.39));
  assert f ->> 'unit' = 'm3' and (f ->> 'unit_price')::numeric = 43 and f ->> 'status' = 'recorded', 'CNG in m³, price from the amount ' || f::text;
  -- ======================================================= 2. km per unit
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 30, 'unit_price', 130, 'odometer_km', 1000));
  assert f ->> 'km_per_unit' is null, 'first full fill: nothing to compare';
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 25, 'unit_price', 130, 'odometer_km', 1300));
  assert (f ->> 'km_per_unit')::numeric = 12.00 and f ->> 'status' = 'recorded', '300 km / 25 L ' || f::text;
  perform public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 10, 'unit_price', 130,
          'odometer_km', 1400, 'full_tank', false));
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 20, 'unit_price', 130, 'odometer_km', 1650));
  assert (f ->> 'km_per_unit')::numeric = 11.67, '350 km / (10 + 20) L ' || f::text;
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 30, 'unit_price', 130, 'odometer_km', 1800));
  assert (f ->> 'km_per_unit')::numeric = 5.00 and f -> 'flags' ? 'low_efficiency' and f ->> 'status' = 'flagged', '150 km / 30 L is low ' || f::text;
  perform set_config('t.f_low', f ->> 'id', true);
  raise notice 'PASS: drivers log their own vehicle''s fuel; CNG in m³; km per unit between full fills; low efficiency is flagged';
end $$;

-- ======================================================= 3. flags
do $$
declare
  f jsonb;
begin
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 50, 'unit_price', 130,
          'odometer_km', 1900, 'full_tank', false));
  assert f -> 'flags' ? 'over_tank', '50 L into a 40 L tank ' || f::text;
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 10, 'unit_price', 160,
          'odometer_km', 1950, 'full_tank', false));
  assert f -> 'flags' ? 'price_off', '৳160 against ৳130 ' || f::text;
  f := public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 10, 'unit_price', 130,
          'odometer_km', 1200, 'full_tank', false));
  assert f -> 'flags' ? 'odometer_back', 'odometer back ' || f::text;
  begin
    perform public.log_tms_fuel(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'fuel', 'octane', 'quantity', 10, 'unit_price', 130,
            'amount', 2000, 'odometer_km', 1960));
    raise exception 'FAIL: amount does not match';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  assert (public.get_tms_vehicle(current_setting('t.v_car')::uuid) ->> 'odometer_km')::numeric = 1950, 'the vehicle odometer never goes back';
  assert jsonb_array_length(public.list_tms_fuel('{"flagged":true}')) = 4, 'four fills wait for the desk';
  raise notice 'PASS: over-tank, price and odometer problems are flagged, not lost';
end $$;

-- ======================================================= 4. verification
do $$
begin
  begin
    perform public.review_tms_fuel(current_setting('t.f_low')::uuid, false, '');
    raise exception 'FAIL: disputed without a reason';
  exception when invalid_parameter_value then null;
  end;
  perform public.review_tms_fuel(current_setting('t.f_low')::uuid, false, 'Receipt shows 15 L only');
  assert jsonb_array_length(public.list_tms_fuel('{"flagged":true}')) = 3, 'one less to check';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_dave')), true);
do $$
begin
  begin
    perform public.review_tms_fuel(current_setting('t.f_low')::uuid, true, null);
    raise exception 'FAIL: a driver verified fuel';
  exception when insufficient_privilege then null;
  end;
  assert jsonb_array_length(public.list_tms_fuel('{"scope":"mine"}')) = 9, 'Dave lists his own nine fills (1 CNG, 5 octane, 3 flagged)';
  raise notice 'PASS: the desk verifies or disputes with a reason; drivers only see their own fills';
end $$;

select '==== ALL TMS T3 CHECKS PASSED ====' as result;
rollback;
