-- =============================================================================
-- DMS D1 tests: folders, naming, upload, versions, duplicates, read access, expiry.
--
-- Alpha: departments Human Resources (code HR), Sales (code SAL), Ops (no code).
--   People: Hana (HR Manager, HR), Mona (Manager, Sales), Sam (employee, Sales), Olu (employee, Ops).
--   1. Every company gets the base folders without choosing an ISO; employees cannot open setup.
--   2. Trade licence: code HR-TRD-0001, expiry defaults to 30 June; confirm needs the file; only the
--      uploader may put the file at the reserved path.
--   3. No duplicates: the same file, or the same type + department + title, is refused.
--   4. New version keeps the code, supersedes v1; readers see only the current file.
--   5. A cancelled upload never gives its number back; a department without a code is refused clearly.
--   6. Manager uploads only for Sales; Confidential / Restricted / department-scoped reading; Beta sees nothing.
--   7. Custom folders: a document in a user folder still gets {DEPT}-{TYPE}-{SEQ}; moving keeps code and file;
--      a folder holding documents cannot be switched off.
--   8. ISO 9001 adds its folders; deselecting hides them while empty; overview steps.
--   9. Overview: counts and licences by expiry (expired ones included); download log.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D1 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d1001', 'authenticated', 'authenticated', 'd1platform@olympus.test', now(), '{"full_name":"D1 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d1002', 'authenticated', 'authenticated', 'd1owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d1003', 'authenticated', 'authenticated', 'd1owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d1001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d1002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Documents', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d1003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Documents', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d1001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d1002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d1003'));
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d1002","role":"authenticated"}', true);
do $$
declare
  v_hr uuid; v_sales uuid; v_ops uuid; v_des_h uuid; v_des_s uuid; v_des_o uuid; v_branch uuid; v_office uuid; v_common jsonb;
begin
  insert into public.departments (name, code) values ('Human Resources', 'HR') returning id into v_hr;
  insert into public.departments (name, code) values ('Sales', 'SAL') returning id into v_sales;
  insert into public.departments (name) values ('Ops') returning id into v_ops;
  insert into public.designations (department_id, grade_id, name) values (v_hr, (select id from public.grades where code = 'EM1'), 'HR Officer') returning id into v_des_h;
  insert into public.designations (department_id, grade_id, name) values (v_sales, (select id from public.grades where code = 'EM1'), 'Sales Officer') returning id into v_des_s;
  insert into public.designations (department_id, grade_id, name) values (v_ops, (select id from public.grades where code = 'EM1'), 'Ops Officer') returning id into v_des_o;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.hr', v_hr::text, true);
  perform set_config('t.sales', v_sales::text, true);
  perform set_config('t.ops', v_ops::text, true);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.e_hana', public.create_employee(v_common || jsonb_build_object('full_name', 'Hana HR', 'department_id', v_hr, 'designation_id', v_des_h))::text, true);
  perform set_config('t.e_mona', public.create_employee(v_common || jsonb_build_object('full_name', 'Mona Manager', 'department_id', v_sales, 'designation_id', v_des_s))::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || jsonb_build_object('full_name', 'Sam Sales', 'department_id', v_sales, 'designation_id', v_des_s))::text, true);
  perform set_config('t.e_olu', public.create_employee(v_common || jsonb_build_object('full_name', 'Olu Ops', 'department_id', v_ops, 'designation_id', v_des_o))::text, true);
  perform set_config('t.u_hana', public.grant_portal_access(current_setting('t.e_hana')::uuid, 'hana@alpha.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(current_setting('t.e_mona')::uuid, 'mona@alpha.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_olu', public.grant_portal_access(current_setting('t.e_olu')::uuid, 'olu@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.role_manager', (select id from public.roles where system_key = 'manager')::text, true);
end $$;

-- D1 checks run without review (D2 adds review; its own test covers it).
reset role;
update public.dms_settings set require_review = false where org_id = current_setting('t.org')::uuid;
set local role authenticated;

-- ======================================================= 1. base folders, setup permission
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.get_dms_setup();
  o jsonb := public.get_dms_overview(null, null);
begin
  assert (select count(*) from jsonb_array_elements(v -> 'folders') f where f ->> 'origin' = 'base') = 6, 'six base folders ' || (v -> 'folders')::text;
  assert (select count(*) from jsonb_array_elements(v -> 'folders') f where f ->> 'origin' = 'iso') = 0, 'no ISO folder before choosing';
  assert jsonb_array_length(v -> 'catalog') = 8, 'eight standards offered';
  assert not (o #>> '{steps,iso,done}')::boolean and (o #>> '{steps,departments,missing_code}')::int = 1, 'steps ' || o::text;
  perform set_config('t.f_lic', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'LIC'), true);
  perform set_config('t.f_hrp', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'HRP'), true);
  perform set_config('t.f_con', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'CON'), true);
  perform set_config('t.ty_trd', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'TRD'), true);
  perform set_config('t.ty_fir', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'FIR'), true);
  perform set_config('t.ty_pol', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'POL'), true);
  perform set_config('t.ty_sup', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'SUP'), true);
  perform set_config('t.ty_doc', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'DOC'), true);
  assert (select t ->> 'expiry_default' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'TRD') = 'fiscal_year_end',
         'trade licence defaults to 30 June';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    perform public.get_dms_setup();
    raise exception 'FAIL: an employee opened DMS setup';
  exception when insufficient_privilege then null;
  end;
  assert not ((public.get_dms_library() -> 'can' ->> 'upload')::boolean), 'an employee cannot upload';
  assert jsonb_array_length(public.get_dms_library() -> 'folders') = 6, 'the employee sees the library folders';
  raise notice 'PASS: base folders for every company without any ISO; setup is for dms.manage only';
