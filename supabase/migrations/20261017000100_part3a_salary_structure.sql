-- =============================================================================
-- Olympus HRIS — Part 3A: Salary structure
-- Salary components and templates, employee compensation history (versioned,
-- never edited), increments with maker-checker approval and arrears preview,
-- bonuses with eligibility, loans/advances, encrypted payment accounts and
-- payroll settings. The payroll engine itself is Part 3B.
--
-- Money rules: numeric(12, 2) taka everywhere (never floating point); every
-- resolved line is rounded to 2 decimals; the salary month is 30 days.
-- Access rules: salary tables are closed to API roles. Reads go through
-- security-barrier views that filter by permission; writes go through RPCs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Permissions (Part 3A)
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('compensation.view',       'payroll', 'See salary templates and employee pay',                                false),
  ('compensation.edit',       'payroll', 'Manage components and templates, set starting pay, request increments', false),
  ('increments.approve',      'payroll', 'Approve or reject salary increments (never their own request)',         false),
  ('bonuses.manage',          'payroll', 'Create and edit bonuses',                                               false),
  ('deductions.manage',       'payroll', 'Loans, advances and other deductions',                                  false),
  ('payroll_settings.manage', 'payroll', 'Payroll settings and statutory value confirmation',                     false),
  ('payment_accounts.view',   'payroll', 'See employee bank and wallet accounts (masked; revealing is audited)',  false),
  ('payment_accounts.edit',   'payroll', 'Add and change employee bank and wallet accounts',                      false)
on conflict (key) do nothing;

