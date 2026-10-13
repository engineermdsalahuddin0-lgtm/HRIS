-- =============================================================================
-- Part 1 acceptance checks for Steps 3-9 (architecture doc, Section 6).
-- Run the whole file in the Supabase SQL editor. One transaction, rolled back.
-- The Results tab must show "ALL STEP 3-9 CHECKS PASSED"; a failure shows an error.
-- =============================================================================
begin;

-- Fixtures: P platform admin, A Alpha admin, B Beta admin.
insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated', 'platform@olympus.test', '{"full_name":"Platform Admin"}', now(), now()),
  ('00000000-0000-0000-0000-0000000000c2', 'authenticated', 'authenticated', 'owner@alpha.test',     '{"full_name":"Alpha Owner"}',    now(), now()),
  ('00000000-0000-0000-0000-0000000000c3', 'authenticated', 'authenticated', 'owner@beta.test',      '{"full_name":"Beta Owner"}',     now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000c1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Garments', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Textiles', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org_a', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000c2'))::text, true);
  perform set_config('t.org_b', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000c3'))::text, true);
end $$;

-- ---------------------------------------------------------------- Alpha admin
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
do $$
declare
  v_em1 uuid; v_em2 uuid; v_ms0 uuid;
  v_prod uuid; v_qual uuid; v_op uuid; v_sup uuid; v_qc uuid;
  v_dhaka uuid; v_gaz uuid; v_hq uuid; v_f1 uuid; v_f2 uuid; v_sew uuid;
begin
  -- Owner got an employee row with an auto card ID; grades were seeded.
  assert (select count(*) from public.employees_v) = 1, 'owner employee row must exist';
  assert (select card_id ~ '^[0-9]{8}$' from public.employees_v), 'owner card id must be 8 digits';
  assert (select count(*) from public.grades) = 10, 'default grades must be seeded';

  select id into v_em1 from public.grades where code = 'EM1';
  select id into v_em2 from public.grades where code = 'EM2';
  select id into v_ms0 from public.grades where code = 'MS0';

  insert into public.departments (name) values ('Production') returning id into v_prod;
  insert into public.departments (name) values ('Quality') returning id into v_qual;
  insert into public.designations (department_id, grade_id, name) values (v_prod, v_em1, 'Operator') returning id into v_op;
  insert into public.designations (department_id, grade_id, name) values (v_prod, v_ms0, 'Supervisor') returning id into v_sup;
  insert into public.designations (department_id, grade_id, name) values (v_qual, v_em2, 'QC Inspector') returning id into v_qc;
  insert into public.branches (name, code) values ('Dhaka', 'DHK') returning id into v_dhaka;
  insert into public.branches (name, code) values ('Gazipur', 'GZP') returning id into v_gaz;
  insert into public.offices (branch_id, name) values (v_dhaka, 'Head Office') returning id into v_hq;
  insert into public.offices (branch_id, name) values (v_gaz, 'Factory 1') returning id into v_f1;
  insert into public.offices (branch_id, name) values (v_gaz, 'Factory 2') returning id into v_f2;
  insert into public.operations (name) values ('Sewing') returning id into v_sew;
  insert into public.office_operations (office_id, operation_id) values (v_f1, v_sew);
  raise notice 'PASS test 4: departments, designations, branches, offices, operations created';

  perform set_config('t.prod', v_prod::text, true);  perform set_config('t.qual', v_qual::text, true);
  perform set_config('t.op', v_op::text, true);      perform set_config('t.sup', v_sup::text, true);
  perform set_config('t.qc', v_qc::text, true);      perform set_config('t.dhaka', v_dhaka::text, true);
  perform set_config('t.gaz', v_gaz::text, true);    perform set_config('t.hq', v_hq::text, true);
  perform set_config('t.f1', v_f1::text, true);      perform set_config('t.f2', v_f2::text, true);
  perform set_config('t.sew', v_sew::text, true);

  -- Designation tied to its department: Operator (Production) under Quality fails.
  begin
    perform public.create_employee(jsonb_build_object(
      'full_name', 'Wrong Pair', 'join_date', '2026-01-10', 'employment_type', 'permanent',
      'department_id', v_qual, 'designation_id', v_op, 'branch_id', v_gaz, 'office_id', v_f1));
    raise exception 'FAIL: designation from another department accepted';
  exception when foreign_key_violation then null;
  end;
  -- Office tied to its branch.
  begin
    perform public.create_employee(jsonb_build_object(
      'full_name', 'Wrong Office', 'join_date', '2026-01-10', 'employment_type', 'permanent',
      'department_id', v_prod, 'designation_id', v_op, 'branch_id', v_dhaka, 'office_id', v_f1));
    raise exception 'FAIL: office from another branch accepted';
  exception when foreign_key_violation then null;
  end;
  raise notice 'PASS test 4: designation tied to department, office tied to branch';

  -- Employees.
  perform set_config('t.e_worker', public.create_employee(jsonb_build_object(
    'full_name', 'Rahim Uddin', 'phone', '01711000001', 'date_of_birth', '1995-05-01', 'gender', 'male',
    'nid_number', '1234567890', 'join_date', '2026-01-10', 'employment_type', 'permanent',
    'department_id', v_prod, 'designation_id', v_op, 'branch_id', v_gaz, 'office_id', v_f1, 'operation_id', v_sew,
    'present_address', 'Gazipur', 'nominees', jsonb_build_array(jsonb_build_object('name', 'Karima', 'relation', 'Mother'))
  ))::text, true);
  perform set_config('t.e_manager', public.create_employee(jsonb_build_object(
    'full_name', 'Selim Hossain', 'join_date', '2025-03-01', 'employment_type', 'permanent', 'date_of_birth', '1985-02-02',
    'department_id', v_prod, 'designation_id', v_sup, 'branch_id', v_gaz, 'office_id', v_f1))::text, true);
  perform set_config('t.e_hr', public.create_employee(jsonb_build_object(
    'full_name', 'Nasrin Akter', 'join_date', '2024-06-01', 'employment_type', 'permanent',
    'department_id', v_qual, 'designation_id', v_qc, 'branch_id', v_dhaka, 'office_id', v_hq))::text, true);

  assert (select count(*) from public.employees_v) = 4, 'four employees expected';
  assert (select count(distinct card_id) from public.employees_v) = 4, 'card ids must be unique';
  raise notice 'PASS test 5: auto card IDs unique inside the organization';

  -- Reporting manager.
  perform public.set_reporting_line(current_setting('t.e_worker')::uuid, 'reporting_manager',
                                    current_setting('t.e_manager')::uuid, '2026-02-01', 'Initial');
end $$;

-- ---------------------------------------------------- card ID custom policy
do $$
begin
  update public.organizations set card_id_mode = 'custom' where id = current_setting('t.org_a')::uuid;
  perform public.create_employee(jsonb_build_object(
    'full_name', 'Custom One', 'card_id', 'ALP-0001', 'join_date', '2026-02-01', 'employment_type', 'contract',
    'department_id', current_setting('t.prod'), 'designation_id', current_setting('t.op'),
    'branch_id', current_setting('t.gaz'), 'office_id', current_setting('t.f2')));
  begin
    perform public.create_employee(jsonb_build_object(
      'full_name', 'Custom Two', 'card_id', 'alp-0001', 'join_date', '2026-02-01', 'employment_type', 'contract',
      'department_id', current_setting('t.prod'), 'designation_id', current_setting('t.op'),
      'branch_id', current_setting('t.gaz'), 'office_id', current_setting('t.f2')));
    raise exception 'FAIL: duplicate custom card id accepted';
  exception when unique_violation then null;
  end;
  update public.organizations set card_id_mode = 'auto' where id = current_setting('t.org_a')::uuid;
  raise notice 'PASS test 5: duplicate custom card ID rejected';
end $$;

-- ------------------------------------------------------------ portal access
do $$
declare
  v_hr_role uuid; v_mgr_role uuid;
begin
  select id into v_hr_role from public.roles where system_key = 'hr_manager';
  select id into v_mgr_role from public.roles where system_key = 'manager';
  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.e_hr')::uuid,
    'nasrin@alpha.test', null, 'FirstPass123', v_hr_role)::text, true);
  perform set_config('t.u_mgr', public.grant_portal_access(current_setting('t.e_manager')::uuid,
    'selim@alpha.test', null, 'FirstPass123', v_mgr_role)::text, true);
  perform set_config('t.u_worker', public.grant_portal_access(current_setting('t.e_worker')::uuid,
    null, '01711000001', 'FirstPass123', null)::text, true);
  raise notice 'PASS test 7: portal access granted (email and phone logins)';
