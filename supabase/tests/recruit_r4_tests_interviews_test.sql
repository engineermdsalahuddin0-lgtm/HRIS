-- =============================================================================
-- Onboarding process R4 tests: online test, written marks, interviews.
--
-- Objective paper (20 min, pass 50 %): Q1 job knowledge 1 mark (A), Q2 aptitude 2 marks (B),
-- Q3 language 2 marks (C). Total 5.
--   Rahim answers A, A, C -> 1 + 0 + 2 = 3 / 5 = 60.0 % pass; sections 100 / 0 / 100.
--   Karim answers only Q2 = B, then the time runs out -> 2 / 5 = 40.0 % fail, auto-submitted.
--   Sadia's first link expires unused; a new link works.
-- Written paper (pass 60 %): one question of 10 marks; Rahim gets 7 -> 70.0 % pass.
-- Interview: due 15 days after the last result; the day after tomorrow is made a holiday, so the
-- proposal is a later working day at 10:00; the next applicant with the same panel gets 10:45;
-- clashes are refused; after the due date a reason is needed; cancelling restores the status.
-- Managers schedule for their own department only; tests and marks are HR's.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R4 TEST AND INTERVIEW CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000007a1', 'authenticated', 'authenticated', 'r4platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000007a2', 'authenticated', 'authenticated', 'r4owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000007a3', 'authenticated', 'authenticated', 'r4owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000007a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Tests', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Tests', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000007a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000007a3'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a2","role":"authenticated"}', true);
do $$
declare
  v_accounts uuid;
  v_sales    uuid;
  v_senior   uuid;
  v_officer  uuid;
  v_branch   uuid;
  v_office   uuid;
  v_common   jsonb;
  v_emp      uuid;
begin
  insert into public.departments (name) values ('Accounts') returning id into v_accounts;
  insert into public.departments (name) values ('Sales') returning id into v_sales;
  insert into public.designations (department_id, grade_id, name)
    values (v_accounts, (select id from public.grades where code = 'MS0'), 'Senior Executive') returning id into v_senior;
  insert into public.designations (department_id, grade_id, name)
    values (v_sales, (select id from public.grades where code = 'EM1'), 'Sales Officer') returning id into v_officer;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Head Office') returning id into v_office;
  perform set_config('t.senior', v_senior::text, true);
  perform set_config('t.org_id', private.current_org_id()::text, true);

  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_accounts, 'designation_id', v_senior,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  v_emp := public.create_employee(v_common || '{"full_name":"HR Person"}');
  perform set_config('t.e_hr', v_emp::text, true);
  perform set_config('t.u_hr', public.grant_portal_access(v_emp, 'hr@r4.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Manager"}');
  perform set_config('t.e_mgr', v_emp::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(v_emp, 'mgr@r4.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  v_emp := public.create_employee(v_common || jsonb_build_object('full_name', 'Sales Manager', 'department_id', v_sales,
                                                                 'designation_id', v_officer));
  perform set_config('t.u_sales', public.grant_portal_access(v_emp, 'sales@r4.test', null, 'Passw0rd1',
                                   (select id from public.roles where system_key = 'manager'))::text, true);
  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 3)));
  perform set_config('t.vac', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                      'seats', 1, 'reason', 'replacement'))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');

-- HR: post, papers, applicants, shortlist.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_ids jsonb;
begin
  perform public.save_job_profile(current_setting('t.senior')::uuid, '{"duties":"Prepare and check vouchers"}'::jsonb);
  perform set_config('t.post', public.create_job_post_from_vacancy(current_setting('t.vac')::uuid)::text, true);
  perform public.publish_job_post(current_setting('t.post')::uuid);
  perform public.save_question_paper(current_setting('t.post')::uuid, 'objective', '{"duration_minutes":20,"pass_percent":50,"questions":[
    {"section":"job_knowledge","stem":"Which account is debited when rent is paid?","options":["Rent","Cash","Capital"],"correct_index":0,"marks":1},
    {"section":"aptitude","stem":"12 is what percent of 48?","options":["20%","25%","30%"],"correct_index":1,"marks":2},
    {"section":"language","stem":"Pick the correct spelling","options":["Recieve","Receeve","Receive"],"correct_index":2,"marks":2}]}', false);
  perform public.save_question_paper(current_setting('t.post')::uuid, 'written', '{"pass_percent":60,"questions":[
    {"section":"job_knowledge","stem":"Explain a bank reconciliation.","model_answer":"Match the cash book with the statement.","marks":10}]}', false);
  v_ids := public.add_applicants(current_setting('t.post')::uuid, jsonb_build_array(
    jsonb_build_object('full_name', 'Rahim Uddin', 'email', 'rahim@example.com'),
    jsonb_build_object('full_name', 'Karim Ahmed', 'email', 'karim@example.com'),
    jsonb_build_object('full_name', 'Sadia Islam', 'email', 'sadia@example.com')), 'email') -> 'ids';
  perform set_config('t.a1', v_ids ->> 0, true);
  perform set_config('t.a2', v_ids ->> 1, true);
  perform set_config('t.a3', v_ids ->> 2, true);
  perform public.move_applicants(current_setting('t.post')::uuid, array[(v_ids ->> 0)::uuid, (v_ids ->> 1)::uuid],
                                 'shortlisted', 'CVs checked by phone');
