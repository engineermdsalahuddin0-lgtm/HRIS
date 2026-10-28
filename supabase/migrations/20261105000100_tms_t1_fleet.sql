-- =============================================================================
-- TMS T1: fleet foundation — vehicles, drivers, vehicle and licence papers in the DMS.
-- Module handbook: src/TMS/architecture.md, features.md, schema.md, security.md.
--
--   * Vehicles: BRTA registration no. (unique per company, spaces normalised), type,
--     fuel (dual fuel allowed, e.g. petrol + CNG), tank / CNG capacity, ownership,
--     branch / department, odometer (never goes back), status, default driver.
--   * Drivers: an HR employee OR an outside (contract / rented) driver with name,
--     phone and NID (shown masked). Licence: number, class (motorcycle / light /
--     medium / heavy), professional or not, expiry. A driver with a login uses the
--     driver view (T2) without any permission.
--   * Papers: a DMS base folder "Transport & Vehicles" with six types (registration,
--     fitness, tax token, route permit, insurance, driving licence), and documents
--     linked to a vehicle or a driver; expiry, review and reminders are the DMS's.
--   * Permissions tms.manage / approve / inventory / view_costs. Anyone may request a vehicle (T2), like a helpdesk ticket.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.list_dms_audit') is null then
    raise exception 'Apply the DMS migrations (20261104000100…0600) first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Permissions and defaults
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('tms.manage',     'tms', 'Transport desk: vehicles, drivers, trips, fuel checks, maintenance, setup', false),
  ('tms.approve',    'tms', 'Approve vehicle requests of your own department',                          false),
  ('tms.inventory',  'tms', 'Spare parts and tyre stock: receive, issue, adjust',                       false),
  ('tms.view_costs', 'tms', 'Transport cost dashboard: cost per vehicle and per km, fuel spend',        false)
on conflict (key) do nothing;

create table public.tms_settings (
  org_id                   uuid primary key references public.organizations (id),
  enabled                  boolean not null default true,
  fuel_prices              jsonb not null default '{}' check (jsonb_typeof(fuel_prices) = 'object'),
  price_tolerance_pct      smallint not null default 10 check (price_tolerance_pct between 0 and 100),
  efficiency_tolerance_pct smallint not null default 25 check (efficiency_tolerance_pct between 0 and 100),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  created_by               uuid references public.user_profiles (id),
  updated_by               uuid references public.user_profiles (id)
);
create trigger set_row_meta before insert or update on public.tms_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.tms_settings
  for each row execute function private.audit_row_change();

create or replace function private.seed_tms_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Once per company: later calls never bring back what the Admin removed.
  insert into public.tms_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  if not found then
    return;
  end if;
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['tms.manage', 'tms.approve', 'tms.inventory']
    when 'manager'    then array['tms.approve']
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
  perform private.seed_recruit_defaults(p_org_id);
  perform private.seed_organogram_defaults(p_org_id);
  perform private.seed_communication_defaults(p_org_id);
  perform private.seed_assistant_defaults(p_org_id);
  perform private.seed_dms_defaults(p_org_id);
  perform private.seed_tms_defaults(p_org_id);
end;
$$;

select private.seed_tms_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Vehicles and drivers
-- -----------------------------------------------------------------------------
create table public.tms_drivers (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations (id),
  employee_id    uuid,
  name           text check (name is null or char_length(btrim(name)) between 2 and 120),
  phone          text check (phone is null or phone ~ '^\+?[0-9 -]{7,20}$'),
  nid            text check (nid is null or nid ~ '^[0-9]{10,17}$'),
  user_id        uuid references public.user_profiles (id),
  licence_no     text not null check (char_length(btrim(licence_no)) between 4 and 40),
  licence_class  text not null check (licence_class in ('motorcycle', 'light', 'medium', 'heavy')),
  licence_kind   text not null default 'professional' check (licence_kind in ('professional', 'non_professional')),
  licence_expiry date not null,
  status         text not null default 'active' check (status in ('active', 'off_duty', 'inactive')),
  notes          text check (notes is null or char_length(notes) <= 1000),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint tms_drivers_org_id_id_uq unique (org_id, id),
  constraint tms_drivers_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint tms_drivers_who check (employee_id is not null or (name is not null and phone is not null))
);
create unique index tms_drivers_employee_uq on public.tms_drivers (org_id, employee_id) where employee_id is not null;
create unique index tms_drivers_licence_uq on public.tms_drivers (org_id, upper(btrim(licence_no)));
select private.attach_standard_triggers('public.tms_drivers');