-- HR gets the day-to-day money permissions. Approving increments and payroll
-- settings stay with the Admin until the Admin ticks them for another role.
-- Managers and employees get no money permission (salary confidentiality).
create or replace function private.seed_payroll_permissions(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array[
      'compensation.view', 'compensation.edit', 'bonuses.manage', 'deductions.manage',
      'payment_accounts.view', 'payment_accounts.edit']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
end;
$$;

-- -----------------------------------------------------------------------------
-- Small money and date helpers
-- -----------------------------------------------------------------------------
-- Rounds to paisa (2 decimals), half away from zero — Postgres numeric rounding.
create or replace function private.round_money(p_amount numeric)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select round(p_amount, 2)
$$;

create or replace function private.month_start(p_date date)
returns date
language sql
immutable
set search_path = ''
as $$
  select date_trunc('month', p_date)::date
$$;

-- Completed months of service from the joining date up to p_as_of (inclusive).
create or replace function private.service_months(p_join_date date, p_as_of date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when p_as_of < p_join_date then 0
              else (extract(year from age(p_as_of + 1, p_join_date)) * 12
                    + extract(month from age(p_as_of + 1, p_join_date)))::int end
$$;

-- Days of a month paid on the 30-day basis when pay starts on p_from_date:
-- the days before it are not paid (at most 30). Starting on the 31st pays 0.
create or replace function private.paid_days_from(p_from_date date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select 30 - least(extract(day from p_from_date)::int - 1, 30)
$$;

-- The employee must exist in the caller's organization.
create or replace function private.assert_org_employee(p_employee_id uuid)
returns public.employees
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee public.employees;
begin
  select * into v_employee from public.employees
  where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  return v_employee;
end;
$$;

-- Nobody changes their own pay or payment data, except the Admin (the owner).
create or replace function private.assert_not_self_money(p_employee_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_employee_id = private.current_employee_id() and not private.is_org_admin() then
    raise exception 'You cannot change your own pay or payment details' using errcode = '42501';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Encryption for bank and wallet numbers. The key is generated once per
-- database and kept in the private schema, which API roles cannot read.
-- -----------------------------------------------------------------------------
create table private.app_secrets (
  name       text primary key,
  secret     text not null,
  created_at timestamptz not null default now()
);
revoke all on table private.app_secrets from public, anon, authenticated;

insert into private.app_secrets (name, secret)
values ('payment_accounts_key', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (name) do nothing;

create or replace function private.encrypt_secret(p_plain text)
returns bytea
language sql
volatile
security definer
set search_path = ''
as $$
  select case when p_plain is null then null else
    extensions.pgp_sym_encrypt(p_plain,
      (select secret from private.app_secrets where name = 'payment_accounts_key'), 'cipher-algo=aes256') end
$$;

create or replace function private.decrypt_secret(p_cipher bytea)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when p_cipher is null then null else
    extensions.pgp_sym_decrypt(p_cipher, (select secret from private.app_secrets where name = 'payment_accounts_key')) end
$$;

-- -----------------------------------------------------------------------------
-- Payroll settings (one row per organization). The month basis (30) is read
-- from org_work_settings. Statutory values are placeholders until the company
-- confirms them (statutory_confirmed_at).
-- -----------------------------------------------------------------------------
create table public.payroll_settings (
  org_id                     uuid primary key references public.organizations (id),
  deduct_base                text not null default 'basic' check (deduct_base in ('basic', 'gross')),
  ot_rate_basis              text not null default 'basic' check (ot_rate_basis in ('basic', 'gross')),
  -- Hourly overtime rate = overtime base / this divisor. A legal value the company must confirm.
  ot_hourly_divisor          numeric(6, 2) not null default 208 check (ot_hourly_divisor between 1 and 744),
  pay_weekly_off             boolean not null default true,
  pay_holidays               boolean not null default true,
  half_day_deduction_percent numeric(5, 2) not null default 50 check (half_day_deduction_percent between 0 and 100),
  unpaid_leave_base          text not null default 'basic' check (unpaid_leave_base in ('basic', 'gross')),
  -- Lines are always rounded to 2 decimals; this rule applies to the net.
  net_rounding               text not null default 'nearest_taka'
                             check (net_rounding in ('none', 'nearest_taka', 'up_taka', 'down_taka')),
  negative_net_rule          text not null default 'zero_and_carry'
                             check (negative_net_rule in ('zero_and_carry', 'block')),
  payslip_release            text not null default 'approved' check (payslip_release in ('approved', 'paid')),
  large_change_percent       numeric(5, 2) not null default 20 check (large_change_percent between 0 and 1000),
  auto_tds                   boolean not null default false,
  pf_enabled                 boolean not null default false,
  gratuity_enabled           boolean not null default false,
  statutory_confirmed_at     timestamptz,
  statutory_confirmed_by     uuid references public.user_profiles (id),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  created_by                 uuid references public.user_profiles (id),
  updated_by                 uuid references public.user_profiles (id)
);

-- Any change to a statutory value clears the confirmation, so the company has
-- to confirm the new value again.
create or replace function private.payroll_settings_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
     and (new.ot_hourly_divisor, new.half_day_deduction_percent)
         is distinct from (old.ot_hourly_divisor, old.half_day_deduction_percent)
     and new.statutory_confirmed_at is not distinct from old.statutory_confirmed_at then
    new.statutory_confirmed_at := null;
    new.statutory_confirmed_by := null;
  end if;
  return new;
end;
$$;
create trigger payroll_settings_guard before update on public.payroll_settings
  for each row execute function private.payroll_settings_guard();

-- -----------------------------------------------------------------------------
-- Salary components (catalog)
-- -----------------------------------------------------------------------------
create table public.salary_components (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null default private.current_org_id() references public.organizations (id),
  name          text not null check (char_length(btrim(name)) between 2 and 80),
  code          text not null check (code ~ '^[A-Z][A-Z0-9_]{1,15}$'),
  kind          text not null check (kind in ('earning', 'deduction')),
  calc          text not null check (calc in ('fixed', 'percent_of_basic', 'percent_of_gross')),
  default_value numeric(12, 2) not null default 0 check (default_value >= 0),
  taxable       boolean not null default true,
  pf_applicable boolean not null default false,
  -- The one Basic component per organization: its amount is the template/employee basic.
  is_basic      boolean not null default false,
  sort_order    smallint not null default 100,
  status        text not null default 'active' check (status in ('active', 'inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint salary_components_org_id_id_uq unique (org_id, id),
  constraint salary_components_org_code_uq unique (org_id, code),
  constraint salary_components_basic_shape check (not is_basic or (kind = 'earning' and calc = 'fixed')),
  constraint salary_components_percent_range check (calc = 'fixed' or default_value <= 100)
);
create unique index salary_components_one_basic_uq on public.salary_components (org_id) where is_basic;

create or replace function private.salary_components_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if new.code <> old.code or new.is_basic <> old.is_basic then
      raise exception 'A component code cannot be changed' using errcode = '23514';
    end if;
    if old.is_basic and (new.status <> 'active' or new.kind <> old.kind or new.calc <> old.calc) then
      raise exception 'The Basic component cannot be changed or switched off' using errcode = '23514';
    end if;
    if new.status = 'inactive' and old.status = 'active' and exists (
         select 1 from public.salary_template_lines l
         join public.salary_templates t on t.id = l.template_id and t.status = 'active'
         where l.component_id = new.id) then
      raise exception 'This component is used by an active salary template' using errcode = '23514';
    end if;
  elsif new.is_basic and exists (select 1 from public.salary_components where org_id = new.org_id and is_basic) then
    raise exception 'The organization already has a Basic component' using errcode = '23505';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Salary templates: a basic amount plus component lines.
-- -----------------------------------------------------------------------------
create table public.salary_templates (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null default private.current_org_id() references public.organizations (id),
  name         text not null check (char_length(btrim(name)) between 2 and 80),
  description  text check (description is null or char_length(description) <= 500),
  grade_id     uuid,
  basic_amount numeric(12, 2) not null check (basic_amount > 0 and basic_amount <= 99999999),
  status       text not null default 'active' check (status in ('active', 'inactive')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint salary_templates_org_id_id_uq unique (org_id, id),
  constraint salary_templates_grade_fk foreign key (org_id, grade_id) references public.grades (org_id, id)
);
create unique index salary_templates_org_name_uq on public.salary_templates (org_id, lower(name));

-- Template lines are configuration that is replaced as a whole when the
-- template is saved; employee pay keeps its own snapshot, so replacing lines
-- never changes anybody's salary.
create table public.salary_template_lines (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  template_id  uuid not null,
  component_id uuid not null,
  calc         text not null check (calc in ('fixed', 'percent_of_basic', 'percent_of_gross')),
  value        numeric(12, 2) not null check (value >= 0),
  sort_order   smallint not null default 100,
  constraint salary_template_lines_template_fk foreign key (org_id, template_id) references public.salary_templates (org_id, id),
  constraint salary_template_lines_component_fk foreign key (org_id, component_id) references public.salary_components (org_id, id),
  constraint salary_template_lines_uq unique (template_id, component_id),
  constraint salary_template_lines_percent_range check (calc = 'fixed' or value <= 100)
);

-- -----------------------------------------------------------------------------
-- Salary resolution. Given a template and either a basic or a target gross,
-- returns {basic, gross, total_deductions, lines[]}. Deterministic: the same
-- inputs always give the same lines.
--   gross = basic + fixed earnings + basic * Σ%basic + gross * Σ%gross
-- With a target gross the basic is solved from the formula; any paisa left by
-- rounding is put on the Basic line, so the gross matches the target exactly.
-- -----------------------------------------------------------------------------
create or replace function private.resolve_salary(
  p_template_id uuid, p_basic numeric default null, p_target_gross numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_template           public.salary_templates;
  v_basic_component    public.salary_components;
  v_fixed_earnings     numeric := 0;
  v_basic_percent      numeric := 0;
  v_gross_percent      numeric := 0;
  v_basic              numeric;
  v_gross_estimate     numeric;
  v_lines              jsonb;
  v_gross              numeric;
  v_rounding_remainder numeric;
begin
  select * into v_template from public.salary_templates where id = p_template_id;
  if not found then
    raise exception 'Salary template not found' using errcode = 'P0002';
  end if;
  select * into v_basic_component from public.salary_components
  where org_id = v_template.org_id and is_basic;
  if not found then
    raise exception 'The Basic component is missing' using errcode = 'P0002';
  end if;

  select coalesce(sum(l.value) filter (where l.calc = 'fixed'), 0),
         coalesce(sum(l.value) filter (where l.calc = 'percent_of_basic'), 0),
         coalesce(sum(l.value) filter (where l.calc = 'percent_of_gross'), 0)
    into v_fixed_earnings, v_basic_percent, v_gross_percent
  from public.salary_template_lines l
  join public.salary_components c on c.id = l.component_id
  where l.template_id = p_template_id and c.kind = 'earning' and c.status = 'active';

  if v_gross_percent >= 100 then
    raise exception 'Percent-of-gross earnings must add up to less than 100%%' using errcode = '22023';
  end if;

  if p_target_gross is not null then
    if p_target_gross <= 0 or p_target_gross > 99999999 then
      raise exception 'Gross must be a positive amount' using errcode = '22023';
    end if;
    v_basic := private.round_money(
      (p_target_gross * (1 - v_gross_percent / 100) - v_fixed_earnings) / (1 + v_basic_percent / 100));
    if v_basic <= 0 then
      raise exception 'The gross is too low for this template''s fixed allowances' using errcode = '22023';
    end if;
    v_gross_estimate := p_target_gross;
  else
    v_basic := private.round_money(coalesce(p_basic, v_template.basic_amount));
    if v_basic <= 0 or v_basic > 99999999 then
      raise exception 'Basic must be a positive amount' using errcode = '22023';
    end if;
    v_gross_estimate := (v_basic * (1 + v_basic_percent / 100) + v_fixed_earnings) / (1 - v_gross_percent / 100);
  end if;

  -- Resolved lines: Basic first (sort -1, so it is always element 0), then the
  -- template lines in their order.
  select jsonb_agg(line order by (line ->> 'sort_order')::int, line ->> 'code')
    into v_lines
  from (
    select jsonb_build_object(
             'component_id', v_basic_component.id, 'code', v_basic_component.code, 'name', v_basic_component.name,
             'kind', 'earning', 'calc', 'fixed', 'rate', null, 'amount', v_basic, 'sort_order', -1,
             'taxable', v_basic_component.taxable, 'pf_applicable', v_basic_component.pf_applicable) as line
    union all
    select jsonb_build_object(
             'component_id', c.id, 'code', c.code, 'name', c.name, 'kind', c.kind, 'calc', l.calc,
             'rate', case when l.calc = 'fixed' then null else l.value end,
             'amount', case l.calc
                         when 'fixed'            then private.round_money(l.value)
                         when 'percent_of_basic' then private.round_money(v_basic * l.value / 100)
                         else                         private.round_money(v_gross_estimate * l.value / 100)
                       end,
             'sort_order', l.sort_order, 'taxable', c.taxable, 'pf_applicable', c.pf_applicable)
    from public.salary_template_lines l
    join public.salary_components c on c.id = l.component_id
    where l.template_id = p_template_id and c.status = 'active' and not c.is_basic
  ) resolved;

  select coalesce(sum((line ->> 'amount')::numeric), 0) into v_gross
  from jsonb_array_elements(v_lines) line where line ->> 'kind' = 'earning';

  if p_target_gross is not null and v_gross <> p_target_gross then
    v_rounding_remainder := p_target_gross - v_gross;
    v_basic := v_basic + v_rounding_remainder;
    v_lines := jsonb_set(v_lines, '{0,amount}', to_jsonb(v_basic));
    v_gross := p_target_gross;
  end if;

  return jsonb_build_object(
    'template_id', p_template_id,
    'basic', v_basic,
    'gross', v_gross,
    'total_deductions', (select coalesce(sum((line ->> 'amount')::numeric), 0)
                         from jsonb_array_elements(v_lines) line where line ->> 'kind' = 'deduction'),
    'lines', v_lines);
end;
$$;

-- -----------------------------------------------------------------------------
-- Employee compensation history. A row is never edited: a change closes the
-- current row (effective_to) and opens a new one. Lines are a snapshot of the
-- resolved amounts, so later template changes never alter past pay.
-- -----------------------------------------------------------------------------
create table public.employee_compensation (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations (id),
  employee_id      uuid not null,
  template_id      uuid,
  basic            numeric(12, 2) not null check (basic > 0),
  gross            numeric(12, 2) not null check (gross >= basic),
  total_deductions numeric(12, 2) not null default 0 check (total_deductions >= 0),
  effective_from   date not null,
  effective_to     date,
  change_type      text not null check (change_type in ('initial', 'increment', 'promotion', 'correction')),
  increment_id     uuid,
  reason           text check (reason is null or char_length(reason) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint employee_compensation_org_id_id_uq unique (org_id, id),
  constraint employee_compensation_dates check (effective_to is null or effective_to >= effective_from),
  constraint employee_compensation_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint employee_compensation_template_fk foreign key (org_id, template_id) references public.salary_templates (org_id, id)
);
create unique index employee_compensation_current_uq on public.employee_compensation (employee_id) where effective_to is null;
create index employee_compensation_employee_idx on public.employee_compensation (employee_id, effective_from);

create table public.employee_compensation_lines (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations (id),
  compensation_id uuid not null,
  component_id    uuid not null,
  code            text not null,
  name            text not null,
  kind            text not null check (kind in ('earning', 'deduction')),
  calc            text not null check (calc in ('fixed', 'percent_of_basic', 'percent_of_gross')),
  rate            numeric(12, 2),
  amount          numeric(12, 2) not null check (amount >= 0),
  taxable         boolean not null,
  pf_applicable   boolean not null,
  sort_order      smallint not null default 100,
  constraint employee_compensation_lines_comp_fk foreign key (org_id, compensation_id)
    references public.employee_compensation (org_id, id),
  constraint employee_compensation_lines_component_fk foreign key (org_id, component_id)
    references public.salary_components (org_id, id),
  constraint employee_compensation_lines_uq unique (compensation_id, component_id)
);

-- Only closing a current row is allowed; everything else about pay history is immutable.
create or replace function private.employee_compensation_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if old.effective_to is not null
       or (to_jsonb(new) - array['effective_to', 'updated_at', 'updated_by'])
          <> (to_jsonb(old) - array['effective_to', 'updated_at', 'updated_by']) then
      raise exception 'Pay history cannot be edited; record a new change instead' using errcode = '42501';
    end if;
    return new;
  end if;
  if exists (select 1 from public.employee_compensation c
             where c.employee_id = new.employee_id
               and daterange(c.effective_from, c.effective_to, '[]')
                   && daterange(new.effective_from, new.effective_to, '[]')) then
    raise exception 'Pay periods of one employee cannot overlap' using errcode = '23P01';
  end if;
  return new;
end;
$$;
create trigger employee_compensation_guard before insert or update on public.employee_compensation
  for each row execute function private.employee_compensation_guard();

create or replace function private.append_only_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Rows in % are a permanent record and cannot be changed', tg_table_name using errcode = '42501';
end;
$$;
create trigger append_only before update or delete on public.employee_compensation_lines
  for each row execute function private.append_only_row();

-- The pay effective on a date (the history row whose range contains it).
create or replace function private.compensation_on(p_employee_id uuid, p_date date)
returns public.employee_compensation
language sql
stable
security definer
set search_path = ''
as $$
  select c.* from public.employee_compensation c
  where c.employee_id = p_employee_id and c.effective_from <= p_date
    and (c.effective_to is null or c.effective_to >= p_date)
  limit 1
$$;

-- Writes a new pay version: closes the current one the day before and stores
-- the resolved snapshot. Callers have already checked permission and org.
create or replace function private.create_compensation(
  p_employee_id    uuid,
  p_template_id    uuid,
  p_basic          numeric,
  p_target_gross   numeric,
  p_effective_from date,
  p_change_type    text,
  p_increment_id   uuid,
  p_reason         text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee        public.employees;
  v_current         public.employee_compensation;
  v_resolved        jsonb;
  v_compensation_id uuid;
begin
  select * into v_employee from public.employees where id = p_employee_id;
  if p_effective_from is null or p_effective_from < v_employee.join_date then
    raise exception 'The effective date cannot be before the joining date' using errcode = '22023';
  end if;
  if exists (select 1 from public.salary_templates
             where id = p_template_id and org_id = v_employee.org_id and status = 'active') is not true then
    raise exception 'Choose an active salary template' using errcode = '22023';
  end if;

  select * into v_current from public.employee_compensation
  where employee_id = p_employee_id and effective_to is null
  for update;
  if found then
    if p_effective_from <= v_current.effective_from then
      raise exception 'The new pay must start after the current pay (from %)', v_current.effective_from
        using errcode = '22023';
    end if;
    update public.employee_compensation set effective_to = p_effective_from - 1 where id = v_current.id;
  end if;

  v_resolved := private.resolve_salary(p_template_id, p_basic, p_target_gross);

  insert into public.employee_compensation (org_id, employee_id, template_id, basic, gross, total_deductions,
                                            effective_from, change_type, increment_id, reason)
  values (v_employee.org_id, p_employee_id, p_template_id, (v_resolved ->> 'basic')::numeric,
          (v_resolved ->> 'gross')::numeric, (v_resolved ->> 'total_deductions')::numeric,
          p_effective_from, p_change_type, p_increment_id, nullif(btrim(p_reason), ''))
  returning id into v_compensation_id;

  insert into public.employee_compensation_lines (org_id, compensation_id, component_id, code, name, kind, calc,
                                                  rate, amount, taxable, pf_applicable, sort_order)
  select v_employee.org_id, v_compensation_id, (line ->> 'component_id')::uuid, line ->> 'code', line ->> 'name',
         line ->> 'kind', line ->> 'calc', (line ->> 'rate')::numeric, (line ->> 'amount')::numeric,
         (line ->> 'taxable')::boolean, (line ->> 'pf_applicable')::boolean, (line ->> 'sort_order')::smallint
  from jsonb_array_elements(v_resolved -> 'lines') line;

  return v_compensation_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Salary increments (maker-checker). Approval creates a new compensation row;
-- a back-dated effective date creates arrears that Part 3B pays.
-- -----------------------------------------------------------------------------
create table public.salary_increments (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations (id),
  employee_id     uuid not null,
  type            text not null check (type in ('increment', 'promotion', 'correction')),
  template_id     uuid not null,
  old_gross       numeric(12, 2) not null,
  new_gross       numeric(12, 2) not null check (new_gross > 0),
  effective_date  date not null,
  reason          text not null check (char_length(btrim(reason)) between 3 and 500),
  status          text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  approved_by     uuid references public.user_profiles (id),
  decided_at      timestamptz,
  decision_note   text check (decision_note is null or char_length(decision_note) <= 500),
  compensation_id uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references public.user_profiles (id),
  updated_by      uuid references public.user_profiles (id),
  constraint salary_increments_org_id_id_uq unique (org_id, id),
  constraint salary_increments_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint salary_increments_template_fk foreign key (org_id, template_id) references public.salary_templates (org_id, id),
  constraint salary_increments_compensation_fk foreign key (org_id, compensation_id)
    references public.employee_compensation (org_id, id)
);
create unique index salary_increments_one_pending_uq on public.salary_increments (employee_id) where status = 'pending';

alter table public.employee_compensation
  add constraint employee_compensation_increment_fk foreign key (org_id, increment_id)
  references public.salary_increments (org_id, id);

-- Arrears of a back-dated change on the 30-day basis: the gross difference for
-- every month from the effective month up to (not including) p_until_month.
-- The first month pays only the days from the effective date.
create or replace function private.arrears_amount(
  p_old_gross numeric, p_new_gross numeric, p_effective date, p_until_month date)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(private.round_money(
           (p_new_gross - p_old_gross)
           * case when m = private.month_start(p_effective) then private.paid_days_from(p_effective) else 30 end
           / 30)), 0)
  from generate_series(private.month_start(p_effective), private.month_start(p_until_month) - interval '1 month',
                       interval '1 month') as m
$$;

-- -----------------------------------------------------------------------------
-- Bonuses
-- -----------------------------------------------------------------------------
create table public.bonuses (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null default private.current_org_id() references public.organizations (id),
  name               text not null check (char_length(btrim(name)) between 2 and 100),
  type               text not null check (type in ('festival', 'performance', 'incentive', 'annual', 'ad_hoc')),
  basis              text not null check (basis in ('fixed', 'percent')),
  amount             numeric(12, 2) check (amount is null or amount > 0),
  percent            numeric(6, 2) check (percent is null or (percent > 0 and percent <= 500)),
  percent_base       text check (percent_base in ('basic', 'gross')),
  payment_month      date not null check (extract(day from payment_month) = 1),
  min_service_months smallint not null default 0 check (min_service_months between 0 and 600),
  scope              text not null default 'all' check (scope in ('all', 'departments', 'employees')),
  status             text not null default 'active' check (status in ('active', 'inactive')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint bonuses_org_id_id_uq unique (org_id, id),
  constraint bonuses_basis_values check (
    (basis = 'fixed' and amount is not null and percent is null and percent_base is null)
    or (basis = 'percent' and percent is not null and percent_base is not null and amount is null))
);

create table public.bonus_eligibility (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations (id),
  bonus_id      uuid not null,
  department_id uuid,
  employee_id   uuid,
  constraint bonus_eligibility_bonus_fk foreign key (org_id, bonus_id) references public.bonuses (org_id, id),
  constraint bonus_eligibility_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint bonus_eligibility_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint bonus_eligibility_one_target check ((department_id is null) <> (employee_id is null))
);
create unique index bonus_eligibility_uq
  on public.bonus_eligibility (bonus_id, coalesce(department_id, employee_id));

-- -----------------------------------------------------------------------------
-- Loans, advances and other deductions. Part 3B posts the installments and
-- reduces `remaining`; it stops at zero.
-- -----------------------------------------------------------------------------
create table public.employee_deductions (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  employee_id uuid not null,
  type        text not null check (type in ('loan', 'advance', 'other')),
  description text check (description is null or char_length(description) <= 300),
  total       numeric(12, 2) not null check (total > 0 and total <= 99999999),
  installment numeric(12, 2) not null check (installment > 0),
  start_month date not null check (extract(day from start_month) = 1),
  remaining   numeric(12, 2) not null check (remaining >= 0),
  status      text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  note        text check (note is null or char_length(note) <= 500),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint employee_deductions_org_id_id_uq unique (org_id, id),
  constraint employee_deductions_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint employee_deductions_amounts check (installment <= total and remaining <= total)
);
create index employee_deductions_employee_idx on public.employee_deductions (employee_id) where status = 'active';

-- -----------------------------------------------------------------------------
-- Payment accounts. Account and wallet numbers are stored encrypted; only the
-- last 4 digits are kept in clear for masking. Never written to the audit log.
-- -----------------------------------------------------------------------------
create table public.employee_payment_accounts (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  employee_id        uuid not null,
  method             text not null check (method in ('bank', 'mobile_wallet', 'cash')),
  bank_name          text check (bank_name is null or char_length(btrim(bank_name)) between 2 and 120),
  branch_name        text check (branch_name is null or char_length(branch_name) <= 120),
  routing_number     text check (routing_number is null or routing_number ~ '^[0-9]{9}$'),
  account_name       text check (account_name is null or char_length(account_name) <= 150),
  account_number_enc bytea,
  wallet_provider    text check (wallet_provider in ('bkash', 'nagad', 'rocket', 'upay', 'other')),
  wallet_number_enc  bytea,
  number_last4       text check (number_last4 is null or number_last4 ~ '^[0-9]{2,4}$'),
  is_primary         boolean not null default false,
  status             text not null default 'active' check (status in ('active', 'inactive')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint employee_payment_accounts_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint employee_payment_accounts_shape check (
    (method = 'bank' and bank_name is not null and account_number_enc is not null and wallet_number_enc is null)
    or (method = 'mobile_wallet' and wallet_provider is not null and wallet_number_enc is not null
        and account_number_enc is null)
    or (method = 'cash' and account_number_enc is null and wallet_number_enc is null))
);
create unique index employee_payment_accounts_primary_uq
  on public.employee_payment_accounts (employee_id) where is_primary and status = 'active';

-- Masked display: the last 4 digits only.
create or replace function private.mask_number(p_last4 text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_last4 is null then null else '•••• ' || p_last4 end
$$;

-- -----------------------------------------------------------------------------
-- Audit: same as before, plus encrypted payment numbers are never logged.
-- -----------------------------------------------------------------------------
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ignore text[] := array['updated_at', 'updated_by', 'last_login_at'];
  v_secret text[] := array['account_number_enc', 'wallet_number_enc'];
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb;
  v_org uuid;
begin
  if tg_op = 'UPDATE' and (v_old - v_ignore) = (v_new - v_ignore) then
    return null;
  end if;
  if tg_table_name = 'employee_sensitive' then
    v_old := v_old || jsonb_build_object('nid_number', '***' || right(v_old ->> 'nid_number', 3));
    v_new := v_new || jsonb_build_object('nid_number', '***' || right(v_new ->> 'nid_number', 3));
  elsif tg_table_name = 'employee_payment_accounts' then
    -- Record that the number changed, never the number (not even encrypted).
    if tg_op = 'UPDATE' and ((v_old -> 'account_number_enc') is distinct from (v_new -> 'account_number_enc')
                             or (v_old -> 'wallet_number_enc') is distinct from (v_new -> 'wallet_number_enc')) then
      v_new := v_new || jsonb_build_object('number_changed', true);
    end if;
    v_old := v_old - v_secret;
    v_new := v_new - v_secret;
  end if;

  v_row := coalesce(v_new, v_old);
  v_org := case
             when tg_table_name = 'organizations' then (v_row ->> 'id')::uuid
             else (v_row ->> 'org_id')::uuid
           end;

  perform private.write_audit(
    v_org, lower(tg_op), tg_table_name,
    case when v_row ? 'id' then (v_row ->> 'id')::uuid
         when v_row ? 'employee_id' then (v_row ->> 'employee_id')::uuid end,
    v_old, v_new);
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- Standard triggers
-- -----------------------------------------------------------------------------
create trigger set_row_meta before insert or update on public.payroll_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.payroll_settings
  for each row execute function private.audit_row_change();
create trigger salary_components_guard before insert or update on public.salary_components
  for each row execute function private.salary_components_guard();
select private.attach_standard_triggers('public.salary_components');
select private.attach_standard_triggers('public.salary_templates');
select private.attach_standard_triggers('public.employee_compensation');
select private.attach_standard_triggers('public.salary_increments');
select private.attach_standard_triggers('public.bonuses');
select private.attach_standard_triggers('public.employee_deductions');
select private.attach_standard_triggers('public.employee_payment_accounts');
create trigger audit after insert or update or delete on public.salary_template_lines
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.bonus_eligibility
  for each row execute function private.audit_row_change();
create trigger audit after insert on public.employee_compensation_lines
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Organization defaults. Component values are common examples, not statutory
-- figures: HR reviews them before use.
-- -----------------------------------------------------------------------------
create or replace function private.seed_payroll_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_payroll_permissions(p_org_id);

  insert into public.payroll_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;

  if not exists (select 1 from public.salary_components where org_id = p_org_id) then
    insert into public.salary_components (org_id, name, code, kind, calc, default_value, taxable, pf_applicable,
                                          is_basic, sort_order)
    values
      (p_org_id, 'Basic',        'BASIC',      'earning', 'fixed',            0,    true,  true,  true,  0),
      (p_org_id, 'House Rent',   'HOUSE_RENT', 'earning', 'percent_of_basic', 50,   true,  false, false, 10),
      (p_org_id, 'Medical',      'MEDICAL',    'earning', 'fixed',            750,  false, false, false, 20),
      (p_org_id, 'Conveyance',   'CONVEYANCE', 'earning', 'fixed',            450,  false, false, false, 30),
      (p_org_id, 'Food',         'FOOD',       'earning', 'fixed',            1250, false, false, false, 40);
  end if;
end;
$$;

create or replace function private.seed_org_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.grades (org_id, code, category, level, description) values
    (p_org_id, 'EM0',     'EM',    0,  'Employee level 0'),
    (p_org_id, 'EM1',     'EM',    1,  'Employee level 1'),
    (p_org_id, 'EM2',     'EM',    2,  'Employee level 2'),
    (p_org_id, 'EM3',     'EM',    3,  'Employee level 3'),
    (p_org_id, 'EM4',     'EM',    4,  'Employee level 4'),
    (p_org_id, 'MS0',     'MS',    10, 'Management level 0'),
    (p_org_id, 'MS1',     'MS',    11, 'Management level 1'),
    (p_org_id, 'MS2',     'MS',    12, 'Management level 2'),
    (p_org_id, 'OWNER01', 'OWNER', 20, 'Owner level 1'),
    (p_org_id, 'OWNER02', 'OWNER', 21, 'Owner level 2')
  on conflict (org_id, code) do nothing;
  perform private.seed_default_field_access(p_org_id);
  perform private.seed_time_defaults(p_org_id);
  perform private.seed_payroll_defaults(p_org_id);
end;
$$;

-- =============================================================================
-- RPCs
-- =============================================================================

-- Salary template save: header and lines in one transaction.
-- p = {name, description, grade_id, basic_amount, status, lines: [{component_id, calc, value}]}
create or replace function public.save_salary_template(p_template_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id      uuid := private.current_org_id();
  v_template_id uuid := p_template_id;
  v_lines       jsonb := coalesce(p -> 'lines', '[]'::jsonb);
begin
  perform private.require_permission('compensation.edit');
  if char_length(coalesce(private.jtext(p, 'name'), '')) < 2 then
    raise exception 'The template name is required' using errcode = '22023';
  end if;
  if coalesce((p ->> 'basic_amount')::numeric, 0) <= 0 then
    raise exception 'The basic amount must be more than zero' using errcode = '22023';
  end if;
  if jsonb_typeof(v_lines) <> 'array' or jsonb_array_length(v_lines) > 50 then
    raise exception 'Invalid template lines' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) l
             left join public.salary_components c
               on c.id = private.jtext(l, 'component_id')::uuid and c.org_id = v_org_id and c.status = 'active'
             where c.id is null or c.is_basic) then
    raise exception 'Every line needs an active component other than Basic' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements(v_lines))
     <> (select count(distinct l ->> 'component_id') from jsonb_array_elements(v_lines) l) then
    raise exception 'A component can appear only once in a template' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(v_lines) l
             where coalesce(l ->> 'calc', '') not in ('fixed', 'percent_of_basic', 'percent_of_gross')
                or coalesce((l ->> 'value')::numeric, -1) < 0
                or (l ->> 'calc' <> 'fixed' and (l ->> 'value')::numeric > 100)) then
    raise exception 'Each line needs a calculation and a value (percentages up to 100)' using errcode = '22023';
  end if;

  if v_template_id is null then
    insert into public.salary_templates (org_id, name, description, grade_id, basic_amount, status)
    values (v_org_id, private.jtext(p, 'name'), private.jtext(p, 'description'),
            private.jtext(p, 'grade_id')::uuid, (p ->> 'basic_amount')::numeric,
            coalesce(private.jtext(p, 'status'), 'active'))
    returning id into v_template_id;
  else
    update public.salary_templates
       set name = private.jtext(p, 'name'), description = private.jtext(p, 'description'),
           grade_id = private.jtext(p, 'grade_id')::uuid, basic_amount = (p ->> 'basic_amount')::numeric,
           status = coalesce(private.jtext(p, 'status'), status)
     where id = v_template_id and org_id = v_org_id;
    if not found then
      raise exception 'Salary template not found' using errcode = 'P0002';
    end if;
    delete from public.salary_template_lines where template_id = v_template_id;
  end if;

  insert into public.salary_template_lines (org_id, template_id, component_id, calc, value, sort_order)
  select v_org_id, v_template_id, (l ->> 'component_id')::uuid, l ->> 'calc', (l ->> 'value')::numeric,
         coalesce((select c.sort_order from public.salary_components c where c.id = (l ->> 'component_id')::uuid), 100)
  from jsonb_array_elements(v_lines) l;

  -- Validates the result (percent-of-gross below 100%, positive basic).
  perform private.resolve_salary(v_template_id);
  return v_template_id;
end;
$$;

-- Preview of a template's lines for a basic or a target gross (template builder,
-- add-pay and increment dialogs).
create or replace function public.preview_salary(p_template_id uuid, p_basic numeric default null,
                                                 p_gross numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (private.has_permission('compensation.view') or private.has_permission('compensation.edit')) then
    raise exception 'You do not have permission for this action (compensation.view)' using errcode = '42501';
  end if;
  if not exists (select 1 from public.salary_templates where id = p_template_id and org_id = private.current_org_id()) then
    raise exception 'Salary template not found' using errcode = 'P0002';
  end if;
  return private.resolve_salary(p_template_id, p_basic, p_gross);
end;
$$;

-- First pay for an employee. Later changes go through increments (maker-checker).
create or replace function public.set_initial_compensation(
  p_employee_id uuid, p_template_id uuid, p_basic numeric, p_gross numeric, p_effective_from date,
  p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee public.employees;
begin
  perform private.require_permission('compensation.edit');
  v_employee := private.assert_org_employee(p_employee_id);
  perform private.assert_not_self_money(p_employee_id);
  if v_employee.status <> 'active' then
    raise exception 'The employee is not active' using errcode = '22023';
  end if;
  if exists (select 1 from public.employee_compensation where employee_id = p_employee_id) then
    raise exception 'This employee already has pay; request an increment or correction instead' using errcode = '23505';
  end if;
  if (p_basic is null) = (p_gross is null) then
    raise exception 'Give either a basic or a gross amount' using errcode = '22023';
  end if;
  return private.create_compensation(p_employee_id, p_template_id, p_basic, p_gross,
                                     coalesce(p_effective_from, v_employee.join_date), 'initial', null, p_reason);
end;
$$;

-- p = {type, template_id (default: current), new_gross, effective_date, reason}
create or replace function public.request_increment(p_employee_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current      public.employee_compensation;
  v_template_id  uuid;
  v_new_gross    numeric := (p ->> 'new_gross')::numeric;
  v_effective    date := (p ->> 'effective_date')::date;
  v_increment_id uuid;
begin
  perform private.require_permission('compensation.edit');
  perform private.assert_org_employee(p_employee_id);
  perform private.assert_not_self_money(p_employee_id);
  if coalesce(private.jtext(p, 'type'), 'increment') not in ('increment', 'promotion', 'correction') then
    raise exception 'Choose increment, promotion or correction' using errcode = '22023';
  end if;
  if char_length(coalesce(private.jtext(p, 'reason'), '')) < 3 then
    raise exception 'A reason is required' using errcode = '22023';
  end if;

  select * into v_current from public.employee_compensation where employee_id = p_employee_id and effective_to is null;
  if not found then
    raise exception 'Set the starting pay first' using errcode = '22023';
  end if;
  if v_effective is null or v_effective <= v_current.effective_from then
    raise exception 'The effective date must be after the current pay start (%)', v_current.effective_from
      using errcode = '22023';
  end if;
  v_template_id := coalesce(private.jtext(p, 'template_id')::uuid, v_current.template_id);
  -- Fails early on an inactive template or an impossible gross.
  perform private.resolve_salary(v_template_id, null, v_new_gross);

  insert into public.salary_increments (org_id, employee_id, type, template_id, old_gross, new_gross,
                                        effective_date, reason)
  values (v_current.org_id, p_employee_id, coalesce(private.jtext(p, 'type'), 'increment'), v_template_id,
          v_current.gross, v_new_gross, v_effective, coalesce(private.jtext(p, 'reason'), ''))
  returning id into v_increment_id;
  return v_increment_id;
exception
  when unique_violation then
    raise exception 'This employee already has a pending increment' using errcode = '23505';
end;
$$;

-- Maker-checker: the person who requested the change can never approve it,
-- and nobody approves a change to their own pay.
create or replace function public.decide_increment(p_increment_id uuid, p_approve boolean, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_increment       public.salary_increments;
  v_compensation_id uuid;
begin
  perform private.require_permission('increments.approve');
  select * into v_increment from public.salary_increments
  where id = p_increment_id and org_id = private.current_org_id()
  for update;
  if not found then
    raise exception 'Increment not found' using errcode = 'P0002';
  end if;
  if v_increment.status <> 'pending' then
    raise exception 'This increment was already decided' using errcode = '22023';
  end if;
  if v_increment.created_by = auth.uid() then
    raise exception 'You requested this increment, so someone else must approve it' using errcode = '42501';
  end if;
  if v_increment.employee_id = private.current_employee_id() then
    raise exception 'You cannot decide your own increment' using errcode = '42501';
  end if;

  if p_approve then
    v_compensation_id := private.create_compensation(
      v_increment.employee_id, v_increment.template_id, null, v_increment.new_gross, v_increment.effective_date,
      v_increment.type, v_increment.id, v_increment.reason);
  end if;

  update public.salary_increments
     set status = case when p_approve then 'approved' else 'rejected' end,
         approved_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), ''),
         compensation_id = v_compensation_id
   where id = v_increment.id;
  return v_compensation_id;
end;
$$;

create or replace function public.cancel_increment(p_increment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('compensation.edit');
  update public.salary_increments set status = 'cancelled'
   where id = p_increment_id and org_id = private.current_org_id() and status = 'pending';
  if not found then
    raise exception 'Only a pending increment can be cancelled' using errcode = '22023';
  end if;
end;
$$;

-- Arrears preview up to (not including) the given month; defaults to the
-- current month, i.e. the months that were already paid at the old rate.
create or replace function public.get_increment_arrears(p_increment_id uuid, p_until_month date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_increment public.salary_increments;
  v_until     date;
begin
  if not (private.has_permission('compensation.view') or private.has_permission('increments.approve')) then
    raise exception 'You do not have permission for this action (compensation.view)' using errcode = '42501';
  end if;
  select * into v_increment from public.salary_increments
  where id = p_increment_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Increment not found' using errcode = 'P0002';
  end if;
  v_until := private.month_start(coalesce(p_until_month, private.org_today(v_increment.org_id)));
  return jsonb_build_object(
    'until_month', v_until,
    'back_dated', v_increment.effective_date < v_until,
    'amount', case when v_increment.effective_date < v_until
                   then private.arrears_amount(v_increment.old_gross, v_increment.new_gross,
                                               v_increment.effective_date, v_until)
                   else 0 end);
end;
$$;

-- Pay history of one employee with the resolved lines of every version.
create or replace function public.get_employee_compensation(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('compensation.view');
  perform private.assert_org_employee(p_employee_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', c.id, 'template_id', c.template_id, 'template_name', t.name, 'basic', c.basic, 'gross', c.gross,
             'total_deductions', c.total_deductions, 'effective_from', c.effective_from,
             'effective_to', c.effective_to, 'change_type', c.change_type, 'reason', c.reason,
             'created_at', c.created_at,
             'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                                'code', l.code, 'name', l.name, 'kind', l.kind, 'calc', l.calc, 'rate', l.rate,
                                'amount', l.amount) order by l.sort_order, l.code), '[]'::jsonb)
                       from public.employee_compensation_lines l where l.compensation_id = c.id))
           order by c.effective_from desc)
    from public.employee_compensation c
    left join public.salary_templates t on t.id = c.template_id
    where c.employee_id = p_employee_id), '[]'::jsonb);
end;
$$;

-- p = {name, type, basis, amount, percent, percent_base, payment_month, min_service_months, scope, status,
--      department_ids[], employee_ids[]}
create or replace function public.save_bonus(p_bonus_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id   uuid := private.current_org_id();
  v_bonus_id uuid := p_bonus_id;
  v_scope    text := coalesce(private.jtext(p, 'scope'), 'all');
  v_basis    text := private.jtext(p, 'basis');
  v_targets  jsonb;
begin
  perform private.require_permission('bonuses.manage');
  if char_length(coalesce(private.jtext(p, 'name'), '')) < 2 then
    raise exception 'The bonus name is required' using errcode = '22023';
  end if;
  if coalesce(private.jtext(p, 'type'), '') not in ('festival', 'performance', 'incentive', 'annual', 'ad_hoc') then
    raise exception 'Choose a bonus type' using errcode = '22023';
  end if;
  if v_scope not in ('all', 'departments', 'employees') then
    raise exception 'Choose who gets the bonus' using errcode = '22023';
  end if;
  if (p ->> 'payment_month') is null then
    raise exception 'The payment month is required' using errcode = '22023';
  end if;
  if v_basis is null or v_basis not in ('fixed', 'percent') then
    raise exception 'Choose a fixed amount or a percent' using errcode = '22023';
  elsif v_basis = 'fixed' and coalesce((p ->> 'amount')::numeric, 0) <= 0 then
    raise exception 'The bonus amount must be more than zero' using errcode = '22023';
  elsif v_basis = 'percent' and (coalesce((p ->> 'percent')::numeric, 0) not between 0.01 and 500
                                 or coalesce(private.jtext(p, 'percent_base'), '') not in ('basic', 'gross')) then
    raise exception 'Give a percent (up to 500) of basic or gross' using errcode = '22023';
  end if;
  v_targets := case v_scope when 'departments' then coalesce(p -> 'department_ids', '[]')
                            when 'employees'   then coalesce(p -> 'employee_ids', '[]')
                            else '[]'::jsonb end;
  if jsonb_typeof(v_targets) <> 'array' or jsonb_array_length(v_targets) > 5000 then
    raise exception 'Invalid eligibility list' using errcode = '22023';
  end if;
  if v_scope <> 'all' and jsonb_array_length(v_targets) = 0 then
    raise exception 'Choose at least one department or employee' using errcode = '22023';
  end if;

  if v_bonus_id is null then
    insert into public.bonuses (org_id, name, type, basis, amount, percent, percent_base, payment_month,
                                min_service_months, scope, status)
    values (v_org_id, private.jtext(p, 'name'), private.jtext(p, 'type'), v_basis,
            case when v_basis = 'fixed' then (p ->> 'amount')::numeric end,
            case when v_basis = 'percent' then (p ->> 'percent')::numeric end,
            case when v_basis = 'percent' then private.jtext(p, 'percent_base') end,
            private.month_start((p ->> 'payment_month')::date),
            coalesce((p ->> 'min_service_months')::smallint, 0), v_scope,
            coalesce(private.jtext(p, 'status'), 'active'))
    returning id into v_bonus_id;
  else
    update public.bonuses
       set name = private.jtext(p, 'name'), type = private.jtext(p, 'type'), basis = v_basis,
           amount = case when v_basis = 'fixed' then (p ->> 'amount')::numeric end,
           percent = case when v_basis = 'percent' then (p ->> 'percent')::numeric end,
           percent_base = case when v_basis = 'percent' then private.jtext(p, 'percent_base') end,
           payment_month = private.month_start((p ->> 'payment_month')::date),
           min_service_months = coalesce((p ->> 'min_service_months')::smallint, 0), scope = v_scope,
           status = coalesce(private.jtext(p, 'status'), status)
     where id = v_bonus_id and org_id = v_org_id;
    if not found then
      raise exception 'Bonus not found' using errcode = 'P0002';
    end if;
    delete from public.bonus_eligibility where bonus_id = v_bonus_id;
  end if;

  -- The composite foreign keys reject a department or employee of another organization.
  insert into public.bonus_eligibility (org_id, bonus_id, department_id, employee_id)
  select distinct v_org_id, v_bonus_id,
         case when v_scope = 'departments' then (target #>> '{}')::uuid end,
         case when v_scope = 'employees' then (target #>> '{}')::uuid end
  from jsonb_array_elements(v_targets) target;
  return v_bonus_id;
end;
$$;

-- Who gets the bonus and how much: active in the payment month, in scope,
-- enough completed service months at the month end, and with pay on record.
create or replace function public.get_bonus_preview(p_bonus_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bonus     public.bonuses;
  v_month_end date;
begin
  if not (private.has_permission('bonuses.manage') or private.has_permission('compensation.view')) then
    raise exception 'You do not have permission for this action (bonuses.manage)' using errcode = '42501';
  end if;
  select * into v_bonus from public.bonuses where id = p_bonus_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Bonus not found' using errcode = 'P0002';
  end if;
  v_month_end := (v_bonus.payment_month + interval '1 month - 1 day')::date;

  return coalesce((
    select jsonb_agg(row_to_json(preview) order by preview.eligible desc, preview.full_name)
    from (
      select e.id as employee_id, e.full_name, e.card_id, d.name as department_name,
             private.service_months(e.join_date, v_month_end) as service_months,
             comp.basic, comp.gross,
             (comp.id is not null and private.service_months(e.join_date, v_month_end) >= v_bonus.min_service_months)
               as eligible,
             case when comp.id is null then 'No pay on record'
                  when private.service_months(e.join_date, v_month_end) < v_bonus.min_service_months
                    then 'Needs ' || v_bonus.min_service_months || ' months of service'
             end as reason,
             case when comp.id is null
                    or private.service_months(e.join_date, v_month_end) < v_bonus.min_service_months then 0
                  when v_bonus.basis = 'fixed' then v_bonus.amount
                  else private.round_money(
                         case v_bonus.percent_base when 'basic' then comp.basic else comp.gross end
                         * v_bonus.percent / 100)
             end as amount
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join lateral private.compensation_on(e.id, least(v_month_end, coalesce(e.exit_date, v_month_end))) comp
        on true
      where e.org_id = v_bonus.org_id
        and e.join_date <= v_month_end
        and (e.exit_date is null or e.exit_date >= v_bonus.payment_month)
        and (e.status = 'active' or e.exit_date is not null)
        and (v_bonus.scope = 'all'
             or (v_bonus.scope = 'departments' and exists (
                   select 1 from public.bonus_eligibility be
                   where be.bonus_id = v_bonus.id and be.department_id = e.department_id))
             or (v_bonus.scope = 'employees' and exists (
                   select 1 from public.bonus_eligibility be
                   where be.bonus_id = v_bonus.id and be.employee_id = e.id)))
    ) preview), '[]'::jsonb);
end;
$$;

-- p = {employee_id, type, description, total, installment, start_month, note}
create or replace function public.create_deduction(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee     public.employees;
  v_deduction_id uuid;
begin
  perform private.require_permission('deductions.manage');
  v_employee := private.assert_org_employee(private.jtext(p, 'employee_id')::uuid);
  perform private.assert_not_self_money(v_employee.id);
  if coalesce(private.jtext(p, 'type'), '') not in ('loan', 'advance', 'other') then
    raise exception 'Choose loan, advance or other' using errcode = '22023';
  end if;
  if coalesce((p ->> 'total')::numeric, 0) <= 0
     or coalesce((p ->> 'installment')::numeric, 0) <= 0
     or (p ->> 'installment')::numeric > (p ->> 'total')::numeric then
    raise exception 'The installment must be more than zero and not more than the total' using errcode = '22023';
  end if;
  if (p ->> 'start_month') is null then
    raise exception 'The start month is required' using errcode = '22023';
  end if;
  insert into public.employee_deductions (org_id, employee_id, type, description, total, installment, start_month,
                                          remaining, note)
  values (v_employee.org_id, v_employee.id, private.jtext(p, 'type'), private.jtext(p, 'description'),
          (p ->> 'total')::numeric, (p ->> 'installment')::numeric,
          private.month_start((p ->> 'start_month')::date), (p ->> 'total')::numeric, private.jtext(p, 'note'))
  returning id into v_deduction_id;
  return v_deduction_id;
end;
$$;

create or replace function public.cancel_deduction(p_deduction_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('deductions.manage');
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  update public.employee_deductions
     set status = 'cancelled', note = btrim(p_reason)
   where id = p_deduction_id and org_id = private.current_org_id() and status = 'active';
  if not found then
    raise exception 'Only an active deduction can be cancelled' using errcode = '22023';
  end if;
end;
$$;

-- p = {employee_id, method, bank_name, branch_name, routing_number, account_name, account_number,
--      wallet_provider, wallet_number, is_primary, status}
-- On update, an empty account/wallet number keeps the stored one.
create or replace function public.save_payment_account(p_account_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing      public.employee_payment_accounts;
  v_employee      public.employees;
  v_method        text := private.jtext(p, 'method');
  v_account_plain text := nullif(regexp_replace(coalesce(p ->> 'account_number', ''), '[\s-]', '', 'g'), '');
  v_wallet_plain  text := nullif(btrim(coalesce(p ->> 'wallet_number', '')), '');
  v_account_enc   bytea;
  v_wallet_enc    bytea;
  v_last4         text;
  v_is_primary    boolean := coalesce((p ->> 'is_primary')::boolean, false);
  v_status        text := coalesce(private.jtext(p, 'status'), 'active');
  v_account_id    uuid := p_account_id;
begin
  perform private.require_permission('payment_accounts.edit');

  if v_account_id is not null then
    select * into v_existing from public.employee_payment_accounts
    where id = v_account_id and org_id = private.current_org_id()
    for update;
    if not found then
      raise exception 'Payment account not found' using errcode = 'P0002';
    end if;
    v_employee := private.assert_org_employee(v_existing.employee_id);
    v_method := v_existing.method;   -- the method of an account never changes
  else
    v_employee := private.assert_org_employee(private.jtext(p, 'employee_id')::uuid);
  end if;
  perform private.assert_not_self_money(v_employee.id);

  if v_method = 'bank' then
    if char_length(coalesce(private.jtext(p, 'bank_name'), '')) < 2 then
      raise exception 'The bank name is required' using errcode = '22023';
    end if;
    if private.jtext(p, 'routing_number') is not null and private.jtext(p, 'routing_number') !~ '^[0-9]{9}$' then
      raise exception 'The routing number must be 9 digits' using errcode = '22023';
    end if;
    if v_account_plain is not null then
      if v_account_plain !~ '^[0-9]{6,20}$' then
        raise exception 'The account number must be 6 to 20 digits' using errcode = '22023';
      end if;
      v_account_enc := private.encrypt_secret(v_account_plain);
      v_last4 := right(v_account_plain, 4);
    elsif v_existing.id is not null then
      v_account_enc := v_existing.account_number_enc;
      v_last4 := v_existing.number_last4;
    else
      raise exception 'The account number is required' using errcode = '22023';
    end if;
  elsif v_method = 'mobile_wallet' then
    if v_wallet_plain is not null then
      v_wallet_plain := private.normalize_bd_phone(v_wallet_plain);
      if v_wallet_plain is null then
        raise exception 'The wallet number must be a Bangladesh mobile number' using errcode = '22023';
      end if;
      v_wallet_enc := private.encrypt_secret(v_wallet_plain);
      v_last4 := right(v_wallet_plain, 4);
    elsif v_existing.id is not null then
      v_wallet_enc := v_existing.wallet_number_enc;
      v_last4 := v_existing.number_last4;
    else
      raise exception 'The wallet number is required' using errcode = '22023';
    end if;
  elsif v_method is distinct from 'cash' then
    raise exception 'Choose bank, mobile wallet or cash' using errcode = '22023';
  end if;
  if v_method = 'mobile_wallet'
     and coalesce(private.jtext(p, 'wallet_provider'), '') not in ('bkash', 'nagad', 'rocket', 'upay', 'other') then
    raise exception 'Choose the wallet provider' using errcode = '22023';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'Invalid status' using errcode = '22023';
  end if;
  v_is_primary := v_is_primary and v_status = 'active';

  -- One primary account per employee: making this one primary demotes the others.
  if v_is_primary and v_status = 'active' then
    update public.employee_payment_accounts set is_primary = false
     where employee_id = v_employee.id and is_primary and id is distinct from v_account_id;
  end if;

  if v_account_id is null then
    insert into public.employee_payment_accounts (org_id, employee_id, method, bank_name, branch_name, routing_number,
                                                  account_name, account_number_enc, wallet_provider, wallet_number_enc,
                                                  number_last4, is_primary, status)
    values (v_employee.org_id, v_employee.id, v_method,
            case when v_method = 'bank' then private.jtext(p, 'bank_name') end,
            case when v_method = 'bank' then private.jtext(p, 'branch_name') end,
            case when v_method = 'bank' then private.jtext(p, 'routing_number') end,
            private.jtext(p, 'account_name'), v_account_enc,
            case when v_method = 'mobile_wallet' then private.jtext(p, 'wallet_provider') end,
            v_wallet_enc, v_last4, v_is_primary, v_status)
    returning id into v_account_id;
  else
    update public.employee_payment_accounts
       set bank_name = case when v_method = 'bank' then private.jtext(p, 'bank_name') end,
           branch_name = case when v_method = 'bank' then private.jtext(p, 'branch_name') end,
           routing_number = case when v_method = 'bank' then private.jtext(p, 'routing_number') end,
           account_name = private.jtext(p, 'account_name'),
           account_number_enc = v_account_enc,
           wallet_provider = case when v_method = 'mobile_wallet' then private.jtext(p, 'wallet_provider') end,
           wallet_number_enc = v_wallet_enc, number_last4 = v_last4,
           is_primary = v_is_primary, status = v_status
     where id = v_account_id;
  end if;
  return v_account_id;
end;
$$;

-- Shows the full number once, for someone allowed to see payment accounts.
-- Every reveal is written to the audit log (without the number).
create or replace function public.reveal_payment_account(p_account_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.employee_payment_accounts;
begin
  perform private.require_permission('payment_accounts.view');
  select * into v_account from public.employee_payment_accounts
  where id = p_account_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Payment account not found' using errcode = 'P0002';
  end if;
  perform private.write_audit(v_account.org_id, 'payment_account.revealed', 'employee_payment_accounts',
                              v_account.id, null, jsonb_build_object('employee_id', v_account.employee_id,
                                                                     'method', v_account.method));
  return coalesce(private.decrypt_secret(v_account.account_number_enc),
                  private.decrypt_secret(v_account.wallet_number_enc));
end;
$$;

-- The company confirms the statutory values (overtime divisor, half-day rule).
create or replace function public.confirm_payroll_statutory_values()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('payroll_settings.manage');
  update public.payroll_settings
     set statutory_confirmed_at = now(), statutory_confirmed_by = auth.uid()
   where org_id = private.current_org_id();
end;
$$;

-- KPI tiles for the salary screens.
create or replace function public.get_compensation_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  perform private.require_permission('compensation.view');
  return jsonb_build_object(
    'active_employees', (select count(*) from public.employees where org_id = v_org_id and status = 'active'),
    'with_pay', (select count(*) from public.employees e
                 where e.org_id = v_org_id and e.status = 'active'
                   and exists (select 1 from public.employee_compensation c
                               where c.employee_id = e.id and c.effective_to is null)),
    'monthly_gross', (select coalesce(sum(c.gross), 0) from public.employee_compensation c
                      join public.employees e on e.id = c.employee_id and e.status = 'active'
                      where c.org_id = v_org_id and c.effective_to is null),
    'templates', (select count(*) from public.salary_templates where org_id = v_org_id and status = 'active'),
    'pending_increments', (select count(*) from public.salary_increments
                           where org_id = v_org_id and status = 'pending'));
end;
$$;

-- =============================================================================
-- Read views (security barrier). Each filters by organization and permission.
-- =============================================================================
create or replace function private.money_viewer()
returns table (org_id uuid, employee_id uuid, see_pay boolean, see_increments boolean, see_deductions boolean,
               see_accounts boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_org_id(), private.current_employee_id(),
         private.has_permission('compensation.view'),
         private.has_permission('compensation.view') or private.has_permission('increments.approve'),
         private.has_permission('compensation.view') or private.has_permission('deductions.manage'),
         private.has_permission('payment_accounts.view') or private.has_permission('payment_accounts.edit')
$$;

-- Current pay of every employee (one row per employee; null pay = not set yet).
create view public.employee_pay_v with (security_barrier = true) as
select e.id as employee_id, e.org_id, e.full_name, e.card_id, e.status as employee_status, e.join_date,
       e.department_id, d.name as department_name, g.code as grade_code,
       c.id as compensation_id, c.template_id, t.name as template_name, c.basic, c.gross, c.total_deductions,
       c.effective_from, c.change_type,
       (select si.id from public.salary_increments si where si.employee_id = e.id and si.status = 'pending')
         as pending_increment_id
from private.money_viewer() v
join public.employees e on e.org_id = v.org_id
left join public.departments d on d.id = e.department_id
left join public.designations ds on ds.id = e.designation_id
left join public.grades g on g.id = ds.grade_id
left join public.employee_compensation c on c.employee_id = e.id and c.effective_to is null
left join public.salary_templates t on t.id = c.template_id
where v.see_pay;

create view public.salary_increments_v with (security_barrier = true) as
select si.*, e.full_name, e.card_id, t.name as template_name,
       requester.full_name as requested_by_name, approver.full_name as approved_by_name,
       (si.created_by = auth.uid()) as is_requester,
       (si.employee_id = v.employee_id) as is_self
from private.money_viewer() v
join public.salary_increments si on si.org_id = v.org_id
join public.employees e on e.id = si.employee_id
left join public.salary_templates t on t.id = si.template_id
left join public.user_profiles requester on requester.id = si.created_by
left join public.user_profiles approver on approver.id = si.approved_by
where v.see_increments;

create view public.employee_deductions_v with (security_barrier = true) as
select ed.*, e.full_name, e.card_id, (ed.employee_id = v.employee_id) as is_self
from private.money_viewer() v
join public.employee_deductions ed on ed.org_id = v.org_id
join public.employees e on e.id = ed.employee_id
where v.see_deductions or ed.employee_id = v.employee_id;

-- Payment accounts are always masked here; the employee sees their own.
create view public.payment_accounts_v with (security_barrier = true) as
select pa.id, pa.org_id, pa.employee_id, e.full_name, e.card_id, pa.method, pa.bank_name, pa.branch_name,
       pa.routing_number, pa.account_name, pa.wallet_provider, private.mask_number(pa.number_last4) as masked_number,
       pa.is_primary, pa.status, pa.created_at, pa.updated_at, (pa.employee_id = v.employee_id) as is_self
from private.money_viewer() v
join public.employee_payment_accounts pa on pa.org_id = v.org_id
join public.employees e on e.id = pa.employee_id
where v.see_accounts or pa.employee_id = v.employee_id;

-- =============================================================================
-- Privileges and RLS
-- =============================================================================
alter table public.payroll_settings            enable row level security;
alter table public.salary_components           enable row level security;
alter table public.salary_templates            enable row level security;
alter table public.salary_template_lines       enable row level security;
alter table public.employee_compensation       enable row level security;
alter table public.employee_compensation_lines enable row level security;
alter table public.salary_increments           enable row level security;
alter table public.bonuses                     enable row level security;
alter table public.bonus_eligibility           enable row level security;
alter table public.employee_deductions         enable row level security;
alter table public.employee_payment_accounts   enable row level security;

-- Protected tables: no direct access at all (views and RPCs only).
revoke all on table
  public.payroll_settings, public.salary_components, public.salary_templates, public.salary_template_lines,
  public.employee_compensation, public.employee_compensation_lines, public.salary_increments, public.bonuses,
  public.bonus_eligibility, public.employee_deductions, public.employee_payment_accounts
from anon, authenticated;

-- Configuration tables readable (and partly writable) through RLS.
grant select on table public.payroll_settings, public.salary_components, public.salary_templates,
                      public.salary_template_lines, public.bonuses, public.bonus_eligibility to authenticated;
grant update (deduct_base, ot_rate_basis, ot_hourly_divisor, pay_weekly_off, pay_holidays, half_day_deduction_percent,
              unpaid_leave_base, net_rounding, negative_net_rule, payslip_release, large_change_percent)
  on public.payroll_settings to authenticated;
grant insert (name, code, kind, calc, default_value, taxable, pf_applicable, sort_order, status),
      update (name, kind, calc, default_value, taxable, pf_applicable, sort_order, status)
  on public.salary_components to authenticated;

create policy payroll_settings_select on public.payroll_settings for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('payroll_settings.manage'))
              or (select private.has_permission('compensation.view'))));
create policy payroll_settings_update on public.payroll_settings for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('payroll_settings.manage')))
  with check (org_id = (select private.current_org_id()));

create policy salary_components_select on public.salary_components for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('compensation.view'))
              or (select private.has_permission('compensation.edit'))));
-- Only RPC-free inserts of ordinary components: the Basic component is seeded.
create policy salary_components_insert on public.salary_components for insert to authenticated
  with check (org_id = (select private.current_org_id()) and (select private.has_permission('compensation.edit'))
              and not is_basic);
create policy salary_components_update on public.salary_components for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('compensation.edit')))
  with check (org_id = (select private.current_org_id()));

create policy salary_templates_select on public.salary_templates for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('compensation.view'))
              or (select private.has_permission('compensation.edit'))));
create policy salary_template_lines_select on public.salary_template_lines for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('compensation.view'))
              or (select private.has_permission('compensation.edit'))));

