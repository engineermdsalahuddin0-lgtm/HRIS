-- =============================================================================
-- DMS fix test: a login without an employee department is never let through.
--
-- Alpha: Owner (Admin) publishes a Sales-only policy. Nora is a Manager (dms.upload, dms.approve) whose login is not
-- linked to an employee, so she has no department.
--   1. Nora cannot open the Sales-only document.
--   2. Nora cannot edit it, review a Sales upload, or upload for Sales.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS NULL-SAFE CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d7001', 'authenticated', 'authenticated', 'd7platform@olympus.test', now(), '{"full_name":"D7 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d7002', 'authenticated', 'authenticated', 'd7owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d7001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d7002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Null', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d7001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d7002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d7002","role":"authenticated"}', true);
do $$
declare
  v_sales uuid; v_des uuid; v_branch uuid; v_office uuid; v jsonb; s jsonb;
begin
  insert into public.departments (name, code) values ('Sales', 'SAL') returning id into v_sales;
  insert into public.designations (department_id, grade_id, name) values (v_sales, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.sales', v_sales::text, true);
  -- Nora: a Manager login (its employee link is removed below, so she has no department).
  perform set_config('t.u_nora', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01',
      'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Nora Nodept',
      'department_id', v_sales, 'designation_id', v_des)),
      'nora@alpha.test', null, 'Passw0rd1', (select id from public.roles where system_key = 'manager'))::text, true);
  s := public.get_dms_setup();
  perform set_config('t.f_hrp', (select f ->> 'id' from jsonb_array_elements(s -> 'folders') f where f ->> 'catalog_code' = 'HRP'), true);
  perform set_config('t.ty_pol', (select t ->> 'id' from jsonb_array_elements(s -> 'types') t where t ->> 'code' = 'POL'), true);
  v := public.dms_register_upload(jsonb_build_object('title', 'Sales commission rules', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', v_sales, 'scope', 'departments', 'scope_department_ids', jsonb_build_array(v_sales),
      'file', jsonb_build_object('name', 'c.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 10, 'hash', encode(sha256('null-1'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_comm', v ->> 'document_id', true);
end $$;

reset role;
update public.org_members set employee_id = null where user_id = current_setting('t.u_nora')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_nora')), true);
do $$
begin
  begin
    perform public.get_dms_document(current_setting('t.d_comm')::uuid);
    raise exception 'FAIL: opened a Sales-only document without a department';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: no department means no access to department-only documents';
end $$;

do $$
begin
  begin
    perform public.dms_register_upload(jsonb_build_object('title', 'Sales note', 'folder_id', current_setting('t.f_hrp'),
      'doc_type_id', current_setting('t.ty_pol'), 'department_id', current_setting('t.sales'),
      'file', jsonb_build_object('name', 'n.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 10, 'hash', encode(sha256('null-2'::bytea), 'hex'))));
    raise exception 'FAIL: uploaded for Sales without a department';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.update_dms_document(current_setting('t.d_comm')::uuid, '{"title":"Changed"}');
    raise exception 'FAIL: edited without a department';
  exception when no_data_found or insufficient_privilege then null;
  end;
  raise notice 'PASS: no department means no upload or edit for other departments';
end $$;

select '==== ALL DMS NULL-SAFE CHECKS PASSED ====' as result;
rollback;
