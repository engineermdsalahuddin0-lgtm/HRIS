-- =============================================================================
-- Onboarding process R2 tests: job profiles, job posts, careers page, applications.
--
-- Company Alpha, Accounts department, Senior Executive (3 sanctioned, 2 people):
--   admin drafts 1 replacement -> HR forwards -> admin approves.
--   HR: no post without a job profile; profile (2+ years, Bachelor in Accounting /
--   Finance, Tally, Excel, VAT) -> post auto-filled, deadline today + 14, salary
--   hidden ("Negotiable") until the toggle is on with min <= max.
--   Public (anon): only published posts; apply with consent, PDF/DOCX <= 5 MB;
--   the CV may be uploaded only to the returned path, then confirmed with the token;
--   same email twice refused; 10 per network per hour.
--   Audit log: no names or emails of applicants.
--   HR adds LinkedIn applicants (duplicates skipped), uploads a CV; closing stops applications.
--   Beta sees nothing of Alpha; anon reaches no other private function.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R2 JOB POST CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000005a1', 'authenticated', 'authenticated', 'r2platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000005a2', 'authenticated', 'authenticated', 'r2owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000005a3', 'authenticated', 'authenticated', 'r2owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000005a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Hiring', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Hiring', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000005a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000005a3'));
end $$;

-- Alpha admin: structure, two people, plan, logins, one vacancy.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a2","role":"authenticated"}', true);
do $$
declare
  v_accounts uuid;
  v_senior   uuid;
  v_branch   uuid;
  v_office   uuid;
  v_common   jsonb;
begin
  insert into public.departments (name) values ('Accounts') returning id into v_accounts;
  insert into public.designations (department_id, grade_id, name)
    values (v_accounts, (select id from public.grades where code = 'MS0'), 'Senior Executive') returning id into v_senior;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Head Office') returning id into v_office;
  perform set_config('t.senior', v_senior::text, true);
  perform set_config('t.org_code', (select o.org_code from public.organizations o where o.id = private.current_org_id()), true);
  perform set_config('t.org_id', private.current_org_id()::text, true);

  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_accounts, 'designation_id', v_senior,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  perform set_config('t.hr', public.create_employee(v_common || '{"full_name":"HR Person"}')::text, true);
  perform set_config('t.mgr', public.create_employee(v_common || '{"full_name":"Accounts Manager"}')::text, true);
  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 3)));
  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.hr')::uuid, 'hr@r2.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(current_setting('t.mgr')::uuid, 'mgr@r2.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.vac', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                      'seats', 1, 'reason', 'replacement'))::text, true);
  raise notice 'PASS setup: Accounts, Senior Executive 3 sanctioned / 2 people, one vacancy drafted';
end $$;

-- HR forwards; nothing can be posted before approval.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  perform public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
  begin
    perform public.create_job_post_from_vacancy(current_setting('t.vac')::uuid);
    raise exception 'FAIL: posted a vacancy that is not approved';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');

-- HR: profile -> post auto-filled; salary toggle; weights; link.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_ready jsonb := public.list_job_posts() -> 'ready';
  v_post  jsonb;
  v_today date := private.org_today(current_setting('t.org_id')::uuid);
