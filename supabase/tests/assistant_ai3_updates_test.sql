-- =============================================================================
-- AI assistant AI3 tests: widget config and the Updates digest.
--
-- Alpha: Hana (HR Manager), Mona (Manager), Sam (Employee) with a pending leave request that Mona approves.
--   1. Digest by role: Sam never gets team / headcount / payroll items; Mona gets team today and "1 request waits";
--      HR gets headcount; no item carries an amount or another person's name.
--   2. A role switched off sees the assistant disabled; the Admin column cannot be switched off.
--   3. Config: Ask is blocked until keys are tested and something is indexed, then open (trial plan);
--      questions left = the role's daily limit.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL AI3 ASSISTANT CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000a3001', 'authenticated', 'authenticated', 'ai3platform@olympus.test', now(), '{"full_name":"AI3 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a3002', 'authenticated', 'authenticated', 'ai3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000a3001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Digest', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3001","role":"authenticated"}', true);
select set_config('t.org', public.approve_org_signup_request(
  (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a3002'))::text, true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3002","role":"authenticated"}', true);
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
  perform set_config('t.e_mona', public.create_employee(v_common || '{"full_name":"Mona Manager"}')::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || '{"full_name":"Sam Staff"}')::text, true);
  perform public.set_reporting_line(current_setting('t.e_sam')::uuid, 'reporting_manager', current_setting('t.e_mona')::uuid, '2026-01-01');
  perform set_config('t.u_hana', public.grant_portal_access(current_setting('t.e_hana')::uuid, 'hana@ai3.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(current_setting('t.e_mona')::uuid, 'mona@ai3.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@ai3.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.r_emp', (select id from public.roles where system_key = 'employee')::text, true);
  perform set_config('t.r_admin', (select id from public.roles where system_key = 'admin')::text, true);
end $$;

-- A pending leave request of Sam that Mona approves (written directly; the leave rules are tested in Part 2).
reset role;
insert into public.leave_requests (org_id, employee_id, leave_type_id, from_date, to_date, days, reason, status, approver_employee_id)
select current_setting('t.org')::uuid, current_setting('t.e_sam')::uuid, lt.id, current_date + 7, current_date + 7, 1, 'Family event', 'pending',
       current_setting('t.e_mona')::uuid
from public.leave_types lt where lt.org_id = current_setting('t.org')::uuid order by lt.code limit 1;
set local role authenticated;

-- ======================================================= 1. digest by role
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb := public.assistant_updates();
begin
  assert not exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' in ('up.team_today', 'up.headcount', 'up.payroll_status', 'up.hiring', 'up.approvals')),
         'an employee gets only personal items ' || v::text;
  assert exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' = 'up.my_leave' and x ->> 'detail' like '1 request%'), 'my pending leave ' || v::text;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v jsonb := public.assistant_updates();
begin
  assert exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' = 'up.team_today'), 'manager sees the team today ' || v::text;
  assert exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' = 'up.approvals' and x ->> 'title' = '1 request wait for you'), 'one approval ' || v::text;
  assert not exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' = 'up.headcount'), 'headcount is not ticked for managers';
  assert v::text not like '%Sam Staff%', 'no names of other people';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.assistant_updates();
begin
  assert exists (select 1 from jsonb_array_elements(v) x where x ->> 'topic' = 'up.headcount' and x ->> 'title' = '4 active employees'), 'HR headcount ' || v::text;
  assert v::text !~ '(Tk|৳|BDT)', 'no amounts';
  raise notice 'PASS: the digest follows role ticks and permissions; counts and statuses only';
end $$;

-- ======================================================= 2. role switched off
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3002","role":"authenticated"}', true);
select public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(
  jsonb_build_object('role_id', current_setting('t.r_emp'), 'enabled', false),
  jsonb_build_object('role_id', current_setting('t.r_admin'), 'enabled', false))));
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert not (public.assistant_my_config() ->> 'enabled')::boolean, 'the employee role is off';
  assert jsonb_array_length(public.assistant_updates()) = 0, 'no updates when off';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3002","role":"authenticated"}', true);
do $$
begin
  assert (public.assistant_my_config() ->> 'enabled')::boolean, 'the Admin is never switched off';
  perform public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(jsonb_build_object('role_id', current_setting('t.r_emp'), 'enabled', true))));
  raise notice 'PASS: switching a role off hides the assistant for it';
end $$;

-- ======================================================= 3. config
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb := public.assistant_my_config();
begin
  assert not (v ->> 'can_ask')::boolean and v ->> 'ask_blocked_reason' like '%AI keys%', 'blocked without keys ' || v::text;
  assert (v ->> 'left')::int = 20, 'twenty questions a day for employees';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a3002","role":"authenticated"}', true);
select public.save_assistant_key('{"slot":"chat","provider":"openai","model":"gpt-4.1-mini","api_key":"sk-openai-abcdefghijklmnop1234"}');
select public.record_assistant_key_test('chat', true, 'ok');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert public.assistant_my_config() ->> 'ask_blocked_reason' like 'Nothing is indexed%', 'keys ok, nothing indexed yet';
end $$;
reset role;
insert into public.assistant_guide_articles (key, route, title, body) values ('test.leave', '/leave', 'Leave', 'Apply under Leave');
insert into public.assistant_chunks (org_id, source, guide_key, chunk_index, location, passage, embedding_model)
values (current_setting('t.org')::uuid, 'guide', 'test.leave', 0, '/leave', 'Apply under Leave', 'text-embedding-3-small');
set local role authenticated;
do $$
begin
  assert (public.assistant_my_config() ->> 'can_ask')::boolean, 'Ask is open once keys work and something is indexed';
  raise notice 'PASS: Ask opens only with tested keys, an allowed plan and an index; daily limit shown';
end $$;

select '==== ALL AI3 ASSISTANT CHECKS PASSED ====' as result;
rollback;
