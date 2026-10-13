-- =============================================================================
-- Step 1 acceptance checks: company isolation, roles, audit, sign-up flow.
--
-- Run the whole file in the Supabase SQL editor (runs as `postgres`), or:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/step1_foundation_test.sql
-- Everything happens inside one transaction and is rolled back at the end.
-- Any failure aborts with the failing check's message.
-- =============================================================================
begin;

-- ---------------------------------------------------------------- fixtures --
-- P = platform admin, A = applicant/admin of Alpha, B = admin of Beta,
-- E = employee in Alpha, C = applicant with no organization.
insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'platform@olympus.test', '{"full_name":"Platform Admin"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'admin@alpha.test',     '{"full_name":"Alpha Admin"}',    now(), now()),
  ('00000000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'admin@beta.test',      '{"full_name":"Beta Admin"}',     now(), now()),
  ('00000000-0000-0000-0000-0000000000a4', 'authenticated', 'authenticated', 'emp@alpha.test',       '{"full_name":"Alpha Employee"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000a5', 'authenticated', 'authenticated', 'applicant@gamma.test', '{"full_name":"Gamma Applicant"}',now(), now());

insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000a1');

-- A and B apply for organizations.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Ltd', 'Alpha Admin', '01711000001');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Ltd', 'Beta Admin', null);

-- Platform admin approves both.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
do $$
declare
  v_a uuid; v_b uuid;
begin
  select public.approve_org_signup_request(id) into v_a from public.org_signup_requests
   where applicant_user_id = '00000000-0000-0000-0000-0000000000a2';
  select public.approve_org_signup_request(id) into v_b from public.org_signup_requests
   where applicant_user_id = '00000000-0000-0000-0000-0000000000a3';
  perform set_config('test.org_a', v_a::text, true);
  perform set_config('test.org_b', v_b::text, true);
  raise notice 'PASS signup: platform admin approved two organizations';
end $$;
reset role;

-- E joins Alpha as Employee (portal-access RPC arrives in Step 7).
insert into public.org_members (org_id, user_id, role_id)
select current_setting('test.org_a')::uuid, '00000000-0000-0000-0000-0000000000a4', id
from public.roles where org_id = current_setting('test.org_a')::uuid and system_key = 'employee';

do $$
begin
  perform set_config('test.b_emp_role',
    (select id::text from public.roles where org_id = current_setting('test.org_b')::uuid and system_key = 'employee'), true);
  perform set_config('test.a_emp_role',
    (select id::text from public.roles where org_id = current_setting('test.org_a')::uuid and system_key = 'employee'), true);
  perform set_config('test.a_hr_role',
    (select id::text from public.roles where org_id = current_setting('test.org_a')::uuid and system_key = 'hr_manager'), true);
  perform set_config('test.a_admin_role',
    (select id::text from public.roles where org_id = current_setting('test.org_a')::uuid and system_key = 'admin'), true);
end $$;

-- ------------------------------------------------------------ as postgres --
do $$
declare
  v_a text; v_b text;
begin
  select org_code into v_a from public.organizations where id = current_setting('test.org_a')::uuid;
  select org_code into v_b from public.organizations where id = current_setting('test.org_b')::uuid;
  assert v_a ~ '^[0-9]{6}$' and v_b ~ '^[0-9]{6}$', 'org codes must be 6 digits';
  assert v_a <> v_b, 'org codes must be unique';
  assert (select count(*) from public.roles where org_id = current_setting('test.org_a')::uuid) = 4,
    'new org must get 4 default roles';
  raise notice 'PASS org: 6-digit unique codes and default roles';

  begin
    update public.organizations set org_code = '123456' where id = current_setting('test.org_a')::uuid;
    raise exception 'FAIL: org code was changed';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS org: code is immutable';

  begin
    delete from public.organizations where id = current_setting('test.org_a')::uuid;
    raise exception 'FAIL: organization was physically deleted';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS soft delete: organizations cannot be deleted';

  begin
    update public.audit_logs set action = 'tampered';
    raise exception 'FAIL: audit row updated by postgres';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.audit_logs;
    raise exception 'FAIL: audit row deleted by postgres';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS audit: append-only even for the database owner';

  -- Same number in two formats must not create two identities.
  insert into auth.users (id, aud, role, phone, created_at, updated_at)
  values ('00000000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated', '01712345678', now(), now());
  begin
    insert into auth.users (id, aud, role, phone, created_at, updated_at)
    values ('00000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated', '+8801712345678', now(), now());
    raise exception 'FAIL: duplicate phone accepted';
  exception when unique_violation then null;
  end;
  assert (select phone from public.user_profiles where id = '00000000-0000-0000-0000-0000000000b1') = '+8801712345678',
    'phone must be stored as +880...';
  raise notice 'PASS identity: phone normalized and unique across formats';
end $$;

-- ------------------------------------------------------- as Alpha admin A --
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
do $$
declare
  v_rows int;
