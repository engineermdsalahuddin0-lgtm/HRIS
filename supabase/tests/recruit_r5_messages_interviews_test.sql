-- =============================================================================
-- Onboarding process R5 tests: messages, pre-interview form, interviewer kit,
-- panel scores, composite result.
--
-- A. Composite = sum(weight x %) / sum(weights present); interview % = (panel mean - 1) / 4 x 100.
--    1 ATS 72, objective 80, written 65, one interviewer 4.2 (= 80 %) -> 7.2 + 20 + 13 + 36 = 76.2
--    2 no written test: (72 x 10 + 80 x 25 + 80 x 45) / 80 = 79.0
--    3 interviewers 4.6 and 3.0: mean 3.8 -> 70 %, spread 1.6 -> flag
-- B. Company Alpha: test links with "send" queue one email each (SMS off); nothing leaves before the
--    Admin sets up email; claim -> sent / failed -> retry. Keys write-only, service role only.
--    Rahim: objective 60.0 %, written 70.0 %; interview with three interviewers (4, 5, 3.8):
--    panel mean 4.27, interview 81.67 %, composite (60 x 25 + 70 x 20 + 81.67 x 45) / 90 = 73.06.
--    Pre-interview form by link; interviewers see others' scores only after scoring; people off the
--    panel cannot open the kit.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R5 MESSAGE AND INTERVIEW CHECKS PASSED".
-- =============================================================================
begin;

-- ======================================================= A. pure calculations
do $$
declare
  f jsonb;
begin
  f := private.composite_figures('{"weights":{"ats":10,"objective":25,"written":20,"interview":45},
                                   "ats":72,"objective":80,"written":65,"interview_means":[4.2]}');
  assert (f ->> 'interview_percent')::numeric = 80 and (f ->> 'composite')::numeric = 76.2, 'case 1 ' || f::text;
  f := private.composite_figures('{"weights":{"ats":10,"objective":25,"written":20,"interview":45},
                                   "ats":72,"objective":80,"interview_means":[4.2]}');
  assert (f ->> 'composite')::numeric = 79.0 and jsonb_array_length(f -> 'components') = 3, 'case 2 renormalised ' || f::text;
  f := private.composite_figures('{"weights":{"ats":10,"objective":25,"written":20,"interview":45},
                                   "interview_means":[4.6,3.0]}');
  assert (f ->> 'interview_percent')::numeric = 70 and (f ->> 'spread')::numeric = 1.6 and (f ->> 'spread_flag')::boolean
         and (f ->> 'composite')::numeric = 70, 'case 3 spread ' || f::text;
  assert private.render_template('Hi {name}, {job_title} {unknown}', '{"name":"Rahim","job_title":"Senior Executive"}')
         = 'Hi Rahim, Senior Executive {unknown}', 'placeholders';
  raise notice 'PASS: composite 76.2 / 79.0 (renormalised) / spread flag; templates fill known placeholders';
end $$;

