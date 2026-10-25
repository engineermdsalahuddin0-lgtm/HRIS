-- =============================================================================
-- Onboarding process R1: workforce planning (workload, headcount, vacancies).
-- Module handbook: src/onboarding-process/architecture.md (sections 5-8).
--
-- Every month the system compares each department's workload (demand hours)
-- with its capacity and with its sanctioned headcount:
--   capacity per person = monthly hours x availability (company setting)
--   demand hours by method: worked + approved OT hours | pieces x SMV / 60 |
--     count x standard minutes / 60 | (org employees / ratio) x capacity
--   index = demand / (active x capacity); required = demand / capacity;
--   gap = required - active; vacancy = sanctioned - active
-- Suggestions: backfill = min(vacancy, ceil(gap)); new positions when the
-- index stays >= overload for N months or reaches critical once; seats over
-- the department budget are drafted as "budget blocked".
-- Vacancies are drafted automatically (snapshot of the current or previous
-- month, or a person in a sanctioned position leaving) and need two people:
-- HR reviews, someone else approves. Approving a new position raises the
-- sanctioned headcount. Salary-derived figures are shown only to roles with
-- compensation.view.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.performance_cycles') is null then
    raise exception 'Apply 20261020000200_pms_manual_scoring.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('workforce.view',   'workforce', 'See workload, headcount and vacancy figures',                    false),
  ('workforce.manage', 'workforce', 'Set workload methods, enter output data and build snapshots',     false),
  ('headcount.manage', 'workforce', 'Set sanctioned headcount, department budgets and thresholds',     false),
  ('vacancy.request',  'workforce', 'Draft a vacancy (managers: own department only)',                 false),
  ('vacancy.review',   'workforce', 'Review drafted vacancies and send them for approval',             false),
  ('vacancy.approve',  'workforce', 'Approve, hold, reject or send back reviewed vacancies',           false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Reference library: formulas and their sources for the (?) tooltips
-- -----------------------------------------------------------------------------
alter table public.statutory_references drop constraint statutory_references_category_check;
alter table public.statutory_references add constraint statutory_references_category_check
  check (category in ('law', 'company_policy', 'company_setting', 'industry_practice'));
alter table public.statutory_references drop constraint statutory_references_area_check;
alter table public.statutory_references add constraint statutory_references_area_check
  check (area in ('tax', 'pf', 'gratuity', 'overtime', 'attendance', 'salary', 'performance', 'workforce'));

insert into public.statutory_references
  (key, category, area, title, title_bn, law_name, section, summary, summary_bn, source_url, verified_on, status, sort_order)
values
  ('workforce.capacity', 'company_setting', 'workforce', 'Capacity per person', 'জনপ্রতি সক্ষমতা', null, null,
   'Capacity = monthly working hours x availability. Monthly hours are set by the company (default 208 = 26 days x 8 hours) and must fit its shifts and the working-hours rules of its labour law. Availability = 1 - (absent + leave days, half days count 0.5) / scheduled workdays over the last 3 months, or a fixed percent.',
   'সক্ষমতা = মাসিক কর্মঘণ্টা x উপস্থিতির হার। মাসিক ঘণ্টা প্রতিষ্ঠান ঠিক করে (ডিফল্ট ২০৮ = ২৬ দিন x ৮ ঘণ্টা); শিফট ও শ্রম আইনের কর্মঘণ্টার নিয়মের সাথে মিলতে হবে।',
   null, null, 'needs_confirmation', 400),
  ('workforce.smv', 'industry_practice', 'workforce', 'Standard minute value (SMV)', 'স্ট্যান্ডার্ড মিনিট ভ্যালু (SMV)', null, null,
   'SMV is the time in minutes a trained operator needs to make one piece of a style, set by the company''s industrial engineering (work study) team. Demand hours = sum of pieces x SMV / 60.',
   'একজন দক্ষ অপারেটরের একটি পিস বানাতে যত মিনিট লাগে, প্রতিষ্ঠানের IE টিম তা ঠিক করে। চাহিদা ঘণ্টা = পিস x SMV / ৬০।',
   null, null, 'needs_confirmation', 410),
  ('workforce.standard_time', 'industry_practice', 'workforce', 'Standard time per task', 'কাজপ্রতি স্ট্যান্ডার্ড সময়', null, null,
   'For office work, each repeated task (voucher, call, ticket, goods line) gets a standard time in minutes from a time study or agreed by the department head. Demand hours = sum of count x standard minutes / 60; fixed work can be entered as hours (count = hours, 60 minutes).',
   'অফিসের প্রতিটি পুনরাবৃত্ত কাজের জন্য মিনিটে একটি স্ট্যান্ডার্ড সময় ধরা হয়। চাহিদা ঘণ্টা = সংখ্যা x মিনিট / ৬০।',
   null, null, 'needs_confirmation', 420),
  ('workforce.staffing_ratio', 'company_policy', 'workforce', 'Staffing ratio', 'স্টাফিং অনুপাত', null, null,
   'Support functions (HR, admin, security) are sized by the people they serve, e.g. one HR person per 100 employees. The ratio is the company''s own policy. Required people = org employees / ratio.',
   'সাপোর্ট বিভাগ যাদের সেবা দেয় তাদের সংখ্যা দিয়ে মাপা হয়, যেমন প্রতি ১০০ জনে ১ জন HR। অনুপাত প্রতিষ্ঠানের নীতি।',
   null, null, 'needs_confirmation', 430),
  ('workforce.index', 'company_setting', 'workforce', 'Workload index and bands', 'ওয়ার্কলোড ইনডেক্স ও সীমা', null, null,
   'Index = demand hours / (active people x capacity). Bands (company setting): at or above 1.25 critical, at or above 1.10 overload, above 1.00 watch, 0.85 to 1.00 balanced, below 0.85 underloaded. New positions are suggested when the index stays in overload for 2 months in a row or is critical once, so one busy month does not trigger hiring.',
   'ইনডেক্স = চাহিদা ঘণ্টা / (কর্মী x সক্ষমতা)। টানা ২ মাস ১.১০ বা এক মাসে ১.২৫ হলে নতুন পদের প্রস্তাব আসে।',
   null, null, 'needs_confirmation', 440),
  ('workforce.attrition', 'industry_practice', 'workforce', 'Attrition rate', 'কর্মী চলে যাওয়ার হার', null, null,
   'Attrition % = people who left in the period / average headcount in the period x 100. Here the period is the last 3 months and the average uses the three month-end headcounts.',
   'চলে যাওয়ার হার = সময়ের মধ্যে কতজন চলে গেছে / গড় কর্মী সংখ্যা x ১০০ (শেষ ৩ মাস)।',
   null, null, 'needs_confirmation', 450),
  ('workforce.vacancy_rate', 'industry_practice', 'workforce', 'Vacancy rate', 'শূন্যপদের হার', null, null,
   'Vacancy = sanctioned positions - active people (not below zero). Vacancy rate % = vacancy / sanctioned x 100.',
   'শূন্যপদ = অনুমোদিত পদ - বর্তমান কর্মী। হার = শূন্যপদ / অনুমোদিত পদ x ১০০।',
   null, null, 'needs_confirmation', 460),
  ('workforce.budget', 'company_policy', 'workforce', 'Department salary budget', 'বিভাগের বেতন বাজেট', null, null,
   'Remaining budget = monthly budget - gross pay of the people in the department. A seat costs the average gross in the department; seats that do not fit are drafted as budget blocked and can be approved only with an explicit over-budget reason.',
   'বাকি বাজেট = মাসিক বাজেট - বিভাগের বর্তমান মোট বেতন। বাজেটে না কুলালে পদটি "budget blocked" হিসেবে তৈরি হয়।',
   null, null, 'needs_confirmation', 470)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.workforce_settings (
  org_id                     uuid primary key references public.organizations (id),
  capacity_hours             numeric(6, 2) not null default 208 check (capacity_hours between 40 and 400),
  availability_source        text not null default 'attendance' check (availability_source in ('attendance', 'fixed')),
  fixed_availability_percent numeric(5, 2) not null default 100 check (fixed_availability_percent between 50 and 100),
  band_underload             numeric(4, 2) not null default 0.85,
  band_watch                 numeric(4, 2) not null default 1.00,
  band_overload              numeric(4, 2) not null default 1.10,
  band_critical              numeric(4, 2) not null default 1.25,
  sustain_months             smallint not null default 2 check (sustain_months between 1 and 6),
  attrition_flag_percent     numeric(5, 2) not null default 20 check (attrition_flag_percent between 1 and 100),
  confirmed_at               timestamptz,
  confirmed_by               uuid references public.user_profiles (id),
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  created_by                 uuid references public.user_profiles (id),
  updated_by                 uuid references public.user_profiles (id),
  constraint workforce_settings_bands check (band_underload > 0 and band_underload < band_watch
                                             and band_watch < band_overload and band_overload < band_critical)
);
select private.attach_standard_triggers('public.workforce_settings');

-- How one department's workload is measured, and its salary budget.
create table public.department_workforce (
  org_id         uuid not null,
  department_id  uuid primary key,
  method         text not null default 'hours' check (method in ('hours', 'output_smv', 'volume_std', 'ratio')),
  per_employees  integer check (per_employees between 5 and 10000),
  monthly_budget numeric(14, 2) check (monthly_budget >= 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint department_workforce_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint department_workforce_ratio check (method <> 'ratio' or per_employees is not null)
);
select private.attach_standard_triggers('public.department_workforce');

-- Sanctioned positions per designation (a designation belongs to one department).
create table public.headcount_plans (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  department_id  uuid not null,
  designation_id uuid not null unique,
  sanctioned     integer not null check (sanctioned between 0 and 10000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint headcount_plans_org_id_id_uq unique (org_id, id),
  constraint headcount_plans_designation_fk foreign key (org_id, department_id, designation_id)
    references public.designations (org_id, department_id, id)
);
select private.attach_standard_triggers('public.headcount_plans');

-- Output / volume figures for a month. Replaced as a set, so rows may be deleted.
create table public.workload_inputs (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  department_id uuid not null,
  period_month  date not null check (extract(day from period_month) = 1),
  metric_key    text not null check (char_length(btrim(metric_key)) between 1 and 40),
  label         text check (label is null or char_length(label) <= 80),
  quantity      numeric(14, 2) not null check (quantity >= 0),
  std_minutes   numeric(10, 3) not null check (std_minutes > 0),
  source        text not null default 'manual' check (source in ('manual', 'csv')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint workload_inputs_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint workload_inputs_metric_uq unique (department_id, period_month, metric_key)
);
create trigger set_row_meta before insert or update on public.workload_inputs
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.workload_inputs
  for each row execute function private.audit_row_change();

-- Derived monthly figures per department; rebuilt idempotently.
create table public.workload_snapshots (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  department_id    uuid not null,
  period_month     date not null check (extract(day from period_month) = 1),
  method           text not null,
  workload_index   numeric(6, 3),
  band             text not null,
  action           text not null,
  figures          jsonb not null,
  built_at         timestamptz not null default now(),
  built_by         uuid references public.user_profiles (id),
  constraint workload_snapshots_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint workload_snapshots_month_uq unique (department_id, period_month)
);

create table public.vacancies (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null,
  department_id          uuid not null,
  designation_id         uuid not null,
  office_id              uuid,
  seats                  smallint not null check (seats between 1 and 500),
  reason                 text not null check (reason in ('replacement', 'new_position')),
  origin                 text not null check (origin in ('separation', 'snapshot', 'manual')),
  separated_employee_id  uuid,
  snapshot_id            uuid references public.workload_snapshots (id),
  period_month           date,
  estimated_monthly_cost numeric(14, 2),
  budget_status          text not null default 'unknown' check (budget_status in ('ok', 'blocked', 'unknown')),
  recommendation         jsonb,
  note                   text check (note is null or char_length(note) <= 500),
  status                 text not null default 'draft'
                         check (status in ('draft', 'hr_reviewed', 'approved', 'on_hold', 'rejected', 'cancelled', 'filled')),
  hr_reviewed_by         uuid references public.user_profiles (id),
  hr_reviewed_at         timestamptz,
  decided_by             uuid references public.user_profiles (id),
  decided_at             timestamptz,
  decision_note          text check (decision_note is null or char_length(decision_note) <= 500),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  created_by             uuid references public.user_profiles (id),
  updated_by             uuid references public.user_profiles (id),
  constraint vacancies_org_id_id_uq unique (org_id, id),
  constraint vacancies_designation_fk foreign key (org_id, department_id, designation_id)
    references public.designations (org_id, department_id, id),
  constraint vacancies_office_fk foreign key (org_id, office_id) references public.offices (org_id, id),
  constraint vacancies_separated_fk foreign key (org_id, separated_employee_id) references public.employees (org_id, id)
);
create index vacancies_department_idx on public.vacancies (department_id, status);
select private.attach_standard_triggers('public.vacancies');

create table public.vacancy_events (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  vacancy_id    uuid not null,
  event         text not null,
  from_status   text,
  to_status     text,
  note          text,
  actor_user_id uuid references public.user_profiles (id) default auth.uid(),
  created_at    timestamptz not null default now(),
  constraint vacancy_events_vacancy_fk foreign key (org_id, vacancy_id) references public.vacancies (org_id, id)
);
create index vacancy_events_vacancy_idx on public.vacancy_events (vacancy_id, created_at);

create or replace function private.vacancy_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Vacancy history cannot be changed' using errcode = '42501';
end;
$$;
create trigger vacancy_events_append_only before update or delete on public.vacancy_events
  for each row execute function private.vacancy_events_append_only();

-- -----------------------------------------------------------------------------
-- Defaults
-- -----------------------------------------------------------------------------
create or replace function private.seed_workforce_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.workforce_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['workforce.view', 'workforce.manage', 'vacancy.request', 'vacancy.review']
    when 'manager'    then array['vacancy.request']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
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
  perform private.seed_statutory_defaults(p_org_id);
  perform private.seed_performance_defaults(p_org_id);
  perform private.seed_workforce_defaults(p_org_id);
end;
$$;

select private.seed_workforce_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- The calculation (pure: same inputs, same figures). Mirrored in
-- src/onboarding-process/core/workload.ts; both are tested with the 10 demo cases.
-- p: demand_hours, capacity_per_fte, active, sanctioned, separations,
--    avg_headcount, prior_overload_months, cost_per_seat, budget_remaining,
--    bands {underload, watch, overload, critical, sustain_months, attrition_flag_percent}
-- -----------------------------------------------------------------------------
create or replace function private.workload_figures(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_demand      numeric := round(coalesce((p ->> 'demand_hours')::numeric, 0), 2);
  v_capacity    numeric := (p ->> 'capacity_per_fte')::numeric;
  v_active      integer := coalesce((p ->> 'active')::integer, 0);
  v_sanctioned  integer := coalesce((p ->> 'sanctioned')::integer, 0);
  v_separations integer := coalesce((p ->> 'separations')::integer, 0);
  v_avg         numeric := (p ->> 'avg_headcount')::numeric;
  v_prior       integer := coalesce((p ->> 'prior_overload_months')::integer, 0);
  v_cost        numeric := (p ->> 'cost_per_seat')::numeric;
  v_budget_left numeric := (p ->> 'budget_remaining')::numeric;
  v_underload   numeric := coalesce((p -> 'bands' ->> 'underload')::numeric, 0.85);
  v_watch       numeric := coalesce((p -> 'bands' ->> 'watch')::numeric, 1.00);
  v_overload    numeric := coalesce((p -> 'bands' ->> 'overload')::numeric, 1.10);
  v_critical    numeric := coalesce((p -> 'bands' ->> 'critical')::numeric, 1.25);
  v_sustain     integer := coalesce((p -> 'bands' ->> 'sustain_months')::integer, 2);
  v_attr_limit  numeric := coalesce((p -> 'bands' ->> 'attrition_flag_percent')::numeric, 20);
  v_index       numeric;
  v_required    numeric;
  v_gap         numeric;
  v_vacancy     integer;
  v_band        text;
  v_months      integer;
  v_rule        boolean;
  v_backfill    integer;
  v_new         integer;
  v_hold        integer;
  v_total       integer;
  v_ok          integer;
  v_ok_backfill integer;
  v_budget      text;
  v_attrition   numeric;
  v_action      text;
begin
  if v_capacity is null or v_capacity <= 0 then
    raise exception 'Capacity per person must be above zero' using errcode = '22023';
  end if;
  v_required := round(v_demand / v_capacity, 2);
  v_gap := v_required - v_active;
  v_index := case when v_active > 0 then round(v_demand / (v_active * v_capacity), 3) end;
  v_vacancy := greatest(v_sanctioned - v_active, 0);
  v_band := case
    when v_index is null then case when v_demand > 0 then 'critical' else 'balanced' end
    when v_index >= v_critical then 'critical'
    when v_index >= v_overload then 'overload'
    when v_index > v_watch then 'watch'
    when v_index >= v_underload then 'balanced'
    else 'underloaded'
  end;
  -- Months in a row at overload or above, this month included.
  v_months := case when v_band in ('overload', 'critical') then v_prior + 1 else 0 end;
  v_rule := v_band = 'critical' or (v_band = 'overload' and v_months >= v_sustain);
  v_backfill := case when v_vacancy > 0 and v_gap > 0 then least(v_vacancy, ceil(v_gap)::integer) else 0 end;
  v_new := case when v_rule then greatest(ceil(v_required)::integer - v_sanctioned, 0) else 0 end;
  v_hold := v_vacancy - v_backfill;
  v_total := v_backfill + v_new;
  if v_cost is null or v_cost <= 0 or v_budget_left is null then
    v_budget := 'unknown';
    v_ok := v_total;
  else
    v_ok := least(v_total, greatest(floor(v_budget_left / v_cost), 0)::integer);
    v_budget := case when v_ok < v_total then 'blocked' else 'ok' end;
  end if;
  -- Replacements use the budget first.
  v_ok_backfill := least(v_backfill, v_ok);
  v_attrition := case when v_avg > 0 then round(v_separations / v_avg * 100, 1) end;
  v_action := case
    when v_total > 0 then 'hire'
    when v_band in ('watch', 'overload', 'critical') then 'watch'
    when v_hold > 0 then 'hold'
    when v_band = 'underloaded' then 'underloaded'
    else 'balanced'
  end;
  return jsonb_build_object(
    'demand_hours', v_demand, 'capacity_per_fte', v_capacity, 'capacity_hours', round(v_active * v_capacity, 2),
    'active', v_active, 'sanctioned', v_sanctioned, 'vacancy', v_vacancy,
    'vacancy_rate', case when v_sanctioned > 0 then round(v_vacancy::numeric / v_sanctioned * 100, 1) end,
    'required_fte', v_required, 'gap', v_gap, 'index', v_index, 'band', v_band,
    'overload_months', v_months, 'overload_rule', v_rule,
    'backfill_seats', v_backfill, 'new_positions', v_new, 'hold_seats', v_hold, 'seats_total', v_total,
    'budget_status', v_budget, 'budget_ok_seats', v_ok, 'budget_ok_backfill', v_ok_backfill,
    'budget_ok_new', v_ok - v_ok_backfill, 'budget_blocked_seats', v_total - v_ok,
    'cost_per_seat', v_cost, 'budget_remaining', v_budget_left,
    'separations', v_separations, 'avg_headcount', v_avg,
    'attrition_percent', v_attrition, 'attrition_flag', coalesce(v_attrition > v_attr_limit, false),
    'action', v_action,
    'bands', jsonb_build_object('underload', v_underload, 'watch', v_watch, 'overload', v_overload,
                                'critical', v_critical, 'sustain_months', v_sustain,
                                'attrition_flag_percent', v_attr_limit));
end;
$$;

-- -----------------------------------------------------------------------------
-- Facts from the organization's data
-- -----------------------------------------------------------------------------
-- People employed on a day (joined, not yet left), optionally per department / designation.
create or replace function private.headcount_on(p_org_id uuid, p_department_id uuid, p_designation_id uuid, p_day date)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.employees e
  where e.org_id = p_org_id
    and (p_department_id is null or e.department_id = p_department_id)
    and (p_designation_id is null or e.designation_id = p_designation_id)
    and e.join_date <= p_day
    and (e.exit_date is null or e.exit_date > p_day)
$$;

-- Seats that hold a sanctioned position: open replacements, and approved new positions
-- (their sanction was already raised).
create or replace function private.open_sanctioned_seats(p_department_id uuid, p_designation_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(v.seats), 0)::integer
  from public.vacancies v
  where v.department_id = p_department_id
    and (p_designation_id is null or v.designation_id = p_designation_id)
    and ((v.reason = 'replacement' and v.status in ('draft', 'hr_reviewed', 'approved', 'on_hold'))
         or (v.reason = 'new_position' and v.status = 'approved'))
$$;

-- Average current gross of the people in a department (or designation) on a day.
create or replace function private.average_gross(p_org_id uuid, p_department_id uuid, p_designation_id uuid, p_day date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select round(avg(c.gross), 2)
  from public.employees e
  join public.employee_compensation c
    on c.employee_id = e.id and c.effective_from <= p_day and (c.effective_to is null or c.effective_to >= p_day)
  where e.org_id = p_org_id and e.department_id = p_department_id
    and (p_designation_id is null or e.designation_id = p_designation_id)
    and e.join_date <= p_day and (e.exit_date is null or e.exit_date > p_day)
$$;

-- Collects one department's month and runs the calculation.
create or replace function private.department_workload(p_org_id uuid, p_department_id uuid, p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings     public.workforce_settings;
  v_config       public.department_workforce;
  v_method       text;
  v_month_end    date := (p_month + interval '1 month' - interval '1 day')::date;
  v_window_start date := (p_month - interval '2 months')::date;
  v_active       integer;
  v_org_people   integer;
  v_sanctioned   integer;
  v_separations  integer;
  v_avg          numeric;
  v_scheduled    numeric;
  v_lost         numeric;
  v_availability numeric;
  v_capacity     numeric;
  v_regular_min  numeric := 0;
  v_overtime_min numeric := 0;
  v_demand       numeric;
  v_prior        integer := 0;
  v_check        date := (p_month - interval '1 month')::date;
  v_band         text;
  v_payroll      numeric;
  v_budget_left  numeric;
begin
  select * into v_settings from public.workforce_settings where org_id = p_org_id;
  if not found then
    raise exception 'Workforce settings are missing' using errcode = 'P0002';
  end if;
  select * into v_config from public.department_workforce where department_id = p_department_id;
  v_method := coalesce(v_config.method, 'hours');

  v_active := private.headcount_on(p_org_id, p_department_id, null, v_month_end);
  v_org_people := private.headcount_on(p_org_id, null, null, v_month_end);
  select coalesce(sum(hp.sanctioned), 0) into v_sanctioned from public.headcount_plans hp where hp.department_id = p_department_id;
  select count(*) into v_separations from public.employees e
   where e.org_id = p_org_id and e.department_id = p_department_id and e.exit_date between v_window_start and v_month_end;
  v_avg := round((private.headcount_on(p_org_id, p_department_id, null, (v_window_start + interval '1 month' - interval '1 day')::date)
                  + private.headcount_on(p_org_id, p_department_id, null, (p_month - interval '1 day')::date)
                  + v_active)::numeric / 3, 2);

  if v_settings.availability_source = 'fixed' then
    v_availability := round(v_settings.fixed_availability_percent / 100, 4);
  else
    select count(*) filter (where r.day_type = 'workday'),
           coalesce(sum(case when r.day_type <> 'workday' then 0
                             when r.status in ('absent', 'on_leave') then 1
                             when r.status = 'half_day' then 0.5 else 0 end), 0)
      into v_scheduled, v_lost
    from public.attendance_records r
    join public.employees e on e.id = r.employee_id
    where r.org_id = p_org_id and e.department_id = p_department_id
      and r.work_date between v_window_start and v_month_end;
    v_availability := case when v_scheduled > 0 then greatest(round(1 - v_lost / v_scheduled, 4), 0.05) else 1 end;
  end if;
  v_capacity := round(v_settings.capacity_hours * v_availability, 2);

  if v_method in ('output_smv', 'volume_std') then
    select coalesce(sum(i.quantity * i.std_minutes), 0) / 60 into v_demand
    from public.workload_inputs i where i.department_id = p_department_id and i.period_month = p_month;
  elsif v_method = 'ratio' then
    v_demand := v_org_people::numeric / v_config.per_employees * v_capacity;
  else
    -- Regular worked time plus approved overtime (pending or rejected overtime is not counted).
    select coalesce(sum(greatest(r.worked_minutes - r.overtime_minutes, 0)), 0) into v_regular_min
    from public.attendance_records r join public.employees e on e.id = r.employee_id
    where r.org_id = p_org_id and e.department_id = p_department_id and r.work_date between p_month and v_month_end;
    select coalesce(sum(o.minutes), 0) into v_overtime_min
    from public.overtime_records o join public.employees e on e.id = o.employee_id
    where o.org_id = p_org_id and e.department_id = p_department_id and o.status = 'approved'
      and o.work_date between p_month and v_month_end;
    v_demand := (v_regular_min + v_overtime_min) / 60;
  end if;

  loop
    select s.band into v_band from public.workload_snapshots s
     where s.department_id = p_department_id and s.period_month = v_check;
    exit when not found or v_band not in ('overload', 'critical') or v_prior >= 12;
    v_prior := v_prior + 1;
    v_check := (v_check - interval '1 month')::date;
  end loop;

  select coalesce(sum(c.gross), 0) into v_payroll
  from public.employees e
  join public.employee_compensation c
    on c.employee_id = e.id and c.effective_from <= v_month_end and (c.effective_to is null or c.effective_to >= v_month_end)
  where e.org_id = p_org_id and e.department_id = p_department_id
    and e.join_date <= v_month_end and (e.exit_date is null or e.exit_date > v_month_end);
  v_budget_left := case when v_config.monthly_budget is not null then v_config.monthly_budget - v_payroll end;

  return private.workload_figures(jsonb_build_object(
           'demand_hours', v_demand, 'capacity_per_fte', v_capacity, 'active', v_active, 'sanctioned', v_sanctioned,
           'separations', v_separations, 'avg_headcount', v_avg, 'prior_overload_months', v_prior,
           'cost_per_seat', private.average_gross(p_org_id, p_department_id, null, v_month_end),
           'budget_remaining', v_budget_left,
           'bands', jsonb_build_object('underload', v_settings.band_underload, 'watch', v_settings.band_watch,
                                       'overload', v_settings.band_overload, 'critical', v_settings.band_critical,
                                       'sustain_months', v_settings.sustain_months,
                                       'attrition_flag_percent', v_settings.attrition_flag_percent)))
         || jsonb_build_object(
           'period_month', p_month, 'method', v_method, 'availability', v_availability,
           'capacity_hours_setting', v_settings.capacity_hours, 'availability_source', v_settings.availability_source,
           'scheduled_workdays', v_scheduled, 'lost_workdays', v_lost,
           'regular_hours', round(v_regular_min / 60, 2), 'overtime_hours', round(v_overtime_min / 60, 2),
           'org_headcount', v_org_people, 'per_employees', v_config.per_employees,
           'monthly_budget', v_config.monthly_budget, 'department_payroll', v_payroll);
end;
$$;

-- Salary-derived numbers are hidden from roles without compensation.view.
create or replace function private.mask_workforce_money(p jsonb, p_show boolean)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p is null or p_show then p
              else p - array['cost_per_seat', 'budget_remaining', 'monthly_budget', 'department_payroll'] end
$$;

-- -----------------------------------------------------------------------------
-- Vacancy drafting
-- -----------------------------------------------------------------------------
create or replace function private.vacancy_event(p_vacancy_id uuid, p_event text, p_from text, p_to text, p_note text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.vacancy_events (org_id, vacancy_id, event, from_status, to_status, note)
  select v.org_id, v.id, p_event, p_from, p_to, nullif(left(btrim(p_note), 500), '')
  from public.vacancies v where v.id = p_vacancy_id
$$;

create or replace function private.insert_vacancy(
  p_org_id uuid, p_department_id uuid, p_designation_id uuid, p_office_id uuid, p_seats integer,
  p_reason text, p_origin text, p_separated_employee_id uuid, p_snapshot_id uuid, p_month date,
  p_cost_per_seat numeric, p_budget_status text, p_recommendation jsonb, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.vacancies (org_id, department_id, designation_id, office_id, seats, reason, origin,
                                separated_employee_id, snapshot_id, period_month, estimated_monthly_cost,
                                budget_status, recommendation, note)
  values (p_org_id, p_department_id, p_designation_id, p_office_id, p_seats, p_reason, p_origin,
          p_separated_employee_id, p_snapshot_id, p_month, round(p_cost_per_seat * p_seats, 2),
          p_budget_status, p_recommendation, p_note)
  returning id into v_id;
  perform private.vacancy_event(v_id, 'drafted', null, 'draft', p_note);
  return v_id;
end;
$$;

-- Drafts p_seats for one designation, split into budget-ok and budget-blocked rows.
create or replace function private.draft_snapshot_seats(
  p_snapshot public.workload_snapshots, p_designation_id uuid, p_reason text, p_seats integer, p_ok_seats integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_budget text := p_snapshot.figures ->> 'budget_status';
  v_cost   numeric := (p_snapshot.figures ->> 'cost_per_seat')::numeric;
  v_ok     integer;
  v_note   text := case p_reason when 'replacement' then 'Drafted from the workload of '
                                  else 'New position suggested by the workload of ' end
                   || to_char(p_snapshot.period_month, 'Mon YYYY');
begin
  if p_seats <= 0 then
    return 0;
  end if;
  if v_budget = 'unknown' then
    perform private.insert_vacancy(p_snapshot.org_id, p_snapshot.department_id, p_designation_id, null, p_seats,
                                   p_reason, 'snapshot', null, p_snapshot.id, p_snapshot.period_month, v_cost,
                                   'unknown', p_snapshot.figures, v_note);
    return p_seats;
  end if;
  v_ok := least(p_seats, greatest(p_ok_seats, 0));
  if v_ok > 0 then
    perform private.insert_vacancy(p_snapshot.org_id, p_snapshot.department_id, p_designation_id, null, v_ok,
                                   p_reason, 'snapshot', null, p_snapshot.id, p_snapshot.period_month, v_cost,
                                   'ok', p_snapshot.figures, v_note);
  end if;
  if p_seats - v_ok > 0 then
    perform private.insert_vacancy(p_snapshot.org_id, p_snapshot.department_id, p_designation_id, null, p_seats - v_ok,
                                   p_reason, 'snapshot', null, p_snapshot.id, p_snapshot.period_month, v_cost,
                                   'blocked', p_snapshot.figures, v_note || ' (over the department budget)');
  end if;
  return p_seats;
end;
$$;

-- Drafts the seats a snapshot suggests that are not already covered by open vacancies.
-- Replacements go to the designations with the most open sanctioned positions;
-- new positions to the designation with the most people.
create or replace function private.draft_vacancies_from_snapshot(p_snapshot_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_snapshot    public.workload_snapshots;
  v_figures     jsonb;
  v_month_end   date;
  v_open        integer;
  v_pending_new integer;
  v_missing     integer;
  v_ok_left     integer;
  v_take        integer;
  v_drafted     integer := 0;
  v_row         record;
  v_designation uuid;
begin
  select * into v_snapshot from public.workload_snapshots where id = p_snapshot_id;
  v_figures := v_snapshot.figures;
  v_month_end := (v_snapshot.period_month + interval '1 month' - interval '1 day')::date;

  v_open := private.open_sanctioned_seats(v_snapshot.department_id, null);
  v_missing := (v_figures ->> 'backfill_seats')::integer - v_open;
  v_ok_left := (v_figures ->> 'budget_ok_backfill')::integer - v_open;
  if v_missing > 0 then
    for v_row in
      select hp.designation_id,
             hp.sanctioned - private.headcount_on(v_snapshot.org_id, v_snapshot.department_id, hp.designation_id, v_month_end)
               - private.open_sanctioned_seats(v_snapshot.department_id, hp.designation_id) as open_positions
      from public.headcount_plans hp
      where hp.department_id = v_snapshot.department_id
      order by 2 desc, hp.designation_id
    loop
      exit when v_missing <= 0;
      continue when v_row.open_positions <= 0;
      v_take := least(v_row.open_positions, v_missing);
      v_drafted := v_drafted + private.draft_snapshot_seats(v_snapshot, v_row.designation_id, 'replacement', v_take, v_ok_left);
      v_ok_left := v_ok_left - v_take;
      v_missing := v_missing - v_take;
    end loop;
  end if;

  select coalesce(sum(v.seats), 0) into v_pending_new from public.vacancies v
   where v.department_id = v_snapshot.department_id and v.reason = 'new_position'
     and v.status in ('draft', 'hr_reviewed', 'on_hold');
  v_missing := (v_figures ->> 'new_positions')::integer - v_pending_new;
  if v_missing > 0 then
    select ds.id into v_designation
    from public.designations ds
    left join public.headcount_plans hp on hp.designation_id = ds.id
    where ds.department_id = v_snapshot.department_id and ds.status = 'active'
    order by (hp.id is not null) desc,
             private.headcount_on(v_snapshot.org_id, v_snapshot.department_id, ds.id, v_month_end) desc, ds.name
    limit 1;
    if v_designation is not null then
      v_drafted := v_drafted + private.draft_snapshot_seats(v_snapshot, v_designation, 'new_position', v_missing,
                                                             (v_figures ->> 'budget_ok_new')::integer - v_pending_new);
    end if;
  end if;
  return v_drafted;
end;
$$;

-- A person in a sanctioned position leaves -> a replacement vacancy is drafted at once.
create or replace function private.on_employee_separation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gross numeric;
begin
  if old.status = 'active' and new.status in ('inactive', 'terminated') and new.designation_id is not null
     and exists (select 1 from public.headcount_plans hp where hp.designation_id = new.designation_id) then
    select c.gross into v_gross from public.employee_compensation c where c.employee_id = new.id and c.effective_to is null;
    perform private.insert_vacancy(new.org_id, new.department_id, new.designation_id, new.office_id, 1,
                                   'replacement', 'separation', new.id, null,
                                   date_trunc('month', coalesce(new.exit_date, current_date))::date, v_gross, 'unknown',
                                   null, 'Drafted automatically when the position holder left');
  end if;
  return new;
end;
$$;
create trigger draft_replacement_vacancy after update of status on public.employees
  for each row execute function private.on_employee_separation();

create or replace function private.require_any_permission(p_keys text[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from unnest(p_keys) as k where private.has_permission(k)) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
end;
$$;

-- The month a request is about: first day, not in the future (org timezone).
create or replace function private.workforce_month(p_month date)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month date := date_trunc('month', coalesce(p_month, private.org_today(private.current_org_id())))::date;
begin
  if v_month > date_trunc('month', private.org_today(private.current_org_id()))::date then
    raise exception 'Pick the current or an earlier month' using errcode = '22023';
  end if;
  return v_month;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: setup
-- -----------------------------------------------------------------------------
create or replace function public.save_workforce_settings(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_row    public.workforce_settings;
  v_new    public.workforce_settings;
begin
  perform private.require_permission('headcount.manage');
  perform private.seed_workforce_defaults(v_org_id);
  select * into v_row from public.workforce_settings where org_id = v_org_id for update;
  v_new := v_row;
  v_new.capacity_hours := coalesce((p ->> 'capacity_hours')::numeric, v_row.capacity_hours);
  v_new.availability_source := coalesce(p ->> 'availability_source', v_row.availability_source);
  v_new.fixed_availability_percent := coalesce((p ->> 'fixed_availability_percent')::numeric, v_row.fixed_availability_percent);
  v_new.band_underload := coalesce((p ->> 'band_underload')::numeric, v_row.band_underload);
  v_new.band_watch := coalesce((p ->> 'band_watch')::numeric, v_row.band_watch);
  v_new.band_overload := coalesce((p ->> 'band_overload')::numeric, v_row.band_overload);
  v_new.band_critical := coalesce((p ->> 'band_critical')::numeric, v_row.band_critical);
  v_new.sustain_months := coalesce((p ->> 'sustain_months')::smallint, v_row.sustain_months);
  v_new.attrition_flag_percent := coalesce((p ->> 'attrition_flag_percent')::numeric, v_row.attrition_flag_percent);

  if v_new.capacity_hours not between 40 and 400 then
    raise exception 'Monthly hours per person must be between 40 and 400' using errcode = '22023';
  end if;
  if v_new.availability_source not in ('attendance', 'fixed') then
    raise exception 'Availability comes from attendance or a fixed percent' using errcode = '22023';
  end if;
  if v_new.fixed_availability_percent not between 50 and 100 then
    raise exception 'Fixed availability must be between 50 and 100 percent' using errcode = '22023';
  end if;
  if not (v_new.band_underload > 0 and v_new.band_underload < v_new.band_watch
          and v_new.band_watch < v_new.band_overload and v_new.band_overload < v_new.band_critical
          and v_new.band_critical <= 9) then
    raise exception 'Bands must rise: underloaded < watch < overload < critical' using errcode = '22023';
  end if;
  if v_new.sustain_months not between 1 and 6 then
    raise exception 'Months in a row must be between 1 and 6' using errcode = '22023';
  end if;
  if v_new.attrition_flag_percent not between 1 and 100 then
    raise exception 'The attrition limit must be between 1 and 100 percent' using errcode = '22023';
  end if;

  update public.workforce_settings
     set capacity_hours = v_new.capacity_hours, availability_source = v_new.availability_source,
         fixed_availability_percent = v_new.fixed_availability_percent, band_underload = v_new.band_underload,
         band_watch = v_new.band_watch, band_overload = v_new.band_overload, band_critical = v_new.band_critical,
         sustain_months = v_new.sustain_months, attrition_flag_percent = v_new.attrition_flag_percent,
         confirmed_at = case when coalesce((p ->> 'confirm')::boolean, false) then now() end,
         confirmed_by = case when coalesce((p ->> 'confirm')::boolean, false) then auth.uid() end
   where org_id = v_org_id
  returning * into v_row;
  return to_jsonb(v_row) - array['org_id', 'created_by', 'updated_by'];
end;
$$;

-- p: method, per_employees (workforce.manage); monthly_budget (headcount.manage). Keys left out keep their value.
create or replace function public.save_department_workforce(p_department_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_row    public.department_workforce;
  v_method text;
  v_ratio  integer;
  v_budget numeric;
begin
  perform private.require_any_permission(array['workforce.manage', 'headcount.manage']);
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org_id and status = 'active') then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  select * into v_row from public.department_workforce where department_id = p_department_id for update;
  v_method := coalesce(v_row.method, 'hours');
  v_ratio := v_row.per_employees;
  v_budget := v_row.monthly_budget;

  if p ? 'method' or p ? 'per_employees' then
    perform private.require_permission('workforce.manage');
    v_method := coalesce(private.jtext(p, 'method'), v_method);
    if v_method not in ('hours', 'output_smv', 'volume_std', 'ratio') then
      raise exception 'Unknown workload method' using errcode = '22023';
    end if;
    v_ratio := case when p ? 'per_employees' then (private.jtext(p, 'per_employees'))::integer else v_ratio end;
    if v_method = 'ratio' and (v_ratio is null or v_ratio not between 5 and 10000) then
      raise exception 'Enter how many employees one person serves (5 to 10,000)' using errcode = '22023';
    end if;
  end if;
  if p ? 'monthly_budget' then
    perform private.require_permission('headcount.manage');
    v_budget := (private.jtext(p, 'monthly_budget'))::numeric;
    if v_budget is not null and (v_budget < 0 or v_budget > 999999999999) then
      raise exception 'Enter a monthly budget of zero or more' using errcode = '22023';
    end if;
  end if;

  insert into public.department_workforce (org_id, department_id, method, per_employees, monthly_budget)
  values (v_org_id, p_department_id, v_method, case when v_method = 'ratio' then v_ratio end, v_budget)
  on conflict (department_id) do update
    set method = excluded.method, per_employees = excluded.per_employees, monthly_budget = excluded.monthly_budget;
end;
$$;

-- p_rows: [{designation_id, sanctioned}]. Designations left out keep their plan.
create or replace function public.save_headcount_plan(p_department_id uuid, p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_row    jsonb;
  v_count  integer;
begin
  perform private.require_permission('headcount.manage');
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org_id) then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Send the plan as a list' using errcode = '22023';
  end if;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from public.designations
                   where id = (v_row ->> 'designation_id')::uuid and department_id = p_department_id and org_id = v_org_id) then
      raise exception 'Designation not found in this department' using errcode = 'P0002';
    end if;
    v_count := (v_row ->> 'sanctioned')::integer;
    if v_count is null or v_count not between 0 and 10000 then
      raise exception 'Sanctioned positions must be a whole number from 0 to 10,000' using errcode = '22023';
    end if;
    insert into public.headcount_plans (org_id, department_id, designation_id, sanctioned)
    values (v_org_id, p_department_id, (v_row ->> 'designation_id')::uuid, v_count)
    on conflict (designation_id) do update set sanctioned = excluded.sanctioned;
  end loop;
end;
$$;

-- Replaces a department's output / volume figures for a month.
-- p_rows: [{metric_key, label, quantity, std_minutes}]
create or replace function public.save_workload_inputs(p_department_id uuid, p_month date, p_rows jsonb, p_source text default 'manual')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_month  date;
  v_method text;
  v_row    jsonb;
  v_count  integer := 0;
begin
  perform private.require_permission('workforce.manage');
  v_month := private.workforce_month(p_month);
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org_id) then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  select method into v_method from public.department_workforce where department_id = p_department_id;
  if coalesce(v_method, 'hours') not in ('output_smv', 'volume_std') then
    raise exception 'Output figures are used only by the output (SMV) and volume methods; change the method first'
      using errcode = '22023';
  end if;
  if coalesce(p_source, 'manual') not in ('manual', 'csv') then
    raise exception 'Source must be manual or csv' using errcode = '22023';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Send the figures as a list' using errcode = '22023';
  end if;
  if (select count(distinct lower(btrim(r ->> 'metric_key'))) from jsonb_array_elements(p_rows) r)
     <> jsonb_array_length(p_rows) then
    raise exception 'Each item may appear only once' using errcode = '23505';
  end if;

  delete from public.workload_inputs where department_id = p_department_id and period_month = v_month;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    if char_length(btrim(coalesce(v_row ->> 'metric_key', ''))) not between 1 and 40 then
      raise exception 'Each row needs an item code of up to 40 characters' using errcode = '23502';
    end if;
    if (v_row ->> 'quantity') is null or (v_row ->> 'quantity')::numeric < 0
       or (v_row ->> 'quantity')::numeric > 999999999 then
      raise exception 'Quantity must be zero or more (row %)', v_row ->> 'metric_key' using errcode = '22023';
    end if;
    if (v_row ->> 'std_minutes') is null or (v_row ->> 'std_minutes')::numeric <= 0
       or (v_row ->> 'std_minutes')::numeric > 100000 then
      raise exception 'Minutes per unit must be above zero (row %)', v_row ->> 'metric_key' using errcode = '22023';
    end if;
    insert into public.workload_inputs (org_id, department_id, period_month, metric_key, label, quantity, std_minutes, source)
    values (v_org_id, p_department_id, v_month, btrim(v_row ->> 'metric_key'),
            nullif(left(btrim(v_row ->> 'label'), 80), ''), (v_row ->> 'quantity')::numeric,
            (v_row ->> 'std_minutes')::numeric, coalesce(p_source, 'manual'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Builds (or rebuilds) every active department's snapshot for a month. Vacancies are
-- drafted only from the current and the previous month; older months are history.
create or replace function public.build_workload_snapshots(p_month date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id   uuid := private.current_org_id();
  v_month    date;
  v_dept     record;
  v_figures  jsonb;
  v_snapshot uuid;
  v_count    integer := 0;
  v_drafted  integer := 0;
  v_drafts   boolean;
begin
  perform private.require_permission('workforce.manage');
  v_month := private.workforce_month(p_month);
  perform private.seed_workforce_defaults(v_org_id);
  v_drafts := v_month >= (date_trunc('month', private.org_today(v_org_id)) - interval '1 month')::date;

  for v_dept in select d.id from public.departments d where d.org_id = v_org_id and d.status = 'active' order by d.name loop
    v_figures := private.department_workload(v_org_id, v_dept.id, v_month);
    insert into public.workload_snapshots (org_id, department_id, period_month, method, workload_index, band, action,
                                           figures, built_at, built_by)
    values (v_org_id, v_dept.id, v_month, v_figures ->> 'method', (v_figures ->> 'index')::numeric,
            v_figures ->> 'band', v_figures ->> 'action', v_figures, now(), auth.uid())
    on conflict (department_id, period_month) do update
      set method = excluded.method, workload_index = excluded.workload_index, band = excluded.band,
          action = excluded.action, figures = excluded.figures, built_at = now(), built_by = auth.uid()
    returning id into v_snapshot;
    v_count := v_count + 1;
    if v_drafts then
      v_drafted := v_drafted + private.draft_vacancies_from_snapshot(v_snapshot);
    end if;
  end loop;

  perform private.write_audit(v_org_id, 'workforce.snapshots_built', 'workload_snapshots', null, null,
                              jsonb_build_object('period_month', v_month, 'departments', v_count, 'seats_drafted', v_drafted));
  return jsonb_build_object('period_month', v_month, 'departments', v_count, 'seats_drafted', v_drafted,
                            'drafting', v_drafts);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: reading
-- -----------------------------------------------------------------------------
create or replace function public.get_workforce_dashboard(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id    uuid := private.current_org_id();
  v_month     date;
  v_month_end date;
  v_money     boolean := private.has_permission('compensation.view');
begin
  perform private.require_any_permission(array['workforce.view', 'workforce.manage', 'headcount.manage']);
  v_month := private.workforce_month(p_month);
  v_month_end := (v_month + interval '1 month' - interval '1 day')::date;
  return jsonb_build_object(
    'period_month', v_month,
    'settings', (select to_jsonb(s) - array['org_id', 'created_by', 'updated_by']
                 from public.workforce_settings s where s.org_id = v_org_id),
    'can', jsonb_build_object(
      'manage', private.has_permission('workforce.manage'), 'headcount', private.has_permission('headcount.manage'),
      'request', private.has_permission('vacancy.request'), 'review', private.has_permission('vacancy.review'),
      'approve', private.has_permission('vacancy.approve'), 'money', v_money),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'name', d.name,
        'method', coalesce(dw.method, 'hours'), 'per_employees', dw.per_employees,
        'monthly_budget', case when v_money then dw.monthly_budget end,
        'plan', coalesce((
          select jsonb_agg(jsonb_build_object(
            'designation_id', ds.id, 'designation_name', ds.name, 'grade_code', g.code,
            'sanctioned', coalesce(hp.sanctioned, 0), 'planned', hp.id is not null,
            'active', private.headcount_on(v_org_id, d.id, ds.id, v_month_end)) order by ds.name)
          from public.designations ds
          join public.grades g on g.id = ds.grade_id
          left join public.headcount_plans hp on hp.designation_id = ds.id
          where ds.department_id = d.id and ds.status = 'active'), '[]'::jsonb),
        'inputs', coalesce((
          select jsonb_agg(jsonb_build_object('metric_key', i.metric_key, 'label', i.label, 'quantity', i.quantity,
                                              'std_minutes', i.std_minutes, 'source', i.source) order by i.metric_key)
          from public.workload_inputs i where i.department_id = d.id and i.period_month = v_month), '[]'::jsonb),
        'snapshot', (select private.mask_workforce_money(s.figures, v_money) || jsonb_build_object('built_at', s.built_at)
                     from public.workload_snapshots s where s.department_id = d.id and s.period_month = v_month),
        'trend', coalesce((
          select jsonb_agg(jsonb_build_object('period_month', s.period_month, 'index', s.workload_index, 'band', s.band)
                           order by s.period_month)
          from public.workload_snapshots s
          where s.department_id = d.id and s.period_month between (v_month - interval '5 months')::date and v_month), '[]'::jsonb),
        'open_seats', (select coalesce(sum(v.seats), 0) from public.vacancies v
                       where v.department_id = d.id and v.status in ('draft', 'hr_reviewed', 'approved', 'on_hold')))
        order by d.name)
      from public.departments d
      left join public.department_workforce dw on dw.department_id = d.id
      where d.org_id = v_org_id and d.status = 'active'), '[]'::jsonb));
end;
$$;

create or replace function public.list_vacancies(p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id   uuid := private.current_org_id();
  v_money    boolean := private.has_permission('compensation.view');
  v_all      boolean := private.has_permission('workforce.view') or private.has_permission('vacancy.review')
                        or private.has_permission('vacancy.approve');
  v_own_dept uuid;
begin
  perform private.require_any_permission(array['workforce.view', 'vacancy.request', 'vacancy.review', 'vacancy.approve']);
  select e.department_id into v_own_dept from public.employees e where e.id = private.current_employee_id();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', v.id, 'department_id', v.department_id, 'department_name', d.name,
      'designation_id', v.designation_id, 'designation_name', ds.name, 'grade_code', g.code,
      'office_name', o.name, 'seats', v.seats, 'reason', v.reason, 'origin', v.origin,
      'separated_employee_name', se.full_name, 'period_month', v.period_month,
      'estimated_monthly_cost', case when v_money then v.estimated_monthly_cost end,
      'budget_status', v.budget_status,
      'recommendation', private.mask_workforce_money(v.recommendation, v_money),
      'latest_snapshot', (select private.mask_workforce_money(s.figures, v_money) from public.workload_snapshots s
                          where s.department_id = v.department_id order by s.period_month desc limit 1),
      'note', v.note, 'status', v.status, 'decision_note', v.decision_note,
      'created_at', v.created_at, 'drafted_by_name', cu.full_name,
      'hr_reviewed_by', v.hr_reviewed_by, 'hr_reviewed_by_name', ru.full_name, 'hr_reviewed_at', v.hr_reviewed_at,
      'decided_by_name', du.full_name, 'decided_at', v.decided_at,
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('event', ev.event, 'from_status', ev.from_status, 'to_status', ev.to_status,
                                            'note', ev.note, 'actor_name', au.full_name, 'created_at', ev.created_at)
                         order by ev.created_at)
        from public.vacancy_events ev
        left join public.user_profiles au on au.id = ev.actor_user_id
        where ev.vacancy_id = v.id), '[]'::jsonb))
      order by v.created_at desc)
    from public.vacancies v
    join public.departments d on d.id = v.department_id
    join public.designations ds on ds.id = v.designation_id
    join public.grades g on g.id = ds.grade_id
    left join public.offices o on o.id = v.office_id
    left join public.employees se on se.id = v.separated_employee_id
    left join public.user_profiles cu on cu.id = v.created_by
    left join public.user_profiles ru on ru.id = v.hr_reviewed_by
    left join public.user_profiles du on du.id = v.decided_by
    where v.org_id = v_org_id
      and (p_status is null or v.status = p_status)
      and (v_all or v.department_id = v_own_dept)), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: vacancy workflow
-- -----------------------------------------------------------------------------
-- p: department_id, designation_id, seats, reason (replacement | new_position), note
create or replace function public.draft_vacancy(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id      uuid := private.current_org_id();
  v_dept        uuid := (private.jtext(p, 'department_id'))::uuid;
  v_designation uuid := (private.jtext(p, 'designation_id'))::uuid;
  v_seats       integer := (private.jtext(p, 'seats'))::integer;
  v_reason      text := coalesce(private.jtext(p, 'reason'), 'replacement');
  v_today       date := private.org_today(v_org_id);
  v_open        integer;
  v_cost        numeric;
begin
  perform private.require_permission('vacancy.request');
  if not exists (select 1 from public.departments where id = v_dept and org_id = v_org_id and status = 'active') then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if not (private.has_permission('vacancy.review') or private.has_permission('workforce.view'))
     and v_dept is distinct from (select e.department_id from public.employees e where e.id = private.current_employee_id()) then
    raise exception 'You can request vacancies only for your own department' using errcode = '42501';
  end if;
  if not exists (select 1 from public.designations where id = v_designation and department_id = v_dept and status = 'active') then
    raise exception 'Pick a designation of this department' using errcode = '22023';
  end if;
  if v_seats is null or v_seats not between 1 and 500 then
    raise exception 'Seats must be between 1 and 500' using errcode = '22023';
  end if;
  if v_reason not in ('replacement', 'new_position') then
    raise exception 'Reason must be replacement or new position' using errcode = '22023';
  end if;
  if v_reason = 'replacement' then
    select hp.sanctioned - private.headcount_on(v_org_id, v_dept, v_designation, v_today)
             - private.open_sanctioned_seats(v_dept, v_designation)
      into v_open
    from public.headcount_plans hp where hp.designation_id = v_designation;
    if coalesce(v_open, 0) < v_seats then
      raise exception 'Only % sanctioned position(s) are open for this designation; draft a new position instead',
        greatest(coalesce(v_open, 0), 0) using errcode = '23514';
    end if;
  end if;
  v_cost := coalesce(private.average_gross(v_org_id, v_dept, v_designation, v_today),
                     private.average_gross(v_org_id, v_dept, null, v_today));
  return private.insert_vacancy(v_org_id, v_dept, v_designation, null, v_seats, v_reason, 'manual', null, null,
                                date_trunc('month', v_today)::date, v_cost, 'unknown',
                                (select s.figures from public.workload_snapshots s where s.department_id = v_dept
                                 order by s.period_month desc limit 1),
                                nullif(left(btrim(p ->> 'note'), 500), ''));
end;
$$;

-- HR step. p_action: forward | hold | reject. While a draft, p may change seats / designation_id.
create or replace function public.review_vacancy(p_vacancy_id uuid, p_action text, p_note text default null,
                                                 p jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vac   public.vacancies;
  v_to    text;
  v_seats integer;
begin
  perform private.require_permission('vacancy.review');
  select * into v_vac from public.vacancies where id = p_vacancy_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Vacancy not found' using errcode = 'P0002';
  end if;
  if v_vac.status not in ('draft', 'on_hold') then
    raise exception 'Only a draft or held vacancy can be reviewed (now %)', v_vac.status using errcode = '22023';
  end if;
  if p_action not in ('forward', 'hold', 'reject') then
    raise exception 'Action must be forward, hold or reject' using errcode = '22023';
  end if;
  if p_action in ('hold', 'reject') and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  if p_action = 'hold' and v_vac.status = 'on_hold' then
    raise exception 'This vacancy is already on hold' using errcode = '22023';
  end if;

  if v_vac.status = 'draft' and (p ? 'seats' or p ? 'designation_id') then
    v_seats := coalesce((private.jtext(p, 'seats'))::integer, v_vac.seats);
    if v_seats not between 1 and 500 then
      raise exception 'Seats must be between 1 and 500' using errcode = '22023';
    end if;
    if p ? 'designation_id' and not exists (select 1 from public.designations
                                           where id = (private.jtext(p, 'designation_id'))::uuid
                                             and department_id = v_vac.department_id and status = 'active') then
      raise exception 'Pick a designation of this department' using errcode = '22023';
    end if;
    update public.vacancies
       set seats = v_seats,
           designation_id = coalesce((private.jtext(p, 'designation_id'))::uuid, designation_id),
           estimated_monthly_cost = case when estimated_monthly_cost is not null
                                         then round(estimated_monthly_cost / seats * v_seats, 2) end
     where id = p_vacancy_id;
  end if;

  v_to := case p_action when 'forward' then 'hr_reviewed' when 'hold' then 'on_hold' else 'rejected' end;
  update public.vacancies
     set status = v_to,
         hr_reviewed_by = case when p_action = 'forward' then auth.uid() else hr_reviewed_by end,
         hr_reviewed_at = case when p_action = 'forward' then now() else hr_reviewed_at end
   where id = p_vacancy_id;
  perform private.vacancy_event(p_vacancy_id, 'reviewed_' || p_action, v_vac.status, v_to, p_note);
end;
$$;

-- Approver step (maker-checker: never the person who forwarded it).
-- p_decision: approve | hold | reject | send_back
create or replace function public.decide_vacancy(p_vacancy_id uuid, p_decision text, p_note text default null,
                                                 p_over_budget boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vac public.vacancies;
  v_to  text;
begin
  perform private.require_permission('vacancy.approve');
  select * into v_vac from public.vacancies where id = p_vacancy_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Vacancy not found' using errcode = 'P0002';
  end if;
  if v_vac.status <> 'hr_reviewed' then
    raise exception 'Only a reviewed vacancy can be decided (now %)', v_vac.status using errcode = '22023';
  end if;
  if v_vac.hr_reviewed_by = auth.uid() then
    raise exception 'Someone other than the reviewer must decide this vacancy' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'hold', 'reject', 'send_back') then
    raise exception 'Decision must be approve, hold, reject or send back' using errcode = '22023';
  end if;
  if (p_decision <> 'approve' or coalesce(p_over_budget, false)) and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;

  if p_decision = 'approve' then
    if v_vac.budget_status = 'blocked' and not coalesce(p_over_budget, false) then
      raise exception 'This vacancy is over the department budget; approve over budget with a reason' using errcode = '23514';
    end if;
    if v_vac.reason = 'new_position' then
      perform private.require_permission('headcount.manage');
      insert into public.headcount_plans (org_id, department_id, designation_id, sanctioned)
      values (v_vac.org_id, v_vac.department_id, v_vac.designation_id, v_vac.seats)
      on conflict (designation_id) do update set sanctioned = public.headcount_plans.sanctioned + excluded.sanctioned;
    end if;
  end if;

  v_to := case p_decision when 'approve' then 'approved' when 'hold' then 'on_hold'
                          when 'reject' then 'rejected' else 'draft' end;
  update public.vacancies
     set status = v_to, decided_by = auth.uid(), decided_at = now(), decision_note = nullif(left(btrim(p_note), 500), '')
   where id = p_vacancy_id;
  perform private.vacancy_event(p_vacancy_id, case when p_decision = 'approve' and coalesce(p_over_budget, false)
                                                   then 'approved_over_budget' else p_decision end,
                                'hr_reviewed', v_to, p_note);
end;
$$;

create or replace function public.cancel_vacancy(p_vacancy_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vac public.vacancies;
begin
  perform private.require_permission('vacancy.review');
  select * into v_vac from public.vacancies where id = p_vacancy_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Vacancy not found' using errcode = 'P0002';
  end if;
  if v_vac.status not in ('draft', 'hr_reviewed', 'approved', 'on_hold') then
    raise exception 'This vacancy is already closed (%)', v_vac.status using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  update public.vacancies set status = 'cancelled', decision_note = left(btrim(p_reason), 500) where id = p_vacancy_id;
  perform private.vacancy_event(p_vacancy_id, 'cancelled', v_vac.status, 'cancelled', p_reason);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges: tables closed, functions only
-- -----------------------------------------------------------------------------
alter table public.workforce_settings   enable row level security;
alter table public.department_workforce enable row level security;
alter table public.headcount_plans      enable row level security;
alter table public.workload_inputs      enable row level security;
alter table public.workload_snapshots   enable row level security;
alter table public.vacancies            enable row level security;
alter table public.vacancy_events       enable row level security;
revoke all on table public.workforce_settings, public.department_workforce, public.headcount_plans,
                    public.workload_inputs, public.workload_snapshots, public.vacancies, public.vacancy_events
from anon, authenticated;

revoke all on function
  public.save_workforce_settings(jsonb), public.save_department_workforce(uuid, jsonb),
  public.save_headcount_plan(uuid, jsonb), public.save_workload_inputs(uuid, date, jsonb, text),
  public.build_workload_snapshots(date), public.get_workforce_dashboard(date), public.list_vacancies(text),
  public.draft_vacancy(jsonb), public.review_vacancy(uuid, text, text, jsonb),
  public.decide_vacancy(uuid, text, text, boolean), public.cancel_vacancy(uuid, text)
from public, anon;
grant execute on function
  public.save_workforce_settings(jsonb), public.save_department_workforce(uuid, jsonb),
  public.save_headcount_plan(uuid, jsonb), public.save_workload_inputs(uuid, date, jsonb, text),
  public.build_workload_snapshots(date), public.get_workforce_dashboard(date), public.list_vacancies(text),
  public.draft_vacancy(jsonb), public.review_vacancy(uuid, text, text, jsonb),
  public.decide_vacancy(uuid, text, text, boolean), public.cancel_vacancy(uuid, text)
to authenticated;

revoke all on function
  private.seed_workforce_defaults(uuid), private.seed_org_defaults(uuid), private.workload_figures(jsonb),
  private.headcount_on(uuid, uuid, uuid, date), private.open_sanctioned_seats(uuid, uuid),
  private.average_gross(uuid, uuid, uuid, date), private.department_workload(uuid, uuid, date),
  private.mask_workforce_money(jsonb, boolean), private.vacancy_event(uuid, text, text, text, text),
  private.insert_vacancy(uuid, uuid, uuid, uuid, integer, text, text, uuid, uuid, date, numeric, text, jsonb, text),
  private.draft_snapshot_seats(public.workload_snapshots, uuid, text, integer, integer),
  private.draft_vacancies_from_snapshot(uuid), private.on_employee_separation(),
  private.require_any_permission(text[]), private.workforce_month(date), private.vacancy_events_append_only()
from public, anon, authenticated;
