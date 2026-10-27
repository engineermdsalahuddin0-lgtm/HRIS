-- =============================================================================
-- Communication C3 tests: password requests.
--
-- Alpha: Hana (HR, users.reset_password), Sam and Olu (employees). Beta: its owner.
--   1. A visitor asks for Sam (email) and for an unknown ID: the same answer both times; only Sam's request
--      is recorded; a second ask while pending does not duplicate it; the 4th ask for one ID in a day is refused.
--   2. Mobile numbers work too (01… form); invalid input is refused.
--   3. HR lists the pending requests; an employee cannot; Beta sees nothing of Alpha.
--   4. Reset: the request is resolved and Sam must change the password at next login; a handled request
--      cannot be handled again; dismiss needs a reason.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL COMM C3 PASSWORD REQUEST CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000c3001', 'authenticated', 'authenticated', 'c3platform@olympus.test', now(), '{"full_name":"C3 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c3002', 'authenticated', 'authenticated', 'c3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c3003', 'authenticated', 'authenticated', 'c3owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000c3001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c3002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Keys', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c3003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Keys', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c3001","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c3002'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c3003'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c3002","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_des uuid; v_branch uuid; v_office uuid; v_common jsonb;
begin
  insert into public.departments (name) values ('Ops') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name) values (v_dept, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'department_id', v_dept,
                                 'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.e_hana', public.create_employee(v_common || '{"full_name":"Hana HR"}')::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || '{"full_name":"Sam Staff"}')::text, true);
  perform set_config('t.e_olu', public.create_employee(v_common || '{"full_name":"Olu Ops"}')::text, true);
  perform set_config('t.u_hana', public.grant_portal_access(current_setting('t.e_hana')::uuid, 'hana@alpha3.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@alpha3.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_olu', public.grant_portal_access(current_setting('t.e_olu')::uuid, null, '01712345678', 'Passw0rd1', null)::text, true);
end $$;

-- ======================================================= 1. the login page
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v_known jsonb := public.request_password_help('Sam@Alpha3.test');
  v_unknown jsonb := public.request_password_help('nobody@alpha3.test');
begin
  assert v_known = v_unknown, 'the same answer for known and unknown IDs';
  perform public.request_password_help('sam@alpha3.test');
  perform public.request_password_help('sam@alpha3.test');
  begin
    perform public.request_password_help('sam@alpha3.test');
    raise exception 'FAIL: a 4th request for one ID in a day';
  exception when raise_exception then
    if sqlerrm not like 'Too many requests%' then raise; end if;
  end;
  -- ======================================================= 2. mobile numbers
  perform public.request_password_help('01712345678');
  begin
    perform public.request_password_help('12345');
    raise exception 'FAIL: an invalid ID accepted';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: one answer for every ID; per-ID limit; email and mobile both work';
end $$;

-- ======================================================= 3. HR list
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.list_password_requests();
  sam jsonb := (select x from jsonb_array_elements(v -> 'requests') x where x ->> 'full_name' = 'Sam Staff');
begin
  assert (v -> 'kpis' ->> 'pending')::int = 2, 'Sam and Olu pending once each ' || v::text;
  assert sam ->> 'login_hint' = 's***@alpha3.test', 'masked login ' || (sam ->> 'login_hint');
  assert (select x ->> 'login_hint' from jsonb_array_elements(v -> 'requests') x where x ->> 'full_name' = 'Olu Ops') = '+8801******678', 'masked mobile';
  perform set_config('t.r_sam', sam ->> 'id', true);
  perform set_config('t.r_olu', (select x ->> 'id' from jsonb_array_elements(v -> 'requests') x where x ->> 'full_name' = 'Olu Ops'), true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.list_password_requests();
    raise exception 'FAIL: an employee listed password requests';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c3003","role":"authenticated"}', true);
do $$
begin
  assert (public.list_password_requests() -> 'kpis' ->> 'pending')::int = 0, 'Beta sees no Alpha request';
  begin
    perform public.dismiss_password_request(current_setting('t.r_olu')::uuid, 'not ours');
    raise exception 'FAIL: Beta handled an Alpha request';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: HR sees the pending requests with masked IDs; employees and other companies do not';
end $$;

-- ======================================================= 4. reset and dismiss
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  perform public.resolve_password_request(current_setting('t.r_sam')::uuid, 'NewPassw0rd9');
  begin
    perform public.resolve_password_request(current_setting('t.r_sam')::uuid, 'NewPassw0rd9');
    raise exception 'FAIL: handled twice';
  exception when check_violation then null;
  end;
  begin
    perform public.dismiss_password_request(current_setting('t.r_olu')::uuid, '');
    raise exception 'FAIL: dismissed without a reason';
  exception when invalid_parameter_value then null;
  end;
  perform public.dismiss_password_request(current_setting('t.r_olu')::uuid, 'Olu remembered it');
  assert (public.list_password_requests() -> 'kpis' ->> 'pending')::int = 0, 'nothing pending';
  assert (public.list_password_requests() -> 'kpis' ->> 'resolved')::int = 1, 'one resolved';
end $$;
reset role;
do $$
begin
  assert (select must_change_password from public.user_profiles where id = current_setting('t.u_sam')::uuid), 'Sam must change the password';
  raise notice 'PASS: reset forces a password change; handled requests stay handled; dismiss needs a reason';
end $$;

select '==== ALL COMM C3 PASSWORD REQUEST CHECKS PASSED ====' as result;
rollback;