create policy bonuses_select on public.bonuses for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('bonuses.manage'))
              or (select private.has_permission('compensation.view'))));
create policy bonus_eligibility_select on public.bonus_eligibility for select to authenticated
  using (org_id = (select private.current_org_id())
         and ((select private.has_permission('bonuses.manage'))
              or (select private.has_permission('compensation.view'))));

grant select on public.employee_pay_v, public.salary_increments_v, public.employee_deductions_v,
                public.payment_accounts_v to authenticated;
revoke all on public.employee_pay_v, public.salary_increments_v, public.employee_deductions_v,
              public.payment_accounts_v from anon;

revoke all on function
  public.save_salary_template(uuid, jsonb), public.preview_salary(uuid, numeric, numeric),
  public.set_initial_compensation(uuid, uuid, numeric, numeric, date, text),
  public.request_increment(uuid, jsonb), public.decide_increment(uuid, boolean, text),
  public.cancel_increment(uuid), public.get_increment_arrears(uuid, date),
  public.get_employee_compensation(uuid), public.save_bonus(uuid, jsonb), public.get_bonus_preview(uuid),
  public.create_deduction(jsonb), public.cancel_deduction(uuid, text),
  public.save_payment_account(uuid, jsonb), public.reveal_payment_account(uuid),
  public.confirm_payroll_statutory_values(), public.get_compensation_stats()
