-- =============================================================================
-- Olympus HRIS — Part 2A: Time rules and configuration
-- Work settings (labour law regime, weekly off, 30-day month, late deduction
-- policy), shifts, rosters, holidays, leave types, overtime policy, period locks.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Permissions (Part 2)
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('attendance.view_own',   'attendance', 'See and punch own attendance',                     false),
  ('attendance.view_team',  'attendance', 'See the attendance of their reporting team',       false),
  ('attendance.view_all',   'attendance', 'See everyone''s attendance',                       false),
  ('attendance.adjust',     'attendance', 'Manual punches and attendance fixes',              false),
  ('attendance.qr_display', 'attendance', 'Show the rotating office QR code',                 false),
  ('attendance.settings',   'attendance', 'Work settings: law, weekly off, late policy',      false),
  ('attendance.lock_period','attendance', 'Lock and unlock payroll periods',                  true),
  ('shifts.manage',         'attendance', 'Create and edit shifts',                           false),
  ('roster.manage',         'attendance', 'Assign shifts to employees',                       false),
  ('holidays.manage',       'attendance', 'Manage holidays',                                  false),
  ('swaps.approve',         'attendance', 'Approve shift swaps',                              false),
  ('geofences.manage',      'attendance', 'Manage geofences',                                 false),
  ('leave.request',         'leave',      'Request leave for themselves',                     false),
  ('leave.approve',         'leave',      'Approve or reject leave',                          false),
  ('leave.manage_types',    'leave',      'Configure leave types and balances',               false),
  ('leave.view_all',        'leave',      'See everyone''s leave',                            false),
  ('overtime.view',         'overtime',   'See overtime records',                             false),
  ('overtime.approve',      'overtime',   'Approve or reject overtime',                       false),
  ('overtime.manage_policy','overtime',   'Configure the overtime policy',                    false)
on conflict (key) do nothing;

create or replace function private.seed_time_permissions(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, k
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array[
      'attendance.view_own', 'attendance.view_team', 'attendance.view_all', 'attendance.adjust',
      'attendance.qr_display', 'attendance.settings', 'shifts.manage', 'roster.manage', 'holidays.manage',
      'swaps.approve', 'geofences.manage', 'leave.request', 'leave.approve', 'leave.manage_types',
      'leave.view_all', 'overtime.view', 'overtime.approve', 'overtime.manage_policy']
    when 'manager' then array[
      'attendance.view_own', 'attendance.view_team', 'swaps.approve', 'leave.request', 'leave.approve',
      'overtime.view', 'overtime.approve']
    when 'employee' then array['attendance.view_own', 'leave.request']
    else array[]::text[]
  end) as k
  where r.org_id = p_org_id
  on conflict do nothing;
end;
$$;

-- -----------------------------------------------------------------------------
-- Team scope: everyone below the caller on the current reporting chain.
-- -----------------------------------------------------------------------------
create or replace function private.team_employee_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive team(id, depth) as (
    select rl.employee_id, 1
    from public.reporting_lines rl
    where rl.manager_employee_id = private.current_employee_id() and rl.end_date is null
    union
    select rl.employee_id, t.depth + 1
    from team t
    join public.reporting_lines rl on rl.manager_employee_id = t.id and rl.end_date is null
    where t.depth < 20
  )
  select distinct id from team
$$;

-- May the caller see this employee's time data (attendance, leave, overtime)?
-- Own record, the whole org with view_all, or their team with view_team.
create or replace function private.can_see_time(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.employees e where e.id = p_employee_id and e.org_id = private.current_org_id())
     and (
       p_employee_id = private.current_employee_id()
       or private.has_permission('attendance.view_all')
       or private.has_permission('leave.view_all')
       or (private.has_permission('attendance.view_team') and p_employee_id in (select private.team_employee_ids()))
     )
$$;

