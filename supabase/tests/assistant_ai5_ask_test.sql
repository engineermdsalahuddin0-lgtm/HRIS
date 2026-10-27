-- =============================================================================
-- AI assistant AI5 tests: retrieval and refusals, conversations, limits, preview.
--
-- Vectors are unit vectors e1..e4 (1024 dimensions) so similarities are exact (1 or 0):
--   e1 = leave policy (company policy, everyone)      e2 = disciplinary SOP (confidential, Admin only)
--   e3 = app guide "Leave" page (/leave, everyone)     e4 = app guide "Payroll runs" (needs payroll permissions)
-- Sam is an employee.
--   1. e1 finds the leave policy; nothing hidden.
--   2. e2 finds nothing for Sam and says a hidden resource matched (never its text).
--   3. e4: the payroll guide is hidden for Sam -> "feature" (the role is not permitted).
--   4. e3 on /leave: the guide article with its route; Sam may open /leave (links list), not /payroll.
--   5. Recording an answer makes a conversation, logs the question, lowers questions left; history returns it.
--   6. The daily limit refuses the next question; the Admin preview sees what the Employee role would get.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL AI5 ASSISTANT CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000a5001', 'authenticated', 'authenticated', 'ai5platform@olympus.test', now(), '{"full_name":"AI5 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a5002', 'authenticated', 'authenticated', 'ai5owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000a5001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a5002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Ask', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a5001","role":"authenticated"}', true);
select set_config('t.org', public.approve_org_signup_request(
  (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a5002'))::text, true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a5002","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_des uuid; v_branch uuid; v_office uuid;
begin
  insert into public.departments (name) values ('Ops') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name) values (v_dept, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
    'department_id', v_dept, 'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Sam Staff')),
    'sam@ai5.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.r_emp', (select id from public.roles where system_key = 'employee')::text, true);
  perform public.save_assistant_key('{"slot":"chat","provider":"openai","model":"gpt-4.1-mini","api_key":"sk-openai-abcdefghijklmnop1234"}');
  perform public.record_assistant_key_test('chat', true, 'ok');
end $$;

-- Index by hand (the Edge Function does this in real life).
reset role;
do $$
declare
  v_org uuid := current_setting('t.org')::uuid;
  v_leave uuid; v_sop uuid;
  e text;
begin
  for i in 1..4 loop
    perform set_config('t.e' || i, (select to_jsonb(array_agg((case when j = i then 1 else 0 end)::real order by j)) from generate_series(1, 1024) j)::text, true);
  end loop;
  insert into public.assistant_resources (org_id, name, kind, size_bytes, file_hash, topic_key, status, embedding_model)
  values (v_org, 'Leave Policy 2026.pdf', 'pdf', 1000, repeat('a', 64), 'kb.company_policy', 'ready', 'text-embedding-3-small') returning id into v_leave;
  insert into public.assistant_resources (org_id, name, kind, size_bytes, file_hash, topic_key, status, embedding_model)
  values (v_org, 'Disciplinary SOP.docx', 'docx', 1000, repeat('b', 64), 'kb.confidential', 'ready', 'text-embedding-3-small') returning id into v_sop;
  insert into public.assistant_chunks (org_id, source, resource_id, chunk_index, location, section, passage, embedding, embedding_model) values
    (v_org, 'resource', v_leave, 0, '2', 'Casual leave', 'Every employee gets 10 days of casual leave.', current_setting('t.e1')::extensions.vector, 'text-embedding-3-small'),
    (v_org, 'resource', v_sop, 0, '1', 'Show-cause', 'The employee has 7 days to reply.', current_setting('t.e2')::extensions.vector, 'text-embedding-3-small');
  insert into public.assistant_chunks (org_id, source, guide_key, chunk_index, location, section, passage, embedding, embedding_model) values
    (v_org, 'guide', 'leave', 0, '/leave', 'Leave', 'Apply in My leave and press Submit.', current_setting('t.e3')::extensions.vector, 'text-embedding-3-small'),
    (v_org, 'guide', 'payroll', 0, '/payroll', 'Payroll runs', 'Create and calculate a run.', current_setting('t.e4')::extensions.vector, 'text-embedding-3-small');
