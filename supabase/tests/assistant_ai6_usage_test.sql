-- =============================================================================
-- AI assistant AI6 tests: usage figures and the purge.
--
-- Alpha: the Admin and HR (with the setup handed over). Four logged questions: two answered (one marked not
-- helpful), one "don't know", one 100 days old.
--   1. Usage is Admin only (HR may manage the setup but not see the log).
--   2. Figures: total 3 in 30 days, the unanswered and not-helpful lists, tokens this month.
--   3. Purge: the 100-day-old question text is cleared (the row stays), its conversation is deleted.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL AI6 ASSISTANT CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000a6001', 'authenticated', 'authenticated', 'ai6platform@olympus.test', now(), '{"full_name":"AI6 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000a6002', 'authenticated', 'authenticated', 'ai6owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000a6001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a6002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Usage', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a6001","role":"authenticated"}', true);
select set_config('t.org', public.approve_org_signup_request(
  (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000a6002'))::text, true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a6002","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_des uuid; v_branch uuid; v_office uuid;
begin
  insert into public.departments (name) values ('Ops') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name) values (v_dept, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
    'department_id', v_dept, 'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Hana HR')),
    'hana@ai6.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform public.set_assistant_delegation(true);
  perform public.get_assistant_setup();
end $$;

-- Four questions, one of them 100 days old with its conversation.
select set_config('t.r1', (public.assistant_record_answer('{"question":"casual leave days","answer":"10 [1]","kind":"answer","tokens_in":300,"tokens_out":40}') ->> 'log_id'), true);
select public.assistant_record_answer('{"question":"how to run payroll","answer":"steps","kind":"answer","tokens_in":200,"tokens_out":60}');
select public.assistant_record_answer('{"question":"gym membership?","answer":"I don''t know","kind":"dont_know"}');
select set_config('t.old_conv', (public.assistant_record_answer('{"question":"old question","answer":"old","kind":"answer"}') ->> 'conversation_id'), true);
select public.assistant_feedback(current_setting('t.r1')::bigint, false);
reset role;
update public.assistant_query_log set asked_at = now() - interval '100 days' where question = 'old question';
update public.assistant_conversations set last_at = now() - interval '100 days' where id = current_setting('t.old_conv')::uuid;
set local role authenticated;

-- ======================================================= 1. Admin only
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  perform public.get_assistant_setup();
  begin
    perform public.get_assistant_usage(30);
    raise exception 'FAIL: HR saw the question log';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: usage is Admin only';
end $$;

-- ======================================================= 2. figures
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000a6002","role":"authenticated"}', true);
do $$
declare
  v jsonb := public.get_assistant_usage(30);
begin
  assert (v ->> 'total')::int = 3, 'three in 30 days ' || v::text;
  assert (v -> 'unanswered' -> 0 ->> 'question') = 'gym membership?', 'unanswered list';
  assert (v -> 'not_helpful' -> 0 ->> 'question') = 'casual leave days', 'not helpful list';
  assert (v ->> 'tokens_month')::int >= 600, 'tokens this month';
  assert (v -> 'by_kind' ->> 'answer')::int = 2, 'by kind';
  raise notice 'PASS: usage figures, gaps and not-helpful answers';
end $$;

-- ======================================================= 3. purge
do $$
declare
  v jsonb := public.run_assistant_purge();
begin
  assert (v ->> 'questions_cleared')::int = 1 and (v ->> 'conversations_deleted')::int >= 1, 'purged ' || v::text;
end $$;
reset role;
do $$
begin
  assert exists (select 1 from public.assistant_query_log where org_id = current_setting('t.org')::uuid and question is null), 'the row stays, the text goes';
  assert not exists (select 1 from public.assistant_conversations where id = current_setting('t.old_conv')::uuid), 'old conversation deleted';
  raise notice 'PASS: the purge clears old question text and deletes old conversations';
end $$;

select '==== ALL AI6 ASSISTANT CHECKS PASSED ====' as result;
rollback;