-- ================================================================ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000008a1', 'authenticated', 'authenticated', 'r5platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000008a2', 'authenticated', 'authenticated', 'r5owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000008a3', 'authenticated', 'authenticated', 'r5owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000008a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Msg', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Msg', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000008a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000008a3'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a2","role":"authenticated"}', true);
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
  perform set_config('t.u_hr', public.grant_portal_access(v_emp, 'hr@r5.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Manager"}');
  perform set_config('t.e_mgr', v_emp::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(v_emp, 'mgr@r5.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Clerk"}');
  perform set_config('t.e_clerk', v_emp::text, true);
  perform set_config('t.u_clerk', public.grant_portal_access(v_emp, 'clerk@r5.test', null, 'Passw0rd1',
                                   (select id from public.roles where system_key = 'employee'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Outsider"}');
  perform set_config('t.u_out', public.grant_portal_access(v_emp, 'out@r5.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'employee'))::text, true);
  v_emp := public.create_employee(v_common || jsonb_build_object('full_name', 'Sales Manager', 'department_id', v_sales,
                                                                 'designation_id', v_officer));
  perform set_config('t.u_sales', public.grant_portal_access(v_emp, 'sales@r5.test', null, 'Passw0rd1',
                                   (select id from public.roles where system_key = 'manager'))::text, true);
  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 6)));
  perform set_config('t.vac', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                      'seats', 1, 'reason', 'replacement'))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');

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
  perform public.save_question_paper(current_setting('t.post')::uuid, 'written',
    '{"pass_percent":60,"questions":[{"stem":"Explain a bank reconciliation.","marks":10}]}', false);
  v_ids := public.add_applicants(current_setting('t.post')::uuid, jsonb_build_array(
    jsonb_build_object('full_name', 'Rahim Uddin', 'email', 'rahim@example.com', 'phone', '01711000001'),
    jsonb_build_object('full_name', 'Karim Ahmed', 'email', 'karim@example.com')), 'email') -> 'ids';
  perform set_config('t.a1', v_ids ->> 0, true);
  perform set_config('t.a2', v_ids ->> 1, true);
  perform public.move_applicants(current_setting('t.post')::uuid, array[(v_ids ->> 0)::uuid, (v_ids ->> 1)::uuid],
                                 'shortlisted', 'CVs checked by phone');
end $$;

-- ======================================================= B1. queueing
do $$
declare
  v_links jsonb;
  v_list  jsonb;
begin
  begin
    perform public.invite_to_test(current_setting('t.post')::uuid, array[current_setting('t.a1')::uuid], 3, 'ftp://bad', true);
    raise exception 'FAIL: a bad app address accepted';
  exception when invalid_parameter_value then null;
  end;
  v_links := public.invite_to_test(current_setting('t.post')::uuid,
    array[current_setting('t.a1')::uuid, current_setting('t.a2')::uuid], 3, 'https://hr.example.com/', true);
  perform set_config('t.tok1', (select x ->> 'token' from jsonb_array_elements(v_links) x where x ->> 'applicant_id' = current_setting('t.a1')), true);
  v_list := public.list_notifications(current_setting('t.post')::uuid);
  assert jsonb_array_length(v_list) = 2 and not exists (select 1 from jsonb_array_elements(v_list) n where n ->> 'channel' = 'sms'),
         'one email each, no SMS while SMS is off ' || v_list::text;
  assert (select n ->> 'subject' from jsonb_array_elements(v_list) n where n ->> 'applicant_id' = current_setting('t.a1'))
         = 'Online test for Senior Executive — Alpha Msg', 'subject filled';
  assert jsonb_array_length(public.claim_notifications(10) -> 'items') = 0, 'nothing is sent before email is set up';
  begin
    perform public.save_messaging_channel('email', '{"from_name":"Alpha HR","from_address":"hr@alpha.test","api_key":"re_test_1234567890"}');
    raise exception 'FAIL: HR changed the email key';
  exception when insufficient_privilege then null;
  end;
  perform public.save_message_template('interview_invite', 'email', 'Interview at {company}',
                                       E'Hi {name},\nYour interview: {interview_time}, {interview_place}.\nForm: {form_link}');
  raise notice 'PASS: test links queue one email each (body with the link); nothing leaves before email is set up';
end $$;
reset role;
do $$
begin
  assert (select body like '%https://hr.example.com/t/' || current_setting('t.tok1') || '%' from public.notifications
          where applicant_id = current_setting('t.a1')::uuid), 'the email carries the test link';
  assert not exists (select 1 from public.audit_logs where entity = 'notifications'), 'no message bodies in the audit log';
end $$;

-- ======================================================= B2. Admin sets up email and SMS
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a2","role":"authenticated"}', true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.save_messaging_channel('email', '{"from_name":"Alpha HR","from_address":"not-an-address","api_key":"re_test_1234567890"}');
    raise exception 'FAIL: a bad sender address accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_messaging_channel('email', '{"from_name":"Alpha HR","from_address":"HR@alpha.test","api_key":"re_test_1234567890"}');
  perform public.save_messaging_channel('sms', '{"url":"https://sms.example.com/send","method":"POST","to_param":"to","text_param":"msg",
                                                 "key_param":"api_key","sender_id":"ALPHA","sender_param":"from","api_key":"smskey-12345678","enabled":true}');
  v := public.get_messaging_settings();
  assert (v -> 'channels' -> 'email' ->> 'configured')::boolean and v -> 'channels' -> 'email' ->> 'last4' = '7890'
         and v -> 'channels' -> 'email' -> 'config' ->> 'from_address' = 'hr@alpha.test', 'email settings ' || v::text;
  assert position('re_test' in v::text) = 0 and position('smskey' in v::text) = 0, 'keys never returned';
  begin
    perform public.service_messaging_config(current_setting('t.org_id')::uuid, 'email');
    raise exception 'FAIL: a logged-in user read the email key';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role service_role;
select public.service_messaging_config(current_setting('t.org_id')::uuid, 'email') ->> 'api_key' = 're_test_1234567890' as service_reads_key;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_items jsonb := public.claim_notifications(10) -> 'items';
begin
  assert jsonb_array_length(v_items) = 2, 'both emails claimed once email is set up';
  perform public.mark_notification((v_items -> 0 ->> 'id')::uuid, true, 'resend-1', null);
  perform public.mark_notification((v_items -> 1 ->> 'id')::uuid, false, null, 'Domain not verified');
  assert jsonb_array_length(public.claim_notifications(10) -> 'items') = 0, 'nothing left';
  perform public.retry_notification((v_items -> 1 ->> 'id')::uuid);
  assert jsonb_array_length(public.claim_notifications(10) -> 'items') = 1, 'the failed one comes back after retry';
  raise notice 'PASS: Admin-only provider keys (never returned, service role only); claim, sent / failed, retry';
end $$;

-- Rahim takes the test; HR enters written marks.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select public.start_test(current_setting('t.tok1')) ->> 'status';
select public.save_test_answer(current_setting('t.tok1'), 1, 0);
select public.save_test_answer(current_setting('t.tok1'), 2, 0);
select public.save_test_answer(current_setting('t.tok1'), 3, 2);
select public.submit_test(current_setting('t.tok1')) ->> 'status';
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.save_written_marks(current_setting('t.a1')::uuid, '[{"position":1,"marks":7}]') ->> 'percent';

-- ======================================================= C. interview invitation and form
do $$
declare
  v_int  uuid;
  v_inv  jsonb;
begin
  v_int := public.save_interview(current_setting('t.a1')::uuid, jsonb_build_object('starts_at', now() + interval '30 minutes',
    'panel', jsonb_build_array(current_setting('t.e_hr'), current_setting('t.e_mgr'), current_setting('t.e_clerk')),
    'mode', 'in_person', 'location', 'Head Office, 3rd floor'));
  perform set_config('t.int', v_int::text, true);
  v_inv := public.send_interview_invite(v_int, 'https://hr.example.com');
  assert (v_inv ->> 'queued')::int = 2 and v_inv ->> 'form_link' like 'https://hr.example.com/f/%', 'email + SMS queued ' || v_inv::text;
  perform set_config('t.form', split_part(v_inv ->> 'form_link', '/f/', 2), true);
  assert (select n ->> 'subject' from jsonb_array_elements(public.list_notifications(current_setting('t.post')::uuid)) n
          where n ->> 'channel' = 'email' and n ->> 'subject' like 'Interview%') = 'Interview at Alpha Msg', 'edited template used';
  raise notice 'PASS: the interview invitation (edited template) goes by email and SMS with a form link';
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v jsonb := public.get_preinterview_form(current_setting('t.form'));
begin
  assert v ->> 'status' = 'open' and v ->> 'first_name' = 'Rahim' and v ->> 'interview_place' = 'Head Office, 3rd floor', 'form ' || v::text;
  begin
    perform public.submit_preinterview_form(current_setting('t.form'), '{"notice_period_days":30}');
    raise exception 'FAIL: form without attendance answer';
  exception when not_null_violation then null;
  end;
  begin
    perform public.submit_preinterview_form(current_setting('t.form'), '{"can_attend":true,"notice_period_days":500}');
    raise exception 'FAIL: a 500-day notice period accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.submit_preinterview_form(current_setting('t.form'),
    '{"can_attend":true,"current_employer":"ABC Ltd","notice_period_days":30,"expected_salary":35000,"questions":"Is there transport?"}');
  v := public.get_preinterview_form(current_setting('t.form'));
  assert v ->> 'status' = 'submitted' and (v -> 'answers' ->> 'expected_salary')::numeric = 35000, 'submitted';
  begin
    perform public.get_preinterview_form('wrong');
    raise exception 'FAIL: a wrong form link opened';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: the pre-interview form opens by link, checks answers and can be updated until the interview';
end $$;

-- ======================================================= D. interviewers
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_clerk')), true);
do $$
declare
  v jsonb;
begin
  assert jsonb_array_length(public.list_my_interviews()) = 1, 'the clerk sees the interview';
  v := public.get_interviewer_kit(current_setting('t.int')::uuid);
  assert v ->> 'access' = 'panel' and v -> 'all_scores' = 'null'::jsonb and (v -> 'objective' ->> 'percent')::numeric = 60
         and (v -> 'written' ->> 'percent')::numeric = 70 and v -> 'form' -> 'answers' ->> 'current_employer' = 'ABC Ltd', 'kit ' || v::text;
  begin
    perform public.submit_interview_score(current_setting('t.int')::uuid,
      '{"scores":{"job_knowledge":6,"communication":4,"problem_solving":4,"confidence":4,"culture_fit":4},"recommendation":"yes"}');
    raise exception 'FAIL: a score of 6 accepted';
  exception when invalid_parameter_value then null;
  end;
  v := public.submit_interview_score(current_setting('t.int')::uuid,
    '{"scores":{"job_knowledge":4,"communication":4,"problem_solving":4,"confidence":4,"culture_fit":4},"recommendation":"yes","comment":"Solid basics"}');
  assert (v ->> 'mean')::numeric = 4 and not (v ->> 'panel_complete')::boolean, 'clerk scored';
  assert jsonb_array_length(public.get_interviewer_kit(current_setting('t.int')::uuid) -> 'all_scores') = 1, 'own score visible after scoring';
  begin
    perform public.list_job_posts();
    raise exception 'FAIL: an interviewer opened job posts';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_out')), true);
do $$
begin
  assert jsonb_array_length(public.list_my_interviews()) = 0, 'not on the panel';
  begin
    perform public.get_interviewer_kit(current_setting('t.int')::uuid);
    raise exception 'FAIL: someone off the panel opened the kit';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sales')), true);
do $$
begin
  begin
    perform public.get_interviewer_kit(current_setting('t.int')::uuid);
    raise exception 'FAIL: the Sales manager opened an Accounts kit';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: interviewers see the kit, score 1-5, see others only after scoring; others are kept out';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
select public.submit_interview_score(current_setting('t.int')::uuid,
  '{"scores":{"job_knowledge":5,"communication":5,"problem_solving":5,"confidence":5,"culture_fit":5},"recommendation":"strong_yes"}') ->> 'mean';
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v   jsonb := public.submit_interview_score(current_setting('t.int')::uuid,
    '{"scores":{"job_knowledge":4,"communication":4,"problem_solving":4,"confidence":3,"culture_fit":4},"recommendation":"yes"}');
  res jsonb;
  f   jsonb;
begin
  assert (v ->> 'mean')::numeric = 3.8 and (v ->> 'panel_complete')::boolean, 'last score completes the panel';
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a
          where a ->> 'id' = current_setting('t.a1')) = 'interviewed', 'interviewed';
  res := public.get_candidate_results(current_setting('t.post')::uuid);
  f := res -> 'rows' -> 0 -> 'figures';
  assert res -> 'rows' -> 0 ->> 'applicant_id' = current_setting('t.a1') and (f ->> 'panel_mean')::numeric = 4.27
         and (f ->> 'interview_percent')::numeric = 81.67 and (f ->> 'spread')::numeric = 1.2 and not (f ->> 'spread_flag')::boolean
         and (f ->> 'composite')::numeric = 73.06, 'composite ' || f::text;
  assert (select r -> 'interview' ->> 'status' from jsonb_array_elements(public.get_assessment_board(current_setting('t.post')::uuid) -> 'rows') r
          where r ->> 'applicant_id' = current_setting('t.a1')) = 'done', 'board shows the done interview';
  raise notice 'PASS: panel complete -> interviewed; composite 73.06 (objective 60, written 70, interview 81.67)';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000008a3","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_interviewer_kit(current_setting('t.int')::uuid);
    raise exception 'FAIL: Beta opened an Alpha kit';
  exception when no_data_found then null;
  end;
  assert public.get_messaging_settings() -> 'channels' = '{}'::jsonb, 'Beta has no messaging settings';
  raise notice 'PASS: company isolation';
end $$;

select '==== ALL R5 MESSAGE AND INTERVIEW CHECKS PASSED ====' as result;
rollback;
