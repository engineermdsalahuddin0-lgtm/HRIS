-- =============================================================================
-- Onboarding process R6 + R7 tests: the end of the hiring cycle.
--
-- Company Alpha, Accounts, Senior Executive, ONE seat. Three applicants interviewed:
--   Karim rejected (rejection email queued), Rahim selected, Sadia: selecting is refused (seat
--   taken) -> waitlisted.
-- Offer: HR prepares (gross 35,000, joining in 10 days, reply in 5); checks on amounts and dates;
--   the preparer never approves (even with offer.approve); Admin sends back, then approves; HR
--   withdraws once and sends a new one; Rahim accepts on the link.
-- Pre-joining: photo only to the path the form gave; NID / account encrypted, shown as last 4;
--   HR returns it once, then verifies.
-- Joining: convert -> employee with card ID, pay 35,000 from the offer, salary account (copied
--   encrypted), NID, nominee; applicant joined; vacancy filled; checklist + 4 documents; named
--   feedback by link; case completed.
-- Close hiring: refused while CV files exist; then every applicant loses name / email / phone;
--   Rahim stays "joined" (the employee keeps the data); the post closes.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL R6 R7 OFFER AND JOINING CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000009a1', 'authenticated', 'authenticated', 'r6platform@olympus.test', now(), '{"full_name":"Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000009a2', 'authenticated', 'authenticated', 'r6owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000009a3', 'authenticated', 'authenticated', 'r6owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000009a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Offers', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Offers', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a1","role":"authenticated"}', true);
do $$
begin
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000009a2'));
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000009a3'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
do $$
declare
  v_accounts uuid;
  v_senior   uuid;
  v_branch   uuid;
  v_office   uuid;
  v_common   jsonb;
  v_emp      uuid;