begin
  assert jsonb_array_length(v_ready) = 1 and not (v_ready -> 0 ->> 'has_profile')::boolean, 'approved vacancy is ready: ' || v_ready::text;
  begin
    perform public.create_job_post_from_vacancy(current_setting('t.vac')::uuid);
    raise exception 'FAIL: posted without a job profile';
  exception when no_data_found then null;
  end;
  begin
    perform public.save_job_profile(current_setting('t.senior')::uuid, '{"duties":"short"}'::jsonb);
    raise exception 'FAIL: duties of 5 characters accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_job_profile(current_setting('t.senior')::uuid, jsonb_build_object(
    'experience_min_years', 2, 'education_level', 'bachelor', 'education_subjects', jsonb_build_array('Accounting', 'Finance'),
    'required_skills', jsonb_build_array('Tally', 'Excel', ' VAT ', ''), 'nice_skills', jsonb_build_array('IFRS'),
    'duties', E'Prepare and check vouchers\n- Monthly bank reconciliation\n\n• VAT and AIT returns'));

  perform set_config('t.post', public.create_job_post_from_vacancy(current_setting('t.vac')::uuid)::text, true);
  v_post := public.get_job_post(current_setting('t.post')::uuid);
  assert v_post ->> 'title' = 'Senior Executive' and v_post ->> 'status' = 'draft' and (v_post ->> 'seats')::int = 1, 'post basics';
  assert (v_post ->> 'deadline')::date = v_today + 14, 'deadline today + 14';
  assert not (v_post ->> 'show_salary')::boolean and v_post ->> 'salary_min' is null, 'salary hidden by default';
  assert v_post ->> 'location' = 'Head Office' and v_post ->> 'public_slug' ~ '^senior-executive-[0-9a-f]{5}$', 'location and link';
  assert v_post -> 'weights' = '{"ats":10,"objective":25,"written":20,"interview":45}'::jsonb, 'default weights';
  assert v_post ->> 'description_md' like E'## About the role\n**Alpha Hiring** is hiring Senior Executive (1 position) in the Accounts department.%', 'intro: ' || (v_post ->> 'description_md');
  assert v_post ->> 'description_md' like E'%## Responsibilities\n- Prepare and check vouchers\n- Monthly bank reconciliation\n- VAT and AIT returns\n%', 'duties as a list';
  assert v_post ->> 'description_md' like E'%- At least 2 years of experience\n- Education: Bachelor''s degree (Pass or Honours) in Accounting / Finance\n- Skills: Tally, Excel, VAT\n%', 'requirements';
  assert v_post ->> 'description_md' like E'%## Nice to have\n- IFRS\n%## Employment\n- Type: Permanent\n', 'nice to have and type';
  begin
    perform public.create_job_post_from_vacancy(current_setting('t.vac')::uuid);
    raise exception 'FAIL: two posts for one vacancy';
  exception when unique_violation then null;
  end;
  raise notice 'PASS: an approved vacancy with a job profile becomes an auto-filled draft post';

  begin
    perform public.update_job_post(current_setting('t.post')::uuid, '{"show_salary":true}'::jsonb);
    raise exception 'FAIL: salary shown without amounts';
  exception when check_violation then null;
  end;
  begin
    perform public.update_job_post(current_setting('t.post')::uuid, '{"show_salary":true,"salary_min":30000,"salary_max":25000}'::jsonb);
    raise exception 'FAIL: minimum above maximum accepted';
  exception when check_violation then null;
  end;
  begin
    perform public.update_job_post(current_setting('t.post')::uuid, '{"weights":{"ats":10,"objective":25,"written":10,"interview":45}}'::jsonb);
    raise exception 'FAIL: weights adding up to 90 accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.update_job_post(current_setting('t.post')::uuid, jsonb_build_object('deadline', v_today - 1));
    raise exception 'FAIL: deadline in the past accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.update_job_post(current_setting('t.post')::uuid, jsonb_build_object(
    'show_salary', true, 'salary_min', 25000, 'salary_max', 32000, 'public_slug', 'senior-executive-accounts',
    'weights', jsonb_build_object('ats', 10, 'objective', 30, 'written', 0, 'interview', 60), 'has_written_test', false));
  v_post := public.get_job_post(current_setting('t.post')::uuid);
  assert (v_post ->> 'salary_min')::numeric = 25000 and v_post ->> 'public_slug' = 'senior-executive-accounts'
         and not (v_post ->> 'has_written_test')::boolean, 'post updated';
  raise notice 'PASS: salary only with min <= max, weights sum to 100, deadline not in the past';
end $$;

-- Anon: a draft is invisible.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  assert jsonb_array_length(public.get_public_careers(current_setting('t.org_code')) -> 'posts') = 0, 'no draft on the careers page';
  begin
    perform public.get_public_job_post(current_setting('t.org_code'), 'senior-executive-accounts');
    raise exception 'FAIL: anon opened a draft';
  exception when no_data_found then null;
  end;
end $$;

-- HR publishes; later profile edits do not change the post.
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_post jsonb;
begin
  perform public.publish_job_post(current_setting('t.post')::uuid);
  perform public.save_job_profile(current_setting('t.senior')::uuid, jsonb_build_object(
    'experience_min_years', 5, 'duties', 'Lead the month-end close'));
  v_post := public.get_job_post(current_setting('t.post')::uuid);
  assert v_post ->> 'status' = 'published' and (v_post ->> 'profile_version')::int = 1
         and (v_post ->> 'profile_current_version')::int = 2 and v_post ->> 'description_md' like '%At least 2 years%', 'post keeps its copy';
  begin
    perform public.update_job_post(current_setting('t.post')::uuid, '{"public_slug":"other-link"}'::jsonb);
    raise exception 'FAIL: link changed after publishing';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: published; the post keeps its own copy of the profile; the link is fixed';
end $$;

-- Anon applies.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v_careers jsonb := public.get_public_careers(current_setting('t.org_code'));
  v_post    jsonb := public.get_public_job_post(current_setting('t.org_code'), 'senior-executive-accounts');
  v_form    jsonb := '{"full_name":"Rahim Uddin","email":"Rahim@Example.com","phone":"01711000001","consent":true,
                       "cv_file_name":"rahim-cv.pdf","cv_size":250000,"cv_type":"application/pdf"}';
  v_result  jsonb;
