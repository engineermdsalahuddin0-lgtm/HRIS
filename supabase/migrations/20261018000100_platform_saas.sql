-- =============================================================================
-- Olympus HRIS — Platform (SaaS) administration
--
-- What this adds:
--   * Richer organization applications, submitted straight from the public
--     landing page together with the applicant's admin account.
--   * Subscription plans, one subscription per organization (every new
--     organization starts on a trial) and manually recorded payments.
--     There is no payment gateway yet; platform admins record payments.
--   * Platform-admin RPCs: organization overview, organization details
--     (employee volume, subscription, payments), activate / deactivate an
--     organization, change the subscription, record and update payments.
--
-- Security model:
--   * Plan catalogue: public plans are readable by anyone (landing page).
--   * Subscriptions and payments: base tables are closed to API roles; only
--     platform admins reach them, through the RPCs below.
--   * Every platform action is written to the audit log of the organization
--     it concerns, so billing changes stay traceable.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Organization applications: extra details collected on the landing page
-- -----------------------------------------------------------------------------
alter table public.org_signup_requests
  add column employee_range text check (employee_range in ('1-25', '26-100', '101-500', '501-1000', '1000+')),
  add column industry       text check (industry is null or char_length(btrim(industry)) between 2 and 80),
  add column address        text check (address is null or char_length(btrim(address)) between 5 and 300),
  add column plan_interest  text check (plan_interest is null or plan_interest ~ '^[A-Z_]{2,20}$');

-- Creates a pending application from the metadata the registration form sends
-- with supabase.auth.signUp(). The metadata is user-supplied, so every value is
-- validated here; a bad application never blocks the account itself (the
-- applicant can still apply later from the onboarding screen).
create or replace function private.create_application_from_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_application jsonb := new.raw_user_meta_data -> 'org_application';
  v_org_name    text;
  v_contact     text;
  v_phone       text;
  v_range       text;
begin
  if v_application is null or jsonb_typeof(v_application) <> 'object' then
    return new;
  end if;

  v_org_name := nullif(btrim(v_application ->> 'org_name'), '');
  v_contact  := coalesce(nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''), v_org_name);
  v_range    := v_application ->> 'employee_range';

  -- An unreadable phone number is dropped rather than losing the whole application.
  begin
    v_phone := private.normalize_bd_phone(v_application ->> 'contact_phone');
  exception when others then
    v_phone := null;
  end;

  begin
    insert into public.org_signup_requests (
      applicant_user_id, org_name, contact_name, contact_phone, employee_range, industry, address, plan_interest)
    values (
      new.id, left(v_org_name, 200), left(v_contact, 120), v_phone,
      case when v_range in ('1-25', '26-100', '101-500', '501-1000', '1000+') then v_range end,
      nullif(left(btrim(v_application ->> 'industry'), 80), ''),
      nullif(left(btrim(v_application ->> 'address'), 300), ''),
      case when (v_application ->> 'plan_interest') ~ '^[A-Z_]{2,20}$' then v_application ->> 'plan_interest' end);
  exception when others then
    -- Invalid application data: keep the account, skip the application.
    raise warning 'Organization application skipped for user %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

-- Fires after on_auth_user_created (triggers run in name order), so the
-- applicant's user_profiles row already exists.
create trigger on_auth_user_signup_application
  after insert on auth.users
  for each row execute function private.create_application_from_signup();