end $$;

-- ======================================================= 1. invitations
do $$
declare
  v jsonb;
begin
  begin
    perform public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a3')::uuid]);
    raise exception 'FAIL: invited someone who is not shortlisted';
  exception when invalid_parameter_value then null;
  end;
  v := public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a1')::uuid, current_setting('t.a2')::uuid]);
  perform set_config('t.tok1', (select x ->> 'token' from jsonb_array_elements(v) x where x ->> 'applicant_id' = current_setting('t.a1')), true);
  perform set_config('t.tok2', (select x ->> 'token' from jsonb_array_elements(v) x where x ->> 'applicant_id' = current_setting('t.a2')), true);
  assert length(current_setting('t.tok1')) = 48, 'a 48-character token';
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a where a ->> 'id' = current_setting('t.a1')) = 'test_invited', 'status test_invited';
  begin
    perform public.save_question_paper(current_setting('t.post')::uuid, 'objective',
      '{"duration_minutes":20,"questions":[{"stem":"Changed?","options":["a","b"],"correct_index":0,"marks":1}]}', false);
    raise exception 'FAIL: the paper changed after the invitations';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: HR invites shortlisted applicants only; the paper locks at the first invitation';
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from public.assessment_invites where token_hash = current_setting('t.tok1')), 'only the hash is stored';
end $$;

-- ======================================================= 2. Rahim takes the test (no login)
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.get_test('not-a-token');
    raise exception 'FAIL: a wrong token opened a test';
  exception when no_data_found then null;
  end;
  v := public.get_test(current_setting('t.tok1'));
  assert v ->> 'status' = 'invited' and v -> 'questions' = 'null'::jsonb and v ->> 'first_name' = 'Rahim'
         and (v ->> 'question_count')::int = 3 and (v ->> 'duration_minutes')::int = 20, 'before start ' || v::text;
  v := public.start_test(current_setting('t.tok1'));
  assert v ->> 'status' = 'started' and jsonb_array_length(v -> 'questions') = 3
         and (v ->> 'seconds_left')::int between 1195 and 1200, 'started';
  assert not exists (select 1 from jsonb_array_elements(v -> 'questions') q where q ? 'correct_index' or q ? 'model_answer'),
         'no answer key on the page';
  perform public.save_test_answer(current_setting('t.tok1'), 1, 0);
  perform public.save_test_answer(current_setting('t.tok1'), 2, 1);
  perform public.save_test_answer(current_setting('t.tok1'), 2, 0);   -- changed his mind
  perform public.save_test_answer(current_setting('t.tok1'), 3, 2);
  begin
    perform public.save_test_answer(current_setting('t.tok1'), 3, 5);
    raise exception 'FAIL: an option that does not exist was saved';
  exception when invalid_parameter_value then null;
  end;
  assert public.get_test(current_setting('t.tok1')) -> 'answers' = '{"1":0,"2":0,"3":2}', 'answers come back after a reload';
  assert public.submit_test(current_setting('t.tok1')) ->> 'status' = 'submitted', 'submitted';
  v := public.get_test(current_setting('t.tok1'));
  assert v ->> 'status' = 'submitted' and v -> 'questions' = 'null'::jsonb, 'no questions after submitting';
  begin
    perform public.save_test_answer(current_setting('t.tok1'), 1, 1);
    raise exception 'FAIL: answer changed after submitting';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.start_test(current_setting('t.tok1'));
    raise exception 'FAIL: a second attempt started';
  exception when invalid_parameter_value then null;
  end;
  -- Karim starts and answers one question.
  perform public.start_test(current_setting('t.tok2'));
  perform public.save_test_answer(current_setting('t.tok2'), 2, 1);
  raise notice 'PASS: the test page starts once, autosaves, never shows the key, and locks after submitting';
end $$;

-- Karim's time runs out.
reset role;
update public.assessment_invites set deadline_at = now() - interval '1 minute'
 where applicant_id = current_setting('t.a2')::uuid and status = 'started';

-- ======================================================= 3. results on the board
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  b  jsonb := public.get_assessment_board(current_setting('t.post')::uuid);
  r1 jsonb := (select r from jsonb_array_elements(b -> 'rows') r where r ->> 'applicant_id' = current_setting('t.a1'));
  r2 jsonb := (select r from jsonb_array_elements(b -> 'rows') r where r ->> 'applicant_id' = current_setting('t.a2'));