begin
  assert (select count(*) from public.organizations) = 1, 'A must see exactly one organization';
  assert (select id from public.organizations) = current_setting('test.org_a')::uuid, 'A must see only Alpha';
  assert (select count(*) from public.roles where org_id = current_setting('test.org_b')::uuid) = 0, 'A must not see Beta roles';
  assert (select count(*) from public.org_members where org_id = current_setting('test.org_b')::uuid) = 0, 'A must not see Beta members';
  assert not exists (select 1 from public.user_profiles where id = '00000000-0000-0000-0000-0000000000a3'), 'A must not see Beta admin profile';
  assert (select count(*) from public.audit_logs) > 0, 'A must see Alpha audit rows';
  assert not exists (select 1 from public.audit_logs where org_id is distinct from current_setting('test.org_a')::uuid),
    'A must see only Alpha audit rows';
  raise notice 'PASS isolation: Alpha admin reads only Alpha data';

  update public.organizations set name = 'Hacked' where id = current_setting('test.org_b')::uuid;
  get diagnostics v_rows = row_count;
  assert v_rows = 0, 'A must not update Beta';

  begin
    insert into public.role_permissions (role_id, permission_key)
    values (current_setting('test.b_emp_role')::uuid, 'org.view');
    raise exception 'FAIL: A granted a permission on a Beta role';
  exception when foreign_key_violation then null;
  end;

  begin
    update public.org_members set role_id = current_setting('test.b_emp_role')::uuid
     where user_id = '00000000-0000-0000-0000-0000000000a4';
    raise exception 'FAIL: A assigned a Beta role';
  exception when foreign_key_violation then null;
  end;
  raise notice 'PASS isolation: Alpha admin cannot write Beta data or link to it';

  begin
    update public.audit_logs set action = 'tampered';
    raise exception 'FAIL: admin updated audit';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS audit: admin cannot edit audit rows';

  begin
    update public.org_members set role_id = current_setting('test.a_emp_role')::uuid
     where user_id = '00000000-0000-0000-0000-0000000000a2';
    raise exception 'FAIL: admin removed own admin access';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS roles: admin cannot remove own admin access';

  begin
    insert into public.role_permissions (role_id, permission_key)
    values (current_setting('test.a_admin_role')::uuid, 'org.view');
    raise exception 'FAIL: admin role permissions changed';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.role_permissions (role_id, permission_key)
    values (current_setting('test.a_hr_role')::uuid, 'audit.view');
    raise exception 'FAIL: admin-only permission granted to HR';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS roles: admin role is fixed; admin-only permissions stay with Admin';

  insert into public.roles (name, description) values ('Supervisor', 'Custom role');
  assert exists (select 1 from public.roles where name = 'Supervisor' and org_id = current_setting('test.org_a')::uuid),
    'custom role must land in Alpha';
  raise notice 'PASS roles: admin can create a custom role in own org';

  begin
    perform public.approve_org_signup_request(gen_random_uuid());
    raise exception 'FAIL: org admin used platform approval';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS signup: only platform admins approve';
end $$;

-- ---------------------------------------------------- as Alpha employee E --
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
do $$
declare
  v_ctx jsonb := public.get_my_context();
begin
  assert (select count(*) from public.org_members) = 1, 'employee must see only own membership';
  assert (select count(*) from public.roles) = 1, 'employee must see only own role';
  assert (select count(*) from public.audit_logs) = 0, 'employee must not read audit';
  assert (select count(*) from public.user_profiles) = 1, 'employee must see only own profile';
  assert v_ctx -> 'permissions' = '["attendance.view_own", "leave.request"]'::jsonb,
    'employee has only own-attendance and leave-request permissions';
  assert (v_ctx -> 'organization' ->> 'id')::uuid = current_setting('test.org_a')::uuid, 'context org must be Alpha';

  begin
    insert into public.roles (name) values ('Sneaky');
    raise exception 'FAIL: employee created a role';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.org_members set role_id = current_setting('test.a_admin_role')::uuid
     where user_id = '00000000-0000-0000-0000-0000000000a4';
    -- RLS hides the row for update, so nothing changes.
  end;
  raise notice 'PASS roles: employee cannot create roles or promote self';
end $$;

reset role;
do $$
begin
  assert (select r.system_key from public.org_members m join public.roles r on r.id = m.role_id
          where m.user_id = '00000000-0000-0000-0000-0000000000a4') = 'employee',
    'employee must still be Employee';
end $$;

-- ----------------------------- role change takes effect on the next request --
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a2","role":"authenticated"}', true);
update public.org_members set role_id = current_setting('test.a_hr_role')::uuid
 where user_id = '00000000-0000-0000-0000-0000000000a4';

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a4","role":"authenticated"}', true);
do $$
begin
  assert (select count(*) from public.roles) = 5, 'HR (roles.view) must see all Alpha roles';
  assert (select count(*) from public.audit_logs) = 0, 'HR must not read audit';
  begin
    insert into public.roles (name) values ('Sneaky');
    raise exception 'FAIL: HR created a role';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS roles: promotion applies immediately; HR still cannot manage roles';
end $$;

-- ------------------------------------------------------ as Beta admin B --
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a3","role":"authenticated"}', true);
do $$
begin
  assert (select count(*) from public.roles where name = 'Supervisor') = 0, 'B must not see Alpha custom role';
  assert (select count(*) from public.user_profiles) = 1, 'B must see only Beta profiles';
  assert not exists (select 1 from public.audit_logs where org_id = current_setting('test.org_a')::uuid),
    'B must not see Alpha audit rows';
  raise notice 'PASS isolation: Beta admin reads only Beta data';
end $$;

-- ------------------------------------------------- as applicant C (no org) --
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a5","role":"authenticated"}', true);
do $$
begin
  perform public.submit_org_signup_request('Gamma Ltd', 'Gamma Applicant', '01811000005');
  begin
    perform public.submit_org_signup_request('Gamma Again', 'Gamma Applicant', null);
    raise exception 'FAIL: second pending request accepted';
  exception when unique_violation then null;
  end;
  assert (select count(*) from public.organizations) = 0, 'applicant sees no organization';
  assert (public.get_my_context() -> 'pending_signup_request' ->> 'org_name') = 'Gamma Ltd', 'context shows pending request';
  raise notice 'PASS signup: one pending request per applicant';
end $$;

reset role;
do $$ begin raise notice '==== ALL STEP 1 CHECKS PASSED ===='; end $$;
-- Shown in the SQL editor's Results tab (it only displays the last result set).
select '==== ALL STEP 1 CHECKS PASSED ====' as result;
rollback;
