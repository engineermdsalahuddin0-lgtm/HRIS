-- =============================================================================
-- Olympus HRIS — Part 1, Step 2: Login support
-- =============================================================================

-- Called by the app right after a successful sign-in.
create or replace function public.record_login()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  -- Skip audit noise: last_login_at alone is not an important change.
  update public.user_profiles set last_login_at = now() where id = auth.uid();
end;
$$;

-- Called by the app after supabase.auth.updateUser({ password }) succeeds.
-- Only ever clears the flag for the caller themselves.
create or replace function public.complete_password_change()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;
  update public.user_profiles set must_change_password = false where id = auth.uid();
  perform private.write_audit(private.current_org_id(), 'password.changed', 'user_profiles',
                              auth.uid(), null, null);
end;
$$;

-- last_login_at changes on every sign-in; keep it out of the audit log.
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

  v_row := coalesce(v_new, v_old);
  v_org := case
             when tg_table_name = 'organizations' then (v_row ->> 'id')::uuid
             else (v_row ->> 'org_id')::uuid
           end;

  perform private.write_audit(
    v_org,
    lower(tg_op),
    tg_table_name,
    case when v_row ? 'id' then (v_row ->> 'id')::uuid end,
    v_old,
    v_new
  );
  return null;
end;
$$;

revoke all on function public.record_login(), public.complete_password_change() from public, anon;
grant execute on function public.record_login(), public.complete_password_change() to authenticated;
revoke all on function private.audit_row_change() from public, anon, authenticated;
