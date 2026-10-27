-- =============================================================================
-- DMS D2: central review, custodians, document requests, reminders, overdue lists.
-- Decisions: src/DMS/architecture.md section 6a (user, 2026-10-27).
--
--   * Every upload goes to review before readers see it; the Admin's own uploads
--     publish directly (audited "published without review"). Reviewers: the
--     Admin (everything) and dms.approve holders (HR Manager: every department;
--     Manager: own department). Nobody reviews their own upload. Reject needs a
--     reason. Never auto-approved: past the review period (working days, default
--     3) an item shows "Review overdue" until someone decides.
--   * Custodians: the person who handles the work owns its folder (e.g. Transport
--     -> Karim). They may upload there without dms.upload and get its reminders.
--   * Requests: Admin / HR Manager ask anyone, a Manager asks people of their own
--     department. The assignee may upload for that request without dms.upload.
--     Past the due date it shows "Upload overdue" until done or cancelled.
--   * Reminders before expiry / review (default 60, 30, 7, 0 days) to the owner and
--     the custodians; at the first reminder a renewal request goes to the owner.
--     No job needed: due reminders are queued when DMS lists are opened.
--   * Settings: require_review (on), review_days, reminder_days.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.dms_register_upload') is null then
    raise exception 'Apply 20261104000100_dms_d1_foundation.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Permissions, settings, columns
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('dms.approve', 'dms', 'Review and approve uploaded documents (own department; every department with dms.upload_all)', false)
on conflict (key) do nothing;

insert into public.role_permissions (org_id, role_id, permission_key)
select r.org_id, r.id, 'dms.approve' from public.roles r where r.system_key in ('hr_manager', 'manager')
on conflict do nothing;

create or replace function private.seed_dms_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Runs once per company: later calls must not bring back folders or permissions the Admin removed.
  insert into public.dms_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  if not found then
    return;
  end if;
  perform private.dms_add_catalog_folders(p_org_id, null);
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['dms.manage', 'dms.upload', 'dms.upload_all', 'dms.view_confidential', 'dms.approve']
    when 'manager'    then array['dms.upload', 'dms.view_confidential', 'dms.approve']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
end;
$$;

alter table public.dms_settings add column require_review boolean not null default true;
alter table public.dms_settings add column review_days smallint not null default 3 check (review_days between 1 and 30);
alter table public.dms_settings add column reminder_days smallint[] not null default '{60,30,7,0}'
  check (cardinality(reminder_days) between 1 and 6 and 0 <= all (reminder_days) and 365 >= all (reminder_days));

alter table public.dms_versions drop constraint dms_versions_status_check;
alter table public.dms_versions add constraint dms_versions_status_check
  check (status in ('uploading', 'in_review', 'rejected', 'current', 'superseded', 'cancelled'));
alter table public.dms_versions add column submitted_at timestamptz;
alter table public.dms_versions add column review_due_date date;
alter table public.dms_versions add column reviewed_by uuid references public.user_profiles (id);
alter table public.dms_versions add column reviewed_at timestamptz;
alter table public.dms_versions add column review_comment text check (review_comment is null or char_length(review_comment) <= 1000);
alter table public.dms_versions add column published_without_review boolean not null default false;
alter table public.dms_versions add column request_id uuid;
-- A rejected file may be sent again (e.g. rejected for its title only).
drop index public.dms_versions_hash_uq;
create unique index dms_versions_hash_uq on public.dms_versions (org_id, file_hash) where status not in ('cancelled', 'rejected');
create index dms_versions_review_idx on public.dms_versions (org_id, status) where status = 'in_review';

-- The outbox also carries DMS emails; DMS users may push it.
alter table public.notifications drop constraint if exists notifications_source_check;
alter table public.notifications add constraint notifications_source_check
  check (source in ('recruit', 'notice', 'helpdesk', 'dms'));

create or replace function private.can_send_messages()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('recruit.manage') or private.has_permission('notices.manage')
      or private.has_permission('notices.department') or private.has_permission('users.reset_password')
      or private.has_permission('dms.manage') or private.has_permission('dms.upload') or private.has_permission('dms.approve')
$$;

-- -----------------------------------------------------------------------------
-- Custodians and requests
-- -----------------------------------------------------------------------------
create table public.dms_custodians (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  folder_id  uuid not null,
  user_id    uuid not null references public.user_profiles (id),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  constraint dms_custodians_uq unique (org_id, folder_id, user_id),
  constraint dms_custodians_folder_fk foreign key (org_id, folder_id) references public.dms_folders (org_id, id)
);
select private.attach_standard_triggers('public.dms_custodians');

create table public.dms_requests (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references public.organizations (id),
  kind                 text not null default 'upload' check (kind in ('upload', 'renewal')),
  requested_by         uuid references public.user_profiles (id),     -- null = the system (renewal)
  assignee_user_id     uuid not null references public.user_profiles (id),
  department_id        uuid not null,
  folder_id            uuid,
  doc_type_id          uuid,
  document_id          uuid,                                         -- a new version / renewal of this document
  note                 text check (note is null or char_length(note) <= 1000),
  due_date             date,
  status               text not null default 'open' check (status in ('open', 'submitted', 'done', 'cancelled')),
  fulfilled_version_id uuid,
  done_at              timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint dms_requests_org_id_id_uq unique (org_id, id),
  constraint dms_requests_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint dms_requests_folder_fk foreign key (org_id, folder_id) references public.dms_folders (org_id, id),
  constraint dms_requests_type_fk foreign key (org_id, doc_type_id) references public.dms_doc_types (org_id, id),
  constraint dms_requests_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id)
);
create index dms_requests_assignee_idx on public.dms_requests (org_id, assignee_user_id, status);
create unique index dms_requests_open_renewal_uq on public.dms_requests (document_id)
  where kind = 'renewal' and status in ('open', 'submitted');
select private.attach_standard_triggers('public.dms_requests');
alter table public.dms_versions add constraint dms_versions_request_fk foreign key (org_id, request_id) references public.dms_requests (org_id, id);

-- One row per reminder step sent, so reminders are never repeated.
create table public.dms_reminders (
  org_id      uuid not null references public.organizations (id),
  document_id uuid not null,
  kind        text not null check (kind in ('expiry', 'review')),
  due_date    date not null,
  step_days   smallint not null,
  sent_at     timestamptz not null default now(),
  emails      smallint not null default 0,
  primary key (document_id, kind, due_date, step_days),
  constraint dms_reminders_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id)
);

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
-- p_days working days (weekly off and company holidays skipped) after p_from.
create or replace function private.dms_add_working_days(p_org_id uuid, p_from date, p_days integer)
returns date
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_off  smallint[] := (select w.off_days from private.office_window(p_org_id) w);
  v_day  date := p_from;
  v_left integer := greatest(coalesce(p_days, 0), 0);
  i      integer := 0;
