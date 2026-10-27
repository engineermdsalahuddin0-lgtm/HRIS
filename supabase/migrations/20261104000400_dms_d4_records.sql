-- =============================================================================
-- DMS D4: retention rules, legal hold, two-person disposal with proof.
-- Module handbook: src/DMS/architecture.md 3.5, features.md (Records).
--
--   * dms.records (no default role; the Admin gives it): retention rules per type
--     (start: published / archived / expiry; years; action review or dispose). The
--     company sets the years (legal / records owner); without a rule nothing is
--     ever offered for disposal.
--   * Legal hold on a document blocks disposal until released (both audited).
--   * Disposal is never automatic: one records holder requests it for a due
--     document, ANOTHER approves; the browser then removes the files through the
--     Storage API (policy allows only files of an approved disposal) and the
--     database checks they are gone before closing it. The document row stays as a
--     tombstone; dms_disposals keeps code, version hashes, who and when.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.get_dms_compliance') is null then
    raise exception 'Apply 20261104000300_dms_d3_compliance.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('dms.records', 'dms', 'Records manager: retention rules, legal holds, request and approve disposal of documents', false)
on conflict (key) do nothing;

alter table public.dms_documents add column archived_at timestamptz;
alter table public.dms_documents drop constraint dms_documents_lifecycle_check;
alter table public.dms_documents add constraint dms_documents_lifecycle_check
  check (lifecycle in ('pending', 'published', 'archived', 'cancelled', 'disposed'));
alter table public.dms_versions drop constraint dms_versions_status_check;
alter table public.dms_versions add constraint dms_versions_status_check
  check (status in ('uploading', 'in_review', 'rejected', 'current', 'superseded', 'cancelled', 'disposing', 'disposed'));
update public.dms_documents set archived_at = updated_at where lifecycle = 'archived' and archived_at is null;

create table public.dms_retention_rules (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  doc_type_id  uuid not null,
  start_event  text not null check (start_event in ('published', 'archived', 'expiry')),
  retain_years smallint not null check (retain_years between 1 and 100),
  action       text not null check (action in ('review', 'dispose')),
  note         text check (note is null or char_length(note) <= 500),
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint dms_retention_rules_type_uq unique (org_id, doc_type_id),
  constraint dms_retention_rules_type_fk foreign key (org_id, doc_type_id) references public.dms_doc_types (org_id, id)
);
select private.attach_standard_triggers('public.dms_retention_rules');

create table public.dms_legal_holds (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations (id),
  document_id    uuid not null,
  reason         text not null check (char_length(btrim(reason)) between 3 and 500),
  placed_by      uuid not null references public.user_profiles (id),
  placed_at      timestamptz not null default now(),
  released_by    uuid references public.user_profiles (id),
  released_at    timestamptz,
  release_reason text check (release_reason is null or char_length(release_reason) <= 500),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint dms_legal_holds_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id)
);
create unique index dms_legal_holds_active_uq on public.dms_legal_holds (document_id) where released_at is null;
select private.attach_standard_triggers('public.dms_legal_holds');

create table public.dms_disposals (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  document_id  uuid not null,
  doc_code     text not null,
  title        text not null,
  version_ids  uuid[] not null default '{}',
  paths        text[] not null default '{}',
  hashes       text[] not null default '{}',
  reason       text not null check (char_length(btrim(reason)) between 3 and 500),
  status       text not null default 'requested' check (status in ('requested', 'approved', 'done', 'cancelled')),
  requested_by uuid not null references public.user_profiles (id),
  requested_at timestamptz not null default now(),
  approved_by  uuid references public.user_profiles (id),
  approved_at  timestamptz,
  completed_at timestamptz,
  method       text not null default 'storage_delete',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint dms_disposals_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id),
  constraint dms_disposals_two_people check (approved_by is null or approved_by <> requested_by)
);
create unique index dms_disposals_open_uq on public.dms_disposals (document_id) where status in ('requested', 'approved');
select private.attach_standard_triggers('public.dms_disposals');

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.dms_on_hold(p_document_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.dms_legal_holds h where h.document_id = p_document_id and h.released_at is null)
$$;

