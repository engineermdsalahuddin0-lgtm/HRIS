-- =============================================================================
-- Communication C2 tests: helpdesk.
--
-- Office time (Asia/Dhaka, 09:00-18:00, Friday off, 16 Dec holiday):
--   Thu 5 Nov 2026 17:00 + 120 office min = Sat 7 Nov 10:00 (60 on Thursday, Friday skipped, 60 on Saturday);
--   minutes between those two moments = 120; Tue 15 Dec 17:30 + 60 = Thu 17 Dec 09:30 (Victory Day skipped);
--   office days after Mon 2 Nov up to Thu 5 Nov = 3.
-- Alpha: Ivan (custom role "IT" with helpdesk.handle) handles IT Support; Hana is HR; Sam raises tickets;
--   Mona (Manager) is a bystander.
--   1. IT ticket goes to Ivan (#1); a Payroll ticket (confidential, no handler) waits in the HR queue (#2);
--      Ivan cannot be the Payroll handler; Mona and Beta see nothing; only HR lists all.
--   2. Thread: Ivan's internal note is hidden from Sam; his reply counts as the first response; waiting ->
--      Sam replies -> in progress again.
--   3. Resolve -> Sam reopens with a reason -> resolve -> Sam rates 5 -> closed; closed tickets refuse replies,
--      reopening and rating.
--   4. Auto-close after 3 working days; SLA breach counted; settings validation.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL COMM C2 HELPDESK CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000c2001', 'authenticated', 'authenticated', 'c2platform@olympus.test', now(), '{"full_name":"C2 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c2002', 'authenticated', 'authenticated', 'c2owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c2003', 'authenticated', 'authenticated', 'c2owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000c2001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c2002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Desk', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c2003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Desk', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c2001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c2002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c2003'));
end $$;

-- ======================================================= 0. office time
reset role;
do $$
declare
  v_org uuid := current_setting('t.org')::uuid;
begin
  assert private.add_office_minutes(v_org, timestamptz '2026-11-05 17:00+06', 120) = timestamptz '2026-11-07 10:00+06',
         'Thu 17:00 + 120 = Sat 10:00, got ' || private.add_office_minutes(v_org, timestamptz '2026-11-05 17:00+06', 120);
  assert private.office_minutes_between(v_org, timestamptz '2026-11-05 17:00+06', timestamptz '2026-11-07 10:00+06') = 120, 'minutes between';
  assert private.add_office_minutes(v_org, timestamptz '2026-12-15 17:30+06', 60) = timestamptz '2026-12-17 09:30+06',
         'Victory Day is skipped, got ' || private.add_office_minutes(v_org, timestamptz '2026-12-15 17:30+06', 60);
  assert private.add_office_minutes(v_org, timestamptz '2026-11-05 20:00+06', 30) = timestamptz '2026-11-07 09:30+06', 'after hours starts next office day';
  assert private.office_days_between(v_org, date '2026-11-02', date '2026-11-05') = 3, 'three office days';
  assert private.office_days_between(v_org, date '2026-11-05', date '2026-11-07') = 1, 'Friday is not an office day';
  raise notice 'PASS: office time skips evenings, Fridays and holidays';
end $$;
set local role authenticated;

-- Alpha admin: people, the IT role, logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c2002","role":"authenticated"}', true);
do $$
declare
  v_dept uuid; v_des uuid; v_branch uuid; v_office uuid; v_common jsonb; v_it uuid;
begin
  insert into public.departments (name) values ('Admin') returning id into v_dept;
  insert into public.designations (department_id, grade_id, name) values (v_dept, (select id from public.grades where code = 'EM1'), 'Officer') returning id into v_des;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  insert into public.roles (name, description) values ('IT', 'IT support') returning id into v_it;
  perform public.set_role_permissions(v_it, array['helpdesk.handle']);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'department_id', v_dept,
                                 'designation_id', v_des, 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.e_ivan', public.create_employee(v_common || '{"full_name":"Ivan IT"}')::text, true);
  perform set_config('t.e_hana', public.create_employee(v_common || '{"full_name":"Hana HR"}')::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || '{"full_name":"Sam Staff"}')::text, true);
  perform set_config('t.e_mona', public.create_employee(v_common || '{"full_name":"Mona Manager"}')::text, true);
  perform set_config('t.u_ivan', public.grant_portal_access(current_setting('t.e_ivan')::uuid, 'ivan@alpha.test', null, 'Passw0rd1', v_it)::text, true);
  perform set_config('t.u_hana', public.grant_portal_access(current_setting('t.e_hana')::uuid, 'hana@alpha.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(current_setting('t.e_mona')::uuid, 'mona@alpha.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'manager'))::text, true);
end $$;

