-- =============================================================================
-- Onboarding process R3 tests: CV reading, gate, ATS score, shortlist,
-- question papers, AI key, roles.
--
-- A. ATS score = skills 40 + experience 25 + education 20 (+ relevance 15),
--    divided by 85 when relevance is not set (basic mode), as a percent:
--    1  3/3 skills, nice 1/1, 4 y (min 2), masters >= bachelor, subject, rel 12 -> 40+25+20+12 = 97.0 pass
--    2  2/3, nice 0/1, 3 y, bachelor, no subject, no rel -> 26.67+25+15 = 66.67/85 = 78.4 pass
--    3  1/3, 1 y of 2, hsc < bachelor, rel 5 -> 13.33+12.5+0+5 = 30.8 fail
--    4  no required skills, years and level unknown, no rel -> 40/85 = 47.1 review
--    5  0/2, min 0, any education, no rel -> 0+25+20 = 45/85 = 52.9 pass
-- B. Basic reading: years from "2019 - 2022" + "2022 - Present" (merged), education lines
--    skipped; BBA -> bachelor; "Tally", "Excel" found; Accounting subject.
-- C. Company Alpha (post as in R2: 2+ years, Bachelor in Accounting / Finance, Tally, Excel, VAT; IFRS):
--    Rahim (basic) 26.67 + 25 + 20 = 71.67 / 85 = 84.3 pass; Karim (AI: 1 y, HSC, VAT, rel 4)
--    13.33 + 12.5 + 0 + 4 = 29.8 fail; HR correction (3 y, bachelor, Tally+VAT, subject, rel 10) -> 81.7.
--    Shortlisting a fail needs a reason; screening out always does.
--    Question papers: Accounts manager sets them and fills the bank; the next post of the same
--    designation starts from the bank; "post only" leaves the bank alone; locked papers refuse edits.
--    AI key: Admin only, never returned, encrypted; only the service role decrypts it.
--    Sales manager and a plain employee see nothing; Beta sees nothing of Alpha.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R3 SCREENING CHECKS PASSED".
-- =============================================================================
begin;

-- ======================================================= A. the calculation
do $$
declare
  f jsonb;
begin
  f := private.ats_figures('{"req_total":3,"req_matched":3,"nice_total":1,"nice_matched":1,"min_years":2,"years":4,
                             "required_level":"bachelor","applicant_level":"masters","subjects_required":2,
                             "subject_matched":true,"relevance":12}');
  assert (f ->> 'score')::numeric = 97.0 and f ->> 'gate' = 'pass' and (f ->> 'max')::int = 100, 'case 1 ' || f::text;
  f := private.ats_figures('{"req_total":3,"req_matched":2,"nice_total":1,"nice_matched":0,"min_years":2,"years":3,
                             "required_level":"bachelor","applicant_level":"bachelor","subjects_required":2,
                             "subject_matched":false}');
  assert (f ->> 'skills')::numeric = 26.67 and (f ->> 'education')::numeric = 15 and (f ->> 'max')::int = 85
         and (f ->> 'score')::numeric = 78.4 and f ->> 'gate' = 'pass', 'case 2 ' || f::text;
  f := private.ats_figures('{"req_total":3,"req_matched":1,"min_years":2,"years":1,"required_level":"bachelor",
                             "applicant_level":"hsc","relevance":5}');
  assert (f ->> 'experience')::numeric = 12.5 and (f ->> 'score')::numeric = 30.8 and f ->> 'gate' = 'fail'
         and f -> 'reasons' = '["experience_below_minimum","education_below_required"]', 'case 3 ' || f::text;
  f := private.ats_figures('{"req_total":0,"min_years":2,"required_level":"bachelor"}');
  assert (f ->> 'score')::numeric = 47.1 and f ->> 'gate' = 'review'
         and f -> 'reasons' = '["experience_unknown","education_unknown"]', 'case 4 ' || f::text;
  f := private.ats_figures('{"req_total":2,"req_matched":0,"min_years":0,"required_level":"any"}');
  assert (f ->> 'score')::numeric = 52.9 and f ->> 'gate' = 'pass', 'case 5 ' || f::text;
  raise notice 'PASS: the 5 ATS cases give the hand-calculated scores and gates';
end $$;