begin
  insert into public.departments (name) values ('Accounts') returning id into v_accounts;
  insert into public.designations (department_id, grade_id, name)
    values (v_accounts, (select id from public.grades where code = 'MS0'), 'Senior Executive') returning id into v_senior;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'Head Office') returning id into v_office;
  perform set_config('t.senior', v_senior::text, true);
  perform set_config('t.office', v_office::text, true);
  perform set_config('t.org_id', private.current_org_id()::text, true);
  perform set_config('t.template', public.save_salary_template(null, '{"name":"Basic only","basic_amount":10000,"lines":[]}'::jsonb)::text, true);
  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_accounts, 'designation_id', v_senior,
                                 'branch_id', v_branch, 'office_id', v_office, 'join_date', '2026-01-01');
  v_emp := public.create_employee(v_common || '{"full_name":"HR Person"}');
  perform set_config('t.e_hr', v_emp::text, true);
  perform set_config('t.u_hr', public.grant_portal_access(v_emp, 'hr@r6.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'hr_manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Manager"}');
  perform set_config('t.e_mgr', v_emp::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(v_emp, 'mgr@r6.test', null, 'Passw0rd1',
                                 (select id from public.roles where system_key = 'manager'))::text, true);
  v_emp := public.create_employee(v_common || '{"full_name":"Accounts Clerk"}');
  perform set_config('t.e_clerk', v_emp::text, true);
  perform set_config('t.u_clerk', public.grant_portal_access(v_emp, 'clerk@r6.test', null, 'Passw0rd1',
                                   (select id from public.roles where system_key = 'employee'))::text, true);
  perform public.save_headcount_plan(v_accounts, jsonb_build_array(jsonb_build_object('designation_id', v_senior, 'sanctioned', 6)));
  perform set_config('t.vac', public.draft_vacancy(jsonb_build_object('department_id', v_accounts, 'designation_id', v_senior,
                                                                      'seats', 1, 'reason', 'replacement'))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.review_vacancy(current_setting('t.vac')::uuid, 'forward', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
select public.decide_vacancy(current_setting('t.vac')::uuid, 'approve');

-- HR: post, three applicants, shortlist, one interview each (different panels), all scored.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_ids jsonb;
begin
  perform public.save_job_profile(current_setting('t.senior')::uuid, '{"duties":"Prepare and check vouchers"}'::jsonb);
  perform set_config('t.post', public.create_job_post_from_vacancy(current_setting('t.vac')::uuid)::text, true);
  perform public.publish_job_post(current_setting('t.post')::uuid);
  v_ids := public.add_applicants(current_setting('t.post')::uuid, jsonb_build_array(
    jsonb_build_object('full_name', 'Rahim Uddin', 'email', 'rahim@example.com', 'phone', '01711000001'),
    jsonb_build_object('full_name', 'Karim Ahmed', 'email', 'karim@example.com'),
    jsonb_build_object('full_name', 'Sadia Islam', 'email', 'sadia@example.com')), 'email') -> 'ids';
  perform set_config('t.a1', v_ids ->> 0, true);
  perform set_config('t.a2', v_ids ->> 1, true);
  perform set_config('t.a3', v_ids ->> 2, true);
  perform public.move_applicants(current_setting('t.post')::uuid,
    array[(v_ids ->> 0)::uuid, (v_ids ->> 1)::uuid, (v_ids ->> 2)::uuid], 'shortlisted', 'CVs checked by phone');
  perform set_config('t.i1', public.save_interview((v_ids ->> 0)::uuid, jsonb_build_object('starts_at', now() + interval '30 minutes',
    'panel', jsonb_build_array(current_setting('t.e_hr')), 'mode', 'in_person', 'location', 'Head Office'))::text, true);
  perform set_config('t.i2', public.save_interview((v_ids ->> 1)::uuid, jsonb_build_object('starts_at', now() + interval '30 minutes',
    'panel', jsonb_build_array(current_setting('t.e_mgr')), 'mode', 'in_person', 'location', 'Head Office'))::text, true);
  perform set_config('t.i3', public.save_interview((v_ids ->> 2)::uuid, jsonb_build_object('starts_at', now() + interval '30 minutes',
    'panel', jsonb_build_array(current_setting('t.e_clerk')), 'mode', 'in_person', 'location', 'Head Office'))::text, true);
  perform public.submit_interview_score(current_setting('t.i1')::uuid,
    '{"scores":{"job_knowledge":5,"communication":5,"problem_solving":4,"confidence":5,"culture_fit":5},"recommendation":"strong_yes"}');
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
select public.submit_interview_score(current_setting('t.i2')::uuid,
  '{"scores":{"job_knowledge":2,"communication":3,"problem_solving":2,"confidence":2,"culture_fit":3},"recommendation":"no"}') ->> 'mean';
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_clerk')), true);
select public.submit_interview_score(current_setting('t.i3')::uuid,
  '{"scores":{"job_knowledge":4,"communication":4,"problem_solving":4,"confidence":4,"culture_fit":4},"recommendation":"yes"}') ->> 'mean';

-- ======================================================= 1. decisions
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb;
begin
  v := public.decide_candidate(current_setting('t.a2')::uuid, 'rejected', 'Weak interview', true);
  assert v ->> 'status' = 'rejected' and (v ->> 'queued')::int = 1, 'Karim rejected, email queued ' || v::text;
  assert (select n ->> 'subject' from jsonb_array_elements(public.list_notifications(current_setting('t.post')::uuid)) n
          where n ->> 'applicant_id' = current_setting('t.a2')) = 'Your application for Senior Executive — Alpha Offers', 'rejection subject';
  v := public.decide_candidate(current_setting('t.a1')::uuid, 'selected', 'Best panel score');
  assert v ->> 'status' = 'selected' and (v ->> 'composite')::numeric = 95, 'Rahim selected (interview 4.8 -> 95 %) ' || v::text;
  begin
    perform public.decide_candidate(current_setting('t.a3')::uuid, 'selected');
    raise exception 'FAIL: a second person selected for one seat';
  exception when check_violation then null;
  end;
  assert public.decide_candidate(current_setting('t.a3')::uuid, 'waitlist', 'Good backup') ->> 'status' = 'interviewed', 'Sadia waitlisted';
  raise notice 'PASS: reject (email queued), select within the seats, waitlist';
end $$;

-- ======================================================= 2. offer (maker-checker)
do $$
declare
  v_today date := private.org_today(current_setting('t.org_id')::uuid);
  v_ctx   jsonb := public.get_offer_context(current_setting('t.a1')::uuid);
  v_base  jsonb;
begin
  assert jsonb_array_length(v_ctx -> 'templates') = 1 and jsonb_array_length(v_ctx -> 'offices') = 1, 'context ' || v_ctx::text;
  v_base := jsonb_build_object('salary_template_id', current_setting('t.template'), 'gross', 35000, 'office_id', current_setting('t.office'),
                               'joining_date', v_today + 10, 'expires_on', v_today + 5, 'probation_months', 6,
                               'terms', 'Six months probation.');
  begin
    perform public.prepare_offer(current_setting('t.a1')::uuid, v_base || '{"gross":0}');
    raise exception 'FAIL: zero gross';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.prepare_offer(current_setting('t.a1')::uuid, v_base || jsonb_build_object('expires_on', v_today + 11));
    raise exception 'FAIL: reply date after joining';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.prepare_offer(current_setting('t.a3')::uuid, v_base);
    raise exception 'FAIL: offer to someone not selected';
  exception when invalid_parameter_value then null;
  end;
  perform set_config('t.offer', public.prepare_offer(current_setting('t.a1')::uuid, v_base)::text, true);
  begin
    perform public.decide_offer(current_setting('t.offer')::uuid, 'approve');
    raise exception 'FAIL: HR approved without offer.approve';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
insert into public.role_permissions (org_id, role_id, permission_key)
select r.org_id, r.id, 'offer.approve' from public.roles r where r.org_id = current_setting('t.org_id')::uuid and r.system_key = 'hr_manager';
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.decide_offer(current_setting('t.offer')::uuid, 'approve');
    raise exception 'FAIL: the preparer approved their own offer';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: offer checks; HR cannot approve, and nobody approves an offer they prepared';
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.decide_offer(current_setting('t.offer')::uuid, 'send_back');
    raise exception 'FAIL: sent back without a reason';
  exception when not_null_violation then null;
  end;
  perform public.decide_offer(current_setting('t.offer')::uuid, 'send_back', 'Add the transport allowance note');
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.prepare_offer(current_setting('t.a1')::uuid, jsonb_build_object('salary_template_id', current_setting('t.template'),
  'gross', 35000, 'office_id', current_setting('t.office'), 'joining_date', private.org_today(current_setting('t.org_id')::uuid) + 10,
  'expires_on', private.org_today(current_setting('t.org_id')::uuid) + 5, 'terms', 'Six months probation. Transport allowance included.'))::text = current_setting('t.offer') as same_draft;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
select public.decide_offer(current_setting('t.offer')::uuid, 'approve');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb;
begin
  perform public.withdraw_offer(current_setting('t.offer')::uuid, 'Wrong office chosen');
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a
          where a ->> 'id' = current_setting('t.a1')) = 'selected', 'back to selected';
  perform set_config('t.offer', public.prepare_offer(current_setting('t.a1')::uuid, jsonb_build_object(
    'salary_template_id', current_setting('t.template'), 'gross', 35000, 'office_id', current_setting('t.office'),
    'joining_date', private.org_today(current_setting('t.org_id')::uuid) + 10,
    'expires_on', private.org_today(current_setting('t.org_id')::uuid) + 5))::text, true);
  begin
    perform public.send_offer(current_setting('t.offer')::uuid, 'https://hr.example.com');
    raise exception 'FAIL: sent before approval';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a2","role":"authenticated"}', true);
select public.decide_offer(current_setting('t.offer')::uuid, 'approve');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb := public.send_offer(current_setting('t.offer')::uuid, 'https://hr.example.com');
begin
  assert (v ->> 'queued')::int = 1 and v ->> 'offer_link' like 'https://hr.example.com/offer/%', 'offer sent ' || v::text;
  perform set_config('t.tok', split_part(v ->> 'offer_link', '/offer/', 2), true);
  raise notice 'PASS: send back with a reason, approve by another person, withdraw, send a new offer by email';
end $$;

-- ======================================================= 3. the applicant accepts and fills the form
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v      jsonb := public.get_offer(current_setting('t.tok'));
  v_path text;
  v_form jsonb := jsonb_build_object('father_name', 'Abdul Uddin', 'mother_name', 'Rokeya Begum', 'date_of_birth', '1995-04-12',
    'gender', 'male', 'present_address', 'House 5, Road 2, Mirpur, Dhaka', 'permanent_address', 'Village Char, Bhola',
    'emergency_name', 'Abdul Uddin', 'emergency_phone', '01811000009',
    'nominees', jsonb_build_array(jsonb_build_object('name', 'Rokeya Begum', 'relation', 'Mother', 'phone', '01911000003')),
    'nid_number', '1234567890', 'payment_method', 'bank', 'bank_name', 'Dutch-Bangla Bank', 'branch_name', 'Mirpur',
    'account_name', 'Rahim Uddin', 'account_number', '1234567890123');
begin
  assert v ->> 'status' = 'sent' and (v ->> 'gross')::numeric = 35000 and v ->> 'designation' = 'Senior Executive'
         and v -> 'prejoining' = 'null'::jsonb, 'offer page ' || v::text;
  v := public.respond_offer(current_setting('t.tok'), 'accept', 'Happy to join');
  assert v ->> 'status' = 'accepted' and v -> 'prejoining' ->> 'status' = 'pending', 'accepted';
  begin
    perform public.respond_offer(current_setting('t.tok'), 'decline');
    raise exception 'FAIL: answered twice';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.submit_prejoining(current_setting('t.tok'), v_form);
    raise exception 'FAIL: submitted without a photo';
  exception when not_null_violation then null;
  end;
  begin
    perform public.start_prejoining_photo(current_setting('t.tok'), 'gif');
    raise exception 'FAIL: gif photo accepted';
  exception when invalid_parameter_value then null;
  end;
  v_path := public.start_prejoining_photo(current_setting('t.tok'), 'jpg');
  begin
    insert into storage.objects (bucket_id, name) values ('prehire-files', current_setting('t.org_id') || '/' || current_setting('t.a1') || '/other.jpg');
    raise exception 'FAIL: photo uploaded to a path the form did not give';
  exception when insufficient_privilege then null;
  end;
  insert into storage.objects (bucket_id, name) values ('prehire-files', v_path);
  begin
    perform public.submit_prejoining(current_setting('t.tok'), v_form || '{"nid_number":"12345"}');
    raise exception 'FAIL: a 5-digit NID accepted';
  exception when invalid_parameter_value then null;
  end;
  v := public.submit_prejoining(current_setting('t.tok'), v_form);
  assert v ->> 'status' = 'submitted' and v ->> 'nid_last4' = '7890' and v ->> 'number_last4' = '0123' and (v ->> 'has_photo')::boolean
         and position('1234567890123' in v::text) = 0, 'submitted, numbers masked ' || v::text;
  raise notice 'PASS: accept on the link; photo only to the given path; NID and account checked, stored, never shown back';
end $$;
reset role;
do $$
begin
  assert (select position(convert_to('1234567890', 'UTF8') in nid_enc) = 0 and position(convert_to('1234567890123', 'UTF8') in account_enc) = 0
          from public.prehire_records where offer_id = current_setting('t.offer')::uuid), 'stored encrypted';
  assert not exists (select 1 from public.audit_logs where coalesce(new_value::text, '') like '%1234567890%'), 'no NID or account in the audit log';
end $$;

-- HR returns, the applicant fixes, HR verifies.
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_rows jsonb := public.list_offers(current_setting('t.post')::uuid);
  v_pre  uuid := (select (r -> 'prehire' ->> 'id')::uuid from jsonb_array_elements(v_rows -> 'rows') r where r ->> 'applicant_id' = current_setting('t.a1'));
  v      jsonb := public.get_prehire(v_pre);
begin
  perform set_config('t.pre', v_pre::text, true);
  assert v ->> 'nid' = '•••• 7890' and v ->> 'number' = '•••• 0123' and v -> 'data' ->> 'father_name' = 'Abdul Uddin', 'HR view ' || v::text;
  assert (v_rows ->> 'seats_taken')::int = 1, 'one seat taken';
  begin
    perform public.convert_to_employee(v_pre);
    raise exception 'FAIL: converted before verification';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.verify_prehire(v_pre, 'return');
    raise exception 'FAIL: returned without saying what to fix';
  exception when not_null_violation then null;
  end;
  perform public.verify_prehire(v_pre, 'return', 'Please add the branch routing number');
end $$;
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
declare
  v jsonb := public.get_offer(current_setting('t.tok'));
begin
  assert v -> 'prejoining' ->> 'status' = 'returned' and v -> 'prejoining' ->> 'return_note' like 'Please add%', 'returned note visible';
  -- NID and account are not sent again: the stored (encrypted) ones are kept.
  v := public.submit_prejoining(current_setting('t.tok'), jsonb_build_object('father_name', 'Abdul Uddin', 'mother_name', 'Rokeya Begum',
    'date_of_birth', '1995-04-12', 'present_address', 'House 5, Road 2, Mirpur, Dhaka', 'permanent_address', 'Village Char, Bhola',
    'nominees', jsonb_build_array(jsonb_build_object('name', 'Rokeya Begum', 'relation', 'Mother')),
    'payment_method', 'bank', 'bank_name', 'Dutch-Bangla Bank', 'branch_name', 'Mirpur', 'routing_number', '090261234',
    'account_name', 'Rahim Uddin'));
  assert v ->> 'status' = 'submitted' and v ->> 'nid_last4' = '7890' and v ->> 'number_last4' = '0123' and v ->> 'routing_number' = '090261234', 'resubmitted';
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
select public.verify_prehire(current_setting('t.pre')::uuid, 'verify');

-- ======================================================= 4. joining
do $$
declare
  v    jsonb := public.convert_to_employee(current_setting('t.pre')::uuid, '{"send_feedback":true,"base_url":"https://hr.example.com"}');
  c    jsonb;
begin
  perform set_config('t.emp', v ->> 'employee_id', true);
  perform set_config('t.case', v ->> 'case_id', true);
  perform set_config('t.fb', split_part(v ->> 'feedback_link_path', '/joining-feedback/', 2), true);
  assert v ->> 'card_id' is not null and (v ->> 'feedback_queued')::boolean, 'converted ' || v::text;
  begin
    perform public.convert_to_employee(current_setting('t.pre')::uuid);
    raise exception 'FAIL: converted twice';
  exception when unique_violation then null;
  end;
  assert (select a ->> 'status' from jsonb_array_elements(public.list_applicants(current_setting('t.post')::uuid)) a
          where a ->> 'id' = current_setting('t.a1')) = 'joined', 'joined';
  c := public.get_onboarding_case(current_setting('t.case')::uuid);
  assert jsonb_array_length(c -> 'tasks') = 7 and jsonb_array_length(c -> 'documents') = 4 and jsonb_array_length(c -> 'nominees') = 1
         and (c -> 'offer' ->> 'gross')::numeric = 35000 and c -> 'employee' ->> 'designation' = 'Senior Executive', 'case ' || c::text;
end $$;
reset role;
do $$
begin
  assert (select e.status = 'active' and e.join_date = private.org_today(e.org_id) + 10 and e.probation_end_date = e.join_date + interval '6 months'
          from public.employees e where e.id = current_setting('t.emp')::uuid), 'employee active, joins on the offer date, probation 6 months';
  assert (select c.gross = 35000 and c.change_type = 'initial' from public.employee_compensation c where c.employee_id = current_setting('t.emp')::uuid), 'pay from the offer';
  assert (select p.number_last4 = '0123' and p.is_primary and p.routing_number = '090261234'
          and private.decrypt_secret(p.account_number_enc) = '1234567890123'
          from public.employee_payment_accounts p where p.employee_id = current_setting('t.emp')::uuid), 'salary account copied encrypted';
  assert (select s.nid_number = '1234567890' from public.employee_sensitive s where s.employee_id = current_setting('t.emp')::uuid), 'NID moved';
  assert (select v.status from public.vacancies v where v.id = current_setting('t.vac')::uuid) = 'filled', 'vacancy filled';
  assert exists (select 1 from public.notifications n where n.applicant_id = current_setting('t.a1')::uuid and n.template_key = 'joining_feedback'),
         'welcome / feedback email queued';
  raise notice 'PASS: convert -> employee with card ID, pay, salary account, NID, nominee; vacancy filled';
end $$;

-- Checklist, documents, completion.
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_kind text;
  v_task jsonb;
begin
  begin
    perform public.complete_onboarding(current_setting('t.case')::uuid);
    raise exception 'FAIL: completed with open checklist items';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.attach_signed_document(current_setting('t.case')::uuid, 'appointment_letter', 'pdf');
    raise exception 'FAIL: attached a scan that was never uploaded';
  exception when no_data_found then null;
  end;
  foreach v_kind in array array['appointment_letter', 'joining_report', 'nominee_form', 'code_of_conduct'] loop
    perform public.mark_document_printed(current_setting('t.case')::uuid, v_kind);
    insert into storage.objects (bucket_id, name)
    values ('onboarding-docs', current_setting('t.org_id') || '/' || current_setting('t.case') || '/' || v_kind || '.pdf');
    perform public.attach_signed_document(current_setting('t.case')::uuid, v_kind, 'pdf');
  end loop;
  assert (select t ->> 'done_at' is not null from jsonb_array_elements(public.get_onboarding_case(current_setting('t.case')::uuid) -> 'tasks') t
          where t ->> 'key' = 'documents_signed'), 'all four signed -> checklist item done';
  for v_task in select jsonb_array_elements(public.get_onboarding_case(current_setting('t.case')::uuid) -> 'tasks') loop
    perform public.set_onboarding_task((v_task ->> 'id')::uuid, true);
  end loop;
  perform public.complete_onboarding(current_setting('t.case')::uuid);
  assert public.get_onboarding_case(current_setting('t.case')::uuid) ->> 'status' = 'completed', 'case completed';
  raise notice 'PASS: documents printed and signed scans attached; checklist complete; case closed';
end $$;

-- Named joining feedback.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $$
begin
  assert public.get_joining_feedback(current_setting('t.fb')) ->> 'full_name' = 'Rahim Uddin', 'named feedback';
  begin
    perform public.submit_joining_feedback(current_setting('t.fb'), '{"ratings":{"overall":6,"recruiter_behaviour":5,"clarity":5,"first_day":5}}');
    raise exception 'FAIL: rating 6 accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.submit_joining_feedback(current_setting('t.fb'),
    '{"ratings":{"overall":5,"recruiter_behaviour":5,"clarity":4,"first_day":4},"comment":"Smooth process"}');
  raise notice 'PASS: the new employee gives named feedback by link';
end $$;

-- ======================================================= 5. close hiring and purge
reset role;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb;
begin
  assert (public.get_onboarding_case(current_setting('t.case')::uuid) -> 'feedback' -> 'ratings' ->> 'overall')::int = 5, 'HR sees the feedback';
  insert into storage.objects (bucket_id, name)
  values ('recruit-cvs', current_setting('t.org_id') || '/' || current_setting('t.post') || '/' || current_setting('t.a2') || '.pdf');
  perform public.attach_applicant_cv(current_setting('t.a2')::uuid, 'pdf');
  v := public.get_purge_plan(current_setting('t.post')::uuid);
  assert (v ->> 'blocking')::int = 0 and (v ->> 'applicants')::int = 3 and jsonb_array_length(v -> 'files' -> 'recruit-cvs') = 1
         and jsonb_array_length(v -> 'files' -> 'prehire-files') = 1, 'plan ' || v::text;
  begin
    perform public.purge_post_applicants(current_setting('t.post')::uuid, 'DELETE');
    raise exception 'FAIL: purged while CV files exist';
  exception when invalid_parameter_value then null;
  end;
end $$;
-- Stand-in for the app deleting the files through the Storage API: Supabase forbids deleting storage rows in SQL
-- (storage.protect_delete), so the test moves them out of the post's folder instead (all rolled back at the end).
reset role;
update storage.objects set name = 'purge-test/' || id::text
 where bucket_id in ('recruit-cvs', 'prehire-files') and name like current_setting('t.org_id') || '/%';
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
begin
  begin
    perform public.purge_post_applicants(current_setting('t.post')::uuid, 'yes');
    raise exception 'FAIL: purged without typing DELETE';
  exception when invalid_parameter_value then null;
  end;
  assert (public.purge_post_applicants(current_setting('t.post')::uuid, 'DELETE') ->> 'purged')::int = 3, 'three purged';
  assert jsonb_array_length(public.list_applicants(current_setting('t.post')::uuid)) = 0, 'no applicant data left to list';
  assert (select p ->> 'status' from jsonb_array_elements(public.list_job_posts() -> 'posts') p where p ->> 'id' = current_setting('t.post')) = 'closed', 'post closed';
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from public.applicants where job_post_id = current_setting('t.post')::uuid
                     and (full_name is not null or email is not null or phone is not null)), 'names, emails, phones cleared';
  assert (select status from public.applicants where id = current_setting('t.a1')::uuid) = 'joined'
         and (select status from public.applicants where id = current_setting('t.a2')::uuid) = 'purged', 'joined stays, others purged';
  assert not exists (select 1 from public.prehire_records where applicant_id = current_setting('t.a1')::uuid)
         and not exists (select 1 from public.notifications where job_post_id = current_setting('t.post')::uuid), 'forms and messages deleted';
  assert (select full_name from public.employees where id = current_setting('t.emp')::uuid) = 'Rahim Uddin', 'the employee record keeps the data';
  raise notice 'PASS: close hiring refuses while files exist, then clears every applicant; the employee keeps the record';
end $$;

-- Who may do it.
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  begin
    perform public.list_offers(current_setting('t.post')::uuid);
    raise exception 'FAIL: a manager opened offers (salary)';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000009a3","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_onboarding_case(current_setting('t.case')::uuid);
    raise exception 'FAIL: Beta opened an Alpha onboarding case';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: offers are HR only; company isolation';
end $$;

select '==== ALL R6 R7 OFFER AND JOINING CHECKS PASSED ====' as result;
rollback;
