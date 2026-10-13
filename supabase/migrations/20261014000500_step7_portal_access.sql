-- =============================================================================
-- Olympus HRIS — Part 1, Step 7: Portal access (and employee deactivation)
--
-- Logins are created and controlled inside Postgres (security definer
-- functions writing auth.users / auth.identities), so no service-role key or
-- Edge Function is needed and everything is one transaction with the audit row.
-- Passwords are hashed with bcrypt (pgcrypto), the same format Supabase Auth uses.
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Internal helpers
-- -----------------------------------------------------------------------------
create or replace function private.assert_password_ok(p_password text)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_password is null or length(p_password) < 8 or p_password !~ '[A-Za-z]' or p_password !~ '[0-9]' then
    raise exception 'Password must be at least 8 characters, with letters and numbers' using errcode = '22023';
  end if;
end;
$$;

-- Ends every session of a user right away (refresh tokens included).
create or replace function private.kill_sessions(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  delete from auth.sessions where user_id = p_user_id;
end;
$$;

create or replace function private.set_auth_password(p_user_id uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.assert_password_ok(p_password);
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
         banned_until = null,
         updated_at = now()
   where id = p_user_id;
  update public.user_profiles set must_change_password = true, status = 'active' where id = p_user_id;
end;
$$;

-- Creates a confirmed login (email and/or phone) with a company-issued password.
create or replace function private.create_auth_user(p_email text, p_phone text, p_password text, p_full_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id    uuid := gen_random_uuid();
  v_phone text := ltrim(p_phone, '+');     -- Supabase Auth stores phones without '+'
  v_providers text[] := array_remove(array[
    case when p_email is not null then 'email' end,
    case when p_phone is not null then 'phone' end], null);
begin
  perform private.assert_password_ok(p_password);
  insert into auth.users (
    instance_id, id, aud, role, email, phone, encrypted_password,
    email_confirmed_at, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email, v_phone,
    extensions.crypt(p_password, extensions.gen_salt('bf', 10)),
    case when p_email is not null then now() end,
    case when p_phone is not null then now() end,
    jsonb_build_object('provider', v_providers[1], 'providers', to_jsonb(v_providers), 'must_change_password', true),
    jsonb_build_object('full_name', p_full_name),
    now(), now(), '', '', '', '', '', '', '', '');

  if p_email is not null then
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_id::text, v_id,
            jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
            'email', null, now(), now());
  end if;
  if p_phone is not null then
    insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (v_id::text, v_id,
            jsonb_build_object('sub', v_id::text, 'phone', v_phone, 'email_verified', false, 'phone_verified', true),
            'phone', null, now(), now());
  end if;
  return v_id;
end;
$$;

-- Turns off a login's access to this organization immediately.
create or replace function private.revoke_portal_internal(p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member public.org_members;
begin
  select * into v_member from public.org_members where employee_id = p_employee_id and status = 'active';
  if not found then
    return;
  end if;
  update public.org_members set status = 'inactive' where id = v_member.id;   -- guard keeps one Admin
  update auth.users set banned_until = now() + interval '100 years', updated_at = now() where id = v_member.user_id;
  perform private.kill_sessions(v_member.user_id);
end;
$$;

-- Admin-level targets can only be handled by an Admin.
create or replace function private.assert_can_manage_login(p_employee_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_employee_id = private.current_employee_id() then
    raise exception 'You cannot do this to your own account' using errcode = '42501';
  end if;
  if not private.is_org_admin() and exists (
    select 1 from public.org_members m join public.roles r on r.id = m.role_id
    where m.employee_id = p_employee_id and m.status = 'active' and r.system_key = 'admin') then
    raise exception 'Only an Admin can manage another Admin''s login' using errcode = '42501';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Public RPCs
-- -----------------------------------------------------------------------------
-- Gives an employee a login. HR may only give the Employee role; any other
-- role (roles are assigned by Admin only) needs an Admin.
create or replace function public.grant_portal_access(
  p_employee_id uuid,
  p_email       text,
  p_phone       text,
  p_password    text,
  p_role_id     uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp     public.employees;
  v_role    public.roles;
  v_email   text := lower(nullif(btrim(p_email), ''));
  v_phone   text := private.normalize_bd_phone(p_phone);
  v_user_id uuid;
  v_by_mail uuid;
  v_by_ph   uuid;
begin
  perform private.require_permission('employees.portal_access');
  select * into v_emp from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if v_emp.status <> 'active' then
    raise exception 'Only active employees can get portal access' using errcode = '23514';
  end if;
  if exists (select 1 from public.org_members where employee_id = p_employee_id and status = 'active') then
    raise exception 'This employee already has portal access' using errcode = '23505';
  end if;
  if v_email is null and v_phone is null then
    raise exception 'Give an email or a mobile number for the login' using errcode = '23502';
  end if;
  if v_email is not null and v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' then
    raise exception 'Invalid email' using errcode = '22023';
  end if;
  perform private.assert_password_ok(p_password);

  if p_role_id is null then
    select * into v_role from public.roles where org_id = v_emp.org_id and system_key = 'employee';
  else
    select * into v_role from public.roles where id = p_role_id and org_id = v_emp.org_id;
  end if;
  if not found or v_role.status <> 'active' then
    raise exception 'Role not found or inactive' using errcode = 'P0002';
  end if;
  if v_role.system_key is distinct from 'employee' and not private.is_org_admin() then
    raise exception 'Only an Admin can give a role other than Employee' using errcode = '42501';
  end if;

  select id into v_by_mail from public.user_profiles where v_email is not null and email = v_email;
  select id into v_by_ph   from public.user_profiles where v_phone is not null and phone = v_phone;
  if v_by_mail is not null and v_by_ph is not null and v_by_mail <> v_by_ph then
    raise exception 'This email or mobile number is already in use' using errcode = '23505';
  end if;
  v_user_id := coalesce(v_emp.user_id, v_by_mail, v_by_ph);
  if (v_by_mail is not null and v_by_mail <> v_user_id) or (v_by_ph is not null and v_by_ph <> v_user_id) then
    raise exception 'This email or mobile number is already in use' using errcode = '23505';
  end if;

  if v_user_id is null then
    v_user_id := private.create_auth_user(v_email, v_phone, p_password, v_emp.full_name);
  else
    -- Existing identity: only allowed when it has no active employment anywhere.
    if exists (select 1 from public.org_members where user_id = v_user_id and status = 'active') then
      raise exception 'This email or mobile number is already in use' using errcode = '23505';
    end if;
    update auth.users
       set email = coalesce(v_email, email),
           phone = coalesce(ltrim(v_phone, '+'), phone),
           email_confirmed_at = coalesce(email_confirmed_at, case when v_email is not null then now() end),
           phone_confirmed_at = coalesce(phone_confirmed_at, case when v_phone is not null then now() end),
           updated_at = now()
     where id = v_user_id;
    perform private.set_auth_password(v_user_id, p_password);
  end if;

  update public.user_profiles
     set must_change_password = true, status = 'active',
         full_name = case when full_name = '' then v_emp.full_name else full_name end
   where id = v_user_id;
  update public.employees set user_id = v_user_id where id = p_employee_id;
  insert into public.org_members (org_id, user_id, role_id, employee_id)
  values (v_emp.org_id, v_user_id, v_role.id, p_employee_id);

  perform private.write_audit(v_emp.org_id, 'portal.granted', 'employees', p_employee_id, null,
    jsonb_build_object('user_id', v_user_id, 'email', v_email, 'phone', v_phone, 'role', v_role.name));
  return v_user_id;
end;
$$;

create or replace function public.revoke_portal_access(p_employee_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('employees.portal_access');
  if not exists (select 1 from public.employees where id = p_employee_id and org_id = v_org) then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  perform private.assert_can_manage_login(p_employee_id);
  if not exists (select 1 from public.org_members where employee_id = p_employee_id and status = 'active') then
    raise exception 'This employee has no portal access' using errcode = 'P0002';
  end if;
  perform private.revoke_portal_internal(p_employee_id);
  perform private.write_audit(v_org, 'portal.revoked', 'employees', p_employee_id, null,
                              jsonb_build_object('reason', nullif(btrim(p_reason), '')));
end;
$$;

-- Role assignment: Admin only (the org_members guard keeps the Admin rules).
create or replace function public.change_portal_role(p_employee_id uuid, p_role_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if not private.is_org_admin() then
    raise exception 'Only an Admin can assign roles' using errcode = '42501';
  end if;
  if not exists (select 1 from public.roles where id = p_role_id and org_id = v_org and status = 'active') then
    raise exception 'Role not found or inactive' using errcode = 'P0002';
  end if;
  update public.org_members set role_id = p_role_id
   where employee_id = p_employee_id and org_id = v_org and status = 'active';
  if not found then
    raise exception 'This employee has no portal access' using errcode = 'P0002';
  end if;
end;
$$;

-- HR/Admin reset (phone-only users cannot use email reset links).
create or replace function public.reset_user_password(p_employee_id uuid, p_new_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_user uuid;
begin
  perform private.require_permission('users.reset_password');
  select m.user_id into v_user from public.org_members m
   where m.employee_id = p_employee_id and m.org_id = v_org and m.status = 'active';
  if v_user is null then
    raise exception 'This employee has no portal access' using errcode = 'P0002';
  end if;
  perform private.assert_can_manage_login(p_employee_id);
  perform private.set_auth_password(v_user, p_new_password);
  perform private.kill_sessions(v_user);
  perform private.write_audit(v_org, 'password.reset', 'user_profiles', v_user, null,
                              jsonb_build_object('employee_id', p_employee_id));
end;
$$;

-- Deactivate (inactive) or terminate. Closes the employee's reporting lines,
-- clears department/branch head roles and revokes portal access.
create or replace function public.deactivate_employee(
  p_employee_id uuid,
  p_status      text,
  p_exit_date   date,
  p_reason      text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp  public.employees;
  v_exit date := coalesce(p_exit_date, current_date);
begin
  perform private.require_permission('employees.deactivate');
  select * into v_emp from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_status not in ('inactive', 'terminated') then
    raise exception 'Status must be inactive or terminated' using errcode = '22023';
  end if;
  if v_emp.status <> 'active' then
    raise exception 'This employee is not active' using errcode = '23514';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A reason is required' using errcode = '23502';
  end if;
  perform private.assert_can_manage_login(p_employee_id);

  perform private.revoke_portal_internal(p_employee_id);
  update public.employees set status = p_status, exit_date = greatest(v_exit, join_date) where id = p_employee_id;
  update public.reporting_lines set end_date = greatest(v_exit, start_date), reason = 'Employee left'
   where employee_id = p_employee_id and end_date is null;
  update public.departments set head_employee_id = null where head_employee_id = p_employee_id;
  update public.branches set head_employee_id = null where head_employee_id = p_employee_id;

  insert into public.employment_history (org_id, employee_id, event_type, from_value, to_value, effective_date, reason)
  values (v_emp.org_id, p_employee_id, 'status',
          jsonb_build_object('status', 'active'), jsonb_build_object('status', p_status),
          v_exit, btrim(p_reason));
end;
$$;

-- Bring an employee back. Optional new placement (p: department_id, designation_id,
-- branch_id, office_id, operation_id) when the old units are inactive.
create or replace function public.reactivate_employee(p_employee_id uuid, p_reason text, p jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
begin
  perform private.require_permission('employees.deactivate');
  select * into v_emp from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if v_emp.status = 'active' then
    raise exception 'This employee is already active' using errcode = '23514';
  end if;

  update public.employees set
    status = 'active', exit_date = null,
    department_id  = case when p ? 'department_id'  then private.jtext(p, 'department_id')::uuid  else department_id end,
    designation_id = case when p ? 'designation_id' then private.jtext(p, 'designation_id')::uuid else designation_id end,
    branch_id      = case when p ? 'branch_id'      then private.jtext(p, 'branch_id')::uuid      else branch_id end,
    office_id      = case when p ? 'office_id'      then private.jtext(p, 'office_id')::uuid      else office_id end,
    operation_id   = case when p ? 'operation_id'   then private.jtext(p, 'operation_id')::uuid   else operation_id end
  where id = p_employee_id;

  insert into public.employment_history (org_id, employee_id, event_type, from_value, to_value, effective_date, reason)
  values (v_emp.org_id, p_employee_id, 'status',
          jsonb_build_object('status', v_emp.status), private.placement_snapshot(p_employee_id),
          current_date, nullif(btrim(p_reason), ''));
end;
$$;

revoke all on function
  public.grant_portal_access(uuid, text, text, text, uuid),
  public.revoke_portal_access(uuid, text),
  public.change_portal_role(uuid, uuid),
  public.reset_user_password(uuid, text),
  public.deactivate_employee(uuid, text, date, text),
  public.reactivate_employee(uuid, text, jsonb)
from public, anon;
grant execute on function
  public.grant_portal_access(uuid, text, text, text, uuid),
  public.revoke_portal_access(uuid, text),
  public.change_portal_role(uuid, uuid),
  public.reset_user_password(uuid, text),
  public.deactivate_employee(uuid, text, date, text),
  public.reactivate_employee(uuid, text, jsonb)
to authenticated;

revoke all on function
  private.assert_password_ok(text), private.kill_sessions(uuid), private.set_auth_password(uuid, text),
  private.create_auth_user(text, text, text, text), private.revoke_portal_internal(uuid),
  private.assert_can_manage_login(uuid)
from public, anon, authenticated;