-- ======================================================= B. basic reading
do $$
declare
  v_cv text := E'# Rahim Uddin\n\n## Experience\nAccounts Officer, ABC Ltd, Jan 2019 - Dec 2022\n'
               || E'Senior Accountant, XYZ Ltd, 2022 – Present\n\n## Education\nBBA in Accounting, University of Dhaka, 2012 - 2016\n'
               || E'HSC, Dhaka College, 2011\n\n## Skills\nTally ERP, MS Excel, reconciliation';
begin
  assert private.estimate_years(v_cv, '2026-10-25') = 7, 'years ' || coalesce(private.estimate_years(v_cv, '2026-10-25')::text, 'null');
  assert private.estimate_years(E'Officer 2015-2018\nManager 2017 to 2020', '2026-10-25') = 5, 'overlap merged';
  assert private.estimate_years('I have 6+ years of experience in accounts', '2026-10-25') = 6, 'stated years';
  assert private.estimate_years('No dates here', '2026-10-25') is null, 'unknown years';
  assert private.detect_education(v_cv) = 'bachelor', 'BBA is a bachelor';
  assert private.detect_education('M.Sc in Physics; B.Sc') = 'masters', 'highest degree';
  assert private.detect_education('SSC 2010, HSC 2012') = 'hsc', 'HSC';
  assert private.detect_education('nothing') is null, 'no degree';
  assert private.text_has_term(v_cv, 'Excel') and private.text_has_term(v_cv, 'tally')
         and not private.text_has_term(v_cv, 'VAT') and not private.text_has_term('Excellent', 'Excel'), 'whole words';
  assert private.text_has_term('C++ and C#', 'C++'), 'symbols in a term';
  raise notice 'PASS: basic reading estimates years (merged, education skipped), degree and skills';
end $$;

-- ================================================================ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000006a1', 'authenticated', 'authenticated', 'r3platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000006a2', 'authenticated', 'authenticated', 'r3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000006a3', 'authenticated', 'authenticated', 'r3owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000006a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Screening', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Screening', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000006a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000006a3'));
end $$;

-- Alpha admin: Accounts and Sales, HR, two managers, an employee, an approved vacancy.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
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
  perform set_config('t.accounts', v_accounts::text, true);
  perform set_config('t.senior', v_senior::text, true);
  perform set_config('t.org_id', private.current_org_id()::text, true);

  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_accounts, 'designation_id', v_senior,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  v_emp := public.create_employee(v_common || '{"full_name":"HR Person"}');
  perform set_config('t.u_hr', public.grant_portal_access(v_emp, 'hr@r3.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Manager"}');
  perform set_config('t.u_mgr', public.grant_portal_access(v_emp, 'mgr@r3.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Clerk"}');
  perform set_config('t.u_emp', public.grant_portal_access(v_emp, 'emp@r3.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'employee'))::text, true);
  v_emp := public.create_employee(v_common || jsonb_build_object('full_name', 'Sales Manager', 'department_id', v_sales,
                                                                 'designation_id', v_officer));
  perform set_config('t.u_sales', public.grant_portal_access(v_emp, 'sales@r3.test', null, 'Passw0rd1',
                                   (select id from public.roles where system_key = 'manager'))::text, true);

  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 4)));
  perform set_config('t.vac', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                      'seats', 1, 'reason', 'replacement'))::text, true);
  perform set_config('t.vac2', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                       'seats', 1, 'reason', 'new_position'))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
