-- =============================================================================
-- Olympus HRIS — Part 1, Step 3: Organization structure
-- Grades, departments, designations, branches, offices, operations.
-- Hierarchy: Organization -> Branch -> Office. Departments are organization-wide.
-- =============================================================================

-- Attaches the standard triggers every business table gets.
create or replace function private.attach_standard_triggers(p_table regclass)
returns void
language plpgsql
set search_path = ''
as $$
begin
  execute format('create trigger set_row_meta before insert or update on %s
                  for each row execute function private.set_row_meta()', p_table);
  execute format('create trigger no_delete before delete on %s
                  for each row execute function private.prevent_delete()', p_table);
  execute format('create trigger audit after insert or update or delete on %s
                  for each row execute function private.audit_row_change()', p_table);
end;
$$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.grades (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null default private.current_org_id() references public.organizations (id),
  code        text not null check (code ~ '^[A-Z0-9]{2,12}$'),
  category    text not null check (category in ('EM', 'MS', 'OWNER')),
  level       smallint not null check (level between 0 and 99),   -- seniority: higher = more senior
  description text,
  status      text not null default 'active' check (status in ('active', 'inactive')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint grades_org_id_id_uq unique (org_id, id),
  constraint grades_org_code_uq unique (org_id, code)
);

create table public.departments (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null default private.current_org_id() references public.organizations (id),
  name             text not null check (char_length(btrim(name)) between 2 and 120),
  code             text check (code ~ '^[A-Za-z0-9-]{1,20}$'),
  description      text,
  head_employee_id uuid,        -- FK to employees added in Step 5
  status           text not null default 'active' check (status in ('active', 'inactive')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint departments_org_id_id_uq unique (org_id, id)
);
create unique index departments_org_name_uq on public.departments (org_id, lower(name));
create unique index departments_org_code_uq on public.departments (org_id, lower(code)) where code is not null;

create table public.designations (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null default private.current_org_id() references public.organizations (id),
  department_id uuid not null,
  grade_id      uuid not null,
  name          text not null check (char_length(btrim(name)) between 2 and 120),
  description   text,
  status        text not null default 'active' check (status in ('active', 'inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint designations_org_id_id_uq unique (org_id, id),
  -- Lets employees reference (org, department, designation) so the pair always matches.
  constraint designations_org_dept_id_uq unique (org_id, department_id, id),
  constraint designations_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint designations_grade_fk foreign key (org_id, grade_id) references public.grades (org_id, id)
);
create unique index designations_dept_name_uq on public.designations (department_id, lower(name));

create table public.branches (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null default private.current_org_id() references public.organizations (id),
  name             text not null check (char_length(btrim(name)) between 2 and 120),
  code             text check (code ~ '^[A-Za-z0-9-]{1,20}$'),
  address          text,
  phone            text check (phone ~ '^\+8801[3-9][0-9]{8}$'),
  head_employee_id uuid,        -- FK to employees added in Step 5
  status           text not null default 'active' check (status in ('active', 'inactive')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint branches_org_id_id_uq unique (org_id, id)
);
create unique index branches_org_name_uq on public.branches (org_id, lower(name));
create unique index branches_org_code_uq on public.branches (org_id, lower(code)) where code is not null;

create table public.offices (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null default private.current_org_id() references public.organizations (id),
  branch_id  uuid not null,
  name       text not null check (char_length(btrim(name)) between 2 and 120),
  code       text check (code ~ '^[A-Za-z0-9-]{1,20}$'),
  layout     text,
  address    text,
  status     text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  constraint offices_org_id_id_uq unique (org_id, id),
  constraint offices_org_branch_id_uq unique (org_id, branch_id, id),
  constraint offices_branch_fk foreign key (org_id, branch_id) references public.branches (org_id, id)
);
create unique index offices_branch_name_uq on public.offices (branch_id, lower(name));
create unique index offices_org_code_uq on public.offices (org_id, lower(code)) where code is not null;

create table public.operations (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null default private.current_org_id() references public.organizations (id),
  name        text not null check (char_length(btrim(name)) between 2 and 120),
  description text,
  status      text not null default 'active' check (status in ('active', 'inactive')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint operations_org_id_id_uq unique (org_id, id)
);
create unique index operations_org_name_uq on public.operations (org_id, lower(name));

-- Which operations run in which office (a link table: rows may be removed).
create table public.office_operations (
  org_id       uuid not null default private.current_org_id() references public.organizations (id),
  office_id    uuid not null,
  operation_id uuid not null,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id) default auth.uid(),
  primary key (office_id, operation_id),
  constraint office_operations_office_fk foreign key (org_id, office_id) references public.offices (org_id, id),
  constraint office_operations_operation_fk foreign key (org_id, operation_id) references public.operations (org_id, id)
);

-- -----------------------------------------------------------------------------
-- Integrity rules
-- -----------------------------------------------------------------------------
-- A designation stays in its department (employees reference the pair), and can
-- only be active under an active department and grade.
create or replace function private.designations_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.department_id is distinct from old.department_id then
    raise exception 'A designation cannot move to another department; create a new one instead'
      using errcode = '42501';
  end if;
  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active' or new.grade_id <> old.grade_id) then
    if not exists (select 1 from public.departments where id = new.department_id and status = 'active') then
      raise exception 'The department is inactive' using errcode = '23514';
    end if;
    if not exists (select 1 from public.grades where id = new.grade_id and status = 'active') then
      raise exception 'The grade is inactive' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- An office stays in its branch, and can only be active under an active branch.
create or replace function private.offices_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.branch_id is distinct from old.branch_id then
    raise exception 'An office cannot move to another branch; create a new one instead'
      using errcode = '42501';
  end if;
  if new.status = 'active' and (tg_op = 'INSERT' or old.status <> 'active') then
    if not exists (select 1 from public.branches where id = new.branch_id and status = 'active') then
      raise exception 'The branch is inactive' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

-- Grade codes are referenced by name on ID cards and history; keep them stable.
create or replace function private.grades_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.code is distinct from old.code or new.category is distinct from old.category then
    raise exception 'Grade code and category cannot change' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger designations_guard before insert or update on public.designations
  for each row execute function private.designations_guard();
create trigger offices_guard before insert or update on public.offices
  for each row execute function private.offices_guard();
create trigger grades_guard before update on public.grades
  for each row execute function private.grades_guard();

select private.attach_standard_triggers('public.grades');
select private.attach_standard_triggers('public.departments');
select private.attach_standard_triggers('public.designations');
select private.attach_standard_triggers('public.branches');
select private.attach_standard_triggers('public.offices');
select private.attach_standard_triggers('public.operations');
create trigger audit after insert or update or delete on public.office_operations
  for each row execute function private.audit_row_change();

-- Normalize phone input on branches.
create or replace function private.branches_normalize()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.phone := private.normalize_bd_phone(new.phone);
  return new;
end;
$$;
create trigger branches_normalize before insert or update of phone on public.branches
  for each row execute function private.branches_normalize();

-- -----------------------------------------------------------------------------
-- Default data for a new organization (later steps extend this function)
-- -----------------------------------------------------------------------------
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
end;
$$;

-- Existing organizations get the default grades now.
select private.seed_org_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Privileges and RLS: everyone in the organization can read the structure
-- (names are not sensitive); writing needs org.manage. Deactivation of
-- departments, designations, branches and offices goes through Step 8 functions.
-- -----------------------------------------------------------------------------
alter table public.grades            enable row level security;
alter table public.departments       enable row level security;
alter table public.designations      enable row level security;
alter table public.branches          enable row level security;
alter table public.offices           enable row level security;
alter table public.operations        enable row level security;
alter table public.office_operations enable row level security;

revoke all on table
  public.grades, public.departments, public.designations, public.branches,
  public.offices, public.operations, public.office_operations
from anon, authenticated;

grant select on table
  public.grades, public.departments, public.designations, public.branches,
  public.offices, public.operations, public.office_operations
to authenticated;

grant insert (code, category, level, description, status),
      update (level, description, status)                                   on public.grades       to authenticated;
grant insert (name, code, description, head_employee_id, status),
      update (name, code, description, head_employee_id, status)           on public.departments  to authenticated;
grant insert (department_id, grade_id, name, description, status),
      update (grade_id, name, description, status)                         on public.designations to authenticated;
grant insert (name, code, address, phone, head_employee_id, status),
      update (name, code, address, phone, head_employee_id, status)        on public.branches     to authenticated;
grant insert (branch_id, name, code, layout, address, status),
      update (name, code, layout, address, status)                         on public.offices      to authenticated;
grant insert (name, description, status),
      update (name, description, status)                                   on public.operations   to authenticated;
grant insert (office_id, operation_id), delete                             on public.office_operations to authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['grades', 'departments', 'designations', 'branches', 'offices', 'operations'] loop
    execute format($f$
      create policy %1$s_select on public.%1$s for select to authenticated
        using (org_id = (select private.current_org_id()));
      create policy %1$s_insert on public.%1$s for insert to authenticated
        with check (org_id = (select private.current_org_id()) and (select private.has_permission('org.manage')));
      create policy %1$s_update on public.%1$s for update to authenticated
        using (org_id = (select private.current_org_id()) and (select private.has_permission('org.manage')))
        with check (org_id = (select private.current_org_id()));
    $f$, t);
  end loop;
end $$;

create policy office_operations_select on public.office_operations for select to authenticated
  using (org_id = (select private.current_org_id()));
create policy office_operations_insert on public.office_operations for insert to authenticated
  with check (org_id = (select private.current_org_id()) and (select private.has_permission('org.manage')));
create policy office_operations_delete on public.office_operations for delete to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('org.manage')));

-- Branch phone normalization runs inside a trigger with the caller's rights.
grant execute on function private.normalize_bd_phone(text) to authenticated;

-- Internal helpers stay closed to API roles.
revoke all on function private.attach_standard_triggers(regclass), private.seed_org_defaults(uuid)
  from public, anon, authenticated;