end $$;

reset role;
do $$
begin
  assert (select encrypted_password = extensions.crypt('FirstPass123', encrypted_password)
          from auth.users where id = current_setting('t.u_worker')::uuid), 'password must be bcrypt-hashed and match';
  assert (select phone from auth.users where id = current_setting('t.u_worker')::uuid) = '8801711000001',
    'auth phone stored without +';
  assert (select must_change_password from public.user_profiles where id = current_setting('t.u_worker')::uuid),
    'first login must force a password change';
  assert (select count(*) from auth.identities where user_id = current_setting('t.u_hr')::uuid) = 1, 'identity row expected';
  raise notice 'PASS test 6/7: logins created with hashed password and forced change';
end $$;

-- ------------------------------------------------------------- Beta admin
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}', true);
do $$
declare
  v_rows int;
begin
  assert (select count(*) from public.employees_v) = 1, 'Beta sees only its owner';
  assert (select count(*) from public.departments) = 0, 'Beta sees no Alpha departments';
  begin
    perform public.get_employee_profile(current_setting('t.e_worker')::uuid);
    raise exception 'FAIL: Beta read an Alpha profile';
  exception when no_data_found then null;
  end;
  begin
    perform public.transfer_employee(current_setting('t.e_worker')::uuid,
      jsonb_build_object('office_id', current_setting('t.f2')));
    raise exception 'FAIL: Beta transferred an Alpha employee';
  exception when no_data_found then null;
  end;
  update public.departments set name = 'Hacked' where id = current_setting('t.prod')::uuid;
  get diagnostics v_rows = row_count;
  assert v_rows = 0, 'Beta must not edit Alpha departments';
  begin
    perform public.grant_portal_access(current_setting('t.e_worker')::uuid, 'x@beta.test', null, 'Abcdefg123', null);
    raise exception 'FAIL: Beta granted access to an Alpha employee';
  exception when no_data_found then null;
  end;
  raise notice 'PASS test 1: Beta cannot see, fetch or change Alpha people or structure';