-- -----------------------------------------------------------------------------
-- Work settings (one row per organization)
-- -----------------------------------------------------------------------------
create table public.org_work_settings (
  org_id                 uuid primary key references public.organizations (id),
  -- Bangladesh: an EPZ enterprise follows the EPZ Labour Act 2019; everyone else the Labour Act 2006.
  labor_regime           text not null default 'bd_labour_act'
                         check (labor_regime in ('bd_labour_act', 'bd_epz_labour_act')),
  weekly_off_days        smallint[] not null default '{5}',   -- 0 = Sunday ... 6 = Saturday; 5 = Friday
  default_shift_id       uuid,
  month_days             smallint not null default 30 check (month_days = 30),  -- salary month is always 30 days
  -- Late deduction policy (amounts are applied to salary in Part 3).
  late_deduction_mode    text not null default 'days_per_lates'
                         check (late_deduction_mode in ('none', 'days_per_lates', 'amount_per_late')),
  lates_per_deduction    smallint not null default 3 check (lates_per_deduction between 1 and 31),
  late_deduction_days    numeric(4, 2) not null default 1 check (late_deduction_days between 0 and 5),
  late_amount_per_late   numeric(10, 2) not null default 0 check (late_amount_per_late >= 0),
  qr_rotation_seconds    smallint not null default 60 check (qr_rotation_seconds between 15 and 600),
  require_location       boolean not null default false,       -- web punches must send a location
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  created_by             uuid references public.user_profiles (id),
  updated_by             uuid references public.user_profiles (id),
  constraint org_work_settings_weekly_off_valid check (weekly_off_days <@ array[0, 1, 2, 3, 4, 5, 6]::smallint[])
);

-- -----------------------------------------------------------------------------
-- Shifts
-- -----------------------------------------------------------------------------
create table public.shifts (
  id                         uuid primary key default gen_random_uuid(),
  org_id                     uuid not null default private.current_org_id() references public.organizations (id),
  name                       text not null check (char_length(btrim(name)) between 2 and 80),
  code                       text not null check (code ~ '^[A-Za-z0-9-]{1,12}$'),
  start_time                 time not null,
  end_time                   time not null,
  crosses_midnight           boolean generated always as (end_time <= start_time) stored,
  break_minutes              smallint not null default 60 check (break_minutes between 0 and 240),
  checkin_earliest_minutes   smallint not null default 120 check (checkin_earliest_minutes between 0 and 480),
  late_grace_minutes         smallint not null default 10 check (late_grace_minutes between 0 and 240),
  checkin_latest_minutes     smallint not null default 240 check (checkin_latest_minutes between 0 and 720), -- after start: absent cut-off
  checkout_latest_minutes    smallint not null default 360 check (checkout_latest_minutes between 0 and 720), -- after end
  early_out_grace_minutes    smallint not null default 10 check (early_out_grace_minutes between 0 and 240),
  auto_checkout              boolean not null default false,
  half_day_threshold_minutes smallint not null default 240 check (half_day_threshold_minutes between 0 and 720),
  status                     text not null default 'active' check (status in ('active', 'inactive')),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  created_by                 uuid references public.user_profiles (id),
  updated_by                 uuid references public.user_profiles (id),
  constraint shifts_org_id_id_uq unique (org_id, id),
  constraint shifts_start_ne_end check (start_time <> end_time)
);
create unique index shifts_org_code_uq on public.shifts (org_id, upper(code));

alter table public.org_work_settings
  add constraint org_work_settings_default_shift_fk foreign key (org_id, default_shift_id) references public.shifts (org_id, id);

