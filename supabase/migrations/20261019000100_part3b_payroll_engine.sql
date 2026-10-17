-- =============================================================================
-- Olympus HRIS — Part 3B: Payroll engine (without tax and PF; those are 3C)
--
-- Run lifecycle: draft -> calculated -> reviewed -> approved -> paid -> locked
--   * The preparer (whoever last calculated) can never approve the run.
--   * Recalculation is allowed until approval and always gives the same slips
--     for the same inputs. A change to any input marks the run stale.
--   * Approval freezes the slips and posts their side effects: loan / advance
--     installments, back-dated increment arrears and payroll adjustments are
--     marked as paid, and one payment batch per payment method is created.
--     Reopening (permission + reason, audited) reverses exactly those postings.
--   * Locking a run of the whole organization also locks that month's
--     attendance, leave and overtime (Part 2 period lock).
--
-- Calculation per employee and month (Part 3 doc, section 2.3), 30-day basis:
--   earnings      every earning line of the pay snapshot at its full monthly value
--   proration     - gross * days not employed / 30 (joiners and leavers)
--   overtime      approved minutes / 60 * (OT base / hourly divisor) * multiplier
--   bonuses       due this month, eligibility and minimum service as in 3A
--   arrears       back-dated increments, for months already paid at the old pay
--   adjustments   approved earning / deduction corrections for this month
--   absence       deduction base / 30 * absent days (+ half days at the set %)
--   unpaid leave  unpaid-leave base / 30 * days on unpaid leave
--   late penalty  the company's own policy from Part 2 (days or taka)
--   loans         installment, never more than the remaining balance
--   carry         shortfall carried from last month's negative net
--   net           gross - deductions, rounded by the net-rounding setting;
--                 negative -> zero and carry, or a blocker (setting)
--
-- Money: numeric everywhere, every line rounded to 2 decimals (half away from
-- zero). Tables are closed to API roles; reads and writes go through RPCs.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Permissions
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('payroll.view_own', 'payroll', 'See own payslips once released',                          false),
  ('payroll.prepare',  'payroll', 'Create and calculate payroll runs, add adjustments',      false),
  ('payroll.review',   'payroll', 'Review a calculated payroll run',                         false),
  ('payroll.approve',  'payroll', 'Approve payroll runs and adjustments, mark payments paid', false),
  ('payroll.reopen',   'payroll', 'Reopen an approved payroll run (with a reason)',          false),
  ('payroll.lock',     'payroll', 'Lock a paid payroll run and its month',                   false),
  ('payment.export',   'payroll', 'Download payment sheets with full account numbers',       false)
on conflict (key) do nothing;

-- Day-to-day preparation and review sit with HR. Approval, reopening, locking
-- and payment exports stay with the Admin until the Admin ticks them for a role.
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
      'payment_accounts.view', 'payment_accounts.edit', 'payroll.view_own', 'payroll.prepare', 'payroll.review']
    when 'manager'  then array['payroll.view_own']
    when 'employee' then array['payroll.view_own']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
end;
$$;

select private.seed_payroll_permissions(id) from public.organizations;

-- Anyone who works on payroll runs (sees every slip of the organization).
create or replace function private.is_payroll_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('payroll.prepare') or private.has_permission('payroll.review')
      or private.has_permission('payroll.approve') or private.has_permission('payroll.reopen')
      or private.has_permission('payroll.lock')
$$;

-- -----------------------------------------------------------------------------
-- 2. Tables
-- -----------------------------------------------------------------------------
create table public.payroll_runs (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null references public.organizations (id),
  period_month     date not null check (extract(day from period_month) = 1),
  scope            text not null default 'all' check (scope in ('all', 'branch', 'department')),
  scope_id         uuid,
  status           text not null default 'draft'
                   check (status in ('draft', 'calculated', 'reviewed', 'approved', 'paid', 'locked', 'cancelled')),
  inputs_fingerprint text,
  prepared_by      uuid references public.user_profiles (id),
  calculated_at    timestamptz,
  reviewed_by      uuid references public.user_profiles (id),
  reviewed_at      timestamptz,
  approved_by      uuid references public.user_profiles (id),
  approved_at      timestamptz,
  paid_at          timestamptz,
  locked_by        uuid references public.user_profiles (id),
  locked_at        timestamptz,
  reopen_count     smallint not null default 0,
  employee_count   integer not null default 0,
  total_gross      numeric(14, 2) not null default 0,
  total_deductions numeric(14, 2) not null default 0,
  total_net        numeric(14, 2) not null default 0,
  warning_count    integer not null default 0,
  blocker_count    integer not null default 0,
  run_warnings     jsonb not null default '[]',
  note             text check (note is null or char_length(note) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint payroll_runs_org_id_id_uq unique (org_id, id),
  constraint payroll_runs_scope_target check ((scope = 'all') = (scope_id is null))
);
-- One live run per organization, month and scope.
create unique index payroll_runs_one_live_uq
  on public.payroll_runs (org_id, period_month, scope, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'))
  where status <> 'cancelled';

create table public.payroll_slips (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null,
  run_id              uuid not null,
  employee_id         uuid not null,
  period_month        date not null,
  compensation_id     uuid,
  monthly_basic       numeric(12, 2) not null default 0,
  monthly_gross       numeric(12, 2) not null default 0,
  employed_days       smallint not null default 0 check (employed_days between 0 and 30),
  payable_days        numeric(5, 2) not null default 0,
  absent_days         smallint not null default 0,
  half_days           smallint not null default 0,
  unpaid_leave_days   smallint not null default 0,
  late_count          smallint not null default 0,
  overtime_minutes    integer not null default 0,
  gross_earnings      numeric(12, 2) not null default 0,
  total_deductions    numeric(12, 2) not null default 0,
  net_before_rounding numeric(12, 2) not null default 0,
  rounding_adjustment numeric(12, 2) not null default 0,
  net                 numeric(12, 2) not null default 0 check (net >= 0),
  carry_forward_out   numeric(12, 2) not null default 0 check (carry_forward_out >= 0),
  payment_account_id  uuid,
  payment_method      text check (payment_method in ('bank', 'mobile_wallet', 'cash')),
  payment_status      text not null default 'pending' check (payment_status in ('pending', 'paid')),
  warnings            jsonb not null default '[]',
  has_blocker         boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint payroll_slips_org_id_id_uq unique (org_id, id),
  constraint payroll_slips_run_fk foreign key (org_id, run_id) references public.payroll_runs (org_id, id),
  constraint payroll_slips_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint payroll_slips_compensation_fk foreign key (org_id, compensation_id)
    references public.employee_compensation (org_id, id),
  -- An employee is paid by one run per month.
  constraint payroll_slips_employee_month_uq unique (employee_id, period_month)
);
create index payroll_slips_run_idx on public.payroll_slips (run_id);

create table public.payroll_slip_lines (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  slip_id     uuid not null,
  direction   text not null check (direction in ('earning', 'deduction')),
  line_type   text not null check (line_type in (
                'earning', 'proration', 'overtime', 'bonus', 'arrear', 'adjustment',
                'component_deduction', 'absence', 'half_day', 'unpaid_leave', 'unpaid_off_day', 'late',
                'loan', 'carry_forward')),
  code        text not null,
  label       text not null,
  base        numeric(14, 4),          -- e.g. daily or hourly rate, or the pay the percent applies to
  rate        numeric(10, 4),          -- e.g. percent, multiplier
  quantity    numeric(10, 2),          -- e.g. days, hours
  amount      numeric(12, 2) not null,
  source_table text,
  source_id   uuid,
  sort_order  smallint not null default 100,
  constraint payroll_slip_lines_slip_fk foreign key (org_id, slip_id) references public.payroll_slips (org_id, id)
    on delete cascade,
  constraint payroll_slip_lines_sign check (amount >= 0 or line_type = 'proration')
);
create index payroll_slip_lines_slip_idx on public.payroll_slip_lines (slip_id);

-- The only way to change pay of a closed period: a dated correction applied in
-- an open month. Maker-checker like increments.
create table public.payroll_adjustments (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  employee_id    uuid not null,
  apply_month    date not null check (extract(day from apply_month) = 1),
  type           text not null check (type in ('arrear', 'correction', 'manual')),
  direction      text not null check (direction in ('earning', 'deduction')),
  amount         numeric(12, 2) not null check (amount > 0 and amount <= 99999999),
  reason         text not null check (char_length(btrim(reason)) between 3 and 500),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'applied', 'cancelled')),
  approved_by    uuid references public.user_profiles (id),
  decided_at     timestamptz,
  applied_run_id uuid,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint payroll_adjustments_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint payroll_adjustments_run_fk foreign key (org_id, applied_run_id) references public.payroll_runs (org_id, id)
);