begin
  assert (r1 -> 'objective' ->> 'score')::numeric = 3 and (r1 -> 'objective' ->> 'total')::numeric = 5
         and (r1 -> 'objective' ->> 'percent')::numeric = 60.0 and (r1 -> 'objective' ->> 'passed')::boolean
         and r1 ->> 'status' = 'test_done', 'Rahim ' || r1::text;
  assert (r1 -> 'objective' -> 'sections' -> 'job_knowledge' ->> 'percent')::numeric = 100
         and (r1 -> 'objective' -> 'sections' -> 'aptitude' ->> 'percent')::numeric = 0
         and (r1 -> 'objective' -> 'sections' -> 'language' ->> 'percent')::numeric = 100, 'sections';
  assert (r2 -> 'objective' ->> 'percent')::numeric = 40.0 and not (r2 -> 'objective' ->> 'passed')::boolean
         and (r2 -> 'invite' ->> 'auto_submitted')::boolean and r2 ->> 'status' = 'test_done', 'Karim time up ' || r2::text;
  raise notice 'PASS: scores reach the board at once (60.0 %% pass, 40.0 %% fail after time-up), by section';
end $$;

-- Sadia: link expires unused, a new one works.
do $$
begin
  perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a3')::uuid], 'shortlisted', 'Late but strong CV');
  perform set_config('t.tok3', public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a3')::uuid], 1) -> 0 ->> 'token', true);
end $$;
reset role;
update public.assessment_invites set expires_at = now() - interval '1 minute' where applicant_id = current_setting('t.a3')::uuid;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  assert public.get_test(current_setting('t.tok3')) ->> 'status' = 'expired', 'expired link';
  begin
    perform public.start_test(current_setting('t.tok3'));
    raise exception 'FAIL: an expired link started';
  exception when invalid_parameter_value then null;
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_new text := public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a3')::uuid], 3) -> 0 ->> 'token';
begin
  perform set_config('t.tok3b', v_new, true);
  raise notice 'PASS: an unused link expires; a new link can be sent';
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select public.get_test(current_setting('t.tok3b')) ->> 'status' = 'invited' as new_link_ok;
reset role;

-- ======================================================= 4. written marks
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.save_written_marks(current_setting('t.a1')::uuid, '[{"position":1,"marks":11}]');
    raise exception 'FAIL: more marks than the question has';
  exception when invalid_parameter_value then null;
  end;
  v := public.save_written_marks(current_setting('t.a1')::uuid, '[{"position":1,"marks":7}]');
  assert (v ->> 'percent')::numeric = 70.0, 'written ' || v::text;
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a where a ->> 'id' = current_setting('t.a1')) = 'written_done', 'status written_done';
  assert (select (r -> 'written' ->> 'passed')::boolean from jsonb_array_elements(public.get_assessment_board(current_setting('t.post')::uuid) -> 'rows') r
          where r ->> 'applicant_id' = current_setting('t.a1')), 'written pass at 60 %';
  raise notice 'PASS: written marks per question, capped at the question marks; 7 / 10 = 70.0 %%';
end $$;

-- ======================================================= 5. interviews
reset role;
insert into public.holidays (org_id, name, date)
values (current_setting('t.org_id')::uuid, 'Test holiday', private.org_today(current_setting('t.org_id')::uuid) + 2);
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_panel jsonb := jsonb_build_array(current_setting('t.e_hr'), current_setting('t.e_mgr'));
  v_today date := private.org_today(current_setting('t.org_id')::uuid);
  p1      jsonb;
  p2      jsonb;
  v_day   date;
  v_due   date;
