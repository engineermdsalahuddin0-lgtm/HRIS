-- =============================================================================
-- Communication C2: helpdesk (internal support tickets).
-- Module handbook: src/communication/architecture.md (sections 1, 3).
--
-- Any portal user raises a ticket (subject, category, priority, description,
-- files). Each category has a handler (an employee whose role holds
-- helpdesk.handle or helpdesk.manage); a new ticket goes to that handler, or
-- waits unassigned for helpdesk.manage. Confidential categories (HR Query,
-- Payroll Issue by default) may only be handled by helpdesk.manage.
-- Visibility: requester (public replies), assignee and helpdesk.manage (also
-- internal notes). Status open -> in_progress -> waiting -> in_progress ->
-- resolved -> closed. On a resolved ticket the requester rates 1-5 (closed) or
-- reopens with a reason; with no action for N working days (default 3) it
-- closes itself. Closed tickets never reopen.
-- SLA in office time: the company's default shift (fallback 09:00-18:00),
-- without weekly off days and company-wide holidays, in the company time zone.
-- While waiting for the employee the resolution clock stops (paused minutes
-- push the due time). Breach and auto-close are computed when tickets are read,
-- so no scheduled job is needed.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.notices') is null then
    raise exception 'Apply 20261102000100_comm_c1_notices.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Permissions and defaults
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('helpdesk.manage', 'communication', 'Helpdesk setup, see and assign every ticket (also confidential ones)', false),
  ('helpdesk.handle', 'communication', 'Be a helpdesk handler: work the tickets assigned to you',              false)
on conflict (key) do nothing;

create table public.helpdesk_settings (
  org_id          uuid primary key references public.organizations (id),
  -- Office minutes per priority: response = first answer, resolution = solved.
  sla             jsonb not null default '{"critical":{"response":60,"resolution":240},"high":{"response":240,"resolution":1440},
                                           "medium":{"response":1440,"resolution":4320},"low":{"response":4320,"resolution":10080}}',
  auto_close_days smallint not null default 3 check (auto_close_days between 1 and 30),
  next_ticket_no  integer not null default 1 check (next_ticket_no >= 1),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references public.user_profiles (id),
  updated_by      uuid references public.user_profiles (id)
);
create trigger set_row_meta before insert or update on public.helpdesk_settings
  for each row execute function private.set_row_meta();

create table public.helpdesk_categories (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null references public.organizations (id),
  name                text not null check (char_length(btrim(name)) between 2 and 80),
  confidential        boolean not null default false,
  handler_employee_id uuid,
  status              text not null default 'active' check (status in ('active', 'inactive')),
  sort                smallint not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id),
  updated_by          uuid references public.user_profiles (id),
  constraint helpdesk_categories_org_id_id_uq unique (org_id, id),
  constraint helpdesk_categories_handler_fk foreign key (org_id, handler_employee_id) references public.employees (org_id, id)
);
create unique index helpdesk_categories_name_uq on public.helpdesk_categories (org_id, lower(name));
select private.attach_standard_triggers('public.helpdesk_categories');

create or replace function private.seed_helpdesk_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.helpdesk_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.helpdesk_categories (org_id, name, confidential, sort)
  select p_org_id, c.name, c.confidential, c.sort
  from (values ('IT Support', false, 1), ('HR Query', true, 2), ('Payroll Issue', true, 3), ('Leave Query', false, 4),
               ('Asset Request', false, 5), ('Facilities', false, 6), ('Other', false, 7)) as c (name, confidential, sort)
  where not exists (select 1 from public.helpdesk_categories x where x.org_id = p_org_id);
end;
$$;

create or replace function private.seed_communication_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['notices.manage', 'helpdesk.manage', 'helpdesk.handle']
    when 'manager'    then array['notices.department']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
  perform private.seed_helpdesk_defaults(p_org_id);
end;
$$;

select private.seed_communication_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Tickets and the thread
-- -----------------------------------------------------------------------------
create table public.helpdesk_tickets (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid not null references public.organizations (id),
  ticket_no             integer not null,
  subject               text not null check (char_length(btrim(subject)) between 3 and 200),
  description           text not null check (char_length(btrim(description)) between 1 and 10000),
  category_id           uuid not null,
  priority              text not null default 'medium' check (priority in ('low', 'medium', 'high', 'critical')),
  requester_employee_id uuid not null,
  assignee_employee_id  uuid,
  status                text not null default 'open' check (status in ('open', 'in_progress', 'waiting', 'resolved', 'closed')),
  response_due_at       timestamptz not null,
  resolution_due_at     timestamptz not null,
  first_response_at     timestamptz,
  waiting_since         timestamptz,
  paused_minutes        integer not null default 0 check (paused_minutes >= 0),
  resolved_at           timestamptz,
  closed_at             timestamptz,
  closed_reason         text check (closed_reason is null or closed_reason in ('rated', 'auto', 'manual')),
  rating                smallint check (rating is null or rating between 1 and 5),
  rating_comment        text check (rating_comment is null or char_length(rating_comment) <= 1000),
  reopen_count          smallint not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid references public.user_profiles (id),
  updated_by            uuid references public.user_profiles (id),
  constraint helpdesk_tickets_org_id_id_uq unique (org_id, id),
  constraint helpdesk_tickets_no_uq unique (org_id, ticket_no),
  constraint helpdesk_tickets_category_fk foreign key (org_id, category_id) references public.helpdesk_categories (org_id, id),
  constraint helpdesk_tickets_requester_fk foreign key (org_id, requester_employee_id) references public.employees (org_id, id),
  constraint helpdesk_tickets_assignee_fk foreign key (org_id, assignee_employee_id) references public.employees (org_id, id),
  constraint helpdesk_tickets_waiting check ((status = 'waiting') = (waiting_since is not null)),
  constraint helpdesk_tickets_resolved check (status not in ('resolved', 'closed') or resolved_at is not null or closed_reason = 'manual'),
  constraint helpdesk_tickets_closed check ((status = 'closed') = (closed_at is not null))
);
create index helpdesk_tickets_requester_idx on public.helpdesk_tickets (requester_employee_id, created_at desc);
create index helpdesk_tickets_assignee_idx on public.helpdesk_tickets (assignee_employee_id, status);
create index helpdesk_tickets_org_status_idx on public.helpdesk_tickets (org_id, status);
select private.attach_standard_triggers('public.helpdesk_tickets');

