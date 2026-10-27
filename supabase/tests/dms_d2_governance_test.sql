-- =============================================================================
-- DMS D2 tests: central review, custodians, requests, overdue lists, reminders.
--
-- Alpha: departments HR (code HR), Sales (SAL), Ops (OPS).
--   People: Owner (Admin), Hana (HR Manager, HR), Mona (Manager, Sales), Sam (employee, Sales),
--   Karim (employee, Ops: handles the licences).
--   1. Mona's upload goes to review: readers do not see it, she cannot approve it, a reason is needed to reject;
--      after a rejection she sends it again (same file allowed) and the Admin approves it.
--   2. The Admin's own upload publishes at once and is audited as published without review.
--   3. A Manager reviews only their own department; HR (dms.approve + upload_all) reviews every department.
--   4. Custodian: Karim cannot upload until the Admin makes him responsible for the licence folder.
--   5. Requests: a Manager asks only her department; Sam (no upload right) uploads for his request;
--      the request is done when approved; a missed due date shows as "Upload overdue".
--   6. Never auto-approved: past the review period it shows "Review overdue" and stays in review.
--   7. Reminders: one per step, a renewal task for the owner, nothing repeated.
--   8. Settings: review can be switched off.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D2 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d2001', 'authenticated', 'authenticated', 'd2platform@olympus.test', now(), '{"full_name":"D2 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d2002', 'authenticated', 'authenticated', 'd2owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d2001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Review', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d2002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
declare
  v_hr uuid; v_sales uuid; v_ops uuid; v_des_h uuid; v_des_s uuid; v_des_o uuid; v_branch uuid; v_office uuid; v_common jsonb;
  v jsonb;
begin
  insert into public.departments (name, code) values ('Human Resources', 'HR') returning id into v_hr;
  insert into public.departments (name, code) values ('Sales', 'SAL') returning id into v_sales;
  insert into public.departments (name, code) values ('Ops', 'OPS') returning id into v_ops;
  insert into public.designations (department_id, grade_id, name) values (v_hr, (select id from public.grades where code = 'EM1'), 'HR Officer') returning id into v_des_h;
  insert into public.designations (department_id, grade_id, name) values (v_sales, (select id from public.grades where code = 'EM1'), 'Sales Officer') returning id into v_des_s;
  insert into public.designations (department_id, grade_id, name) values (v_ops, (select id from public.grades where code = 'EM1'), 'Ops Officer') returning id into v_des_o;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.hr', v_hr::text, true);
  perform set_config('t.sales', v_sales::text, true);
  perform set_config('t.ops', v_ops::text, true);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_common || jsonb_build_object('full_name', 'Hana HR', 'department_id', v_hr, 'designation_id', v_des_h)),
                                  'hana@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(public.create_employee(v_common || jsonb_build_object('full_name', 'Mona Manager', 'department_id', v_sales, 'designation_id', v_des_s)),
                                  'mona@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(public.create_employee(v_common || jsonb_build_object('full_name', 'Sam Sales', 'department_id', v_sales, 'designation_id', v_des_s)),
                                 'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_karim', public.grant_portal_access(public.create_employee(v_common || jsonb_build_object('full_name', 'Karim Ops', 'department_id', v_ops, 'designation_id', v_des_o)),
                                   'karim@alpha.test', null, 'Passw0rd1', null)::text, true);
  v := public.get_dms_setup();
  perform set_config('t.f_lic', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'LIC'), true);
  perform set_config('t.f_hrp', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'HRP'), true);
  perform set_config('t.ty_fir', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'FIR'), true);
  perform set_config('t.ty_pol', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'POL'), true);
  perform set_config('t.ty_doc', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'DOC'), true);
  assert (v ->> 'require_review')::boolean and (v ->> 'review_days')::int = 3, 'review on, 3 working days by default';
end $$;