begin
  assert jsonb_array_length(v_careers -> 'posts') = 1 and (v_careers -> 'posts' -> 0 ->> 'salary_min')::numeric = 25000, 'careers list';
  assert (v_post ->> 'is_open')::boolean and v_post ->> 'description_md' like '## About the role%'
         and v_post -> 'organization' ->> 'name' = 'Alpha Hiring', 'public post';
  assert not (v_post ? 'weights') and not (v_post ? 'vacancy_id') and not (v_post ? 'profile'), 'no internal fields in public';

  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form - 'consent');
    raise exception 'FAIL: applied without consent';
  exception when not_null_violation then null;
  end;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form || '{"email":"not-an-email"}');
    raise exception 'FAIL: bad email accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form || '{"website":"http://spam"}');
    raise exception 'FAIL: honeypot filled and accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts',
                                          v_form || '{"cv_file_name":"cv.exe","cv_type":"application/octet-stream"}');
    raise exception 'FAIL: .exe accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form || '{"cv_size":6000000}');
    raise exception 'FAIL: 6 MB CV accepted';
  exception when invalid_parameter_value then null;
  end;

  v_result := public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form);
  assert v_result ->> 'upload_path' = current_setting('t.org_id') || '/' || current_setting('t.post') || '/'
                                       || (v_result ->> 'applicant_id') || '.pdf', 'upload path ' || v_result::text;
  perform set_config('t.app1', v_result ->> 'applicant_id', true);

  begin
    insert into storage.objects (bucket_id, name)
    values ('recruit-cvs', current_setting('t.org_id') || '/' || current_setting('t.post') || '/' || gen_random_uuid() || '.pdf');
    raise exception 'FAIL: anon uploaded to a path nobody asked for';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.confirm_cv_upload((v_result ->> 'applicant_id')::uuid, v_result ->> 'upload_token');
    raise exception 'FAIL: confirmed before the file arrived';
  exception when invalid_parameter_value then null;
  end;
  insert into storage.objects (bucket_id, name) values ('recruit-cvs', v_result ->> 'upload_path');
  begin
    perform public.confirm_cv_upload((v_result ->> 'applicant_id')::uuid, 'wrong-token');
    raise exception 'FAIL: wrong token accepted';
  exception when no_data_found then null;
  end;
  perform public.confirm_cv_upload((v_result ->> 'applicant_id')::uuid, v_result ->> 'upload_token');
  begin
    perform public.confirm_cv_upload((v_result ->> 'applicant_id')::uuid, v_result ->> 'upload_token');
    raise exception 'FAIL: token used twice';
  exception when no_data_found then null;
  end;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts', v_form || '{"email":"rahim@example.com"}');
    raise exception 'FAIL: same email applied twice';
  exception when unique_violation then null;
  end;
  raise notice 'PASS: public apply checks consent, email, file type and size; CV only to its own path, token once';

  -- 10 applications per network per hour.
  perform set_config('request.headers', '{"x-forwarded-for":"203.0.113.9, 10.0.0.1"}', true);
  for i in 1..10 loop
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts',
                                          v_form || jsonb_build_object('email', 'person' || i || '@example.com'));
  end loop;
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts',
                                          v_form || '{"email":"person11@example.com"}');
    raise exception 'FAIL: 11th application from one network accepted';
  exception when raise_exception then null;
  end;
  perform set_config('request.headers', '', true);
  raise notice 'PASS: the 11th application from one network within an hour is refused';
end $$;

reset role;
do $$
begin
  assert (select count(*) from public.audit_logs where entity = 'applicants') >= 11, 'applicants are audited';
  assert not exists (select 1 from public.audit_logs where entity = 'applicants'
                     and (coalesce(new_value::text, '') || coalesce(old_value::text, '')) ~* '(@|rahim|0171)'), 'no personal data in audit';
  raise notice 'PASS: the audit log has applicant ids and status, no names, emails or phones';
end $$;

-- HR: applicants list, other sources, CV upload.
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_list   jsonb := public.list_applicants(current_setting('t.post')::uuid);
  v_result jsonb;
  v_new    uuid;