-- Rosters: one active shift per employee per date. Override rows (from an
-- approved swap or a one-off change) win over normal rows on their dates.
create table public.shift_rosters (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null default private.current_org_id() references public.organizations (id),
  employee_id uuid not null,
  shift_id    uuid not null,
  date_from   date not null,
  date_to     date not null,
  is_override boolean not null default false,
  note        text,
  status      text not null default 'active' check (status in ('active', 'inactive')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint shift_rosters_dates check (date_to >= date_from and date_to - date_from <= 366),
  constraint shift_rosters_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint shift_rosters_shift_fk foreign key (org_id, shift_id) references public.shifts (org_id, id)
);
create index shift_rosters_employee_idx on public.shift_rosters (employee_id, date_from, date_to) where status = 'active';

create or replace function private.shift_rosters_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'active' then
    if not exists (select 1 from public.shifts where id = new.shift_id and status = 'active')
       and (tg_op = 'INSERT' or new.shift_id <> old.shift_id or old.status <> 'active') then
      raise exception 'The shift is inactive' using errcode = '23514';
    end if;
    if exists (
      select 1 from public.shift_rosters r
      where r.employee_id = new.employee_id and r.status = 'active' and r.id <> new.id
        and r.is_override = new.is_override
        and daterange(r.date_from, r.date_to, '[]') && daterange(new.date_from, new.date_to, '[]')) then
      raise exception 'This employee already has a shift on some of these dates (overlap)' using errcode = '23P01';
    end if;
  end if;
  return new;
end;
$$;
create trigger shift_rosters_guard before insert or update on public.shift_rosters
  for each row execute function private.shift_rosters_guard();

-- -----------------------------------------------------------------------------
-- Holidays
-- -----------------------------------------------------------------------------
create table public.holidays (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null default private.current_org_id() references public.organizations (id),
  name       text not null check (char_length(btrim(name)) between 2 and 120),
  date       date not null,
  type       text not null default 'public' check (type in ('public', 'company', 'optional')),
  branch_ids uuid[] not null default '{}',     -- empty = every branch
  status     text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id)
);
create unique index holidays_org_date_name_uq on public.holidays (org_id, date, lower(name));
create index holidays_org_date_idx on public.holidays (org_id, date) where status = 'active';

