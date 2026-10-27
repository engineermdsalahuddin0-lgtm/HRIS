-- =============================================================================
-- Communication C3: password requests ("Forgot password? Ask HR").
-- Module handbook: src/communication/architecture.md (section 4).
--
-- The login page sends the typed email or mobile number (no sign-in needed).
-- The answer is always the same, so it never reveals which accounts exist.
-- When the ID belongs to an active employee login, one pending request is
-- recorded for that company. Limits: 3 per ID per day, 10 per IP per hour
-- (hashes only, kept one day). HR with users.reset_password sees the list and
-- either resets (the existing reset_user_password: temporary password, change
-- forced at next login, sessions ended) or dismisses with a note.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.helpdesk_tickets') is null then
    raise exception 'Apply 20261102000200_comm_c2_helpdesk.sql first, then run this file again';
  end if;
end;
$guard$;

create table public.password_requests (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  user_id      uuid not null references public.user_profiles (id),
  employee_id  uuid not null,
  login_hint   text not null check (char_length(login_hint) <= 120),
  status       text not null default 'pending' check (status in ('pending', 'resolved', 'dismissed')),
  requested_at timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references public.user_profiles (id),
  note         text check (note is null or char_length(note) <= 300),
  updated_at   timestamptz not null default now(),
  constraint password_requests_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint password_requests_done check ((status = 'pending') = (resolved_at is null))
);
create unique index password_requests_one_pending on public.password_requests (user_id) where status = 'pending';
create index password_requests_org_idx on public.password_requests (org_id, status, requested_at desc);
create trigger no_delete before delete on public.password_requests
  for each row execute function private.prevent_delete();
create trigger audit after insert or update on public.password_requests
  for each row execute function private.audit_row_change();

create table private.password_request_log (
  id         bigserial primary key,
  login_hash text not null,
  ip_hash    text,
  created_at timestamptz not null default now()
);
create index password_request_log_created_idx on private.password_request_log (created_at);

