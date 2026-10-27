-- =============================================================================
-- Communication C1: notices (company announcements and policy updates).
-- Module handbook: src/communication/architecture.md (sections 1, 2).
--
-- Publishers: notices.manage (HR; Admin implicit) to everyone, departments,
-- branches or chosen employees; notices.department (Manager) only to their own
-- department, and only their own notices. Content in English with an optional
-- Bangla version, safe markdown, optional attachment (bucket notice-files).
-- Stored status draft -> published -> archived (no delete); the shown status
-- adds scheduled (publish_at ahead) and expired (expires_at passed).
-- Readers: active employees matching the target at read time. The first open is
-- a read receipt; notices that require it are acknowledged once ("I have read
-- and agree"), never undone. Email copy and acknowledgement reminders go to the
-- R5 outbox (notifications, now also used outside recruitment); the existing
-- Edge Function recruit-notify sends them. Scheduled notices need no job: their
-- email copy is queued the first time notices are listed after publish_at.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.notifications') is null then
    raise exception 'Apply 20261029000100_recruit_r5_messages_interviews.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Permissions and defaults
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('notices.manage',     'communication', 'Publish notices to anyone; edit, pin and archive every notice; read receipts', false),
  ('notices.department', 'communication', 'Publish notices to your own department and manage your own notices',           false)
on conflict (key) do nothing;

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
    when 'hr_manager' then array['notices.manage']
    when 'manager'    then array['notices.department']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
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
  perform private.seed_time_defaults(p_org_id);
  perform private.seed_payroll_defaults(p_org_id);
  perform private.seed_statutory_defaults(p_org_id);
  perform private.seed_performance_defaults(p_org_id);
  perform private.seed_workforce_defaults(p_org_id);
  perform private.seed_recruit_defaults(p_org_id);
  perform private.seed_organogram_defaults(p_org_id);
  perform private.seed_communication_defaults(p_org_id);
end;
$$;

select private.seed_communication_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.notices (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  category           text not null default 'general'
                     check (category in ('general', 'policy_update', 'event', 'urgent', 'hr_notice', 'safety')),
  title              text not null check (char_length(btrim(title)) between 3 and 200),
  title_bn           text check (title_bn is null or char_length(btrim(title_bn)) between 2 and 200),
  body               text not null check (char_length(btrim(body)) between 1 and 20000),
  body_bn            text check (body_bn is null or char_length(body_bn) <= 20000),
  audience           text not null default 'all' check (audience in ('all', 'department', 'branch', 'employees')),
  department_ids     uuid[] not null default '{}',
  branch_ids         uuid[] not null default '{}',
  employee_ids       uuid[] not null default '{}',
  pinned             boolean not null default false,
  requires_ack       boolean not null default false,
  email_copy         boolean not null default false,
  status             text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  publish_at         timestamptz,
  expires_at         timestamptz,
  published_by       uuid references public.user_profiles (id),
  attachment_path    text,
  attachment_name    text check (attachment_name is null or char_length(attachment_name) <= 200),
  attachment_type    text check (attachment_type is null or attachment_type in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp')),
  email_base_url     text,
  email_queued_at    timestamptz,
  last_reminded_at   timestamptz,
  author_employee_id uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint notices_org_id_id_uq unique (org_id, id),
  constraint notices_author_fk foreign key (org_id, author_employee_id) references public.employees (org_id, id),
  constraint notices_published_has_time check (status = 'draft' or publish_at is not null),
  constraint notices_expiry_after_publish check (expires_at is null or publish_at is null or expires_at > publish_at),
  constraint notices_attachment_complete check ((attachment_path is null) = (attachment_name is null))
);
create index notices_org_status_idx on public.notices (org_id, status, publish_at desc);
select private.attach_standard_triggers('public.notices');

-- Read receipts and acknowledgements: high volume, no row audit (acknowledgements are audited by the RPC).
create table public.notice_reads (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null,
  notice_id       uuid not null,
  employee_id     uuid not null,
  first_read_at   timestamptz not null default now(),
  acknowledged_at timestamptz,
  constraint notice_reads_uq unique (notice_id, employee_id),
  constraint notice_reads_notice_fk foreign key (org_id, notice_id) references public.notices (org_id, id),
  constraint notice_reads_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id)
);

-- Once given, an acknowledgement stays; reads are never removed.
create or replace function private.notice_reads_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Read receipts cannot be removed' using errcode = '42501';
  end if;
  if old.acknowledged_at is not null and new.acknowledged_at is distinct from old.acknowledged_at then
    raise exception 'An acknowledgement cannot be changed' using errcode = '42501';
  end if;
  if new.first_read_at is distinct from old.first_read_at then
    new.first_read_at := old.first_read_at;
  end if;
  return new;
end;
$$;
create trigger notice_reads_guard before update or delete on public.notice_reads
  for each row execute function private.notice_reads_guard();

-- The R5 outbox now also carries notice and helpdesk emails (employee recipients).
alter table public.notifications alter column applicant_id drop not null;
alter table public.notifications alter column job_post_id drop not null;
alter table public.notifications add column source text not null default 'recruit'
  check (source in ('recruit', 'notice', 'helpdesk'));
alter table public.notifications add column employee_id uuid;
alter table public.notifications add column ref_id uuid;
alter table public.notifications add constraint notifications_employee_fk
  foreign key (org_id, employee_id) references public.employees (org_id, id);
alter table public.notifications add constraint notifications_source_target check (
  (source = 'recruit' and applicant_id is not null and job_post_id is not null)
  or (source <> 'recruit' and employee_id is not null));
create index notifications_ref_idx on public.notifications (ref_id) where ref_id is not null;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.notice_shown_status(n public.notices)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when n.status = 'draft' then 'draft'
    when n.status = 'archived' then 'archived'
    when n.publish_at > now() then 'scheduled'
    when n.expires_at is not null and n.expires_at <= now() then 'expired'
    else 'active'
  end
$$;

-- Active employees the notice is meant for, evaluated now.
create or replace function private.notice_targets(n public.notices)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.id from public.employees e
  where e.org_id = n.org_id and e.status = 'active'
    and (n.audience = 'all'
         or (n.audience = 'department' and e.department_id = any (n.department_ids))
         or (n.audience = 'branch' and e.branch_id = any (n.branch_ids))
         or (n.audience = 'employees' and e.id = any (n.employee_ids)))
$$;

create or replace function private.notice_can_manage(n public.notices)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select n.org_id = private.current_org_id()
     and (private.has_permission('notices.manage')
          or (private.has_permission('notices.department') and n.created_by = auth.uid()))
$$;

-- Readers see published notices that have started and are meant for them (expired ones stay readable).
create or replace function private.notice_can_read(n public.notices)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select n.org_id = private.current_org_id() and n.status = 'published' and n.publish_at <= now()
     and private.current_employee_id() in (select private.notice_targets(n))
$$;

create or replace function private.load_notice(p_id uuid)
returns public.notices
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.notices;
begin
  select * into v from public.notices where id = p_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Notice not found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

create or replace function private.email_channel_ready(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.org_messaging m
                 where m.org_id = p_org_id and m.channel = 'email' and m.enabled and m.secret_enc is not null)
$$;

-- Queues one email per target employee with an address. Reminders skip those who acknowledged.
-- Returns the number queued, or -1 when the company has no working email channel.
create or replace function private.queue_notice_emails(p_notice_id uuid, p_reminder boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n       public.notices;
  v_company text;
  v_link    text;
  v_subject text;
  v_body    text;
  v_count   integer;
begin
  select * into v_n from public.notices where id = p_notice_id;
  if not private.email_channel_ready(v_n.org_id) then
    return -1;
  end if;
  v_company := (select o.name from public.organizations o where o.id = v_n.org_id);
  v_link := case when v_n.email_base_url is not null then v_n.email_base_url || '/notices?open=' || v_n.id end;
  v_subject := left(case when p_reminder then 'Reminder: please acknowledge — ' else 'Notice: ' end || v_n.title
                    || ' — ' || v_company, 200);
  v_body := v_n.title || coalesce(E'\n' || v_n.title_bn, '') || E'\n\n' || v_n.body
            || coalesce(E'\n\n' || v_n.body_bn, '')
            || case when v_n.requires_ack then E'\n\nPlease open the notice and press "I have read and agree".' else '' end
            || coalesce(E'\n\nOpen it in Olympus HRIS: ' || v_link, '')
            || E'\n\n' || v_company;
  insert into public.notifications (org_id, source, employee_id, ref_id, template_key, channel, to_address, subject, body)
  select v_n.org_id, 'notice', e.id, v_n.id, case when p_reminder then 'notice_reminder' else 'notice' end, 'email',
         coalesce(e.email, up.email), v_subject, left(v_body, 20000)
  from public.employees e
  left join public.user_profiles up on up.id = e.user_id
  where e.id in (select private.notice_targets(v_n))
    and coalesce(e.email, up.email) is not null
    and (not p_reminder or not exists (select 1 from public.notice_reads r
                                       where r.notice_id = v_n.id and r.employee_id = e.id and r.acknowledged_at is not null));
  get diagnostics v_count = row_count;
  if not p_reminder then
    update public.notices set email_queued_at = now() where id = v_n.id;
  end if;
  return v_count;
end;
$$;

-- Scheduled notices whose time has come: queue their email copy once.
create or replace function private.release_due_notices(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select n.id from public.notices n
    where n.org_id = p_org_id and n.status = 'published' and n.email_copy and n.email_queued_at is null
      and n.publish_at <= now() and (n.expires_at is null or n.expires_at > now())
    for update skip locked
  loop
    if private.queue_notice_emails(v_id, false) = -1 then
      -- No email channel: mark as handled so it is not retried on every list.
      update public.notices set email_queued_at = now() where id = v_id;
    end if;
  end loop;
end;
$$;

create or replace function private.uuid_array(p jsonb, p_key text)
returns uuid[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array(select distinct x::uuid from jsonb_array_elements_text(coalesce(p -> p_key, '[]'::jsonb)) x), '{}')
$$;

create or replace function private.notice_json(n public.notices)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', n.id, 'category', n.category, 'title', n.title, 'title_bn', n.title_bn, 'body', n.body, 'body_bn', n.body_bn,
    'audience', n.audience, 'department_ids', to_jsonb(n.department_ids), 'branch_ids', to_jsonb(n.branch_ids),
    'employee_ids', to_jsonb(n.employee_ids), 'pinned', n.pinned, 'requires_ack', n.requires_ack, 'email_copy', n.email_copy,
    'status', n.status, 'shown_status', private.notice_shown_status(n), 'publish_at', n.publish_at, 'expires_at', n.expires_at,
    'attachment_path', n.attachment_path, 'attachment_name', n.attachment_name, 'attachment_type', n.attachment_type,
    'email_queued_at', n.email_queued_at, 'last_reminded_at', n.last_reminded_at, 'created_at', n.created_at,
    'updated_at', n.updated_at,
    'author', (select e.full_name from public.employees e where e.id = n.author_employee_id),
    'audience_label', case n.audience
      when 'all' then 'All employees'
      when 'department' then (select string_agg(d.name, ', ' order by d.name) from public.departments d where d.id = any (n.department_ids))
      when 'branch' then (select string_agg(b.name, ', ' order by b.name) from public.branches b where b.id = any (n.branch_ids))
      else cardinality(n.employee_ids) || ' employee' || case when cardinality(n.employee_ids) = 1 then '' else 's' end
    end)
$$;

-- -----------------------------------------------------------------------------
-- API: publishers
-- -----------------------------------------------------------------------------
create or replace function public.save_notice(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org       uuid := private.current_org_id();
  v_full      boolean := private.has_permission('notices.manage');
  v_old       public.notices;
  v_id        uuid := coalesce(p_id, gen_random_uuid());
  v_audience  text := coalesce(private.jtext(p, 'audience'), 'all');
  v_depts     uuid[] := private.uuid_array(p, 'department_ids');
  v_branches  uuid[] := private.uuid_array(p, 'branch_ids');
  v_people    uuid[] := private.uuid_array(p, 'employee_ids');
  v_my_dept   uuid;
  v_publish   timestamptz := nullif(p ->> 'publish_at', '')::timestamptz;
  v_expires   timestamptz := nullif(p ->> 'expires_at', '')::timestamptz;
  v_path      text := private.jtext(p, 'attachment_path');
  v_att_name  text := private.jtext(p, 'attachment_name');
  v_att_type  text := private.jtext(p, 'attachment_type');
begin
  if not (v_full or private.has_permission('notices.department')) then
    raise exception 'You do not have permission for this action (notices.manage)' using errcode = '42501';
  end if;
  if p_id is not null then
    v_old := private.load_notice(p_id);
    if not private.notice_can_manage(v_old) then
      raise exception 'You can only change your own notices' using errcode = '42501';
    end if;
    if v_old.status = 'archived' then
      raise exception 'An archived notice cannot be changed' using errcode = '23514';
    end if;
  end if;

  if not v_full then
    -- Managers: always exactly their own department.
    select e.department_id into v_my_dept from public.employees e where e.id = private.current_employee_id();
    if v_my_dept is null then
      raise exception 'Your employee record has no department, so you cannot publish a notice' using errcode = '23514';
    end if;
    v_audience := 'department';
    v_depts := array[v_my_dept];
    v_branches := '{}';
    v_people := '{}';
  elsif v_audience = 'department' then
    if cardinality(v_depts) = 0 or (select count(*) from public.departments d where d.id = any (v_depts) and d.org_id = v_org) <> cardinality(v_depts) then
      raise exception 'Choose at least one department of your company' using errcode = '22023';
    end if;
    v_branches := '{}'; v_people := '{}';
  elsif v_audience = 'branch' then
    if cardinality(v_branches) = 0 or (select count(*) from public.branches b where b.id = any (v_branches) and b.org_id = v_org) <> cardinality(v_branches) then
      raise exception 'Choose at least one branch of your company' using errcode = '22023';
    end if;
    v_depts := '{}'; v_people := '{}';
  elsif v_audience = 'employees' then
    if cardinality(v_people) = 0 or (select count(*) from public.employees e where e.id = any (v_people) and e.org_id = v_org) <> cardinality(v_people) then
      raise exception 'Choose at least one employee of your company' using errcode = '22023';
    end if;
    v_depts := '{}'; v_branches := '{}';
  elsif v_audience = 'all' then
    v_depts := '{}'; v_branches := '{}'; v_people := '{}';
  else
    raise exception 'Unknown audience' using errcode = '22023';
  end if;

  if char_length(coalesce(btrim(p ->> 'title'), '')) < 3 then
    raise exception 'The title needs at least 3 characters' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'body'), '')) = 0 then
    raise exception 'Write the notice text' using errcode = '22023';
  end if;
  -- An already published notice keeps its publish time.
  if v_old.status = 'published' then
    v_publish := v_old.publish_at;
  end if;
  if v_expires is not null and v_expires <= greatest(coalesce(v_publish, now()), now()) then
    raise exception 'The expiry date must be after the publish time' using errcode = '22023';
  end if;
  if v_path is not null then
    if p_id is null or v_path not like v_org || '/' || v_id || '/%' then
      raise exception 'Save the notice before adding a file' using errcode = '22023';
    end if;
    if v_att_name is null or v_att_type is null then
      raise exception 'The file name and type are missing' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.notices (id, org_id, category, title, title_bn, body, body_bn, audience, department_ids, branch_ids,
                                employee_ids, pinned, requires_ack, email_copy, publish_at, expires_at, author_employee_id)
    values (v_id, v_org, coalesce(private.jtext(p, 'category'), 'general'), btrim(p ->> 'title'), private.jtext(p, 'title_bn'),
            btrim(p ->> 'body'), private.jtext(p, 'body_bn'), v_audience, v_depts, v_branches, v_people,
            coalesce((p ->> 'pinned')::boolean, false), coalesce((p ->> 'requires_ack')::boolean, false),
            coalesce((p ->> 'email_copy')::boolean, false), v_publish, v_expires, private.current_employee_id());
  else
    update public.notices
       set category = coalesce(private.jtext(p, 'category'), category), title = btrim(p ->> 'title'),
           title_bn = private.jtext(p, 'title_bn'), body = btrim(p ->> 'body'), body_bn = private.jtext(p, 'body_bn'),
           audience = v_audience, department_ids = v_depts, branch_ids = v_branches, employee_ids = v_people,
           pinned = coalesce((p ->> 'pinned')::boolean, pinned), requires_ack = coalesce((p ->> 'requires_ack')::boolean, requires_ack),
           email_copy = case when status = 'draft' then coalesce((p ->> 'email_copy')::boolean, email_copy) else email_copy end,
           publish_at = v_publish, expires_at = v_expires,
           attachment_path = case when p ? 'attachment_path' then v_path else attachment_path end,
           attachment_name = case when p ? 'attachment_path' then v_att_name else attachment_name end,
           attachment_type = case when p ? 'attachment_path' then v_att_type else attachment_type end
     where id = p_id;
  end if;
  return v_id;