select public.review_vacancy(current_setting('t.vac2')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');
select public.decide_vacancy(current_setting('t.vac2')::uuid, 'approve');

-- HR: profile, post, three applicants with CVs.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_ids jsonb;
  v_id  text;
begin
  perform public.save_job_profile(current_setting('t.senior')::uuid, jsonb_build_object(
    'experience_min_years', 2, 'education_level', 'bachelor', 'education_subjects', jsonb_build_array('Accounting', 'Finance'),
    'required_skills', jsonb_build_array('Tally', 'Excel', 'VAT'), 'nice_skills', jsonb_build_array('IFRS'),
    'duties', 'Prepare and check vouchers'));
  perform set_config('t.post', public.create_job_post_from_vacancy(current_setting('t.vac')::uuid)::text, true);
  perform public.publish_job_post(current_setting('t.post')::uuid);
  v_ids := public.add_applicants(current_setting('t.post')::uuid, jsonb_build_array(
    jsonb_build_object('full_name', 'Rahim Uddin', 'email', 'rahim@example.com'),
    jsonb_build_object('full_name', 'Karim Ahmed', 'email', 'karim@example.com'),
    jsonb_build_object('full_name', 'Scan Only', 'email', 'scan@example.com')), 'email') -> 'ids';
  perform set_config('t.a1', v_ids ->> 0, true);
  perform set_config('t.a2', v_ids ->> 1, true);
  perform set_config('t.a3', v_ids ->> 2, true);
  for v_id in select jsonb_array_elements_text(v_ids) loop
    insert into storage.objects (bucket_id, name)
    values ('recruit-cvs', current_setting('t.org_id') || '/' || current_setting('t.post') || '/' || v_id || '.pdf');
    perform public.attach_applicant_cv(v_id::uuid, 'pdf');
  end loop;
end $$;

-- ======================================================= C1. AI key and settings
do $$
begin
  begin
    perform public.save_ai_integration('{"api_key":"sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234"}'::jsonb);
    raise exception 'FAIL: HR saved the AI key';
  exception when insufficient_privilege then null;
  end;
  perform public.save_recruit_settings('{"cv_mode":"ai"}'::jsonb);
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a2","role":"authenticated"}', true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.save_ai_integration('{"api_key":"not-a-key"}'::jsonb);
    raise exception 'FAIL: a wrong key format accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_ai_integration('{"api_key":"sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234","model":"claude-haiku-5-5"}'::jsonb);
  v := public.get_recruit_settings();
  assert v ->> 'cv_mode' = 'ai' and (v -> 'ai' ->> 'configured')::boolean and v -> 'ai' ->> 'last4' = '1234'
         and v -> 'ai' ->> 'model' = 'claude-haiku-5-5', 'settings ' || v::text;
  assert position('sk-ant' in v::text) = 0, 'the key is never returned';
  begin
    perform public.service_ai_key(current_setting('t.org_id')::uuid);
    raise exception 'FAIL: a logged-in user read the decrypted key';
  exception when insufficient_privilege then null;
  end;
  -- Model change without a new key keeps the key.
  perform public.save_ai_integration('{"model":"claude-opus-5-5"}'::jsonb);
end $$;
reset role;
set local role service_role;
do $$
begin
  assert public.service_ai_key(current_setting('t.org_id')::uuid) ->> 'api_key' = 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234'
         and public.service_ai_key(current_setting('t.org_id')::uuid) ->> 'model' = 'claude-opus-5-5', 'service role decrypts';
end $$;
reset role;
do $$
begin
  assert (select position(convert_to('sk-ant', 'UTF8') in secret_enc) = 0 from public.org_integrations
          where org_id = current_setting('t.org_id')::uuid), 'stored encrypted';
  assert not exists (select 1 from public.audit_logs where coalesce(new_value::text, '') || coalesce(old_value::text, '') like '%sk-ant%'),
         'no key in the audit log';
  raise notice 'PASS: AI key is Admin-only, write-only, encrypted; only the service role decrypts it';
end $$;

-- ======================================================= C2. reading CVs
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_claim jsonb := public.claim_cv_reads(current_setting('t.post')::uuid, 5);
  v       jsonb;
  v_year  integer := extract(year from private.org_today(current_setting('t.org_id')::uuid))::integer;
begin
  assert v_claim ->> 'mode' = 'ai' and (v_claim ->> 'ai_ready')::boolean and jsonb_array_length(v_claim -> 'items') = 3
         and v_claim -> 'job' -> 'profile' ->> 'education_level' = 'bachelor', 'claim ' || v_claim::text;
  assert jsonb_array_length(public.claim_cv_reads(current_setting('t.post')::uuid, 5) -> 'items') = 0, 'claimed once';

  -- Rahim: AI failed, basic reading used.
  v := public.save_cv_read(current_setting('t.a1')::uuid, jsonb_build_object('mode_used', 'basic', 'ai_error', 'rate limited',
    'markdown', E'# Rahim Uddin\n## Experience\nAccounts Officer, ABC Ltd, Jan 2019 - Dec 2022\nSenior Accountant, XYZ Ltd, 2022 - Present\n'
                || E'## Education\nBBA in Accounting, University of Dhaka, 2012 - 2016\n## Skills\nTally ERP, MS Excel'));
  assert v ->> 'gate' = 'pass' and (v ->> 'ats_score')::numeric = 84.3, 'Rahim ' || v::text;
  assert (select (p ->> 'years')::numeric = v_year - 2019 and p ->> 'education_level' = 'bachelor'
          and p -> 'matched_required' = '["Tally","Excel"]' and (p ->> 'subject_matched')::boolean
          from (select a -> 'profile' as p from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a
                where a ->> 'id' = current_setting('t.a1')) x), 'Rahim profile';

  -- Karim: AI facts.
  v := public.save_cv_read(current_setting('t.a2')::uuid, jsonb_build_object('mode_used', 'ai', 'ai_model', 'claude-opus-5-5',
    'markdown', 'A short CV with enough text to be kept for the record.',
    'ai', jsonb_build_object('experience_known', true, 'total_experience_years', 1, 'education_level', 'hsc',
                             'education_subjects', '[]'::jsonb, 'skills', jsonb_build_array('VAT returns', 'VAT'),
                             'relevance', 4, 'relevance_reason', 'Little accounts work', 'summary', 'Junior clerk.')));
  assert v ->> 'gate' = 'fail' and (v ->> 'ats_score')::numeric = 29.8, 'Karim ' || v::text;

  -- Scan only: no text -> failed, HR enters by hand.
  v := public.save_cv_read(current_setting('t.a3')::uuid, '{"mode_used":"basic","markdown":"  "}'::jsonb);
  assert v ->> 'status' = 'failed', 'scanned CV fails';
  raise notice 'PASS: CVs read in AI and basic mode give the expected scores; an empty CV is marked for manual entry';

  -- Shortlist and screen out.
  perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a1')::uuid], 'shortlisted');
  begin
    perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid], 'shortlisted');
    raise exception 'FAIL: shortlisted a failing applicant without a reason';
  exception when not_null_violation then null;
  end;
  begin
    perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid], 'screened_out');
    raise exception 'FAIL: screened out without a reason';
  exception when not_null_violation then null;
  end;
  perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid], 'screened_out', 'Below the required degree');
  perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a2')::uuid], 'applied', 'Reconsider after HR check');

  -- HR corrects Karim's profile.
  v := public.save_applicant_profile(current_setting('t.a2')::uuid, jsonb_build_object(
    'years', 3, 'education_level', 'bachelor', 'matched_required', jsonb_build_array('Tally', 'VAT'),
    'subject_matched', true, 'relevance', 10, 'relevance_reason', 'Checked by phone'));
  assert v ->> 'gate' = 'pass' and (v ->> 'ats_score')::numeric = 81.7, 'corrected ' || v::text;
  -- A re-read does not overwrite HR's corrections.
  assert (select array_agg(i ->> 'applicant_id' order by i ->> 'applicant_id')
          from jsonb_array_elements(public.claim_cv_reads(current_setting('t.post')::uuid, 5, true, clock_timestamp()) -> 'items') i)
         = (select array_agg(x order by x) from unnest(array[current_setting('t.a1'), current_setting('t.a3')]) x),
         're-read takes Rahim and the failed scan, not the corrected Karim';
  raise notice 'PASS: shortlist / screen out need reasons where required; HR corrections rescore and survive a re-read';