-- When the retention period of a document ends (null: no active rule, or its start has not happened yet).
create or replace function private.dms_retention_end(d public.dms_documents)
returns table (action text, starts date, ends date)
language sql
stable
security definer
set search_path = ''
as $$
  select r.action, x.starts, (x.starts + make_interval(years => r.retain_years))::date
  from public.dms_retention_rules r
  cross join lateral (select case r.start_event
      when 'published' then (select min(v.published_at)::date from public.dms_versions v where v.document_id = d.id and v.published_at is not null)
      when 'archived' then d.archived_at::date
      else d.expiry_date end as starts) x
  where r.doc_type_id = d.doc_type_id and r.active and x.starts is not null
$$;

create or replace function private.dms_doc_json(d public.dms_documents)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', d.id, 'doc_code', d.doc_code, 'title', d.title, 'version', d.current_version,
    'version_name', case when d.current_version > 0 then d.doc_code || '_v' || d.current_version end,
    'folder_id', d.folder_id, 'folder', (select f.name from public.dms_folders f where f.id = d.folder_id),
    'doc_type_id', d.doc_type_id, 'type_code', t.code, 'type_name', t.name, 'has_expiry', t.has_expiry,
    'department_id', d.department_id, 'department', (select dp.name from public.departments dp where dp.id = d.department_id),
    'owner_user_id', d.owner_user_id, 'owner', (select up.full_name from public.user_profiles up where up.id = d.owner_user_id),
    'classification', d.classification, 'scope', d.scope, 'scope_department_ids', to_jsonb(d.scope_department_ids),
    'restricted_role_ids', to_jsonb(d.restricted_role_ids), 'language', d.language, 'fields', d.fields,
    'expiry_date', d.expiry_date, 'expiry_status', private.dms_expiry_status(d.expiry_date),
    'days_left', case when d.expiry_date is not null then d.expiry_date - current_date end,
    'next_review_date', d.next_review_date, 'lifecycle', d.lifecycle, 'archived_at', d.archived_at,
    'legal_hold', private.dms_on_hold(d.id), 'created_at', d.created_at, 'updated_at', d.updated_at)
  from public.dms_doc_types t where t.id = d.doc_type_id
$$;

create or replace function public.archive_dms_document(p_id uuid, p_archive boolean default true)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.dms_documents := private.load_dms_document(p_id);
begin
  if not private.dms_can_edit(d) then
    raise exception 'You can only archive documents of your own department' using errcode = '42501';
  end if;
  if coalesce(p_archive, true) then
    if d.lifecycle <> 'published' then
      raise exception 'Only a published document can be archived' using errcode = '23514';
    end if;
    update public.dms_documents set lifecycle = 'archived', archived_at = now() where id = d.id;
  else
    if d.lifecycle <> 'archived' then
      raise exception 'Only an archived document can be restored' using errcode = '23514';
    end if;
    if exists (select 1 from public.dms_disposals x where x.document_id = d.id and x.status in ('requested', 'approved')) then
      raise exception 'A disposal of this document is in progress' using errcode = '23514';
    end if;
    if exists (select 1 from public.dms_documents x where x.org_id = d.org_id and x.id <> d.id and x.doc_type_id = d.doc_type_id
               and x.department_id = d.department_id and lower(x.title) = lower(d.title) and x.lifecycle in ('published', 'pending')) then
      raise exception 'A published document with the same title exists; archive it first' using errcode = '23505';
    end if;
    update public.dms_documents set lifecycle = 'published', archived_at = null where id = d.id;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- API (dms.records)