create table public.tms_vehicles (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  reg_no             text not null check (char_length(reg_no) between 4 and 40),
  vtype              text not null check (vtype in ('car', 'microbus', 'pickup', 'covered_van', 'truck', 'bus', 'motorcycle', 'other')),
  make               text check (make is null or char_length(make) <= 60),
  model              text check (model is null or char_length(model) <= 60),
  year               smallint check (year is null or year between 1970 and 2100),
  color              text check (color is null or char_length(color) <= 30),
  fuel               text not null check (fuel in ('octane', 'petrol', 'diesel', 'cng', 'lpg', 'electric')),
  fuel2              text check (fuel2 is null or fuel2 in ('octane', 'petrol', 'diesel', 'cng', 'lpg')),
  tank_l             numeric(7, 1) check (tank_l is null or tank_l between 1 and 2000),
  cng_m3             numeric(7, 1) check (cng_m3 is null or cng_m3 between 1 and 500),
  seats              smallint check (seats is null or seats between 1 and 100),
  payload_kg         integer check (payload_kg is null or payload_kg between 1 and 100000),
  ownership          text not null default 'owned' check (ownership in ('owned', 'leased', 'rented')),
  branch_id          uuid,
  department_id      uuid,
  chassis_no         text check (chassis_no is null or char_length(chassis_no) <= 40),
  engine_no          text check (engine_no is null or char_length(engine_no) <= 40),
  purchase_date      date,
  purchase_cost      numeric(14, 2) check (purchase_cost is null or purchase_cost >= 0),
  odometer_km        numeric(10, 1) not null default 0 check (odometer_km >= 0),
  normal_km_per_unit numeric(6, 2) check (normal_km_per_unit is null or normal_km_per_unit > 0),
  status             text not null default 'active' check (status in ('active', 'in_maintenance', 'off_road', 'disposed')),
  driver_id          uuid,
  notes              text check (notes is null or char_length(notes) <= 1000),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint tms_vehicles_org_id_id_uq unique (org_id, id),
  constraint tms_vehicles_reg_uq unique (org_id, reg_no),
  constraint tms_vehicles_branch_fk foreign key (org_id, branch_id) references public.branches (org_id, id),
  constraint tms_vehicles_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint tms_vehicles_driver_fk foreign key (org_id, driver_id) references public.tms_drivers (org_id, id),
  constraint tms_vehicles_fuel2 check (fuel2 is null or fuel2 <> fuel)
);
-- A driver is the default driver of one vehicle at a time.
create unique index tms_vehicles_driver_uq on public.tms_vehicles (org_id, driver_id) where driver_id is not null and status <> 'disposed';
select private.attach_standard_triggers('public.tms_vehicles');

-- -----------------------------------------------------------------------------
-- Papers in the DMS: base folder "Transport & Vehicles" and six types
-- -----------------------------------------------------------------------------
insert into public.dms_catalog_folders (code, name, profile_code, sort) values ('TRP', 'Transport & Vehicles', null, 45);
insert into public.dms_catalog_doc_types (code, folder_code, name, field_schema, has_expiry, expiry_default, review_months, default_classification, sort)
select v.code, 'TRP', v.name, v.fields::jsonb, true, 'none', null, 'internal', v.sort
from (values
  ('VRC', 'Registration Certificate (BRTA)', '[{"key":"licence_no","label":"Registration / certificate number","type":"text","required":true},{"key":"authority","label":"Issued by","type":"text","required":true}]', 1),
  ('FIT', 'Fitness Certificate',             '[{"key":"licence_no","label":"Certificate number","type":"text","required":true},{"key":"authority","label":"Issued by","type":"text","required":true}]', 2),
  ('TTK', 'Tax Token',                       '[{"key":"licence_no","label":"Token number","type":"text","required":true},{"key":"authority","label":"Issued by","type":"text","required":true}]', 3),
  ('RPM', 'Route Permit',                    '[{"key":"licence_no","label":"Permit number","type":"text","required":true},{"key":"authority","label":"Issued by","type":"text","required":true},{"key":"route","label":"Route","type":"text"}]', 4),
  ('INS', 'Vehicle Insurance',               '[{"key":"licence_no","label":"Policy number","type":"text","required":true},{"key":"authority","label":"Insurer","type":"text","required":true}]', 5),
  ('DLC', 'Driving Licence',                 '[{"key":"licence_no","label":"Licence number","type":"text","required":true},{"key":"authority","label":"Issued by","type":"text","required":true}]', 6)
) as v (code, name, fields, sort);

