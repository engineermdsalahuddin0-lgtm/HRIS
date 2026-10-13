-- =============================================================================
-- Olympus HRIS — Part 1, Step 5: Employees
-- Employees, sensitive data, nominees, history and reporting tables, card IDs,
-- per-field masking (employees_v), create/edit RPCs.
--
-- The base tables are NOT readable or writable by API roles. Reads go through
-- the employees_v view (row filter + per-field masking); writes go through
-- RPCs that check permissions and per-field edit rights.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.employees (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  user_id            uuid references public.user_profiles (id),
  card_id            text not null check (card_id ~ '^[A-Za-z0-9-]{6,15}$'),
  full_name          text not null check (char_length(btrim(full_name)) between 2 and 150),
  phone              text check (phone ~ '^\+8801[3-9][0-9]{8}$'),
  email              text check (email = lower(email) and email ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$'),
  date_of_birth      date check (date_of_birth > date '1900-01-01'),
  gender             text check (gender in ('male', 'female', 'other')),
  marital_status     text check (marital_status in ('single', 'married', 'divorced', 'widowed')),
  religion           text check (religion in ('islam', 'hinduism', 'buddhism', 'christianity', 'other')),
  blood_group        text check (blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  join_date          date not null,
  employment_type    text not null check (employment_type in ('permanent', 'contract', 'probation', 'intern', 'part_time')),
  status             text not null default 'active' check (status in ('active', 'inactive', 'terminated')),
  exit_date          date,
  department_id      uuid,
  designation_id     uuid,
  branch_id          uuid,
  office_id          uuid,
  operation_id       uuid,
  present_address    text,
  permanent_address  text,
  probation_end_date date,
  confirmation_date  date,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint employees_org_id_id_uq unique (org_id, id),
  constraint employees_designation_needs_department check (designation_id is null or department_id is not null),
  constraint employees_office_needs_branch check (office_id is null or branch_id is not null),
  constraint employees_exit_after_join check (exit_date is null or exit_date >= join_date),
  -- Composite keys: every link stays inside the organization, the designation
  -- belongs to the department, and the office belongs to the branch.
  constraint employees_department_fk  foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint employees_designation_fk foreign key (org_id, department_id, designation_id)
    references public.designations (org_id, department_id, id),
  constraint employees_branch_fk      foreign key (org_id, branch_id) references public.branches (org_id, id),
  constraint employees_office_fk      foreign key (org_id, branch_id, office_id) references public.offices (org_id, branch_id, id),
  constraint employees_operation_fk   foreign key (org_id, operation_id) references public.operations (org_id, id)
);

-- Card ID: unique inside one organization; the same value may exist in another.
create unique index employees_org_card_uq on public.employees (org_id, upper(card_id));
create index employees_org_status_idx on public.employees (org_id, status);
create index employees_department_idx on public.employees (department_id);
create index employees_branch_idx on public.employees (branch_id);
create index employees_office_idx on public.employees (office_id);
create index employees_user_idx on public.employees (user_id);

-- Sensitive data lives in its own table (NID now; salary and bank later).
create table public.employee_sensitive (
  employee_id uuid primary key,
  org_id      uuid not null,
  nid_number  text check (nid_number ~ '^([0-9]{10}|[0-9]{13}|[0-9]{17})$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint employee_sensitive_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);
create unique index employee_sensitive_org_nid_uq on public.employee_sensitive (org_id, nid_number) where nid_number is not null;

create table public.employee_nominees (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  employee_id uuid not null,
  name        text not null check (char_length(btrim(name)) between 2 and 150),
  phone       text check (phone ~ '^\+8801[3-9][0-9]{8}$'),
  relation    text not null check (char_length(btrim(relation)) between 2 and 50),
  status      text not null default 'active' check (status in ('active', 'inactive')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint employee_nominees_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);
create index employee_nominees_employee_idx on public.employee_nominees (employee_id, status);

-- HR record of where the employee was and is now. Append-only.
create table public.employment_history (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  employee_id    uuid not null,
  event_type     text not null check (event_type in (
                   'joined', 'transfer', 'promotion', 'demotion', 'designation', 'department',
                   'branch', 'office', 'operation', 'employment_type', 'status')),
  from_value     jsonb,
  to_value       jsonb,
  effective_date date not null,
  reason         text,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id) default auth.uid(),
  constraint employment_history_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);
create index employment_history_employee_idx on public.employment_history (employee_id, effective_date desc, created_at desc);

-- Reporting chain. end_date null = current. Changing a manager closes the old
-- row and opens a new one, so history is kept.
create table public.reporting_lines (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null,
  employee_id         uuid not null,
  manager_employee_id uuid not null,
  line_type           text not null check (line_type in ('reporting_manager', 'supervisor', 'it_manager', 'finance_manager')),
  start_date          date not null,
  end_date            date,
  reason              text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id),
  updated_by          uuid references public.user_profiles (id),
  constraint reporting_lines_not_self check (employee_id <> manager_employee_id),
  constraint reporting_lines_dates check (end_date is null or end_date >= start_date),
  constraint reporting_lines_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint reporting_lines_manager_fk  foreign key (org_id, manager_employee_id) references public.employees (org_id, id)
);
create unique index reporting_lines_one_current_uq on public.reporting_lines (employee_id, line_type) where end_date is null;
create index reporting_lines_manager_idx on public.reporting_lines (manager_employee_id) where end_date is null;

-- Link logins to their employment; department/branch heads to employees.
alter table public.org_members add column employee_id uuid;
alter table public.org_members
  add constraint org_members_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id);
create unique index org_members_employee_active_uq on public.org_members (employee_id)
  where status = 'active' and employee_id is not null;

alter table public.departments
  add constraint departments_head_fk foreign key (org_id, head_employee_id) references public.employees (org_id, id);
alter table public.branches
  add constraint branches_head_fk foreign key (org_id, head_employee_id) references public.employees (org_id, id);

-- -----------------------------------------------------------------------------
-- Integrity triggers
-- -----------------------------------------------------------------------------
-- New placements (create, transfer, reactivation) must use active units; an
-- operation must run in the chosen office.
create or replace function private.employees_placement_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_check boolean := new.status = 'active' and (
    tg_op = 'INSERT'
    or old.status <> 'active'
    or new.department_id  is distinct from old.department_id
    or new.designation_id is distinct from old.designation_id
    or new.branch_id      is distinct from old.branch_id
    or new.office_id      is distinct from old.office_id
    or new.operation_id   is distinct from old.operation_id);
begin
  new.phone := private.normalize_bd_phone(new.phone);
  new.email := lower(nullif(btrim(new.email), ''));
  if tg_op = 'UPDATE' and (new.card_id is distinct from old.card_id or new.org_id is distinct from old.org_id) then
    raise exception 'Card ID and organization of an employment never change' using errcode = '42501';
  end if;
  if not v_check then
    return new;
  end if;
  if new.department_id is not null
     and not exists (select 1 from public.departments where id = new.department_id and status = 'active') then
    raise exception 'The department is inactive and cannot receive employees' using errcode = '23514';
  end if;
  if new.designation_id is not null
     and not exists (select 1 from public.designations where id = new.designation_id and status = 'active') then
    raise exception 'The designation is inactive and cannot receive employees' using errcode = '23514';
  end if;
  if new.branch_id is not null
     and not exists (select 1 from public.branches where id = new.branch_id and status = 'active') then
    raise exception 'The branch is inactive and cannot receive employees' using errcode = '23514';
  end if;
  if new.office_id is not null
     and not exists (select 1 from public.offices where id = new.office_id and status = 'active') then
    raise exception 'The office is inactive and cannot receive employees' using errcode = '23514';
  end if;
  if new.operation_id is not null then
    if not exists (select 1 from public.operations where id = new.operation_id and status = 'active') then
      raise exception 'The operation is inactive' using errcode = '23514';
    end if;
    if new.office_id is not null and not exists (
      select 1 from public.office_operations where office_id = new.office_id and operation_id = new.operation_id) then
      raise exception 'This operation does not run in the chosen office' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

create trigger employees_placement_guard before insert or update on public.employees
  for each row execute function private.employees_placement_guard();

create or replace function private.employment_history_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Employment history is append-only' using errcode = '42501';
end;
$$;
create trigger employment_history_append_only before update or delete on public.employment_history
  for each row execute function private.employment_history_guard();

-- Reporting lines: only end_date (and reason) may be set, once.
create or replace function private.reporting_lines_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.employee_id <> old.employee_id or new.manager_employee_id <> old.manager_employee_id
     or new.line_type <> old.line_type or new.start_date <> old.start_date
     or (old.end_date is not null and new.end_date is distinct from old.end_date) then
    raise exception 'A reporting line can only be closed, not changed' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger reporting_lines_guard before update on public.reporting_lines
  for each row execute function private.reporting_lines_guard();

create or replace function private.nominees_normalize()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.phone := private.normalize_bd_phone(new.phone);
  return new;
end;
$$;
create trigger nominees_normalize before insert or update on public.employee_nominees
  for each row execute function private.nominees_normalize();

select private.attach_standard_triggers('public.employees');
select private.attach_standard_triggers('public.employee_sensitive');
select private.attach_standard_triggers('public.employee_nominees');
select private.attach_standard_triggers('public.reporting_lines');
create trigger audit after insert on public.employment_history
  for each row execute function private.audit_row_change();

-- Never put the NID itself into the audit log.
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ignore text[] := array['updated_at', 'updated_by', 'last_login_at'];
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
-- Access helpers
-- -----------------------------------------------------------------------------
create or replace function private.current_employee_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.employee_id
  from public.org_members m
  where m.user_id = auth.uid() and m.status = 'active'
    and m.org_id = private.current_org_id()
$$;

-- Everything the caller may see, computed once per query (used by employees_v).
create or replace function private.viewer()
returns table (org_id uuid, employee_id uuid, see_all boolean, can_list boolean, fields text[])
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.current_org_id(),
    private.current_employee_id(),
    private.is_org_admin(),
    private.has_permission('employees.view'),
    coalesce((select array_agg(rfa.resource || '.' || rfa.field_key)
              from public.role_field_access rfa
              where rfa.role_id = private.current_role_id() and rfa.can_view), '{}')
$$;

-- Fields the caller may edit on one employee ('resource.field' keys).
create or replace function private.editable_fields(p_employee_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when private.is_org_admin() then
      (select array_agg(resource || '.' || field_key) from public.field_catalog)
    when p_employee_id = private.current_employee_id() or private.has_permission('employees.edit') then
      coalesce((select array_agg(rfa.resource || '.' || rfa.field_key)
                from public.role_field_access rfa
                where rfa.role_id = private.current_role_id() and rfa.can_edit), '{}')
    else '{}'::text[]
  end
$$;

create or replace function private.require_permission(p_key text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.has_permission(p_key) then
    raise exception 'You do not have permission for this action (%)', p_key using errcode = '42501';
  end if;
end;
$$;

-- Empty strings from forms become null.
create or replace function private.jtext(p jsonb, k text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(p ->> k), '')
$$;

-- -----------------------------------------------------------------------------
-- Card ID generation. Auto: 2-digit joining year + random digits, total length
-- set by the organization (8-10). Caller must hold the org card lock.
-- -----------------------------------------------------------------------------
create or replace function private.lock_card_ids(p_org_id uuid)
returns void
language sql
set search_path = ''
as $$
  select pg_advisory_xact_lock(hashtextextended('olympus.card_id:' || p_org_id::text, 0))
$$;

create or replace function private.generate_card_id(p_org_id uuid, p_join_date date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_len     int;
  v_card    text;
  v_attempt int := 0;
begin
  select card_id_length into v_len from public.organizations where id = p_org_id;
  loop
    v_attempt := v_attempt + 1;
    v_card := to_char(p_join_date, 'YY')
              || lpad(floor(random() * power(10, v_len - 2))::bigint::text, v_len - 2, '0');
    exit when not exists (select 1 from public.employees where org_id = p_org_id and upper(card_id) = v_card);
    if v_attempt >= 100 then
      raise exception 'Could not generate a unique card ID; increase the card ID length' using errcode = '23505';
    end if;
  end loop;
  return v_card;
end;
$$;

-- Snapshot of an employee's placement, with names, for history rows.
create or replace function private.placement_snapshot(p_employee_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'department_id', e.department_id, 'department', d.name,
    'designation_id', e.designation_id, 'designation', ds.name,
    'grade', g.code, 'grade_level', g.level,
    'branch_id', e.branch_id, 'branch', b.name,
    'office_id', e.office_id, 'office', o.name,
    'operation_id', e.operation_id, 'operation', op.name,
    'employment_type', e.employment_type, 'status', e.status))
  from public.employees e
  left join public.departments d on d.id = e.department_id
  left join public.designations ds on ds.id = e.designation_id
  left join public.grades g on g.id = ds.grade_id
  left join public.branches b on b.id = e.branch_id
  left join public.offices o on o.id = e.office_id
  left join public.operations op on op.id = e.operation_id
  where e.id = p_employee_id
$$;

-- Reporting-manager cycles (A -> B -> A) are rejected.
create or replace function private.assert_no_reporting_cycle(p_employee_id uuid, p_manager_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    with recursive chain(id, depth) as (
      select p_manager_id, 1
      union all
      select rl.manager_employee_id, c.depth + 1
      from chain c
      join public.reporting_lines rl
        on rl.employee_id = c.id and rl.line_type = 'reporting_manager' and rl.end_date is null
      where c.depth < 50
    )
    select 1 from chain where id = p_employee_id
  ) then
    raise exception 'This would create a reporting loop' using errcode = '23514';
  end if;
end;
$$;

-- Opens a reporting line (closing the current one of that type).
create or replace function private.set_reporting_line_internal(
  p_employee_id uuid, p_line_type text, p_manager_id uuid, p_effective date, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select org_id into v_org from public.employees where id = p_employee_id;
  update public.reporting_lines
     set end_date = greatest(p_effective, start_date), reason = coalesce(p_reason, reason)
   where employee_id = p_employee_id and line_type = p_line_type and end_date is null;

  if p_manager_id is not null then
    if not exists (select 1 from public.employees where id = p_manager_id and org_id = v_org and status = 'active') then
      raise exception 'The manager must be an active employee of this organization' using errcode = '23514';
    end if;
    if p_line_type = 'reporting_manager' then
      perform private.assert_no_reporting_cycle(p_employee_id, p_manager_id);
    end if;
    insert into public.reporting_lines (org_id, employee_id, manager_employee_id, line_type, start_date, reason)
    values (v_org, p_employee_id, p_manager_id, p_line_type, p_effective, p_reason);
  end if;
end;
$$;

-- Replaces an employee's active nominees with the given list.
create or replace function private.save_nominees_internal(p_employee_id uuid, p_nominees jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
begin
  select org_id into v_org from public.employees where id = p_employee_id;
  update public.employee_nominees set status = 'inactive'
   where employee_id = p_employee_id and status = 'active';
  insert into public.employee_nominees (org_id, employee_id, name, phone, relation)
  select v_org, p_employee_id, btrim(n.name), nullif(btrim(n.phone), ''), btrim(n.relation)
  from jsonb_to_recordset(coalesce(p_nominees, '[]'::jsonb)) as n(name text, phone text, relation text)
  where nullif(btrim(n.name), '') is not null;
end;
$$;

-- Creates the employee row for a login that has none (organization owner).
create or replace function private.ensure_member_employee(p_member_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_m   public.org_members;
  v_u   public.user_profiles;
  v_id  uuid;
begin
  select * into v_m from public.org_members where id = p_member_id;
  if v_m.employee_id is not null then
    return v_m.employee_id;
  end if;
  select * into v_u from public.user_profiles where id = v_m.user_id;
  perform private.lock_card_ids(v_m.org_id);
  insert into public.employees (org_id, user_id, card_id, full_name, phone, email, join_date, employment_type)
  values (v_m.org_id, v_m.user_id, private.generate_card_id(v_m.org_id, current_date),
          coalesce(nullif(btrim(v_u.full_name), ''), 'Organization Owner'), v_u.phone, v_u.email,
          current_date, 'permanent')
  returning id into v_id;
  update public.org_members set employee_id = v_id where id = p_member_id;
  insert into public.employment_history (org_id, employee_id, event_type, to_value, effective_date, reason)
  values (v_m.org_id, v_id, 'joined', private.placement_snapshot(v_id), current_date, 'Organization created');
  return v_id;
end;
$$;

-- Organization creation now also seeds grades/field access and gives the
-- owner an employee row.
create or replace function private.create_organization(
  p_name          text,
  p_timezone      text,
  p_owner_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id    uuid;
  v_attempt   int := 0;
  v_admin_id  uuid;
  v_hr_id     uuid;
  v_mgr_id    uuid;
  v_member_id uuid;
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown timezone %', p_timezone using errcode = '22023';
  end if;
  if exists (select 1 from public.org_members where user_id = p_owner_user_id and status = 'active') then
    raise exception 'This user already belongs to an organization' using errcode = '23505';
  end if;

  loop
    v_attempt := v_attempt + 1;
    insert into public.organizations (org_code, name, timezone)
    values ((100000 + floor(random() * 900000))::int::text, btrim(p_name), p_timezone)
    on conflict (org_code) do nothing
    returning id into v_org_id;
    exit when v_org_id is not null;
    if v_attempt >= 25 then
      raise exception 'Could not generate a unique organization code' using errcode = '23505';
    end if;
  end loop;

  insert into public.roles (org_id, name, description, system_key)
  values (v_org_id, 'Admin', 'Full access inside this organization', 'admin') returning id into v_admin_id;
  insert into public.roles (org_id, name, description, system_key)
  values (v_org_id, 'HR Manager', 'Manages employees and organization structure', 'hr_manager') returning id into v_hr_id;
  insert into public.roles (org_id, name, description, system_key)
  values (v_org_id, 'Manager', 'Sees the people list within allowed fields', 'manager') returning id into v_mgr_id;
  insert into public.roles (org_id, name, description, system_key)
  values (v_org_id, 'Employee', 'Sees and edits only their own profile', 'employee');

  insert into public.role_permissions (org_id, role_id, permission_key)
  select v_org_id, v_hr_id, k
  from unnest(array[
    'org.view', 'org.manage',
    'employees.view', 'employees.create', 'employees.edit', 'employees.deactivate',
    'employees.transfer', 'employees.reporting', 'employees.portal_access',
    'users.reset_password', 'roles.view'
  ]) as k;
  insert into public.role_permissions (org_id, role_id, permission_key)
  select v_org_id, v_mgr_id, k from unnest(array['org.view', 'employees.view']) as k;

  perform private.seed_org_defaults(v_org_id);

  insert into public.org_members (org_id, user_id, role_id)
  values (v_org_id, p_owner_user_id, v_admin_id)
  returning id into v_member_id;
  perform private.ensure_member_employee(v_member_id);

  perform private.write_audit(v_org_id, 'organization.created', 'organizations', v_org_id, null,
                              jsonb_build_object('owner_user_id', p_owner_user_id));
  return v_org_id;
end;
$$;

-- Approval sets the applicant's name first so the owner's employee row gets it.
create or replace function public.approve_org_signup_request(p_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_req    public.org_signup_requests;
  v_org_id uuid;
begin
  if not private.is_platform_admin() then
    raise exception 'Only a platform admin can approve sign-ups' using errcode = '42501';
  end if;
  select * into v_req from public.org_signup_requests where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    raise exception 'No pending request found' using errcode = 'P0002';
  end if;

  update public.user_profiles set full_name = v_req.contact_name
   where id = v_req.applicant_user_id and full_name = '';

  v_org_id := private.create_organization(v_req.org_name, v_req.timezone, v_req.applicant_user_id);

  update public.org_signup_requests
     set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), organization_id = v_org_id
   where id = p_request_id;
  return v_org_id;
end;
$$;

-- Existing members (organization owners from Step 1) get their employee row.
select private.ensure_member_employee(id) from public.org_members where status = 'active' and employee_id is null;

-- -----------------------------------------------------------------------------
-- employees_v: the only way to read employees. Row filter = own record, or the
-- whole organization with employees.view. Each optional field is shown only if
-- the role ticked it (Admin and the employee themselves see everything).
-- Runs with the owner's rights on purpose (security definer view).
-- -----------------------------------------------------------------------------
create view public.employees_v with (security_barrier = true) as
select
  e.id, e.org_id, e.card_id, e.full_name, e.status, e.exit_date,
  e.department_id, d.name as department_name,
  e.designation_id, ds.name as designation_name,
  g.id as grade_id, g.code as grade_code, g.category as grade_category, g.level as grade_level,
  e.branch_id, b.name as branch_name,
  e.office_id, o.name as office_name,
  e.operation_id, op.name as operation_name,
  e.user_id,
  (m.id is not null) as has_portal_access,
  m.role_id as portal_role_id, r.name as portal_role_name, r.system_key as portal_role_key,
  (e.id = v.employee_id) as is_self,
  case when v.see_all or e.id = v.employee_id or 'employees.phone'              = any (v.fields) then e.phone end as phone,
  case when v.see_all or e.id = v.employee_id or 'employees.email'              = any (v.fields) then e.email end as email,
  case when v.see_all or e.id = v.employee_id or 'employees.date_of_birth'      = any (v.fields) then e.date_of_birth end as date_of_birth,
  case when v.see_all or e.id = v.employee_id or 'employees.gender'             = any (v.fields) then e.gender end as gender,
  case when v.see_all or e.id = v.employee_id or 'employees.marital_status'     = any (v.fields) then e.marital_status end as marital_status,
  case when v.see_all or e.id = v.employee_id or 'employees.religion'           = any (v.fields) then e.religion end as religion,
  case when v.see_all or e.id = v.employee_id or 'employees.blood_group'        = any (v.fields) then e.blood_group end as blood_group,
  case when v.see_all or e.id = v.employee_id or 'employees.join_date'          = any (v.fields) then e.join_date end as join_date,
  case when v.see_all or e.id = v.employee_id or 'employees.employment_type'    = any (v.fields) then e.employment_type end as employment_type,
  case when v.see_all or e.id = v.employee_id or 'employees.present_address'    = any (v.fields) then e.present_address end as present_address,
  case when v.see_all or e.id = v.employee_id or 'employees.permanent_address'  = any (v.fields) then e.permanent_address end as permanent_address,
  case when v.see_all or e.id = v.employee_id or 'employees.probation_end_date' = any (v.fields) then e.probation_end_date end as probation_end_date,
  case when v.see_all or e.id = v.employee_id or 'employees.confirmation_date'  = any (v.fields) then e.confirmation_date end as confirmation_date,
  case when v.see_all or e.id = v.employee_id or 'employee_sensitive.nid_number' = any (v.fields) then s.nid_number end as nid_number,
  e.created_at, e.updated_at
from private.viewer() v
join public.employees e on e.org_id = v.org_id
left join public.employee_sensitive s on s.employee_id = e.id
left join public.departments d on d.id = e.department_id
left join public.designations ds on ds.id = e.designation_id
left join public.grades g on g.id = ds.grade_id
left join public.branches b on b.id = e.branch_id
left join public.offices o on o.id = e.office_id
left join public.operations op on op.id = e.operation_id
left join public.org_members m on m.employee_id = e.id and m.status = 'active'
left join public.roles r on r.id = m.role_id
where e.id = v.employee_id or v.can_list;

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------
-- p: { full_name, phone, email, date_of_birth, gender, marital_status, religion,
--      blood_group, nid_number, present_address, permanent_address,
--      join_date, employment_type, probation_end_date, confirmation_date,
--      department_id, designation_id, branch_id, office_id, operation_id,
--      card_id (custom policy only),
--      nominees: [{name, phone, relation}],
--      reporting: [{line_type, manager_employee_id}] }
create or replace function public.create_employee(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   public.organizations;
  v_id    uuid;
  v_card  text;
  v_join  date := (private.jtext(p, 'join_date'))::date;
  v_line  record;
begin
  perform private.require_permission('employees.create');
  select * into v_org from public.organizations where id = private.current_org_id();

  if private.jtext(p, 'full_name') is null then
    raise exception 'Full name is required (as per NID)' using errcode = '23502';
  end if;
  if v_join is null then
    raise exception 'Join date is required' using errcode = '23502';
  end if;
  if private.jtext(p, 'department_id') is null or private.jtext(p, 'designation_id') is null
     or private.jtext(p, 'branch_id') is null or private.jtext(p, 'office_id') is null then
    raise exception 'Department, designation, branch and office are required' using errcode = '23502';
  end if;

  perform private.lock_card_ids(v_org.id);
  if v_org.card_id_mode = 'custom' then
    v_card := upper(private.jtext(p, 'card_id'));
    if v_card is null or v_card !~ '^[A-Z0-9-]{6,15}$' then
      raise exception 'Card ID must be 6-15 letters, numbers or hyphens' using errcode = '22023';
    end if;
    if exists (select 1 from public.employees where org_id = v_org.id and upper(card_id) = v_card) then
      raise exception 'Card ID % is already used in this organization', v_card using errcode = '23505';
    end if;
  else
    v_card := private.generate_card_id(v_org.id, v_join);
  end if;

  insert into public.employees (
    org_id, card_id, full_name, phone, email, date_of_birth, gender, marital_status, religion, blood_group,
    join_date, employment_type, department_id, designation_id, branch_id, office_id, operation_id,
    present_address, permanent_address, probation_end_date, confirmation_date)
  values (
    v_org.id, v_card, btrim(p ->> 'full_name'), private.jtext(p, 'phone'), private.jtext(p, 'email'),
    private.jtext(p, 'date_of_birth')::date, private.jtext(p, 'gender'), private.jtext(p, 'marital_status'),
    private.jtext(p, 'religion'), private.jtext(p, 'blood_group'),
    v_join, coalesce(private.jtext(p, 'employment_type'), 'permanent'),
    private.jtext(p, 'department_id')::uuid, private.jtext(p, 'designation_id')::uuid,
    private.jtext(p, 'branch_id')::uuid, private.jtext(p, 'office_id')::uuid, private.jtext(p, 'operation_id')::uuid,
    private.jtext(p, 'present_address'), private.jtext(p, 'permanent_address'),
    private.jtext(p, 'probation_end_date')::date, private.jtext(p, 'confirmation_date')::date)
  returning id into v_id;

  if private.jtext(p, 'nid_number') is not null then
    insert into public.employee_sensitive (employee_id, org_id, nid_number)
    values (v_id, v_org.id, private.jtext(p, 'nid_number'));
  end if;

  perform private.save_nominees_internal(v_id, p -> 'nominees');

  insert into public.employment_history (org_id, employee_id, event_type, to_value, effective_date, reason)
  values (v_org.id, v_id, 'joined', private.placement_snapshot(v_id), v_join, 'Employee added');

  for v_line in
    select r.line_type, nullif(r.manager_employee_id, '')::uuid as manager_id
    from jsonb_to_recordset(coalesce(p -> 'reporting', '[]'::jsonb)) as r(line_type text, manager_employee_id text)
  loop
    if v_line.manager_id is not null then
      perform private.set_reporting_line_internal(v_id, v_line.line_type, v_line.manager_id, v_join, null);
    end if;
  end loop;

  perform private.write_audit(v_org.id, 'employee.created', 'employees', v_id, null,
                              jsonb_build_object('card_id', v_card, 'full_name', btrim(p ->> 'full_name')));
  return v_id;
end;
$$;

-- Edits personal and contract fields. Each key in p must be editable by the
-- caller's role (or self-edit). Placement changes go through transfer_employee.
create or replace function public.update_employee(p_employee_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allowed text[];
  v_key     text;
  v_old     public.employees;
  v_res     text;
  v_cols    constant text[] := array[
    'full_name', 'phone', 'email', 'date_of_birth', 'gender', 'marital_status', 'religion', 'blood_group',
    'join_date', 'employment_type', 'present_address', 'permanent_address', 'probation_end_date',
    'confirmation_date', 'nid_number', 'nominees'];
begin
  select * into v_old from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;

  v_allowed := private.editable_fields(p_employee_id);
  for v_key in select jsonb_object_keys(p) loop
    if v_key <> all (v_cols) then
      raise exception 'Unknown or read-only field: %', v_key using errcode = '22023';
    end if;
    v_res := case when v_key = 'nid_number' then 'employee_sensitive.' else 'employees.' end || v_key;
    if v_res <> all (v_allowed) then
      raise exception 'You are not allowed to edit %', replace(v_key, '_', ' ') using errcode = '42501';
    end if;
  end loop;

  if p ? 'full_name' and private.jtext(p, 'full_name') is null then
    raise exception 'Full name is required (as per NID)' using errcode = '23502';
  end if;

  update public.employees set
    full_name          = case when p ? 'full_name'          then btrim(p ->> 'full_name') else full_name end,
    phone              = case when p ? 'phone'              then private.jtext(p, 'phone') else phone end,
    email              = case when p ? 'email'              then private.jtext(p, 'email') else email end,
    date_of_birth      = case when p ? 'date_of_birth'      then private.jtext(p, 'date_of_birth')::date else date_of_birth end,
    gender             = case when p ? 'gender'             then private.jtext(p, 'gender') else gender end,
    marital_status     = case when p ? 'marital_status'     then private.jtext(p, 'marital_status') else marital_status end,
    religion           = case when p ? 'religion'           then private.jtext(p, 'religion') else religion end,
    blood_group        = case when p ? 'blood_group'        then private.jtext(p, 'blood_group') else blood_group end,
    join_date          = case when p ? 'join_date'          then coalesce(private.jtext(p, 'join_date')::date, join_date) else join_date end,
    employment_type    = case when p ? 'employment_type'    then coalesce(private.jtext(p, 'employment_type'), employment_type) else employment_type end,
    present_address    = case when p ? 'present_address'    then private.jtext(p, 'present_address') else present_address end,
    permanent_address  = case when p ? 'permanent_address'  then private.jtext(p, 'permanent_address') else permanent_address end,
    probation_end_date = case when p ? 'probation_end_date' then private.jtext(p, 'probation_end_date')::date else probation_end_date end,
    confirmation_date  = case when p ? 'confirmation_date'  then private.jtext(p, 'confirmation_date')::date else confirmation_date end
  where id = p_employee_id;

  if p ? 'employment_type' and private.jtext(p, 'employment_type') is distinct from v_old.employment_type then
    insert into public.employment_history (org_id, employee_id, event_type, from_value, to_value, effective_date)
    values (v_old.org_id, p_employee_id, 'employment_type',
            jsonb_build_object('employment_type', v_old.employment_type),
            jsonb_build_object('employment_type', private.jtext(p, 'employment_type')), current_date);
  end if;

  if p ? 'nid_number' then
    insert into public.employee_sensitive (employee_id, org_id, nid_number)
    values (p_employee_id, v_old.org_id, private.jtext(p, 'nid_number'))
    on conflict (employee_id) do update set nid_number = excluded.nid_number;
  end if;

  if p ? 'nominees' then
    perform private.save_nominees_internal(p_employee_id, p -> 'nominees');
  end if;
end;
$$;

-- People-list KPI tiles.
create or replace function public.get_employee_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('employees.view');
  return jsonb_build_object(
    'total',         (select count(*) from public.employees where org_id = v_org),
    'active',        (select count(*) from public.employees where org_id = v_org and status = 'active'),
    'inactive',      (select count(*) from public.employees where org_id = v_org and status <> 'active'),
    'portal_access', (select count(*) from public.org_members where org_id = v_org and status = 'active' and employee_id is not null),
    'departments',   (select count(*) from public.departments where org_id = v_org and status = 'active'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges: base tables closed to API roles; RLS on as a second wall.
-- -----------------------------------------------------------------------------
alter table public.employees          enable row level security;
alter table public.employee_sensitive enable row level security;
alter table public.employee_nominees  enable row level security;
alter table public.employment_history enable row level security;
alter table public.reporting_lines    enable row level security;

revoke all on table
  public.employees, public.employee_sensitive, public.employee_nominees,
  public.employment_history, public.reporting_lines
from anon, authenticated;

revoke all on table public.employees_v from anon, authenticated;
grant select on table public.employees_v to authenticated;

revoke all on function
  public.create_employee(jsonb), public.update_employee(uuid, jsonb), public.get_employee_stats()
from public, anon;
grant execute on function
  public.create_employee(jsonb), public.update_employee(uuid, jsonb), public.get_employee_stats()
to authenticated;

revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function
  private.active_membership(), private.current_org_id(), private.current_role_id(),
  private.is_org_admin(), private.has_permission(text), private.is_platform_admin(),
  private.current_employee_id(), private.viewer(), private.normalize_bd_phone(text)
to authenticated;