end;
$$;

create or replace function public.publish_notice(p_id uuid, p_base_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n      public.notices := private.load_notice(p_id);
  v_base   text := case when nullif(btrim(coalesce(p_base_url, '')), '') is not null then private.clean_base_url(p_base_url) end;
  v_at     timestamptz;
  v_queued integer;
begin
  if not private.notice_can_manage(v_n) then
    raise exception 'You can only publish your own notices' using errcode = '42501';
  end if;
  if v_n.status <> 'draft' then
    raise exception 'Only a draft can be published' using errcode = '23514';
  end if;
  v_at := greatest(coalesce(v_n.publish_at, now()), now());
  if v_n.expires_at is not null and v_n.expires_at <= v_at then
    raise exception 'The expiry date has already passed; change it first' using errcode = '23514';
  end if;
  update public.notices set status = 'published', publish_at = v_at, published_by = auth.uid(), email_base_url = v_base
   where id = p_id returning * into v_n;
  if v_n.email_copy and v_at <= now() then
    v_queued := private.queue_notice_emails(p_id, false);
    if v_queued = -1 then
      update public.notices set email_queued_at = now() where id = p_id;
    end if;
  end if;
  perform private.write_audit(v_n.org_id, 'notice.published', 'notices', v_n.id, null,
    jsonb_build_object('title', v_n.title, 'audience', v_n.audience, 'publish_at', v_at));
  return jsonb_build_object('status', private.notice_shown_status(v_n), 'publish_at', v_at,
    'emails_queued', greatest(coalesce(v_queued, 0), 0),
    'email_skipped', case when v_n.email_copy and v_queued = -1 then 'The company has no working email channel (Recruitment settings → Email)'
                          when v_n.email_copy and v_queued is null then 'The email copy goes out when the notice starts' end);
end;
$$;

create or replace function public.set_notice_pin(p_id uuid, p_pinned boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n public.notices := private.load_notice(p_id);
begin
  if not private.notice_can_manage(v_n) then
    raise exception 'You can only change your own notices' using errcode = '42501';
  end if;
  if v_n.status = 'archived' then
    raise exception 'An archived notice cannot be pinned' using errcode = '23514';
  end if;
  update public.notices set pinned = coalesce(p_pinned, false) where id = p_id;
end;
$$;

create or replace function public.archive_notice(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n public.notices := private.load_notice(p_id);
begin
  if not private.notice_can_manage(v_n) then
    raise exception 'You can only archive your own notices' using errcode = '42501';
  end if;
  update public.notices set status = 'archived', pinned = false where id = p_id and status <> 'archived';
end;
$$;

-- Publisher list with KPIs and reach (targets, portal users, reads, acknowledgements).
create or replace function public.list_notices_manage()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_full boolean := private.has_permission('notices.manage');
begin
  if not (v_full or private.has_permission('notices.department')) then
    raise exception 'You do not have permission for this action (notices.manage)' using errcode = '42501';
  end if;
  perform private.release_due_notices(v_org);
  return (
    with rows as (
      select n, private.notice_shown_status(n) as shown,
             (select count(*) from private.notice_targets(n) t) as targets,
             (select count(*) from private.notice_targets(n) t
               join public.org_members m on m.employee_id = t and m.status = 'active') as portal,
             (select count(*) from public.notice_reads r where r.notice_id = n.id) as reads,
             (select count(*) from public.notice_reads r where r.notice_id = n.id and r.acknowledged_at is not null) as acks
      from public.notices n
      where n.org_id = v_org and (v_full or n.created_by = auth.uid())
    )
    select jsonb_build_object(
      'kpis', jsonb_build_object(
        'total', (select count(*) from rows where shown <> 'archived'),
        'pinned', (select count(*) from rows where (n).pinned and shown = 'active'),
        'active', (select count(*) from rows where shown = 'active'),
        'this_month', (select count(*) from rows where (n).publish_at >= date_trunc('month', now()) and shown <> 'draft')),
      'can_target_all', v_full,
      'notices', coalesce((select jsonb_agg(private.notice_json(n) || jsonb_build_object(
                     'targets', targets, 'portal', portal, 'reads', reads, 'acks', acks)
                   order by (n).status = 'archived', (n).pinned desc, coalesce((n).publish_at, (n).created_at) desc)
                 from rows), '[]'::jsonb))
  );
end;
$$;

create or replace function public.notice_receipts(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_n public.notices := private.load_notice(p_id);
begin
  if not private.notice_can_manage(v_n) then
    raise exception 'You can only see receipts of your own notices' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id,
             'department', (select d.name from public.departments d where d.id = e.department_id),
             'has_portal', exists (select 1 from public.org_members m where m.employee_id = e.id and m.status = 'active'),
             'first_read_at', r.first_read_at, 'acknowledged_at', r.acknowledged_at)
           order by r.first_read_at is not null, e.full_name)
    from public.employees e
    left join public.notice_reads r on r.notice_id = v_n.id and r.employee_id = e.id
    where e.id in (select private.notice_targets(v_n))), '[]'::jsonb);
