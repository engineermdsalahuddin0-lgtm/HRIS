-- =============================================================================
-- AI assistant AI1 tests: setup, keys, delegation, role matrix.
--
-- Alpha: Hana (HR Manager), Mona (Manager), Sam (Employee). Beta: its owner.
--   1. Defaults: settings, one row per role, matrix as DEFAULT_SETUP (Employee: app guide yes, labour law no).
--   2. HR cannot open the setup until the Admin hands it over; assistant.manage can never go to the Manager role;
--      only an Admin changes the hand-over.
--   3. Keys: format checked per provider; only the last 4 characters come back; chat = Claude needs a separate
--      embedding key, chat = OpenAI embeds with the same key; the service function is closed to users.
--   4. Matrix: an Employee tick on Headcount is stored as off (no employees.view); HR cannot change sensitive ticks
--      for HR Manager, the Admin can; the Admin column is never changed.
--   5. Hyperparameters checked; changed chunking reports the resources to process again. Beta sees only its own setup.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL AI1 ASSISTANT CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000a1001', 'authenticated', 'authenticated', 'ai1platform@olympus.test', now(), '{"full_name":"AI1 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a1002', 'authenticated', 'authenticated', 'ai1owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a1003', 'authenticated', 'authenticated', 'ai1owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000a1001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha AI', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta AI', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a1002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a1003'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1002","role":"authenticated"}', true);
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
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Hana HR"}'), 'hana@ai1.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Mona Manager"}'), 'mona@ai1.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Sam Staff"}'), 'sam@ai1.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.r_hr', (select id from public.roles where system_key = 'hr_manager')::text, true);
  perform set_config('t.r_mgr', (select id from public.roles where system_key = 'manager')::text, true);
  perform set_config('t.r_emp', (select id from public.roles where system_key = 'employee')::text, true);
  perform set_config('t.r_admin', (select id from public.roles where system_key = 'admin')::text, true);
end $$;

-- ======================================================= 1. defaults
do $$
declare
  v jsonb := public.get_assistant_setup();
  emp jsonb := (select r from jsonb_array_elements(v -> 'roles') r where r ->> 'system_key' = 'employee');
  adm jsonb := (select r from jsonb_array_elements(v -> 'roles') r where r ->> 'system_key' = 'admin');
begin
  assert (v -> 'settings' ->> 'enabled')::boolean and v -> 'settings' ->> 'name' = 'Olympus Assistant', 'settings seeded';
  assert jsonb_array_length(v -> 'roles') = 4, 'four roles';
  assert (emp -> 'ticks' ->> 'kb.app_guide')::boolean and not (emp -> 'ticks' ->> 'kb.labour_law')::boolean, 'employee defaults';
  assert (emp ->> 'daily_limit')::int = 20 and adm ->> 'daily_limit' is null, 'limits 20 / none';
  assert not (emp -> 'usable' ->> 'up.headcount')::boolean, 'employee cannot use headcount';
  assert v -> 'keys' -> 'chat' = 'null'::jsonb and v -> 'keys' -> 'embed_effective' = 'null'::jsonb, 'no keys yet';
  assert jsonb_array_length(v -> 'models' -> 'embed' -> 'voyage') >= 1, 'models listed';
  raise notice 'PASS: defaults per company and per role';
end $$;

-- ======================================================= 2. delegation
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  begin
    perform public.get_assistant_setup();
    raise exception 'FAIL: HR opened the setup before the hand-over';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1002","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.set_role_permissions(current_setting('t.r_mgr')::uuid, array['assistant.manage']);
    raise exception 'FAIL: assistant.manage given to the Manager role';
  exception when insufficient_privilege then null;
  end;
  perform public.set_assistant_delegation(true);
  assert (public.get_assistant_setup() ->> 'hr_can_manage')::boolean, 'handed over';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  assert not (public.get_assistant_setup() ->> 'is_admin')::boolean, 'HR opens the setup now';
  begin
    perform public.set_assistant_delegation(false);
    raise exception 'FAIL: HR changed the hand-over';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: only the Admin hands the setup to HR Manager; never to other roles';
end $$;

-- ======================================================= 3. keys
do $$
declare
  v jsonb;