create table public.payment_batches (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  run_id      uuid not null,
  method      text not null check (method in ('bank', 'mobile_wallet', 'cash', 'unassigned')),
  row_count   integer not null,
  total       numeric(14, 2) not null,
  status      text not null default 'generated' check (status in ('generated', 'exported', 'paid')),
  exported_at timestamptz,
  exported_by uuid references public.user_profiles (id),
  paid_at     timestamptz,
  reference   text check (reference is null or char_length(reference) <= 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint payment_batches_run_fk foreign key (org_id, run_id) references public.payroll_runs (org_id, id)
    on delete cascade,
  constraint payment_batches_run_method_uq unique (run_id, method)
);

-- Arrears of an approved increment are paid once; remember the slip.
alter table public.salary_increments add column arrears_slip_id uuid;

-- -----------------------------------------------------------------------------
-- 3. Guards: frozen slips stay frozen
-- -----------------------------------------------------------------------------
-- Slips and lines change only while their run is open (draft / calculated /
-- reviewed). Payment marking on an approved run sets a transaction-local flag.
-- Shared check: may the slip still change? (Its run must be open, unless an
-- approved run is being marked as paid.)
create or replace function private.assert_slip_open(p_slip_id uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_run_status text;
begin
  select r.status into v_run_status
  from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id
  where s.id = p_slip_id;
  if v_run_status in ('approved', 'paid', 'locked')
     and coalesce(current_setting('olympus.payroll_posting', true), '') <> 'on' then
    raise exception 'This payroll run is approved; its slips cannot change. Reopen it or use an adjustment.'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function private.payroll_slip_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.assert_slip_open(old.id);
  return coalesce(new, old);
end;
$$;

create or replace function private.payroll_slip_line_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.assert_slip_open(old.slip_id);
  return coalesce(new, old);
end;
$$;

create trigger payroll_slip_guard before update or delete on public.payroll_slips
  for each row execute function private.payroll_slip_guard();
create trigger payroll_slip_line_guard before update or delete on public.payroll_slip_lines
  for each row execute function private.payroll_slip_line_guard();

create or replace function private.begin_payroll_posting()
returns void
language sql
set search_path = ''
as $$
  select set_config('olympus.payroll_posting', 'on', true)
$$;

create or replace function private.end_payroll_posting()
returns void
language sql
set search_path = ''
as $$
  select set_config('olympus.payroll_posting', 'off', true)
$$;

create trigger set_row_meta before insert or update on public.payroll_runs
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.payroll_runs
  for each row execute function private.audit_row_change();
select private.attach_standard_triggers('public.payroll_adjustments');
create trigger touch before update on public.payroll_slips
  for each row execute function private.touch_updated_at();
create trigger touch before update on public.payment_batches
  for each row execute function private.touch_updated_at();
create trigger audit after insert or update or delete on public.payment_batches
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- 4. Calculation helpers
-- -----------------------------------------------------------------------------
create or replace function private.month_end(p_month date)
returns date
language sql
immutable
set search_path = ''
as $$
  select (date_trunc('month', p_month) + interval '1 month - 1 day')::date
$$;

-- Days employed in the month on the 30-day basis: the days before joining and
-- after leaving are unpaid; leaving on or after the month end is a full month.
create or replace function private.employed_days(p_month date, p_join_date date, p_exit_date date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select greatest(0,
    (case when p_exit_date is null or p_exit_date >= private.month_end(p_month) then 30
          else least(extract(day from p_exit_date)::int, 30) end)
    - (case when p_join_date > p_month then extract(day from p_join_date)::int - 1 else 0 end))
$$;

-- Applies the net-rounding setting to an amount already rounded to paisa.
create or replace function private.round_net(p_amount numeric, p_rule text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_rule
    when 'nearest_taka' then round(p_amount, 0)
    when 'up_taka'      then ceil(p_amount)
    when 'down_taka'    then floor(p_amount)
    else round(p_amount, 2)
  end
$$;

-- Changes whenever any payroll input of the organization and month changes.
-- A run whose stored fingerprint differs is stale and must be recalculated.
create or replace function private.payroll_inputs_fingerprint(p_org_id uuid, p_month date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(concat_ws('|',
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.attendance_records
      where org_id = p_org_id and work_date between p_month and private.month_end(p_month)),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') || ':' || coalesce(sum(minutes), 0)
       from public.overtime_records
      where org_id = p_org_id and work_date between p_month and private.month_end(p_month) and status = 'approved'),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.employee_compensation where org_id = p_org_id),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.salary_increments where org_id = p_org_id),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.bonuses
      where org_id = p_org_id and payment_month = p_month),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.employee_deductions where org_id = p_org_id),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.payroll_adjustments
      where org_id = p_org_id and apply_month = p_month),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.employees where org_id = p_org_id),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.employee_payment_accounts where org_id = p_org_id),
    (select coalesce(max(updated_at)::text, '') from public.payroll_settings where org_id = p_org_id),
    (select coalesce(max(updated_at)::text, '') from public.org_work_settings where org_id = p_org_id),
    (select count(*) || ':' || coalesce(sum(s.net), 0) || ':' || coalesce(sum(s.carry_forward_out), 0)
       from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id
      where s.org_id = p_org_id and s.period_month = (p_month - interval '1 month')::date
        and r.status in ('approved', 'paid', 'locked'))))
$$;

