-- =============================================================================
-- DMS D4 tests: retention rules, legal hold, two-person disposal.
--
-- Alpha: Owner (Admin) and Hana (HR Manager, given dms.records). An internal audit report published
-- eight years ago.
--   1. Without a retention rule nothing can be disposed; with "7 years after publishing, dispose" it is due.
--   2. A legal hold blocks the disposal request until it is released.
--   3. Two people: Hana requests, Hana cannot approve, the Admin approves; the files may now be deleted.
--   4. The disposal closes only when the files are gone; a tombstone and the proof (hashes) stay.
--   5. Employees cannot see the records area.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D4 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d4001', 'authenticated', 'authenticated', 'd4platform@olympus.test', now(), '{"full_name":"D4 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d4002', 'authenticated', 'authenticated', 'd4owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d4001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d4002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Records', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d4001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d4002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d4002","role":"authenticated"}', true);
do $$
declare
  v_qa uuid; v_des uuid; v_branch uuid; v_office uuid; v jsonb; v_common jsonb;
begin
  insert into public.departments (name, code) values ('Quality', 'QA') returning id into v_qa;
  insert into public.designations (department_id, grade_id, name) values (v_qa, (select id from public.grades where code = 'EM1'), 'QA Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.qa', v_qa::text, true);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office,
                                 'department_id', v_qa, 'designation_id', v_des);
  perform set_config('t.u_hana', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Hana HR"}'),
      'hana@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_emp', public.grant_portal_access(public.create_employee(v_common || '{"full_name":"Eva Employee"}'),
      'eva@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform public.set_role_permissions((select id from public.roles where system_key = 'hr_manager'),
    array(select rp.permission_key from public.role_permissions rp join public.roles r on r.id = rp.role_id where r.system_key = 'hr_manager'
          and r.org_id = current_setting('t.org')::uuid) || array['dms.records']);
  v := public.get_dms_setup();
  perform set_config('t.ty_iar', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'IAR'), true);
  v := public.dms_register_upload(jsonb_build_object('title', 'Internal audit 2018',
      'folder_id', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'REC'),
      'doc_type_id', current_setting('t.ty_iar'), 'department_id', v_qa,
      'file', jsonb_build_object('name', 'audit.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('audit2018'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_audit', v ->> 'document_id', true);
  perform set_config('t.p_audit', v ->> 'path', true);
end $$;
reset role;
update public.dms_versions set published_at = now() - interval '8 years' where document_id = current_setting('t.d_audit')::uuid;
set local role authenticated;

-- ======================================================= 1. rules
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  begin
    perform public.request_dms_disposal(current_setting('t.d_audit')::uuid, 'Too old');
    raise exception 'FAIL: disposed without a rule';
  exception when check_violation then null;
  end;
  perform public.save_dms_retention_rule(current_setting('t.ty_iar')::uuid, '{"start_event":"published","retain_years":7,"action":"dispose","note":"Company policy QA-7"}');
  assert (select count(*) from jsonb_array_elements(public.get_dms_records() -> 'due') x where x ->> 'id' = current_setting('t.d_audit')) = 1,
         'due after seven years';
  raise notice 'PASS: nothing is disposed without a rule; the rule makes old documents due';
end $$;

-- ======================================================= 2. legal hold
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d4002","role":"authenticated"}', true);
select set_config('t.hold', public.place_dms_hold(current_setting('t.d_audit')::uuid, 'Labour court case 12/2026')::text, true);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
begin
  assert (public.get_dms_document(current_setting('t.d_audit')::uuid) ->> 'legal_hold')::boolean, 'shown as on hold';
  begin
    perform public.request_dms_disposal(current_setting('t.d_audit')::uuid, 'Retention ended');
    raise exception 'FAIL: disposal requested during a legal hold';
  exception when check_violation then null;
  end;
  begin
    perform public.release_dms_hold(current_setting('t.hold')::uuid, '');
    raise exception 'FAIL: released without a reason';
  exception when invalid_parameter_value then null;
  end;
  perform public.release_dms_hold(current_setting('t.hold')::uuid, 'Case closed');
  raise notice 'PASS: a legal hold blocks disposal until it is released with a reason';
end $$;

-- ======================================================= 3. two people
do $$
begin
  perform set_config('t.disp', public.request_dms_disposal(current_setting('t.d_audit')::uuid, 'Retention ended (rule QA-7)')::text, true);
  begin
    perform public.approve_dms_disposal(current_setting('t.disp')::uuid);
    raise exception 'FAIL: the requester approved';
  exception when check_violation then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d4002","role":"authenticated"}', true);
do $$
declare
  v jsonb := public.approve_dms_disposal(current_setting('t.disp')::uuid);
begin
  assert v -> 'paths' = jsonb_build_array(current_setting('t.p_audit')), 'the files to remove ' || v::text;
  assert private.dms_file_disposable(current_setting('t.p_audit')), 'storage now lets a records holder delete the file';
  raise notice 'PASS: one person requests, another approves';
end $$;

-- ======================================================= 4. completion and proof
do $$
begin
  begin
    perform public.complete_dms_disposal(current_setting('t.disp')::uuid);
    raise exception 'FAIL: closed while the file is still stored';
  exception when check_violation then null;
  end;
end $$;
-- Stand-in for the Storage API delete (SQL deletes on storage are blocked, as on Supabase).
reset role;
update storage.objects set name = name || '-removed' where bucket_id = 'dms-documents' and name = current_setting('t.p_audit');
set local role authenticated;
do $$
declare
  r jsonb;
begin
  perform public.complete_dms_disposal(current_setting('t.disp')::uuid);
  r := (select x from jsonb_array_elements(public.get_dms_records() -> 'disposals') x where x ->> 'id' = current_setting('t.disp'));
  assert r ->> 'status' = 'done' and jsonb_array_length(r -> 'hashes') = 1 and r ->> 'doc_code' = 'QA-IAR-0001', 'proof kept ' || r::text;
  assert public.get_dms_document(current_setting('t.d_audit')::uuid) ->> 'lifecycle' = 'disposed', 'tombstone';
  assert jsonb_array_length(public.list_dms_documents('{"archived":true}')) = 0, 'gone from the library';
end $$;
reset role;
do $$
begin
  assert (select count(*) from public.audit_logs where action = 'dms.disposed' and entity_id = current_setting('t.d_audit')::uuid) = 1, 'audited';
  raise notice 'PASS: the disposal closes only when the files are gone; the proof stays';
end $$;
set local role authenticated;

-- ======================================================= 5. employees
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_emp')), true);
do $$
begin
  begin
    perform public.get_dms_records();
    raise exception 'FAIL: an employee opened the records area';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: the records area is for dms.records only';
end $$;

select '==== ALL DMS D4 CHECKS PASSED ====' as result;
rollback;