-- Companies that already have the DMS get the new folder and types (only these; nothing else is re-enabled).
insert into public.dms_folders (org_id, origin, catalog_code, name, sort)
select s.org_id, 'base', 'TRP', 'Transport & Vehicles', 45 from public.dms_settings s
on conflict (org_id, catalog_code) do nothing;
insert into public.dms_doc_types (org_id, folder_id, code, name, origin, field_schema, has_expiry, expiry_default, review_months,
                                  default_classification, sort, ai_enabled, assistant_topic)
select f.org_id, f.id, t.code, t.name, 'catalog', t.field_schema, t.has_expiry, t.expiry_default, t.review_months,
       t.default_classification, t.sort, t.ai_default, t.assistant_topic
from public.dms_catalog_doc_types t join public.dms_folders f on f.catalog_code = 'TRP'
where t.folder_code = 'TRP'
on conflict (org_id, code) do nothing;

alter table public.dms_documents add column vehicle_id uuid;
alter table public.dms_documents add column driver_id uuid;
alter table public.dms_documents add constraint dms_documents_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id);
alter table public.dms_documents add constraint dms_documents_driver_fk foreign key (org_id, driver_id) references public.tms_drivers (org_id, id);
create index dms_documents_vehicle_idx on public.dms_documents (org_id, vehicle_id) where vehicle_id is not null;
create index dms_documents_driver_idx on public.dms_documents (org_id, driver_id) where driver_id is not null;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
-- "dhaka metro-ga  12-3456" → "DHAKA METRO-GA 12-3456"
create or replace function private.tms_norm_reg(p text)
returns text
language sql
immutable
set search_path = ''
as $$
  select upper(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'))
$$;

-- The licence class a vehicle type needs (BRTA: light up to ~2.5 t, medium up to ~6.5 t, heavy above).
create or replace function private.tms_class_needed(p_vtype text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_vtype when 'motorcycle' then 'motorcycle' when 'covered_van' then 'medium'
                      when 'truck' then 'heavy' when 'bus' then 'heavy' else 'light' end
$$;

-- Does the licence class allow the vehicle? Heavy covers medium and light; medium covers light; motorcycle only itself.
create or replace function private.tms_class_ok(p_class text, p_vtype text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case private.tms_class_needed(p_vtype)
    when 'motorcycle' then p_class = 'motorcycle'
    when 'light' then p_class in ('light', 'medium', 'heavy')
    when 'medium' then p_class in ('medium', 'heavy')
    else p_class = 'heavy' end
$$;

create or replace function private.tms_can_see()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('tms.manage') or private.has_permission('tms.approve') or private.has_permission('tms.view_costs')
      or private.has_permission('tms.inventory')
$$;

create or replace function private.tms_driver_name(d public.tms_drivers)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select e.full_name from public.employees e where e.id = d.employee_id), d.name)
$$;

create or replace function private.tms_driver_json(d public.tms_drivers)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', d.id, 'employee_id', d.employee_id, 'name', private.tms_driver_name(d), 'outside', d.employee_id is null,
    'phone', coalesce(d.phone, (select e.phone from public.employees e where e.id = d.employee_id)),
    'nid', case when d.nid is null then null when private.has_permission('tms.manage') then d.nid else '••••' || right(d.nid, 4) end,
    'has_login', d.user_id is not null,
    'licence_no', d.licence_no, 'licence_class', d.licence_class, 'licence_kind', d.licence_kind, 'licence_expiry', d.licence_expiry,
    'licence_status', private.dms_expiry_status(d.licence_expiry),
    'licence_days_left', d.licence_expiry - current_date,
    'status', d.status, 'notes', d.notes,
    'vehicle', (select jsonb_build_object('id', v.id, 'reg_no', v.reg_no) from public.tms_vehicles v
                where v.driver_id = d.id and v.status <> 'disposed' limit 1),
    'department', (select dp.name from public.employees e join public.departments dp on dp.id = e.department_id where e.id = d.employee_id))
