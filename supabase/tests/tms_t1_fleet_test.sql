-- =============================================================================
-- TMS T1 tests: vehicles, drivers, papers in the DMS.
--
-- Alpha: Owner (Admin), Hana (HR Manager: tms.manage), Mona (Manager: tms.approve), Sam (employee, a driver with a
-- login), Rahim (outside driver). Beta: another company.
--   1. Permissions: the desk manages; a manager reads; an employee cannot open the fleet.
--   2. Vehicles: registration number normalised and unique; the odometer never goes back.
--   3. Drivers: employee driver gets his login linked; outside drivers need name + phone; NID masked for non-desk.
--   4. Safety: a light licence cannot drive a truck; a driver is the default driver of one vehicle only.
--   5. Papers: a fitness certificate in the DMS linked to the vehicle gives its next expiry; the overview lists
--      papers and licences expiring (expired included).
--   6. The driver view finds Sam's record; Beta sees nothing of Alpha.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL TMS T1 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000e1001', 'authenticated', 'authenticated', 't1platform@olympus.test', now(), '{"full_name":"T1 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e1002', 'authenticated', 'authenticated', 't1owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e1003', 'authenticated', 'authenticated', 't1owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000e1001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Transport', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Transport', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e1002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e1003'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1002","role":"authenticated"}', true);
do $$
declare
  v_adm uuid; v_sales uuid; v_des uuid; v_branch uuid; v_office uuid; v_common jsonb;
begin
  insert into public.departments (name, code) values ('Admin', 'ADM') returning id into v_adm;
  insert into public.departments (name, code) values ('Sales', 'SAL') returning id into v_sales;
  insert into public.designations (department_id, grade_id, name) values (v_adm, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.adm', v_adm::text, true);
  perform set_config('t.branch', v_branch::text, true);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office,
                                 'department_id', v_adm, 'designation_id', v_des);
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Hana HR"}'),
      'hana@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Mona Manager"}'),
      'mona@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || '{"full_name":"Sam Driver","phone":"+8801711000001"}')::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
end $$;

-- ======================================================= 1. permissions
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.get_tms_fleet();
    raise exception 'FAIL: an employee opened the fleet';
  exception when insufficient_privilege then null;
  end;
  assert public.my_tms_driver() is null, 'not a driver yet';
end $$;

-- ======================================================= 2. vehicles
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  f jsonb := public.get_tms_fleet();
  v_car uuid;