end $$;
set local role authenticated;

-- ======================================================= 1-4. retrieval
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb;
begin
  v := public.assistant_prepare('casual leave days', current_setting('t.e1'), '/', null);
  assert v ->> 'hidden' = 'none' and (v -> 'passages' -> 0 ->> 'name') = 'Leave Policy 2026.pdf', '1: the leave policy ' || v::text;
  assert (v -> 'passages' -> 0 ->> 'similarity')::numeric = 1, 'exact match';

  v := public.assistant_prepare('show-cause reply time', current_setting('t.e2'), '/', null);
  assert jsonb_array_length(v -> 'passages') = 0 and v ->> 'hidden' = 'resource', '2: hidden resource ' || v::text;
  assert v::text not like '%7 days to reply%', 'never the hidden text';

  v := public.assistant_prepare('how do I run payroll', current_setting('t.e4'), '/', null);
  assert jsonb_array_length(v -> 'passages') = 0 and v ->> 'hidden' = 'feature', '3: feature not permitted ' || v::text;

  v := public.assistant_prepare('how do I apply', current_setting('t.e3'), '/leave', null);
  assert v -> 'passages' -> 0 ->> 'route' = '/leave' and v -> 'passages' -> 0 ->> 'source' = 'guide', '4: page guide ' || v::text;
  assert exists (select 1 from jsonb_array_elements(v -> 'routes') r where r ->> 'route' = '/leave')
         and not exists (select 1 from jsonb_array_elements(v -> 'routes') r where r ->> 'route' = '/payroll'), 'links only to pages Sam may open';
  assert jsonb_typeof(v -> 'digest') = 'array', 'the digest comes along';
  raise notice 'PASS: retrieval reads only what the role may read; hidden matches refuse without content; page-aware guide';
end $$;

-- ======================================================= 5. conversation and log
do $$
declare
  r jsonb;
  h jsonb;
begin
  r := public.assistant_record_answer(jsonb_build_object('question', 'casual leave days', 'answer', 'You get 10 days [1].', 'kind', 'answer',
        'citations', '[{"n":1,"name":"Leave Policy 2026.pdf"}]', 'route', '/', 'tokens_in', 300, 'tokens_out', 40));
  assert (r ->> 'left')::int = 19, 'one question used ' || r::text;
  perform set_config('t.conv', r ->> 'conversation_id', true);
  perform set_config('t.log', r ->> 'log_id', true);
  h := public.assistant_history();
  assert h ->> 'conversation_id' = current_setting('t.conv') and jsonb_array_length(h -> 'messages') = 2, 'history ' || h::text;
  assert jsonb_array_length(public.assistant_prepare('more', current_setting('t.e1'), '/', current_setting('t.conv')::uuid) -> 'history') = 2,
         'the last turns go with the next question';
  perform public.assistant_feedback(current_setting('t.log')::bigint, false);
  raise notice 'PASS: answers are recorded per person with history and feedback';
end $$;

-- ======================================================= 6. limits and preview
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a5002","role":"authenticated"}', true);
select public.save_assistant_role_matrix(jsonb_build_object('roles', jsonb_build_array(jsonb_build_object('role_id', current_setting('t.r_emp'), 'daily_limit', 1))));
do $$
declare
  v jsonb := public.assistant_preview_as_role(current_setting('t.r_emp')::uuid, 'show-cause', current_setting('t.e2'), null);
begin
  assert v ->> 'hidden' = 'resource', 'the preview shows the Employee view ' || v::text;
  assert (public.assistant_preview_as_role(current_setting('t.r_emp')::uuid, 'again', current_setting('t.e2'), null) ->> 'refusal') is null, 'no limits in preview';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert public.assistant_prepare('again', current_setting('t.e1'), '/', null) ->> 'refusal' like 'You reached today''s limit%', 'daily limit';
  begin
    perform public.assistant_preview_as_role(current_setting('t.r_emp')::uuid, 'again', current_setting('t.e1'), null);
    raise exception 'FAIL: an employee used the preview';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: daily limit; preview for managers only';
end $$;

select '==== ALL AI5 ASSISTANT CHECKS PASSED ====' as result;
rollback;
