-- =============================================================================
-- DMS D5: the DMS becomes the only source of the AI assistant's documents.
-- Decisions: docs/Part04Architecture.md section 12 (DMS only), src/DMS/architecture.md 3.3.
--
--   * A document reaches the assistant only when ALL hold: published; Public or
--     Internal; readable by the whole company (department-scoped documents never
--     go, the assistant cannot filter by department); its type has AI switched on
--     with a topic; the current file is PDF, DOCX or JSON up to 20 MB.
--     Confidential and Restricted text never leaves for an external API.
--   * Kept in step by triggers: publishing a new version, archiving, disposing,
--     reclassifying or switching AI off removes the old resource and its chunks in
--     the same transaction; the new one waits as 'processing' for the Edge Function
--     `assistant` (ingest), which now reads it from the dms-documents bucket.
--   * The assistant's own upload is retired in the UI (Setup → AI assistant →
--     Resources points to Documents); citations of DMS documents open the document
--     page (path "dms:<id>").
-- =============================================================================

do $guard$
begin
  if to_regproc('public.get_dms_records') is null then
    raise exception 'Apply 20261104000400_dms_d4_records.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- AI switch and topic per type
-- -----------------------------------------------------------------------------
alter table public.dms_catalog_doc_types add column ai_default boolean not null default false;
alter table public.dms_catalog_doc_types add column assistant_topic text references public.assistant_topics (key);
update public.dms_catalog_doc_types set ai_default = true, assistant_topic = case
    when code in ('POL', 'COC', 'HBK') then 'kb.hr_rules'
    else 'kb.company_policy' end
 where code in ('POL', 'COC', 'HBK', 'QMN', 'QPL', 'OBJ', 'PRC', 'WIN', 'ISP', 'EPL', 'OHP', 'ENP', 'ABP', 'BCP');

alter table public.dms_doc_types add column ai_enabled boolean not null default false;
alter table public.dms_doc_types add column assistant_topic text references public.assistant_topics (key);
alter table public.dms_doc_types add constraint dms_doc_types_ai_topic check (not ai_enabled or assistant_topic is not null);
update public.dms_doc_types t set ai_enabled = c.ai_default, assistant_topic = c.assistant_topic
  from public.dms_catalog_doc_types c where c.code = t.code and t.origin = 'catalog';

create or replace function private.dms_add_catalog_folders(p_org_id uuid, p_profile text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.dms_folders (org_id, origin, catalog_code, name, sort)
  select p_org_id, case when f.profile_code is null then 'base' else 'iso' end, f.code, f.name, f.sort
  from public.dms_catalog_folders f
  where f.profile_code is not distinct from p_profile
  on conflict (org_id, catalog_code) do update set enabled = true;
  insert into public.dms_doc_types (org_id, folder_id, code, name, origin, field_schema, has_expiry, expiry_default,
                                    review_months, default_classification, sort, ai_enabled, assistant_topic)
  select p_org_id, fo.id, t.code, t.name, 'catalog', t.field_schema, t.has_expiry, t.expiry_default, t.review_months,
         t.default_classification, t.sort, t.ai_default, t.assistant_topic
  from public.dms_catalog_doc_types t
  join public.dms_catalog_folders f on f.code = t.folder_code
  join public.dms_folders fo on fo.org_id = p_org_id and fo.catalog_code = f.code
  where f.profile_code is not distinct from p_profile
  on conflict (org_id, code) do update set active = true;
end;
$$;

create or replace function private.dms_types_json(p_org_id uuid, p_all boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'folder_id', t.folder_id, 'code', t.code, 'name', t.name, 'origin', t.origin,
           'field_schema', t.field_schema, 'has_expiry', t.has_expiry, 'expiry_default', t.expiry_default,
           'review_months', t.review_months, 'default_classification', t.default_classification, 'active', t.active,
           'ai_enabled', t.ai_enabled, 'assistant_topic', t.assistant_topic,
           -- Setup only: the count includes documents the caller may not read.
           'documents', case when p_all then (select count(*) from public.dms_documents d
                                              where d.doc_type_id = t.id and d.lifecycle <> 'cancelled') end)
         order by t.sort, t.name), '[]'::jsonb)
  from public.dms_doc_types t
  join public.dms_folders f on f.id = t.folder_id
  where t.org_id = p_org_id and (p_all or (t.active and f.enabled))
$$;

