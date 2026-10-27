-- =============================================================================
-- DMS D6 tests: audit log, downloads, access review.
--
-- Alpha: Owner (Admin) uploads a policy, Eva (employee) downloads it.
--   1. The audit lists the publication and Eva's download; filters by kind and code work.
--   2. Employees cannot read the audit; an auditor (dms.audit) can but cannot sign the access review.
--   3. The access review lists who holds DMS rights; signing keeps a snapshot and clears "due".
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL DMS D6 CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000d6001', 'authenticated', 'authenticated', 'd6platform@olympus.test', now(), '{"full_name":"D6 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000d6002', 'authenticated', 'authenticated', 'd6owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000d6001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Audit', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000d6002'))::text, true);
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6002","role":"authenticated"}', true);
do $$
declare
  v_hr uuid; v_des uuid; v_branch uuid; v_office uuid; v jsonb;
begin
  insert into public.departments (name, code) values ('Human Resources', 'HR') returning id into v_hr;
  insert into public.designations (department_id, grade_id, name) values (v_hr, (select id from public.grades where code = 'EM1'), 'HR Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.u_eva', public.grant_portal_access(public.create_employee(jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent',
      'branch_id', v_branch, 'office_id', v_office, 'full_name', 'Eva Employee', 'department_id', v_hr, 'designation_id', v_des)),
      'eva@alpha.test', null, 'Passw0rd1', null)::text, true);
  v := public.get_dms_setup();
  v := public.dms_register_upload(jsonb_build_object('title', 'Travel policy',
      'folder_id', (select f ->> 'id' from jsonb_array_elements(v -> 'folders') f where f ->> 'catalog_code' = 'HRP'),
      'doc_type_id', (select t ->> 'id' from jsonb_array_elements(v -> 'types') t where t ->> 'code' = 'POL'), 'department_id', v_hr,
      'file', jsonb_build_object('name', 'travel.pdf', 'kind', 'pdf', 'mime', 'application/pdf', 'size_bytes', 100, 'hash', encode(sha256('travel6'::bytea), 'hex'))));
  insert into storage.objects (bucket_id, name) values ('dms-documents', v ->> 'path');
  perform public.dms_confirm_upload((v ->> 'version_id')::uuid);
  perform set_config('t.d_travel', v ->> 'document_id', true);
  perform set_config('t.v_travel', v ->> 'version_id', true);
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_eva')), true);
select public.dms_file_path(current_setting('t.v_travel')::uuid);

-- ======================================================= 1. the audit
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6002","role":"authenticated"}', true);
do $$
declare
  a jsonb := public.list_dms_audit(jsonb_build_object('document_id', current_setting('t.d_travel')));
begin
  assert (select count(*) from jsonb_array_elements(a) x where x ->> 'action' = 'dms.published_without_review') = 1, 'publication listed ' || a::text;
  assert (select count(*) from jsonb_array_elements(a) x where x ->> 'action' = 'dms.download' and x ->> 'by' = 'Eva Employee') = 1, 'download listed';
  assert (select bool_and(x ->> 'kind' = 'download') from jsonb_array_elements(public.list_dms_audit('{"kind":"downloads"}')) x), 'kind filter';
  assert jsonb_array_length(public.list_dms_audit('{"q":"HR-POL-0001"}')) > 0 and jsonb_array_length(public.list_dms_audit('{"q":"XX-NONE"}')) = 0, 'code filter';
  raise notice 'PASS: changes, approvals and downloads are in one audit list with filters';
end $$;

-- ======================================================= 2. who may read it
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_eva')), true);
do $$
begin
  begin
    perform public.list_dms_audit('{}');
    raise exception 'FAIL: an employee read the audit';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6002","role":"authenticated"}', true);
select public.set_role_permissions((select id from public.roles where system_key = 'employee' and org_id = current_setting('t.org')::uuid),
  array(select rp.permission_key from public.role_permissions rp join public.roles r on r.id = rp.role_id
        where r.system_key = 'employee' and r.org_id = current_setting('t.org')::uuid) || array['dms.audit']);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_eva')), true);
do $$
begin
  assert jsonb_array_length(public.list_dms_audit('{}')) > 0, 'the auditor reads the audit';
  assert (public.get_dms_access_review() ->> 'can_sign')::boolean = false, 'but cannot sign';
  begin
    perform public.sign_dms_access_review('ok');
    raise exception 'FAIL: the auditor signed';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: the audit is for document managers and auditors; auditors only read';
end $$;

-- ======================================================= 3. access review
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000d6002","role":"authenticated"}', true);
do $$
declare
  r jsonb := public.get_dms_access_review();
begin
  assert (r ->> 'due')::boolean, 'due before the first review';
  assert (select count(*) from jsonb_array_elements(r #> '{current,roles}') x where x ->> 'system_key' = 'hr_manager' and x -> 'rights' ? 'dms.manage') = 1,
         'HR Manager holds dms.manage ' || (r -> 'current')::text;
  assert (select x -> 'people' ? 'Eva Employee' from jsonb_array_elements(r #> '{current,roles}') x where x ->> 'system_key' = 'employee'), 'people listed';
  perform public.sign_dms_access_review('Q4 2026 review: rights correct');
  r := public.get_dms_access_review();
  assert not (r ->> 'due')::boolean and jsonb_array_length(r -> 'history') = 1 and r #>> '{history,0,note}' like 'Q4 2026%', 'signed and kept';
  raise notice 'PASS: the access review shows every DMS right and keeps signed snapshots';
end $$;

select '==== ALL DMS D6 CHECKS PASSED ====' as result;
rollback;