$$;

-- Papers of a vehicle or driver (published DMS documents), with the earliest expiry first.
create or replace function private.tms_papers(p_vehicle_id uuid, p_driver_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'document_id', d.id, 'doc_code', d.doc_code, 'title', d.title, 'type_code', t.code, 'type_name', t.name,
           'expiry_date', d.expiry_date, 'expiry_status', private.dms_expiry_status(d.expiry_date),
           'days_left', d.expiry_date - current_date, 'lifecycle', d.lifecycle)
         order by d.expiry_date nulls last), '[]'::jsonb)
  from public.dms_documents d join public.dms_doc_types t on t.id = d.doc_type_id
  where d.lifecycle in ('published', 'pending')
    and ((p_vehicle_id is not null and d.vehicle_id = p_vehicle_id) or (p_driver_id is not null and d.driver_id = p_driver_id))
$$;

create or replace function private.tms_vehicle_json(v public.tms_vehicles, p_full boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', v.id, 'reg_no', v.reg_no, 'vtype', v.vtype, 'make', v.make, 'model', v.model, 'year', v.year, 'color', v.color,
    'fuel', v.fuel, 'fuel2', v.fuel2, 'tank_l', v.tank_l, 'cng_m3', v.cng_m3, 'seats', v.seats, 'payload_kg', v.payload_kg,
    'ownership', v.ownership, 'branch_id', v.branch_id, 'branch', (select b.name from public.branches b where b.id = v.branch_id),
    'department_id', v.department_id, 'department', (select d.name from public.departments d where d.id = v.department_id),
    'chassis_no', v.chassis_no, 'engine_no', v.engine_no, 'purchase_date', v.purchase_date,
    'purchase_cost', case when p_full then v.purchase_cost end,
    'odometer_km', v.odometer_km, 'normal_km_per_unit', v.normal_km_per_unit, 'status', v.status, 'notes', v.notes,
    'class_needed', private.tms_class_needed(v.vtype),
    'driver', (select jsonb_build_object('id', d.id, 'name', private.tms_driver_name(d)) from public.tms_drivers d where d.id = v.driver_id),
    'next_expiry', (select min(d.expiry_date) from public.dms_documents d where d.vehicle_id = v.id and d.lifecycle = 'published'),
    'papers_count', (select count(*) from public.dms_documents d where d.vehicle_id = v.id and d.lifecycle = 'published'))
$$;

-- -----------------------------------------------------------------------------
-- API
-- -----------------------------------------------------------------------------
create or replace function public.get_tms_fleet()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_full boolean := private.has_permission('tms.manage') or private.has_permission('tms.view_costs');
begin
  if not private.tms_can_see() then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  perform private.seed_tms_defaults(v_org);
  return jsonb_build_object(
    'can', jsonb_build_object('manage', private.has_permission('tms.manage'), 'approve', private.has_permission('tms.approve'),
                              'inventory', private.has_permission('tms.inventory'), 'view_costs', private.has_permission('tms.view_costs')),
    'vehicles', coalesce((select jsonb_agg(private.tms_vehicle_json(v, v_full) order by v.status = 'disposed', v.reg_no)
                          from public.tms_vehicles v where v.org_id = v_org), '[]'::jsonb),
    'drivers', coalesce((select jsonb_agg(private.tms_driver_json(d) order by d.status = 'inactive', private.tms_driver_name(d))
                         from public.tms_drivers d where d.org_id = v_org), '[]'::jsonb),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name) order by b.name)
                          from public.branches b where b.org_id = v_org and b.status = 'active'), '[]'::jsonb),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name)
                             from public.departments d where d.org_id = v_org and d.status = 'active'), '[]'::jsonb),
    'employees', case when private.has_permission('tms.manage') then coalesce((
                   select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'department', dp.name) order by e.full_name)
                   from public.employees e left join public.departments dp on dp.id = e.department_id
                   where e.org_id = v_org and e.status = 'active'
                     and not exists (select 1 from public.tms_drivers x where x.employee_id = e.id)), '[]'::jsonb) else '[]'::jsonb end);