-- -----------------------------------------------------------------------------
-- 2. Plans, subscriptions and payments
-- -----------------------------------------------------------------------------
create table public.platform_plans (
  id                 uuid primary key default gen_random_uuid(),
  code               text not null unique check (code ~ '^[A-Z_]{2,20}$'),
  name               text not null check (char_length(btrim(name)) between 2 and 60),
  tagline            text,
  price_per_employee numeric(10, 2) check (price_per_employee is null or price_per_employee >= 0), -- null = contact sales
  max_employees      integer check (max_employees is null or max_employees > 0),                  -- null = unlimited
  trial_days         smallint check (trial_days is null or trial_days between 1 and 90),
  features           text[] not null default '{}',
  is_public          boolean not null default true,
  sort_order         smallint not null default 0,
  status             text not null default 'active' check (status in ('active', 'inactive')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

insert into public.platform_plans (code, name, tagline, price_per_employee, max_employees, trial_days, features, sort_order) values
  ('TRIAL', 'Free trial', 'Try everything with your own team', 0, 25, 30,
   array['Up to 25 employees', 'Employees, attendance and leave', 'Web, GPS and QR check-in', 'Email support'], 1),
  ('BASIC', 'Basic', 'Core HR for growing companies', null, 100, null,
   array['Up to 100 employees', 'Everything in the trial', 'Shifts, rosters and overtime', 'Roles and field-level access'], 2),
  ('PRO', 'Professional', 'HR, attendance and payroll in one place', null, 1000, null,
   array['Up to 1,000 employees', 'Everything in Basic', 'Salary structure and payroll', 'Audit log and approvals'], 3),
  ('ENTERPRISE', 'Enterprise', 'For groups and large factories', null, null, null,
   array['Unlimited employees', 'Everything in Professional', 'Multiple branches and factories', 'Priority support and onboarding'], 4)
on conflict (code) do nothing;

create table public.org_subscriptions (
  org_id             uuid primary key references public.organizations (id),
  plan_id            uuid not null references public.platform_plans (id),
  status             text not null default 'trial'
                     check (status in ('trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired')),
  billing_cycle      text not null default 'monthly' check (billing_cycle in ('monthly', 'yearly')),
  seats              integer check (seats is null or seats > 0),                       -- licensed employees
  price_per_employee numeric(10, 2) check (price_per_employee is null or price_per_employee >= 0),
  started_on         date not null default current_date,
  current_period_end date,
  trial_ends_on      date,
  note               text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id)
);

create table public.org_payments (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  period_start date not null,
  period_end   date not null,
  amount       numeric(12, 2) not null check (amount >= 0),
  currency     text not null default 'BDT' check (currency = 'BDT'),
  status       text not null default 'due' check (status in ('due', 'paid', 'overdue', 'waived', 'refunded')),
  due_date     date not null,
  paid_on      date,
  method       text check (method in ('bank', 'bkash', 'nagad', 'rocket', 'card', 'cash', 'other')),
  reference    text check (reference is null or char_length(reference) <= 120),
  note         text check (note is null or char_length(note) <= 500),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint org_payments_period check (period_end >= period_start),
  constraint org_payments_paid_has_date check (status <> 'paid' or paid_on is not null)
);
create index org_payments_org_idx on public.org_payments (org_id, period_start desc);

create trigger touch before update on public.platform_plans
  for each row execute function private.touch_updated_at();
create trigger set_row_meta before insert or update on public.org_subscriptions
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.org_subscriptions
  for each row execute function private.audit_row_change();
create trigger set_row_meta before insert or update on public.org_payments
  for each row execute function private.set_row_meta();
create trigger no_delete before delete on public.org_payments
  for each row execute function private.prevent_delete();
create trigger audit after insert or update or delete on public.org_payments
  for each row execute function private.audit_row_change();

-- Every new organization starts on the trial plan.
create or replace function private.start_trial_subscription()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trial public.platform_plans;
begin
  select * into v_trial from public.platform_plans where code = 'TRIAL';
  if v_trial.id is not null then
    insert into public.org_subscriptions (org_id, plan_id, status, seats, price_per_employee, trial_ends_on, current_period_end)
    values (new.id, v_trial.id, 'trial', v_trial.max_employees, v_trial.price_per_employee,
            current_date + coalesce(v_trial.trial_days, 30), current_date + coalesce(v_trial.trial_days, 30))
    on conflict (org_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger start_trial_subscription after insert on public.organizations
  for each row execute function private.start_trial_subscription();

-- Organizations that existed before this migration get a trial too.
insert into public.org_subscriptions (org_id, plan_id, status, seats, price_per_employee, trial_ends_on, current_period_end)
select o.id, p.id, 'trial', p.max_employees, p.price_per_employee,
       current_date + coalesce(p.trial_days, 30), current_date + coalesce(p.trial_days, 30)
from public.organizations o
cross join public.platform_plans p
where p.code = 'TRIAL'
on conflict (org_id) do nothing;

-- Payment status of an organization, derived from its payment records:
-- overdue > due > paid > none.
create or replace function private.org_payment_status(p_org_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.org_payments
                 where org_id = p_org_id and (status = 'overdue' or (status = 'due' and due_date < current_date))) then 'overdue'
    when exists (select 1 from public.org_payments where org_id = p_org_id and status = 'due') then 'due'
    when exists (select 1 from public.org_payments where org_id = p_org_id and status = 'paid') then 'paid'
    else 'none'
  end
$$;

create or replace function private.require_platform_admin()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_admin() then
    raise exception 'Only a platform admin can do this' using errcode = '42501';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 3. Public RPC: plans shown on the landing page (no login needed)
-- -----------------------------------------------------------------------------
create or replace function public.get_public_plans()
returns table (code text, name text, tagline text, price_per_employee numeric, max_employees integer,
               trial_days smallint, features text[])
language sql
stable
security definer
set search_path = ''
as $$
  select p.code, p.name, p.tagline, p.price_per_employee, p.max_employees, p.trial_days, p.features
  from public.platform_plans p
  where p.is_public and p.status = 'active'
  order by p.sort_order
$$;

-- -----------------------------------------------------------------------------
-- 4. Platform-admin RPCs
-- -----------------------------------------------------------------------------

-- Dashboard: application counts and one row per organization.
create or replace function public.platform_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_platform_admin();
  return jsonb_build_object(
    'applications', (
      select jsonb_build_object(
        'pending',  count(*) filter (where status = 'pending'),
        'approved', count(*) filter (where status = 'approved'),
        'rejected', count(*) filter (where status = 'rejected'))
      from public.org_signup_requests),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id, 'name', o.name, 'org_code', o.org_code, 'status', o.status, 'created_at', o.created_at,
        'active_employees', (select count(*) from public.employees e where e.org_id = o.id and e.status = 'active'),
        'plan_name', p.name, 'subscription_status', s.status,
        'payment_status', private.org_payment_status(o.id))
        order by o.created_at desc)
      from public.organizations o
      left join public.org_subscriptions s on s.org_id = o.id
      left join public.platform_plans p on p.id = s.plan_id), '[]'::jsonb));