begin
  begin
    perform public.save_assistant_key('{"slot":"chat","provider":"anthropic","model":"claude-sonnet-5-5","api_key":"sk-wrong-key-format-123456"}');
    raise exception 'FAIL: a wrong Anthropic key format';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.save_assistant_key('{"slot":"chat","provider":"anthropic","model":"gpt-4.1","api_key":"sk-ant-abcdefghijklmnopqrstuvwx"}');
    raise exception 'FAIL: a model of another provider';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_assistant_key('{"slot":"chat","provider":"anthropic","model":"claude-sonnet-5-5","api_key":"sk-ant-abcdefghijklmnopqrstuvwx"}');
  v := public.get_assistant_setup() -> 'keys';
  assert v -> 'chat' ->> 'last4' = 'uvwx' and v -> 'chat' ->> 'status' = 'saved', 'last 4 only ' || v::text;
  assert v::text not like '%abcdefghijkl%', 'the key never comes back';
  assert v -> 'embed_effective' = 'null'::jsonb, 'Claude cannot embed: an embedding key is needed';
  perform public.save_assistant_key('{"slot":"embed","provider":"voyage","model":"voyage-3.5","api_key":"pa-voyage-key-0123456789abcd"}');
  v := public.get_assistant_setup() -> 'keys';
  assert v -> 'embed_effective' ->> 'provider' = 'voyage' and v -> 'embed_effective' ->> 'slot' = 'embed', 'Voyage embeds';
  perform public.remove_assistant_key('embed');
  perform public.save_assistant_key('{"slot":"chat","provider":"openai","model":"gpt-4.1-mini","api_key":"sk-openai-abcdefghijklmnop1234"}');
  v := public.get_assistant_setup() -> 'keys';
  assert v -> 'embed_effective' ->> 'slot' = 'chat' and v -> 'embed_effective' ->> 'model' = 'text-embedding-3-small', 'OpenAI chat key also embeds ' || v::text;
  perform public.record_assistant_key_test('chat', true, 'ok');
  assert (public.get_assistant_setup() -> 'keys' -> 'embed_effective' ->> 'ready')::boolean, 'tested key is ready for embeddings';
  begin
    perform public.service_assistant_keys(current_setting('t.org')::uuid);
    raise exception 'FAIL: a user read the decrypted keys';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: keys are checked, encrypted, shown as last 4; the embedding slot follows the chat provider';
end $$;

-- ======================================================= 4. matrix
do $$
declare
  v jsonb;
begin
  perform public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(
    jsonb_build_object('role_id', current_setting('t.r_emp'), 'daily_limit', 25, 'ticks', jsonb_build_object('up.headcount', true, 'kb.labour_law', true)))));
  v := (select r from jsonb_array_elements(public.get_assistant_setup() -> 'roles') r where r ->> 'system_key' = 'employee');
  assert not (v -> 'ticks' ->> 'up.headcount')::boolean, 'tick without permission stays off';
  assert (v -> 'ticks' ->> 'kb.labour_law')::boolean and (v ->> 'daily_limit')::int = 25, 'normal tick and limit saved';
  begin
    perform public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(
      jsonb_build_object('role_id', current_setting('t.r_hr'), 'ticks', jsonb_build_object('kb.confidential', true)))));
    raise exception 'FAIL: HR widened its own sensitive access';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1002","role":"authenticated"}', true);
do $$
declare
  v jsonb;
begin
  perform public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(
    jsonb_build_object('role_id', current_setting('t.r_hr'), 'ticks', jsonb_build_object('kb.confidential', true)),
    jsonb_build_object('role_id', current_setting('t.r_admin'), 'enabled', false, 'ticks', jsonb_build_object('kb.company_policy', false)))));
  v := public.get_assistant_setup();
  assert ((select r from jsonb_array_elements(v -> 'roles') r where r ->> 'system_key' = 'hr_manager') -> 'ticks' ->> 'kb.confidential')::boolean,
         'the Admin can tick sensitive topics for HR';
  assert ((select r from jsonb_array_elements(v -> 'roles') r where r ->> 'system_key' = 'admin') ->> 'enabled')::boolean, 'the Admin column never changes';
  raise notice 'PASS: matrix ticks follow permissions; sensitive HR ticks are Admin-only';
end $$;

-- ======================================================= 5. hyperparameters, isolation
do $$
declare
  v uuid[];
begin
  begin
    perform public.save_assistant_hyper('{"temperature":1.5,"max_answer_tokens":600,"answer_style":"short","top_k":6,"min_score":0.3,"chunk_size":400,"chunk_overlap":15}');
    raise exception 'FAIL: temperature 1.5 accepted';
  exception when invalid_parameter_value then null;
  end;
  v := public.save_assistant_hyper('{"temperature":0.1,"max_answer_tokens":800,"answer_style":"detailed","top_k":8,"min_score":0.25,"chunk_size":500,"chunk_overlap":10}');
  assert cardinality(v) = 0, 'no resources to process yet';
  assert (public.get_assistant_setup() -> 'settings' -> 'hyper' ->> 'top_k')::int = 8, 'saved';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a1003","role":"authenticated"}', true);
do $$
declare
  v jsonb := public.get_assistant_setup();
begin
  assert v -> 'keys' -> 'chat' = 'null'::jsonb and (v -> 'settings' -> 'hyper' ->> 'top_k')::int = 6, 'Beta has its own untouched setup';
  raise notice 'PASS: hyperparameters validated; companies are separate';
end $$;

select '==== ALL AI1 ASSISTANT CHECKS PASSED ====' as result;
rollback;
