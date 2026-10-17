-- =============================================================================
-- Platform (SaaS) administration checks: landing-page applications, platform
-- admin dashboard, subscriptions, payments, organization activation.
-- Run the whole file in the SQL editor; it rolls back.
-- Expect "ALL PLATFORM CHECKS PASSED".
-- =============================================================================
begin;

-- Platform admin, and three applicants signing up from the landing page.
insert into auth.users (id, aud, role, email, email_confirmed_at, raw_user_meta_data, created_at, updated_at) values
  ('00000000-0000-0000-0000-0000000000f1', 'authenticated', 'authenticated', 'pa@olympus.test', now(),
   '{"full_name":"Platform Admin"}', now(), now()),
  -- Complete application.
  ('00000000-0000-0000-0000-0000000000f2', 'authenticated', 'authenticated', 'owner@delta.test', now(),
   '{"full_name":"Delta Owner","org_application":{"org_name":"Delta Garments Ltd","contact_phone":"01712000002",
     "employee_range":"101-500","industry":"Apparel","address":"Plot 7, Ashulia, Savar","plan_interest":"PRO"}}', now(), now()),
  -- Bad phone and bad range: application kept, the bad values dropped.
  ('00000000-0000-0000-0000-0000000000f3', 'authenticated', 'authenticated', 'owner@echo.test', null,
   '{"full_name":"Echo Owner","org_application":{"org_name":"Echo Knit","contact_phone":"12345","employee_range":"lots"}}', now(), now()),
  -- No organization name: the account is created, no application.
  ('00000000-0000-0000-0000-0000000000f4', 'authenticated', 'authenticated', 'owner@foxtrot.test', now(),
   '{"full_name":"Foxtrot Owner","org_application":{"org_name":""}}', now(), now());
insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-0000000000f1');

do $$
declare
  v_req public.org_signup_requests;
