-- =============================================================================
-- Olympus HRIS — Part 1, Step 1: Foundation core
-- Private schema, shared trigger helpers, append-only audit log.
-- =============================================================================

-- Functions in `private` are never exposed through the REST API (only `public` is).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
alter default privileges in schema private revoke execute on functions from public;

-- -----------------------------------------------------------------------------
-- Row metadata: created_at/by are fixed at insert, updated_at/by on every write.
-- Values sent by the client are ignored.
-- -----------------------------------------------------------------------------
create or replace function private.set_row_meta()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.created_by := coalesce(auth.uid(), new.created_by);
  else
    new.created_at := old.created_at;
    new.created_by := old.created_by;
  end if;
  new.updated_at := now();
  new.updated_by := coalesce(auth.uid(), new.updated_by);
  return new;
end;
$$;

-- Soft delete only: business rows are never physically removed.
create or replace function private.prevent_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Rows in % cannot be deleted; set status instead', tg_table_name
    using errcode = '42501';
end;
$$;

-- -----------------------------------------------------------------------------
-- Bangladesh mobile numbers are stored as +8801XXXXXXXXX so one number can
-- never create two accounts. Accepts 01XXXXXXXXX, 8801XXXXXXXXX, +8801XXXXXXXXX.
-- -----------------------------------------------------------------------------
create or replace function private.normalize_bd_phone(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text;
begin
  if p_phone is null or btrim(p_phone) = '' then
    return null;
  end if;
  v := regexp_replace(p_phone, '[\s()-]', '', 'g');
  if v ~ '^01[3-9][0-9]{8}$' then
    return '+88' || v;
  elsif v ~ '^8801[3-9][0-9]{8}$' then
    return '+' || v;
  elsif v ~ '^\+8801[3-9][0-9]{8}$' then
    return v;
  end if;
  raise exception 'Invalid phone number. Use 01XXXXXXXXX or +8801XXXXXXXXX'
    using errcode = '22023';
end;
$$;

-- =============================================================================
-- Audit log (append-only, minimum 3-year retention)
-- =============================================================================
create table public.audit_logs (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid,               -- null for platform-level events
  actor_user_id uuid,               -- null when done by the system
  action        text not null,      -- insert / update / delete, or a named event
  entity        text not null,      -- table or domain object name
  entity_id     uuid,
  old_value     jsonb,
  new_value     jsonb,
  ip            text,
  user_agent    text,
  created_at    timestamptz not null default now()
);

create index audit_logs_org_created_idx   on public.audit_logs (org_id, created_at desc);
create index audit_logs_actor_created_idx on public.audit_logs (actor_user_id, created_at desc);
create index audit_logs_entity_idx        on public.audit_logs (entity, entity_id);

create or replace function private.request_header(p_name text)
returns text
language sql
stable
set search_path = ''
as $$
  select nullif(nullif(current_setting('request.headers', true), '')::json ->> p_name, '')
$$;

create or replace function private.write_audit(
  p_org_id    uuid,
  p_action    text,
  p_entity    text,
  p_entity_id uuid,
  p_old       jsonb,
  p_new       jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_logs (org_id, actor_user_id, action, entity, entity_id,
                                 old_value, new_value, ip, user_agent)
  values (p_org_id, auth.uid(), p_action, p_entity, p_entity_id, p_old, p_new,
          nullif(btrim(split_part(coalesce(private.request_header('x-forwarded-for'), ''), ',', 1)), ''),
          private.request_header('user-agent'));
end;
$$;

-- Generic row-change audit trigger. Runs in the same transaction as the change.
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb;
  v_org uuid;
begin
  -- Ignore no-op updates (only timestamps changed).
  if tg_op = 'UPDATE'
     and (v_old - 'updated_at' - 'updated_by') = (v_new - 'updated_at' - 'updated_by') then
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

-- Nobody edits or deletes audit rows. The only exception is the system purge of
-- rows older than 3 years, which sets a transaction-local flag.
create or replace function private.audit_logs_guard_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE'
     and coalesce(current_setting('olympus.audit_purge', true), '') = 'on'
     and old.created_at < now() - interval '3 years' then
    return old;
  end if;
  raise exception 'audit_logs is append-only' using errcode = '42501';
end;
$$;

create or replace function private.audit_logs_guard_truncate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only' using errcode = '42501';
end;
$$;

create trigger audit_logs_append_only
  before update or delete on public.audit_logs
  for each row execute function private.audit_logs_guard_row();

create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function private.audit_logs_guard_truncate();

-- System-only retention purge. Not callable by any API role.
-- Schedule with pg_cron, e.g.:
--   select cron.schedule('audit-purge', '0 3 * * 0', 'select private.purge_expired_audit_logs()');
create or replace function private.purge_expired_audit_logs()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform set_config('olympus.audit_purge', 'on', true);
  delete from public.audit_logs where created_at < now() - interval '3 years';
  get diagnostics v_count = row_count;
  perform set_config('olympus.audit_purge', 'off', true);
  return v_count;
end;
$$;

alter table public.audit_logs enable row level security;
revoke all on table public.audit_logs from anon, authenticated;
grant select on table public.audit_logs to authenticated;
-- Select policy is created in the tenancy migration (needs permission helpers).