-- Replies, internal notes and events. Append-only; message text is not copied into the audit log.
create table public.helpdesk_messages (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null,
  ticket_id          uuid not null,
  kind               text not null check (kind in ('reply', 'note', 'event')),
  author_employee_id uuid,
  body               text not null default '' check (char_length(body) <= 10000),
  attachments        jsonb not null default '[]' check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 5),
  created_at         timestamptz not null default now(),
  constraint helpdesk_messages_ticket_fk foreign key (org_id, ticket_id) references public.helpdesk_tickets (org_id, id),
  constraint helpdesk_messages_author_fk foreign key (org_id, author_employee_id) references public.employees (org_id, id),
  constraint helpdesk_messages_not_empty check (kind = 'event' or char_length(btrim(body)) > 0 or jsonb_array_length(attachments) > 0)
);
create index helpdesk_messages_ticket_idx on public.helpdesk_messages (ticket_id, created_at);
create trigger helpdesk_messages_append_only before update or delete on public.helpdesk_messages
  for each row execute function private.history_append_only();

-- -----------------------------------------------------------------------------
-- Office time (the SLA clock). Computed only here; the UI shows the results.
-- -----------------------------------------------------------------------------
-- Office day window of the company: default shift (unless it crosses midnight), else 09:00-18:00.
create or replace function private.office_window(p_org_id uuid)
returns table (day_start time, day_end time, off_days smallint[], tz text)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(case when not s.crosses_midnight then s.start_time end, time '09:00'),
         coalesce(case when not s.crosses_midnight then s.end_time end, time '18:00'),
         coalesce(w.weekly_off_days, '{5}'::smallint[]),
         o.timezone
  from public.organizations o
  left join public.org_work_settings w on w.org_id = o.id
  left join public.shifts s on s.id = w.default_shift_id
  where o.id = p_org_id
$$;