-- -----------------------------------------------------------------------------
create or replace function public.get_dms_records()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('dms.records');
  return jsonb_build_object(
    'rules', coalesce((
      select jsonb_agg(jsonb_build_object(
               'doc_type_id', t.id, 'type_code', t.code, 'type_name', t.name,
               'folder', (select f.name from public.dms_folders f where f.id = t.folder_id),
               'rule', case when r.id is not null and r.active then jsonb_build_object('start_event', r.start_event, 'retain_years', r.retain_years,
                                                                     'action', r.action, 'note', r.note) end,
               'documents', (select count(*) from public.dms_documents d where d.doc_type_id = t.id and d.lifecycle in ('published', 'archived')))
             order by t.sort, t.name)
      from public.dms_doc_types t
      left join public.dms_retention_rules r on r.doc_type_id = t.id
      where t.org_id = v_org and (t.active or exists (select 1 from public.dms_documents d where d.doc_type_id = t.id))), '[]'::jsonb),
    'due', coalesce((
      select jsonb_agg(private.dms_doc_json(d) || jsonb_build_object('retention_action', e.action, 'retention_ends', e.ends,
               'disposal', (select jsonb_build_object('id', x.id, 'status', x.status) from public.dms_disposals x
                            where x.document_id = d.id and x.status in ('requested', 'approved')))
             order by e.ends)
      from public.dms_documents d cross join lateral private.dms_retention_end(d) e
      where d.org_id = v_org and d.lifecycle in ('published', 'archived') and e.ends <= current_date), '[]'::jsonb),
    'holds', coalesce((
      select jsonb_agg(jsonb_build_object('id', h.id, 'document_id', h.document_id, 'doc_code', d.doc_code, 'title', d.title,
                                          'reason', h.reason, 'placed_by', private.dms_user_name(h.placed_by), 'placed_at', h.placed_at)
             order by h.placed_at desc)
      from public.dms_legal_holds h join public.dms_documents d on d.id = h.document_id
      where h.org_id = v_org and h.released_at is null), '[]'::jsonb),
    'disposals', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.id, 'document_id', x.document_id, 'doc_code', x.doc_code, 'title', x.title,
                                          'reason', x.reason, 'status', x.status, 'versions', cardinality(x.version_ids),
                                          'requested_by', private.dms_user_name(x.requested_by), 'requested_at', x.requested_at,
                                          'requested_by_me', x.requested_by = auth.uid(), 'paths', to_jsonb(x.paths),
                                          'approved_by', private.dms_user_name(x.approved_by), 'approved_at', x.approved_at,
                                          'completed_at', x.completed_at, 'hashes', to_jsonb(x.hashes))
             order by x.status = 'done', x.requested_at desc)
      from public.dms_disposals x where x.org_id = v_org and x.status <> 'cancelled'), '[]'::jsonb));
end;
$$;