begin
  while v_left > 0 and i < 400 loop
    v_day := v_day + 1;
    i := i + 1;
    if private.is_office_day(p_org_id, v_day, coalesce(v_off, '{5}')) then
      v_left := v_left - 1;
    end if;
  end loop;
  return v_day;
end;
$$;

-- Custodian of this folder or of a folder above it.
create or replace function private.dms_is_custodian(p_folder_id uuid, p_user_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  with recursive up as (
    select f.id, f.parent_id from public.dms_folders f where f.id = p_folder_id
    union all select f.id, f.parent_id from public.dms_folders f join up on f.id = up.parent_id
  )
  select exists (select 1 from public.dms_custodians c join up on c.folder_id = up.id
                 where c.user_id = coalesce(p_user_id, auth.uid()) and c.active)
$$;

create or replace function private.dms_is_any_custodian()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.dms_custodians c
                 where c.org_id = private.current_org_id() and c.user_id = auth.uid() and c.active)
$$;

create or replace function private.dms_can_upload()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('dms.manage') or private.has_permission('dms.upload_all') or private.has_permission('dms.upload')
      or private.dms_is_any_custodian()
$$;

-- May the caller review this document's pending version?
create or replace function private.dms_can_review(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select d.org_id = private.current_org_id()
     and (private.is_org_admin()
          or (private.has_permission('dms.approve')
              and (private.has_permission('dms.upload_all') or private.has_permission('dms.manage')
                   or d.department_id = private.dms_my_department())))
$$;

create or replace function private.dms_can_read(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select d.org_id = private.current_org_id() and d.lifecycle <> 'cancelled' and (
    private.has_permission('dms.manage')
    or d.owner_user_id = auth.uid() or d.created_by = auth.uid()
    or private.dms_is_custodian(d.folder_id)
    or (exists (select 1 from public.dms_versions v where v.document_id = d.id and v.status = 'in_review') and private.dms_can_review(d))
    or (d.lifecycle = 'published' and case d.classification
          when 'restricted' then private.current_role_id() = any (d.restricted_role_ids)
          when 'confidential' then private.has_permission('dms.view_confidential')
                                   and (private.has_permission('dms.upload_all') or d.department_id = private.dms_my_department())
          else d.scope = 'company' or private.has_permission('dms.upload_all')
               or private.dms_my_department() = any (d.scope_department_ids)
        end))
$$;

create or replace function private.dms_can_edit(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select d.org_id = private.current_org_id() and d.lifecycle <> 'cancelled'
     and (private.has_permission('dms.manage') or private.has_permission('dms.upload_all')
          or (private.has_permission('dms.upload') and (d.department_id = private.dms_my_department() or d.owner_user_id = auth.uid()))
          or private.dms_is_custodian(d.folder_id))
$$;

create or replace function private.dms_user_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select e.full_name from public.org_members m join public.employees e on e.id = m.employee_id
                   where m.user_id = p_user_id and m.org_id = private.current_org_id() limit 1),
                  (select up.full_name from public.user_profiles up where up.id = p_user_id))
$$;

-- One email to a login of the company (needs an employee record and an address). Returns true when queued.
create or replace function private.dms_queue_email(p_org_id uuid, p_user_id uuid, p_ref uuid, p_template text, p_subject text, p_body text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp  uuid;
  v_addr text;
begin
  if p_user_id is null or not private.email_channel_ready(p_org_id) then
    return false;
  end if;
  select m.employee_id, coalesce(e.email, up.email) into v_emp, v_addr
  from public.org_members m
  left join public.employees e on e.id = m.employee_id
  left join public.user_profiles up on up.id = m.user_id
  where m.org_id = p_org_id and m.user_id = p_user_id and m.status = 'active'
  limit 1;
  if v_emp is null or v_addr is null then
    return false;
  end if;
  insert into public.notifications (org_id, source, employee_id, ref_id, template_key, channel, to_address, subject, body)
  values (p_org_id, 'dms', v_emp, p_ref, p_template, 'email', v_addr, left(p_subject, 200),
          left(p_body || E'\n\n' || (select o.name from public.organizations o where o.id = p_org_id), 20000));
  return true;
end;
$$;

-- Publishes a version: the previous one is superseded, the request (if any) is done.
create or replace function private.dms_publish_version(p_version_id uuid, p_without_review boolean)
returns public.dms_documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.dms_versions;
  d public.dms_documents;
begin
  select * into v from public.dms_versions where id = p_version_id for update;
  update public.dms_versions set status = 'superseded' where document_id = v.document_id and status = 'current';
  update public.dms_versions
     set status = 'current', published_at = now(), published_without_review = coalesce(p_without_review, false)
   where id = v.id;
  update public.dms_documents
     set lifecycle = 'published', current_version = v.version, expiry_date = coalesce(v.expiry_date, expiry_date), fields = v.fields
   where id = v.document_id
  returning * into d;
  update public.dms_requests set status = 'done', done_at = now(), fulfilled_version_id = v.id
   where id = v.request_id or (kind = 'renewal' and document_id = d.id and status in ('open', 'submitted') and v.version > 1);
  perform private.write_audit(d.org_id,
    case when p_without_review then 'dms.published_without_review' when v.version = 1 then 'dms.document_published' else 'dms.version_published' end,
    'dms_documents', d.id, null, jsonb_build_object('doc_code', d.doc_code, 'version', v.version, 'file_hash', v.file_hash));
  return d;
end;
$$;

-- -----------------------------------------------------------------------------
-- Upload (redefined): requests and custodians; new versions of pending documents
-- -----------------------------------------------------------------------------
create or replace function public.dms_register_upload(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_file    jsonb := coalesce(p -> 'file', '{}');
  v_kind    text := v_file ->> 'kind';
  v_hash    text := lower(coalesce(v_file ->> 'hash', ''));
  v_size    integer := coalesce((v_file ->> 'size_bytes')::integer, 0);
  v_req     public.dms_requests;
  v_doc     public.dms_documents;
  v_type    public.dms_doc_types;
  v_dup     text;
  v_dept    uuid;
  v_folder  uuid;
  v_dcode   text;
  v_seq     integer;
  v_cls     text;
  v_scope   text;
  v_sdepts  uuid[];
  v_roles   uuid[];
  v_fields  jsonb;
  v_expiry  date;
  v_review  date;
  v_title   text := nullif(btrim(coalesce(p ->> 'title', '')), '');
  v_ver     integer;
  v_vid     uuid := gen_random_uuid();
  v_path    text;
begin
  if nullif(p ->> 'request_id', '') is not null then
    select * into v_req from public.dms_requests
    where id = (p ->> 'request_id')::uuid and org_id = v_org and assignee_user_id = auth.uid() and status = 'open' for update;
    if not found then
      raise exception 'This request is not open for you' using errcode = 'P0002';
    end if;
  elsif not private.dms_can_upload() then
    raise exception 'You do not have permission for this action (dms.upload)' using errcode = '42501';
  end if;
  perform private.dms_require_enabled(v_org);

  -- The file
  if v_kind is null or v_kind not in ('pdf', 'docx', 'xlsx', 'json', 'jpg', 'png') then
    raise exception 'Only PDF, Word (DOCX), Excel (XLSX), JSON, JPG and PNG files can be uploaded' using errcode = '22023';
  end if;
  if not private.dms_kind_mime_ok(v_kind, v_file ->> 'mime') then
    raise exception 'The file type does not match its name' using errcode = '22023';
  end if;
  if v_size not between 1 and 26214400 then
    raise exception 'The file must be smaller than 25 MB' using errcode = '22023';
  end if;
  if v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'The file fingerprint is missing' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(v_file ->> 'name'), '')) not between 1 and 255 then
    raise exception 'The file name is missing' using errcode = '22023';
  end if;
  select d.doc_code || ' v' || v.version into v_dup
  from public.dms_versions v join public.dms_documents d on d.id = v.document_id
  where v.org_id = v_org and v.file_hash = v_hash and v.status not in ('cancelled', 'rejected')
    and not (v.status = 'uploading' and v.uploaded_by = auth.uid())
  limit 1;
  if v_dup is not null then
    raise exception 'This file is already saved as %', v_dup using errcode = '23505';
  end if;
  update public.dms_versions set status = 'cancelled'
   where org_id = v_org and file_hash = v_hash and status = 'uploading' and uploaded_by = auth.uid();
  update public.dms_documents d set lifecycle = 'cancelled'
   where d.org_id = v_org and d.lifecycle = 'pending'
     and not exists (select 1 from public.dms_versions v where v.document_id = d.id and v.status <> 'cancelled');

  if coalesce(nullif(p ->> 'document_id', '')::uuid, v_req.document_id) is not null then
    -- A new version (or renewal) of an existing document.
    select * into v_doc from public.dms_documents
    where id = coalesce(v_req.document_id, (p ->> 'document_id')::uuid) and org_id = v_org for update;
    if not found or (v_req.id is null and not private.dms_can_read(v_doc)) then
      raise exception 'Document not found' using errcode = 'P0002';
    end if;
    if v_req.id is null and not private.dms_can_edit(v_doc) then
      raise exception 'You can only upload new versions for your own department' using errcode = '42501';
    end if;
    if v_doc.lifecycle not in ('published', 'pending') then
      raise exception 'Only a published document gets a new version' using errcode = '23514';
    end if;
    select * into v_type from public.dms_doc_types where id = v_doc.doc_type_id;
    update public.dms_versions set status = 'cancelled'
     where document_id = v_doc.id and status = 'uploading' and (uploaded_at < now() - interval '1 hour' or uploaded_by = auth.uid());
    if exists (select 1 from public.dms_versions where document_id = v_doc.id and status = 'uploading') then
      raise exception 'Someone is uploading a new version of this document right now; try again in a moment' using errcode = '23514';
    end if;
    if exists (select 1 from public.dms_versions where document_id = v_doc.id and status = 'in_review') then
      raise exception 'A new version of this document is waiting for review; wait for the decision first' using errcode = '23514';
    end if;
    v_fields := v_doc.fields || case when p ? 'fields' then private.dms_clean_fields(v_type.field_schema, v_doc.fields || coalesce(p -> 'fields', '{}')) else '{}' end;
    v_expiry := case when v_type.has_expiry then coalesce(nullif(p ->> 'expiry_date', '')::date,
                       case when v_type.expiry_default = 'fiscal_year_end' then private.dms_fiscal_year_end(current_date) end) end;
    if v_type.has_expiry and v_expiry is null then
      raise exception 'Enter the expiry date of the new file' using errcode = '22023';
    end if;
    v_ver := (select coalesce(max(version), 0) + 1 from public.dms_versions where document_id = v_doc.id);
  else
    -- A new document.
    select * into v_type from public.dms_doc_types
    where id = coalesce(nullif(p ->> 'doc_type_id', '')::uuid, v_req.doc_type_id) and org_id = v_org and active;
    if not found then
      raise exception 'Choose a document type' using errcode = '22023';
    end if;
    v_folder := coalesce(nullif(p ->> 'folder_id', '')::uuid, v_req.folder_id, v_type.folder_id);
    if not exists (select 1 from public.dms_folders where id = v_folder and org_id = v_org and enabled) then
      raise exception 'Choose an open folder' using errcode = '22023';
    end if;
    v_dept := coalesce(v_req.department_id, nullif(p ->> 'department_id', '')::uuid, private.dms_my_department());
    if v_dept is null or not exists (select 1 from public.departments where id = v_dept and org_id = v_org and status = 'active') then
      raise exception 'Choose a department' using errcode = '22023';
    end if;
    if v_req.id is null and not private.dms_can_use_department(v_dept)
       and not (private.dms_is_custodian(v_folder) and v_dept = private.dms_my_department()) then
      raise exception 'You can only upload for your own department' using errcode = '42501';
    end if;
    v_dcode := private.dms_dept_code(v_dept);
    if v_dcode is null then
      raise exception 'The department "%" has no short code yet. Add one in Organization → Departments (e.g. HR, ACC), then upload again',
        (select name from public.departments where id = v_dept) using errcode = '23514';
    end if;
    if v_title is null or char_length(v_title) not between 3 and 200 then
      raise exception 'The title needs 3 to 200 characters' using errcode = '22023';
    end if;
    select d.doc_code into v_dup from public.dms_documents d
    where d.org_id = v_org and d.doc_type_id = v_type.id and d.department_id = v_dept
      and lower(d.title) = lower(v_title) and d.lifecycle in ('published', 'pending')
    limit 1;
    if v_dup is not null then
      raise exception 'A document with this title already exists: %. Open it and upload the file as its new version', v_dup
        using errcode = '23505';
    end if;
    v_cls := coalesce(nullif(p ->> 'classification', ''), v_type.default_classification);
    if v_cls not in ('public', 'internal', 'confidential', 'restricted') then
      raise exception 'Unknown classification' using errcode = '22023';
    end if;
    v_scope := coalesce(nullif(p ->> 'scope', ''), 'company');
    v_sdepts := case when v_scope = 'departments' then private.uuid_array(p, 'scope_department_ids') else '{}' end;
    if v_scope not in ('company', 'departments')
       or (v_scope = 'departments' and (cardinality(v_sdepts) = 0
           or (select count(*) from public.departments where id = any (v_sdepts) and org_id = v_org) <> cardinality(v_sdepts))) then
      raise exception 'Choose who may read it: the whole company or departments of your company' using errcode = '22023';
    end if;
    v_roles := case when v_cls = 'restricted' then private.uuid_array(p, 'restricted_role_ids') else '{}' end;
    if v_cls = 'restricted' and (cardinality(v_roles) = 0
       or (select count(*) from public.roles where id = any (v_roles) and org_id = v_org) <> cardinality(v_roles)) then
      raise exception 'A restricted document needs the roles that may read it' using errcode = '22023';
    end if;
    if coalesce(p ->> 'language', 'en') not in ('en', 'bn', 'both') then
      raise exception 'Unknown language' using errcode = '22023';
    end if;
    v_fields := private.dms_clean_fields(v_type.field_schema, coalesce(p -> 'fields', '{}'));
    v_expiry := case when v_type.has_expiry then coalesce(nullif(p ->> 'expiry_date', '')::date,
                       case when v_type.expiry_default = 'fiscal_year_end' then private.dms_fiscal_year_end(current_date) end) end;
    if v_type.has_expiry and v_expiry is null then
      raise exception 'Enter the expiry date' using errcode = '22023';
    end if;
    v_review := coalesce(nullif(p ->> 'next_review_date', '')::date,
                         case when v_type.review_months is not null then current_date + make_interval(months => v_type.review_months) end::date);

    insert into public.dms_code_sequences as s (org_id, dept_code, type_code, last_seq)
    values (v_org, v_dcode, v_type.code, 1)
    on conflict (org_id, dept_code, type_code) do update set last_seq = s.last_seq + 1
    returning last_seq into v_seq;
    insert into public.dms_documents (org_id, doc_code, dept_code, seq, title, folder_id, doc_type_id, department_id,
                                      owner_user_id, classification, scope, scope_department_ids, restricted_role_ids,
                                      language, fields, expiry_date, next_review_date)
    values (v_org, v_dcode || '-' || v_type.code || '-' || lpad(v_seq::text, 4, '0'), v_dcode, v_seq, v_title,
            v_folder, v_type.id, v_dept, auth.uid(), v_cls, v_scope, v_sdepts, v_roles,
            coalesce(p ->> 'language', 'en'), v_fields, v_expiry, v_review)
    returning * into v_doc;
    v_ver := 1;
  end if;

  v_path := v_org || '/' || v_doc.id || '/v' || v_ver || '.' || v_kind;
  insert into public.dms_versions (id, org_id, document_id, version, original_file_name, file_kind, mime, size_bytes,
                                   file_hash, file_path, change_note, expiry_date, fields, uploaded_by, request_id)
  values (v_vid, v_org, v_doc.id, v_ver, left(btrim(v_file ->> 'name'), 255), v_kind, v_file ->> 'mime', v_size, v_hash,
          v_path, left(nullif(btrim(coalesce(p ->> 'change_note', '')), ''), 500), v_expiry, v_fields, auth.uid(), v_req.id);
  return jsonb_build_object('document_id', v_doc.id, 'version_id', v_vid, 'version', v_ver, 'doc_code', v_doc.doc_code,
                            'version_name', v_doc.doc_code || '_v' || v_ver, 'path', v_path, 'expiry_date', v_expiry);
end;
$$;

-- The file is in storage. The Admin's uploads (or every upload when review is off) publish at once;
-- everyone else's go to review.
create or replace function public.dms_confirm_upload(p_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v      public.dms_versions;
  d      public.dms_documents;
  s      public.dms_settings;
  v_admin boolean := private.is_org_admin();
  r      record;
begin
  select * into v from public.dms_versions where id = p_version_id and org_id = v_org for update;
  if not found or v.uploaded_by is distinct from auth.uid() then
    raise exception 'Upload not found' using errcode = 'P0002';
  end if;
  if v.status <> 'uploading' then
    raise exception 'This upload is already finished' using errcode = '23514';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'dms-documents' and o.name = v.file_path) then
    raise exception 'The file has not arrived yet; upload it again' using errcode = '23514';
  end if;
  select * into s from public.dms_settings where org_id = v_org;
  if v_admin or not s.require_review then
    d := private.dms_publish_version(v.id, v_admin and s.require_review);
    return private.dms_doc_json(d) || jsonb_build_object('status', 'published');
  end if;

  update public.dms_versions
     set status = 'in_review', submitted_at = now(), review_due_date = private.dms_add_working_days(v_org, current_date, s.review_days)
   where id = v.id
  returning * into v;
  update public.dms_requests set status = 'submitted', fulfilled_version_id = v.id where id = v.request_id and status = 'open';
  select * into d from public.dms_documents where id = v.document_id;
  perform private.write_audit(v_org, 'dms.submitted_for_review', 'dms_documents', d.id, null,
    jsonb_build_object('doc_code', d.doc_code, 'version', v.version));
  -- Tell the Admins (central review).
  for r in select m.user_id from public.org_members m join public.roles ro on ro.id = m.role_id
           where m.org_id = v_org and m.status = 'active' and ro.system_key = 'admin' and m.user_id <> auth.uid() loop
    perform private.dms_queue_email(v_org, r.user_id, d.id, 'dms_review',
      'Document to review: ' || d.doc_code || '_v' || v.version || ' ' || d.title,
      'A document is waiting for your review: ' || d.doc_code || '_v' || v.version || ' — ' || d.title
      || E'\nUploaded by ' || coalesce(private.dms_user_name(auth.uid()), 'someone') || '. Review by ' || to_char(v.review_due_date, 'DD Mon YYYY')
      || E'.\nOpen Olympus HRIS → Documents → Review.');
  end loop;
  return private.dms_doc_json(d) || jsonb_build_object('status', 'in_review', 'review_due_date', v.review_due_date);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: review
-- -----------------------------------------------------------------------------
create or replace function public.dms_decide(p_version_id uuid, p_approve boolean, p_comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v         public.dms_versions;
  d         public.dms_documents;
  v_comment text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  select * into v from public.dms_versions where id = p_version_id and org_id = v_org for update;
  if not found then
    raise exception 'Version not found' using errcode = 'P0002';
  end if;
  select * into d from public.dms_documents where id = v.document_id;
  if not private.dms_can_review(d) then
    raise exception 'You do not have permission for this action (dms.approve)' using errcode = '42501';
  end if;
  if v.status <> 'in_review' then
    raise exception 'This version is not waiting for review' using errcode = '23514';
  end if;
  if v.uploaded_by = auth.uid() then
    raise exception 'You cannot review your own upload' using errcode = '23514';
  end if;
  if not coalesce(p_approve, false) and char_length(coalesce(v_comment, '')) < 3 then
    raise exception 'Write why it is rejected, so the uploader can fix it' using errcode = '22023';
  end if;
  update public.dms_versions set reviewed_by = auth.uid(), reviewed_at = now(), review_comment = v_comment where id = v.id;
  if p_approve then
    d := private.dms_publish_version(v.id, false);
    perform private.write_audit(v_org, 'dms.approved', 'dms_documents', d.id, null,
      jsonb_build_object('doc_code', d.doc_code, 'version', v.version, 'comment', v_comment));
    perform private.dms_queue_email(v_org, v.uploaded_by, d.id, 'dms_approved',
      'Approved: ' || d.doc_code || '_v' || v.version, 'Your document ' || d.doc_code || '_v' || v.version || ' — ' || d.title || ' is approved and published.');
    return private.dms_doc_json(d) || jsonb_build_object('status', 'published');
  end if;
  update public.dms_versions set status = 'rejected' where id = v.id;
  update public.dms_requests set status = 'open', fulfilled_version_id = null where id = v.request_id;
  perform private.write_audit(v_org, 'dms.rejected', 'dms_documents', d.id, null,
    jsonb_build_object('doc_code', d.doc_code, 'version', v.version, 'comment', v_comment));
  perform private.dms_queue_email(v_org, v.uploaded_by, d.id, 'dms_rejected',
    'Please fix: ' || d.doc_code || '_v' || v.version,
    'Your document ' || d.doc_code || '_v' || v.version || ' — ' || d.title || E' was sent back.\nReason: ' || v_comment
    || E'\nOpen Olympus HRIS → Documents → My tasks to upload it again.');
  return private.dms_doc_json(d) || jsonb_build_object('status', 'rejected');
end;
$$;

-- -----------------------------------------------------------------------------
-- API: requests and custodians
-- -----------------------------------------------------------------------------
create or replace function private.dms_can_request_for(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.org_members m where m.user_id = p_user_id and m.org_id = private.current_org_id() and m.status = 'active')
     and (private.has_permission('dms.manage') or private.has_permission('dms.upload_all')
          or (private.has_permission('dms.upload') and private.dms_my_department() is not null
              and private.dms_my_department() = (select e.department_id from public.org_members m join public.employees e on e.id = m.employee_id
                                                  where m.user_id = p_user_id and m.org_id = private.current_org_id() limit 1)))
$$;

-- People a request can go to (Admin / HR: everyone; Manager: own department).
create or replace function public.list_dms_people()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_all boolean := private.has_permission('dms.manage') or private.has_permission('dms.upload_all');
begin
  if not private.dms_can_upload() then
    raise exception 'You do not have permission for this action (dms.upload)' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', coalesce(e.full_name, up.full_name),
                                        'department_id', e.department_id,
                                        'department', (select d.name from public.departments d where d.id = e.department_id))
                     order by coalesce(e.full_name, up.full_name))
    from public.org_members m
    left join public.employees e on e.id = m.employee_id
    left join public.user_profiles up on up.id = m.user_id
    where m.org_id = v_org and m.status = 'active'
      and (v_all or (e.department_id is not null and e.department_id = private.dms_my_department()))), '[]'::jsonb);
