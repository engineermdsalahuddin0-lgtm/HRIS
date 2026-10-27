-- =============================================================================
-- DMS D3: ISO compliance checklist (clauses, evidence, gaps).
-- Module handbook: src/DMS/features.md (ISO compliance), schema.md.
--
-- A standard's clauses are listed with OUR OWN short topic wording and the clause
-- number only (the ISO text is copyrighted). Evidence comes from document types
-- (e.g. Internal Audit Report -> 9.2 in every standard that has it) plus manual
-- tags on a document. One document counts for every standard that needs it; it is
-- never copied. Status per clause: ok (a current document), stale (only expired
-- or past-review documents), gap (nothing). Clause numbers follow the editions in
-- dms_iso_profiles and must be checked against the edition the client uses.
-- dms.audit: read-only auditor (checklist, every document, audit log in D6).
-- =============================================================================

do $guard$
begin
  if to_regproc('public.dms_decide') is null then
    raise exception 'Apply 20261104000200_dms_d2_governance.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('dms.audit', 'dms', 'Auditor: read every document, the ISO checklist and the document audit log (no changes)', false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Catalog: clauses and which types are evidence for them
-- -----------------------------------------------------------------------------
create table public.dms_iso_clauses (
  profile_code text not null references public.dms_iso_profiles (code),
  clause       text not null check (char_length(clause) between 1 and 12),
  topic        text not null,
  sort         smallint not null,
  primary key (profile_code, clause)
);

insert into public.dms_iso_clauses (profile_code, clause, topic, sort)
select p.code, c.clause, c.topic, c.sort
from public.dms_iso_profiles p
cross join (values
  ('4.3',  'Scope of the management system', 10),
  ('5.2',  'Policy', 20),
  ('6.2',  'Objectives and plans to reach them', 30),
  ('7.2',  'Competence and training records', 40),
  ('7.5',  'Control of documented information', 50),
  ('8.1',  'Operational planning and control', 60),
  ('9.2',  'Internal audit', 90),
  ('9.3',  'Management review', 91),
  ('10.2', 'Nonconformity and corrective action', 100)
) as c (clause, topic, sort)
where p.code in ('ISO_9001', 'ISO_27001', 'ISO_14001', 'ISO_45001');

insert into public.dms_iso_clauses (profile_code, clause, topic, sort) values
  ('ISO_9001',  '8.4',    'Control of external providers (suppliers)', 64),
  ('ISO_9001',  '8.5',    'Production and service provision', 65),
  ('ISO_27001', '6.1.2',  'Information security risk assessment', 25),
  ('ISO_27001', '6.1.3',  'Risk treatment and Statement of Applicability', 26),
  ('ISO_27001', 'A.5.9',  'Inventory of information and assets', 70),
  ('ISO_27001', 'A.5.24', 'Incident management planning', 71),
  ('ISO_27001', 'A.8.13', 'Information backup', 72),
  ('ISO_14001', '6.1.2',  'Environmental aspects', 25),
  ('ISO_14001', '6.1.3',  'Compliance obligations (laws, permits)', 26),
  ('ISO_14001', '8.2',    'Emergency preparedness and response', 62),
  ('ISO_14001', '9.1',    'Monitoring and measurement (e.g. waste records)', 80),
  ('ISO_45001', '5.4',    'Consultation and participation of workers', 22),
  ('ISO_45001', '6.1.2',  'Hazard identification and risk assessment', 25),
  ('ISO_45001', '6.1.3',  'Legal requirements (licences, permits)', 26),
  ('ISO_45001', '8.2',    'Emergency preparedness and response', 62),
  ('ISO_50001', '5.2',    'Energy policy', 20),
  ('ISO_50001', '6.3',    'Energy review', 30),
  ('ISO_50001', '6.4',    'Energy performance indicators', 31),
  ('ISO_22000', '8.2',    'Prerequisite programmes', 30),
  ('ISO_22000', '8.5',    'Hazard control (HACCP plan)', 31),
  ('ISO_22301', '8.2',    'Business impact analysis and risk assessment', 30),
  ('ISO_22301', '8.4',    'Business continuity plans', 31),
  ('ISO_37001', '5.2',    'Anti-bribery policy', 20),
  ('ISO_37001', '8.2',    'Due diligence', 30);