begin
  p1 := public.propose_interview_slot(current_setting('t.a1')::uuid, jsonb_build_object('panel', v_panel));
  v_day := ((p1 ->> 'starts_at')::timestamptz at time zone 'Asia/Dhaka')::date;
  v_due := (p1 ->> 'due_by')::date;
  assert (p1 ->> 'found')::boolean and v_day > v_today + 2
         and private.day_type(current_setting('t.org_id')::uuid, null, v_day) = 'workday'
         and ((p1 ->> 'starts_at')::timestamptz at time zone 'Asia/Dhaka')::time = '10:00', 'proposal ' || p1::text;
  assert v_due = v_today + 15, 'due 15 days after the written result';
  perform set_config('t.slot1', p1 ->> 'starts_at', true);
  perform public.save_interview(current_setting('t.a1')::uuid, jsonb_build_object('starts_at', p1 ->> 'starts_at', 'panel', v_panel,
    'mode', 'in_person', 'location', 'Head Office, 3rd floor', 'proposed_by', 'system'));
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a where a ->> 'id' = current_setting('t.a1')) = 'interview_scheduled', 'scheduled';

  p2 := public.propose_interview_slot(current_setting('t.a2')::uuid, jsonb_build_object('panel', v_panel));
  assert (p2 ->> 'starts_at')::timestamptz = (p1 ->> 'starts_at')::timestamptz + interval '45 minutes', 'next slot ' || p2::text;
  begin
    perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object('starts_at', p1 ->> 'starts_at',
      'panel', jsonb_build_array(current_setting('t.e_mgr')), 'mode', 'online', 'online_link', 'https://meet.example.com/x'));
    raise exception 'FAIL: two interviews for one interviewer at the same time';
  exception when exclusion_violation then null;
  end;
  begin
    perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object('starts_at', now() - interval '1 hour',
      'panel', v_panel, 'mode', 'in_person', 'location', 'Head Office'));
    raise exception 'FAIL: an interview in the past';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object('starts_at', p2 ->> 'starts_at',
      'panel', v_panel, 'mode', 'online', 'online_link', 'http://insecure.example.com'));
    raise exception 'FAIL: an online interview without an https link';
  exception when invalid_parameter_value then null;
  end;
  perform set_config('t.late', (((p2 ->> 'due_by')::date + 3) + time '11:00')::text, true);
  begin
    perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object(
      'starts_at', (current_setting('t.late')::timestamp at time zone 'Asia/Dhaka'), 'panel', v_panel, 'mode', 'in_person', 'location', 'Head Office'));
    raise exception 'FAIL: after the due date without a reason';
  exception when not_null_violation then null;
  end;
  perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object(
    'starts_at', (current_setting('t.late')::timestamp at time zone 'Asia/Dhaka'), 'panel', v_panel, 'mode', 'in_person',
    'location', 'Head Office', 'late_reason', 'Panel member travelling'));
  raise notice 'PASS: proposals skip holidays and clashes (10:00, then 10:45); clashes, past times and late dates are checked';
end $$;

-- Managers: own department may reschedule; tests and marks stay with HR.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object(
    'starts_at', (current_setting('t.slot1')::timestamptz + interval '45 minutes'), 'panel', jsonb_build_array(current_setting('t.e_mgr')),
    'mode', 'online', 'online_link', 'https://meet.example.com/karim'));
  assert jsonb_array_length(public.list_interviewer_options(current_setting('t.post')::uuid)) >= 3, 'interviewer list';
  begin
    perform public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid]);
    raise exception 'FAIL: manager sent test links';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_written_marks(current_setting('t.a2')::uuid, '[{"position":1,"marks":5}]');
    raise exception 'FAIL: manager entered marks';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sales')), true);
do $$
begin
  begin
    perform public.get_assessment_board(current_setting('t.post')::uuid);
    raise exception 'FAIL: Sales manager opened the Accounts board';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.save_interview(current_setting('t.a2')::uuid, jsonb_build_object(
      'starts_at', now() + interval '3 days', 'panel', jsonb_build_array(current_setting('t.e_mgr')), 'mode', 'in_person', 'location', 'X'));
    raise exception 'FAIL: Sales manager scheduled an Accounts interview';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: the department Manager reschedules; another department cannot; tests and marks are HR only';
end $$;

-- Cancel and screen out.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_int uuid := (select r -> 'interview' ->> 'id' from jsonb_array_elements(public.get_assessment_board(current_setting('t.post')::uuid) -> 'rows') r
                 where r ->> 'applicant_id' = current_setting('t.a1'))::uuid;
begin
  begin
    perform public.cancel_interview(v_int, 'no');
    raise exception 'FAIL: cancelled without a reason';
  exception when not_null_violation then null;
  end;
  perform public.cancel_interview(v_int, 'Candidate asked for another day');
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a where a ->> 'id' = current_setting('t.a1')) = 'written_done', 'status restored';
  perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid], 'screened_out', 'Test score too low');
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a
          where a ->> 'id' = current_setting('t.a2')) = 'screened_out', 'screened out';
  raise notice 'PASS: cancelling restores the status; screening out after the test cancels the interview';
end $$;

reset role;
do $$
begin
  assert not exists (select 1 from public.interview_schedules where applicant_id = current_setting('t.a2')::uuid and status = 'scheduled'),
         'screening out cancels the interview';
end $$;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000007a3","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_assessment_board(current_setting('t.post')::uuid);
    raise exception 'FAIL: Beta opened an Alpha board';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: company isolation';
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  begin
    perform public.get_assessment_board(current_setting('t.post')::uuid);
    raise exception 'FAIL: anon opened the board';
  exception when insufficient_privilege then null;
  end;
end $$;

select '==== ALL R4 TEST AND INTERVIEW CHECKS PASSED ====' as result;
rollback;