end;
$$;

-- p: {assignee_user_id, folder_id, doc_type_id, document_id, note, due_date}
create or replace function public.create_dms_request(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_user    uuid := nullif(p ->> 'assignee_user_id', '')::uuid;
  v_doc     public.dms_documents;
  v_dept    uuid;
  v_due     date := nullif(p ->> 'due_date', '')::date;
  v_note    text := nullif(btrim(coalesce(p ->> 'note', '')), '');
  v_id      uuid;
begin
  if v_user is null or not private.dms_can_request_for(v_user) then
    raise exception 'You can ask only people you manage (Admin and HR: anyone; Manager: your department)' using errcode = '42501';
  end if;
  perform private.dms_require_enabled(v_org);
  if nullif(p ->> 'document_id', '') is not null then
    v_doc := private.load_dms_document((p ->> 'document_id')::uuid);
    v_dept := v_doc.department_id;
  else
    v_dept := (select e.department_id from public.org_members m join public.employees e on e.id = m.employee_id
               where m.user_id = v_user and m.org_id = v_org limit 1);
    if v_dept is null then
      raise exception 'This person has no department, so the document cannot be named' using errcode = '23514';
    end if;
  end if;
  if nullif(p ->> 'folder_id', '') is not null
     and not exists (select 1 from public.dms_folders where id = (p ->> 'folder_id')::uuid and org_id = v_org and enabled) then
    raise exception 'Choose an open folder' using errcode = '22023';
  end if;
  if nullif(p ->> 'doc_type_id', '') is not null
     and not exists (select 1 from public.dms_doc_types where id = (p ->> 'doc_type_id')::uuid and org_id = v_org and active) then
    raise exception 'Choose a document type' using errcode = '22023';
  end if;
  if v_due is not null and v_due < current_date then
    raise exception 'The due date is in the past' using errcode = '22023';
  end if;
  if v_note is null and v_doc.id is null and nullif(p ->> 'doc_type_id', '') is null then
    raise exception 'Say what to upload: a note, a document type or a document' using errcode = '22023';
  end if;
  insert into public.dms_requests (org_id, requested_by, assignee_user_id, department_id, folder_id, doc_type_id, document_id, note, due_date)
  values (v_org, auth.uid(), v_user, v_dept, nullif(p ->> 'folder_id', '')::uuid, nullif(p ->> 'doc_type_id', '')::uuid,
          v_doc.id, left(v_note, 1000), v_due)
  returning id into v_id;
  perform private.dms_queue_email(v_org, v_user, v_id, 'dms_request',
    'Document requested' || coalesce(' by ' || to_char(v_due, 'DD Mon YYYY'), ''),
    coalesce(private.dms_user_name(auth.uid()), 'Your company') || ' asks you to upload '
    || coalesce(v_doc.doc_code || ' ' || v_doc.title, (select t.name from public.dms_doc_types t where t.id = nullif(p ->> 'doc_type_id', '')::uuid), 'a document')
    || coalesce(' by ' || to_char(v_due, 'DD Mon YYYY'), '') || '.' || coalesce(E'\nNote: ' || v_note, '')
    || E'\nOpen Olympus HRIS → Documents → My tasks.');
  return v_id;
end;
$$;

create or replace function public.cancel_dms_request(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.dms_requests;
begin
  select * into r from public.dms_requests where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Request not found' using errcode = 'P0002';
  end if;
  if not (r.requested_by = auth.uid() or private.has_permission('dms.manage')) then
    raise exception 'Only the person who asked (or the document manager) can cancel it' using errcode = '42501';
  end if;
  if r.status not in ('open', 'submitted') then
    raise exception 'This request is already finished' using errcode = '23514';
  end if;
  update public.dms_requests set status = 'cancelled', done_at = now() where id = p_id;
end;
$$;

create or replace function public.save_dms_custodian(p_folder_id uuid, p_user_id uuid, p_active boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('dms.manage');
  if not exists (select 1 from public.dms_folders where id = p_folder_id and org_id = v_org) then
    raise exception 'Folder not found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.org_members where user_id = p_user_id and org_id = v_org and status = 'active') then
    raise exception 'Choose a person with a login in your company' using errcode = '22023';
  end if;
  insert into public.dms_custodians (org_id, folder_id, user_id, active) values (v_org, p_folder_id, p_user_id, coalesce(p_active, true))
  on conflict (org_id, folder_id, user_id) do update set active = excluded.active;
end;
$$;

-- p: {require_review, review_days, reminder_days}
create or replace function public.save_dms_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_days smallint[];
begin
  perform private.require_permission('dms.manage');
  if p ? 'reminder_days' then
    v_days := (select array_agg(distinct x::smallint order by x::smallint desc) from jsonb_array_elements_text(p -> 'reminder_days') x);
    if v_days is null or cardinality(v_days) > 6 or 0 > any (v_days) or 365 < any (v_days) then
      raise exception 'Reminder days: 1 to 6 numbers between 0 and 365' using errcode = '22023';
    end if;
  end if;
  if p ? 'review_days' and coalesce((p ->> 'review_days')::int, 0) not between 1 and 30 then
    raise exception 'The review period must be 1 to 30 working days' using errcode = '22023';
  end if;
  update public.dms_settings
     set require_review = coalesce((p ->> 'require_review')::boolean, require_review),
         review_days = coalesce((p ->> 'review_days')::smallint, review_days),
         reminder_days = coalesce(v_days, reminder_days)
   where org_id = private.current_org_id();
end;
$$;

-- -----------------------------------------------------------------------------
-- Reminders (idempotent; run when DMS lists are opened)
-- -----------------------------------------------------------------------------
create or replace function private.run_dms_reminders(p_org_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  s       public.dms_settings;
  r       record;
  v_step  smallint;
  v_sent  integer := 0;
  v_mails smallint;
  u       record;
begin
  select * into s from public.dms_settings where org_id = p_org_id;
  if not found or not s.enabled then
    return 0;
  end if;
  for r in
    select d.id, d.doc_code, d.title, d.folder_id, d.department_id, d.owner_user_id, x.kind, x.due
    from public.dms_documents d
    cross join lateral (values ('expiry', d.expiry_date), ('review', d.next_review_date)) as x (kind, due)
    where d.org_id = p_org_id and d.lifecycle = 'published' and x.due is not null
      and x.due - current_date <= (select max(v) from unnest(s.reminder_days) v)
  loop
    -- The current step: the smallest reminder day not below the days left (or 0 once due).
    v_step := (select min(v) from unnest(s.reminder_days) v where v >= greatest(r.due - current_date, 0));
    if v_step is null or exists (select 1 from public.dms_reminders m where m.document_id = r.id and m.kind = r.kind
                                 and m.due_date = r.due and m.step_days = v_step) then
      continue;
    end if;
    v_mails := 0;
    for u in
      select distinct x.user_id from (
        select r.owner_user_id as user_id
        union all
        select c.user_id from public.dms_custodians c
        where c.active and c.folder_id in (with recursive up as (select f.id, f.parent_id from public.dms_folders f where f.id = r.folder_id
                                                                union all select f.id, f.parent_id from public.dms_folders f join up on f.id = up.parent_id)
                                           select id from up)) x
    loop
      if private.dms_queue_email(p_org_id, u.user_id, r.id, 'dms_' || r.kind || '_reminder',
           case when r.kind = 'expiry' then 'Expiry ' else 'Review ' end
           || case when r.due < current_date then 'passed' when r.due = current_date then 'today' else 'in ' || (r.due - current_date) || ' days' end
           || ': ' || r.doc_code || ' ' || r.title,
           r.doc_code || ' — ' || r.title || case when r.kind = 'expiry' then E'\nExpiry date: ' else E'\nReview date: ' end
           || to_char(r.due, 'DD Mon YYYY') || E'.\nOpen Olympus HRIS → Documents to upload the renewal or the reviewed version.') then
        v_mails := v_mails + 1;
      end if;
    end loop;
    insert into public.dms_reminders (org_id, document_id, kind, due_date, step_days, emails)
    values (p_org_id, r.id, r.kind, r.due, v_step, v_mails);
    -- A renewal task for the owner (once per document while one is open).
    if r.kind = 'expiry' then
      insert into public.dms_requests (org_id, kind, assignee_user_id, department_id, document_id, note, due_date)
      values (p_org_id, 'renewal', r.owner_user_id, r.department_id, r.id, 'Upload the renewed ' || r.title, r.due)
      on conflict do nothing;
    end if;
    v_sent := v_sent + 1;
  end loop;
  return v_sent;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: tasks (everyone) and the review queue
-- -----------------------------------------------------------------------------
create or replace function private.dms_request_json(r public.dms_requests)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'kind', r.kind, 'status', r.status, 'note', r.note, 'due_date', r.due_date,
    'overdue', r.status = 'open' and r.due_date < current_date,
    'requested_by', case when r.requested_by is null then 'System (expiry)' else private.dms_user_name(r.requested_by) end,
    'assignee_user_id', r.assignee_user_id, 'assignee', private.dms_user_name(r.assignee_user_id),
    'department_id', r.department_id, 'department', (select d.name from public.departments d where d.id = r.department_id),
    'folder_id', r.folder_id, 'folder', (select f.name from public.dms_folders f where f.id = r.folder_id),
    'doc_type_id', r.doc_type_id, 'type_name', (select t.name from public.dms_doc_types t where t.id = r.doc_type_id),
    'document_id', r.document_id, 'doc_code', (select d.doc_code from public.dms_documents d where d.id = r.document_id),
    'doc_title', (select d.title from public.dms_documents d where d.id = r.document_id),
    'created_at', r.created_at)
$$;

create or replace function private.dms_version_task_json(v public.dms_versions)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.dms_doc_json(d) || jsonb_build_object(
    'version_id', v.id, 'version_status', v.status, 'pending_version', v.version,
    'pending_version_name', d.doc_code || '_v' || v.version, 'submitted_at', v.submitted_at,
    'review_due_date', v.review_due_date, 'review_overdue', v.status = 'in_review' and v.review_due_date < current_date,
    'review_comment', v.review_comment, 'reviewed_at', v.reviewed_at, 'uploaded_by_name', private.dms_user_name(v.uploaded_by),
    'reviewed_by_name', private.dms_user_name(v.reviewed_by), 'original_file_name', v.original_file_name)
  from public.dms_documents d where d.id = v.document_id
$$;

create or replace function public.list_dms_tasks()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_review jsonb;
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  perform private.run_dms_reminders(v_org);
  v_review := coalesce((
    select jsonb_agg(private.dms_version_task_json(v) order by v.review_due_date, v.submitted_at)
    from public.dms_versions v join public.dms_documents d on d.id = v.document_id
    where v.org_id = v_org and v.status = 'in_review' and v.uploaded_by <> auth.uid() and private.dms_can_review(d)), '[]'::jsonb);
  return jsonb_build_object(
    'can_review', private.is_org_admin() or private.has_permission('dms.approve'),
    'can_request', private.dms_can_upload(),
    'requested_from_me', coalesce((select jsonb_agg(private.dms_request_json(r) order by r.due_date nulls last, r.created_at)
                                   from public.dms_requests r where r.org_id = v_org and r.assignee_user_id = auth.uid() and r.status = 'open'), '[]'::jsonb),
    'my_uploads', coalesce((select jsonb_agg(private.dms_version_task_json(v) order by v.updated_at desc)
                            from public.dms_versions v
                            where v.org_id = v_org and v.uploaded_by = auth.uid()
                              and (v.status = 'in_review'
                                   or (v.status = 'rejected' and not exists (select 1 from public.dms_versions n where n.document_id = v.document_id
                                                                             and n.version > v.version and n.status <> 'cancelled')))), '[]'::jsonb),
    'to_review', v_review,
    'requests_i_made', coalesce((select jsonb_agg(private.dms_request_json(r) order by r.status, r.due_date nulls last)
                                 from public.dms_requests r
                                 where r.org_id = v_org and r.status in ('open', 'submitted')
                                   and (r.requested_by = auth.uid() or (private.has_permission('dms.manage') and r.requested_by is not null))), '[]'::jsonb),
    'counts', jsonb_build_object(
      'requested_from_me', (select count(*) from public.dms_requests r where r.org_id = v_org and r.assignee_user_id = auth.uid() and r.status = 'open'),
      'to_review', jsonb_array_length(v_review),
      'review_overdue', (select count(*) from jsonb_array_elements(v_review) x where (x ->> 'review_overdue')::boolean),
      'upload_overdue', (select count(*) from public.dms_requests r where r.org_id = v_org and r.status = 'open' and r.due_date < current_date
                         and (r.assignee_user_id = auth.uid() or r.requested_by = auth.uid() or private.has_permission('dms.manage')))));
end;
$$;

-- -----------------------------------------------------------------------------
-- Redefined reads: versions under review, setup with settings and custodians, overview counts
-- -----------------------------------------------------------------------------
create or replace function public.get_dms_document(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d        public.dms_documents := private.load_dms_document(p_id);
  v_edit   boolean := private.dms_can_edit(d);
  v_review boolean := private.dms_can_review(d);
begin
  return private.dms_doc_json(d) || jsonb_build_object(
    'can_edit', v_edit, 'can_manage', private.has_permission('dms.manage'), 'can_review', v_review,
    'custodians', coalesce((select jsonb_agg(private.dms_user_name(c.user_id)) from public.dms_custodians c
                            where c.folder_id = d.folder_id and c.active), '[]'::jsonb),
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'version', v.version, 'version_name', d.doc_code || '_v' || v.version, 'status', v.status,
               'original_file_name', v.original_file_name, 'file_kind', v.file_kind, 'size_bytes', v.size_bytes,
               'expiry_date', v.expiry_date, 'change_note', v.change_note, 'uploaded_at', v.uploaded_at,
               'published_at', v.published_at, 'uploaded_by', private.dms_user_name(v.uploaded_by),
               'uploaded_by_me', v.uploaded_by = auth.uid(),
               'review_due_date', v.review_due_date, 'review_overdue', v.status = 'in_review' and v.review_due_date < current_date,
               'reviewed_by', private.dms_user_name(v.reviewed_by), 'reviewed_at', v.reviewed_at, 'review_comment', v.review_comment,
               'published_without_review', v.published_without_review)
             order by v.version desc)
      from public.dms_versions v
      where v.document_id = d.id
        and (v.status = 'current'
             or (v.status = 'superseded' and v_edit)
             or (v.status in ('in_review', 'rejected') and (v_edit or v_review or v.uploaded_by = auth.uid())))), '[]'::jsonb));