end;
$$;

create or replace function public.get_tms_vehicle(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.tms_vehicles;
begin
  if not private.tms_can_see() then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  select * into v from public.tms_vehicles where id = p_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  return private.tms_vehicle_json(v, private.has_permission('tms.manage') or private.has_permission('tms.view_costs'))
      || jsonb_build_object('papers', private.tms_papers(v.id, null),
                            'driver_papers', case when v.driver_id is not null then private.tms_papers(null, v.driver_id) else '[]'::jsonb end);
end;
$$;

-- p: vehicle fields. The odometer never goes back; a disposed vehicle is frozen.
create or replace function public.save_tms_vehicle(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_old    public.tms_vehicles;
  v_reg    text := private.tms_norm_reg(p ->> 'reg_no');
  v_driver uuid := nullif(p ->> 'driver_id', '')::uuid;
  v_odo    numeric := nullif(p ->> 'odometer_km', '')::numeric;
  v_id     uuid;
  d        public.tms_drivers;
  v_vtype  text;
begin
  perform private.require_permission('tms.manage');
  if p_id is not null then
    select * into v_old from public.tms_vehicles where id = p_id and org_id = v_org for update;
    if not found then
      raise exception 'Vehicle not found' using errcode = 'P0002';
    end if;
    if v_old.status = 'disposed' then
      raise exception 'A disposed vehicle cannot be changed' using errcode = '23514';
    end if;
  end if;
  if char_length(v_reg) < 4 then
    raise exception 'Enter the registration number (e.g. DHAKA METRO-GA 12-3456)' using errcode = '22023';
  end if;
  v_vtype := coalesce(nullif(p ->> 'vtype', ''), v_old.vtype);
  if v_vtype is null or v_vtype not in ('car', 'microbus', 'pickup', 'covered_van', 'truck', 'bus', 'motorcycle', 'other') then
    raise exception 'Choose the vehicle type' using errcode = '22023';
  end if;
  if coalesce(nullif(p ->> 'fuel', ''), v_old.fuel) is null then
    raise exception 'Choose the fuel' using errcode = '22023';
  end if;
  if v_odo is not null and v_old.id is not null and v_odo < v_old.odometer_km then
    raise exception 'The odometer cannot go back (now % km)', v_old.odometer_km using errcode = '23514';
  end if;
  if nullif(p ->> 'branch_id', '') is not null and not exists (select 1 from public.branches where id = (p ->> 'branch_id')::uuid and org_id = v_org) then
    raise exception 'Choose a branch of your company' using errcode = '22023';
  end if;
  if nullif(p ->> 'department_id', '') is not null and not exists (select 1 from public.departments where id = (p ->> 'department_id')::uuid and org_id = v_org) then
    raise exception 'Choose a department of your company' using errcode = '22023';
  end if;
  if v_driver is not null then
    select * into d from public.tms_drivers where id = v_driver and org_id = v_org;
    if not found or d.status = 'inactive' then
      raise exception 'Choose an active driver' using errcode = '22023';
    end if;
    if not private.tms_class_ok(d.licence_class, v_vtype) then
      raise exception 'This driver''s licence (%) does not cover a % (needs %)', d.licence_class, v_vtype, private.tms_class_needed(v_vtype)
        using errcode = '23514';
    end if;
  end if;
  begin
    if p_id is null then
      insert into public.tms_vehicles (org_id, reg_no, vtype, make, model, year, color, fuel, fuel2, tank_l, cng_m3, seats, payload_kg,
                                       ownership, branch_id, department_id, chassis_no, engine_no, purchase_date, purchase_cost,
                                       odometer_km, normal_km_per_unit, driver_id, notes)
      values (v_org, v_reg, v_vtype, private.jtext(p, 'make'), private.jtext(p, 'model'), nullif(p ->> 'year', '')::smallint,
              private.jtext(p, 'color'), p ->> 'fuel', nullif(p ->> 'fuel2', ''), nullif(p ->> 'tank_l', '')::numeric,
              nullif(p ->> 'cng_m3', '')::numeric, nullif(p ->> 'seats', '')::smallint, nullif(p ->> 'payload_kg', '')::integer,
              coalesce(nullif(p ->> 'ownership', ''), 'owned'), nullif(p ->> 'branch_id', '')::uuid, nullif(p ->> 'department_id', '')::uuid,
              private.jtext(p, 'chassis_no'), private.jtext(p, 'engine_no'), nullif(p ->> 'purchase_date', '')::date,
              nullif(p ->> 'purchase_cost', '')::numeric, coalesce(v_odo, 0), nullif(p ->> 'normal_km_per_unit', '')::numeric,
              v_driver, private.jtext(p, 'notes'))
      returning id into v_id;
      return v_id;
    end if;
    update public.tms_vehicles
       set reg_no = v_reg, vtype = v_vtype,
           make = case when p ? 'make' then private.jtext(p, 'make') else make end,
           model = case when p ? 'model' then private.jtext(p, 'model') else model end,
           year = case when p ? 'year' then nullif(p ->> 'year', '')::smallint else year end,
           color = case when p ? 'color' then private.jtext(p, 'color') else color end,
           fuel = coalesce(nullif(p ->> 'fuel', ''), fuel),
           fuel2 = case when p ? 'fuel2' then nullif(p ->> 'fuel2', '') else fuel2 end,
           tank_l = case when p ? 'tank_l' then nullif(p ->> 'tank_l', '')::numeric else tank_l end,
           cng_m3 = case when p ? 'cng_m3' then nullif(p ->> 'cng_m3', '')::numeric else cng_m3 end,
           seats = case when p ? 'seats' then nullif(p ->> 'seats', '')::smallint else seats end,
           payload_kg = case when p ? 'payload_kg' then nullif(p ->> 'payload_kg', '')::integer else payload_kg end,
           ownership = coalesce(nullif(p ->> 'ownership', ''), ownership),
           branch_id = case when p ? 'branch_id' then nullif(p ->> 'branch_id', '')::uuid else branch_id end,
           department_id = case when p ? 'department_id' then nullif(p ->> 'department_id', '')::uuid else department_id end,
           chassis_no = case when p ? 'chassis_no' then private.jtext(p, 'chassis_no') else chassis_no end,
           engine_no = case when p ? 'engine_no' then private.jtext(p, 'engine_no') else engine_no end,
           purchase_date = case when p ? 'purchase_date' then nullif(p ->> 'purchase_date', '')::date else purchase_date end,
           purchase_cost = case when p ? 'purchase_cost' then nullif(p ->> 'purchase_cost', '')::numeric else purchase_cost end,
           odometer_km = coalesce(v_odo, odometer_km),
           normal_km_per_unit = case when p ? 'normal_km_per_unit' then nullif(p ->> 'normal_km_per_unit', '')::numeric else normal_km_per_unit end,
           status = coalesce(nullif(p ->> 'status', ''), status),
           driver_id = case when p ? 'driver_id' then v_driver else driver_id end,
           notes = case when p ? 'notes' then private.jtext(p, 'notes') else notes end
     where id = p_id;
    return p_id;
  exception when unique_violation then
    raise exception 'A vehicle with this registration number, or this default driver, already exists' using errcode = '23505';
  end;
end;
$$;

-- p: {employee_id | name, phone, nid; licence_no, licence_class, licence_kind, licence_expiry, status, notes}
create or replace function public.save_tms_driver(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_old public.tms_drivers;
  v_emp uuid := nullif(p ->> 'employee_id', '')::uuid;
  v_id  uuid;
  v_exp date := nullif(p ->> 'licence_expiry', '')::date;
begin
  perform private.require_permission('tms.manage');
  if p_id is not null then
    select * into v_old from public.tms_drivers where id = p_id and org_id = v_org for update;
    if not found then
      raise exception 'Driver not found' using errcode = 'P0002';
    end if;
    v_emp := coalesce(v_old.employee_id, v_emp);
  end if;
  if v_emp is not null and not exists (select 1 from public.employees where id = v_emp and org_id = v_org) then
    raise exception 'Choose an employee of your company' using errcode = '22023';
  end if;
  if v_emp is null and (char_length(coalesce(btrim(coalesce(p ->> 'name', v_old.name)), '')) < 2
                        or coalesce(nullif(p ->> 'phone', ''), v_old.phone) is null) then
    raise exception 'An outside driver needs a name and a phone number' using errcode = '22023';
  end if;
  if coalesce(nullif(p ->> 'licence_class', ''), v_old.licence_class) not in ('motorcycle', 'light', 'medium', 'heavy') then
    raise exception 'Choose the licence class' using errcode = '22023';
  end if;
  if coalesce(v_exp, v_old.licence_expiry) is null then
    raise exception 'Enter the licence expiry date' using errcode = '22023';
  end if;
  if coalesce(nullif(p ->> 'status', ''), 'active') not in ('active', 'off_duty', 'inactive') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  begin
    if p_id is null then
      insert into public.tms_drivers (org_id, employee_id, name, phone, nid, user_id, licence_no, licence_class, licence_kind, licence_expiry, status, notes)
      values (v_org, v_emp, case when v_emp is null then btrim(p ->> 'name') end, private.jtext(p, 'phone'),
              case when v_emp is null then private.jtext(p, 'nid') end,
              (select m.user_id from public.org_members m where m.employee_id = v_emp and m.status = 'active' limit 1),
              btrim(p ->> 'licence_no'), p ->> 'licence_class', coalesce(nullif(p ->> 'licence_kind', ''), 'professional'), v_exp,
              coalesce(nullif(p ->> 'status', ''), 'active'), private.jtext(p, 'notes'))
      returning id into v_id;
      return v_id;
    end if;
    update public.tms_drivers
       set name = case when employee_id is null and p ? 'name' then btrim(p ->> 'name') else name end,
           phone = case when p ? 'phone' then private.jtext(p, 'phone') else phone end,
           nid = case when employee_id is null and p ? 'nid' then private.jtext(p, 'nid') else nid end,
           user_id = coalesce((select m.user_id from public.org_members m
                               where m.employee_id = public.tms_drivers.employee_id and m.status = 'active' limit 1), user_id),
           licence_no = coalesce(nullif(btrim(p ->> 'licence_no'), ''), licence_no),
           licence_class = coalesce(nullif(p ->> 'licence_class', ''), licence_class),
           licence_kind = coalesce(nullif(p ->> 'licence_kind', ''), licence_kind),
           licence_expiry = coalesce(v_exp, licence_expiry),
           status = coalesce(nullif(p ->> 'status', ''), status),
           notes = case when p ? 'notes' then private.jtext(p, 'notes') else notes end
     where id = p_id;
    -- An inactive driver is no vehicle's default driver.
    if (p ->> 'status') = 'inactive' then
      update public.tms_vehicles set driver_id = null where driver_id = p_id;
    end if;
    return p_id;
  exception when unique_violation then
    raise exception 'This employee or licence number is already registered as a driver' using errcode = '23505';
  end;
end;
$$;

-- Links a DMS document (vehicle paper or licence copy) to a vehicle or a driver.
create or replace function public.tms_link_document(p_document_id uuid, p_vehicle_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  d     public.dms_documents := private.load_dms_document(p_document_id);
begin
  perform private.require_permission('tms.manage');
  if p_vehicle_id is not null and not exists (select 1 from public.tms_vehicles where id = p_vehicle_id and org_id = v_org) then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if p_driver_id is not null and not exists (select 1 from public.tms_drivers where id = p_driver_id and org_id = v_org) then
    raise exception 'Driver not found' using errcode = 'P0002';
  end if;
  update public.dms_documents set vehicle_id = p_vehicle_id, driver_id = p_driver_id where id = d.id;
end;
$$;

-- The driver view: my driver record (any login), or null.
create or replace function public.my_tms_driver()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.tms_driver_json(d) from public.tms_drivers d
  where d.org_id = private.current_org_id() and d.status <> 'inactive'
    and (d.user_id = auth.uid() or d.employee_id = private.current_employee_id())
  limit 1
$$;

-- Overview: fleet by status, papers and licences expiring within 60 days (expired included).
create or replace function public.get_tms_overview()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if not private.tms_can_see() then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  perform private.seed_tms_defaults(v_org);
  return jsonb_build_object(
    'vehicles', jsonb_build_object(
      'total', (select count(*) from public.tms_vehicles v where v.org_id = v_org and v.status <> 'disposed'),
      'active', (select count(*) from public.tms_vehicles v where v.org_id = v_org and v.status = 'active'),
      'in_maintenance', (select count(*) from public.tms_vehicles v where v.org_id = v_org and v.status = 'in_maintenance'),
      'off_road', (select count(*) from public.tms_vehicles v where v.org_id = v_org and v.status = 'off_road')),
    'drivers', jsonb_build_object(
      'active', (select count(*) from public.tms_drivers d where d.org_id = v_org and d.status = 'active'),
      'licence_expired', (select count(*) from public.tms_drivers d where d.org_id = v_org and d.status <> 'inactive' and d.licence_expiry < current_date)),
    'expiring', coalesce((
      select jsonb_agg(x order by x ->> 'expiry_date')
      from (
        select jsonb_build_object('kind', 'paper', 'what', t.name, 'doc_code', d.doc_code, 'document_id', d.id,
                                  'vehicle', (select v.reg_no from public.tms_vehicles v where v.id = d.vehicle_id),
                                  'driver', (select private.tms_driver_name(r) from public.tms_drivers r where r.id = d.driver_id),
                                  'expiry_date', d.expiry_date, 'days_left', d.expiry_date - current_date,
                                  'expiry_status', private.dms_expiry_status(d.expiry_date)) as x
        from public.dms_documents d join public.dms_doc_types t on t.id = d.doc_type_id
        where d.org_id = v_org and d.lifecycle = 'published' and (d.vehicle_id is not null or d.driver_id is not null)
          and d.expiry_date <= current_date + 60
        union all
        select jsonb_build_object('kind', 'licence', 'what', 'Driving licence ' || r.licence_no, 'driver', private.tms_driver_name(r),
                                  'driver_id', r.id, 'expiry_date', r.licence_expiry, 'days_left', r.licence_expiry - current_date,
                                  'expiry_status', private.dms_expiry_status(r.licence_expiry))
        from public.tms_drivers r
        where r.org_id = v_org and r.status <> 'inactive' and r.licence_expiry <= current_date + 60) s), '[]'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.tms_settings enable row level security;
alter table public.tms_drivers  enable row level security;
alter table public.tms_vehicles enable row level security;
revoke all on table public.tms_settings, public.tms_drivers, public.tms_vehicles from anon, authenticated;

revoke all on function
  public.get_tms_fleet(), public.get_tms_vehicle(uuid), public.save_tms_vehicle(uuid, jsonb), public.save_tms_driver(uuid, jsonb),
  public.tms_link_document(uuid, uuid, uuid), public.my_tms_driver(), public.get_tms_overview()
from public, anon;
grant execute on function
  public.get_tms_fleet(), public.get_tms_vehicle(uuid), public.save_tms_vehicle(uuid, jsonb), public.save_tms_driver(uuid, jsonb),
  public.tms_link_document(uuid, uuid, uuid), public.my_tms_driver(), public.get_tms_overview()
to authenticated;
revoke all on function
  private.seed_tms_defaults(uuid), private.tms_norm_reg(text), private.tms_class_needed(text), private.tms_class_ok(text, text),
  private.tms_can_see(), private.tms_driver_name(public.tms_drivers), private.tms_driver_json(public.tms_drivers),
  private.tms_papers(uuid, uuid), private.tms_vehicle_json(public.tms_vehicles, boolean)
from public, anon, authenticated;