end $$;

-- ----------------------------------------------------------- Alpha manager
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
declare
  v_row public.employees_v;
begin
  assert (select count(*) from public.employees_v) = 5, 'manager sees the whole people list';
  select * into v_row from public.employees_v where id = current_setting('t.e_worker')::uuid;
  assert v_row.phone is not null, 'manager sees phone (ticked)';
  assert v_row.date_of_birth is null, 'manager must not see date of birth';
  assert v_row.nid_number is null, 'manager must not see NID';
  assert v_row.present_address is null, 'manager must not see address';
  assert (public.get_employee_profile(current_setting('t.e_worker')::uuid) -> 'nominees') = 'null'::jsonb,
    'manager must not see nominees';
  assert (select date_of_birth from public.employees_v where is_self) is not null, 'manager sees own date of birth';
  begin
    perform public.update_employee(current_setting('t.e_worker')::uuid, '{"present_address":"x"}');
    raise exception 'FAIL: manager edited another employee';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_employee('{"full_name":"No Way"}');
    raise exception 'FAIL: manager created an employee';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.roles (name) values ('Sneaky');
    raise exception 'FAIL: manager created a role';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 2/3: manager sees the list, sensitive fields hidden, no writes';
end $$;

-- ---------------------------------------------------------- Alpha employee
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_worker')), true);
do $$
begin
  assert (select count(*) from public.employees_v) = 1, 'employee sees only themselves';
  assert (select nid_number from public.employees_v) = '1234567890', 'employee sees own NID';
  perform public.update_employee(current_setting('t.e_worker')::uuid, '{"present_address":"Tongi, Gazipur"}');
  assert (select present_address from public.employees_v) = 'Tongi, Gazipur', 'self edit of address must work';
  begin
    perform public.update_employee(current_setting('t.e_worker')::uuid, '{"join_date":"2020-01-01"}');
    raise exception 'FAIL: employee edited own join date';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.get_employee_profile(current_setting('t.e_manager')::uuid);
    raise exception 'FAIL: employee read another profile';
  exception when no_data_found then null;
  end;
  assert jsonb_array_length(public.get_employee_profile(current_setting('t.e_worker')::uuid) -> 'reporting') = 1,
    'employee sees own reporting chain';
  raise notice 'PASS test 2: employee sees and edits only allowed fields of their own profile';