end;
$$;

create or replace function public.dms_file_path(p_version_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v     public.dms_versions;
  d     public.dms_documents;
begin
  select * into v from public.dms_versions where id = p_version_id and org_id = v_org;
  if not found then
    raise exception 'File not found' using errcode = 'P0002';
  end if;
  d := private.load_dms_document(v.document_id);
  if not (v.status = 'current'
          or (v.status = 'superseded' and private.dms_can_edit(d))
          or (v.status in ('in_review', 'rejected') and (private.dms_can_edit(d) or private.dms_can_review(d) or v.uploaded_by = auth.uid()))) then
    raise exception 'File not found' using errcode = 'P0002';
  end if;
  insert into public.dms_access_log (org_id, document_id, version_id, user_id) values (v_org, d.id, v.id, auth.uid());
  return jsonb_build_object('path', v.file_path, 'file_name', d.doc_code || '_v' || v.version || '.' || v.file_kind, 'mime', v.mime);
end;
$$;

create or replace function private.dms_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.dms_versions;
  d public.dms_documents;
begin
  if p_name is null or split_part(p_name, '/', 1) !~ '^[0-9a-f-]{36}$' then
    return false;
  end if;
  select * into v from public.dms_versions
  where file_path = p_name and org_id = split_part(p_name, '/', 1)::uuid and status <> 'cancelled';
  if not found or v.org_id is distinct from private.current_org_id() then
    return false;
  end if;
  if p_write then
    return v.status = 'uploading' and v.uploaded_by = auth.uid();
  end if;
  select * into d from public.dms_documents where id = v.document_id;
  return private.dms_can_read(d) and (
    v.status = 'current'
    or (v.status = 'superseded' and private.dms_can_edit(d))
    or (v.status in ('in_review', 'rejected') and (private.dms_can_edit(d) or private.dms_can_review(d) or v.uploaded_by = auth.uid())));
end;
$$;

create or replace function public.get_dms_setup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  s     public.dms_settings;
begin
  perform private.require_permission('dms.manage');
  perform private.seed_dms_defaults(v_org);
  select * into s from public.dms_settings where org_id = v_org;
  return jsonb_build_object(
    'enabled', s.enabled, 'profiles', to_jsonb(s.profiles), 'no_iso', s.no_iso,
    'require_review', s.require_review, 'review_days', s.review_days, 'reminder_days', to_jsonb(s.reminder_days),
    'catalog', (select jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'edition', p.edition, 'summary', p.summary,
                                                    'who_needs_it', p.who_needs_it, 'selected', p.code = any (s.profiles),
                                                    'folders', (select jsonb_agg(c.name order by c.sort) from public.dms_catalog_folders c
                                                                where c.profile_code = p.code))
                                 order by p.sort) from public.dms_iso_profiles p),
    'folders', private.dms_folders_json(v_org, true),
    'types', private.dms_types_json(v_org, true),
    'custodians', coalesce((select jsonb_agg(jsonb_build_object('folder_id', c.folder_id, 'user_id', c.user_id, 'name', private.dms_user_name(c.user_id)))
                            from public.dms_custodians c where c.org_id = v_org and c.active), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'name', coalesce(e.full_name, up.full_name)) order by coalesce(e.full_name, up.full_name))
                        from public.org_members m left join public.employees e on e.id = m.employee_id
                        left join public.user_profiles up on up.id = m.user_id
                        where m.org_id = v_org and m.status = 'active'), '[]'::jsonb),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'code', private.dms_dept_code(d.id))
                                              order by d.name)
                             from public.departments d where d.org_id = v_org and d.status = 'active'), '[]'::jsonb));