-- p: {ai_enabled, assistant_topic} (dms.manage); everything else as before.
create or replace function public.save_dms_doc_type_ai(p_id uuid, p_enabled boolean, p_topic text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('dms.manage');
  if coalesce(p_enabled, false) and not exists (select 1 from public.assistant_topics where key = p_topic and topic_group = 'knowledge'
                                                and key not in ('kb.app_guide')) then
    raise exception 'Choose the assistant topic for this type' using errcode = '22023';
  end if;
  update public.dms_doc_types set ai_enabled = coalesce(p_enabled, false), assistant_topic = coalesce(nullif(p_topic, ''), assistant_topic)
   where id = p_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Document type not found' using errcode = 'P0002';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- The sync
-- -----------------------------------------------------------------------------
create or replace function private.dms_sync_assistant(p_document_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d      public.dms_documents;
  t      public.dms_doc_types;
  v      public.dms_versions;
  v_want boolean;
  v_keep uuid;
begin
  select * into d from public.dms_documents where id = p_document_id;
  if not found or to_regclass('public.assistant_resources') is null then
    return;
  end if;
  select * into t from public.dms_doc_types where id = d.doc_type_id;
  select * into v from public.dms_versions where document_id = d.id and status = 'current' limit 1;
  v_want := d.lifecycle = 'published' and d.classification in ('public', 'internal') and d.scope = 'company'
            and t.ai_enabled and t.assistant_topic is not null and v.id is not null
            and v.file_kind in ('pdf', 'docx', 'json') and v.size_bytes <= 20971520
            and coalesce((select s.enabled from public.dms_settings s where s.org_id = d.org_id), false);
  if v_want then
    select r.id into v_keep from public.assistant_resources r
    where r.source = 'dms' and r.dms_version_id = v.id and r.status <> 'archived' limit 1;
    if v_keep is not null then
      update public.assistant_resources set topic_key = t.assistant_topic, name = left(d.doc_code || ' · ' || d.title, 200)
       where id = v_keep and (topic_key <> t.assistant_topic or name <> left(d.doc_code || ' · ' || d.title, 200));
    end if;
  end if;
  -- Everything else of this document leaves the store.
  delete from public.assistant_chunks c using public.assistant_resources r
   where c.resource_id = r.id and r.source = 'dms' and r.dms_document_id = d.id and r.id is distinct from v_keep;
  update public.assistant_resources set status = 'archived'
   where source = 'dms' and dms_document_id = d.id and status <> 'archived' and id is distinct from v_keep;
  if v_want and v_keep is null then
    -- An old direct upload of the very same file gives way (one file, one resource).
    delete from public.assistant_chunks c using public.assistant_resources r
     where c.resource_id = r.id and r.org_id = d.org_id and r.file_hash = v.file_hash and r.status <> 'archived';
    update public.assistant_resources set status = 'archived'
     where org_id = d.org_id and file_hash = v.file_hash and status <> 'archived';
    insert into public.assistant_resources (org_id, source, dms_document_id, dms_version_id, name, kind, size_bytes, file_hash,
                                            file_path, topic_key, audience_role_ids, version, status, processed_through, uploaded_by)
    values (d.org_id, 'dms', d.id, v.id, left(d.doc_code || ' · ' || d.title, 200), v.file_kind, v.size_bytes, v.file_hash,
            v.file_path, t.assistant_topic, '{}', v.version, 'processing', 0, v.uploaded_by);
  end if;
end;
$$;

create or replace function private.dms_sync_document_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.dms_sync_assistant(new.id);
  return null;
end;
$$;
create trigger dms_sync_assistant after update of lifecycle, classification, scope, current_version, doc_type_id, title
  on public.dms_documents for each row execute function private.dms_sync_document_trigger();

create or replace function private.dms_sync_type_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in select d.id from public.dms_documents d where d.doc_type_id = new.id and d.lifecycle = 'published' loop
    perform private.dms_sync_assistant(v_id);
  end loop;
  return null;
end;
$$;
create trigger dms_sync_assistant after update of ai_enabled, assistant_topic
  on public.dms_doc_types for each row execute function private.dms_sync_type_trigger();

-- Existing published documents join the store now.
do $$
declare
  v_id uuid;
begin
  for v_id in select id from public.dms_documents where lifecycle = 'published' loop
    perform private.dms_sync_assistant(v_id);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Assistant side: where the Edge Function reads the file, citations, the upload retired
-- -----------------------------------------------------------------------------
create or replace function private.assistant_resource_path(r public.assistant_resources)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when r.source = 'dms' then r.file_path else r.org_id || '/' || r.id || '/v' || r.version || '.' || r.kind end
$$;

create or replace function private.assistant_resource_json(r public.assistant_resources)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'source', r.source, 'name', r.name, 'kind', r.kind, 'size_bytes', r.size_bytes, 'topic_key', r.topic_key,
    'audience_role_ids', to_jsonb(r.audience_role_ids), 'version', r.version, 'replaces_id', r.replaces_id, 'status', r.status,
    'error', r.error, 'units', r.units, 'chunks', r.chunks, 'processed_through', r.processed_through,
    'embedding_model', r.embedding_model, 'uploaded_at', r.uploaded_at, 'updated_at', r.updated_at, 'path', private.assistant_resource_path(r),
    'bucket', case when r.source = 'dms' then 'dms-documents' else 'assistant-resources' end,
    'dms_document_id', r.dms_document_id,
    'uploaded_by', (select up.full_name from public.user_profiles up where up.id = r.uploaded_by))
$$;

-- Citations: a DMS document opens its page ("dms:<id>") when the reader may read it.
create or replace function public.assistant_resource_path(p_resource_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when r.source = 'dms' then 'dms:' || r.dms_document_id else private.assistant_resource_path(r) end
  from public.assistant_resources r
  where r.id = p_resource_id and r.org_id = private.current_org_id()
    and (private.has_permission('assistant.manage')
         or private.assistant_can_read_resource(r, private.current_role_id(), private.assistant_allowed_topics(private.current_role_id())))
    and (r.source <> 'dms' or private.dms_can_read((select d from public.dms_documents d where d.id = r.dms_document_id)))
$$;

-- DMS resources follow their document: topic, archive and restore are managed in the DMS
-- (the sync runs inside the DMS triggers, so its own changes pass at trigger depth > 1).
create or replace function private.assistant_dms_resource_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.source = 'dms'
     and (new.topic_key is distinct from old.topic_key or new.audience_role_ids is distinct from old.audience_role_ids
          or (new.status = 'archived') <> (old.status = 'archived'))
     and pg_trigger_depth() = 1 then
    raise exception 'This document comes from the DMS: change it there (type AI switch, classification, archive)' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger assistant_dms_resource_guard before update on public.assistant_resources
  for each row execute function private.assistant_dms_resource_guard();

-- Overview: step 4 and the indexed count come from the assistant store.
create or replace function private.dms_ai_counts(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'indexed', count(*) filter (where r.status = 'ready'),
    'processing', count(*) filter (where r.status = 'processing'),
    'failed', count(*) filter (where r.status = 'failed'))
  from public.assistant_resources r where r.org_id = p_org_id and r.source = 'dms' and r.status <> 'archived'
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
  v_ai   jsonb;
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  if v_to < v_from or v_to > v_from + 3660 then
    raise exception 'Choose a date range of at most 10 years' using errcode = '22023';
  end if;
  perform private.seed_dms_defaults(v_org);
  v_tasks := public.list_dms_tasks() -> 'counts';
  v_ai := private.dms_ai_counts(v_org);
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
        'ai', jsonb_build_object('done', (v_ai ->> 'indexed')::int > 0, 'indexed', (v_ai ->> 'indexed')::int,
                                 'processing', (v_ai ->> 'processing')::int, 'failed', (v_ai ->> 'failed')::int)),
      'counts', jsonb_build_object(
        'documents', (select count(*) from readable),
        'expiring_60', (select count(*) from readable where expiry_date between current_date and current_date + 60),
        'expired', (select count(*) from readable where expiry_date < current_date),
        'awaiting_approval', (v_tasks ->> 'to_review')::int,
        'review_overdue', (v_tasks ->> 'review_overdue')::int,
        'upload_overdue', (v_tasks ->> 'upload_overdue')::int,
        'requested_from_me', (v_tasks ->> 'requested_from_me')::int,
        'indexed', (v_ai ->> 'indexed')::int),
      'expiring', coalesce((
        select jsonb_agg(private.dms_doc_json(r.doc) order by r.expiry_date)
        from readable r
        where r.expiry_date is not null and r.expiry_date <= v_to and (r.expiry_date >= v_from or r.expiry_date < current_date)), '[]'::jsonb))
  );