create or replace function private.is_office_day(p_org_id uuid, p_day date, p_off smallint[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select extract(dow from p_day)::smallint <> all (p_off)
     and not exists (select 1 from public.holidays h
                     where h.org_id = p_org_id and h.date = p_day and h.status = 'active' and h.branch_ids = '{}')
$$;

-- p_from plus p_minutes of office time.
create or replace function private.add_office_minutes(p_org_id uuid, p_from timestamptz, p_minutes integer)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w         record;
  v_local   timestamp;
  v_day     date;
  v_start   timestamp;
  v_end     timestamp;
  v_cur     timestamp;
  v_avail   numeric;
  v_left    numeric := greatest(coalesce(p_minutes, 0), 0);
  i         integer := 0;
begin
  select * into w from private.office_window(p_org_id);
  v_local := p_from at time zone w.tz;
  v_day := v_local::date;
  while i < 1000 loop
    if private.is_office_day(p_org_id, v_day, w.off_days) then
      v_start := v_day + w.day_start;
      v_end := v_day + w.day_end;
      v_cur := greatest(v_local, v_start);
      if v_cur < v_end then
        v_avail := extract(epoch from v_end - v_cur) / 60;
        if v_left <= v_avail then
          return (v_cur + v_left * interval '1 minute') at time zone w.tz;
        end if;
        v_left := v_left - v_avail;
      end if;
    end if;
    v_day := v_day + 1;
    v_local := v_day::timestamp;
    i := i + 1;
  end loop;
  return p_from + p_minutes * interval '1 minute';
end;
$$;

-- Office minutes between two moments (0 when p_to is not after p_from).
create or replace function private.office_minutes_between(p_org_id uuid, p_from timestamptz, p_to timestamptz)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w       record;
  v_from  timestamp;
  v_to    timestamp;
  v_day   date;
  v_total numeric := 0;
  v_a     timestamp;
  v_b     timestamp;
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return 0;
  end if;
  select * into w from private.office_window(p_org_id);
  v_from := p_from at time zone w.tz;
  v_to := p_to at time zone w.tz;
  v_day := v_from::date;
  while v_day <= v_to::date and v_day < v_from::date + 1000 loop
    if private.is_office_day(p_org_id, v_day, w.off_days) then
      v_a := greatest(v_from, v_day + w.day_start);
      v_b := least(v_to, v_day + w.day_end);
      if v_b > v_a then
        v_total := v_total + extract(epoch from v_b - v_a) / 60;
      end if;
    end if;
    v_day := v_day + 1;
  end loop;
  return floor(v_total)::integer;
end;
$$;

-- Office days after p_from (exclusive) up to p_to (inclusive), in the company calendar.
create or replace function private.office_days_between(p_org_id uuid, p_from date, p_to date)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from generate_series(p_from + 1, p_to, interval '1 day') d,
       private.office_window(p_org_id) w
  where p_to > p_from and private.is_office_day(p_org_id, d::date, w.off_days)
$$;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
-- Does this employee's active login hold the permission (Admin holds all)?
create or replace function private.employee_has_permission(p_employee_id uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.org_members m
    join public.roles r on r.id = m.role_id
    where m.employee_id = p_employee_id and m.status = 'active'
      and (r.system_key = 'admin'
           or exists (select 1 from public.role_permissions rp where rp.role_id = r.id and rp.permission_key = p_key)))
$$;

-- Handlers need helpdesk.handle (or manage); confidential categories need helpdesk.manage.
create or replace function private.check_helpdesk_handler(p_org_id uuid, p_employee_id uuid, p_confidential boolean)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_employee_id is null then
    return;
  end if;
  if not exists (select 1 from public.employees e where e.id = p_employee_id and e.org_id = p_org_id and e.status = 'active') then
    raise exception 'Choose an active employee of your company' using errcode = '22023';
  end if;
  if p_confidential then
    if not private.employee_has_permission(p_employee_id, 'helpdesk.manage') then
      raise exception 'Confidential tickets can only go to someone with helpdesk.manage (HR)' using errcode = '23514';
    end if;
  elsif not (private.employee_has_permission(p_employee_id, 'helpdesk.handle')
             or private.employee_has_permission(p_employee_id, 'helpdesk.manage')) then
    raise exception 'This person''s role does not have helpdesk.handle; give it in Roles & access first' using errcode = '23514';
  end if;
end;
$$;

-- 'manage' | 'handler' | 'requester' | null for the caller on this ticket.
create or replace function private.ticket_access(t public.helpdesk_tickets)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when t.org_id is distinct from private.current_org_id() then null
    when private.has_permission('helpdesk.manage') then 'manage'
    when t.assignee_employee_id = private.current_employee_id() then 'handler'
    when t.requester_employee_id = private.current_employee_id() then 'requester'
  end
$$;

create or replace function private.load_ticket(p_id uuid, p_for_update boolean default false)
returns public.helpdesk_tickets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.helpdesk_tickets;
begin
  if p_for_update then
    select * into v from public.helpdesk_tickets where id = p_id for update;
  else
    select * into v from public.helpdesk_tickets where id = p_id;
  end if;
  if not found or private.ticket_access(v) is null then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

create or replace function private.sla_minutes(p_org_id uuid, p_priority text, p_kind text)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((s.sla -> p_priority ->> p_kind)::integer, case p_kind when 'response' then 1440 else 4320 end)
  from public.helpdesk_settings s where s.org_id = p_org_id
$$;

-- SLA figures now (breaches, office minutes left; the resolution clock stops while waiting).
create or replace function private.ticket_sla(t public.helpdesk_tickets)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_resp_end  timestamptz := coalesce(t.first_response_at, case when t.status in ('resolved', 'closed') then coalesce(t.resolved_at, t.closed_at) end, now());
  v_res_end   timestamptz := coalesce(t.resolved_at, case when t.status = 'closed' then t.closed_at end, now());
  v_paused    boolean := t.status = 'waiting';
  v_done      boolean := t.status in ('resolved', 'closed');
  v_left      integer;
begin
  if not v_done and not v_paused then
    v_left := case when t.resolution_due_at > now() then private.office_minutes_between(t.org_id, now(), t.resolution_due_at)
                   else -private.office_minutes_between(t.org_id, t.resolution_due_at, now()) end;
  end if;
  return jsonb_build_object(
    'response_due_at', t.response_due_at, 'resolution_due_at', t.resolution_due_at,
    'response_breached', v_resp_end > t.response_due_at,
    'resolution_breached', not v_paused and v_res_end > t.resolution_due_at,
    'paused', v_paused, 'resolution_left_minutes', v_left);
end;
$$;

create or replace function private.ticket_event(t public.helpdesk_tickets, p_text text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.helpdesk_messages (org_id, ticket_id, kind, author_employee_id, body)
  values (t.org_id, t.id, 'event', private.current_employee_id(), left(p_text, 10000))
$$;

-- One status change with its side effects (response time, pause, resolve times).
create or replace function private.ticket_set_status(p_id uuid, p_status text, p_note text)
returns public.helpdesk_tickets
language plpgsql
security definer
set search_path = ''
as $$
declare
  t        public.helpdesk_tickets;
  v_paused integer := 0;
  v_label  text;
begin
  select * into t from public.helpdesk_tickets where id = p_id for update;
  if t.status = p_status then
    return t;
  end if;
  if t.status = 'closed' then
    raise exception 'This ticket is closed; raise a new one' using errcode = '23514';
  end if;
  if p_status not in ('in_progress', 'waiting', 'resolved', 'closed') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  if t.status = 'waiting' then
    v_paused := private.office_minutes_between(t.org_id, t.waiting_since, now());
  end if;
  update public.helpdesk_tickets
     set status = p_status,
         waiting_since = case when p_status = 'waiting' then now() end,
         paused_minutes = paused_minutes + v_paused,
         resolution_due_at = case when v_paused > 0
                                  then private.add_office_minutes(org_id, created_at, private.sla_minutes(org_id, priority, 'resolution') + paused_minutes + v_paused)
                                  else resolution_due_at end,
         resolved_at = case when p_status = 'resolved' then now() when p_status = 'closed' then resolved_at end,
         closed_at = case when p_status = 'closed' then now() end,
         closed_reason = case when p_status = 'closed' then 'manual' end
   where id = p_id returning * into t;
  v_label := case p_status when 'in_progress' then 'In progress' when 'waiting' then 'Waiting for the employee'
                           when 'resolved' then 'Resolved' else 'Closed' end;
  perform private.ticket_event(t, 'Status: ' || v_label || coalesce(' — ' || nullif(btrim(p_note), ''), ''));
  return t;
end;
$$;

-- Resolved tickets without an answer for N office days close themselves (run when tickets are listed).
create or replace function private.auto_close_tickets(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days integer := (select auto_close_days from public.helpdesk_settings where org_id = p_org_id);
  v_tz   text := (select timezone from public.organizations where id = p_org_id);
  t      public.helpdesk_tickets;
begin
  for t in
    select * from public.helpdesk_tickets
    where org_id = p_org_id and status = 'resolved'
      and private.office_days_between(p_org_id, (resolved_at at time zone v_tz)::date, private.org_today(p_org_id)) >= coalesce(v_days, 3)
    for update skip locked
  loop
    update public.helpdesk_tickets set status = 'closed', closed_at = now(), closed_reason = 'auto' where id = t.id;
    perform private.ticket_event(t, 'Closed automatically after ' || coalesce(v_days, 3) || ' working days without a reply');
  end loop;
end;
$$;

-- Files given with a message: [{path, name, type}], under helpdesk-files/{org}/{ticket}/.
create or replace function private.clean_ticket_files(t public.helpdesk_tickets, p_files jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  f jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if p_files is null or jsonb_typeof(p_files) <> 'array' then
    return v_out;
  end if;
  if jsonb_array_length(p_files) > 5 then
    raise exception 'At most 5 files per message' using errcode = '22023';
  end if;
  for f in select * from jsonb_array_elements(p_files) loop
    if coalesce(f ->> 'path', '') not like t.org_id || '/' || t.id || '/%'
       or coalesce(f ->> 'type', '') not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')
       or char_length(coalesce(f ->> 'name', '')) not between 1 and 200 then
      raise exception 'A file is not valid for this ticket' using errcode = '22023';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object('path', f ->> 'path', 'name', f ->> 'name', 'type', f ->> 'type'));
  end loop;
  return v_out;
end;
$$;

create or replace function private.ticket_row_json(t public.helpdesk_tickets)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'ticket_no', t.ticket_no, 'subject', t.subject, 'priority', t.priority, 'status', t.status,
    'category_id', t.category_id, 'category', c.name, 'confidential', c.confidential,
    'requester_employee_id', t.requester_employee_id, 'requester', rq.full_name,
    'assignee_employee_id', t.assignee_employee_id, 'assignee', asg.full_name,
    'created_at', t.created_at, 'updated_at', t.updated_at, 'resolved_at', t.resolved_at, 'closed_at', t.closed_at,
    'closed_reason', t.closed_reason, 'rating', t.rating, 'response_due_at', t.response_due_at,
    'resolution_due_at', t.resolution_due_at,
    'response_breached', coalesce(t.first_response_at, case when t.status in ('resolved', 'closed') then coalesce(t.resolved_at, t.closed_at) end, now()) > t.response_due_at,
    'resolution_breached', t.status <> 'waiting' and coalesce(t.resolved_at, case when t.status = 'closed' then t.closed_at end, now()) > t.resolution_due_at)
  from public.helpdesk_categories c, public.employees rq
  left join public.employees asg on asg.id = t.assignee_employee_id
  where c.id = t.category_id and rq.id = t.requester_employee_id
$$;

-- -----------------------------------------------------------------------------
-- API: everyone
-- -----------------------------------------------------------------------------
create or replace function public.list_helpdesk_categories()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'confidential', c.confidential) order by c.sort, c.name), '[]'::jsonb)
  from public.helpdesk_categories c
  where c.org_id = private.current_org_id() and c.status = 'active'