end;
$$;

create or replace function public.get_dms_overview(p_from date default null, p_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_from date := coalesce(p_from, current_date);
  v_to   date := coalesce(p_to, current_date + 90);
  s      public.dms_settings;
  v_tasks jsonb;
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  if v_to < v_from or v_to > v_from + 3660 then
    raise exception 'Choose a date range of at most 10 years' using errcode = '22023';
  end if;
  perform private.seed_dms_defaults(v_org);
  v_tasks := public.list_dms_tasks() -> 'counts';
  select * into s from public.dms_settings where org_id = v_org;
  return (
    with readable as (
      select d as doc, d.expiry_date from public.dms_documents d
      where d.org_id = v_org and d.lifecycle = 'published' and private.dms_can_read(d)
    ), used_depts as (
      select d.id, d.name, private.dms_dept_code(d.id) as code from public.departments d
      where d.org_id = v_org and d.status = 'active'
    )
    select jsonb_build_object(
      'enabled', s.enabled,
      'steps', jsonb_build_object(
        'iso', jsonb_build_object('done', cardinality(s.profiles) > 0 or s.no_iso, 'profiles', to_jsonb(s.profiles), 'no_iso', s.no_iso),
        'departments', jsonb_build_object(
          'done', exists (select 1 from used_depts) and not exists (select 1 from used_depts where code is null),
          'total', (select count(*) from used_depts), 'missing_code', (select count(*) from used_depts where code is null)),
        'documents', jsonb_build_object('done', exists (select 1 from public.dms_documents d where d.org_id = v_org and d.lifecycle = 'published'),
                                        'total', (select count(*) from public.dms_documents d where d.org_id = v_org and d.lifecycle = 'published')),
        'ai', jsonb_build_object('done', false, 'indexed', 0)),
      'counts', jsonb_build_object(
        'documents', (select count(*) from readable),
        'expiring_60', (select count(*) from readable where expiry_date between current_date and current_date + 60),
        'expired', (select count(*) from readable where expiry_date < current_date),
        'awaiting_approval', (v_tasks ->> 'to_review')::int,
        'review_overdue', (v_tasks ->> 'review_overdue')::int,
        'upload_overdue', (v_tasks ->> 'upload_overdue')::int,
        'requested_from_me', (v_tasks ->> 'requested_from_me')::int,
        'indexed', 0),
      'expiring', coalesce((
        select jsonb_agg(private.dms_doc_json(r.doc) order by r.expiry_date)
        from readable r
        where r.expiry_date is not null and r.expiry_date <= v_to and (r.expiry_date >= v_from or r.expiry_date < current_date)), '[]'::jsonb))
  );
end;
$$;

-- Types are listed for everyone: a person uploading for a request needs them without dms.upload.
create or replace function public.get_dms_library()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_upload boolean := private.dms_can_upload();
  v_all    boolean := private.has_permission('dms.manage') or private.has_permission('dms.upload_all');
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  perform private.seed_dms_defaults(v_org);
  return jsonb_build_object(
    'enabled', (select s.enabled from public.dms_settings s where s.org_id = v_org),
    'can', jsonb_build_object('manage', private.has_permission('dms.manage'), 'upload', v_upload, 'upload_all', v_all,
                              'review', private.is_org_admin() or private.has_permission('dms.approve')),
    'my_department_id', private.dms_my_department(),
    'folders', private.dms_folders_json(v_org, false),
    'types', private.dms_types_json(v_org, false),
    'departments', case when v_upload then coalesce((
        select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'code', private.dms_dept_code(d.id)) order by d.name)
        from public.departments d
        where d.org_id = v_org and d.status = 'active' and (v_all or d.id = private.dms_my_department())), '[]'::jsonb)
      else '[]'::jsonb end,
    'all_departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name)
                                 from public.departments d where d.org_id = v_org and d.status = 'active'), '[]'::jsonb),
    'roles', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) order by r.name)
                       from public.roles r where r.org_id = v_org and r.status = 'active'), '[]'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.dms_custodians enable row level security;