begin
  assert (f -> 'can' ->> 'manage')::boolean, 'HR runs the transport desk';
  v_car := public.save_tms_vehicle(null, jsonb_build_object('reg_no', '  dhaka metro-ga   12-3456 ', 'vtype', 'car', 'make', 'Toyota',
            'model', 'Axio', 'fuel', 'octane', 'fuel2', 'cng', 'tank_l', 40, 'cng_m3', 12, 'seats', 4, 'odometer_km', 52000,
            'branch_id', current_setting('t.branch'), 'department_id', current_setting('t.adm')));
  perform set_config('t.v_car', v_car::text, true);
  assert (public.get_tms_vehicle(v_car) ->> 'reg_no') = 'DHAKA METRO-GA 12-3456', 'registration normalised';
  begin
    perform public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-GA 12-3456","vtype":"car","fuel":"octane"}');
    raise exception 'FAIL: duplicate registration';
  exception when unique_violation then null;
  end;
  begin
    perform public.save_tms_vehicle(v_car, '{"reg_no":"Dhaka Metro-GA 12-3456","odometer_km":51000}');
    raise exception 'FAIL: odometer went back';
  exception when check_violation then null;
  end;
  perform set_config('t.v_truck', public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-TA 11-2222","vtype":"truck","fuel":"diesel","tank_l":200,"payload_kg":7000}')::text, true);
  raise notice 'PASS: vehicles are registered once, normalised, and the odometer never goes back';
end $$;

-- ======================================================= 3. drivers
do $$
declare
  v_sam uuid; v_rahim uuid;
begin
  v_sam := public.save_tms_driver(null, jsonb_build_object('employee_id', current_setting('t.e_sam'), 'licence_no', 'DK0123456L00001',
            'licence_class', 'light', 'licence_expiry', (current_date + 400)::text));
  perform set_config('t.d_sam', v_sam::text, true);
  begin
    perform public.save_tms_driver(null, '{"licence_no":"X1234","licence_class":"heavy","licence_expiry":"2030-01-01"}');
    raise exception 'FAIL: outside driver without name and phone';
  exception when invalid_parameter_value then null;
  end;
  v_rahim := public.save_tms_driver(null, jsonb_build_object('name', 'Rahim Uddin', 'phone', '+8801811000002', 'nid', '1990123456789',
              'licence_no', 'DK9876543H00002', 'licence_class', 'heavy', 'licence_expiry', (current_date - 3)::text));
  perform set_config('t.d_rahim', v_rahim::text, true);
  begin
    perform public.save_tms_driver(null, '{"name":"Copy","phone":"+8801811000009","licence_no":"dk9876543h00002","licence_class":"light","licence_expiry":"2030-01-01"}');
    raise exception 'FAIL: same licence number twice';
  exception when unique_violation then null;
  end;
  assert (select (x ->> 'has_login')::boolean from jsonb_array_elements(public.get_tms_fleet() -> 'drivers') x where x ->> 'id' = v_sam::text),
         'the employee driver''s login is linked';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  assert (select x ->> 'nid' from jsonb_array_elements(public.get_tms_fleet() -> 'drivers') x where x ->> 'id' = current_setting('t.d_rahim')) = '••••6789',
         'NID masked outside the desk';
  begin
    perform public.save_tms_vehicle(null, '{"reg_no":"X 1","vtype":"car","fuel":"octane"}');
    raise exception 'FAIL: a manager registered a vehicle';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: employee and outside drivers; licences unique; NID masked; managers only read';
end $$;

-- ======================================================= 4. licence class and one vehicle per driver
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  begin
    perform public.save_tms_vehicle(current_setting('t.v_truck')::uuid, jsonb_build_object('reg_no', 'Dhaka Metro-TA 11-2222', 'driver_id', current_setting('t.d_sam')));
    raise exception 'FAIL: a light licence on a truck';
  exception when check_violation then
    assert sqlerrm like '%needs heavy%', sqlerrm;
  end;
  perform public.save_tms_vehicle(current_setting('t.v_car')::uuid, jsonb_build_object('reg_no', 'Dhaka Metro-GA 12-3456', 'driver_id', current_setting('t.d_sam')));
  perform public.save_tms_vehicle(current_setting('t.v_truck')::uuid, jsonb_build_object('reg_no', 'Dhaka Metro-TA 11-2222', 'driver_id', current_setting('t.d_rahim')));
  begin
    perform public.save_tms_vehicle(null, jsonb_build_object('reg_no', 'Dhaka Metro-GA 99-0001', 'vtype', 'car', 'fuel', 'octane', 'driver_id', current_setting('t.d_sam')));
    raise exception 'FAIL: one driver, two default vehicles';
  exception when unique_violation then null;
  end;
  raise notice 'PASS: the licence class must cover the vehicle; one default vehicle per driver';
end $$;

-- ======================================================= 5. papers in the DMS
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1002","role":"authenticated"}', true);
do $$
declare
  s jsonb := public.get_dms_setup();
  v jsonb;
  o jsonb;
begin
  assert (select count(*) from jsonb_array_elements(s -> 'folders') f where f ->> 'catalog_code' = 'TRP') = 1, 'Transport & Vehicles folder';
  v := public.dms_register_upload(jsonb_build_object('title', 'Fitness DM-GA 12-3456',
      'folder_id', (select f ->> 'id' from jsonb_array_elements(s -> 'folders') f where f ->> 'catalog_code' = 'TRP'),
      'doc_type_id', (select t ->> 'id' from jsonb_array_elements(s -> 'types') t where t ->> 'code' = 'FIT'),
      'department_id', current_setting('t.adm'), 'expiry_date', (current_date + 30)::text,
      'fields', '{"licence_no":"FIT-778","authority":"BRTA"}'::jsonb,
      'file', jsonb_build_object('name', 'fitness.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('fit1'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform public.tms_link_document((v ->> 'document_id')::uuid, current_setting('t.v_car')::uuid, null);
  v := public.get_tms_vehicle(current_setting('t.v_car')::uuid);
  assert (v ->> 'next_expiry')::date = current_date + 30 and jsonb_array_length(v -> 'papers') = 1, 'paper linked ' || v::text;
  assert v #>> '{papers,0,doc_code}' = 'ADM-FIT-0001', 'named by the DMS';
  o := public.get_tms_overview();
  assert (o #>> '{vehicles,total}')::int = 2 and (o #>> '{drivers,licence_expired}')::int = 1, 'counts ' || o::text;
  assert (select count(*) from jsonb_array_elements(o -> 'expiring') x where x ->> 'kind' = 'paper' and x ->> 'vehicle' = 'DHAKA METRO-GA 12-3456') = 1
     and (select count(*) from jsonb_array_elements(o -> 'expiring') x where x ->> 'kind' = 'licence' and x ->> 'expiry_status' = 'expired') = 1,
         'papers and licences expiring ' || (o -> 'expiring')::text;
  raise notice 'PASS: vehicle papers live in the DMS, linked to the vehicle, with expiry in the overview';
end $$;

-- ======================================================= 6. driver view, isolation
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert public.my_tms_driver() #>> '{vehicle,reg_no}' = 'DHAKA METRO-GA 12-3456', 'Sam sees his vehicle';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e1003","role":"authenticated"}', true);
do $$
begin
  assert jsonb_array_length(public.get_tms_fleet() -> 'vehicles') = 0, 'Beta sees no Alpha vehicle';
  begin
    perform public.get_tms_vehicle(current_setting('t.v_car')::uuid);
    raise exception 'FAIL: Beta opened an Alpha vehicle';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: drivers find their record; other companies see nothing';
end $$;

select '==== ALL TMS T1 CHECKS PASSED ====' as result;
rollback;
