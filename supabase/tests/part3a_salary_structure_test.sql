-- =============================================================================
-- Part 3A acceptance checks: salary structure (Part 3 architecture, Section 6).
-- Every expected amount below was calculated by hand before the code ran.
-- Covers tests 1-2 (isolation, salary confidentiality), 9 (back-dated increment
-- arrears), 10 (bonus minimum service and eligibility), 14 (loan set-up),
-- 16 (line rounding), 17 (maker-checker), 21 (masked account numbers) and the
-- immutability of pay history.
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL PART 3A CHECKS PASSED".
-- =============================================================================
begin;

-- ------------------------------------------------------------------ fixtures
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000003a1', 'authenticated', 'authenticated', 'p3platform@olympus.test', now(), '{"full_name":"P3 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003a2', 'authenticated', 'authenticated', 'p3owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000003a3', 'authenticated', 'authenticated', 'p3owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000003a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a2","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Garments', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a3","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Textiles', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a1","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org_a', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003a2'))::text, true);
  perform set_config('t.org_b', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000003a3'))::text, true);
end $$;

-- Alpha admin: structure, people and logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a2","role":"authenticated"}', true);
do $$
declare
  v_production  uuid;
  v_quality     uuid;
  v_operator    uuid;
  v_inspector   uuid;
  v_manager_des uuid;
  v_branch      uuid;
  v_office      uuid;
  v_hr_role     uuid := (select id from public.roles where system_key = 'hr_manager');
  v_mgr_role    uuid := (select id from public.roles where system_key = 'manager');
  v_common      jsonb;
begin
  insert into public.departments (name) values ('Production') returning id into v_production;
  insert into public.departments (name) values ('Quality') returning id into v_quality;
  insert into public.designations (department_id, grade_id, name)
    values (v_production, (select id from public.grades where code = 'EM1'), 'Operator') returning id into v_operator;
  insert into public.designations (department_id, grade_id, name)
    values (v_quality, (select id from public.grades where code = 'EM2'), 'Inspector') returning id into v_inspector;
  insert into public.designations (department_id, grade_id, name)
    values (v_production, (select id from public.grades where code = 'MS1'), 'Line Manager') returning id into v_manager_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.quality', v_quality::text, true);

  v_common := jsonb_build_object('employment_type', 'permanent', 'department_id', v_production,
                                 'designation_id', v_operator, 'branch_id', v_branch, 'office_id', v_office);
  -- w1 joined mid-January (5 completed months at June end), w2 a year earlier.
  perform set_config('t.w1', public.create_employee(v_common || '{"full_name":"Worker One","join_date":"2026-01-15"}')::text, true);
  perform set_config('t.w2', public.create_employee(v_common || '{"full_name":"Worker Two","join_date":"2025-06-01"}')::text, true);
  perform set_config('t.q1', public.create_employee(v_common || jsonb_build_object(
    'full_name', 'Quality One', 'join_date', '2025-01-01', 'department_id', v_quality, 'designation_id', v_inspector))::text, true);
  perform set_config('t.m', public.create_employee(v_common || jsonb_build_object(
    'full_name', 'Line Manager', 'join_date', '2025-01-01', 'designation_id', v_manager_des))::text, true);
  perform set_config('t.h', public.create_employee(v_common || '{"full_name":"HR Person","join_date":"2025-01-01"}')::text, true);

  perform set_config('t.u_w1', public.grant_portal_access(current_setting('t.w1')::uuid, 'w1@alpha3.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_m', public.grant_portal_access(current_setting('t.m')::uuid, 'm@alpha3.test', null, 'Passw0rd1', v_mgr_role)::text, true);
  perform set_config('t.u_h', public.grant_portal_access(current_setting('t.h')::uuid, 'h@alpha3.test', null, 'Passw0rd1', v_hr_role)::text, true);
  perform set_config('t.admin_emp', (select employee_id from public.org_members
                                     where user_id = '00000000-0000-0000-0000-0000000003a2')::text, true);

  assert (select count(*) from public.salary_components) = 5, 'five components are seeded';
  assert (select count(*) from public.salary_components where is_basic and code = 'BASIC') = 1, 'one Basic component';
  assert (select ot_hourly_divisor from public.payroll_settings) = 208, 'payroll settings are seeded';
  assert (select statutory_confirmed_at from public.payroll_settings) is null, 'statutory values start unconfirmed';
  raise notice 'PASS setup: components, payroll settings, people and logins';
end $$;

-- ------------------------------------------------- templates and rounding (test 16)
do $$
declare
  v_template_a uuid;
  v_template_b uuid;
  v_special    uuid;
  v_preview    jsonb;
begin
  v_template_a := public.save_salary_template(null, jsonb_build_object(
    'name', 'Worker EM1', 'basic_amount', 10000,
    'lines', (select jsonb_agg(jsonb_build_object('component_id', id, 'calc', calc, 'value', default_value))
              from public.salary_components where not is_basic)));
  perform set_config('t.tpl_a', v_template_a::text, true);

  -- 10,000 + 50% house rent 5,000 + 750 + 450 + 1,250 = 17,450.00
  v_preview := public.preview_salary(v_template_a);
  assert (v_preview ->> 'gross')::numeric = 17450.00, format('template gross 17450, got %s', v_preview ->> 'gross');
  assert (v_preview -> 'lines' -> 0 ->> 'code') = 'BASIC', 'Basic is the first line';

  -- Target gross 25,000: basic = (25,000 - 2,450) / 1.5 = 15,033.333 -> 15,033.33;
  -- house rent = 7,516.665 -> 7,516.67 (half away from zero); sum = 25,000.00 exactly.
  v_preview := public.preview_salary(v_template_a, null, 25000);
  assert (v_preview ->> 'basic')::numeric = 15033.33, format('basic 15033.33, got %s', v_preview ->> 'basic');
  assert (select (l ->> 'amount')::numeric from jsonb_array_elements(v_preview -> 'lines') l where l ->> 'code' = 'HOUSE_RENT')
         = 7516.67, 'house rent rounds 7516.665 to 7516.67';
  assert (v_preview ->> 'gross')::numeric = 25000.00, 'gross hits the target exactly';

  -- Percent of gross: basic 20,000, house rent 10,000, medical 750, special 10% of gross.
  -- gross = 30,750 / 0.9 = 34,166.666… ; special = 3,416.67 ; sum = 34,166.67.
  insert into public.salary_components (name, code, kind, calc, default_value)
    values ('Special Allowance', 'SPECIAL', 'earning', 'percent_of_gross', 10) returning id into v_special;
  v_template_b := public.save_salary_template(null, jsonb_build_object(
    'name', 'Manager MS1', 'basic_amount', 20000, 'lines', jsonb_build_array(
      jsonb_build_object('component_id', (select id from public.salary_components where code = 'HOUSE_RENT'), 'calc', 'percent_of_basic', 'value', 50),
      jsonb_build_object('component_id', (select id from public.salary_components where code = 'MEDICAL'), 'calc', 'fixed', 'value', 750),
      jsonb_build_object('component_id', v_special, 'calc', 'percent_of_gross', 'value', 10))));
  v_preview := public.preview_salary(v_template_b);
  assert (v_preview ->> 'gross')::numeric = 34166.67, format('gross 34166.67, got %s', v_preview ->> 'gross');
  assert (select (l ->> 'amount')::numeric from jsonb_array_elements(v_preview -> 'lines') l where l ->> 'code' = 'SPECIAL')
         = 3416.67, 'special allowance 3416.67';

  begin
    perform public.save_salary_template(v_template_b, jsonb_build_object(
      'name', 'Manager MS1', 'basic_amount', 20000, 'lines', jsonb_build_array(
        jsonb_build_object('component_id', v_special, 'calc', 'percent_of_gross', 'value', 100))));
    raise exception 'FAIL: 100%% of gross accepted';
  exception when invalid_parameter_value then null;
  end;
  assert (select count(*) from public.salary_template_lines where template_id = v_template_b) = 3,
    'a refused save leaves the template unchanged';

  begin
    update public.salary_components set status = 'inactive' where code = 'MEDICAL';
    raise exception 'FAIL: a component in use was switched off';
  exception when check_violation then null;
  end;
  begin
    update public.salary_components set status = 'inactive' where code = 'BASIC';
    raise exception 'FAIL: Basic was switched off';
  exception when check_violation then null;
  end;
  raise notice 'PASS test 16: template resolution and rounding (17450.00, 15033.33 / 7516.67 / 25000.00, 34166.67)';
end $$;

-- ------------------------------------------------------------------- starting pay (HR)
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  perform public.set_initial_compensation(current_setting('t.w1')::uuid, current_setting('t.tpl_a')::uuid,
                                          10000, null, '2026-01-15', 'Joining pay');
  perform public.set_initial_compensation(current_setting('t.w2')::uuid, current_setting('t.tpl_a')::uuid,
                                          null, 25000, '2025-06-01', 'Joining pay');
  assert (select gross from public.employee_pay_v where employee_id = current_setting('t.w1')::uuid) = 17450.00, 'w1 gross 17450';
  assert (select basic from public.employee_pay_v where employee_id = current_setting('t.w2')::uuid) = 15033.33, 'w2 basic 15033.33';
  begin
    perform public.set_initial_compensation(current_setting('t.w1')::uuid, current_setting('t.tpl_a')::uuid,
                                            12000, null, '2026-02-01', null);
    raise exception 'FAIL: a second starting pay was accepted';
  exception when unique_violation then null;
  end;
  begin
    perform public.set_initial_compensation(current_setting('t.h')::uuid, current_setting('t.tpl_a')::uuid,
                                            50000, null, '2025-01-01', null);
    raise exception 'FAIL: HR set their own pay';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS starting pay: once per employee, never by yourself';
end $$;

-- ------------------------------------------- confidentiality and isolation (tests 1-2)
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
begin
  assert (select count(*) from public.employee_pay_v) = 0, 'a manager sees no pay';
  assert (select count(*) from public.salary_components) = 0, 'a manager sees no salary components';
  assert (select count(*) from public.salary_templates) = 0, 'a manager sees no templates';
  begin
    perform public.get_employee_compensation(current_setting('t.w1')::uuid);
    raise exception 'FAIL: a manager read pay history';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.employee_compensation;
    raise exception 'FAIL: the pay table is open to API roles';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w1')), true);
do $$
begin
  assert (select count(*) from public.employee_pay_v) = 0, 'an employee sees no pay table (payslips come in 3B)';
  begin
    perform public.preview_salary(current_setting('t.tpl_a')::uuid);
    raise exception 'FAIL: an employee previewed a template';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a3","role":"authenticated"}', true);
do $$
begin
  assert not exists (select 1 from public.employee_pay_v where org_id = current_setting('t.org_a')::uuid),
    'company B sees none of company A''s pay';
  assert not exists (select 1 from public.salary_templates where org_id = current_setting('t.org_a')::uuid),
    'company B sees none of company A''s templates';
  begin
    perform public.get_employee_compensation(current_setting('t.w1')::uuid);
    raise exception 'FAIL: company B read company A''s pay history';
  exception when no_data_found then null;
  end;
  begin
    perform public.preview_salary(current_setting('t.tpl_a')::uuid);
    raise exception 'FAIL: company B previewed company A''s template';
  exception when no_data_found then null;
  end;
  raise notice 'PASS tests 1-2: managers and employees see no salary; company B sees nothing of company A';
end $$;

-- --------------------------------------- increments: maker-checker and arrears (9, 17)
reset role;
insert into public.role_permissions (org_id, role_id, permission_key)
select org_id, id, 'increments.approve' from public.roles
where org_id = current_setting('t.org_a')::uuid and system_key = 'hr_manager';
set local role authenticated;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  -- Back-dated: 17,450 -> 20,000 from 15 March.
  perform set_config('t.inc', public.request_increment(current_setting('t.w1')::uuid, jsonb_build_object(
    'type', 'increment', 'new_gross', 20000, 'effective_date', '2026-03-15', 'reason', 'Annual review'))::text, true);
  begin
    perform public.request_increment(current_setting('t.w1')::uuid, jsonb_build_object(
      'new_gross', 21000, 'effective_date', '2026-04-01', 'reason', 'Second one'));
    raise exception 'FAIL: two pending increments for one employee';
  exception when unique_violation then null;
  end;
  begin
    perform public.decide_increment(current_setting('t.inc')::uuid, true, null);
    raise exception 'FAIL: the requester approved their own increment';
  exception when insufficient_privilege then null;
  end;
  -- Arrears up to May: March 16 of 30 days x 2,550 = 1,360.00 + April 2,550.00 = 3,910.00
  assert (public.get_increment_arrears(current_setting('t.inc')::uuid, '2026-05-01') ->> 'amount')::numeric = 3910.00,
    'arrears preview 3910.00';
  assert (public.get_increment_arrears(current_setting('t.inc')::uuid, '2026-03-01') ->> 'amount')::numeric = 0,
    'no arrears before the effective month';
  raise notice 'PASS test 17: maker-checker (the requester cannot approve); one pending increment per employee';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a2","role":"authenticated"}', true);
do $$
declare
  v_history jsonb;
begin
  perform public.decide_increment(current_setting('t.inc')::uuid, true, 'Approved');
  v_history := public.get_employee_compensation(current_setting('t.w1')::uuid);
  assert jsonb_array_length(v_history) = 2, 'two pay versions';
  -- New basic = (20,000 - 2,450) / 1.5 = 11,700.00 ; house rent 5,850.00
  assert (v_history -> 0 ->> 'gross')::numeric = 20000.00 and (v_history -> 0 ->> 'basic')::numeric = 11700.00,
    'new pay 20000 / basic 11700';
  assert (v_history -> 0 ->> 'effective_to') is null, 'the new version is current';
  assert (v_history -> 1 ->> 'effective_to')::date = '2026-03-14', 'the old version closes the day before';
  assert (select status from public.salary_increments_v where id = current_setting('t.inc')::uuid) = 'approved', 'approved';
  raise notice 'PASS test 9: an approved back-dated increment opens a new pay version and previews 3910.00 arrears';
end $$;

-- Pay history is immutable, even for the table owner.
reset role;
do $$
begin
  begin
    update public.employee_compensation set gross = 1 where employee_id = current_setting('t.w1')::uuid;
    raise exception 'FAIL: pay history was edited';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.employee_compensation_lines set amount = 1
     where compensation_id in (select id from public.employee_compensation where employee_id = current_setting('t.w1')::uuid);
    raise exception 'FAIL: pay lines were edited';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.employee_compensation where employee_id = current_setting('t.w1')::uuid;
    raise exception 'FAIL: pay history was deleted';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS immutability: pay history and its lines cannot be edited or deleted';
end $$;
set local role authenticated;

-- ------------------------------------------------------------ bonuses (test 10)
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
declare
  v_bonus   uuid;
  v_preview jsonb;
begin
  v_bonus := public.save_bonus(null, jsonb_build_object(
    'name', 'Eid-ul-Adha 2026', 'type', 'festival', 'basis', 'percent', 'percent', 50, 'percent_base', 'basic',
    'payment_month', '2026-06-01', 'min_service_months', 6, 'scope', 'all'));
  v_preview := public.get_bonus_preview(v_bonus);
  -- w1: joined 2026-01-15, 5 completed months by 30 June (Jan 15 - Jun 14) -> not eligible.
  assert (select (r ->> 'eligible')::boolean from jsonb_array_elements(v_preview) r
          where r ->> 'employee_id' = current_setting('t.w1')) = false, 'w1 lacks minimum service';
  assert (select (r ->> 'service_months')::int from jsonb_array_elements(v_preview) r
          where r ->> 'employee_id' = current_setting('t.w1')) = 5, 'w1 has 5 months';
  -- w2: 12 months; 50% of basic 15,033.33 = 7,516.665 -> 7,516.67
  assert (select (r ->> 'amount')::numeric from jsonb_array_elements(v_preview) r
          where r ->> 'employee_id' = current_setting('t.w2')) = 7516.67, 'w2 bonus 7516.67';
  -- People without pay on record are listed but not eligible.
  assert (select (r ->> 'eligible')::boolean from jsonb_array_elements(v_preview) r
          where r ->> 'employee_id' = current_setting('t.q1')) = false, 'no pay -> not eligible';

  -- Department scope: only Quality.
  v_bonus := public.save_bonus(null, jsonb_build_object(
    'name', 'Quality incentive', 'type', 'incentive', 'basis', 'fixed', 'amount', 2000,
    'payment_month', '2026-06-01', 'scope', 'departments', 'department_ids', jsonb_build_array(current_setting('t.quality'))));
  v_preview := public.get_bonus_preview(v_bonus);
  assert jsonb_array_length(v_preview) = 1 and v_preview -> 0 ->> 'employee_id' = current_setting('t.q1'),
    'department scope lists only Quality';
  raise notice 'PASS test 10: bonus respects minimum service, pay on record and eligibility scope';
end $$;

-- ------------------------------------------------------ loans and deductions (14)
do $$
declare
  v_loan uuid;
begin
  v_loan := public.create_deduction(jsonb_build_object(
    'employee_id', current_setting('t.w1'), 'type', 'loan', 'description', 'Emergency loan',
    'total', 10000, 'installment', 3000, 'start_month', '2026-07-01'));
  assert (select remaining from public.employee_deductions_v where id = v_loan) = 10000, 'remaining starts at the total';
  begin
    perform public.create_deduction(jsonb_build_object(
      'employee_id', current_setting('t.w1'), 'type', 'advance', 'total', 1000, 'installment', 2000, 'start_month', '2026-07-01'));
    raise exception 'FAIL: installment above the total';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.create_deduction(jsonb_build_object(
      'employee_id', current_setting('t.h'), 'type', 'loan', 'total', 1000, 'installment', 100, 'start_month', '2026-07-01'));
    raise exception 'FAIL: HR created a loan for themselves';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS test 14 (set-up): loans start with remaining = total; the installment never exceeds the total';
end $$;

-- ------------------------------------------------- payment accounts (test 21 masking)
do $$
declare
  v_bank   uuid;
  v_wallet uuid;
begin
  v_bank := public.save_payment_account(null, jsonb_build_object(
    'employee_id', current_setting('t.w1'), 'method', 'bank', 'bank_name', 'Sonali Bank', 'branch_name', 'Motijheel',
    'routing_number', '200270522', 'account_name', 'Worker One', 'account_number', '0123-4567-89012', 'is_primary', true));
  v_wallet := public.save_payment_account(null, jsonb_build_object(
    'employee_id', current_setting('t.w1'), 'method', 'mobile_wallet', 'wallet_provider', 'bkash',
    'wallet_number', '01712345678', 'is_primary', true));
  perform set_config('t.bank', v_bank::text, true);

  assert (select masked_number from public.payment_accounts_v where id = v_bank) = '•••• 9012', 'bank number masked';
  assert (select masked_number from public.payment_accounts_v where id = v_wallet) = '•••• 5678', 'wallet number masked';
  assert (select count(*) from public.payment_accounts_v where employee_id = current_setting('t.w1')::uuid and is_primary) = 1,
    'one primary account (the newer one took over)';
  assert public.reveal_payment_account(v_bank) = '0123456789012', 'reveal returns the full number';

  -- Editing without a new number keeps the stored one.
  perform public.save_payment_account(v_bank, jsonb_build_object(
    'bank_name', 'Sonali Bank', 'branch_name', 'Gulshan', 'routing_number', '200270522', 'account_name', 'Worker One'));
  assert public.reveal_payment_account(v_bank) = '0123456789012', 'the number survives an edit';

  begin
    perform public.save_payment_account(null, jsonb_build_object(
      'employee_id', current_setting('t.h'), 'method', 'cash'));
    raise exception 'FAIL: HR changed their own payment account';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.employee_payment_accounts;
    raise exception 'FAIL: the payment account table is open to API roles';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_w1')), true);
do $$
begin
  assert (select count(*) from public.payment_accounts_v) = 2, 'an employee sees their own accounts (masked)';
  assert (select count(*) from public.employee_deductions_v) = 1, 'an employee sees their own loan';
  begin
    perform public.reveal_payment_account(current_setting('t.bank')::uuid);
    raise exception 'FAIL: an employee revealed a number';
  exception when insufficient_privilege then null;
  end;
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_m')), true);
do $$
begin
  assert (select count(*) from public.payment_accounts_v) = 0, 'a manager sees no payment accounts';
  assert (select count(*) from public.employee_deductions_v) = 0, 'a manager sees no deductions';
  assert (select count(*) from public.bonuses) = 0, 'a manager sees no bonuses';
end $$;

reset role;
do $$
begin
  assert not exists (select 1 from public.audit_logs
                     where (coalesce(old_value::text, '') || coalesce(new_value::text, '')) like '%0123456789012%'
                        or (coalesce(old_value::text, '') || coalesce(new_value::text, '')) like '%1712345678%'
                        or (coalesce(old_value::text, '') || coalesce(new_value::text, '')) like '%number_enc%'),
    'no account number (plain or encrypted) in the audit log';
  assert (select count(*) from public.audit_logs where action = 'payment_account.revealed') = 2, 'every reveal is audited';
  assert (select count(*) from public.audit_logs
          where entity = 'employee_payment_accounts' and new_value ? 'number_changed') = 0,
    'an edit without a new number does not flag a change';
  assert (select account_number_enc from public.employee_payment_accounts where id = current_setting('t.bank')::uuid)::text
         not like '%0123456789012%', 'stored encrypted';
  raise notice 'PASS test 21 (accounts): numbers encrypted, masked in views, never in the audit log; reveals audited';
end $$;
set local role authenticated;

-- ------------------------------------------------- statutory confirmation (settings)
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000003a2","role":"authenticated"}', true);
do $$
begin
  perform public.confirm_payroll_statutory_values();
  assert (select statutory_confirmed_at from public.payroll_settings) is not null, 'confirmed';
  update public.payroll_settings set ot_hourly_divisor = 240;
  assert (select statutory_confirmed_at from public.payroll_settings) is null, 'a changed statutory value needs confirming again';
  update public.payroll_settings set net_rounding = 'down_taka';
  assert (select net_rounding from public.payroll_settings) = 'down_taka', 'admin updates settings';
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_h')), true);
do $$
begin
  update public.payroll_settings set net_rounding = 'none';
  assert (select net_rounding from public.payroll_settings) = 'down_taka', 'HR cannot change payroll settings by default';
  begin
    perform public.confirm_payroll_statutory_values();
    raise exception 'FAIL: HR confirmed statutory values';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS settings: statutory values need confirmation; only the permission holder changes settings';
end $$;

do $$ begin raise notice '==== ALL PART 3A CHECKS PASSED ===='; end $$;
select '==== ALL PART 3A CHECKS PASSED ====' as result;
rollback;
