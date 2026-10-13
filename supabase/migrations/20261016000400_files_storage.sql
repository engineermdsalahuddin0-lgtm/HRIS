-- =============================================================================
-- Olympus HRIS — Files: employee photo / signature / NID scan, company logo
--
-- Private buckets (no public URLs; the app uses short-lived signed URLs).
--   employee-files : {org_id}/{employee_id}/{photo|signature|nid}
--   org-assets     : {org_id}/logo
-- Access follows the same rules as the employee profile:
--   read  photo/signature : the person, Admin, anyone with employees.view
--   read  nid             : the person, Admin, roles ticked for NID
--   write photo/signature : the person, Admin, employees.edit
--   write nid             : Admin, roles allowed to edit NID
--   logo                  : read by the whole organization, written with settings.manage
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('employee-files', 'employee-files', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']),
  ('org-assets',     'org-assets',     false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.employee_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_org   uuid;
  v_emp   uuid;
  v_kind  text;
  v_self  boolean;
  v       record;
begin
  if array_length(v_parts, 1) <> 3
     or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$'
     or v_parts[3] not in ('photo', 'signature', 'nid') then
    return false;
  end if;
  v_org := v_parts[1]::uuid;
  v_emp := v_parts[2]::uuid;
  v_kind := v_parts[3];
  if v_org is distinct from private.current_org_id()
     or not exists (select 1 from public.employees where id = v_emp and org_id = v_org) then
    return false;
  end if;
  if private.is_org_admin() then
    return true;
  end if;
  v_self := v_emp = private.current_employee_id();

  if not p_write then
    if v_self then
      return true;
    end if;
    select * into v from private.viewer();
    if not v.can_list then
      return false;
    end if;
    return v_kind <> 'nid' or 'employee_sensitive.nid_number' = any (v.fields);
  end if;

  if v_kind = 'nid' then
    return 'employee_sensitive.nid_number' = any (private.editable_fields(v_emp));
  end if;
  return v_self or private.has_permission('employees.edit');
end;
$$;

create or replace function private.org_asset_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
begin
  if array_length(v_parts, 1) <> 2 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] <> 'logo' then
    return false;
  end if;
  if v_parts[1]::uuid is distinct from private.current_org_id() then
    return false;
  end if;
  return not p_write or private.has_permission('settings.manage');
end;
$$;

revoke all on function private.employee_file_access(text, boolean), private.org_asset_access(text, boolean)
  from public, anon;
grant execute on function private.employee_file_access(text, boolean), private.org_asset_access(text, boolean)
  to authenticated;

drop policy if exists olympus_employee_files_select on storage.objects;
drop policy if exists olympus_employee_files_insert on storage.objects;
drop policy if exists olympus_employee_files_update on storage.objects;
drop policy if exists olympus_employee_files_delete on storage.objects;
drop policy if exists olympus_org_assets_select on storage.objects;
drop policy if exists olympus_org_assets_insert on storage.objects;
drop policy if exists olympus_org_assets_update on storage.objects;
drop policy if exists olympus_org_assets_delete on storage.objects;

create policy olympus_employee_files_select on storage.objects for select to authenticated
  using (bucket_id = 'employee-files' and private.employee_file_access(name, false));
create policy olympus_employee_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'employee-files' and private.employee_file_access(name, true));
create policy olympus_employee_files_update on storage.objects for update to authenticated
  using (bucket_id = 'employee-files' and private.employee_file_access(name, true))
  with check (bucket_id = 'employee-files' and private.employee_file_access(name, true));
create policy olympus_employee_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'employee-files' and private.employee_file_access(name, true));

create policy olympus_org_assets_select on storage.objects for select to authenticated
  using (bucket_id = 'org-assets' and private.org_asset_access(name, false));
create policy olympus_org_assets_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'org-assets' and private.org_asset_access(name, true));
create policy olympus_org_assets_update on storage.objects for update to authenticated
  using (bucket_id = 'org-assets' and private.org_asset_access(name, true))
  with check (bucket_id = 'org-assets' and private.org_asset_access(name, true));
create policy olympus_org_assets_delete on storage.objects for delete to authenticated
  using (bucket_id = 'org-assets' and private.org_asset_access(name, true));