-- New policy types the standards need (added to companies that already chose the standard).
insert into public.dms_catalog_doc_types (code, folder_code, name, review_months, default_classification, sort) values
  ('ISP', 'ISM', 'Information Security Policy',       12, 'internal', 0),
  ('EPL', 'ENV', 'Environmental Policy',              12, 'internal', 0),
  ('OHP', 'OHS', 'Health & Safety Policy',            12, 'internal', 0),
  ('ENP', 'ENR', 'Energy Policy',                     12, 'internal', 0);
insert into public.dms_doc_types (org_id, folder_id, code, name, origin, review_months, default_classification, sort)
select f.org_id, f.id, t.code, t.name, 'catalog', t.review_months, t.default_classification, t.sort
from public.dms_catalog_doc_types t
join public.dms_folders f on f.catalog_code = t.folder_code
where t.code in ('ISP', 'EPL', 'OHP', 'ENP')
on conflict (org_id, code) do nothing;

create table public.dms_catalog_type_clauses (
  type_code    text not null references public.dms_catalog_doc_types (code),
  profile_code text not null,
  clause       text not null,
  primary key (type_code, profile_code, clause),
  foreign key (profile_code, clause) references public.dms_iso_clauses (profile_code, clause)
);

insert into public.dms_catalog_type_clauses (type_code, profile_code, clause) values
  -- ISO 9001
  ('QMN', 'ISO_9001', '4.3'), ('QMN', 'ISO_9001', '7.5'), ('QPL', 'ISO_9001', '5.2'), ('OBJ', 'ISO_9001', '6.2'),
  ('PRC', 'ISO_9001', '8.1'), ('PRC', 'ISO_9001', '7.5'), ('WIN', 'ISO_9001', '8.5'), ('FRM', 'ISO_9001', '7.5'),
  ('SUP', 'ISO_9001', '8.4'),
  -- ISO 27001
  ('SCP', 'ISO_27001', '4.3'), ('ISP', 'ISO_27001', '5.2'), ('RSK', 'ISO_27001', '6.1.2'), ('SOA', 'ISO_27001', '6.1.3'),
  ('AST', 'ISO_27001', 'A.5.9'), ('INC', 'ISO_27001', 'A.5.24'), ('BKP', 'ISO_27001', 'A.8.13'), ('PRC', 'ISO_27001', '7.5'),
  -- ISO 14001
  ('EPL', 'ISO_14001', '5.2'), ('ASP', 'ISO_14001', '6.1.2'), ('LEG', 'ISO_14001', '6.1.3'), ('ENV', 'ISO_14001', '6.1.3'),
  ('EDR', 'ISO_14001', '8.2'), ('WST', 'ISO_14001', '9.1'), ('PRC', 'ISO_14001', '7.5'),
  -- ISO 45001
  ('OHP', 'ISO_45001', '5.2'), ('SCM', 'ISO_45001', '5.4'), ('HAZ', 'ISO_45001', '6.1.2'), ('LEG', 'ISO_45001', '6.1.3'),
  ('FCT', 'ISO_45001', '6.1.3'), ('FIR', 'ISO_45001', '6.1.3'), ('BLR', 'ISO_45001', '6.1.3'), ('PPE', 'ISO_45001', '8.1'),
  ('DRL', 'ISO_45001', '8.2'), ('NMS', 'ISO_45001', '10.2'), ('PRC', 'ISO_45001', '7.5'),
  -- Shared by the four main standards
  ('TRN', 'ISO_9001', '7.2'), ('TRN', 'ISO_27001', '7.2'), ('TRN', 'ISO_14001', '7.2'), ('TRN', 'ISO_45001', '7.2'),
  ('IAR', 'ISO_9001', '9.2'), ('IAR', 'ISO_27001', '9.2'), ('IAR', 'ISO_14001', '9.2'), ('IAR', 'ISO_45001', '9.2'),
  ('MRV', 'ISO_9001', '9.3'), ('MRV', 'ISO_27001', '9.3'), ('MRV', 'ISO_14001', '9.3'), ('MRV', 'ISO_45001', '9.3'),
  ('CAR', 'ISO_9001', '10.2'), ('CAR', 'ISO_27001', '10.2'), ('CAR', 'ISO_14001', '10.2'), ('CAR', 'ISO_45001', '10.2'),
  ('OBJ', 'ISO_27001', '6.2'), ('OBJ', 'ISO_14001', '6.2'), ('OBJ', 'ISO_45001', '6.2'),
  -- Others
  ('ENP', 'ISO_50001', '5.2'), ('EGY', 'ISO_50001', '6.3'), ('EPI', 'ISO_50001', '6.4'),
  ('PRP', 'ISO_22000', '8.2'), ('HAC', 'ISO_22000', '8.5'),
  ('BIA', 'ISO_22301', '8.2'), ('BCP', 'ISO_22301', '8.4'),
  ('ABP', 'ISO_37001', '5.2'), ('DDR', 'ISO_37001', '8.2');