end $$;

-- ======================================================= 2. trade licence: code, 30 June, file
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb;
  v_fy date := case when current_date <= make_date(extract(year from current_date)::int, 6, 30)
                    then make_date(extract(year from current_date)::int, 6, 30)
                    else make_date(extract(year from current_date)::int + 1, 6, 30) end;
begin
  assert public.dms_next_code(current_setting('t.ty_trd')::uuid, current_setting('t.hr')::uuid) = 'HR-TRD-0001', 'next code preview';
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Trade Licence Dhaka', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_trd'), 'department_id', current_setting('t.hr'), 'fields', '{"authority":"DNCC"}'::jsonb,
      'file', jsonb_build_object('name', 'trade licence final2.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 1200,
                                 'hash', encode(sha256('trade-1'::bytea), 'hex'))));
    raise exception 'FAIL: licence without its number accepted';
  exception when invalid_parameter_value then null;
  end;
  v := public.dms_register_upload(jsonb_build_object('title', 'Trade Licence Dhaka', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_trd'), 'department_id', current_setting('t.hr'),
      'fields', '{"licence_no":"TRAD/DNCC/0042","authority":"DNCC","unknown":"dropped"}'::jsonb,
      'file', jsonb_build_object('name', 'trade licence final2.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 1200,
                                 'hash', encode(sha256('trade-1'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'HR-TRD-0001' and v ->> 'version_name' = 'HR-TRD-0001_v1', 'system name ' || v::text;
  assert (v ->> 'expiry_date')::date = v_fy, 'expiry defaults to 30 June ' || v::text;
  assert v ->> 'path' = current_setting('t.org') || '/' || (v ->> 'document_id') || '/v1.pdf', 'storage path holds ids only';
  perform set_config('t.d_trd', v ->> 'document_id', true);
  perform set_config('t.v_trd1', v ->> 'version_id', true);
  perform set_config('t.p_trd1', v ->> 'path', true);
  begin
    perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
    raise exception 'FAIL: confirmed without a file';
  exception when check_violation then null;
  end;
end $$;
-- Sam cannot put a file at Hana's reserved path.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  begin
    insert into storage.objects (bucket_id, name) values ('dms-documents', current_setting('t.p_trd1'));
    raise exception 'FAIL: someone else wrote the reserved path';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
insert into storage.objects (bucket_id, name) values ('dms-documents', current_setting('t.p_trd1'));
do $$
declare
  d jsonb := public.dms_confirm_upload(current_setting('t.v_trd1')::uuid);
begin
  assert d ->> 'lifecycle' = 'published' and (d ->> 'version')::int = 1, 'published ' || d::text;
  assert d -> 'fields' = '{"licence_no":"TRAD/DNCC/0042","authority":"DNCC"}'::jsonb, 'only defined fields kept ' || (d -> 'fields')::text;
  begin
    insert into storage.objects (bucket_id, name) values ('dms-documents', current_setting('t.org') || '/' || current_setting('t.d_trd') || '/v9.pdf');
    raise exception 'FAIL: a file outside a reserved upload was accepted';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: the system names the licence HR-TRD-0001_v1, expiry defaults to 30 June, the file must arrive at its reserved path';
end $$;

-- ======================================================= 3. no duplicates
do $$
begin
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Another name', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_trd'), 'department_id', current_setting('t.hr'),
      'fields', '{"licence_no":"X","authority":"Y"}'::jsonb, 'expiry_date', '2027-06-30',
      'file', jsonb_build_object('name', 'copy.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 1200,
                                 'hash', encode(sha256('trade-1'::bytea), 'hex'))));
    raise exception 'FAIL: the same file was saved twice';
  exception when unique_violation then
    assert sqlerrm like '%HR-TRD-0001 v1%', 'names the existing document: ' || sqlerrm;
  end;
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'trade licence dhaka', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_trd'), 'department_id', current_setting('t.hr'),
      'fields', '{"licence_no":"X","authority":"Y"}'::jsonb,
      'file', jsonb_build_object('name', 'renewal.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 1300,
                                 'hash', encode(sha256('trade-2'::bytea), 'hex'))));
    raise exception 'FAIL: a second document with the same title';
  exception when unique_violation then
    assert sqlerrm like '%HR-TRD-0001%new version%', 'points to the new version: ' || sqlerrm;
  end;
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Disguised', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_trd'), 'department_id', current_setting('t.hr'),
      'fields', '{"licence_no":"X","authority":"Y"}'::jsonb,
      'file', jsonb_build_object('name', 'x.pdf', 'kind', 'pdf', 'mime', 'text/html', 'size_bytes', 10,
                                 'hash', encode(sha256('html'::bytea), 'hex'))));
    raise exception 'FAIL: a file whose type does not match';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: the same file, or the same type + department + title, is refused with the existing code';