$$;

create or replace function public.create_ticket(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org      uuid := private.current_org_id();
  v_me       uuid := private.current_employee_id();
  v_cat      public.helpdesk_categories;
  v_priority text := coalesce(private.jtext(p, 'priority'), 'medium');
  v_no       integer;
  v_handler  uuid;
  v_now      timestamptz := now();
  t          public.helpdesk_tickets;
begin
  if v_org is null or v_me is null then
    raise exception 'Only people with an employee profile can raise tickets' using errcode = '42501';
  end if;
  if char_length(coalesce(btrim(p ->> 'subject'), '')) < 3 then
    raise exception 'The subject needs at least 3 characters' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'description'), '')) = 0 then
    raise exception 'Describe the problem' using errcode = '22023';
  end if;
  if v_priority not in ('low', 'medium', 'high', 'critical') then
    raise exception 'Unknown priority' using errcode = '22023';
  end if;
  select * into v_cat from public.helpdesk_categories
   where id = nullif(p ->> 'category_id', '')::uuid and org_id = v_org and status = 'active';
  if not found then
    raise exception 'Choose a category' using errcode = '22023';
  end if;
  if (select count(*) from public.helpdesk_tickets where requester_employee_id = v_me and created_at > now() - interval '1 day') >= 20 then
    raise exception 'You raised 20 tickets today; please wait until tomorrow' using errcode = '23514';
  end if;
  perform private.seed_helpdesk_defaults(v_org);
  update public.helpdesk_settings set next_ticket_no = next_ticket_no + 1 where org_id = v_org
  returning next_ticket_no - 1 into v_no;

  -- Route to the category's handler while that person still qualifies; otherwise the HR queue.
  v_handler := v_cat.handler_employee_id;
  if v_handler is not null then
    begin
      perform private.check_helpdesk_handler(v_org, v_handler, v_cat.confidential);
    exception when others then
      v_handler := null;
    end;
  end if;

  insert into public.helpdesk_tickets (org_id, ticket_no, subject, description, category_id, priority, requester_employee_id,
                                       assignee_employee_id, response_due_at, resolution_due_at, created_at)
  values (v_org, v_no, btrim(p ->> 'subject'), btrim(p ->> 'description'), v_cat.id, v_priority, v_me, v_handler,
          private.add_office_minutes(v_org, v_now, private.sla_minutes(v_org, v_priority, 'response')),
          private.add_office_minutes(v_org, v_now, private.sla_minutes(v_org, v_priority, 'resolution')), v_now)
  returning * into t;
  perform private.ticket_event(t, case when v_handler is null then 'Raised; waiting in the HR queue'
                                       else 'Raised; assigned to ' || (select full_name from public.employees where id = v_handler) end);
  return jsonb_build_object('id', t.id, 'ticket_no', t.ticket_no, 'assigned', v_handler is not null);
