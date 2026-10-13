-- =============================================================================
-- Olympus HRIS — Part 1, Step 1: Organization sign-up and creation
--
-- Flow:
--   1. Applicant creates a login (Supabase Auth, email + password).
--   2. Applicant calls submit_org_signup_request(...)  -> status 'pending'.
--   3. Platform admin calls approve_org_signup_request(id)
--        -> organization (random 6-digit code), default roles, applicant = Admin.
--      or reject_org_signup_request(id, note).
-- =============================================================================

create table public.org_signup_requests (
  id                uuid primary key default gen_random_uuid(),
  applicant_user_id uuid not null references public.user_profiles (id),
  org_name          text not null check (char_length(btrim(org_name)) between 2 and 200),
  contact_name      text not null check (char_length(btrim(contact_name)) between 2 and 120),
  contact_phone     text check (contact_phone ~ '^\+8801[3-9][0-9]{8}$'),
  timezone          text not null default 'Asia/Dhaka',
  status            text not null default 'pending'
                    check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  review_note       text,
  reviewed_by       uuid references public.user_profiles (id),
  reviewed_at       timestamptz,
  organization_id   uuid references public.organizations (id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references public.user_profiles (id),
  updated_by        uuid references public.user_profiles (id)
);

create unique index org_signup_requests_one_pending_uq
  on public.org_signup_requests (applicant_user_id) where status = 'pending';
create index org_signup_requests_status_idx on public.org_signup_requests (status, created_at);

create trigger set_row_meta before insert or update on public.org_signup_requests
  for each row execute function private.set_row_meta();
create trigger no_delete before delete on public.org_signup_requests
  for each row execute function private.prevent_delete();
create trigger audit after insert or update or delete on public.org_signup_requests
  for each row execute function private.audit_row_change();

alter table public.org_signup_requests enable row level security;
revoke all on table public.org_signup_requests from anon, authenticated;
grant select on table public.org_signup_requests to authenticated;

create policy org_signup_requests_select on public.org_signup_requests for select to authenticated
using (applicant_user_id = (select auth.uid()) or (select private.is_platform_admin()));

-- -----------------------------------------------------------------------------
-- Internal: create an organization with defaults. Not callable from the API.
-- -----------------------------------------------------------------------------
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
  v_org_id   uuid;
  v_attempt  int := 0;
  v_admin_id uuid;
  v_hr_id    uuid;
  v_mgr_id   uuid;
  v_emp_id   uuid;
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown timezone %', p_timezone using errcode = '22023';
  end if;

  if exists (select 1 from public.org_members where user_id = p_owner_user_id and status = 'active') then
    raise exception 'This user already belongs to an organization' using errcode = '23505';
  end if;

  -- Random 6-digit code (100000-999999), retried on collision. The unique
  -- constraint makes this safe under concurrency.
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

  insert into public.roles (org_id, name, description, system_key) values
    (v_org_id, 'Admin',      'Full access inside this organization', 'admin')
    returning id into v_admin_id;
  insert into public.roles (org_id, name, description, system_key) values
    (v_org_id, 'HR Manager', 'Manages employees and organization structure', 'hr_manager')
    returning id into v_hr_id;
  insert into public.roles (org_id, name, description, system_key) values
    (v_org_id, 'Manager',    'Sees the people list within allowed fields', 'manager')
    returning id into v_mgr_id;
  insert into public.roles (org_id, name, description, system_key) values
    (v_org_id, 'Employee',   'Sees and edits only their own profile', 'employee')
    returning id into v_emp_id;

  -- Admin needs no rows: it implicitly holds every permission.
  insert into public.role_permissions (org_id, role_id, permission_key)
  select v_org_id, v_hr_id, k
  from unnest(array[
    'org.view', 'org.manage',
    'employees.view', 'employees.create', 'employees.edit', 'employees.deactivate',
    'employees.transfer', 'employees.reporting', 'employees.portal_access',
    'users.reset_password', 'roles.view'
  ]) as k;

  insert into public.role_permissions (org_id, role_id, permission_key)
  select v_org_id, v_mgr_id, k
  from unnest(array['org.view', 'employees.view']) as k;

  -- Employee role: no permissions; own-profile access is granted by row policies.

  insert into public.org_members (org_id, user_id, role_id)
  values (v_org_id, p_owner_user_id, v_admin_id);

  perform private.write_audit(v_org_id, 'organization.created', 'organizations', v_org_id, null,
                              jsonb_build_object('owner_user_id', p_owner_user_id));
  return v_org_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Public RPCs
-- -----------------------------------------------------------------------------
create or replace function public.submit_org_signup_request(
  p_org_name      text,
  p_contact_name  text,
  p_contact_phone text default null,
  p_timezone      text default 'Asia/Dhaka'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  if exists (select 1 from public.org_members where user_id = v_uid and status = 'active') then
    raise exception 'You already belong to an organization' using errcode = '23505';
  end if;
  if exists (select 1 from public.org_signup_requests where applicant_user_id = v_uid and status = 'pending') then
    raise exception 'You already have a pending request' using errcode = '23505';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'Unknown timezone %', p_timezone using errcode = '22023';
  end if;

  insert into public.org_signup_requests (applicant_user_id, org_name, contact_name, contact_phone, timezone)
  values (v_uid, btrim(p_org_name), btrim(p_contact_name),
          private.normalize_bd_phone(p_contact_phone), p_timezone)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.cancel_org_signup_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.org_signup_requests
     set status = 'cancelled'
   where id = p_request_id and applicant_user_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'No pending request found' using errcode = 'P0002';
  end if;
end;
$$;

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

  v_org_id := private.create_organization(v_req.org_name, v_req.timezone, v_req.applicant_user_id);

  update public.user_profiles
     set full_name = v_req.contact_name
   where id = v_req.applicant_user_id and full_name = '';

  update public.org_signup_requests
     set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), organization_id = v_org_id
   where id = p_request_id;

  return v_org_id;
end;
$$;

create or replace function public.reject_org_signup_request(p_request_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_platform_admin() then
    raise exception 'Only a platform admin can reject sign-ups' using errcode = '42501';
  end if;
  if p_note is null or btrim(p_note) = '' then
    raise exception 'A reason is required' using errcode = '22023';
  end if;
  update public.org_signup_requests
     set status = 'rejected', review_note = btrim(p_note), reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request_id and status = 'pending';
  if not found then
    raise exception 'No pending request found' using errcode = 'P0002';
  end if;
end;
$$;

-- Everything the UI needs after login, in one call (for the Zustand session store).
-- For display only: the database re-checks every permission on every request.
create or replace function public.get_my_context()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user', (select jsonb_build_object('id', u.id, 'email', u.email, 'phone', u.phone,
                                       'full_name', u.full_name, 'status', u.status,
                                       'must_change_password', u.must_change_password)
             from public.user_profiles u where u.id = auth.uid()),
    'organization', (select jsonb_build_object('id', o.id, 'org_code', o.org_code, 'name', o.name,
                                               'timezone', o.timezone)
                     from public.organizations o where o.id = private.current_org_id()),
    'role', (select jsonb_build_object('id', r.id, 'name', r.name, 'system_key', r.system_key)
             from public.roles r where r.id = private.current_role_id()),
    'permissions', coalesce((
      select jsonb_agg(p.key order by p.key)
      from public.permissions p
      where private.current_org_id() is not null and private.has_permission(p.key)
    ), '[]'::jsonb),
    'is_platform_admin', private.is_platform_admin(),
    'pending_signup_request', (
      select jsonb_build_object('id', s.id, 'org_name', s.org_name, 'status', s.status, 'created_at', s.created_at)
      from public.org_signup_requests s
      where s.applicant_user_id = auth.uid() and s.status = 'pending'
    )
  )
$$;

revoke all on function
  public.submit_org_signup_request(text, text, text, text),
  public.cancel_org_signup_request(uuid),
  public.approve_org_signup_request(uuid),
  public.reject_org_signup_request(uuid, text),
  public.get_my_context()
from public, anon;

grant execute on function
  public.submit_org_signup_request(text, text, text, text),
  public.cancel_org_signup_request(uuid),
  public.approve_org_signup_request(uuid),
  public.reject_org_signup_request(uuid, text),
  public.get_my_context()
to authenticated;

-- Internal functions stay closed to every API role.
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function
  private.active_membership(), private.current_org_id(), private.current_role_id(),
  private.is_org_admin(), private.has_permission(text), private.is_platform_admin()
to authenticated;