end;
$$;

-- Full details of one organization for the platform admin.
create or replace function public.platform_organization_details(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org public.organizations;
begin
  perform private.require_platform_admin();
  select * into v_org from public.organizations where id = p_org_id;
  if not found then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'organization', jsonb_build_object(
      'id', v_org.id, 'name', v_org.name, 'org_code', v_org.org_code, 'status', v_org.status,
      'timezone', v_org.timezone, 'created_at', v_org.created_at,
      'labor_regime', (select labor_regime from public.org_work_settings where org_id = v_org.id)),
    'application', (
      select jsonb_build_object(
        'contact_name', r.contact_name, 'contact_phone', r.contact_phone, 'employee_range', r.employee_range,
        'industry', r.industry, 'address', r.address, 'plan_interest', r.plan_interest,
        'submitted_at', r.created_at, 'reviewed_at', r.reviewed_at, 'applicant_email', u.email)
      from public.org_signup_requests r
      join public.user_profiles u on u.id = r.applicant_user_id
      where r.organization_id = v_org.id
      order by r.created_at desc limit 1),
    'admins', coalesce((
      select jsonb_agg(jsonb_build_object('full_name', u.full_name, 'email', u.email, 'phone', u.phone,
                                          'last_login_at', u.last_login_at) order by u.full_name)
      from public.org_members m
      join public.roles r on r.id = m.role_id and r.system_key = 'admin'
      join public.user_profiles u on u.id = m.user_id
      where m.org_id = v_org.id and m.status = 'active'), '[]'::jsonb),
    'employees', (
      select jsonb_build_object(
        'total',      count(*),
        'active',     count(*) filter (where e.status = 'active'),
        'inactive',   count(*) filter (where e.status = 'inactive'),
        'terminated', count(*) filter (where e.status = 'terminated'),
        'portal_users', (select count(*) from public.org_members m
                         where m.org_id = v_org.id and m.status = 'active'),
        'departments', (select count(*) from public.departments d where d.org_id = v_org.id and d.status = 'active'),
        'branches',    (select count(*) from public.branches b where b.org_id = v_org.id and b.status = 'active'))
      from public.employees e where e.org_id = v_org.id),
    'subscription', (
      select jsonb_build_object(
        'plan_code', p.code, 'plan_name', p.name, 'status', s.status, 'billing_cycle', s.billing_cycle,
        'seats', s.seats, 'price_per_employee', s.price_per_employee, 'started_on', s.started_on,
        'current_period_end', s.current_period_end, 'trial_ends_on', s.trial_ends_on, 'note', s.note)
      from public.org_subscriptions s
      join public.platform_plans p on p.id = s.plan_id
      where s.org_id = v_org.id),
    'payment_status', private.org_payment_status(v_org.id),
    'payments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pay.id, 'period_start', pay.period_start, 'period_end', pay.period_end, 'amount', pay.amount,
        'status', case when pay.status = 'due' and pay.due_date < current_date then 'overdue' else pay.status end,
        'due_date', pay.due_date, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference,
        'note', pay.note)
        order by pay.period_start desc, pay.created_at desc)
      from public.org_payments pay where pay.org_id = v_org.id), '[]'::jsonb),
    'payment_totals', (
      select jsonb_build_object(
        'paid',        coalesce(sum(amount) filter (where status = 'paid'), 0),
        'outstanding', coalesce(sum(amount) filter (where status in ('due', 'overdue')), 0))
      from public.org_payments where org_id = v_org.id));