end;
$$;

-- p_scope: mine (raised by me) | assigned (to me) | all (helpdesk.manage).
create or replace function public.list_tickets(p_scope text default 'mine')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_me     uuid := private.current_employee_id();
  v_manage boolean := private.has_permission('helpdesk.manage');
  v_handle boolean := v_manage or private.has_permission('helpdesk.handle');
  v_today  date;
begin
  if v_org is null then
    return jsonb_build_object('tickets', '[]'::jsonb);
  end if;
  if p_scope = 'all' and not v_manage then
    raise exception 'You do not have permission for this action (helpdesk.manage)' using errcode = '42501';
  end if;
  if p_scope = 'assigned' and not v_handle then
    raise exception 'You do not have permission for this action (helpdesk.handle)' using errcode = '42501';
  end if;
  if p_scope not in ('mine', 'assigned', 'all') then
    raise exception 'Unknown list' using errcode = '22023';
  end if;
  perform private.auto_close_tickets(v_org);
  v_today := private.org_today(v_org);
  return (
    with scoped as (
      select t.* from public.helpdesk_tickets t
      where t.org_id = v_org
        and case p_scope when 'mine' then t.requester_employee_id = v_me
                         when 'assigned' then t.assignee_employee_id = v_me
                         else true end
    ), kpi_base as (
      -- KPIs cover the widest list the caller may see.
      select t.* from public.helpdesk_tickets t
      where t.org_id = v_org
        and (v_manage or t.assignee_employee_id = v_me or t.requester_employee_id = v_me)
    )
    select jsonb_build_object(
      'scope', p_scope,
      'can_handle', v_handle, 'can_manage', v_manage,
      'kpis', jsonb_build_object(
        'open', (select count(*) from kpi_base where status = 'open'),
        'in_progress', (select count(*) from kpi_base where status in ('in_progress', 'waiting')),
        'sla_breach', (select count(*) from kpi_base t where status not in ('resolved', 'closed')
                         and ((t.first_response_at is null and now() > t.response_due_at)
                              or (t.status <> 'waiting' and now() > t.resolution_due_at))),
        'my_tickets', (select count(*) from kpi_base where requester_employee_id = v_me and status <> 'closed'),
        'resolved_today', (select count(*) from kpi_base t
                           where t.resolved_at is not null
                             and (t.resolved_at at time zone (select timezone from public.organizations where id = v_org))::date = v_today)),
      'tickets', coalesce((select jsonb_agg(private.ticket_row_json(t) order by
                             (t.status in ('resolved', 'closed')), t.created_at desc)
                           from public.helpdesk_tickets t
                           where t.id in (select s.id from scoped s order by s.created_at desc limit 500)), '[]'::jsonb))
  );
end;
$$;