-- Arrears of approved, back-dated increments not paid yet: for every month
-- from the effective month up to (not including) p_month whose slip was paid
-- at a different pay, the gross difference on the 30-day basis. The first
-- month counts only the days from the effective date.
create or replace function private.increment_arrears_due(p_employee_id uuid, p_month date)
returns table (increment_id uuid, amount numeric, months integer)
language sql
stable
security definer
set search_path = ''
as $$
  select si.id,
         coalesce(sum(private.round_money(
           (si.new_gross - s.monthly_gross)
           * case when s.period_month = private.month_start(si.effective_date)
                  then private.paid_days_from(si.effective_date) else 30 end / 30)), 0),
         count(s.id)::int
  from public.salary_increments si
  join public.payroll_slips s on s.employee_id = si.employee_id
  join public.payroll_runs r on r.id = s.run_id and r.status in ('approved', 'paid', 'locked')
  where si.employee_id = p_employee_id and si.status = 'approved' and si.arrears_slip_id is null
    and si.compensation_id is not null
    and si.effective_date < p_month
    and s.period_month >= private.month_start(si.effective_date) and s.period_month < p_month
    and s.compensation_id is distinct from si.compensation_id
  group by si.id
  having count(s.id) > 0
$$;

-- -----------------------------------------------------------------------------
-- 5. The engine: one slip for one employee and month (inside a run)
-- -----------------------------------------------------------------------------
create or replace function private.calculate_slip(p_run_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run           public.payroll_runs;
  v_employee      public.employees;
  v_settings      public.payroll_settings;
  v_work          public.org_work_settings;
  v_compensation  public.employee_compensation;
  v_month_end     date;
  v_slip_id       uuid;
  v_employed      integer;
  v_not_employed  integer;
  v_absent        integer := 0;
  v_half_days     integer := 0;
  v_unpaid_leave  integer := 0;
  v_unpaid_off    integer := 0;
  v_late_count    integer := 0;
  v_ot_minutes    integer := 0;
  v_deduct_daily  numeric;
  v_leave_daily   numeric;
  v_ot_hourly     numeric;
  v_gross         numeric := 0;
  v_deductions    numeric := 0;
  v_net_raw       numeric;
  v_net           numeric;
  v_carry_out     numeric := 0;
  v_warnings      jsonb := '[]';
  v_blocker       boolean := false;
  v_account       public.employee_payment_accounts;
  v_previous_net  numeric;
  v_previous_carry numeric;
  v_late_days     numeric;
  v_row           record;
begin
  select * into v_run from public.payroll_runs where id = p_run_id;
  select * into v_employee from public.employees where id = p_employee_id;
  select * into v_settings from public.payroll_settings where org_id = v_run.org_id;
  select * into v_work from public.org_work_settings where org_id = v_run.org_id;
  v_month_end := private.month_end(v_run.period_month);

  -- The pay in force at the start of the month (or on the joining day). A
  -- change later in the month is paid as arrears next month.
  v_compensation := private.compensation_on(p_employee_id, greatest(v_run.period_month, v_employee.join_date));
  if v_compensation.id is null then
    v_compensation := private.compensation_on(p_employee_id, least(v_month_end, coalesce(v_employee.exit_date, v_month_end)));
  end if;

  v_employed := private.employed_days(v_run.period_month, v_employee.join_date, v_employee.exit_date);
  v_not_employed := 30 - v_employed;

  insert into public.payroll_slips (org_id, run_id, employee_id, period_month, compensation_id, monthly_basic,
                                    monthly_gross, employed_days)
  values (v_run.org_id, p_run_id, p_employee_id, v_run.period_month, v_compensation.id,
          coalesce(v_compensation.basic, 0), coalesce(v_compensation.gross, 0), v_employed)
  returning id into v_slip_id;

  if v_compensation.id is null then
    update public.payroll_slips
       set has_blocker = true,
           warnings = jsonb_build_array(jsonb_build_object('code', 'missing_compensation', 'severity', 'blocker',
                                                           'message', 'No pay on record for this month'))
     where id = v_slip_id;
    return;
  end if;

  -- Attendance of the month (Part 2 derived records).
  select count(*) filter (where status = 'absent'),
         count(*) filter (where status = 'half_day'),
         count(*) filter (where is_late),
         count(*) filter (where status = 'weekend' and not v_settings.pay_weekly_off)
           + count(*) filter (where status = 'holiday' and not v_settings.pay_holidays)
    into v_absent, v_half_days, v_late_count, v_unpaid_off
  from public.attendance_records
  where employee_id = p_employee_id and work_date between v_run.period_month and v_month_end;

  select count(*) into v_unpaid_leave
  from public.attendance_records r
  where r.employee_id = p_employee_id and r.status = 'on_leave'
    and r.work_date between v_run.period_month and v_month_end
    and exists (select 1 from public.leave_requests lr
                join public.leave_types lt on lt.id = lr.leave_type_id and not lt.paid
                where lr.employee_id = p_employee_id and lr.status = 'approved'
                  and r.work_date between lr.from_date and lr.to_date);

  v_deduct_daily := case v_settings.deduct_base when 'gross' then v_compensation.gross else v_compensation.basic end / 30;
  v_leave_daily  := case v_settings.unpaid_leave_base when 'gross' then v_compensation.gross else v_compensation.basic end / 30;
  v_ot_hourly    := case v_settings.ot_rate_basis when 'gross' then v_compensation.gross else v_compensation.basic end
                    / v_settings.ot_hourly_divisor;

  -- Earnings and deduction components of the pay snapshot, at full monthly value.
  insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                         amount, source_table, source_id, sort_order)
  select v_run.org_id, v_slip_id,
         l.kind, case l.kind when 'earning' then 'earning' else 'component_deduction' end,
         l.code, l.name, null, l.rate, 1, l.amount, 'employee_compensation_lines', l.id, l.sort_order
  from public.employee_compensation_lines l
  where l.compensation_id = v_compensation.id;

  -- Joiner / leaver proration on the 30-day basis.
  if v_not_employed > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'earning', 'proration', 'PRORATION', 'Days not employed',
            v_compensation.gross, null, v_not_employed,
            -private.round_money(v_compensation.gross * v_not_employed / 30), 500);
  end if;

  -- Overtime: approved minutes grouped by day type and multiplier (every grade).
  for v_row in
    select o.day_type, o.multiplier, sum(o.minutes) as minutes
    from public.overtime_records o
    where o.employee_id = p_employee_id and o.status = 'approved'
      and o.work_date between v_run.period_month and v_month_end
    group by o.day_type, o.multiplier
    order by o.day_type
  loop
    v_ot_minutes := v_ot_minutes + v_row.minutes;
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'earning', 'overtime', 'OT_' || upper(v_row.day_type),
            'Overtime (' || v_row.day_type || ') ×' || trim(trailing '.' from trim(trailing '0' from v_row.multiplier::text)),
            round(v_ot_hourly, 4), v_row.multiplier, round(v_row.minutes / 60.0, 2),
            private.round_money(v_row.minutes / 60.0 * v_ot_hourly * v_row.multiplier), 600);
  end loop;

  -- Bonuses due this month: in scope, enough completed service at the month end.
  insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                         amount, source_table, source_id, sort_order)
  select v_run.org_id, v_slip_id, 'earning', 'bonus', 'BONUS', b.name,
         case b.basis when 'percent' then case b.percent_base when 'basic' then v_compensation.basic else v_compensation.gross end end,
         b.percent, 1,
         case b.basis when 'fixed' then b.amount
              else private.round_money(case b.percent_base when 'basic' then v_compensation.basic
                                                            else v_compensation.gross end * b.percent / 100) end,
         'bonuses', b.id, 700
  from public.bonuses b
  where b.org_id = v_run.org_id and b.status = 'active' and b.payment_month = v_run.period_month
    and private.service_months(v_employee.join_date, v_month_end) >= b.min_service_months
    and (b.scope = 'all'
         or (b.scope = 'departments' and exists (select 1 from public.bonus_eligibility be
                                                 where be.bonus_id = b.id and be.department_id = v_employee.department_id))
         or (b.scope = 'employees' and exists (select 1 from public.bonus_eligibility be
                                               where be.bonus_id = b.id and be.employee_id = p_employee_id)));

  -- Arrears of back-dated increments.
  insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                         amount, source_table, source_id, sort_order)
  select v_run.org_id, v_slip_id, 'earning', 'arrear', 'ARREAR', 'Increment arrears', null, null, a.months,
         a.amount, 'salary_increments', a.increment_id, 800
  from private.increment_arrears_due(p_employee_id, v_run.period_month) a
  where a.amount > 0;

  -- Approved adjustments for this month (earning and deduction side).
  insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                         amount, source_table, source_id, sort_order)
  select v_run.org_id, v_slip_id, a.direction, 'adjustment', 'ADJUST_' || upper(a.type),
         initcap(a.type) || ': ' || left(a.reason, 80), null, null, 1, a.amount, 'payroll_adjustments', a.id,
         case a.direction when 'earning' then 900 else 1900 end
  from public.payroll_adjustments a
  where a.employee_id = p_employee_id and a.apply_month = v_run.period_month and a.status = 'approved';

  -- Absence, half days, unpaid leave and unpaid off days.
  if v_absent > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'absence', 'ABSENCE', 'Absent days', round(v_deduct_daily, 4), null,
            v_absent, private.round_money(v_deduct_daily * v_absent), 1100);
  end if;
  if v_half_days > 0 and v_settings.half_day_deduction_percent > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'half_day', 'HALF_DAY', 'Half days', round(v_deduct_daily, 4),
            v_settings.half_day_deduction_percent, v_half_days,
            private.round_money(v_deduct_daily * v_settings.half_day_deduction_percent / 100 * v_half_days), 1110);
  end if;
  if v_unpaid_leave > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'unpaid_leave', 'UNPAID_LEAVE', 'Unpaid leave', round(v_leave_daily, 4),
            null, v_unpaid_leave, private.round_money(v_leave_daily * v_unpaid_leave), 1120);
  end if;
  if v_unpaid_off > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'unpaid_off_day', 'UNPAID_OFF', 'Unpaid weekly off / holidays',
            round(v_deduct_daily, 4), null, v_unpaid_off, private.round_money(v_deduct_daily * v_unpaid_off), 1130);
  end if;

  -- Late penalty from the company's own Part 2 policy.
  if v_late_count > 0 and v_work.late_deduction_mode = 'days_per_lates' then
    v_late_days := floor(v_late_count / v_work.lates_per_deduction::numeric) * v_work.late_deduction_days;
    if v_late_days > 0 then
      insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                             amount, sort_order)
      values (v_run.org_id, v_slip_id, 'deduction', 'late', 'LATE', v_late_count || ' lates', round(v_deduct_daily, 4),
              null, v_late_days, private.round_money(v_deduct_daily * v_late_days), 1200);
    end if;
  elsif v_late_count > 0 and v_work.late_deduction_mode = 'amount_per_late' and v_work.late_amount_per_late > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'late', 'LATE', v_late_count || ' lates', v_work.late_amount_per_late,
            null, v_late_count, private.round_money(v_work.late_amount_per_late * v_late_count), 1200);
  end if;

  -- Loan and advance installments (never more than what is left).
  insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                         amount, source_table, source_id, sort_order)
  select v_run.org_id, v_slip_id, 'deduction', 'loan', upper(d.type), initcap(d.type) || coalesce(': ' || left(d.description, 60), ''),
         d.remaining, null, 1, least(d.installment, d.remaining), 'employee_deductions', d.id, 1300
  from public.employee_deductions d
  where d.employee_id = p_employee_id and d.status = 'active' and d.remaining > 0 and d.start_month <= v_run.period_month;

  -- Shortfall carried from last month's negative net.
  select s.net, s.carry_forward_out into v_previous_net, v_previous_carry
  from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id and r.status in ('approved', 'paid', 'locked')
  where s.employee_id = p_employee_id and s.period_month = (v_run.period_month - interval '1 month')::date;
  if coalesce(v_previous_carry, 0) > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_run.org_id, v_slip_id, 'deduction', 'carry_forward', 'CARRY', 'Shortfall from last month', null, null, 1,
            v_previous_carry, 1400);
  end if;

  -- Totals, rounding and the negative-net rule.
  select coalesce(sum(amount) filter (where direction = 'earning'), 0),
         coalesce(sum(amount) filter (where direction = 'deduction'), 0)
    into v_gross, v_deductions
  from public.payroll_slip_lines where slip_id = v_slip_id;

  v_net_raw := v_gross - v_deductions;
  if v_net_raw < 0 then
    if v_settings.negative_net_rule = 'zero_and_carry' then
      v_carry_out := -v_net_raw;
      v_net := 0;
      v_warnings := v_warnings || jsonb_build_object('code', 'negative_net', 'severity', 'warning',
        'message', 'Deductions exceed earnings; ' || v_carry_out || ' carried to next month');
    else
      v_net := 0;
      v_blocker := true;
      v_warnings := v_warnings || jsonb_build_object('code', 'negative_net', 'severity', 'blocker',
        'message', 'Deductions exceed earnings by ' || (-v_net_raw));
    end if;
  else
    v_net := private.round_net(v_net_raw, v_settings.net_rounding);
  end if;

  -- Payment account: the primary active one, else any active one.
  select * into v_account from public.employee_payment_accounts
  where employee_id = p_employee_id and status = 'active'
  order by is_primary desc, created_at limit 1;
  if v_account.id is null then
    v_warnings := v_warnings || jsonb_build_object('code', 'missing_payment_account', 'severity', 'warning',
      'message', 'No bank, wallet or cash account on record');
  end if;

  if v_previous_net is not null and v_previous_net > 0
     and abs(v_net - v_previous_net) / v_previous_net * 100 > v_settings.large_change_percent then
    v_warnings := v_warnings || jsonb_build_object('code', 'large_change', 'severity', 'warning',
      'message', 'Net changed by ' || round(abs(v_net - v_previous_net) / v_previous_net * 100) || '% from last month');
  end if;

  if v_employed > 0 and not exists (select 1 from public.attendance_records
                                    where employee_id = p_employee_id
                                      and work_date between v_run.period_month and v_month_end) then
    v_warnings := v_warnings || jsonb_build_object('code', 'no_attendance', 'severity', 'warning',
      'message', 'No attendance recorded this month (paid in full)');
  end if;

  update public.payroll_slips
     set absent_days = v_absent, half_days = v_half_days, unpaid_leave_days = v_unpaid_leave, late_count = v_late_count,
         overtime_minutes = v_ot_minutes,
         payable_days = greatest(0, v_employed - v_absent - v_unpaid_leave - v_unpaid_off
                                    - v_half_days * v_settings.half_day_deduction_percent / 100),
         gross_earnings = v_gross, total_deductions = v_deductions,
         net_before_rounding = case when v_net_raw < 0 then v_net_raw else private.round_money(v_net_raw) end,
         rounding_adjustment = case when v_net_raw < 0 then 0 else v_net - private.round_money(v_net_raw) end,
         net = v_net, carry_forward_out = v_carry_out,
         payment_account_id = v_account.id, payment_method = v_account.method,
         warnings = v_warnings, has_blocker = v_blocker
   where id = v_slip_id;