end $$;

reset role;
do $$
begin
  assert not exists (select 1 from public.audit_logs where entity in ('applicant_profiles', 'applicants')
                     and coalesce(new_value::text, '') ~* '(rahim|tally|@)'), 'no CV text or names in audit';
  raise notice 'PASS: the audit log has scores and gates, no CV text';
end $$;

-- ======================================================= C3. question papers
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
declare
  v jsonb := public.get_question_papers(current_setting('t.post')::uuid);
  v_paper jsonb := '{"duration_minutes":30,"pass_percent":50,"questions":[
    {"section":"job_knowledge","stem":"Which account is debited when cash is paid for rent?","options":["Rent","Cash","Capital","Sales"],"correct_index":0,"marks":1},
    {"section":"aptitude","stem":"12 is what percent of 48?","options":["20%","25%","30%"],"correct_index":1,"marks":2}]}';
begin
  assert v -> 'papers' -> 'objective' = 'null'::jsonb and jsonb_array_length(v -> 'bank' -> 'objective') = 0
         and (v ->> 'ai_available')::boolean, 'empty start';
  begin
    perform public.save_question_paper(current_setting('t.post')::uuid, 'objective',
      jsonb_set(v_paper, '{questions,1,correct_index}', '3'), true);
    raise exception 'FAIL: correct answer outside the options accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_question_paper(current_setting('t.post')::uuid, 'objective', v_paper, true);
  assert jsonb_array_length(public.list_applicants(current_setting('t.post')::uuid)) = 3, 'manager sees own department applicants';
  begin
    perform public.move_applicants(current_setting('t.post')::uuid, array[current_setting('t.a3')::uuid], 'screened_out', 'Not for managers');
    raise exception 'FAIL: manager shortlisted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.claim_cv_reads(current_setting('t.post')::uuid);
    raise exception 'FAIL: manager started CV reading';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v      jsonb := public.get_question_papers(current_setting('t.post')::uuid);
  v_post uuid;