create or replace function public.get_ticket(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t        public.helpdesk_tickets := private.load_ticket(p_id);
  v_access text := private.ticket_access(t);
  v_staff  boolean := v_access in ('manage', 'handler');
  v_me     uuid := private.current_employee_id();
  v_mine   boolean := t.requester_employee_id = v_me;
begin
  perform private.auto_close_tickets(t.org_id);
  select * into t from public.helpdesk_tickets where id = p_id;
  return private.ticket_row_json(t) || jsonb_build_object(
    'description', t.description, 'rating_comment', t.rating_comment, 'reopen_count', t.reopen_count,
    'first_response_at', t.first_response_at, 'access', v_access,
    'sla', private.ticket_sla(t),
    'can', jsonb_build_object(
      'reply', t.status <> 'closed' and (v_staff or t.status <> 'resolved'),
      'note', v_staff and t.status <> 'closed',
      'status', v_staff and t.status <> 'closed',
      'assign', v_access = 'manage' and t.status <> 'closed',
      'close', v_access = 'manage' and t.status <> 'closed',
      'rate', v_mine and t.status = 'resolved',
      'reopen', v_mine and t.status = 'resolved'),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'kind', m.kind, 'body', m.body, 'attachments', m.attachments,
                                          'created_at', m.created_at, 'author', e.full_name,
                                          'mine', m.author_employee_id = v_me,
                                          'from_staff', m.author_employee_id is distinct from t.requester_employee_id)
                       order by m.created_at, m.id)
      from public.helpdesk_messages m
      left join public.employees e on e.id = m.author_employee_id
      where m.ticket_id = t.id and (v_staff or m.kind <> 'note')), '[]'::jsonb));
end;
$$;