end;
$$;

-- Employees a run covers: employed at some point in the month, in scope, and
-- not already paid by another live run of the same month.
create or replace function private.run_employees(p_run_id uuid)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.id
  from public.payroll_runs r
  join public.employees e on e.org_id = r.org_id
  where r.id = p_run_id
    and e.join_date <= private.month_end(r.period_month)
    and (e.exit_date is null or e.exit_date >= r.period_month)
    and (r.scope = 'all'
         or (r.scope = 'branch' and e.branch_id = r.scope_id)
         or (r.scope = 'department' and e.department_id = r.scope_id))
    and not exists (select 1 from public.payroll_slips s
                    join public.payroll_runs other on other.id = s.run_id and other.status <> 'cancelled'
                    where s.employee_id = e.id and s.period_month = r.period_month and s.run_id <> r.id)
  order by e.full_name, e.id
$$;

create or replace function private.refresh_run_totals(p_run_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.payroll_runs r
     set employee_count   = t.employees,
         total_gross      = t.gross,
         total_deductions = t.deductions,
         total_net        = t.net,
         warning_count    = t.warnings,
         blocker_count    = t.blockers
    from (select count(*) as employees, coalesce(sum(gross_earnings), 0) as gross,
                 coalesce(sum(total_deductions), 0) as deductions, coalesce(sum(net), 0) as net,
                 coalesce(sum(jsonb_array_length(warnings)), 0) as warnings,
                 count(*) filter (where has_blocker) as blockers
          from public.payroll_slips where run_id = p_run_id) t
   where r.id = p_run_id
$$;

create or replace function private.load_run_for_update(p_run_id uuid)
returns public.payroll_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  select * into v_run from public.payroll_runs where id = p_run_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Payroll run not found' using errcode = 'P0002';
  end if;
  return v_run;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. Run lifecycle RPCs
-- -----------------------------------------------------------------------------
create or replace function public.create_payroll_run(p_period_month date, p_scope text default 'all',
                                                     p_scope_id uuid default null, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_month  date := private.month_start(p_period_month);
  v_run_id uuid;
begin
  perform private.require_permission('payroll.prepare');
  if p_period_month is null then
    raise exception 'Choose the payroll month' using errcode = '22023';
  end if;
  if coalesce(p_scope, '') not in ('all', 'branch', 'department') then
    raise exception 'Choose all, a branch or a department' using errcode = '22023';
  end if;
  if (p_scope = 'all') <> (p_scope_id is null) then
    raise exception 'Choose the branch or department for this run' using errcode = '22023';
  end if;
  if p_scope = 'branch' and not exists (select 1 from public.branches where id = p_scope_id and org_id = v_org_id) then
    raise exception 'Branch not found' using errcode = 'P0002';
  end if;
  if p_scope = 'department' and not exists (select 1 from public.departments where id = p_scope_id and org_id = v_org_id) then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if v_month > private.month_start(private.org_today(v_org_id)) then
    raise exception 'Payroll cannot be run for a future month' using errcode = '22023';
  end if;

  insert into public.payroll_runs (org_id, period_month, scope, scope_id, note)
  values (v_org_id, v_month, p_scope, p_scope_id, nullif(btrim(p_note), ''))
  returning id into v_run_id;
  return v_run_id;
exception
  when unique_violation then
    raise exception 'A payroll run for this month and scope already exists' using errcode = '23505';
end;
$$;

-- Calculates (or recalculates) every slip of the run. Repeatable: the old slips
-- of this run are replaced and the same inputs give the same result.
create or replace function public.calculate_payroll_run(p_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run         public.payroll_runs;
  v_employee_id uuid;
  v_run_warnings jsonb := '[]';
begin
  perform private.require_permission('payroll.prepare');
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status not in ('draft', 'calculated', 'reviewed') then
    raise exception 'Only a draft, calculated or reviewed run can be calculated (status: %)', v_run.status
      using errcode = '22023';
  end if;

  delete from public.payroll_slips where run_id = p_run_id;
  for v_employee_id in select private.run_employees(p_run_id) loop
    perform private.calculate_slip(p_run_id, v_employee_id);
  end loop;

  if not private.is_locked(v_run.org_id, private.month_end(v_run.period_month)) then
    v_run_warnings := v_run_warnings || jsonb_build_object('code', 'attendance_not_locked', 'severity', 'warning',
      'message', 'Attendance for this month is not locked yet; it can still change');
  end if;
  if exists (select 1 from public.payroll_settings where org_id = v_run.org_id and statutory_confirmed_at is null) then
    v_run_warnings := v_run_warnings || jsonb_build_object('code', 'statutory_unconfirmed', 'severity', 'warning',
      'message', 'Statutory payroll values (overtime divisor, half-day %) are not confirmed');
  end if;

  update public.payroll_runs
     set status = 'calculated', prepared_by = auth.uid(), calculated_at = now(),
         reviewed_by = null, reviewed_at = null, run_warnings = v_run_warnings,
         inputs_fingerprint = private.payroll_inputs_fingerprint(v_run.org_id, v_run.period_month)
   where id = p_run_id;
  perform private.refresh_run_totals(p_run_id);

  return (select jsonb_build_object('employee_count', employee_count, 'total_net', total_net,
                                    'blocker_count', blocker_count, 'warning_count', warning_count)
          from public.payroll_runs where id = p_run_id);
end;
$$;

create or replace function private.assert_run_fresh(p_run public.payroll_runs)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_run.inputs_fingerprint is distinct from private.payroll_inputs_fingerprint(p_run.org_id, p_run.period_month) then
    raise exception 'Payroll inputs changed after calculation; recalculate the run first' using errcode = '22023';
  end if;
  if p_run.blocker_count > 0 then
    raise exception '% slip(s) have blockers; fix them and recalculate', p_run.blocker_count using errcode = '22023';
  end if;
end;
$$;

create or replace function public.review_payroll_run(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  perform private.require_permission('payroll.review');
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status <> 'calculated' then
    raise exception 'Only a calculated run can be reviewed (status: %)', v_run.status using errcode = '22023';
  end if;
  perform private.assert_run_fresh(v_run);
  update public.payroll_runs set status = 'reviewed', reviewed_by = auth.uid(), reviewed_at = now() where id = p_run_id;
end;
$$;

-- Approval freezes the slips and posts their side effects in one transaction.
create or replace function public.approve_payroll_run(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  perform private.require_permission('payroll.approve');
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status <> 'reviewed' then
    raise exception 'Only a reviewed run can be approved (status: %)', v_run.status using errcode = '22023';
  end if;
  if v_run.prepared_by = auth.uid() then
    raise exception 'You prepared this run, so someone else must approve it' using errcode = '42501';
  end if;
  perform private.assert_run_fresh(v_run);

  -- Loan and advance installments reduce the balance; zero completes the loan.
  update public.employee_deductions d
     set remaining = d.remaining - l.amount,
         status = case when d.remaining - l.amount <= 0 then 'completed' else d.status end
    from (select l.source_id, sum(l.amount) as amount
          from public.payroll_slip_lines l join public.payroll_slips s on s.id = l.slip_id
          where s.run_id = p_run_id and l.line_type = 'loan'
          group by l.source_id) l
   where d.id = l.source_id;

  -- Arrears are paid once.
  update public.salary_increments si
     set arrears_slip_id = l.slip_id
    from (select l.source_id, l.slip_id
          from public.payroll_slip_lines l join public.payroll_slips s on s.id = l.slip_id
          where s.run_id = p_run_id and l.line_type = 'arrear') l
   where si.id = l.source_id;

  update public.payroll_adjustments a
     set status = 'applied', applied_run_id = p_run_id
    from public.payroll_slip_lines l join public.payroll_slips s on s.id = l.slip_id
   where s.run_id = p_run_id and l.line_type = 'adjustment' and l.source_id = a.id;

  -- One payment batch per method; slips without an account go to "unassigned".
  insert into public.payment_batches (org_id, run_id, method, row_count, total)
  select v_run.org_id, p_run_id, coalesce(payment_method, 'unassigned'), count(*), sum(net)
  from public.payroll_slips where run_id = p_run_id and net > 0
  group by coalesce(payment_method, 'unassigned');

  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run_id;
end;
$$;

-- Reopening reverses every posting of the approval. Needs a reason; audited.
create or replace function public.reopen_payroll_run(p_run_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  perform private.require_permission('payroll.reopen');
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'A reason (at least 5 characters) is required to reopen a run' using errcode = '23502';
  end if;
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status <> 'approved' then
    raise exception 'Only an approved, unpaid run can be reopened (status: %)', v_run.status using errcode = '22023';
  end if;

  update public.employee_deductions d
     set remaining = d.remaining + l.amount, status = 'active'
    from (select l.source_id, sum(l.amount) as amount
          from public.payroll_slip_lines l join public.payroll_slips s on s.id = l.slip_id
          where s.run_id = p_run_id and l.line_type = 'loan'
          group by l.source_id) l
   where d.id = l.source_id;
  update public.salary_increments set arrears_slip_id = null
   where arrears_slip_id in (select id from public.payroll_slips where run_id = p_run_id);
  update public.payroll_adjustments set status = 'approved', applied_run_id = null where applied_run_id = p_run_id;
  delete from public.payment_batches where run_id = p_run_id;

  update public.payroll_runs
     set status = 'calculated', reviewed_by = null, reviewed_at = null, approved_by = null, approved_at = null,
         reopen_count = reopen_count + 1
   where id = p_run_id;
  perform private.write_audit(v_run.org_id, 'payroll.reopened', 'payroll_runs', p_run_id,
    jsonb_build_object('status', 'approved'), jsonb_build_object('status', 'calculated', 'reason', btrim(p_reason)));
end;
$$;

-- Cancels a run that is not approved yet (its slips are removed).
create or replace function public.cancel_payroll_run(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  perform private.require_permission('payroll.prepare');
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status not in ('draft', 'calculated', 'reviewed') then
    raise exception 'An approved run cannot be cancelled; reopen it first' using errcode = '22023';
  end if;
  delete from public.payroll_slips where run_id = p_run_id;
  update public.payroll_runs set status = 'cancelled' where id = p_run_id;
  perform private.refresh_run_totals(p_run_id);
end;
$$;

-- Marks one payment batch as paid; when every batch is paid the run is paid.
create or replace function public.mark_payment_batch_paid(p_batch_id uuid, p_reference text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.payment_batches;
  v_run   public.payroll_runs;
begin
  perform private.require_permission('payroll.approve');
  select * into v_batch from public.payment_batches where id = p_batch_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Payment batch not found' using errcode = 'P0002';
  end if;
  v_run := private.load_run_for_update(v_batch.run_id);
  if v_run.status <> 'approved' then
    raise exception 'Payments can be marked only on an approved run' using errcode = '22023';
  end if;
  if v_batch.status = 'paid' then
    raise exception 'This batch is already paid' using errcode = '22023';
  end if;

  update public.payment_batches
     set status = 'paid', paid_at = now(), reference = coalesce(nullif(left(btrim(p_reference), 120), ''), reference)
   where id = p_batch_id;

  perform private.begin_payroll_posting();
  update public.payroll_slips set payment_status = 'paid'
   where run_id = v_batch.run_id and coalesce(payment_method, 'unassigned') = v_batch.method and net > 0;
  perform private.end_payroll_posting();

  if not exists (select 1 from public.payment_batches where run_id = v_batch.run_id and status <> 'paid') then
    update public.payroll_runs set status = 'paid', paid_at = now() where id = v_batch.run_id;
  end if;
end;
$$;

-- Locks a paid run. A whole-organization run also locks the month in Part 2
-- (attendance, leave, overtime become read-only).
create or replace function public.lock_payroll_run(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run       public.payroll_runs;
  v_month_end date;
begin
  perform private.require_permission('payroll.lock');
  v_run := private.load_run_for_update(p_run_id);
  if v_run.status <> 'paid' then
    raise exception 'Only a paid run can be locked (status: %)', v_run.status using errcode = '22023';
  end if;
  v_month_end := private.month_end(v_run.period_month);

  if v_run.scope = 'all' and not exists (
       select 1 from public.period_locks
       where org_id = v_run.org_id and status = 'locked'
         and period_start <= v_run.period_month and period_end >= v_month_end) then
    insert into public.period_locks (org_id, period_start, period_end, note)
    values (v_run.org_id, v_run.period_month, v_month_end, 'Payroll locked');
    update public.attendance_records set locked = true
     where org_id = v_run.org_id and work_date between v_run.period_month and v_month_end;
    update public.overtime_records set locked = true
     where org_id = v_run.org_id and work_date between v_run.period_month and v_month_end;
  end if;

  update public.payroll_runs set status = 'locked', locked_by = auth.uid(), locked_at = now() where id = p_run_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. Adjustments (maker-checker)
-- -----------------------------------------------------------------------------
create or replace function public.create_payroll_adjustment(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee      public.employees;
  v_month         date := private.month_start((private.jtext(p, 'apply_month'))::date);
  v_adjustment_id uuid;
begin
  perform private.require_permission('payroll.prepare');
  v_employee := private.assert_org_employee(private.jtext(p, 'employee_id')::uuid);
  perform private.assert_not_self_money(v_employee.id);
  if v_month is null then
    raise exception 'Choose the month the adjustment applies to' using errcode = '22023';
  end if;
  if coalesce(private.jtext(p, 'type'), '') not in ('arrear', 'correction', 'manual') then
    raise exception 'Choose arrear, correction or manual' using errcode = '22023';
  end if;
  if coalesce(private.jtext(p, 'direction'), '') not in ('earning', 'deduction') then
    raise exception 'Choose whether it adds to pay or deducts from it' using errcode = '22023';
  end if;
  if coalesce((p ->> 'amount')::numeric, 0) <= 0 or (p ->> 'amount')::numeric > 99999999 then
    raise exception 'The amount must be more than zero' using errcode = '22023';
  end if;
  if char_length(coalesce(private.jtext(p, 'reason'), '')) < 3 then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  if exists (select 1 from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id
             where s.employee_id = v_employee.id and s.period_month = v_month
               and r.status in ('approved', 'paid', 'locked')) then
    raise exception 'That month is already approved for this employee; apply the adjustment to an open month'
      using errcode = '22023';
  end if;

  insert into public.payroll_adjustments (org_id, employee_id, apply_month, type, direction, amount, reason)
  values (v_employee.org_id, v_employee.id, v_month, private.jtext(p, 'type'), private.jtext(p, 'direction'),
          round((p ->> 'amount')::numeric, 2), private.jtext(p, 'reason'))
  returning id into v_adjustment_id;
  return v_adjustment_id;
end;
$$;

create or replace function public.decide_payroll_adjustment(p_adjustment_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_adjustment public.payroll_adjustments;
begin
  perform private.require_permission('payroll.approve');
  select * into v_adjustment from public.payroll_adjustments
  where id = p_adjustment_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Adjustment not found' using errcode = 'P0002';
  end if;
  if v_adjustment.status <> 'pending' then
    raise exception 'This adjustment was already decided' using errcode = '22023';
  end if;
  if v_adjustment.created_by = auth.uid() then
    raise exception 'You created this adjustment, so someone else must approve it' using errcode = '42501';
  end if;
  if v_adjustment.employee_id = private.current_employee_id() then
    raise exception 'You cannot decide an adjustment to your own pay' using errcode = '42501';
  end if;
  update public.payroll_adjustments
     set status = case when p_approve then 'approved' else 'rejected' end, approved_by = auth.uid(), decided_at = now()
   where id = p_adjustment_id;
end;
$$;

create or replace function public.cancel_payroll_adjustment(p_adjustment_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('payroll.prepare');
  update public.payroll_adjustments set status = 'cancelled'
   where id = p_adjustment_id and org_id = private.current_org_id() and status in ('pending', 'approved');
  if not found then
    raise exception 'Only a pending or approved (not applied) adjustment can be cancelled' using errcode = '22023';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. Read RPCs
-- -----------------------------------------------------------------------------
create or replace function private.require_payroll_staff()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_payroll_staff() then
    raise exception 'You do not have permission for this action (payroll)' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.list_payroll_runs()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_payroll_staff();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'period_month', r.period_month, 'scope', r.scope, 'scope_id', r.scope_id,
      'scope_name', coalesce(b.name, d.name), 'status', r.status, 'employee_count', r.employee_count,
      'total_gross', r.total_gross, 'total_deductions', r.total_deductions, 'total_net', r.total_net,
      'warning_count', r.warning_count, 'blocker_count', r.blocker_count, 'calculated_at', r.calculated_at,
      'approved_at', r.approved_at, 'created_at', r.created_at)
      order by r.period_month desc, r.created_at desc)
    from public.payroll_runs r
    left join public.branches b on b.id = r.scope_id and r.scope = 'branch'
    left join public.departments d on d.id = r.scope_id and r.scope = 'department'
    where r.org_id = private.current_org_id()), '[]'::jsonb);
end;
$$;

create or replace function public.get_payroll_run(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_run public.payroll_runs;
begin
  perform private.require_payroll_staff();
  select * into v_run from public.payroll_runs where id = p_run_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Payroll run not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'run', to_jsonb(v_run) - 'inputs_fingerprint' || jsonb_build_object(
      'is_stale', v_run.status in ('calculated', 'reviewed')
                  and v_run.inputs_fingerprint is distinct from
                      private.payroll_inputs_fingerprint(v_run.org_id, v_run.period_month),
      'prepared_by_name', (select full_name from public.user_profiles where id = v_run.prepared_by),
      'reviewed_by_name', (select full_name from public.user_profiles where id = v_run.reviewed_by),
      'approved_by_name', (select full_name from public.user_profiles where id = v_run.approved_by),
      'is_preparer', v_run.prepared_by = auth.uid()),
    'slips', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'employee_id', s.employee_id, 'full_name', e.full_name, 'card_id', e.card_id,
        'department_name', dep.name, 'grade_code', g.code, 'monthly_gross', s.monthly_gross,
        'payable_days', s.payable_days, 'absent_days', s.absent_days, 'overtime_minutes', s.overtime_minutes,
        'gross_earnings', s.gross_earnings, 'total_deductions', s.total_deductions, 'net', s.net,
        'carry_forward_out', s.carry_forward_out, 'payment_method', s.payment_method,
        'payment_status', s.payment_status, 'warnings', s.warnings, 'has_blocker', s.has_blocker)
        order by e.full_name)
      from public.payroll_slips s
      join public.employees e on e.id = s.employee_id
      left join public.departments dep on dep.id = e.department_id
      left join public.designations ds on ds.id = e.designation_id
      left join public.grades g on g.id = ds.grade_id
      where s.run_id = p_run_id), '[]'::jsonb),
    'batches', coalesce((
      select jsonb_agg(jsonb_build_object('id', pb.id, 'method', pb.method, 'row_count', pb.row_count,
                                          'total', pb.total, 'status', pb.status, 'exported_at', pb.exported_at,
                                          'paid_at', pb.paid_at, 'reference', pb.reference) order by pb.method)
      from public.payment_batches pb where pb.run_id = p_run_id), '[]'::jsonb));
end;
$$;

-- A payslip: payroll staff see any slip; an employee sees their own once the
-- run is released (approved, or paid if the organization chose so).
create or replace function public.get_payslip(p_slip_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_slip    public.payroll_slips;
  v_run     public.payroll_runs;
  v_release text;
begin
  select * into v_slip from public.payroll_slips where id = p_slip_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Payslip not found' using errcode = 'P0002';
  end if;
  select * into v_run from public.payroll_runs where id = v_slip.run_id;
  select payslip_release into v_release from public.payroll_settings where org_id = v_slip.org_id;

  if not private.is_payroll_staff() then
    if v_slip.employee_id is distinct from private.current_employee_id()
       or not private.has_permission('payroll.view_own')
       or v_run.status not in ('approved', 'paid', 'locked')
       or (v_release = 'paid' and v_run.status = 'approved') then
      raise exception 'Payslip not found' using errcode = 'P0002';
    end if;
  end if;

  return jsonb_build_object(
    'slip', to_jsonb(v_slip),
    'run', jsonb_build_object('id', v_run.id, 'status', v_run.status, 'period_month', v_run.period_month,
                              'approved_at', v_run.approved_at),
    'employee', (select jsonb_build_object('full_name', e.full_name, 'card_id', e.card_id, 'join_date', e.join_date,
                                           'department_name', d.name, 'designation_name', ds.name, 'grade_code', g.code,
                                           'branch_name', b.name)
                 from public.employees e
                 left join public.departments d on d.id = e.department_id
                 left join public.designations ds on ds.id = e.designation_id
                 left join public.grades g on g.id = ds.grade_id
                 left join public.branches b on b.id = e.branch_id
                 where e.id = v_slip.employee_id),
    'organization', (select jsonb_build_object('name', o.name, 'org_code', o.org_code)
                     from public.organizations o where o.id = v_slip.org_id),
    'payment', (select jsonb_build_object('method', pa.method, 'bank_name', pa.bank_name, 'wallet_provider', pa.wallet_provider,
                                          'masked_number', private.mask_number(pa.number_last4))
                from public.employee_payment_accounts pa where pa.id = v_slip.payment_account_id),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object('direction', l.direction, 'line_type', l.line_type, 'code', l.code,
                                          'label', l.label, 'base', l.base, 'rate', l.rate, 'quantity', l.quantity,
                                          'amount', l.amount) order by l.sort_order, l.code)
      from public.payroll_slip_lines l where l.slip_id = p_slip_id), '[]'::jsonb));
end;
$$;

create or replace function public.list_my_payslips()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_release text;
begin
  perform private.require_permission('payroll.view_own');
  select payslip_release into v_release from public.payroll_settings where org_id = private.current_org_id();
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'period_month', s.period_month, 'gross_earnings', s.gross_earnings,
                                        'total_deductions', s.total_deductions, 'net', s.net,
                                        'payment_status', s.payment_status, 'run_status', r.status)
                     order by s.period_month desc)
    from public.payroll_slips s
    join public.payroll_runs r on r.id = s.run_id
    where s.employee_id = private.current_employee_id()
      and s.org_id = private.current_org_id()
      and (r.status in ('paid', 'locked') or (r.status = 'approved' and v_release = 'approved'))), '[]'::jsonb);