-- Manual tags: a document that is evidence beyond what its type says (e.g. a custom type).
create table public.dms_document_clauses (
  org_id       uuid not null references public.organizations (id),
  document_id  uuid not null,
  profile_code text not null,
  clause       text not null,
  created_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id) default auth.uid(),
  primary key (document_id, profile_code, clause),
  constraint dms_document_clauses_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id),
  constraint dms_document_clauses_clause_fk foreign key (profile_code, clause) references public.dms_iso_clauses (profile_code, clause)
);

-- -----------------------------------------------------------------------------
-- Helpers and API
-- -----------------------------------------------------------------------------
-- Every (document, standard, clause) of a company: from the document's type, plus manual tags.
create or replace function private.dms_evidence(p_org_id uuid)
returns table (document_id uuid, profile_code text, clause text, source text)
language sql
stable
security definer
set search_path = ''
as $$
  select d.id, tc.profile_code, tc.clause, 'type'
  from public.dms_documents d
  join public.dms_doc_types t on t.id = d.doc_type_id
  join public.dms_catalog_type_clauses tc on tc.type_code = t.code
  where d.org_id = p_org_id and d.lifecycle = 'published' and t.origin = 'catalog'
  union
  select m.document_id, m.profile_code, m.clause, 'manual'
  from public.dms_document_clauses m join public.dms_documents d on d.id = m.document_id
  where m.org_id = p_org_id and d.lifecycle = 'published'
$$;

create or replace function private.dms_can_audit()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('dms.manage') or private.has_permission('dms.audit')
$$;

-- Auditors read every document of the company (no changes).
create or replace function private.dms_can_read(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select d.org_id = private.current_org_id() and d.lifecycle <> 'cancelled' and (
    private.has_permission('dms.manage') or private.has_permission('dms.audit')
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

-- The checklist of one standard (or every selected standard when null).
create or replace function public.get_dms_compliance(p_profile text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org      uuid := private.current_org_id();
  v_profiles text[];
begin
  if not private.dms_can_audit() then
    raise exception 'You do not have permission for this action (dms.audit)' using errcode = '42501';
  end if;
  v_profiles := case when p_profile is null then (select s.profiles from public.dms_settings s where s.org_id = v_org) else array[p_profile] end;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'profile', p.code, 'name', p.name, 'edition', p.edition,
             'clauses', (
               select jsonb_agg(jsonb_build_object(
                        'clause', c.clause, 'topic', c.topic,
                        'status', case when ev.ok > 0 then 'ok' when ev.total > 0 then 'stale' else 'gap' end,
                        'documents', coalesce(ev.docs, '[]'::jsonb),
                        'types', (select jsonb_agg(t.name order by t.name) from public.dms_catalog_type_clauses tc
                                  join public.dms_catalog_doc_types t on t.code = tc.type_code
                                  where tc.profile_code = c.profile_code and tc.clause = c.clause))
                      order by c.sort, c.clause)
               from public.dms_iso_clauses c
               left join lateral (
                 select count(*) as total,
                        count(*) filter (where (d.expiry_date is null or d.expiry_date >= current_date)
                                           and (d.next_review_date is null or d.next_review_date >= current_date)) as ok,
                        jsonb_agg(jsonb_build_object('id', d.id, 'doc_code', d.doc_code, 'title', d.title,
                                                     'version_name', d.doc_code || '_v' || d.current_version, 'source', e.source,
                                                     'expiry_date', d.expiry_date, 'next_review_date', d.next_review_date,
                                                     'stale', (d.expiry_date < current_date or d.next_review_date < current_date))
                                  order by d.doc_code) as docs
                 from (select distinct on (x.document_id) x.document_id, x.source from private.dms_evidence(v_org) x
                       where x.profile_code = c.profile_code and x.clause = c.clause order by x.document_id, x.source desc) e
                 join public.dms_documents d on d.id = e.document_id
               ) ev on true
               where c.profile_code = p.code))
           order by p.sort)
    from public.dms_iso_profiles p where p.code = any (v_profiles)), '[]'::jsonb);