-- HR sets the IT handler; Ivan cannot take the confidential Payroll category.
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.get_helpdesk_setup();
  v_it uuid := (select (c ->> 'id')::uuid from jsonb_array_elements(v -> 'categories') c where c ->> 'name' = 'IT Support');
  v_pay uuid := (select (c ->> 'id')::uuid from jsonb_array_elements(v -> 'categories') c where c ->> 'name' = 'Payroll Issue');
begin
  assert jsonb_array_length(v -> 'categories') = 7, 'seven default categories';
  assert (select (c ->> 'confidential')::boolean from jsonb_array_elements(v -> 'categories') c where c ->> 'name' = 'Payroll Issue'), 'Payroll is confidential';
  assert (select count(*) from jsonb_array_elements(v -> 'handlers') h where h ->> 'full_name' = 'Ivan IT') = 1, 'Ivan is a possible handler';
  perform set_config('t.c_it', v_it::text, true);
  perform set_config('t.c_pay', v_pay::text, true);
  perform public.save_helpdesk_category(v_it, jsonb_build_object('name', 'IT Support', 'handler_employee_id', current_setting('t.e_ivan')));
  begin
    perform public.save_helpdesk_category(v_pay, jsonb_build_object('name', 'Payroll Issue', 'confidential', true, 'handler_employee_id', current_setting('t.e_ivan')));
    raise exception 'FAIL: a non-HR handler for a confidential category';
  exception when check_violation then null;
  end;
  begin
    perform public.save_helpdesk_category(v_it, jsonb_build_object('name', 'IT Support', 'handler_employee_id', current_setting('t.e_sam')));
    raise exception 'FAIL: a handler without helpdesk.handle';
  exception when check_violation then null;
  end;
  begin
    perform public.save_helpdesk_settings('{"sla":{"critical":{"response":300,"resolution":60},"high":{"response":240,"resolution":1440},"medium":{"response":1440,"resolution":4320},"low":{"response":4320,"resolution":10080}},"auto_close_days":3}');
    raise exception 'FAIL: response after resolution accepted';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS: setup seeds categories; handlers need helpdesk.handle, confidential ones helpdesk.manage; SLA checked';
end $$;

-- ======================================================= 1. routing and visibility
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v1 jsonb;
  v2 jsonb;
begin
  v1 := public.create_ticket(jsonb_build_object('subject', 'Laptop does not start', 'description', 'Black screen since morning',
                                                'category_id', current_setting('t.c_it'), 'priority', 'high'));
  v2 := public.create_ticket(jsonb_build_object('subject', 'Overtime missing in payslip', 'description', 'October OT not paid',
                                                'category_id', current_setting('t.c_pay')));
  assert (v1 ->> 'ticket_no')::int = 1 and (v1 ->> 'assigned')::boolean, 'IT ticket #1 goes to Ivan ' || v1::text;
  assert (v2 ->> 'ticket_no')::int = 2 and not (v2 ->> 'assigned')::boolean, 'Payroll ticket #2 waits in the HR queue ' || v2::text;
  perform set_config('t.t_it', v1 ->> 'id', true);
  perform set_config('t.t_pay', v2 ->> 'id', true);
  assert jsonb_array_length(public.list_tickets('mine') -> 'tickets') = 2, 'Sam lists his two tickets';
  begin
    perform public.list_tickets('all');
    raise exception 'FAIL: an employee listed all tickets';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_ivan')), true);
do $$
begin
  assert jsonb_array_length(public.list_tickets('assigned') -> 'tickets') = 1, 'Ivan sees only the IT ticket';
  begin
    perform public.get_ticket(current_setting('t.t_pay')::uuid);
    raise exception 'FAIL: the IT handler opened a payroll ticket';
  exception when no_data_found then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
begin
  begin
    perform public.get_ticket(current_setting('t.t_it')::uuid);
    raise exception 'FAIL: a manager opened someone else''s ticket';
  exception when no_data_found then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c2003","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.get_ticket(current_setting('t.t_it')::uuid);
    raise exception 'FAIL: another company opened the ticket';
  exception when no_data_found then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.list_tickets('all');
begin
  assert jsonb_array_length(v -> 'tickets') = 2 and (v -> 'kpis' ->> 'open')::int = 2, 'HR sees both ' || (v -> 'kpis')::text;
  perform public.assign_ticket(current_setting('t.t_pay')::uuid, current_setting('t.e_hana')::uuid);
  begin
    perform public.assign_ticket(current_setting('t.t_pay')::uuid, current_setting('t.e_ivan')::uuid);
    raise exception 'FAIL: confidential ticket assigned to IT';
  exception when check_violation then null;
  end;
  raise notice 'PASS: tickets route by category, confidential ones stay with HR, others see nothing';
end $$;

-- ======================================================= 2. thread, internal notes, waiting
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_ivan')), true);
do $$
declare
  v jsonb;