end $$;

-- -------------------------------------------------------------- Alpha HR
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_event text;
begin
  assert (select nid_number from public.employees_v where id = current_setting('t.e_worker')::uuid) = '1234567890',
    'HR sees NID';

  -- Test 6: a login phone/email already used by someone else is rejected.
  begin
    perform public.grant_portal_access((select id from public.employees_v where card_id = 'ALP-0001'),
                                       null, '+8801711000001', 'Abcdefg123', null);
    raise exception 'FAIL: duplicate phone accepted';
  exception when unique_violation then null;
  end;
  begin
    perform public.grant_portal_access((select id from public.employees_v where card_id = 'ALP-0001'),
                                       'NASRIN@alpha.test', null, 'Abcdefg123', null);
    raise exception 'FAIL: duplicate email accepted';
  exception when unique_violation then null;
  end;
  raise notice 'PASS test 6: duplicate phone or email rejected';

  -- Promotion: Operator (EM1) -> Supervisor (MS0).
  v_event := public.transfer_employee(current_setting('t.e_worker')::uuid,
    jsonb_build_object('designation_id', current_setting('t.sup'), 'effective_date', '2026-03-01', 'reason', 'Good work'));
  assert v_event = 'promotion', 'grade increase must be a promotion, got ' || v_event;
  -- Transfer to Factory 2 (Sewing does not run there, so it is cleared).
  v_event := public.transfer_employee(current_setting('t.e_worker')::uuid,
    jsonb_build_object('office_id', current_setting('t.f2'), 'operation_id', null));
  assert v_event = 'transfer', 'office change must be a transfer';
  raise notice 'PASS: transfer and promotion recorded with event types';

  -- Test 10: changing the manager keeps the old line.
  perform public.set_reporting_line(current_setting('t.e_worker')::uuid, 'reporting_manager',
                                    current_setting('t.e_hr')::uuid, '2026-04-01', 'Moved team');
  begin
    perform public.set_reporting_line(current_setting('t.e_hr')::uuid, 'reporting_manager',
                                      current_setting('t.e_worker')::uuid, null, null);
    raise exception 'FAIL: reporting loop accepted';
  exception when check_violation then null;
  end;

  -- HR cannot give a non-Employee role or manage roles.
  begin
    perform public.change_portal_role(current_setting('t.e_worker')::uuid,
      (select id from public.roles where system_key = 'hr_manager'));
    raise exception 'FAIL: HR assigned a role';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_role_permissions((select id from public.roles where system_key = 'manager'), array['org.view']);
    raise exception 'FAIL: HR changed role permissions';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 12: HR cannot create, change or assign roles';

  -- Test 8: inactive department cannot receive a new employee.
  insert into public.departments (name) values ('Closed Dept');
  perform public.deactivate_department((select id from public.departments where name = 'Closed Dept'), 'test');
  begin
    update public.departments set status = 'inactive' where id = current_setting('t.prod')::uuid;
    raise exception 'FAIL: department deactivated directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.deactivate_department(current_setting('t.prod')::uuid, 'test');
    raise exception 'FAIL: department with employees deactivated';
  exception when check_violation then null;
  end;
  raise notice 'PASS test 8: departments with people cannot be closed; closing needs the flow';

  -- Test 9: deactivate Gazipur, move everyone to Dhaka / Head Office.
  assert public.deactivate_branch(current_setting('t.gaz')::uuid, current_setting('t.dhaka')::uuid,
                                  current_setting('t.hq')::uuid, 'Factory closed') = 3,
    'three active employees must move';
  assert not exists (select 1 from public.employees_v where branch_id = current_setting('t.gaz')::uuid and status = 'active'),
    'nobody active stays in Gazipur';
  assert (select status from public.offices where id = current_setting('t.f1')::uuid) = 'inactive', 'offices close with the branch';
  begin
    perform public.create_employee(jsonb_build_object(
      'full_name', 'Late Joiner', 'join_date', '2026-05-01', 'employment_type', 'permanent',
      'department_id', current_setting('t.prod'), 'designation_id', current_setting('t.op'),
      'branch_id', current_setting('t.gaz'), 'office_id', current_setting('t.f1')));
    raise exception 'FAIL: inactive branch received an employee';
  exception when check_violation then null;
  end;
  raise notice 'PASS test 8/9: branch deactivated with transfer; inactive branch cannot receive people';

  -- Test 7: revoke stops access immediately.
  perform public.revoke_portal_access(current_setting('t.e_manager')::uuid, 'Test');
  raise notice 'PASS test 7: portal access revoked';