-- ======================================================= 1. review, reject with a reason, send again, approve
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v jsonb;
  c jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Sales visit policy', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'),
      'file', jsonb_build_object('name', 'visits.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('visits'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  c := public.dms_confirm_upload((v ->> 'version_id')::uuid);
  assert c ->> 'status' = 'in_review' and c ->> 'lifecycle' = 'pending', 'goes to review ' || c::text;
  assert (c ->> 'review_due_date')::date > current_date, 'review period set';
  perform set_config('t.d_visit', v ->> 'document_id', true);
  perform set_config('t.v_visit1', v ->> 'version_id', true);
  begin
    perform public.dms_decide((v ->> 'version_id')::uuid, true, null);
    raise exception 'FAIL: approved her own upload';
  exception when check_violation then null;
  end;
  assert (select count(*) from jsonb_array_elements(public.list_dms_tasks() -> 'my_uploads') x where x ->> 'version_status' = 'in_review') = 1,
         'her upload waits in My tasks';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert jsonb_array_length(public.list_dms_documents('{}')) = 0, 'readers do not see a document under review';
  begin
    perform public.dms_decide(current_setting('t.v_visit1')::uuid, true, null);
    raise exception 'FAIL: an employee reviewed';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  t jsonb := public.list_dms_tasks();
begin
  assert (select count(*) from jsonb_array_elements(t -> 'to_review') x where x ->> 'version_id' = current_setting('t.v_visit1')) = 1,
         'HR sees it in the review queue';
  begin
    perform public.dms_decide(current_setting('t.v_visit1')::uuid, false, '');
    raise exception 'FAIL: rejected without a reason';
  exception when invalid_parameter_value then null;
  end;
  assert (public.dms_decide(current_setting('t.v_visit1')::uuid, false, 'Add the visit claim form')) ->> 'status' = 'rejected', 'rejected';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  t jsonb := public.list_dms_tasks();
  v jsonb;
begin
  assert (select x ->> 'review_comment' from jsonb_array_elements(t -> 'my_uploads') x where x ->> 'version_status' = 'rejected') = 'Add the visit claim form',
         'she sees the reason ' || (t -> 'my_uploads')::text;
  -- Same file again is allowed after a rejection; it is v2 of the same code.
  v := public.dms_register_upload(jsonb_build_object('document_id', current_setting('t.d_visit'), 'change_note', 'Form added',
      'file', jsonb_build_object('name', 'visits.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('visits'::bytea), 'hex'))));
  assert v ->> 'version_name' = 'SAL-POL-0001_v2', 'sent again as v2 ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.v_visit2', v ->> 'version_id', true);
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
begin
  assert (public.dms_decide(current_setting('t.v_visit2')::uuid, true, 'OK')) ->> 'lifecycle' = 'published', 'the Admin approves';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.list_dms_documents('{}')) x where x ->> 'version_name' = 'SAL-POL-0001_v2') = 1,
         'readers see it once approved';
  raise notice 'PASS: uploads wait for review; no self-approval; a reason is needed to reject; sent again and approved';
end $$;

-- ======================================================= 2. the Admin's own upload
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Code of conduct 2027', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'coc.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('coc'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  assert (public.dms_confirm_upload((v ->> 'version_id')::uuid)) ->> 'status' = 'published', 'the Admin publishes directly';
  perform set_config('t.d_coc', v ->> 'document_id', true);
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.audit_logs where action = 'dms.published_without_review' and entity_id = current_setting('t.d_coc')::uuid) = 1,
         'audited as published without review';
  raise notice 'PASS: the Admin''s own uploads publish directly and are audited';
end $$;
set local role authenticated;

-- ======================================================= 3. who reviews what
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Leave rules', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'leave.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('leave'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  assert (public.dms_confirm_upload((v ->> 'version_id')::uuid)) ->> 'status' = 'in_review', 'HR''s upload also goes to review';
  perform set_config('t.v_leave', v ->> 'version_id', true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  assert jsonb_array_length(public.list_dms_tasks() -> 'to_review') = 0, 'the Sales manager does not get HR''s document';
  begin
    perform public.dms_decide(current_setting('t.v_leave')::uuid, true, null);
    raise exception 'FAIL: a manager reviewed another department';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
begin
  perform public.dms_decide(current_setting('t.v_leave')::uuid, true, null);
  raise notice 'PASS: a Manager reviews only their department; the Admin reviews everything';
end $$;

-- ======================================================= 4. custodian
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_karim')), true);
do $$
begin
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Fire licence', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_fir'), 'fields', '{"licence_no":"F-1","authority":"Fire Service"}'::jsonb, 'expiry_date', '2027-03-01',
      'file', jsonb_build_object('name', 'fire.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('fire'::bytea), 'hex'))));
    raise exception 'FAIL: uploaded without any right';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
select public.save_dms_custodian(current_setting('t.f_lic')::uuid, current_setting('t.u_karim')::uuid, true);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_karim')), true);
do $$
declare
  v jsonb;
begin
  assert (public.get_dms_library() -> 'can' ->> 'upload')::boolean, 'a custodian may upload';
  v := public.dms_register_upload(jsonb_build_object('title', 'Fire licence', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_fir'), 'fields', '{"licence_no":"F-1","authority":"Fire Service"}'::jsonb,
      'expiry_date', (current_date + 20)::text,
      'file', jsonb_build_object('name', 'fire.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('fire'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'OPS-FIR-0001', 'named from his department ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.v_fire', v ->> 'version_id', true);
  perform set_config('t.d_fire', v ->> 'document_id', true);
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
begin
  perform public.dms_decide(current_setting('t.v_fire')::uuid, true, null);
  raise notice 'PASS: the person responsible for a folder uploads there without a role permission';
end $$;

-- ======================================================= 5. requests
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  begin
    perform public.create_dms_request(jsonb_build_object('assignee_user_id', current_setting('t.u_karim'), 'note', 'Send the trade licence'));
    raise exception 'FAIL: a manager asked someone outside her department';
  exception when insufficient_privilege then null;
  end;
  perform set_config('t.r_sam', public.create_dms_request(jsonb_build_object('assignee_user_id', current_setting('t.u_sam'),
    'doc_type_id', current_setting('t.ty_doc'), 'folder_id', current_setting('t.f_hrp'), 'note', 'Upload the client price list',
    'due_date', (current_date + 2)::text))::text, true);
  perform set_config('t.r_late', public.create_dms_request(jsonb_build_object('assignee_user_id', current_setting('t.u_sam'),
    'note', 'Upload the visit report', 'due_date', current_date::text))::text, true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb;
begin
  assert (public.list_dms_tasks() #>> '{counts,requested_from_me}')::int = 2, 'Sam has two requests';
  v := public.dms_register_upload(jsonb_build_object('request_id', current_setting('t.r_sam'), 'title', 'Client price list',
      'file', jsonb_build_object('name', 'prices.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('prices'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'SAL-DOC-0001', 'uploaded for the request without upload permission ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.v_prices', v ->> 'version_id', true);
end $$;
reset role;
update public.dms_requests set due_date = current_date - 1 where id = current_setting('t.r_late')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  t jsonb := public.list_dms_tasks();
begin
  assert (select x ->> 'status' from jsonb_array_elements(t -> 'requests_i_made') x where x ->> 'id' = current_setting('t.r_sam')) = 'submitted',
         'the request shows the upload';
  assert (select (x ->> 'overdue')::boolean from jsonb_array_elements(t -> 'requests_i_made') x where x ->> 'id' = current_setting('t.r_late')),
         'the late request is overdue';
  assert (t #>> '{counts,upload_overdue}')::int = 1, 'upload overdue counted';
  perform public.dms_decide(current_setting('t.v_prices')::uuid, true, null);
end $$;
reset role;
do $$
begin
  assert (select status from public.dms_requests where id = current_setting('t.r_sam')::uuid) = 'done', 'approval completes the request';
  raise notice 'PASS: requests go to the right people; the assignee uploads without a role right; overdue requests stay listed';
end $$;
set local role authenticated;

-- ======================================================= 6. never auto-approved
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Sales targets', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_doc'),
      'file', jsonb_build_object('name', 'targets.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('targets'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.v_targets', v ->> 'version_id', true);
end $$;
reset role;
update public.dms_versions set review_due_date = current_date - 5 where id = current_setting('t.v_targets')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d2002","role":"authenticated"}', true);
do $$
declare
  t jsonb := public.list_dms_tasks();
begin
  assert (select (x ->> 'review_overdue')::boolean from jsonb_array_elements(t -> 'to_review') x where x ->> 'version_id' = current_setting('t.v_targets')),
         'shown as review overdue';
  assert (public.get_dms_overview(null, null) #>> '{counts,review_overdue}')::int = 1, 'overview counts it';
end $$;
reset role;
do $$
begin
  assert (select status from public.dms_versions where id = current_setting('t.v_targets')::uuid) = 'in_review', 'still waiting: never auto-approved';
  raise notice 'PASS: past the review period it is overdue, never approved by itself';
end $$;
set local role authenticated;

-- ======================================================= 7. reminders
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_karim')), true);
do $$
begin
  perform public.list_dms_tasks();
  perform public.list_dms_tasks();
end $$;
reset role;
do $$
begin
  -- Fire licence expires in 20 days: the 30-day step, once.
  assert (select count(*) from public.dms_reminders where document_id = current_setting('t.d_fire')::uuid and kind = 'expiry') = 1, 'one reminder';
  assert (select step_days from public.dms_reminders where document_id = current_setting('t.d_fire')::uuid and kind = 'expiry') = 30, 'the 30-day step';
  assert (select count(*) from public.dms_requests where document_id = current_setting('t.d_fire')::uuid and kind = 'renewal'
          and assignee_user_id = current_setting('t.u_karim')::uuid and status = 'open') = 1, 'a renewal task for the owner';
end $$;
update public.dms_documents set expiry_date = current_date + 5 where id = current_setting('t.d_fire')::uuid;
set local role authenticated;
select public.list_dms_tasks();
reset role;
do $$
begin
  assert (select count(*) from public.dms_reminders where document_id = current_setting('t.d_fire')::uuid and kind = 'expiry') = 2, 'the 7-day step follows';
  assert (select count(*) from public.dms_requests where document_id = current_setting('t.d_fire')::uuid and kind = 'renewal') = 1, 'still one renewal task';
  raise notice 'PASS: reminders go once per step, with one renewal task for the owner';
end $$;
set local role authenticated;

-- ======================================================= 8. settings
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.save_dms_settings('{"review_days":0}');
    raise exception 'FAIL: zero review days';
  exception when invalid_parameter_value then null;
  end;
  perform public.save_dms_settings('{"require_review":false,"reminder_days":[90,30,0]}');
  assert (public.get_dms_setup() -> 'reminder_days') = '[90, 30, 0]'::jsonb, 'reminder steps saved';
  v := public.dms_register_upload(jsonb_build_object('title', 'Holiday list', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_doc'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'holidays.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100,
                                 'hash', encode(sha256('holidays'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  assert (public.dms_confirm_upload((v ->> 'version_id')::uuid)) ->> 'status' = 'published', 'review switched off: published at once';
  raise notice 'PASS: review can be switched off; reminder steps are set by the company';
end $$;

select '==== ALL DMS D2 CHECKS PASSED ====' as result;
rollback;
