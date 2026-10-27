-- =============================================================================
-- DMS D5 tests: the DMS feeds the AI assistant.
--
-- Alpha (Admin uploads, so documents publish directly); Eva is an employee.
--   1. A published Internal HR policy becomes an assistant resource (topic HR rules, read from dms-documents).
--   2. Confidential, department-only and AI-off documents never go; the document says why.
--   3. A new version replaces the old resource and removes its chunks; archiving removes it.
--   4. The AI switch per type adds and removes its documents.
--   5. DMS resources cannot be changed from the assistant side; citations open the document page.
--   6. The overview counts indexed documents.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D5 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d5001', 'authenticated', 'authenticated', 'd5platform@olympus.test', now(), '{"full_name":"D5 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d5002', 'authenticated', 'authenticated', 'd5owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d5001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d5002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha AI Docs', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d5001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d5002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d5002","role":"authenticated"}', true);
do $$
declare
  v_hr uuid; v_des uuid; v_branch uuid; v_office uuid; v jsonb;
begin
  insert into public.departments (name, code) values ('Human Resources', 'HR') returning id into v_hr;
  insert into public.designations (department_id, grade_id, name) values (v_hr, (select id from public.grades where code = 'EM1'), 'HR Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.hr', v_hr::text, true);
  perform set_config('t.u_eva', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
      'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Eva Employee', 'department_id', v_hr, 'designation_id', v_des)),
      'eva@alpha.test', null, 'Passw0rd1', null)::text, true);
  v := public.get_dms_setup();
  perform set_config('t.f_hrp', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'HRP'), true);
  perform set_config('t.ty_pol', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'POL'), true);
  assert (select (t ->> 'ai_enabled')::boolean and t ->> 'assistant_topic' = 'kb.hr_rules' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'POL'),
         'HR policies go to the assistant by default';
  assert (select not (t ->> 'ai_enabled')::boolean from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'TRD'), 'licences do not';
end $$;

-- Uploads by the Admin (published at once).
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Leave policy', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'leave.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('leave5'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_leave', v ->> 'document_id', true);
  perform set_config('t.p_leave', v ->> 'path', true);
  v := public.dms_register_upload(jsonb_build_object('title', 'Salary bands', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'), 'classification', 'confidential',
      'file', jsonb_build_object('name', 'bands.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('bands5'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_bands', v ->> 'document_id', true);
  v := public.dms_register_upload(jsonb_build_object('title', 'HR team rota rules', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'scope', 'departments', 'scope_department_ids', jsonb_build_array(current_setting('t.hr')),
      'file', jsonb_build_object('name', 'rota.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('rota5'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_rota', v ->> 'document_id', true);
end $$;

-- ======================================================= 1–2. what goes, what never goes
reset role;
do $$
declare
  r public.assistant_resources;
begin
  select * into r from public.assistant_resources where dms_document_id = current_setting('t.d_leave')::uuid and status <> 'archived';
  assert r.status = 'processing' and r.topic_key = 'kb.hr_rules' and r.file_path = current_setting('t.p_leave') and r.name like 'HR-POL-0001%',
         'the policy waits for indexing';
  assert (private.assistant_resource_json(r) ->> 'bucket') = 'dms-documents', 'the Edge Function reads it from the DMS bucket';
  assert not exists (select 1 from public.assistant_resources where dms_document_id in (current_setting('t.d_bands')::uuid, current_setting('t.d_rota')::uuid)),
         'confidential and department-only documents never go';
  perform set_config('t.res1', r.id::text, true);
  insert into public.assistant_chunks (org_id, source, resource_id, chunk_index, location, passage, embedding_model)
  values (r.org_id, 'resource', r.id, 0, '1', 'Casual leave is ten days.', 'test-model');
end $$;
set local role authenticated;
do $$
begin
  assert public.get_dms_document_ai(current_setting('t.d_bands')::uuid) ->> 'reason' like 'Confidential%', 'the document says why';
  assert public.get_dms_document_ai(current_setting('t.d_rota')::uuid) ->> 'reason' like 'Documents for some departments%', 'and for department-only';
  raise notice 'PASS: published Internal company-wide policies go to the assistant; confidential and department-only never do';
end $$;

-- ======================================================= 3. new version, archive
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('document_id', current_setting('t.d_leave'),
      'file', jsonb_build_object('name', 'leave2.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 120, 'hash', encode(sha256('leave5b'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
end $$;
reset role;
do $$
begin
  assert (select status from public.assistant_resources where id = current_setting('t.res1')::uuid) = 'archived', 'v1 left the store';
  assert not exists (select 1 from public.assistant_chunks where resource_id = current_setting('t.res1')::uuid), 'its chunks are gone';
  assert (select count(*) from public.assistant_resources where dms_document_id = current_setting('t.d_leave')::uuid and status = 'processing'
          and version = 2) = 1, 'v2 waits for indexing';
end $$;
set local role authenticated;
select public.archive_dms_document(current_setting('t.d_leave')::uuid, true);
reset role;
do $$
begin
  assert not exists (select 1 from public.assistant_resources where dms_document_id = current_setting('t.d_leave')::uuid and status <> 'archived'),
         'archiving removes it';
  raise notice 'PASS: a new version replaces the old resource and its chunks; archiving removes it';
end $$;
set local role authenticated;
select public.archive_dms_document(current_setting('t.d_leave')::uuid, false);

-- ======================================================= 4. AI switch per type
do $$
begin
  perform public.save_dms_doc_type_ai(current_setting('t.ty_pol')::uuid, false, null);
end $$;
reset role;
do $$
begin
  assert not exists (select 1 from public.assistant_resources where org_id = current_setting('t.org')::uuid and source = 'dms' and status <> 'archived'),
         'switching AI off removes the type''s documents';
end $$;
set local role authenticated;
select public.save_dms_doc_type_ai(current_setting('t.ty_pol')::uuid, true, 'kb.company_policy');
reset role;
do $$
begin
  assert (select topic_key from public.assistant_resources where dms_document_id = current_setting('t.d_leave')::uuid and status <> 'archived') = 'kb.company_policy',
         'switching it on adds them again with the chosen topic';
  update public.assistant_resources set status = 'ready' where dms_document_id = current_setting('t.d_leave')::uuid and status = 'processing';
  perform set_config('t.res_now', (select id from public.assistant_resources where dms_document_id = current_setting('t.d_leave')::uuid and status = 'ready')::text, true);
  raise notice 'PASS: the AI switch of a type adds and removes its documents';
end $$;

-- ======================================================= 5. assistant side
set local role authenticated;
do $$
begin
  begin
    perform public.update_assistant_resource(current_setting('t.res_now')::uuid, '{"action":"archive"}');
    raise exception 'FAIL: archived a DMS resource from the assistant';
  exception when check_violation then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_eva')), true);
do $$
begin
  assert public.assistant_resource_path(current_setting('t.res_now')::uuid) = 'dms:' || current_setting('t.d_leave'), 'the citation opens the document page';
  raise notice 'PASS: DMS resources are managed in the DMS; citations open the document';
end $$;

-- ======================================================= 6. overview
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d5002","role":"authenticated"}', true);
do $$
declare
  o jsonb := public.get_dms_overview(null, null);
begin
  assert (o #>> '{counts,indexed}')::int = 1 and (o #>> '{steps,ai,done}')::boolean, 'step 4 done ' || (o -> 'steps')::text;
  raise notice 'PASS: the overview counts documents indexed for the assistant';
end $$;

select '==== ALL DMS D5 CHECKS PASSED ====' as result;
rollback;
