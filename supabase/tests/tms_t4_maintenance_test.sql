-- =============================================================================
-- TMS T4 tests: service plans, job cards, parts and tyre stock.
--
-- Alpha: Owner (Admin), Hana (HR Manager: tms.manage + tms.inventory), Mona (Manager: tms.approve only).
-- Car at 6,200 km; engine oil every 5,000 km / 6 months, last done at 1,000 km.
--   1. The plan is overdue; a job card puts the car in maintenance; trips cannot take it.
--   2. Stock: receive 10 @ ৳500 and 10 @ ৳700 → average ৳600; issue 4 to the job (৳2,400); never below zero;
--      adjustments need a reason; history cannot be edited.
--   3. Closing the job: total = labour + outside parts + stock parts; the plan restarts from this km; the car is active.
--   4. A manager with only tms.approve cannot touch stock or job cards.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL TMS T4 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000e4001', 'authenticated', 'authenticated', 't4platform@olympus.test', now(), '{"full_name":"T4 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000e4002', 'authenticated', 'authenticated', 't4owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000e4001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e4002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Garage', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e4001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000e4002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e4002","role":"authenticated"}', true);
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
  perform set_config('t.u_mona', public.grant_portal_access(public.create_employee(v_base || '{"full_name":"Mona Manager"}'),
      'mona@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'manager'))::text, true);
end $$;

-- ======================================================= 1. plan and job card
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  m jsonb;
begin
  perform set_config('t.v_car', public.save_tms_vehicle(null, '{"reg_no":"Dhaka Metro-GA 44-0001","vtype":"car","fuel":"octane","odometer_km":6200}')::text, true);
  perform set_config('t.plan', public.save_tms_service_plan(null, jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'name', 'Engine oil',
    'every_km', 5000, 'every_months', 6, 'last_km', 1000, 'last_date', (current_date - 30)::text))::text, true);
  m := public.get_tms_maintenance();
  assert (select x ->> 'status' from jsonb_array_elements(m -> 'plans') x where x ->> 'id' = current_setting('t.plan')) = 'overdue', 'overdue at 6,200 km';
  perform set_config('t.job', public.open_tms_job_card(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'plan_id', current_setting('t.plan'),
    'kind', 'service', 'workshop', 'Navana Service, Tejgaon', 'description', 'Engine oil and filter'))::text, true);
  assert (public.get_tms_vehicle(current_setting('t.v_car')::uuid) ->> 'status') = 'in_maintenance', 'the car is in maintenance';
  raise notice 'PASS: an overdue service is shown; a job card takes the car off the road';
end $$;

-- ======================================================= 2. stock
do $$
declare
  r jsonb;
begin
  perform set_config('t.part', public.save_tms_part(null, '{"code":"OIL-5W30","name":"Engine oil 5W-30","category":"lubricant","unit":"litre","min_stock":5}')::text, true);
  perform public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'receive', 'qty', 10, 'unit_cost', 500, 'supplier', 'Meghna'));
  r := public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'receive', 'qty', 10, 'unit_cost', 700));
  assert (r ->> 'avg_cost')::numeric = 600 and (r ->> 'on_hand')::numeric = 20, 'weighted average ' || r::text;
  r := public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'issue', 'qty', 4, 'job_card_id', current_setting('t.job')));
  assert (r ->> 'on_hand')::numeric = 16, 'issued 4';
  begin
    perform public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'issue', 'qty', 20, 'job_card_id', current_setting('t.job')));
    raise exception 'FAIL: issued more than in stock';
  exception when check_violation then null;
  end;
  begin
    perform public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'adjust', 'qty', -2));
    raise exception 'FAIL: adjusted without a reason';
  exception when invalid_parameter_value then null;
  end;
  r := public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'adjust', 'qty', -2, 'note', 'Spilled'));
  assert (r ->> 'on_hand')::numeric = 14, 'adjusted';
end $$;
reset role;
do $$
begin
  begin
    update public.tms_stock_moves set qty = 1 where part_id = current_setting('t.part')::uuid;
    raise exception 'FAIL: stock history edited';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: average cost, issue to the job, never below zero, adjustments with a reason, frozen history';
end $$;
set local role authenticated;

-- ======================================================= 3. closing the job
do $$
declare
  j jsonb;
  m jsonb;
begin
  j := public.close_tms_job_card(current_setting('t.job')::uuid, '{"labour_cost":1000,"outside_parts_cost":300,"odometer_km":6210}');
  assert (j ->> 'stock_parts_cost')::numeric = 2400 and (j ->> 'total_cost')::numeric = 3700, 'job total ' || j::text;
  m := public.get_tms_maintenance();
  assert (select (x ->> 'last_km')::numeric = 6210 and x ->> 'status' = 'ok' from jsonb_array_elements(m -> 'plans') x where x ->> 'id' = current_setting('t.plan')),
         'the plan restarts from this service';
  assert (public.get_tms_vehicle(current_setting('t.v_car')::uuid) ->> 'status') = 'active', 'the car is back on the road';
  raise notice 'PASS: closing the job adds up the cost, restarts the plan and returns the car';
end $$;

-- ======================================================= 4. permissions
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  begin
    perform public.tms_stock_move(jsonb_build_object('part_id', current_setting('t.part'), 'kind', 'receive', 'qty', 1, 'unit_cost', 1));
    raise exception 'FAIL: an approver received stock';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.open_tms_job_card(jsonb_build_object('vehicle_id', current_setting('t.v_car'), 'kind', 'repair', 'description', 'Brake check'));
    raise exception 'FAIL: an approver opened a job card';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: stock and job cards are for the store and the transport desk';
end $$;

select '==== ALL TMS T4 CHECKS PASSED ====' as result;
rollback;