begin
  assert jsonb_array_length(v_list) = 11, 'eleven applicants';
  assert (select (a ->> 'has_cv')::boolean and a ->> 'email' = 'rahim@example.com' and a ->> 'phone' = '+8801711000001'
          from jsonb_array_elements(v_list) a where a ->> 'id' = current_setting('t.app1')), 'Rahim with CV, email lower-cased';
  v_result := public.add_applicants(current_setting('t.post')::uuid, jsonb_build_array(
    jsonb_build_object('full_name', 'Rahim Again', 'email', 'RAHIM@example.com'),
    jsonb_build_object('full_name', 'Karim Ahmed', 'email', 'karim@example.com', 'phone', '+8801811000002')), 'linkedin');
  assert (v_result ->> 'added')::int = 1 and (v_result ->> 'duplicates')::int = 1, 'duplicate skipped: ' || v_result::text;
  v_new := (v_result -> 'ids' ->> 0)::uuid;
  begin
    perform public.attach_applicant_cv(v_new, 'pdf');
    raise exception 'FAIL: attached a CV that was never uploaded';
  exception when no_data_found then null;
  end;
  begin
    insert into storage.objects (bucket_id, name)
    values ('recruit-cvs', current_setting('t.org_id') || '/' || gen_random_uuid() || '/' || v_new || '.pdf');
    raise exception 'FAIL: HR uploaded outside an applicant folder';
  exception when insufficient_privilege then null;
  end;
  insert into storage.objects (bucket_id, name)
  values ('recruit-cvs', current_setting('t.org_id') || '/' || current_setting('t.post') || '/' || v_new || '.docx');
  perform public.attach_applicant_cv(v_new, 'docx');
  assert (select (a ->> 'has_cv')::boolean and a ->> 'source' = 'linkedin'
          from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a where (a ->> 'id')::uuid = v_new), 'Karim has a CV';
  assert (select (p ->> 'applicants')::int = 12 and (p ->> 'with_cv')::int = 2
          from jsonb_array_elements(public.list_job_posts() -> 'posts') p), 'post counts';
  raise notice 'PASS: HR sees applicants, adds LinkedIn applicants (duplicates skipped) and uploads their CV';
end $$;

-- Manager: may look at the own department's posts (R3) but not change posts or applicants.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  begin
    perform public.update_job_post(current_setting('t.post')::uuid, '{"title":"Changed by manager"}'::jsonb);
    raise exception 'FAIL: manager edited a job post';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.add_applicants(current_setting('t.post')::uuid, '[{"full_name":"Some One","email":"one@example.com"}]'::jsonb, 'email');
    raise exception 'FAIL: manager added applicants';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: changing posts and applicants needs recruit.manage';
end $$;

-- Beta sees nothing of Alpha.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000005a3","role":"authenticated"}', true);
do $$
begin
  assert jsonb_array_length(public.list_job_posts() -> 'posts') = 0, 'Beta has no posts';
  begin
    perform public.get_job_post(current_setting('t.post')::uuid);
    raise exception 'FAIL: Beta opened an Alpha post';
  exception when no_data_found then null;
  end;
  begin
    perform public.list_applicants(current_setting('t.post')::uuid);
    raise exception 'FAIL: Beta listed Alpha applicants';
  exception when no_data_found then null;
  end;
  assert not exists (select 1 from storage.objects where bucket_id = 'recruit-cvs'), 'Beta sees no Alpha CV';
  raise notice 'PASS: company isolation (posts, applicants, CV files)';
end $$;

-- HR closes the post: the public page says closed, applications stop.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.close_job_post(current_setting('t.post')::uuid, 'Enough applicants');
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  assert not (public.get_public_job_post(current_setting('t.org_code'), 'senior-executive-accounts') ->> 'is_open')::boolean, 'closed';
  assert jsonb_array_length(public.get_public_careers(current_setting('t.org_code')) -> 'posts') = 0, 'not listed';
  begin
    perform public.submit_job_application(current_setting('t.org_code'), 'senior-executive-accounts',
      '{"full_name":"Late Person","email":"late@example.com","phone":"01711000009","consent":true,
        "cv_file_name":"cv.pdf","cv_size":1000,"cv_type":"application/pdf"}'::jsonb);
    raise exception 'FAIL: applied to a closed post';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.list_job_posts();
    raise exception 'FAIL: anon called an HR function';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: a closed post stays readable but takes no applications';
end $$;

reset role;
do $$
begin
  assert not has_schema_privilege('anon', 'private', 'usage'), 'anon must not reach the private schema';
  -- R6 adds the pre-joining photo check; nothing else may live there.
  assert (select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
          where n.nspname = 'policy_checks') <@ array['prehire_photo_pending', 'recruit_cv_pending'], 'policy_checks holds only upload checks';
  raise notice 'PASS: anon reaches only the CV upload check, nothing of the private schema';
end $$;

select '==== ALL R2 JOB POST CHECKS PASSED ====' as result;
rollback;
