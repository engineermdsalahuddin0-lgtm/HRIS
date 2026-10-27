-- =============================================================================
-- DMS D3 tests: ISO checklist.
--
-- Alpha (Admin uploads, so documents publish directly): ISO 9001 + ISO 45001 selected.
--   1. One Internal Audit Report counts for 9.2 in both standards (stored once).
--   2. An expired fire licence makes 45001 6.1.3 "stale"; a missing quality policy is a "gap".
--   3. A manual tag turns a general document into evidence; only dms.manage tags.
--   4. Employees cannot open the checklist; an auditor (dms.audit) can, and reads every document.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D3 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d3001', 'authenticated', 'authenticated', 'd3platform@olympus.test', now(), '{"full_name":"D3 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d3002', 'authenticated', 'authenticated', 'd3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d3001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d3002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha ISO', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d3001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d3002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d3002","role":"authenticated"}', true);
do $$
declare
  v_qa uuid; v_des uuid; v_branch uuid; v_office uuid; v jsonb;
begin
  insert into public.departments (name, code) values ('Quality', 'QA') returning id into v_qa;
  insert into public.designations (department_id, grade_id, name) values (v_qa, (select id from public.grades where code = 'EM1'), 'QA Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.qa', v_qa::text, true);
  perform set_config('t.u_emp', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
      'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Eva Employee', 'department_id', v_qa, 'designation_id', v_des)),
      'eva@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform public.set_dms_profiles(array['ISO_9001', 'ISO_45001'], false);
  v := public.get_dms_setup();
  perform set_config('t.f_rec', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'REC'), true);
  perform set_config('t.f_lic', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'LIC'), true);
  perform set_config('t.f_gen', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'GEN'), true);
  perform set_config('t.ty_iar', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'IAR'), true);
  perform set_config('t.ty_fir', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'FIR'), true);
  perform set_config('t.ty_doc', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'DOC'), true);
  assert (select count(*) from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'OHP') = 1, 'the H&S policy type comes with 45001';
end $$;

-- Uploads (the Admin publishes directly).
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Internal audit 2026', 'folder_id', current_setting('t.f_rec'),
      'doc_type_id', current_setting('t.ty_iar'), 'department_id', current_setting('t.qa'),
      'file', jsonb_build_object('name', 'audit.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('audit'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_audit', v ->> 'document_id', true);
  v := public.dms_register_upload(jsonb_build_object('title', 'Fire licence', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_fir'), 'department_id', current_setting('t.qa'), 'expiry_date', '2026-01-31',
      'fields', '{"licence_no":"F-9","authority":"Fire Service"}'::jsonb,
      'file', jsonb_build_object('name', 'fire.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('fire3'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  v := public.dms_register_upload(jsonb_build_object('title', 'Our quality promise', 'folder_id', current_setting('t.f_gen'),
      'doc_type_id', current_setting('t.ty_doc'), 'department_id', current_setting('t.qa'), 'classification', 'confidential',
      'file', jsonb_build_object('name', 'promise.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('promise'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_promise', v ->> 'document_id', true);
end $$;

-- ======================================================= 1–2. evidence, stale, gap
do $$
declare
  c jsonb := public.get_dms_compliance(null);
  q jsonb := (select x -> 'clauses' from jsonb_array_elements(c) x where x ->> 'profile' = 'ISO_9001');
  h jsonb := (select x -> 'clauses' from jsonb_array_elements(c) x where x ->> 'profile' = 'ISO_45001');
begin
  assert jsonb_array_length(c) = 2, 'two selected standards';
  assert (select x ->> 'status' from jsonb_array_elements(q) x where x ->> 'clause' = '9.2') = 'ok'
     and (select x ->> 'status' from jsonb_array_elements(h) x where x ->> 'clause' = '9.2') = 'ok', 'one audit report, two standards';
  assert (select x ->> 'status' from jsonb_array_elements(h) x where x ->> 'clause' = '6.1.3') = 'stale', 'expired licence is stale';
  assert (select x ->> 'status' from jsonb_array_elements(q) x where x ->> 'clause' = '5.2') = 'gap', 'no quality policy: a gap';
  assert (select x -> 'types' from jsonb_array_elements(q) x where x ->> 'clause' = '5.2') ? 'Quality Policy', 'the gap says what to upload';
  raise notice 'PASS: one document counts for every standard that needs it; expired evidence is stale; missing evidence is a gap';
end $$;

-- ======================================================= 3. manual tags
do $$
declare
  q jsonb;
begin
  perform public.set_dms_document_clauses(current_setting('t.d_promise')::uuid, '[{"profile":"ISO_9001","clause":"5.2"}]');
  q := (select x -> 'clauses' from jsonb_array_elements(public.get_dms_compliance('ISO_9001')) x);
  assert (select x ->> 'status' from jsonb_array_elements(q) x where x ->> 'clause' = '5.2') = 'ok', 'tagged document closes the gap';
  assert (public.get_dms_document_clauses(current_setting('t.d_audit')::uuid) -> 'tags') @> '[{"profile":"ISO_9001","clause":"9.2","source":"type"}]',
         'the document shows what it counts for';
  begin
    perform public.set_dms_document_clauses(current_setting('t.d_promise')::uuid, '[{"profile":"ISO_9001","clause":"99"}]');
    raise exception 'FAIL: unknown clause';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: a manual tag makes any document evidence';
end $$;

-- ======================================================= 4. auditors
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_emp')), true);
do $$
begin
  begin
    perform public.get_dms_compliance(null);
    raise exception 'FAIL: an employee opened the checklist';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.get_dms_document(current_setting('t.d_promise')::uuid);
    raise exception 'FAIL: an employee read a confidential document';
  exception when no_data_found then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d3002","role":"authenticated"}', true);
select public.set_role_permissions((select id from public.roles where system_key = 'employee' and org_id = current_setting('t.org')::uuid),
  array(select rp.permission_key from public.role_permissions rp join public.roles r on r.id = rp.role_id
        where r.system_key = 'employee' and r.org_id = current_setting('t.org')::uuid) || array['dms.audit']);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_emp')), true);
do $$
begin
  assert jsonb_array_length(public.get_dms_compliance(null)) = 2, 'the auditor opens the checklist';
  assert public.get_dms_document(current_setting('t.d_promise')::uuid) ->> 'doc_code' like 'QA-DOC-%', 'the auditor reads every document';
  begin
    perform public.set_dms_document_clauses(current_setting('t.d_promise')::uuid, '[]');
    raise exception 'FAIL: the auditor changed tags';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: the checklist is for managers and auditors; auditors read everything and change nothing';
end $$;

select '==== ALL DMS D3 CHECKS PASSED ====' as result;
rollback;