end $$;

-- ======================================================= 4. new version (renewal)
do $$
declare
  v jsonb;
  d jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('document_id', current_setting('t.d_trd'), 'expiry_date', '2028-06-30',
      'change_note', 'Renewed for 2027-28',
      'file', jsonb_build_object('name', 'renewal.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 1300,
                                 'hash', encode(sha256('trade-2'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'HR-TRD-0001' and (v ->> 'version')::int = 2, 'same code, v2 ' || v::text;
  perform set_config('t.v_trd2', v ->> 'version_id', true);
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  d := public.dms_confirm_upload((v ->> 'version_id')::uuid);
  assert d ->> 'version_name' = 'HR-TRD-0001_v2' and (d ->> 'expiry_date')::date = '2028-06-30', 'renewal carries the new expiry ' || d::text;
  d := public.get_dms_document(current_setting('t.d_trd')::uuid);
  assert jsonb_array_length(d -> 'versions') = 2 and d #>> '{versions,1,status}' = 'superseded'
         and (d #>> '{versions,1,expiry_date}')::date <> '2028-06-30', 'v1 superseded, its old expiry kept ' || (d -> 'versions')::text;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
declare
  d jsonb := public.get_dms_document(current_setting('t.d_trd')::uuid);
begin
  assert jsonb_array_length(d -> 'versions') = 1 and (d #>> '{versions,0,version}')::int = 2, 'a reader sees only the current file';
  assert (public.dms_file_path(current_setting('t.v_trd2')::uuid)) ->> 'file_name' = 'HR-TRD-0001_v2.pdf', 'download name from the code';
  begin
    perform public.dms_file_path(current_setting('t.v_trd1')::uuid);
    raise exception 'FAIL: a reader opened a superseded file';
  exception when no_data_found then null;
  end;
  assert (select count(*) from storage.objects where bucket_id = 'dms-documents' and name = current_setting('t.p_trd1')) = 0,
         'storage hides the old file from readers';
  raise notice 'PASS: a renewal is v2 of the same code; v1 keeps its own expiry; readers get only the current file';
end $$;

-- ======================================================= 5. numbers are never reused; department without a code
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Leave Policy', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'leave.docx', 'kind', 'docx', 'mime', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                 'size_bytes', 900, 'hash', encode(sha256('leave-a'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'HR-POL-0001', 'first policy ' || v::text;
  perform public.dms_cancel_upload((v ->> 'version_id')::uuid);
  v := public.dms_register_upload(jsonb_build_object('title', 'Leave Policy', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'leave.docx', 'kind', 'docx', 'mime', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                 'size_bytes', 900, 'hash', encode(sha256('leave-a'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'HR-POL-0002', 'a cancelled number is not reused ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_pol', v ->> 'document_id', true);
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Ops safety rules', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.ops'),
      'file', jsonb_build_object('name', 'ops.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 900,
                                 'hash', encode(sha256('ops'::bytea), 'hex'))));
    raise exception 'FAIL: a department without a code was used';
  exception when check_violation then
    assert sqlerrm like '%"Ops" has no short code%', 'explains the missing code: ' || sqlerrm;
  end;
  raise notice 'PASS: a cancelled upload keeps its number used; a department needs a short code first';
end $$;

-- ======================================================= 6. who uploads, who reads
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v jsonb;
begin
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'HR thing', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.hr'),
      'file', jsonb_build_object('name', 'h.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 10,
                                 'hash', encode(sha256('mona-hr'::bytea), 'hex'))));
    raise exception 'FAIL: a manager uploaded for another department';
  exception when insufficient_privilege then null;
  end;
  -- Default department = her own (Sales). Supplier contract: Confidential by default.
  v := public.dms_register_upload(jsonb_build_object('title', 'Fabric supplier contract', 'folder_id', current_setting('t.f_con'),
      'doc_type_id', current_setting('t.ty_sup'), 'fields', '{"party":"Acme Fabrics"}'::jsonb, 'expiry_date', '2027-12-31',
      'file', jsonb_build_object('name', 'acme.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 500,
                                 'hash', encode(sha256('acme'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'SAL-SUP-0001', 'manager code ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  assert (public.dms_confirm_upload((v ->> 'version_id')::uuid)) ->> 'classification' = 'confidential', 'contracts are confidential';
  perform set_config('t.d_sup', v ->> 'document_id', true);
  -- Restricted to the Manager role; Sales-only policy.
  v := public.dms_register_upload(jsonb_build_object('title', 'Sales bonus rules', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'classification', 'restricted', 'restricted_role_ids', jsonb_build_array(current_setting('t.role_manager')),
      'file', jsonb_build_object('name', 'bonus.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 500,
                                 'hash', encode(sha256('bonus'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_bonus', v ->> 'document_id', true);
  v := public.dms_register_upload(jsonb_build_object('title', 'Sales dress code', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'scope', 'departments', 'scope_department_ids', jsonb_build_array(current_setting('t.sales')),
      'file', jsonb_build_object('name', 'dress.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 500,
                                 'hash', encode(sha256('dress'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_dress', v ->> 'document_id', true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v_ids text[] := array(select x ->> 'id' from jsonb_array_elements(public.list_dms_documents('{}')) x);
begin
  assert current_setting('t.d_dress') = any (v_ids), 'Sam (Sales) reads the Sales-only policy';
  assert not (current_setting('t.d_sup') = any (v_ids)), 'Sam cannot read a Confidential contract';
  assert not (current_setting('t.d_bonus') = any (v_ids)), 'Sam cannot read a document restricted to managers';
  assert current_setting('t.d_trd') = any (v_ids) and current_setting('t.d_pol') = any (v_ids), 'company-wide documents are readable';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
declare
  v_ids text[] := array(select x ->> 'id' from jsonb_array_elements(public.list_dms_documents('{}')) x);
begin
  assert not (current_setting('t.d_dress') = any (v_ids)), 'Olu (Ops) does not read the Sales-only policy';
  begin
    perform public.get_dms_document(current_setting('t.d_sup')::uuid);
    raise exception 'FAIL: Olu opened a Confidential contract';
  exception when no_data_found then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d1003","role":"authenticated"}', true);
do $$
begin
  assert jsonb_array_length(public.list_dms_documents('{}')) = 0, 'Beta sees no Alpha document';
  begin
    perform public.get_dms_document(current_setting('t.d_trd')::uuid);
    raise exception 'FAIL: Beta opened an Alpha document';
  exception when no_data_found then null;
  end;
  begin
    perform public.dms_register_upload(jsonb_build_object('document_id', current_setting('t.d_trd'),
      'file', jsonb_build_object('name', 'x.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 10,
                                 'hash', encode(sha256('beta'::bytea), 'hex'))));
    raise exception 'FAIL: Beta added a version to an Alpha document';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: managers upload for their department; Confidential, Restricted and department scope hold; other companies see nothing';
end $$;

-- ======================================================= 7. custom folders keep the naming rule
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v_folder uuid;
  v_sub    uuid;
  v        jsonb;
  d        jsonb;
begin
  v_folder := public.save_dms_folder(null, '{"name":"Sales Team Files"}');
  v_sub := public.save_dms_folder(null, jsonb_build_object('name', 'Price lists', 'parent_id', v_folder));
  perform set_config('t.f_team', v_folder::text, true);
  begin
    perform public.save_dms_folder(null, '{"name":"sales team files"}');
    raise exception 'FAIL: two folders with the same name side by side';
  exception when unique_violation then null;
  end;
  v := public.dms_register_upload(jsonb_build_object('title', 'Price list 2027', 'folder_id', v_sub, 'doc_type_id', current_setting('t.ty_doc'),
      'file', jsonb_build_object('name', 'PRICES FINAL (3).xlsx', 'kind', 'xlsx',
                                 'mime', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'size_bytes', 700,
                                 'hash', encode(sha256('prices'::bytea), 'hex'))));
  assert v ->> 'doc_code' = 'SAL-DOC-0001', 'a user folder still gives a standard code ' || v::text;
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  d := public.update_dms_document((v ->> 'document_id')::uuid, jsonb_build_object('folder_id', v_folder));
  assert d ->> 'doc_code' = 'SAL-DOC-0001' and d ->> 'folder_id' = v_folder::text, 'moving keeps the code ' || d::text;
  assert (public.dms_file_path((public.get_dms_document((v ->> 'document_id')::uuid) #>> '{versions,0,id}')::uuid)) ->> 'path'
         = v ->> 'path', 'moving never moves the file';
  assert jsonb_array_length(public.list_dms_documents(jsonb_build_object('folder_id', v_folder))) = 1, 'listed in its folder';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  begin
    perform public.save_dms_folder(current_setting('t.f_team')::uuid, '{"enabled":false}');
    raise exception 'FAIL: switched off a folder with documents';
  exception when check_violation then null;
  end;
  perform public.save_dms_folder(current_setting('t.f_lic')::uuid, '{"name":"Licences"}');
  assert (select f ->> 'name' from jsonb_array_elements(public.get_dms_setup() -> 'folders') f where f ->> 'catalog_code' = 'LIC') = 'Licences',
         'built-in folders can be renamed';
  perform public.save_dms_folder((select f ->> 'id' from jsonb_array_elements(public.get_dms_setup() -> 'folders') f
                                  where f ->> 'catalog_code' = 'BUY')::uuid, '{"enabled":false}');
  assert (select count(*) from jsonb_array_elements(public.get_dms_library() -> 'folders') f where f ->> 'catalog_code' = 'BUY') = 0,
         'a switched-off base folder is hidden';
  raise notice 'PASS: users make folders; any folder gives a standard code; moving keeps code and file; folders with documents stay open';
end $$;

-- ======================================================= 8. ISO folders are optional
do $$
declare
  v jsonb;
begin
  perform public.set_dms_profiles(array['ISO_9001'], false);
  v := public.get_dms_setup();
  assert (select count(*) from jsonb_array_elements(v -> 'folders') f where f ->> 'origin' = 'iso' and (f ->> 'enabled')::boolean) = 2,
         'ISO 9001 adds two folders';
  assert (public.get_dms_overview(null, null) #>> '{steps,iso,done}')::boolean, 'step 1 done';
  perform public.set_dms_profiles(array[]::text[], true);
  v := public.get_dms_setup();
  assert (select count(*) from jsonb_array_elements(v -> 'folders') f where f ->> 'origin' = 'iso' and (f ->> 'enabled')::boolean) = 0,
         'deselecting hides the empty ISO folders';
  assert (public.get_dms_overview(null, null) #>> '{steps,iso,done}')::boolean, '"no ISO" also completes step 1';
  begin
    perform public.save_dms_doc_type((select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'TRD')::uuid, '{"code":"TRL"}');
    raise exception 'FAIL: a type code changed';
  exception when check_violation then null;
  end;
  raise notice 'PASS: ISO folders come and go with the selection; type codes never change';
end $$;

-- ======================================================= 9. overview: licences by expiry
do $$
declare
  v jsonb;
begin
  v := public.dms_register_upload(jsonb_build_object('title', 'Fire Licence HQ', 'folder_id', current_setting('t.f_lic'),
      'doc_type_id', current_setting('t.ty_fir'), 'department_id', current_setting('t.hr'),
      'fields', '{"licence_no":"FS-11","authority":"Fire Service"}'::jsonb, 'expiry_date', (current_date + 16)::text,
      'file', jsonb_build_object('name', 'fire.jpg', 'kind', 'jpg', 'mime', 'image/jpeg', 'size_bytes', 400,
                                 'hash', encode(sha256('fire'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_fire', v ->> 'document_id', true);
end $$;
reset role;
update public.dms_documents set expiry_date = current_date - 12 where id = current_setting('t.d_trd')::uuid;
set local role authenticated;
do $$
declare
  o jsonb := public.get_dms_overview(current_date, current_date + 60);
begin
  assert (o #>> '{counts,expiring_60}')::int = 1 and (o #>> '{counts,expired}')::int = 1, 'counts ' || (o -> 'counts')::text;
  assert jsonb_array_length(o -> 'expiring') = 2, 'expired + due in range ' || (o -> 'expiring')::text;
  assert o #>> '{expiring,0,expiry_status}' = 'expired' and o #>> '{expiring,1,expiry_status}' = 'due'
         and (o #>> '{expiring,1,days_left}')::int = 16, 'status and days left ' || (o -> 'expiring')::text;
  assert (o #>> '{steps,documents,done}')::boolean, 'step 3 done';
  assert jsonb_array_length(public.list_dms_documents('{"expiry":"due"}')) = 1, 'filter by expiry status';
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.dms_access_log where document_id = current_setting('t.d_trd')::uuid) = 1, 'one download logged';
  assert (select count(*) from public.audit_logs where action = 'dms.version_published' and entity_id = current_setting('t.d_trd')::uuid) = 1,
         'the new version is audited';
  raise notice 'PASS: overview counts and lists licences by expiry (expired included, days left); downloads and versions are logged';
end $$;

select '==== ALL DMS D1 CHECKS PASSED ====' as result;
rollback;