begin
  assert (v -> 'papers' -> 'objective' ->> 'total_marks')::numeric = 3 and (v -> 'papers' -> 'objective' ->> 'question_count')::int = 2
         and jsonb_array_length(v -> 'bank' -> 'objective') = 2, 'paper and bank';
  -- The next post of the same designation starts from the bank.
  v_post := public.create_job_post_from_vacancy(current_setting('t.vac2')::uuid);
  v := public.get_question_papers(v_post);
  assert v -> 'papers' -> 'objective' = 'null'::jsonb and jsonb_array_length(v -> 'bank' -> 'objective') = 2
         and v -> 'bank' -> 'objective' -> 1 ->> 'stem' = '12 is what percent of 48?', 'bank reused';
  perform public.save_question_paper(v_post, 'written',
    '{"questions":[{"section":"job_knowledge","stem":"Explain a bank reconciliation.","model_answer":"Match the cash book with the bank statement.","marks":10}]}', false);
  v := public.get_question_papers(v_post);
  assert (v -> 'papers' -> 'written' ->> 'total_marks')::numeric = 10 and jsonb_array_length(v -> 'bank' -> 'written') = 0, 'post only';
  perform set_config('t.post2', v_post::text, true);
  raise notice 'PASS: papers are saved per post, fill the bank on request, and the next post starts from the bank';
end $$;

reset role;
update public.question_papers set locked_at = now() where job_post_id = current_setting('t.post2')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.save_question_paper(current_setting('t.post2')::uuid, 'written',
      '{"questions":[{"stem":"Changed after the start?","marks":5}]}', false);
    raise exception 'FAIL: a locked paper changed';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: a locked paper cannot change';
end $$;

-- ======================================================= C4. who may see it
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sales')), true);
do $$
begin
  assert jsonb_array_length(public.list_job_posts() -> 'posts') = 0 and not (public.list_job_posts() -> 'can' ->> 'manage')::boolean,
         'Sales manager sees no Accounts posts';
  begin
    perform public.get_question_papers(current_setting('t.post')::uuid);
    raise exception 'FAIL: Sales manager opened Accounts papers';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.list_applicants(current_setting('t.post')::uuid);
    raise exception 'FAIL: Sales manager listed Accounts applicants';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_emp')), true);
do $$
begin
  begin
    perform public.list_job_posts();
    raise exception 'FAIL: an employee opened job posts';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.get_question_papers(current_setting('t.post')::uuid);
    raise exception 'FAIL: an employee opened question papers';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  assert jsonb_array_length(public.list_job_posts() -> 'posts') = 2 and jsonb_array_length(public.list_job_posts() -> 'ready') = 0,
         'Accounts manager sees both Accounts posts, no ready list';
  raise notice 'PASS: Manager own department only, employee nothing';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000006a3","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_question_papers(current_setting('t.post')::uuid);
    raise exception 'FAIL: Beta opened Alpha papers';
  exception when no_data_found then null;
  end;
  begin
    perform public.save_cv_read(current_setting('t.a1')::uuid, '{"mode_used":"basic","markdown":"x"}');
    raise exception 'FAIL: Beta wrote an Alpha profile';
  exception when no_data_found then null;
  end;
  assert public.get_recruit_settings() -> 'ai' = 'null'::jsonb, 'Beta has no AI key';
  raise notice 'PASS: company isolation';
end $$;

select '==== ALL R3 SCREENING CHECKS PASSED ====' as result;
rollback;