end;
$$;

create or replace function public.list_payroll_adjustments(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_payroll_staff();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'employee_id', a.employee_id, 'full_name', e.full_name, 'card_id', e.card_id,
      'apply_month', a.apply_month, 'type', a.type, 'direction', a.direction, 'amount', a.amount, 'reason', a.reason,
      'status', a.status, 'created_by_name', cu.full_name, 'approved_by_name', au.full_name,
      'is_creator', a.created_by = auth.uid(), 'created_at', a.created_at)
      order by a.created_at desc)
    from public.payroll_adjustments a
    join public.employees e on e.id = a.employee_id
    left join public.user_profiles cu on cu.id = a.created_by
    left join public.user_profiles au on au.id = a.approved_by
    where a.org_id = private.current_org_id() and (p_status is null or a.status = p_status)), '[]'::jsonb);
end;
$$;

-- Payment sheet of one batch with full account numbers. Needs payment.export;
-- every download is audited (without the numbers).
create or replace function public.get_payment_sheet(p_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.payment_batches;
  v_rows  jsonb;
begin
  perform private.require_permission('payment.export');
  select * into v_batch from public.payment_batches where id = p_batch_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Payment batch not found' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'card_id', e.card_id, 'full_name', e.full_name, 'account_name', pa.account_name,
           'bank_name', pa.bank_name, 'branch_name', pa.branch_name, 'routing_number', pa.routing_number,
           'account_number', private.decrypt_secret(pa.account_number_enc),
           'wallet_provider', pa.wallet_provider, 'wallet_number', private.decrypt_secret(pa.wallet_number_enc),
           'amount', s.net) order by e.full_name), '[]'::jsonb)
    into v_rows
  from public.payroll_slips s
  join public.employees e on e.id = s.employee_id
  left join public.employee_payment_accounts pa on pa.id = s.payment_account_id
  where s.run_id = v_batch.run_id and s.net > 0 and coalesce(s.payment_method, 'unassigned') = v_batch.method;

  update public.payment_batches
     set status = case when status = 'generated' then 'exported' else status end,
         exported_at = now(), exported_by = auth.uid()
   where id = p_batch_id;
  perform private.write_audit(v_batch.org_id, 'payment_sheet.exported', 'payment_batches', v_batch.id, null,
    jsonb_build_object('run_id', v_batch.run_id, 'method', v_batch.method, 'rows', v_batch.row_count,
                       'total', v_batch.total));
  return jsonb_build_object('method', v_batch.method, 'total', v_batch.total, 'row_count', v_batch.row_count, 'rows', v_rows);
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. Privileges
-- -----------------------------------------------------------------------------
alter table public.payroll_runs        enable row level security;
alter table public.payroll_slips       enable row level security;
alter table public.payroll_slip_lines  enable row level security;
alter table public.payroll_adjustments enable row level security;
alter table public.payment_batches     enable row level security;
revoke all on table public.payroll_runs, public.payroll_slips, public.payroll_slip_lines,
                    public.payroll_adjustments, public.payment_batches from anon, authenticated;