-- p: {body, internal, attachments [{path,name,type}], status}. Staff may add internal notes and change status.
create or replace function public.reply_ticket(p_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t         public.helpdesk_tickets := private.load_ticket(p_id, true);
  v_access  text := private.ticket_access(t);
  v_staff   boolean := v_access in ('manage', 'handler');
  v_note    boolean := coalesce((p ->> 'internal')::boolean, false);
  v_body    text := coalesce(btrim(p ->> 'body'), '');
  v_files   jsonb := private.clean_ticket_files(t, p -> 'attachments');
  v_status  text := private.jtext(p, 'status');
begin
  if t.status = 'closed' then
    raise exception 'This ticket is closed; raise a new one' using errcode = '23514';
  end if;
  if char_length(v_body) = 0 and jsonb_array_length(v_files) = 0 then
    raise exception 'Write a message or add a file' using errcode = '22023';
  end if;
  if char_length(v_body) > 10000 then
    raise exception 'The message is too long' using errcode = '22023';
  end if;
  if not v_staff then
    if v_note or v_status is not null then
      raise exception 'Only the handler can add internal notes or change the status' using errcode = '42501';
    end if;
    if t.status = 'resolved' then
      raise exception 'This ticket is resolved: rate it, or reopen it with a reason' using errcode = '23514';
    end if;
  end if;

  insert into public.helpdesk_messages (org_id, ticket_id, kind, author_employee_id, body, attachments)
  values (t.org_id, t.id, case when v_note then 'note' else 'reply' end, private.current_employee_id(), v_body, v_files);

  if v_staff and not v_note then
    update public.helpdesk_tickets set first_response_at = coalesce(first_response_at, now()),
                                       status = case when status = 'open' then 'in_progress' else status end
     where id = t.id;
  elsif not v_staff and t.status = 'waiting' then
    -- The employee answered: the clock runs again.
    perform private.ticket_set_status(t.id, 'in_progress', 'the employee replied');
  end if;
  if v_staff and v_status is not null then
    if v_status = 'closed' and v_access <> 'manage' then
      raise exception 'Only helpdesk managers close tickets directly' using errcode = '42501';
    end if;
    perform private.ticket_set_status(t.id, v_status, null);
  end if;
end;
$$;

create or replace function public.set_ticket_status(p_id uuid, p_status text, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t        public.helpdesk_tickets := private.load_ticket(p_id, true);
  v_access text := private.ticket_access(t);
begin
  if v_access not in ('manage', 'handler') then
    raise exception 'Only the handler can change the status' using errcode = '42501';
  end if;
  if p_status = 'closed' and v_access <> 'manage' then
    raise exception 'Only helpdesk managers close tickets directly' using errcode = '42501';
  end if;
  if p_status = 'closed' and char_length(coalesce(btrim(p_note), '')) < 3 then
    raise exception 'Give a short reason for closing' using errcode = '22023';
  end if;
  update public.helpdesk_tickets set first_response_at = coalesce(first_response_at, now()) where id = t.id;
  perform private.ticket_set_status(t.id, p_status, p_note);
end;
$$;

create or replace function public.assign_ticket(p_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t     public.helpdesk_tickets := private.load_ticket(p_id, true);
  v_cat public.helpdesk_categories;
begin
  if private.ticket_access(t) <> 'manage' then
    raise exception 'You do not have permission for this action (helpdesk.manage)' using errcode = '42501';
  end if;
  if t.status = 'closed' then
    raise exception 'This ticket is closed' using errcode = '23514';
  end if;
  select * into v_cat from public.helpdesk_categories where id = t.category_id;
  perform private.check_helpdesk_handler(t.org_id, p_employee_id, v_cat.confidential);
  update public.helpdesk_tickets set assignee_employee_id = p_employee_id where id = t.id returning * into t;
  perform private.ticket_event(t, case when p_employee_id is null then 'Moved back to the HR queue'
                                       else 'Assigned to ' || (select full_name from public.employees where id = p_employee_id) end);
end;
$$;

create or replace function public.rate_ticket(p_id uuid, p_rating integer, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.helpdesk_tickets := private.load_ticket(p_id, true);
begin
  if t.requester_employee_id is distinct from private.current_employee_id() then
    raise exception 'Only the person who raised the ticket can rate it' using errcode = '42501';
  end if;
  if t.status <> 'resolved' then
    raise exception 'Only a resolved ticket can be rated' using errcode = '23514';
  end if;
  if p_rating is null or p_rating not between 1 and 5 then
    raise exception 'Give 1 to 5 stars' using errcode = '22023';
  end if;
  update public.helpdesk_tickets
     set rating = p_rating, rating_comment = left(nullif(btrim(p_comment), ''), 1000),
         status = 'closed', closed_at = now(), closed_reason = 'rated'
   where id = t.id returning * into t;
  perform private.ticket_event(t, 'Rated ' || p_rating || ' of 5 and closed');
end;
$$;

create or replace function public.reopen_ticket(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.helpdesk_tickets := private.load_ticket(p_id, true);
begin
  if t.requester_employee_id is distinct from private.current_employee_id() then
    raise exception 'Only the person who raised the ticket can reopen it' using errcode = '42501';
  end if;
  if t.status <> 'resolved' then
    raise exception 'Only a resolved ticket can be reopened; a closed one needs a new ticket' using errcode = '23514';
  end if;
  if char_length(coalesce(btrim(p_reason), '')) < 3 then
    raise exception 'Say why it is not solved' using errcode = '22023';
  end if;
  insert into public.helpdesk_messages (org_id, ticket_id, kind, author_employee_id, body)
  values (t.org_id, t.id, 'reply', private.current_employee_id(), left(btrim(p_reason), 10000));
  update public.helpdesk_tickets set status = 'in_progress', resolved_at = null, reopen_count = reopen_count + 1
   where id = t.id returning * into t;
  perform private.ticket_event(t, 'Reopened by the employee');
end;
$$;

-- -----------------------------------------------------------------------------
-- API: setup (helpdesk.manage)
-- -----------------------------------------------------------------------------
create or replace function public.get_helpdesk_setup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('helpdesk.manage');
  perform private.seed_helpdesk_defaults(v_org);
  return jsonb_build_object(
    'settings', (select jsonb_build_object('sla', s.sla, 'auto_close_days', s.auto_close_days) from public.helpdesk_settings s where s.org_id = v_org),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'confidential', c.confidential, 'status', c.status,
                                          'sort', c.sort, 'handler_employee_id', c.handler_employee_id, 'handler', e.full_name)
                       order by c.sort, c.name)
      from public.helpdesk_categories c left join public.employees e on e.id = c.handler_employee_id
      where c.org_id = v_org), '[]'::jsonb),
    -- People who may handle tickets: active employees whose login holds handle or manage.
    'handlers', coalesce((
      select jsonb_agg(jsonb_build_object('employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id,
                                          'can_confidential', private.employee_has_permission(e.id, 'helpdesk.manage'))
                       order by e.full_name)
      from public.employees e
      where e.org_id = v_org and e.status = 'active'
        and (private.employee_has_permission(e.id, 'helpdesk.handle') or private.employee_has_permission(e.id, 'helpdesk.manage'))), '[]'::jsonb));
end;
$$;

create or replace function public.save_helpdesk_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_sla  jsonb := p -> 'sla';
  v_pri  text;
  v_resp integer;
  v_res  integer;
  v_days integer := coalesce((p ->> 'auto_close_days')::integer, 3);
begin
  perform private.require_permission('helpdesk.manage');
  if v_sla is null or jsonb_typeof(v_sla) <> 'object' then
    raise exception 'SLA targets are missing' using errcode = '22023';
  end if;
  foreach v_pri in array array['critical', 'high', 'medium', 'low'] loop
    v_resp := (v_sla -> v_pri ->> 'response')::integer;
    v_res := (v_sla -> v_pri ->> 'resolution')::integer;
    if v_resp is null or v_res is null or v_resp not between 15 and 43200 or v_res not between 15 and 43200 then
      raise exception 'SLA for %: give 15 minutes to 720 hours', v_pri using errcode = '22023';
    end if;
    if v_resp > v_res then
      raise exception 'SLA for %: the first response cannot come after the resolution', v_pri using errcode = '22023';
    end if;
  end loop;
  if v_days not between 1 and 30 then
    raise exception 'Auto-close must be 1 to 30 working days' using errcode = '22023';
  end if;
  perform private.seed_helpdesk_defaults(v_org);
  update public.helpdesk_settings
     set sla = jsonb_build_object(
           'critical', jsonb_build_object('response', (v_sla -> 'critical' ->> 'response')::integer, 'resolution', (v_sla -> 'critical' ->> 'resolution')::integer),
           'high',     jsonb_build_object('response', (v_sla -> 'high' ->> 'response')::integer,     'resolution', (v_sla -> 'high' ->> 'resolution')::integer),
           'medium',   jsonb_build_object('response', (v_sla -> 'medium' ->> 'response')::integer,   'resolution', (v_sla -> 'medium' ->> 'resolution')::integer),
           'low',      jsonb_build_object('response', (v_sla -> 'low' ->> 'response')::integer,      'resolution', (v_sla -> 'low' ->> 'resolution')::integer)),
         auto_close_days = v_days
   where org_id = v_org;
  perform private.write_audit(v_org, 'helpdesk.settings_saved', 'helpdesk_settings', null, null, p);
end;
$$;

create or replace function public.save_helpdesk_category(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_name    text := btrim(coalesce(p ->> 'name', ''));
  v_conf    boolean := coalesce((p ->> 'confidential')::boolean, false);
  v_handler uuid := nullif(p ->> 'handler_employee_id', '')::uuid;
  v_status  text := coalesce(private.jtext(p, 'status'), 'active');
  v_id      uuid;
begin
  perform private.require_permission('helpdesk.manage');
  if char_length(v_name) not between 2 and 80 then
    raise exception 'The category name needs 2 to 80 characters' using errcode = '22023';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'Unknown status' using errcode = '22023';
  end if;
  perform private.check_helpdesk_handler(v_org, v_handler, v_conf);
  if p_id is null then
    insert into public.helpdesk_categories (org_id, name, confidential, handler_employee_id, status, sort)
    values (v_org, v_name, v_conf, v_handler, v_status, coalesce((p ->> 'sort')::smallint, 50))
    returning id into v_id;
  else
    update public.helpdesk_categories
       set name = v_name, confidential = v_conf, handler_employee_id = v_handler, status = v_status,
           sort = coalesce((p ->> 'sort')::smallint, sort)
     where id = p_id and org_id = v_org returning id into v_id;
    if v_id is null then
      raise exception 'Category not found' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: helpdesk-files/{org}/{ticket}/{file}
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('helpdesk-files', 'helpdesk-files', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.helpdesk_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  t       public.helpdesk_tickets;
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$' then
    return false;
  end if;
  select * into t from public.helpdesk_tickets where id = v_parts[2]::uuid and org_id = v_parts[1]::uuid;
  if not found or private.ticket_access(t) is null then
    return false;
  end if;
  return not p_write or t.status <> 'closed';
end;
$$;

drop policy if exists olympus_helpdesk_files_select on storage.objects;
drop policy if exists olympus_helpdesk_files_insert on storage.objects;
create policy olympus_helpdesk_files_select on storage.objects for select to authenticated
  using (bucket_id = 'helpdesk-files' and private.helpdesk_file_access(name, false));
create policy olympus_helpdesk_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'helpdesk-files' and private.helpdesk_file_access(name, true));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.helpdesk_settings   enable row level security;
alter table public.helpdesk_categories enable row level security;
alter table public.helpdesk_tickets    enable row level security;
alter table public.helpdesk_messages   enable row level security;
revoke all on table public.helpdesk_settings, public.helpdesk_categories, public.helpdesk_tickets, public.helpdesk_messages
  from anon, authenticated;

revoke all on function
  public.list_helpdesk_categories(), public.create_ticket(jsonb), public.list_tickets(text), public.get_ticket(uuid),
  public.reply_ticket(uuid, jsonb), public.set_ticket_status(uuid, text, text), public.assign_ticket(uuid, uuid),
  public.rate_ticket(uuid, integer, text), public.reopen_ticket(uuid, text), public.get_helpdesk_setup(),
  public.save_helpdesk_settings(jsonb), public.save_helpdesk_category(uuid, jsonb)
from public, anon;
grant execute on function
  public.list_helpdesk_categories(), public.create_ticket(jsonb), public.list_tickets(text), public.get_ticket(uuid),
  public.reply_ticket(uuid, jsonb), public.set_ticket_status(uuid, text, text), public.assign_ticket(uuid, uuid),
  public.rate_ticket(uuid, integer, text), public.reopen_ticket(uuid, text), public.get_helpdesk_setup(),
  public.save_helpdesk_settings(jsonb), public.save_helpdesk_category(uuid, jsonb)
to authenticated;

revoke all on function
  private.seed_helpdesk_defaults(uuid), private.office_window(uuid), private.is_office_day(uuid, date, smallint[]),
  private.add_office_minutes(uuid, timestamptz, integer), private.office_minutes_between(uuid, timestamptz, timestamptz),
  private.office_days_between(uuid, date, date), private.employee_has_permission(uuid, text),
  private.check_helpdesk_handler(uuid, uuid, boolean), private.ticket_access(public.helpdesk_tickets),
  private.load_ticket(uuid, boolean), private.sla_minutes(uuid, text, text), private.ticket_sla(public.helpdesk_tickets),
  private.ticket_event(public.helpdesk_tickets, text), private.ticket_set_status(uuid, text, text),
  private.auto_close_tickets(uuid), private.clean_ticket_files(public.helpdesk_tickets, jsonb),
  private.ticket_row_json(public.helpdesk_tickets)
from public, anon, authenticated;
grant execute on function private.helpdesk_file_access(text, boolean) to authenticated;
revoke all on function private.helpdesk_file_access(text, boolean) from public, anon;