alter table public.dms_requests   enable row level security;
alter table public.dms_reminders  enable row level security;
revoke all on table public.dms_custodians, public.dms_requests, public.dms_reminders from anon, authenticated;

revoke all on function
  public.dms_decide(uuid, boolean, text), public.list_dms_people(), public.create_dms_request(jsonb), public.cancel_dms_request(uuid),
  public.save_dms_custodian(uuid, uuid, boolean), public.save_dms_settings(jsonb), public.list_dms_tasks()
from public, anon;
grant execute on function
  public.dms_decide(uuid, boolean, text), public.list_dms_people(), public.create_dms_request(jsonb), public.cancel_dms_request(uuid),
  public.save_dms_custodian(uuid, uuid, boolean), public.save_dms_settings(jsonb), public.list_dms_tasks()
to authenticated;

revoke all on function
  private.dms_add_working_days(uuid, date, integer), private.dms_is_custodian(uuid, uuid), private.dms_is_any_custodian(),
  private.dms_can_review(public.dms_documents), private.dms_user_name(uuid),
  private.dms_queue_email(uuid, uuid, uuid, text, text, text), private.dms_publish_version(uuid, boolean),
  private.dms_can_request_for(uuid), private.run_dms_reminders(uuid), private.dms_request_json(public.dms_requests),
  private.dms_version_task_json(public.dms_versions)
from public, anon, authenticated;