end;
$$;

-- Activate or deactivate an organization. A non-active organization's users
-- lose access on their next request (active_membership requires an active org).
create or replace function public.platform_set_organization_status(p_org_id uuid, p_status text, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_status text;
begin
  perform private.require_platform_admin();
  if p_status not in ('active', 'suspended', 'inactive') then
    raise exception 'Status must be active, suspended or inactive' using errcode = '22023';
  end if;
  if p_status <> 'active' and nullif(btrim(p_note), '') is null then
    raise exception 'A reason is required to deactivate an organization' using errcode = '23502';
  end if;
  select status into v_old_status from public.organizations where id = p_org_id for update;
  if not found then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;
  update public.organizations set status = p_status where id = p_org_id;
  perform private.write_audit(p_org_id, 'platform.organization_status', 'organizations', p_org_id,
    jsonb_build_object('status', v_old_status),
    jsonb_build_object('status', p_status, 'note', nullif(btrim(p_note), '')));
end;
$$;

-- Change plan / status / period of an organization's subscription.
create or replace function public.platform_update_subscription(
  p_org_id             uuid,
  p_plan_code          text,
  p_status             text,
  p_billing_cycle      text,
  p_seats              integer,
  p_price_per_employee numeric,
  p_current_period_end date,
  p_note               text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan public.platform_plans;
begin
  perform private.require_platform_admin();
  select * into v_plan from public.platform_plans where code = upper(btrim(p_plan_code));
  if not found then
    raise exception 'Unknown plan %', p_plan_code using errcode = '22023';
  end if;
  if p_status not in ('trial', 'active', 'past_due', 'suspended', 'cancelled', 'expired') then
    raise exception 'Unknown subscription status %', p_status using errcode = '22023';
  end if;
  if p_billing_cycle not in ('monthly', 'yearly') then
    raise exception 'Billing cycle must be monthly or yearly' using errcode = '22023';
  end if;
  if p_seats is not null and p_seats <= 0 then
    raise exception 'Seats must be a positive number' using errcode = '22023';
  end if;
  if p_price_per_employee is not null and p_price_per_employee < 0 then
    raise exception 'Price cannot be negative' using errcode = '22023';
  end if;
  if not exists (select 1 from public.organizations where id = p_org_id) then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;

  insert into public.org_subscriptions as s (org_id, plan_id, status, billing_cycle, seats, price_per_employee,
                                             current_period_end, note)
  values (p_org_id, v_plan.id, p_status, p_billing_cycle, p_seats, p_price_per_employee, p_current_period_end,
          nullif(btrim(p_note), ''))
  on conflict (org_id) do update
    set plan_id = excluded.plan_id, status = excluded.status, billing_cycle = excluded.billing_cycle,
        seats = excluded.seats, price_per_employee = excluded.price_per_employee,
        current_period_end = excluded.current_period_end, note = excluded.note;
end;
$$;

-- Record a payment (or an invoice that is still due) for an organization.
create or replace function public.platform_record_payment(
  p_org_id       uuid,
  p_period_start date,
  p_period_end   date,
  p_amount       numeric,
  p_due_date     date,
  p_status       text,
  p_paid_on      date default null,
  p_method       text default null,
  p_reference    text default null,
  p_note         text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment_id uuid;
begin
  perform private.require_platform_admin();
  if not exists (select 1 from public.organizations where id = p_org_id) then
    raise exception 'Organization not found' using errcode = 'P0002';
  end if;
  if p_amount is null or p_amount < 0 then
    raise exception 'Amount must be zero or more' using errcode = '22023';
  end if;
  if p_period_start is null or p_period_end is null or p_period_end < p_period_start then
    raise exception 'The billing period is not valid' using errcode = '22023';
  end if;
  if p_status not in ('due', 'paid', 'overdue', 'waived', 'refunded') then
    raise exception 'Unknown payment status %', p_status using errcode = '22023';
  end if;
  if p_status = 'paid' and p_paid_on is null then
    raise exception 'Give the date the payment was received' using errcode = '23502';
  end if;
  if p_method is not null and p_method not in ('bank', 'bkash', 'nagad', 'rocket', 'card', 'cash', 'other') then
    raise exception 'Unknown payment method %', p_method using errcode = '22023';
  end if;

  insert into public.org_payments (org_id, period_start, period_end, amount, due_date, status, paid_on, method,
                                   reference, note)
  values (p_org_id, p_period_start, p_period_end, round(p_amount, 2), coalesce(p_due_date, p_period_start),
          p_status, p_paid_on, p_method, nullif(left(btrim(p_reference), 120), ''), nullif(left(btrim(p_note), 500), ''))
  returning id into v_payment_id;
  return v_payment_id;
end;
$$;

-- Mark a recorded payment as paid / waived / refunded (or back to due).
create or replace function public.platform_update_payment(
  p_payment_id uuid,
  p_status     text,
  p_paid_on    date default null,
  p_method     text default null,
  p_reference  text default null,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_platform_admin();
  if p_status not in ('due', 'paid', 'overdue', 'waived', 'refunded') then
    raise exception 'Unknown payment status %', p_status using errcode = '22023';
  end if;
  if p_status = 'paid' and p_paid_on is null then
    raise exception 'Give the date the payment was received' using errcode = '23502';
  end if;
  if p_method is not null and p_method not in ('bank', 'bkash', 'nagad', 'rocket', 'card', 'cash', 'other') then
    raise exception 'Unknown payment method %', p_method using errcode = '22023';
  end if;
  update public.org_payments
     set status = p_status,
         paid_on = case when p_status = 'paid' then p_paid_on else paid_on end,
         method = coalesce(p_method, method),
         reference = coalesce(nullif(left(btrim(p_reference), 120), ''), reference),
         note = coalesce(nullif(left(btrim(p_note), 500), ''), note)
   where id = p_payment_id;
  if not found then
    raise exception 'Payment not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Applications list for the review screen, with whether the applicant has
-- confirmed their email (approval works either way; login needs confirmation).
create or replace function public.platform_list_applications(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_platform_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'org_name', r.org_name, 'contact_name', r.contact_name, 'contact_phone', r.contact_phone,
      'employee_range', r.employee_range, 'industry', r.industry, 'address', r.address,
      'plan_interest', r.plan_interest, 'status', r.status, 'review_note', r.review_note,
      'created_at', r.created_at, 'reviewed_at', r.reviewed_at, 'organization_id', r.organization_id,
      'applicant_email', u.email,
      'email_confirmed', au.email_confirmed_at is not null)
      order by r.created_at desc)
    from public.org_signup_requests r
    join public.user_profiles u on u.id = r.applicant_user_id
    left join auth.users au on au.id = r.applicant_user_id
    where p_status is null or r.status = p_status), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- 5. Privileges
-- -----------------------------------------------------------------------------
alter table public.platform_plans    enable row level security;
alter table public.org_subscriptions enable row level security;
alter table public.org_payments      enable row level security;
revoke all on table public.platform_plans, public.org_subscriptions, public.org_payments from anon, authenticated;

revoke all on function
  public.platform_overview(), public.platform_organization_details(uuid),
  public.platform_set_organization_status(uuid, text, text),
  public.platform_update_subscription(uuid, text, text, text, integer, numeric, date, text),
  public.platform_record_payment(uuid, date, date, numeric, date, text, date, text, text, text),
  public.platform_update_payment(uuid, text, date, text, text, text),
  public.platform_list_applications(text),
  public.get_public_plans()
from public, anon;

grant execute on function
  public.platform_overview(), public.platform_organization_details(uuid),
  public.platform_set_organization_status(uuid, text, text),
  public.platform_update_subscription(uuid, text, text, text, integer, numeric, date, text),
  public.platform_record_payment(uuid, date, date, numeric, date, text, date, text, text, text),
  public.platform_update_payment(uuid, text, date, text, text, text),
  public.platform_list_applications(text)
to authenticated;

-- The plan catalogue is public (landing page).
grant execute on function public.get_public_plans() to anon, authenticated;

revoke all on function
  private.create_application_from_signup(), private.start_trial_subscription(),
  private.org_payment_status(uuid), private.require_platform_admin()
from public, anon, authenticated;