-- -----------------------------------------------------------------------------
-- Leave types
-- -----------------------------------------------------------------------------
create table public.leave_types (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null default private.current_org_id() references public.organizations (id),
  name                 text not null check (char_length(btrim(name)) between 2 and 80),
  code                 text not null check (code ~ '^[A-Z0-9]{1,8}$'),
  days_per_year        numeric(5, 1) check (days_per_year is null or days_per_year between 0 and 366),  -- null = unlimited
  paid                 boolean not null default true,
  carry_forward        boolean not null default false,
  carry_forward_cap    numeric(5, 1) check (carry_forward_cap is null or carry_forward_cap >= 0),
  accrual              text not null default 'yearly' check (accrual in ('yearly', 'monthly')),
  allows_half_day      boolean not null default true,
  document_required    boolean not null default false,
  counts_off_days      boolean not null default false,   -- count weekly offs / holidays inside the range
  status               text not null default 'active' check (status in ('active', 'inactive')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint leave_types_org_id_id_uq unique (org_id, id),
  constraint leave_types_org_code_uq unique (org_id, code)
);

-- -----------------------------------------------------------------------------
-- Overtime policy (one row per organization). Applies to every grade,
-- management and owners included.
-- -----------------------------------------------------------------------------
create table public.overtime_policy (
  org_id                uuid primary key references public.organizations (id),
  weekday_multiplier    numeric(4, 2) not null default 2.0 check (weekday_multiplier between 1 and 5),
  weekend_multiplier    numeric(4, 2) not null default 2.0 check (weekend_multiplier between 1 and 5),
  holiday_multiplier    numeric(4, 2) not null default 2.0 check (holiday_multiplier between 1 and 5),
  minimum_minutes       smallint not null default 30 check (minimum_minutes between 0 and 240),
  rounding_minutes      smallint not null default 15 check (rounding_minutes between 1 and 60),
  daily_cap_minutes     smallint not null default 120 check (daily_cap_minutes between 0 and 720),
  monthly_cap_minutes   integer check (monthly_cap_minutes is null or monthly_cap_minutes between 0 and 20000),
  auto_capture          boolean not null default true,
  requires_approval     boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid references public.user_profiles (id),
  updated_by            uuid references public.user_profiles (id)
);

-- -----------------------------------------------------------------------------
-- Payroll period locks (Part 3 will call lock/unlock). Locked dates are read-only.
-- -----------------------------------------------------------------------------
create table public.period_locks (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null default private.current_org_id() references public.organizations (id),
  period_start date not null,
  period_end   date not null,
  note         text,
  status       text not null default 'locked' check (status in ('locked', 'unlocked')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint period_locks_dates check (period_end >= period_start)
);

create or replace function private.is_locked(p_org_id uuid, p_date date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.period_locks
                 where org_id = p_org_id and status = 'locked' and p_date between period_start and period_end)
$$;

create or replace function private.assert_not_locked(p_org_id uuid, p_from date, p_to date default null)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.period_locks
             where org_id = p_org_id and status = 'locked'
               and daterange(period_start, period_end, '[]') && daterange(p_from, coalesce(p_to, p_from), '[]')) then
    raise exception 'This period is locked for payroll and cannot be changed' using errcode = '42501';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Defaults for a new (or existing) organization. Statutory values are seeds
-- to be confirmed by HR against the chosen law.
-- -----------------------------------------------------------------------------
create or replace function private.seed_leave_types(p_org_id uuid, p_regime text, p_reset boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Both Bangladesh acts currently give the same base entitlements; the regime
  -- column lets them diverge without code changes.
  insert into public.leave_types as lt (org_id, name, code, days_per_year, paid, carry_forward, carry_forward_cap,
                                        accrual, allows_half_day, document_required, counts_off_days)
  values
    (p_org_id, 'Casual Leave',    'CL', 10,  true,  false, null, 'yearly',  true,  false, false),
    (p_org_id, 'Sick Leave',      'SL', 14,  true,  false, null, 'yearly',  true,  true,  false),
    (p_org_id, 'Earned Leave',    'EL', 18,  true,  true,  40,   'monthly', false, false, false),
    (p_org_id, 'Maternity Leave', 'ML', 112, true,  false, null, 'yearly',  false, true,  true),
    (p_org_id, 'Leave Without Pay','LWP', null, false, false, null, 'yearly', true, false, false)
  on conflict (org_id, code) do update
    set days_per_year = excluded.days_per_year, paid = excluded.paid, carry_forward = excluded.carry_forward,
        carry_forward_cap = excluded.carry_forward_cap, accrual = excluded.accrual,
        allows_half_day = excluded.allows_half_day, document_required = excluded.document_required,
        counts_off_days = excluded.counts_off_days
    where p_reset;
end;
$$;

create or replace function private.seed_time_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shift uuid;
  v_year  int := extract(year from now() at time zone 'Asia/Dhaka')::int;
  y       int;
begin
  perform private.seed_time_permissions(p_org_id);

  insert into public.shifts (org_id, name, code, start_time, end_time, break_minutes)
  values (p_org_id, 'General', 'GEN', '09:00', '18:00', 60)
  on conflict do nothing;
  select id into v_shift from public.shifts where org_id = p_org_id and upper(code) = 'GEN';

  insert into public.org_work_settings (org_id, default_shift_id)
  values (p_org_id, v_shift)
  on conflict (org_id) do nothing;

  insert into public.overtime_policy (org_id) values (p_org_id) on conflict (org_id) do nothing;

  perform private.seed_leave_types(p_org_id, 'bd_labour_act', false);

  -- Fixed-date Bangladesh public holidays. Eid, Puja and other moon/lunar dates
  -- are added by HR each year.
  for y in v_year .. v_year + 1 loop
    insert into public.holidays (org_id, name, date, type) values
      (p_org_id, 'Shaheed Day and International Mother Language Day', make_date(y, 2, 21), 'public'),
      (p_org_id, 'Independence Day',  make_date(y, 3, 26), 'public'),
      (p_org_id, 'Bengali New Year',  make_date(y, 4, 14), 'public'),
      (p_org_id, 'May Day',           make_date(y, 5, 1),  'public'),
      (p_org_id, 'Victory Day',       make_date(y, 12, 16), 'public'),
      (p_org_id, 'Christmas Day',     make_date(y, 12, 25), 'public')
    on conflict do nothing;
  end loop;
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
end;
$$;

-- -----------------------------------------------------------------------------
-- Settings RPC: switching the law re-applies its leave/overtime seeds.
-- -----------------------------------------------------------------------------
create or replace function public.apply_labor_regime_defaults(p_regime text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('attendance.settings');
  if p_regime not in ('bd_labour_act', 'bd_epz_labour_act') then
    raise exception 'Unknown labour law %', p_regime using errcode = '22023';
  end if;
  update public.org_work_settings set labor_regime = p_regime where org_id = v_org;
  perform private.seed_leave_types(v_org, p_regime, true);
  update public.overtime_policy
     set weekday_multiplier = 2.0, weekend_multiplier = 2.0, holiday_multiplier = 2.0, daily_cap_minutes = 120
   where org_id = v_org;
  perform private.write_audit(v_org, 'labor_regime.applied', 'org_work_settings', null, null,
                              jsonb_build_object('regime', p_regime));
end;
$$;

-- Admin-only payroll period lock.
create or replace function public.set_period_lock(p_start date, p_end date, p_locked boolean, p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_id  uuid;
begin
  perform private.require_permission('attendance.lock_period');
  if p_locked then
    insert into public.period_locks (org_id, period_start, period_end, note)
    values (v_org, p_start, p_end, nullif(btrim(p_note), '')) returning id into v_id;
    update public.attendance_records set locked = true
     where org_id = v_org and work_date between p_start and p_end;
    update public.overtime_records set locked = true
     where org_id = v_org and work_date between p_start and p_end;
  else
    update public.period_locks set status = 'unlocked'
     where org_id = v_org and status = 'locked' and period_start = p_start and period_end = p_end
    returning id into v_id;
    update public.attendance_records r set locked = private.is_locked(v_org, r.work_date)
     where r.org_id = v_org and r.work_date between p_start and p_end;
    update public.overtime_records r set locked = private.is_locked(v_org, r.work_date)
     where r.org_id = v_org and r.work_date between p_start and p_end;
  end if;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Standard triggers
-- -----------------------------------------------------------------------------
create trigger set_row_meta before insert or update on public.org_work_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.org_work_settings
  for each row execute function private.audit_row_change();
create trigger set_row_meta before insert or update on public.overtime_policy
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.overtime_policy
  for each row execute function private.audit_row_change();
select private.attach_standard_triggers('public.shifts');
select private.attach_standard_triggers('public.shift_rosters');
select private.attach_standard_triggers('public.holidays');
select private.attach_standard_triggers('public.leave_types');
select private.attach_standard_triggers('public.period_locks');

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
alter table public.org_work_settings enable row level security;
alter table public.shifts            enable row level security;
alter table public.shift_rosters     enable row level security;
alter table public.holidays          enable row level security;
alter table public.leave_types       enable row level security;
alter table public.overtime_policy   enable row level security;
alter table public.period_locks      enable row level security;

revoke all on table
  public.org_work_settings, public.shifts, public.shift_rosters, public.holidays,
  public.leave_types, public.overtime_policy, public.period_locks
from anon, authenticated;
grant select on table
  public.org_work_settings, public.shifts, public.shift_rosters, public.holidays,
  public.leave_types, public.overtime_policy, public.period_locks
to authenticated;

grant update (weekly_off_days, default_shift_id, late_deduction_mode, lates_per_deduction, late_deduction_days,
              late_amount_per_late, qr_rotation_seconds, require_location) on public.org_work_settings to authenticated;
grant insert (name, code, start_time, end_time, break_minutes, checkin_earliest_minutes, late_grace_minutes,
              checkin_latest_minutes, checkout_latest_minutes, early_out_grace_minutes, auto_checkout,
              half_day_threshold_minutes, status),
      update (name, start_time, end_time, break_minutes, checkin_earliest_minutes, late_grace_minutes,
              checkin_latest_minutes, checkout_latest_minutes, early_out_grace_minutes, auto_checkout,
              half_day_threshold_minutes, status) on public.shifts to authenticated;
grant insert (employee_id, shift_id, date_from, date_to, note, status),
      update (shift_id, date_from, date_to, note, status) on public.shift_rosters to authenticated;
grant insert (name, date, type, branch_ids, status), update (name, date, type, branch_ids, status) on public.holidays to authenticated;
grant insert (name, code, days_per_year, paid, carry_forward, carry_forward_cap, accrual, allows_half_day,
              document_required, counts_off_days, status),
      update (name, days_per_year, paid, carry_forward, carry_forward_cap, accrual, allows_half_day,
              document_required, counts_off_days, status) on public.leave_types to authenticated;
grant update (weekday_multiplier, weekend_multiplier, holiday_multiplier, minimum_minutes, rounding_minutes,
              daily_cap_minutes, monthly_cap_minutes, auto_capture, requires_approval) on public.overtime_policy to authenticated;

-- Configuration is readable by everyone in the organization.
create policy org_work_settings_select on public.org_work_settings for select to authenticated
  using (org_id = (select private.current_org_id()));
create policy org_work_settings_update on public.org_work_settings for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('attendance.settings')))
  with check (org_id = (select private.current_org_id()));

create policy overtime_policy_select on public.overtime_policy for select to authenticated
  using (org_id = (select private.current_org_id()));
create policy overtime_policy_update on public.overtime_policy for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('overtime.manage_policy')))
  with check (org_id = (select private.current_org_id()));

