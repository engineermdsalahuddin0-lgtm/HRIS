-- =============================================================================
-- Communication C1 tests: notices.
--
-- Alpha: departments Sales and Ops. People: HR (HR Manager), Mona (Manager, Sales),
--   Sam (Sales), Olu (Ops), Nia (Sales, no portal login).
--   1. HR publishes to everyone (acknowledgement required); Sam and Olu see it, Beta never does.
--   2. Mona (Manager) asks for "everyone" but the notice goes to Sales only; Olu does not see it;
--      Mona cannot edit HR's notice; an employee cannot publish.
--   3. Read receipt on first open (once); receipts list 4 Sales people for Mona's notice incl. Nia (no portal).
--   4. Acknowledge once (the time never changes); a notice without acknowledgement refuses it.
--   5. Scheduled notice: hidden until its time, then active.
--   6. Email copy: without an email channel the publish says so; with one, one email per target with an
--      address (Alpha: 5 targets all with an address); reminders only to those not acknowledged, once per 24 h.
--   7. Validation (expiry before publish), archive (gone from readers, frozen), KPIs, dashboard alerts.
--
-- Run the whole file in the SQL editor; it rolls back. Expect "ALL COMM C1 NOTICE CHECKS PASSED".
-- =============================================================================
begin;

insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000c1001', 'authenticated', 'authenticated', 'c1platform@olympus.test', now(), '{"full_name":"C1 Platform"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c1002', 'authenticated', 'authenticated', 'c1owner@alpha.test', now(), '{"full_name":"Alpha Owner"}', now(), now()),
  ('00000000-0000-0000-0000-0000000c1003', 'authenticated', 'authenticated', 'c1owner@beta.test', now(), '{"full_name":"Beta Owner"}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000c1001');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c1002","role":"authenticated"}', true);
select public.submit_org_signup_request('Alpha Notices', 'Alpha Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c1003","role":"authenticated"}', true);
select public.submit_org_signup_request('Beta Notices', 'Beta Owner', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c1001","role":"authenticated"}', true);
do $$
begin
  perform set_config('t.org', public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c1002'))::text, true);
  perform public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000c1003'));
end $$;

-- Alpha admin: structure, people, logins.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c1002","role":"authenticated"}', true);
do $$
declare
  v_sales uuid; v_ops uuid; v_des_s uuid; v_des_o uuid; v_branch uuid; v_office uuid; v_common jsonb;
begin
  insert into public.departments (name) values ('Sales') returning id into v_sales;
  insert into public.departments (name) values ('Ops') returning id into v_ops;
  insert into public.designations (department_id, grade_id, name) values (v_sales, (select id from public.grades where code = 'EM1'), 'Sales Officer') returning id into v_des_s;
  insert into public.designations (department_id, grade_id, name) values (v_ops, (select id from public.grades where code = 'EM1'), 'Ops Officer') returning id into v_des_o;
  insert into public.branches (name) values ('Dhaka') returning id into v_branch;
  insert into public.offices (branch_id, name) values (v_branch, 'HQ') returning id into v_office;
  perform set_config('t.sales', v_sales::text, true);
  perform set_config('t.ops', v_ops::text, true);
  v_common := jsonb_build_object('join_date', '2026-01-01', 'employment_type', 'permanent', 'branch_id', v_branch, 'office_id', v_office);
  perform set_config('t.e_hr', public.create_employee(v_common || jsonb_build_object('full_name', 'Hana HR', 'department_id', v_ops, 'designation_id', v_des_o))::text, true);
  perform set_config('t.e_mona', public.create_employee(v_common || jsonb_build_object('full_name', 'Mona Manager', 'department_id', v_sales, 'designation_id', v_des_s))::text, true);
  perform set_config('t.e_sam', public.create_employee(v_common || jsonb_build_object('full_name', 'Sam Sales', 'department_id', v_sales, 'designation_id', v_des_s))::text, true);
  perform set_config('t.e_olu', public.create_employee(v_common || jsonb_build_object('full_name', 'Olu Ops', 'department_id', v_ops, 'designation_id', v_des_o))::text, true);
  perform set_config('t.e_nia', public.create_employee(v_common || jsonb_build_object('full_name', 'Nia Noportal', 'department_id', v_sales,
                                                                                      'designation_id', v_des_s, 'email', 'nia@alpha.test'))::text, true);
  perform set_config('t.u_hr', public.grant_portal_access(current_setting('t.e_hr')::uuid, 'hana@alpha.test', null, 'Passw0rd1',
                                (select id from public.roles where system_key = 'hr_manager'))::text, true);
  perform set_config('t.u_mona', public.grant_portal_access(current_setting('t.e_mona')::uuid, 'mona@alpha.test', null, 'Passw0rd1',
                                  (select id from public.roles where system_key = 'manager'))::text, true);
  perform set_config('t.u_sam', public.grant_portal_access(current_setting('t.e_sam')::uuid, 'sam@alpha.test', null, 'Passw0rd1', null)::text, true);
  perform set_config('t.u_olu', public.grant_portal_access(current_setting('t.e_olu')::uuid, 'olu@alpha.test', null, 'Passw0rd1', null)::text, true);
end $$;

-- ======================================================= 1. HR publishes to everyone
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_id uuid;
  v jsonb;
begin
  v_id := public.save_notice(null, jsonb_build_object('category', 'policy_update', 'title', 'Leave policy 2027', 'title_bn', 'ছুটির নীতি ২০২৭',
            'body', 'Casual leave is **10 days**.', 'audience', 'all', 'requires_ack', true, 'pinned', true));
  perform set_config('t.n_all', v_id::text, true);
  assert (select x ->> 'shown_status' from jsonb_array_elements(public.list_notices_manage() -> 'notices') x where x ->> 'id' = v_id::text) = 'draft',
         'saved as a draft';
  v := public.publish_notice(v_id, null);
  assert v ->> 'status' = 'active', 'published now ' || v::text;
  begin
    perform public.publish_notice(v_id, null);
    raise exception 'FAIL: published twice';
  exception when check_violation then null;
  end;
  raise notice 'PASS: HR saves a draft and publishes it to everyone';
end $$;

select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_all')) = 1, 'Sam sees it';
  begin
    perform public.save_notice(null, '{"title":"My own","body":"x"}');
    raise exception 'FAIL: an employee published';
  exception when insufficient_privilege then null;
  end;
end $$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000c1003","role":"authenticated"}', true);
do $$
begin
  assert jsonb_array_length(public.my_notices()) = 0, 'Beta sees no Alpha notice';
  begin
    perform public.open_notice(current_setting('t.n_all')::uuid);
    raise exception 'FAIL: Beta opened an Alpha notice';
  exception when no_data_found then null;
  end;
  raise notice 'PASS: the audience sees it, other companies never do, employees cannot publish';
end $$;

-- ======================================================= 2. Manager: own department only
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v_id uuid;
begin
  v_id := public.save_notice(null, '{"title":"Sales meeting Sunday","body":"10 am, room 3","audience":"all"}');
  perform set_config('t.n_sales', v_id::text, true);
  assert (select x ->> 'audience' = 'department' and x -> 'department_ids' = jsonb_build_array(current_setting('t.sales'))
          from jsonb_array_elements(public.list_notices_manage() -> 'notices') x where x ->> 'id' = v_id::text),
         'a manager notice always targets their own department';
  perform public.publish_notice(v_id, null);
  begin
    perform public.save_notice(current_setting('t.n_all')::uuid, '{"title":"Hacked","body":"x"}');
    raise exception 'FAIL: a manager edited HR''s notice';
  exception when insufficient_privilege then null;
  end;
  assert jsonb_array_length(public.list_notices_manage() -> 'notices') = 1, 'the manager lists only their own notice';
  assert not (public.list_notices_manage() ->> 'can_target_all')::boolean, 'the manager cannot target everyone';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_sales')) = 0, 'Ops does not see Sales';
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_all')) = 1, 'Ops sees the all-staff notice';
  raise notice 'PASS: a manager publishes only to their department and cannot touch other notices';
end $$;

-- ======================================================= 3. read receipts
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v jsonb;
begin
  v := public.open_notice(current_setting('t.n_sales')::uuid);
  assert (v ->> 'read')::boolean and (v ->> 'in_audience')::boolean, 'opening records the read';
  v := public.open_notice(current_setting('t.n_sales')::uuid);
  assert (v ->> 'read')::boolean, 'still read after the second open';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_mona')), true);
do $$
declare
  v jsonb := public.notice_receipts(current_setting('t.n_sales')::uuid);
  n jsonb := (select x from jsonb_array_elements(public.list_notices_manage() -> 'notices') x where x ->> 'id' = current_setting('t.n_sales'));
begin
  -- Sales: Mona, Sam, Nia = 3 targets; Mona and Sam have portal access; Sam read it.
  assert jsonb_array_length(v) = 3, 'three Sales targets ' || v::text;
  assert (select count(*) from jsonb_array_elements(v) x where x ->> 'first_read_at' is not null) = 1, 'one read (opening twice counts once)';
  assert (select not (x ->> 'has_portal')::boolean from jsonb_array_elements(v) x where x ->> 'full_name' = 'Nia Noportal'), 'Nia has no portal';
  assert (n ->> 'targets')::int = 3 and (n ->> 'portal')::int = 2 and (n ->> 'reads')::int = 1, 'reach ' || n::text;
  raise notice 'PASS: the first open is a read receipt; receipts list every target with portal status';
end $$;

-- ======================================================= 4. acknowledgements
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
do $$
declare
  v_first timestamptz;
  v_again timestamptz;
begin
  v_first := public.acknowledge_notice(current_setting('t.n_all')::uuid);
  perform pg_sleep(0.01);
  v_again := public.acknowledge_notice(current_setting('t.n_all')::uuid);
  assert v_first = v_again, 'the acknowledgement time never changes';
  assert (select (x ->> 'read')::boolean from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_all')),
         'acknowledging also counts as read';
  begin
    perform public.acknowledge_notice(current_setting('t.n_sales')::uuid);
    raise exception 'FAIL: acknowledged a notice that needs none';
  exception when check_violation then null;
  end;
  raise notice 'PASS: an acknowledgement is given once and cannot change';
end $$;

-- ======================================================= 5. scheduled notice
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_id uuid;
begin
  v_id := public.save_notice(null, jsonb_build_object('title', 'Eid holiday', 'body', 'Office closed', 'audience', 'all',
                                                      'publish_at', now() + interval '2 days'));
  perform set_config('t.n_sched', v_id::text, true);
  assert (public.publish_notice(v_id, null)) ->> 'status' = 'scheduled', 'scheduled';
  begin
    perform public.save_notice(null, jsonb_build_object('title', 'Bad dates', 'body', 'x', 'audience', 'all',
                                                        'publish_at', now() + interval '2 days', 'expires_at', now() + interval '1 day'));
    raise exception 'FAIL: expiry before publish accepted';
  exception when invalid_parameter_value then null;
  end;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_sched')) = 0, 'hidden before its time';
end $$;
reset role;
update public.notices set publish_at = now() - interval '1 minute' where id = current_setting('t.n_sched')::uuid;
set local role authenticated;
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_sched')) = 1, 'visible once due';
  raise notice 'PASS: a scheduled notice stays hidden until its time; expiry must follow publish';
end $$;

-- ======================================================= 6. email copy and reminders
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v_id uuid;
  v jsonb;
begin
  v_id := public.save_notice(null, '{"title":"Fire drill","body":"Thursday 3 pm","audience":"all","email_copy":true,"requires_ack":true,"category":"safety"}');
  v := public.publish_notice(v_id, 'https://hr.alpha.test');
  assert v ->> 'email_skipped' like 'The company has no working email channel%', 'no channel reported ' || v::text;
  assert (v ->> 'emails_queued')::int = 0, 'nothing queued without a channel';
end $$;
reset role;
insert into public.org_messaging (org_id, channel, provider, enabled, config, secret_enc, secret_last4)
values (current_setting('t.org')::uuid, 'email', 'resend', true, '{"from_name":"Alpha","from_address":"hr@alpha.test"}',
        private.encrypt_secret('re_test_key'), 'tkey');
set local role authenticated;
do $$
declare
  v_id uuid;
  v jsonb;
begin
  v_id := public.save_notice(null, '{"title":"Safety shoes","body":"Wear them on the floor","audience":"all","email_copy":true,"requires_ack":true,"category":"safety"}');
  perform set_config('t.n_mail', v_id::text, true);
  v := public.publish_notice(v_id, 'https://hr.alpha.test');
  -- Targets: Alpha Owner (admin employee), Hana, Mona, Sam, Olu, Nia = 6, all with an address (login or employee email).
  assert (v ->> 'emails_queued')::int = 6, 'one email per target ' || v::text;
  assert (select count(*) from jsonb_array_elements(public.claim_notifications(50) -> 'items') x
          where x ->> 'body' like '%/notices?open=' || v_id || '%') = 6, 'HR can push the outbox; emails carry the link';
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_sam')), true);
select public.acknowledge_notice(current_setting('t.n_mail')::uuid);
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  v jsonb;
begin
  v := public.remind_notice_ack(current_setting('t.n_mail')::uuid, null);
  assert (v ->> 'emails_queued')::int = 5, 'reminder skips Sam who acknowledged ' || v::text;
  begin
    perform public.remind_notice_ack(current_setting('t.n_mail')::uuid, null);
    raise exception 'FAIL: two reminders within 24 hours';
  exception when check_violation then null;
  end;
  raise notice 'PASS: email copy needs a channel, goes to every target, reminders skip acknowledged people once a day';
end $$;

-- ======================================================= 7. alerts, archive, KPIs
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
declare
  v jsonb := public.my_notice_alerts();
begin
  -- Olu: n_all (pinned, ack), n_sched, fire drill (ack), n_mail (ack) all unread; nothing acknowledged.
  assert jsonb_array_length(v -> 'pinned') = 1, 'one pinned ' || v::text;
  assert (v ->> 'unread')::int = 4 and (v ->> 'pending_ack')::int = 3, 'unread and pending ' || v::text;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_hr')), true);
do $$
declare
  k jsonb;
begin
  perform public.archive_notice(current_setting('t.n_sched')::uuid);
  begin
    perform public.save_notice(current_setting('t.n_sched')::uuid, '{"title":"Changed","body":"x"}');
    raise exception 'FAIL: changed an archived notice';
  exception when check_violation then null;
  end;
  k := public.list_notices_manage() -> 'kpis';
  -- Not archived: n_all, n_sales, fire drill, n_mail = 4; active 4; pinned 1.
  assert (k ->> 'total')::int = 4 and (k ->> 'active')::int = 4 and (k ->> 'pinned')::int = 1, 'kpis ' || k::text;
end $$;
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('t.u_olu')), true);
do $$
begin
  assert (select count(*) from jsonb_array_elements(public.my_notices()) x where x ->> 'id' = current_setting('t.n_sched')) = 0, 'archived notices disappear';
  raise notice 'PASS: dashboard alerts, archive freezes and hides a notice, KPIs count the rest';
end $$;

select '==== ALL COMM C1 NOTICE CHECKS PASSED ====' as result;
rollback;
