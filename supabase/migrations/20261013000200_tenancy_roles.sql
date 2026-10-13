-- =============================================================================
-- Olympus HRIS — Part 1, Step 1: Tenancy, identity, roles and permissions
-- =============================================================================

-- -----------------------------------------------------------------------------
-- user_profiles: one row per login identity (mirrors auth.users)
-- -----------------------------------------------------------------------------
create table public.user_profiles (
  id                   uuid primary key references auth.users (id) on delete restrict,
  email                text,
  phone                text check (phone ~ '^\+8801[3-9][0-9]{8}$'),
  full_name            text not null default '',
  status               text not null default 'active' check (status in ('active', 'disabled')),
  must_change_password boolean not null default false,
  last_login_at        timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint user_profiles_email_or_phone check (email is not null or phone is not null),
  constraint user_profiles_email_lower check (email = lower(email))
);

create unique index user_profiles_email_uq on public.user_profiles (email) where email is not null;
create unique index user_profiles_phone_uq on public.user_profiles (phone) where phone is not null;

-- Platform operators (approve organization sign-ups). Outside every tenant.
-- Seed manually:  insert into public.platform_admins (user_id) values ('<auth user id>');
create table public.platform_admins (
  user_id    uuid primary key references public.user_profiles (id),
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- organizations: one row per company (the tenant)
-- -----------------------------------------------------------------------------
create table public.organizations (
  id             uuid primary key default gen_random_uuid(),
  org_code       text not null unique check (org_code ~ '^[0-9]{6}$'),
  name           text not null check (char_length(btrim(name)) between 2 and 200),
  status         text not null default 'active' check (status in ('active', 'suspended', 'inactive')),
  timezone       text not null default 'Asia/Dhaka',
  card_id_mode   text not null default 'auto' check (card_id_mode in ('auto', 'custom')),
  card_id_length smallint not null default 8 check (card_id_length between 8 and 10),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id)
);

create or replace function private.organizations_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.org_code is distinct from old.org_code then
    raise exception 'Organization code can never change' using errcode = '42501';
  end if;
  if new.timezone is distinct from old.timezone
     and not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception 'Unknown timezone %', new.timezone using errcode = '22023';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Roles and permissions
-- -----------------------------------------------------------------------------
create table public.permissions (
  key         text primary key,
  module      text not null,
  description text not null,
  admin_only  boolean not null default false   -- can never be granted to a non-Admin role
);

create table public.roles (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  name        text not null check (char_length(btrim(name)) between 2 and 80),
  description text,
  system_key  text check (system_key in ('admin', 'hr_manager', 'manager', 'employee')),
  is_system   boolean generated always as (system_key is not null) stored,
  status      text not null default 'active' check (status in ('active', 'inactive')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint roles_org_id_id_uq unique (org_id, id),
  constraint roles_org_system_key_uq unique (org_id, system_key)
);

create unique index roles_org_name_uq on public.roles (org_id, lower(name));

-- Users <-> organization. One active membership per user (one company at a time).
-- In Step 5 this gets linked to the employee row.
create table public.org_members (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  user_id    uuid not null references public.user_profiles (id),
  role_id    uuid not null,
  status     text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  -- Role must belong to the same organization.
  constraint org_members_role_fk foreign key (org_id, role_id) references public.roles (org_id, id)
);

create unique index org_members_one_active_uq on public.org_members (user_id) where status = 'active';
create index org_members_org_idx on public.org_members (org_id, status);
create index org_members_role_idx on public.org_members (role_id);

create table public.role_permissions (
  org_id         uuid not null references public.organizations (id),
  role_id        uuid not null,
  permission_key text not null references public.permissions (key),
  created_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id) default auth.uid(),
  primary key (role_id, permission_key),
  constraint role_permissions_role_fk foreign key (org_id, role_id) references public.roles (org_id, id)
);

-- The Admin's per-field checkboxes: which fields a role may see or edit.
create table public.role_field_access (
  org_id     uuid not null references public.organizations (id),
  role_id    uuid not null,
  resource   text not null,           -- e.g. 'employees', 'employee_sensitive'
  field_key  text not null,           -- e.g. 'date_of_birth', 'nid_number'
  can_view   boolean not null default false,
  can_edit   boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  primary key (role_id, resource, field_key),
  constraint role_field_access_role_fk foreign key (org_id, role_id) references public.roles (org_id, id),
  constraint role_field_access_edit_needs_view check (not can_edit or can_view)
);