-- p: {start_event, retain_years, action, note} or {active:false} to remove the rule.
create or replace function public.save_dms_retention_rule(p_doc_type_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('dms.records');
  if not exists (select 1 from public.dms_doc_types where id = p_doc_type_id and org_id = v_org) then
    raise exception 'Document type not found' using errcode = 'P0002';
  end if;
  if coalesce((p ->> 'active')::boolean, true) = false then
    update public.dms_retention_rules set active = false where doc_type_id = p_doc_type_id;
    return;
  end if;
  if coalesce(p ->> 'start_event', '') not in ('published', 'archived', 'expiry')
     or coalesce(p ->> 'action', '') not in ('review', 'dispose')
     or coalesce((p ->> 'retain_years')::int, 0) not between 1 and 100 then
    raise exception 'Choose when it starts, 1 to 100 years, and review or dispose' using errcode = '22023';
  end if;
  if p ->> 'start_event' = 'expiry' and not (select t.has_expiry from public.dms_doc_types t where t.id = p_doc_type_id) then
    raise exception 'This type has no expiry date; start from publishing or archiving' using errcode = '22023';
  end if;
  insert into public.dms_retention_rules (org_id, doc_type_id, start_event, retain_years, action, note)
  values (v_org, p_doc_type_id, p ->> 'start_event', (p ->> 'retain_years')::smallint, p ->> 'action', left(nullif(btrim(coalesce(p ->> 'note', '')), ''), 500))
  on conflict (org_id, doc_type_id) do update
    set start_event = excluded.start_event, retain_years = excluded.retain_years, action = excluded.action, note = excluded.note, active = true;
end;
$$;

create or replace function public.place_dms_hold(p_document_id uuid, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  d    public.dms_documents := private.load_dms_document(p_document_id);
  v_id uuid;
begin
  perform private.require_permission('dms.records');
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Write why the document is held (e.g. the case number)' using errcode = '22023';
  end if;
  if private.dms_on_hold(d.id) then
    raise exception 'This document is already on hold' using errcode = '23505';
  end if;
  insert into public.dms_legal_holds (org_id, document_id, reason, placed_by) values (d.org_id, d.id, btrim(p_reason), auth.uid())
  returning id into v_id;
  -- A hold stops any disposal in progress.
  update public.dms_disposals set status = 'cancelled' where document_id = d.id and status = 'requested';
  return v_id;
end;
$$;

create or replace function public.release_dms_hold(p_hold_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('dms.records');
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Write why the hold is released' using errcode = '22023';
  end if;
  update public.dms_legal_holds set released_by = auth.uid(), released_at = now(), release_reason = btrim(p_reason)
   where id = p_hold_id and org_id = private.current_org_id() and released_at is null;
  if not found then
    raise exception 'Hold not found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.request_dms_disposal(p_document_id uuid, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  d    public.dms_documents := private.load_dms_document(p_document_id);
  e    record;
  v_id uuid;
begin
  perform private.require_permission('dms.records');
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Write why it is disposed (e.g. retention ended under rule ...)' using errcode = '22023';
  end if;
  if d.lifecycle not in ('published', 'archived') then
    raise exception 'Only a published or archived document can be disposed' using errcode = '23514';
  end if;
  if private.dms_on_hold(d.id) then
    raise exception 'This document is on legal hold' using errcode = '23514';
  end if;
  select * into e from private.dms_retention_end(d) limit 1;
  if e.action is distinct from 'dispose' or e.ends > current_date then
    raise exception 'Its retention period has not ended (or its rule says review, not dispose)' using errcode = '23514';
  end if;
  begin
    insert into public.dms_disposals (org_id, document_id, doc_code, title, reason, requested_by)
    values (d.org_id, d.id, d.doc_code, d.title, btrim(p_reason), auth.uid())
    returning id into v_id;
  exception when unique_violation then
    raise exception 'A disposal of this document is already in progress' using errcode = '23505';
  end;
  perform private.write_audit(d.org_id, 'dms.disposal_requested', 'dms_documents', d.id, null, jsonb_build_object('reason', p_reason));
  return v_id;
end;
$$;

-- A second records holder approves; the document is hidden and its files may now be removed.
create or replace function public.approve_dms_disposal(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  x public.dms_disposals;
begin
  perform private.require_permission('dms.records');
  select * into x from public.dms_disposals where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Disposal not found' using errcode = 'P0002';
  end if;
  if x.status <> 'requested' then
    raise exception 'This disposal is not waiting for approval' using errcode = '23514';
  end if;
  if x.requested_by = auth.uid() then
    raise exception 'Someone else must approve a disposal you requested' using errcode = '23514';
  end if;
  if private.dms_on_hold(x.document_id) then
    raise exception 'This document is on legal hold' using errcode = '23514';
  end if;
  update public.dms_versions set status = 'disposing'
   where document_id = x.document_id and status in ('current', 'superseded', 'rejected', 'in_review');
  update public.dms_disposals
     set status = 'approved', approved_by = auth.uid(), approved_at = now(),
         version_ids = (select array_agg(v.id order by v.version) from public.dms_versions v where v.document_id = x.document_id and v.status = 'disposing'),
         paths = (select array_agg(v.file_path order by v.version) from public.dms_versions v where v.document_id = x.document_id and v.status = 'disposing'),
         hashes = (select array_agg(v.file_hash order by v.version) from public.dms_versions v where v.document_id = x.document_id and v.status = 'disposing')
   where id = x.id
  returning * into x;
  update public.dms_documents set lifecycle = 'archived', archived_at = coalesce(archived_at, now()) where id = x.document_id;
  update public.dms_requests set status = 'cancelled' where document_id = x.document_id and status in ('open', 'submitted');
  perform private.write_audit(x.org_id, 'dms.disposal_approved', 'dms_documents', x.document_id, null,
    jsonb_build_object('doc_code', x.doc_code, 'requested_by', x.requested_by));
  return jsonb_build_object('paths', to_jsonb(coalesce(x.paths, '{}')));
end;
$$;

-- After the browser removed the files: checks they are gone, closes the disposal, leaves a tombstone.
create or replace function public.complete_dms_disposal(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  x public.dms_disposals;
begin
  perform private.require_permission('dms.records');
  select * into x from public.dms_disposals where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Disposal not found' using errcode = 'P0002';
  end if;
  if x.status <> 'approved' then
    raise exception 'This disposal is not approved' using errcode = '23514';
  end if;
  if exists (select 1 from storage.objects o where o.bucket_id = 'dms-documents' and o.name = any (x.paths)) then
    raise exception 'Some files are still in storage; remove them first' using errcode = '23514';
  end if;
  update public.dms_versions set status = 'disposed', fields = '{}' where id = any (x.version_ids);
  update public.dms_documents set lifecycle = 'disposed', fields = '{}', title = 'Disposed document' where id = x.document_id;
  update public.dms_disposals set status = 'done', completed_at = now() where id = x.id;
  perform private.write_audit(x.org_id, 'dms.disposed', 'dms_documents', x.document_id, null,
    jsonb_build_object('doc_code', x.doc_code, 'hashes', x.hashes, 'approved_by', x.approved_by));
end;
$$;

create or replace function public.cancel_dms_disposal(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('dms.records');
  update public.dms_disposals set status = 'cancelled'
   where id = p_id and org_id = private.current_org_id() and status = 'requested';
  if not found then
    raise exception 'Only a disposal waiting for approval can be cancelled' using errcode = '23514';
  end if;
end;
$$;

-- Storage: files of an approved disposal may be deleted by a records holder (through the Storage API).
create or replace function private.dms_file_disposable(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('dms.records') and exists (
    select 1 from public.dms_versions v
    where v.file_path = p_name and v.org_id = private.current_org_id() and v.status = 'disposing')
$$;

drop policy if exists olympus_dms_files_delete on storage.objects;
create policy olympus_dms_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'dms-documents' and private.dms_file_disposable(name));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.dms_retention_rules enable row level security;
alter table public.dms_legal_holds     enable row level security;
alter table public.dms_disposals       enable row level security;
revoke all on table public.dms_retention_rules, public.dms_legal_holds, public.dms_disposals from anon, authenticated;

revoke all on function
  public.get_dms_records(), public.save_dms_retention_rule(uuid, jsonb), public.place_dms_hold(uuid, text),
  public.release_dms_hold(uuid, text), public.request_dms_disposal(uuid, text), public.approve_dms_disposal(uuid),
  public.complete_dms_disposal(uuid), public.cancel_dms_disposal(uuid)
from public, anon;
grant execute on function
  public.get_dms_records(), public.save_dms_retention_rule(uuid, jsonb), public.place_dms_hold(uuid, text),
  public.release_dms_hold(uuid, text), public.request_dms_disposal(uuid, text), public.approve_dms_disposal(uuid),
  public.complete_dms_disposal(uuid), public.cancel_dms_disposal(uuid)
to authenticated;
revoke all on function private.dms_on_hold(uuid), private.dms_retention_end(public.dms_documents) from public, anon, authenticated;
grant execute on function private.dms_file_disposable(text) to authenticated;
revoke all on function private.dms_file_disposable(text) from public, anon;
