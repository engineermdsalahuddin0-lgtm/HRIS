-- =============================================================================
-- Olympus HRIS — Part 1, Step 4: Roles screen and field visibility
-- =============================================================================

-- Fixed catalog of employee fields an Admin can tick per role.
-- Core fields (card ID, name, status, department, designation, grade, branch,
-- office, operation) are always visible to anyone who can see the employee.
create table public.field_catalog (
  resource   text not null,
  field_key  text not null,
  label      text not null,
  group_name text not null,
  sensitive  boolean not null default false,
  sort       smallint not null,
  primary key (resource, field_key)
);

insert into public.field_catalog (resource, field_key, label, group_name, sensitive, sort) values
  ('employees',          'full_name',         'Full name',            'Personal',      false, 10),
  ('employees',          'phone',             'Phone',                'Contact',       false, 20),
  ('employees',          'email',             'Email',                'Contact',       false, 21),
  ('employees',          'present_address',   'Present address',      'Contact',       false, 22),
  ('employees',          'permanent_address', 'Permanent address',    'Contact',       false, 23),
  ('employees',          'date_of_birth',     'Date of birth',        'Personal',      false, 11),
  ('employees',          'gender',            'Gender',               'Personal',      false, 12),
  ('employees',          'marital_status',    'Marital status',       'Personal',      false, 13),
  ('employees',          'religion',          'Religion',             'Personal',      false, 14),
  ('employees',          'blood_group',       'Blood group',          'Personal',      false, 15),
  ('employees',          'join_date',         'Join date',            'Job',           false, 30),
  ('employees',          'employment_type',   'Employment type',      'Job',           false, 31),
  ('employees',          'probation_end_date','Probation end date',   'Job',           false, 32),
  ('employees',          'confirmation_date', 'Confirmation date',    'Job',           false, 33),
  ('employees',          'nominees',          'Nominees',             'Family',        false, 40),
  ('employee_sensitive', 'nid_number',        'NID number',           'Identification', true, 50);

alter table public.field_catalog enable row level security;
revoke all on table public.field_catalog from anon, authenticated;
grant select on table public.field_catalog to authenticated;
create policy field_catalog_select on public.field_catalog for select to authenticated using (true);

-- Field rows must name a catalog field.
alter table public.role_field_access
  add constraint role_field_access_field_fk foreign key (resource, field_key)
  references public.field_catalog (resource, field_key);

-- -----------------------------------------------------------------------------
-- Default field access for the system roles.
-- HR Manager: everything. Manager: work contact and job fields only.
-- Employee: these rows decide what they may edit on their own profile
-- (people always see their own full record).
-- -----------------------------------------------------------------------------
create or replace function private.seed_default_field_access(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_field_access (org_id, role_id, resource, field_key, can_view, can_edit)
  select p_org_id, r.id, f.resource, f.field_key, true, true
  from public.roles r cross join public.field_catalog f
  where r.org_id = p_org_id and r.system_key = 'hr_manager'
  on conflict do nothing;

  insert into public.role_field_access (org_id, role_id, resource, field_key, can_view, can_edit)
  select p_org_id, r.id, f.resource, f.field_key, true, false
  from public.roles r cross join public.field_catalog f
  where r.org_id = p_org_id and r.system_key = 'manager'
    and f.field_key in ('phone', 'email', 'join_date', 'employment_type', 'gender')
  on conflict do nothing;

  insert into public.role_field_access (org_id, role_id, resource, field_key, can_view, can_edit)
  select p_org_id, r.id, f.resource, f.field_key, true, true
  from public.roles r cross join public.field_catalog f
  where r.org_id = p_org_id and r.system_key = 'employee'
    and f.field_key in ('phone', 'present_address', 'permanent_address', 'marital_status', 'blood_group', 'nominees')
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
end;
$$;

select private.seed_default_field_access(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Admin RPCs: save a role's permissions / field ticks as one atomic change.
-- -----------------------------------------------------------------------------
create or replace function public.set_role_permissions(p_role_id uuid, p_keys text[])
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.roles;
begin
  if not private.is_org_admin() then
    raise exception 'Only an Admin can change roles' using errcode = '42501';
  end if;
  select * into v_role from public.roles where id = p_role_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Role not found' using errcode = 'P0002';
  end if;
  if v_role.system_key = 'admin' then
    raise exception 'Admin permissions are fixed and cannot be changed' using errcode = '42501';
  end if;

  delete from public.role_permissions
   where role_id = p_role_id and permission_key <> all (coalesce(p_keys, '{}'));
  insert into public.role_permissions (org_id, role_id, permission_key)
  select v_role.org_id, p_role_id, k from unnest(coalesce(p_keys, '{}')) as k
  on conflict do nothing;   -- admin-only keys are rejected by the role_permissions guard
end;
$$;

-- p_fields: [{ "resource": "employees", "field_key": "phone", "can_view": true, "can_edit": false }, ...]
create or replace function public.set_role_field_access(p_role_id uuid, p_fields jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.roles;
begin
  if not private.is_org_admin() then
    raise exception 'Only an Admin can change field access' using errcode = '42501';
  end if;
  select * into v_role from public.roles where id = p_role_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Role not found' using errcode = 'P0002';
  end if;
  if v_role.system_key = 'admin' then
    raise exception 'Admin sees and edits every field' using errcode = '42501';
  end if;

  delete from public.role_field_access where role_id = p_role_id;
  insert into public.role_field_access (org_id, role_id, resource, field_key, can_view, can_edit)
  select v_role.org_id, p_role_id, f.resource, f.field_key,
         coalesce(f.can_view, false) or coalesce(f.can_edit, false), coalesce(f.can_edit, false)
  from jsonb_to_recordset(coalesce(p_fields, '[]'::jsonb))
       as f(resource text, field_key text, can_view boolean, can_edit boolean)
  where coalesce(f.can_view, false) or coalesce(f.can_edit, false);
end;
$$;

revoke all on function public.set_role_permissions(uuid, text[]), public.set_role_field_access(uuid, jsonb)
  from public, anon;
grant execute on function public.set_role_permissions(uuid, text[]), public.set_role_field_access(uuid, jsonb)
  to authenticated;
revoke all on function private.seed_default_field_access(uuid), private.seed_org_defaults(uuid)
  from public, anon, authenticated;