end $$;

-- The revoked manager now sees nothing.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  assert (select count(*) from public.employees_v) = 0, 'revoked user must see no employees';
  assert (public.get_my_context() -> 'organization') = 'null'::jsonb, 'revoked user has no organization';
  raise notice 'PASS test 7: revoked login loses access on the next request';
end $$;

reset role;
do $$
declare
  v_worker uuid := current_setting('t.e_worker')::uuid;
begin
  assert (select banned_until > now() from auth.users where id = current_setting('t.u_mgr')::uuid), 'revoked user is banned';
  assert (select count(*) from public.reporting_lines where employee_id = v_worker and line_type = 'reporting_manager') = 2,
    'old reporting line kept';
  assert (select count(*) from public.reporting_lines where employee_id = v_worker and end_date is null) = 1,
    'exactly one current line';
  assert (select count(*) from public.employment_history where employee_id = v_worker and event_type = 'branch') = 1,
    'branch move written to history';
  assert exists (select 1 from public.audit_logs where action = 'branch.deactivated'), 'branch deactivation audited';
  assert not exists (select 1 from public.audit_logs where entity = 'employee_sensitive'
                     and (new_value ->> 'nid_number') = '1234567890'), 'NID must be masked in the audit log';
  begin
    update public.employment_history set reason = 'x' where employee_id = v_worker;
    raise exception 'FAIL: history edited';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 9/10/11: history kept, audit written, NID masked, history append-only';
end $$;

-- ---------------------------------------------------- Alpha admin: roles
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
do $$
declare
  v_mgr_role uuid := (select id from public.roles where system_key = 'manager');
begin
  perform public.set_role_field_access(v_mgr_role, '[{"resource":"employee_sensitive","field_key":"nid_number","can_view":true}]');
  begin
    perform public.change_portal_role(
      (select id from public.employees_v where is_self), v_mgr_role);
    raise exception 'FAIL: admin removed own admin access';
  exception when insufficient_privilege then null;
  end;
  assert (select jsonb_array_length(public.list_audit_logs() -> 'rows')) > 0, 'admin reads the audit log';
  assert (public.get_dashboard_stats() -> 'kpis' ->> 'active')::int = 5, 'dashboard counts active employees';
  raise notice 'PASS test 12: admin edits field access, cannot drop own admin; audit + dashboard readable';
end $$;

-- Manager role now ticked for NID: give the manager access back and check.
do $$
begin
  perform public.grant_portal_access(current_setting('t.e_manager')::uuid, 'selim@alpha.test', null, 'SecondPass123',
                                     (select id from public.roles where system_key = 'manager'));
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mgr')), true);
do $$
begin
  assert (select nid_number from public.employees_v where id = current_setting('t.e_worker')::uuid) = '1234567890',
    'manager sees NID once the Admin ticks it';
  begin
    perform public.list_audit_logs();
    raise exception 'FAIL: manager read the audit log';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 3: sensitive field visible only after the Admin ticks it';
end $$;

reset role;
do $$ begin raise notice '==== ALL STEP 3-9 CHECKS PASSED ===='; end $$;
select '==== ALL STEP 3-9 CHECKS PASSED ====' as result;
rollback;