begin
  select * into v_req from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f2';
  assert v_req.status = 'pending', 'landing-page signup creates a pending application';
  assert v_req.org_name = 'Delta Garments Ltd' and v_req.contact_phone = '+8801712000002'
     and v_req.employee_range = '101-500' and v_req.plan_interest = 'PRO', 'application keeps the details';
  select * into v_req from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f3';
  assert v_req.id is not null and v_req.contact_phone is null and v_req.employee_range is null,
    'invalid values are dropped, the application is kept';
  assert not exists (select 1 from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f4'),
    'no organization name -> no application';
  assert exists (select 1 from public.user_profiles where id = '00000000-0000-0000-0000-0000000000f4'),
    'the account itself is still created';
  raise notice 'PASS applications: created from the registration form, validated, never blocking signup';
end $$;

-- Anonymous visitors can read the public plans; nothing else.
set local role anon;
do $$
begin
  assert (select count(*) from public.get_public_plans()) = 4, 'four public plans';
  begin
    perform public.platform_overview();
    raise exception 'FAIL: anon reached the platform overview';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS landing: public plans readable without login; platform data is not';
end $$;
reset role;

-- A normal user is not a platform admin.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.platform_overview();
    raise exception 'FAIL: applicant read the platform overview';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.platform_record_payment(gen_random_uuid(), current_date, current_date, 1, current_date, 'paid', current_date);
    raise exception 'FAIL: applicant recorded a payment';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: only platform admins use platform RPCs';
end $$;

-- Platform admin reviews the applications.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
do $$
declare
  v_list jsonb := public.platform_list_applications('pending');
  v_org  uuid;
begin
  assert jsonb_array_length(v_list) >= 2, 'pending applications listed';
  assert (select (x ->> 'email_confirmed')::boolean from jsonb_array_elements(v_list) x
          where x ->> 'applicant_email' = 'owner@echo.test') = false, 'unconfirmed email is shown';

  begin
    perform public.reject_org_signup_request(
      (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f3'), '');
    raise exception 'FAIL: reject without remarks';
  exception when invalid_parameter_value then null;
  end;
  perform public.reject_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f3'),
    'Please give a valid phone number and employee count');

  v_org := public.approve_org_signup_request(
    (select id from public.org_signup_requests where applicant_user_id = '00000000-0000-0000-0000-0000000000f2'));
  perform set_config('t.org', v_org::text, true);

  assert (public.platform_overview() -> 'applications' ->> 'rejected')::int >= 1, 'rejected counted';
  assert (public.platform_overview() -> 'applications' ->> 'approved')::int >= 1, 'approved counted';
  raise notice 'PASS review: reject needs remarks; approve creates the organization';
end $$;

do $$
declare
  v_org     uuid := current_setting('t.org')::uuid;
  v_details jsonb;
begin
  v_details := public.platform_organization_details(v_org);
  assert v_details -> 'subscription' ->> 'plan_code' = 'TRIAL' and v_details -> 'subscription' ->> 'status' = 'trial',
    'a new organization starts on the trial';
  assert (v_details -> 'employees' ->> 'active')::int = 1, 'employee volume: the owner';
  assert v_details -> 'application' ->> 'industry' = 'Apparel', 'application details shown';
  assert v_details ->> 'payment_status' = 'none', 'no payments yet';

  -- An invoice that is past its due date shows as overdue.
  perform set_config('t.pay', public.platform_record_payment(v_org, '2026-09-01', '2026-09-30', 12500, '2026-10-05', 'due')::text, true);
  assert public.platform_organization_details(v_org) ->> 'payment_status' = 'overdue', 'past due date -> overdue';
  begin
    perform public.platform_update_payment(current_setting('t.pay')::uuid, 'paid');
    raise exception 'FAIL: paid without a date';
  exception when not_null_violation then null;
  end;
  perform public.platform_update_payment(current_setting('t.pay')::uuid, 'paid', current_date, 'bkash', 'TX-123');
  v_details := public.platform_organization_details(v_org);
  assert v_details ->> 'payment_status' = 'paid', 'paid after update';
  assert (v_details -> 'payment_totals' ->> 'paid')::numeric = 12500, 'paid total';

  perform public.platform_update_subscription(v_org, 'PRO', 'active', 'monthly', 300, 60, '2026-11-30', 'Signed yearly contract');
  assert public.platform_organization_details(v_org) -> 'subscription' ->> 'plan_code' = 'PRO', 'plan changed';
  begin
    perform public.platform_update_subscription(v_org, 'GOLD', 'active', 'monthly', 10, 1, null);
    raise exception 'FAIL: unknown plan accepted';
  exception when invalid_parameter_value then null;
  end;
  raise notice 'PASS details: employee volume, trial subscription, payments (overdue -> paid), plan change';

  begin
    perform public.platform_set_organization_status(v_org, 'suspended', '');
    raise exception 'FAIL: deactivated without a reason';
  exception when not_null_violation then null;
  end;
  perform public.platform_set_organization_status(v_org, 'suspended', 'Payment overdue for 60 days');
  assert (select status from public.organizations where id = v_org) = 'suspended', 'organization suspended';
end $$;

-- The owner of a suspended organization loses access immediately.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
do $$
begin
  assert (public.get_my_context() -> 'organization') = 'null'::jsonb, 'suspended organization: no access';
  begin
    perform 1 from public.org_payments;
    raise exception 'FAIL: org user read payments table';
  exception when insufficient_privilege then null;
  end;
  raise notice 'PASS: a non-active organization loses access; billing tables stay closed to org users';
end $$;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
select public.platform_set_organization_status(current_setting('t.org')::uuid, 'active', null);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f2","role":"authenticated"}', true);
do $$
begin
  assert (public.get_my_context() -> 'organization' ->> 'id')::uuid = current_setting('t.org')::uuid, 'reactivated';
  raise notice 'PASS: reactivation restores access';
end $$;

reset role;
do $$
begin
  assert exists (select 1 from public.audit_logs where action = 'platform.organization_status'), 'status change audited';
  assert exists (select 1 from public.audit_logs where entity = 'org_payments' and action = 'update'), 'payment change audited';
end $$;

do $$ begin raise notice '==== ALL PLATFORM CHECKS PASSED ===='; end $$;
select '==== ALL PLATFORM CHECKS PASSED ====' as result;
rollback;