revoke all on function
  public.create_payroll_run(date, text, uuid, text), public.calculate_payroll_run(uuid),
  public.review_payroll_run(uuid), public.approve_payroll_run(uuid), public.reopen_payroll_run(uuid, text),
  public.cancel_payroll_run(uuid), public.mark_payment_batch_paid(uuid, text), public.lock_payroll_run(uuid),
  public.create_payroll_adjustment(jsonb), public.decide_payroll_adjustment(uuid, boolean),
  public.cancel_payroll_adjustment(uuid), public.list_payroll_runs(), public.get_payroll_run(uuid),
  public.get_payslip(uuid), public.list_my_payslips(), public.list_payroll_adjustments(text),
  public.get_payment_sheet(uuid)
from public, anon;
grant execute on function
  public.create_payroll_run(date, text, uuid, text), public.calculate_payroll_run(uuid),
  public.review_payroll_run(uuid), public.approve_payroll_run(uuid), public.reopen_payroll_run(uuid, text),
  public.cancel_payroll_run(uuid), public.mark_payment_batch_paid(uuid, text), public.lock_payroll_run(uuid),
  public.create_payroll_adjustment(jsonb), public.decide_payroll_adjustment(uuid, boolean),
  public.cancel_payroll_adjustment(uuid), public.list_payroll_runs(), public.get_payroll_run(uuid),
  public.get_payslip(uuid), public.list_my_payslips(), public.list_payroll_adjustments(text),
  public.get_payment_sheet(uuid)
to authenticated;

revoke all on function
  private.seed_payroll_permissions(uuid), private.is_payroll_staff(), private.begin_payroll_posting(),
  private.end_payroll_posting(), private.payroll_inputs_fingerprint(uuid, date),
  private.increment_arrears_due(uuid, date), private.calculate_slip(uuid, uuid), private.run_employees(uuid),
  private.refresh_run_totals(uuid), private.load_run_for_update(uuid), private.assert_run_fresh(public.payroll_runs),
  private.require_payroll_staff()
from public, anon, authenticated;