end;
$$;

-- The standards and clauses a document counts for; manual tags are editable by dms.manage.
create or replace function public.get_dms_document_clauses(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d public.dms_documents := private.load_dms_document(p_id);
begin
  return jsonb_build_object(
    'tags', coalesce((select jsonb_agg(jsonb_build_object('profile', x.profile_code, 'clause', x.clause, 'source', x.source,
                                                          'topic', c.topic) order by x.profile_code, c.sort)
                      from (select distinct on (e.profile_code, e.clause) e.* from private.dms_evidence(d.org_id) e
                            where e.document_id = d.id order by e.profile_code, e.clause, e.source desc) x
                      join public.dms_iso_clauses c on c.profile_code = x.profile_code and c.clause = x.clause), '[]'::jsonb),
    'can_tag', private.has_permission('dms.manage'),
    'clauses', case when private.has_permission('dms.manage') then coalesce((
                 select jsonb_agg(jsonb_build_object('profile', c.profile_code, 'clause', c.clause, 'topic', c.topic) order by c.profile_code, c.sort)
                 from public.dms_iso_clauses c
                 where c.profile_code in (select unnest(s.profiles) from public.dms_settings s where s.org_id = d.org_id)), '[]'::jsonb) end);
end;
$$;

-- p_tags: [{profile, clause}] — the manual tags of the document (replaces the previous manual tags).
create or replace function public.set_dms_document_clauses(p_id uuid, p_tags jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d public.dms_documents := private.load_dms_document(p_id);
begin
  perform private.require_permission('dms.manage');
  if jsonb_typeof(coalesce(p_tags, '[]')) <> 'array' then
    raise exception 'Tags must be a list' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p_tags, '[]')) t
             where not exists (select 1 from public.dms_iso_clauses c where c.profile_code = t ->> 'profile' and c.clause = t ->> 'clause')) then
    raise exception 'Unknown clause' using errcode = '22023';
  end if;
  -- Manual tags are replaced as a set (the audit row below keeps what was set).
  delete from public.dms_document_clauses where document_id = d.id;
  insert into public.dms_document_clauses (org_id, document_id, profile_code, clause)
  select distinct d.org_id, d.id, t ->> 'profile', t ->> 'clause' from jsonb_array_elements(coalesce(p_tags, '[]')) t;
  perform private.write_audit(d.org_id, 'dms.clauses_tagged', 'dms_documents', d.id, null, jsonb_build_object('tags', p_tags));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.dms_iso_clauses          enable row level security;
alter table public.dms_catalog_type_clauses enable row level security;
alter table public.dms_document_clauses     enable row level security;
revoke all on table public.dms_iso_clauses, public.dms_catalog_type_clauses, public.dms_document_clauses from anon, authenticated;

revoke all on function public.get_dms_compliance(text), public.get_dms_document_clauses(uuid), public.set_dms_document_clauses(uuid, jsonb)
from public, anon;
grant execute on function public.get_dms_compliance(text), public.get_dms_document_clauses(uuid), public.set_dms_document_clauses(uuid, jsonb)
to authenticated;
revoke all on function private.dms_evidence(uuid), private.dms_can_audit() from public, anon, authenticated;