end;
$$;

create or replace function public.remind_notice_ack(p_id uuid, p_base_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n     public.notices := private.load_notice(p_id);
  v_count integer;
begin
  if not private.notice_can_manage(v_n) then
    raise exception 'You can only remind people about your own notices' using errcode = '42501';
  end if;
  if not v_n.requires_ack or private.notice_shown_status(v_n) <> 'active' then
    raise exception 'Reminders are only for active notices that need acknowledgement' using errcode = '23514';
  end if;
  if v_n.last_reminded_at > now() - interval '24 hours' then
    raise exception 'A reminder was sent less than 24 hours ago' using errcode = '23514';
  end if;
  if nullif(btrim(coalesce(p_base_url, '')), '') is not null then
    update public.notices set email_base_url = private.clean_base_url(p_base_url) where id = p_id;
  end if;
  v_count := private.queue_notice_emails(p_id, true);
  if v_count = -1 then
    raise exception 'The company has no working email channel (Recruitment settings → Email)' using errcode = '23514';
  end if;
  update public.notices set last_reminded_at = now() where id = p_id;
  perform private.write_audit(v_n.org_id, 'notice.reminded', 'notices', v_n.id, null, jsonb_build_object('emails', v_count));
  return jsonb_build_object('emails_queued', v_count);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: readers
-- -----------------------------------------------------------------------------
create or replace function public.my_notices()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_me  uuid := private.current_employee_id();
begin
  if v_org is null or v_me is null then
    return '[]'::jsonb;
  end if;
  perform private.release_due_notices(v_org);
  return coalesce((
    select jsonb_agg(private.notice_json(n) || jsonb_build_object(
             'read', r.first_read_at is not null, 'acknowledged_at', r.acknowledged_at)
           order by n.pinned desc, n.publish_at desc)
    from public.notices n
    left join public.notice_reads r on r.notice_id = n.id and r.employee_id = v_me
    where n.org_id = v_org and private.notice_shown_status(n) = 'active' and private.notice_can_read(n)), '[]'::jsonb);
end;
$$;

-- Opening a notice records the first read (for its audience). Publishers may open their own notices too.
create or replace function public.open_notice(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n    public.notices := private.load_notice(p_id);
  v_me   uuid := private.current_employee_id();
  v_read public.notice_reads;
begin
  if private.notice_can_read(v_n) then
    insert into public.notice_reads (org_id, notice_id, employee_id) values (v_n.org_id, v_n.id, v_me)
    on conflict (notice_id, employee_id) do nothing;
  elsif not private.notice_can_manage(v_n) then
    raise exception 'Notice not found' using errcode = 'P0002';
  end if;
  select * into v_read from public.notice_reads where notice_id = v_n.id and employee_id = v_me;
  return private.notice_json(v_n) || jsonb_build_object(
    'read', v_read.first_read_at is not null, 'acknowledged_at', v_read.acknowledged_at,
    'can_manage', private.notice_can_manage(v_n), 'in_audience', private.notice_can_read(v_n));
end;
$$;

create or replace function public.acknowledge_notice(p_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n  public.notices := private.load_notice(p_id);
  v_me uuid := private.current_employee_id();
  v_at timestamptz;
begin
  if not private.notice_can_read(v_n) then
    raise exception 'Notice not found' using errcode = 'P0002';
  end if;
  if not v_n.requires_ack then
    raise exception 'This notice does not need an acknowledgement' using errcode = '23514';
  end if;
  insert into public.notice_reads (org_id, notice_id, employee_id, acknowledged_at) values (v_n.org_id, v_n.id, v_me, now())
  on conflict (notice_id, employee_id) do update set acknowledged_at = coalesce(public.notice_reads.acknowledged_at, now())
  returning acknowledged_at into v_at;
  perform private.write_audit(v_n.org_id, 'notice.acknowledged', 'notices', v_n.id, null,
    jsonb_build_object('employee_id', v_me, 'acknowledged_at', v_at));
  return v_at;
end;
$$;

-- Dashboard banner: pinned active notices, unread count, acknowledgements waiting.
create or replace function public.my_notice_alerts()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list jsonb := public.my_notices();
begin
  return jsonb_build_object(
    'pinned', coalesce((select jsonb_agg(jsonb_build_object('id', x ->> 'id', 'title', x ->> 'title', 'title_bn', x ->> 'title_bn',
                                                            'category', x ->> 'category', 'read', (x ->> 'read')::boolean))
                        from jsonb_array_elements(v_list) x where (x ->> 'pinned')::boolean), '[]'::jsonb),
    'unread', (select count(*) from jsonb_array_elements(v_list) x where not (x ->> 'read')::boolean),
    'pending_ack', (select count(*) from jsonb_array_elements(v_list) x
                    where (x ->> 'requires_ack')::boolean and x ->> 'acknowledged_at' is null));
end;
$$;

-- -----------------------------------------------------------------------------
-- Outbox: the senders now include notice and helpdesk publishers
-- -----------------------------------------------------------------------------
create or replace function private.can_send_messages()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('recruit.manage') or private.has_permission('notices.manage')
      or private.has_permission('notices.department') or private.has_permission('users.reset_password')
$$;

create or replace function public.claim_notifications(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_ids    uuid[];
begin
  if not private.can_send_messages() then
    raise exception 'You do not have permission for this action (recruit.manage)' using errcode = '42501';
  end if;
  select array_agg(n.id) into v_ids from (
    select n.id from public.notifications n
    where n.org_id = v_org_id
      and (n.status = 'queued' or (n.status = 'sending' and n.claimed_at < now() - interval '10 minutes'))
      and exists (select 1 from public.org_messaging m where m.org_id = v_org_id and m.channel = n.channel
                  and m.enabled and m.secret_enc is not null)
    order by n.created_at
    limit least(greatest(coalesce(p_limit, 20), 1), 50)
    for update skip locked) n;
  if v_ids is null then
    return jsonb_build_object('org_id', v_org_id, 'items', '[]'::jsonb);
  end if;
  update public.notifications set status = 'sending', claimed_at = now(), attempts = attempts + 1 where id = any (v_ids);
  return jsonb_build_object('org_id', v_org_id, 'items', (
    select jsonb_agg(jsonb_build_object('id', n.id, 'channel', n.channel, 'to', n.to_address, 'subject', n.subject, 'body', n.body))
    from public.notifications n where n.id = any (v_ids)));
end;
$$;

create or replace function public.mark_notification(p_id uuid, p_ok boolean, p_provider_ref text, p_error text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.can_send_messages() then
    raise exception 'You do not have permission for this action (recruit.manage)' using errcode = '42501';
  end if;
  update public.notifications
     set status = case when p_ok then 'sent' else 'failed' end, sent_at = case when p_ok then now() end,
         provider_ref = left(p_provider_ref, 200), error = case when p_ok then null else left(coalesce(p_error, 'Not sent'), 500) end
   where id = p_id and org_id = private.current_org_id() and status = 'sending';
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: notice-files/{org}/{notice}/{file}
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('notice-files', 'notice-files', false, 10485760, array['application/pdf', 'image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.notice_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_n     public.notices;
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$' then
    return false;
  end if;
  select * into v_n from public.notices where id = v_parts[2]::uuid and org_id = v_parts[1]::uuid;
  if not found or v_n.org_id is distinct from private.current_org_id() then
    return false;
  end if;
  if p_write then
    return v_n.status <> 'archived' and private.notice_can_manage(v_n);
  end if;
  return private.notice_can_manage(v_n) or private.notice_can_read(v_n);
end;
$$;

drop policy if exists olympus_notice_files_select on storage.objects;
drop policy if exists olympus_notice_files_insert on storage.objects;
drop policy if exists olympus_notice_files_update on storage.objects;
drop policy if exists olympus_notice_files_delete on storage.objects;
create policy olympus_notice_files_select on storage.objects for select to authenticated
  using (bucket_id = 'notice-files' and private.notice_file_access(name, false));
create policy olympus_notice_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'notice-files' and private.notice_file_access(name, true));
create policy olympus_notice_files_update on storage.objects for update to authenticated
  using (bucket_id = 'notice-files' and private.notice_file_access(name, true))
  with check (bucket_id = 'notice-files' and private.notice_file_access(name, true));
create policy olympus_notice_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'notice-files' and private.notice_file_access(name, true));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.notices      enable row level security;
alter table public.notice_reads enable row level security;
revoke all on table public.notices, public.notice_reads from anon, authenticated;

revoke all on function
  public.save_notice(uuid, jsonb), public.publish_notice(uuid, text), public.set_notice_pin(uuid, boolean),
  public.archive_notice(uuid), public.list_notices_manage(), public.notice_receipts(uuid), public.remind_notice_ack(uuid, text),
  public.my_notices(), public.open_notice(uuid), public.acknowledge_notice(uuid), public.my_notice_alerts()
from public, anon;
grant execute on function
  public.save_notice(uuid, jsonb), public.publish_notice(uuid, text), public.set_notice_pin(uuid, boolean),
  public.archive_notice(uuid), public.list_notices_manage(), public.notice_receipts(uuid), public.remind_notice_ack(uuid, text),
  public.my_notices(), public.open_notice(uuid), public.acknowledge_notice(uuid), public.my_notice_alerts()
to authenticated;

revoke all on function
  private.seed_communication_defaults(uuid), private.notice_reads_guard(), private.notice_shown_status(public.notices),
  private.notice_targets(public.notices), private.notice_can_manage(public.notices), private.notice_can_read(public.notices),
  private.load_notice(uuid), private.email_channel_ready(uuid), private.queue_notice_emails(uuid, boolean),
  private.release_due_notices(uuid), private.uuid_array(jsonb, text), private.notice_json(public.notices),
  private.can_send_messages()
from public, anon, authenticated;
-- Storage policies run as the caller.
grant execute on function private.notice_file_access(text, boolean) to authenticated;
revoke all on function private.notice_file_access(text, boolean) from public, anon;