-- "s***@alpha.test", "+8801*****678": enough for HR to recognise, nothing more.
create or replace function private.mask_login(p_login text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when position('@' in p_login) > 1 then left(p_login, 1) || '***' || substr(p_login, position('@' in p_login))
    else left(p_login, 5) || repeat('*', greatest(char_length(p_login) - 8, 0)) || right(p_login, 3)
  end
$$;

-- -----------------------------------------------------------------------------
-- API: the login page (anon)
-- -----------------------------------------------------------------------------
create or replace function public.request_password_help(p_login text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_raw    text := lower(btrim(coalesce(p_login, '')));
  v_login  text;
  v_hash   text;
  v_ip     text := nullif(btrim(split_part(coalesce(private.request_header('x-forwarded-for'), ''), ',', 1)), '');
  v_iphash text;
  v_user   uuid;
  m        record;
  v_reply  jsonb := jsonb_build_object('ok', true,
    'message', 'If this ID has an account, your HR has been told. They will give you a new password.');
begin
  if char_length(v_raw) = 0 or char_length(v_raw) > 200 then
    raise exception 'Enter your email or mobile number' using errcode = '22023';
  end if;
  if position('@' in v_raw) > 0 then
    v_login := v_raw;
  else
    begin
      v_login := private.normalize_bd_phone(v_raw);
    exception when others then
      v_login := null;
    end;
    if v_login is null then
      raise exception 'Enter a valid email or mobile number (01XXXXXXXXX)' using errcode = '22023';
    end if;
  end if;

  v_hash := encode(extensions.digest(v_login, 'sha256'), 'hex');
  v_iphash := case when v_ip is not null then encode(extensions.digest(v_ip, 'sha256'), 'hex') end;
  delete from private.password_request_log where created_at < now() - interval '1 day';
  if (select count(*) from private.password_request_log where login_hash = v_hash) >= 3
     or (v_iphash is not null and (select count(*) from private.password_request_log
                                   where ip_hash = v_iphash and created_at > now() - interval '1 hour') >= 10) then
    raise exception 'Too many requests; please try again later' using errcode = 'P0001';
  end if;
  insert into private.password_request_log (login_hash, ip_hash) values (v_hash, v_iphash);

  select up.id into v_user from public.user_profiles up
   where (position('@' in v_login) > 0 and lower(up.email) = v_login) or up.phone = v_login
   limit 1;
  if v_user is null then
    return v_reply;
  end if;
  select om.org_id, om.employee_id into m
  from public.org_members om join public.organizations o on o.id = om.org_id
  where om.user_id = v_user and om.status = 'active' and o.status = 'active' and om.employee_id is not null
  limit 1;
  if m.org_id is null then
    return v_reply;
  end if;
  insert into public.password_requests (org_id, user_id, employee_id, login_hint)
  values (m.org_id, v_user, m.employee_id, private.mask_login(v_login))
  on conflict (user_id) where status = 'pending' do nothing;
  return v_reply;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: HR (users.reset_password)
-- -----------------------------------------------------------------------------
create or replace function public.list_password_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('users.reset_password');
  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'pending', (select count(*) from public.password_requests where org_id = v_org and status = 'pending'),
      'resolved', (select count(*) from public.password_requests where org_id = v_org and status = 'resolved'
                    and resolved_at > now() - interval '30 days')),
    'requests', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'employee_id', r.employee_id, 'full_name', e.full_name, 'card_id', e.card_id,
               'department', (select d.name from public.departments d where d.id = e.department_id),
               'login_hint', r.login_hint, 'status', r.status, 'requested_at', r.requested_at,
               'resolved_at', r.resolved_at, 'resolved_by', (select up.full_name from public.user_profiles up where up.id = r.resolved_by),
               'note', r.note)
             order by r.status <> 'pending', r.requested_at desc)
      from public.password_requests r
      join public.employees e on e.id = r.employee_id
      where r.org_id = v_org and (r.status = 'pending' or r.requested_at > now() - interval '90 days')), '[]'::jsonb));
end;
$$;

create or replace function public.resolve_password_request(p_id uuid, p_password text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.password_requests;
begin
  perform private.require_permission('users.reset_password');
  select * into r from public.password_requests where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if r.status <> 'pending' then
    raise exception 'This request is already handled' using errcode = '23514';
  end if;
  -- Same checks as the profile page: permission, who may manage whose login, password rules.
  perform public.reset_user_password(r.employee_id, p_password);
  update public.password_requests set status = 'resolved', resolved_at = now(), resolved_by = auth.uid(), updated_at = now()
   where id = r.id;
end;
$$;

create or replace function public.dismiss_password_request(p_id uuid, p_note text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.password_requests;
begin
  perform private.require_permission('users.reset_password');
  select * into r from public.password_requests where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if r.status <> 'pending' then
    raise exception 'This request is already handled' using errcode = '23514';
  end if;
  if char_length(coalesce(btrim(p_note), '')) not between 3 and 300 then
    raise exception 'Give a short reason (3 to 300 characters)' using errcode = '22023';
  end if;
  update public.password_requests
     set status = 'dismissed', resolved_at = now(), resolved_by = auth.uid(), note = btrim(p_note), updated_at = now()
   where id = r.id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.password_requests enable row level security;
revoke all on table public.password_requests from anon, authenticated;
revoke all on table private.password_request_log from public, anon, authenticated;

revoke all on function
  public.request_password_help(text), public.list_password_requests(), public.resolve_password_request(uuid, text),
  public.dismiss_password_request(uuid, text)
from public, anon;
grant execute on function public.request_password_help(text) to anon, authenticated;
grant execute on function
  public.list_password_requests(), public.resolve_password_request(uuid, text), public.dismiss_password_request(uuid, text)
to authenticated;
revoke all on function private.mask_login(text) from public, anon, authenticated;