-- -----------------------------------------------------------------------------
-- Access helpers used by every RLS policy. They read the tables (not JWT claims)
-- so role changes and revocations take effect on the very next request.
-- -----------------------------------------------------------------------------
create or replace function private.active_membership()
returns table (org_id uuid, role_id uuid, role_key text)
language sql
stable
security definer
set search_path = ''
as $$
  select m.org_id, m.role_id, r.system_key
  from public.org_members m
  join public.organizations o on o.id = m.org_id and o.status = 'active'
  join public.user_profiles u on u.id = m.user_id and u.status = 'active'
  join public.roles r on r.id = m.role_id and r.status = 'active'
  where m.user_id = auth.uid()
    and m.status = 'active'
  limit 1
$$;

create or replace function private.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select org_id from private.active_membership()
$$;

create or replace function private.current_role_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select role_id from private.active_membership()
$$;

create or replace function private.is_org_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select role_key = 'admin' from private.active_membership()), false)
$$;

-- Admin implicitly holds every permission; other roles need a role_permissions row.
create or replace function private.has_permission(p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.active_membership() am
    where am.role_key = 'admin'
       or exists (select 1 from public.role_permissions rp
                  where rp.role_id = am.role_id and rp.permission_key = p_key)
  )
$$;

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins pa
    join public.user_profiles u on u.id = pa.user_id and u.status = 'active'
    where pa.user_id = auth.uid()
  )
$$;

-- New rows default to the caller's organization.
alter table public.roles             alter column org_id set default private.current_org_id();
alter table public.role_permissions  alter column org_id set default private.current_org_id();
alter table public.role_field_access alter column org_id set default private.current_org_id();

-- -----------------------------------------------------------------------------
-- Role protection rules
-- -----------------------------------------------------------------------------
create or replace function private.roles_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.org_id is distinct from old.org_id or new.system_key is distinct from old.system_key then
    raise exception 'Role organization and system key cannot change' using errcode = '42501';
  end if;
  if new.status = 'inactive' and old.status = 'active' then
    if old.is_system then
      raise exception 'System roles cannot be deactivated' using errcode = '42501';
    end if;
    if exists (select 1 from public.org_members where role_id = old.id and status = 'active') then
      raise exception 'Reassign the users of this role before deactivating it' using errcode = '23503';
    end if;
  end if;
  return new;
end;
$$;

create or replace function private.role_permissions_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_role_id uuid := coalesce(new.role_id, old.role_id);
  v_key     text := coalesce(new.permission_key, old.permission_key);
begin
  if exists (select 1 from public.roles where id = v_role_id and system_key = 'admin') then
    raise exception 'Admin permissions are fixed and cannot be changed' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and exists (select 1 from public.permissions where key = v_key and admin_only) then
    raise exception 'Permission % is reserved for the Admin role', v_key using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

-- An Admin cannot remove their own admin access; an organization always keeps
-- at least one active Admin. Organization and user of a membership never change.
create or replace function private.org_members_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_was_admin boolean;
  v_is_admin  boolean;
begin
  if new.org_id is distinct from old.org_id or new.user_id is distinct from old.user_id then
    raise exception 'Membership organization and user cannot change' using errcode = '42501';
  end if;

  if new.role_id is distinct from old.role_id
     and exists (select 1 from public.roles where id = new.role_id and status <> 'active') then
    raise exception 'Cannot assign an inactive role' using errcode = '23514';
  end if;

  select system_key = 'admin' into v_was_admin from public.roles where id = old.role_id;
  select system_key = 'admin' into v_is_admin  from public.roles where id = new.role_id;

  if coalesce(v_was_admin, false) and old.status = 'active'
     and (not coalesce(v_is_admin, false) or new.status <> 'active') then
    if old.user_id = auth.uid() then
      raise exception 'You cannot remove your own admin access' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.org_members m
      join public.roles r on r.id = m.role_id and r.system_key = 'admin'
      where m.org_id = old.org_id and m.status = 'active' and m.id <> old.id
    ) then
      raise exception 'An organization must keep at least one active Admin' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Keep user_profiles in sync with auth.users