do $$
declare
  t record;
begin
  for t in select * from (values ('shifts', 'shifts.manage'), ('holidays', 'holidays.manage'),
                                 ('leave_types', 'leave.manage_types')) as x(tbl, perm) loop
    execute format($f$
      create policy %1$s_select on public.%1$s for select to authenticated
        using (org_id = (select private.current_org_id()));
      create policy %1$s_insert on public.%1$s for insert to authenticated
        with check (org_id = (select private.current_org_id()) and (select private.has_permission(%2$L)));
      create policy %1$s_update on public.%1$s for update to authenticated
        using (org_id = (select private.current_org_id()) and (select private.has_permission(%2$L)))
        with check (org_id = (select private.current_org_id()));
    $f$, t.tbl, t.perm);
  end loop;
end $$;

-- Rosters: visible within the caller's time scope; written with roster.manage.
create policy shift_rosters_select on public.shift_rosters for select to authenticated
  using (org_id = (select private.current_org_id()) and private.can_see_time(employee_id));
create policy shift_rosters_insert on public.shift_rosters for insert to authenticated
  with check (org_id = (select private.current_org_id()) and (select private.has_permission('roster.manage')) and not is_override);
create policy shift_rosters_update on public.shift_rosters for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('roster.manage')))
  with check (org_id = (select private.current_org_id()));

create policy period_locks_select on public.period_locks for select to authenticated
  using (org_id = (select private.current_org_id()));

revoke all on function public.apply_labor_regime_defaults(text), public.set_period_lock(date, date, boolean, text)
  from public, anon;
grant execute on function public.apply_labor_regime_defaults(text), public.set_period_lock(date, date, boolean, text)
  to authenticated;

revoke all on function
  private.seed_time_permissions(uuid), private.seed_leave_types(uuid, text, boolean),
  private.seed_time_defaults(uuid), private.seed_org_defaults(uuid),
  private.assert_not_locked(uuid, date, date)
from public, anon, authenticated;
grant execute on function private.team_employee_ids(), private.can_see_time(uuid), private.is_locked(uuid, date)
  to authenticated;

-- Existing organizations get the Part 2 defaults now.
select private.seed_time_defaults(id) from public.organizations;