end;
$$;

-- The document page shows whether (and why not) the assistant can answer from it.
create or replace function public.get_dms_document_ai(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d public.dms_documents := private.load_dms_document(p_id);
  t public.dms_doc_types;
  v public.dms_versions;
  r public.assistant_resources;
begin
  select * into t from public.dms_doc_types where id = d.doc_type_id;
  select * into v from public.dms_versions where document_id = d.id and status = 'current' limit 1;
  select * into r from public.assistant_resources where source = 'dms' and dms_document_id = d.id and status <> 'archived' limit 1;
  return jsonb_build_object(
    'status', coalesce(r.status, 'not_indexed'), 'error', r.error, 'resource_id', r.id,
    'reason', case
      when r.id is not null then null
      when d.lifecycle <> 'published' then 'Only published documents are used.'
      when d.classification not in ('public', 'internal') then 'Confidential and restricted documents never go to the AI.'
      when d.scope <> 'company' then 'Documents for some departments only are not used (the assistant cannot filter by department).'
      when not t.ai_enabled then 'AI is switched off for this document type (Setup → Document types).'
      when v.file_kind not in ('pdf', 'docx', 'json') then 'Only PDF, DOCX and JSON files are read by the assistant.'
      when v.size_bytes > 20971520 then 'Files over 20 MB are not indexed.'
      else 'Not indexed.' end);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
revoke all on function public.save_dms_doc_type_ai(uuid, boolean, text), public.get_dms_document_ai(uuid) from public, anon;
grant execute on function public.save_dms_doc_type_ai(uuid, boolean, text), public.get_dms_document_ai(uuid) to authenticated;
revoke all on function
  private.dms_sync_assistant(uuid), private.dms_sync_document_trigger(), private.dms_sync_type_trigger(),
  private.assistant_dms_resource_guard(), private.dms_ai_counts(uuid)
from public, anon, authenticated;