from public, anon;
grant execute on function
  public.save_salary_template(uuid, jsonb), public.preview_salary(uuid, numeric, numeric),
  public.set_initial_compensation(uuid, uuid, numeric, numeric, date, text),
  public.request_increment(uuid, jsonb), public.decide_increment(uuid, boolean, text),
  public.cancel_increment(uuid), public.get_increment_arrears(uuid, date),
  public.get_employee_compensation(uuid), public.save_bonus(uuid, jsonb), public.get_bonus_preview(uuid),
  public.create_deduction(jsonb), public.cancel_deduction(uuid, text),
  public.save_payment_account(uuid, jsonb), public.reveal_payment_account(uuid),
  public.confirm_payroll_statutory_values(), public.get_compensation_stats()
to authenticated;

-- Internal functions: never callable through the API.
revoke all on function
  private.seed_payroll_permissions(uuid), private.seed_payroll_defaults(uuid), private.seed_org_defaults(uuid),
  private.encrypt_secret(text), private.decrypt_secret(bytea),
  private.resolve_salary(uuid, numeric, numeric), private.compensation_on(uuid, date),
  private.create_compensation(uuid, uuid, numeric, numeric, date, text, uuid, text),
  private.assert_org_employee(uuid), private.assert_not_self_money(uuid), private.audit_row_change()
from public, anon, authenticated;
-- Used inside RLS policies and views evaluated as the caller.
grant execute on function private.money_viewer(), private.mask_number(text) to authenticated;

-- Existing organizations get the Part 3A defaults now.
select private.seed_payroll_defaults(id) from public.organizations;