begin
  perform public.reply_ticket(current_setting('t.t_it')::uuid, '{"body":"Probably the charger","internal":true}');
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert v ->> 'first_response_at' is null, 'an internal note is not a response';
  perform public.reply_ticket(current_setting('t.t_it')::uuid, '{"body":"Is the charger light on?","status":"waiting"}');
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert v ->> 'status' = 'waiting' and v ->> 'first_response_at' is not null, 'reply = first response; now waiting';
  assert (v -> 'sla' ->> 'paused')::boolean, 'the clock is paused';
  begin
    perform public.set_ticket_status(current_setting('t.t_it')::uuid, 'closed', 'done');
    raise exception 'FAIL: a handler closed directly';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb := public.get_ticket(current_setting('t.t_it')::uuid);
begin
  assert (select count(*) from jsonb_array_elements(v -> 'messages') m where m ->> 'kind' = 'note') = 0, 'Sam never sees internal notes';
  assert (select count(*) from jsonb_array_elements(v -> 'messages') m where m ->> 'kind' = 'reply') = 1, 'Sam sees the reply';
  begin
    perform public.reply_ticket(current_setting('t.t_it')::uuid, '{"body":"x","internal":true}');
    raise exception 'FAIL: the requester wrote an internal note';
  exception when insufficient_privilege then null;
  end;
  perform public.reply_ticket(current_setting('t.t_it')::uuid, '{"body":"No light at all"}');
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert v ->> 'status' = 'in_progress', 'the employee''s answer restarts the clock';
  raise notice 'PASS: internal notes stay internal; waiting pauses until the employee replies';
end $$;

-- ======================================================= 3. resolve, reopen, rate, closed
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_ivan')), true);
select public.set_ticket_status(current_setting('t.t_it')::uuid, 'resolved', 'Charger replaced');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb;
begin
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert (v -> 'can' ->> 'rate')::boolean and (v -> 'can' ->> 'reopen')::boolean and not (v -> 'can' ->> 'reply')::boolean, 'rate or reopen ' || (v -> 'can')::text;
  begin
    perform public.reopen_ticket(current_setting('t.t_it')::uuid, '');
    raise exception 'FAIL: reopened without a reason';
  exception when invalid_parameter_value then null;
  end;
  perform public.reopen_ticket(current_setting('t.t_it')::uuid, 'Still black screen');
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert v ->> 'status' = 'in_progress' and (v ->> 'reopen_count')::int = 1, 'reopened';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_ivan')), true);
select public.set_ticket_status(current_setting('t.t_it')::uuid, 'resolved', 'New motherboard');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb;
begin
  perform public.rate_ticket(current_setting('t.t_it')::uuid, 5, 'Fast');
  v := public.get_ticket(current_setting('t.t_it')::uuid);
  assert v ->> 'status' = 'closed' and v ->> 'closed_reason' = 'rated' and (v ->> 'rating')::int = 5, 'rated and closed';
  begin
    perform public.reply_ticket(current_setting('t.t_it')::uuid, '{"body":"one more thing"}');
    raise exception 'FAIL: replied to a closed ticket';
  exception when check_violation then null;
  end;
  begin
    perform public.reopen_ticket(current_setting('t.t_it')::uuid, 'again');
    raise exception 'FAIL: reopened a closed ticket';
  exception when check_violation then null;
  end;
  raise notice 'PASS: resolved -> reopen with a reason -> resolved -> rated and closed; closed stays closed';
end $$;

-- ======================================================= 4. auto-close and SLA breach
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
select public.set_ticket_status(current_setting('t.t_pay')::uuid, 'resolved', 'OT added to November');
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
select set_config('t.t_late', (public.create_ticket(jsonb_build_object('subject', 'Printer jam', 'description', 'Floor 2',
                                 'category_id', current_setting('t.c_it'), 'priority', 'critical')) ->> 'id'), true);
reset role;
update public.helpdesk_tickets set resolved_at = now() - interval '10 days' where id = current_setting('t.t_pay')::uuid;
update public.helpdesk_tickets set response_due_at = now() - interval '1 hour', created_at = now() - interval '2 days'
 where id = current_setting('t.t_late')::uuid;
set local role authenticated;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hana')), true);
do $$
declare
  v jsonb := public.list_tickets('all');
  pay jsonb := (select x from jsonb_array_elements(v -> 'tickets') x where x ->> 'id' = current_setting('t.t_pay'));
  late jsonb := (select x from jsonb_array_elements(v -> 'tickets') x where x ->> 'id' = current_setting('t.t_late'));
begin
  assert pay ->> 'status' = 'closed' and pay ->> 'closed_reason' = 'auto', 'closed after 3 working days ' || pay::text;
  assert (late ->> 'response_breached')::boolean, 'response SLA breached';
  assert (v -> 'kpis' ->> 'sla_breach')::int = 1, 'one breach counted ' || (v -> 'kpis')::text;
  raise notice 'PASS: resolved tickets close themselves; breaches are counted';
end $$;

select '==== ALL COMM C2 HELPDESK CHECKS PASSED ====' as result;
rollback;