-- -----------------------------------------------------------------------------
create or replace function private.handle_auth_user_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_profiles (id, email, phone, full_name, must_change_password)
  values (
    new.id,
    lower(nullif(btrim(new.email), '')),
    private.normalize_bd_phone(new.phone),
    coalesce(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    -- app_meta_data is writable only with the service key, so this is safe.
    coalesce((new.raw_app_meta_data ->> 'must_change_password')::boolean, false)
  );
  return new;
end;
$$;

create or replace function private.handle_auth_user_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.user_profiles
     set email = lower(nullif(btrim(new.email), '')),
         phone = private.normalize_bd_phone(new.phone)
   where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_auth_user_insert();

create trigger on_auth_user_contact_changed
  after update of email, phone on auth.users
  for each row
  when (old.email is distinct from new.email or old.phone is distinct from new.phone)
  execute function private.handle_auth_user_update();

-- -----------------------------------------------------------------------------
-- Triggers: metadata, guards, soft delete, audit
-- -----------------------------------------------------------------------------
create trigger set_row_meta before insert or update on public.user_profiles
  for each row execute function private.set_row_meta();
create trigger set_row_meta before insert or update on public.organizations
  for each row execute function private.set_row_meta();
create trigger set_row_meta before insert or update on public.roles
  for each row execute function private.set_row_meta();
create trigger set_row_meta before insert or update on public.org_members
  for each row execute function private.set_row_meta();
create trigger set_row_meta before insert or update on public.role_field_access
  for each row execute function private.set_row_meta();

create trigger organizations_guard before update on public.organizations
  for each row execute function private.organizations_guard();
create trigger roles_guard before update on public.roles
  for each row execute function private.roles_guard();
create trigger role_permissions_guard before insert or update or delete on public.role_permissions
  for each row execute function private.role_permissions_guard();
create trigger org_members_guard before update on public.org_members
  for each row execute function private.org_members_guard();

create trigger no_delete before delete on public.user_profiles
  for each row execute function private.prevent_delete();
create trigger no_delete before delete on public.organizations
  for each row execute function private.prevent_delete();
create trigger no_delete before delete on public.roles
  for each row execute function private.prevent_delete();
create trigger no_delete before delete on public.org_members
  for each row execute function private.prevent_delete();

create trigger audit after insert or update or delete on public.user_profiles
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.organizations
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.roles
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.org_members
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.role_permissions
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.role_field_access
  for each row execute function private.audit_row_change();
create trigger audit after insert or update or delete on public.platform_admins
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Permission catalog (Part 1)
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('org.view',               'organization', 'View organization structure',                         false),
  ('org.manage',             'organization', 'Manage departments, designations, grades, branches, offices, operations', false),
  ('employees.view',         'employees',    'View the people list and profiles',                   false),
  ('employees.create',       'employees',    'Add employees',                                       false),
  ('employees.edit',         'employees',    'Edit employee details',                               false),
  ('employees.deactivate',   'employees',    'Deactivate employees',                                false),
  ('employees.transfer',     'employees',    'Transfer and promote employees',                      false),
  ('employees.reporting',    'employees',    'Change reporting lines',                              false),
  ('employees.portal_access','employees',    'Assign and revoke portal access',                     false),
  ('users.reset_password',   'security',     'Reset a user''s password',                            false),
  ('roles.view',             'security',     'View roles and their permissions',                    false),
  ('roles.manage',           'security',     'Create, edit and assign roles',                       true),
  ('settings.manage',        'settings',     'Organization settings and card ID policy',            true),
  ('audit.view',             'security',     'View the audit log',                                  true);

-- =============================================================================
-- Privileges and row-level security
-- =============================================================================
alter table public.user_profiles     enable row level security;
alter table public.platform_admins   enable row level security;
alter table public.organizations     enable row level security;
alter table public.permissions       enable row level security;
alter table public.roles             enable row level security;
alter table public.org_members       enable row level security;
alter table public.role_permissions  enable row level security;
alter table public.role_field_access enable row level security;

revoke all on table
  public.user_profiles, public.platform_admins, public.organizations, public.permissions,
  public.roles, public.org_members, public.role_permissions, public.role_field_access
from anon, authenticated;

-- Writes to identity, membership and organizations go through server functions,
-- except the narrow column grants below.
grant select on table
  public.user_profiles, public.organizations, public.permissions,
  public.roles, public.org_members, public.role_permissions, public.role_field_access
to authenticated;

grant update (name, timezone, card_id_mode, card_id_length) on public.organizations to authenticated;
grant insert (name, description, status), update (name, description, status) on public.roles to authenticated;
grant update (role_id) on public.org_members to authenticated;
grant insert (role_id, permission_key), delete on public.role_permissions to authenticated;
grant insert (role_id, resource, field_key, can_view, can_edit),
      update (can_view, can_edit),
      delete on public.role_field_access to authenticated;

grant execute on function
  private.active_membership(), private.current_org_id(), private.current_role_id(),
  private.is_org_admin(), private.has_permission(text), private.is_platform_admin()
to authenticated;

-- user_profiles -------------------------------------------------------------
create policy user_profiles_select on public.user_profiles for select to authenticated
using (
  id = (select auth.uid())
  or (select private.is_platform_admin())
  or (
    (select private.has_permission('employees.view'))
    and exists (select 1 from public.org_members m
                where m.user_id = user_profiles.id
                  and m.org_id = (select private.current_org_id()))
  )
);

-- organizations -------------------------------------------------------------
create policy organizations_select on public.organizations for select to authenticated
using (id = (select private.current_org_id()) or (select private.is_platform_admin()));

create policy organizations_update on public.organizations for update to authenticated
using (id = (select private.current_org_id()) and (select private.has_permission('settings.manage')))
with check (id = (select private.current_org_id()));

-- permissions (global catalog) ---------------------------------------------
create policy permissions_select on public.permissions for select to authenticated using (true);

-- roles -----------------------------------------------------------------------
create policy roles_select on public.roles for select to authenticated
using (
  org_id = (select private.current_org_id())
  and ((select private.has_permission('roles.view')) or id = (select private.current_role_id()))
);

create policy roles_insert on public.roles for insert to authenticated
with check (org_id = (select private.current_org_id()) and (select private.is_org_admin()));

create policy roles_update on public.roles for update to authenticated
using (org_id = (select private.current_org_id()) and (select private.is_org_admin()))
with check (org_id = (select private.current_org_id()));

-- role_permissions ----------------------------------------------------------
create policy role_permissions_select on public.role_permissions for select to authenticated
using (
  org_id = (select private.current_org_id())
  and ((select private.has_permission('roles.view')) or role_id = (select private.current_role_id()))
);

create policy role_permissions_insert on public.role_permissions for insert to authenticated
with check (org_id = (select private.current_org_id()) and (select private.is_org_admin()));

create policy role_permissions_delete on public.role_permissions for delete to authenticated
using (org_id = (select private.current_org_id()) and (select private.is_org_admin()));

-- role_field_access ---------------------------------------------------------
create policy role_field_access_select on public.role_field_access for select to authenticated
using (
  org_id = (select private.current_org_id())
  and ((select private.has_permission('roles.view')) or role_id = (select private.current_role_id()))
);

create policy role_field_access_insert on public.role_field_access for insert to authenticated
with check (org_id = (select private.current_org_id()) and (select private.is_org_admin()));

create policy role_field_access_update on public.role_field_access for update to authenticated
using (org_id = (select private.current_org_id()) and (select private.is_org_admin()))
with check (org_id = (select private.current_org_id()));

create policy role_field_access_delete on public.role_field_access for delete to authenticated
using (org_id = (select private.current_org_id()) and (select private.is_org_admin()));

-- org_members ---------------------------------------------------------------
create policy org_members_select on public.org_members for select to authenticated
using (
  (select private.is_platform_admin())
  or user_id = (select auth.uid())
  or (
    org_id = (select private.current_org_id())
    and ((select private.has_permission('employees.view')) or (select private.has_permission('roles.view')))
  )
);

-- Only Admin assigns roles. New memberships are created by server functions only.
create policy org_members_update on public.org_members for update to authenticated
using (org_id = (select private.current_org_id()) and (select private.is_org_admin()))
with check (org_id = (select private.current_org_id()));

-- audit_logs (table from the core migration) --------------------------------
create policy audit_logs_select on public.audit_logs for select to authenticated
using (
  (org_id = (select private.current_org_id()) and (select private.has_permission('audit.view')))
  or (select private.is_platform_admin())
);
