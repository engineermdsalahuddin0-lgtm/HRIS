-- =============================================================================
-- DMS D1: foundation (catalog, folders, document types, naming, upload,
-- versions, read access, expiry overview).
-- Module handbook: src/DMS/architecture.md, features.md, schema.md, security.md.
--
-- The user opens a folder and uploads; the system does the rest:
--   * code {DEPT}-{TYPE}-{SEQ} assigned once from the department and document
--     type (never from the folder), version name {code}_v{n}, storage path
--     dms-documents/{org}/{document}/v{n}.{ext}; nobody types a file name;
--   * the same file twice is refused (SHA-256), a second document with the same
--     type, department and title is refused ("upload it as a new version");
--   * folders are views: base folders for every company (each can be switched
--     off), ISO folders when a standard is selected (optional), custom folders
--     made by users; moving a document never renames it or moves its file;
--   * licences keep their expiry date; some types default to 30 June (the end of
--     the Bangladesh fiscal year), the user can change it.
-- Approval, reminders (D2), ISO clauses (D3), retention (D4) and the AI link
-- (D5) come later; in D1 a confirmed upload is published at once.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.get_assistant_usage') is null then
    raise exception 'Apply 20261103000500_assistant_ai6_usage.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Permissions and defaults
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('dms.manage',            'dms', 'Set up the document library: ISO standards, folders, document types; manage every document', false),
  ('dms.upload',            'dms', 'Upload documents and new versions for your own department; create folders',                  false),
  ('dms.upload_all',        'dms', 'Upload and edit documents for every department',                                              false),
  ('dms.view_confidential', 'dms', 'Read Confidential documents of your department (every department with dms.upload_all)',       false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Catalog (same for every company, written only by migrations)
-- -----------------------------------------------------------------------------
create table public.dms_iso_profiles (
  code         text primary key check (code ~ '^ISO_[0-9]{4,5}$'),
  name         text not null,
  edition      text not null,
  summary      text not null,
  who_needs_it text not null,
  sort         smallint not null
);
insert into public.dms_iso_profiles (code, name, edition, summary, who_needs_it, sort) values
  ('ISO_9001',  'ISO 9001 Quality',                 '2015', 'We do the work the same correct way every time and fix what goes wrong.', 'Almost every company; most buyers ask for it first.', 1),
  ('ISO_27001', 'ISO 27001 Information security',   '2022', 'Our data and systems are protected and we can prove it.',                'IT and software firms, banks, anyone holding customer or employee data.', 2),
  ('ISO_14001', 'ISO 14001 Environment',            '2015', 'We know how we affect the environment and we control it.',              'Factories, garments and textiles, chemicals.', 3),
  ('ISO_45001', 'ISO 45001 Health and safety',      '2018', 'Workers are safe and they have a voice.',                                'Factories, construction, any site with physical risk; expected by buyers.', 4),
  ('ISO_50001', 'ISO 50001 Energy',                 '2018', 'We measure and cut the energy we use.',                                  'Large factories cutting energy cost; buyers with carbon targets.', 5),
  ('ISO_22000', 'ISO 22000 Food safety',            '2018', 'The food we make or handle is safe.',                                    'Food and beverage companies only.', 6),
  ('ISO_22301', 'ISO 22301 Business continuity',    '2019', 'We keep running after a disaster.',                                      'Banks, IT and service companies.', 7),
  ('ISO_37001', 'ISO 37001 Anti-bribery',           '2016', 'We prevent and detect bribery.',                                         'Companies selling to government or large multinationals.', 8);

-- profile_code null = base folder (every company).
create table public.dms_catalog_folders (
  code         text primary key check (code ~ '^[A-Z]{2,6}$'),
  name         text not null,
  profile_code text references public.dms_iso_profiles (code),
  sort         smallint not null
);
insert into public.dms_catalog_folders (code, name, profile_code, sort) values
  ('LIC', 'License & Compliance',             null,        10),
  ('BUY', 'Buyer Compliance',                 null,        20),
  ('HRP', 'HR Policy',                        null,        30),
  ('CON', 'Contracts',                        null,        40),
  ('REC', 'Records & Audits',                 null,        50),
  ('GEN', 'General',                          null,        90),
  ('QMS', 'Quality Manual & Policy',          'ISO_9001',  60),
  ('PRC', 'Procedures & Work Instructions',   'ISO_9001',  61),
  ('ISM', 'Information Security',             'ISO_27001', 62),
  ('ENV', 'Environment',                      'ISO_14001', 63),
  ('OHS', 'Health & Safety',                  'ISO_45001', 64),
  ('ENR', 'Energy',                           'ISO_50001', 65),
  ('FSM', 'Food Safety',                      'ISO_22000', 66),
  ('BCM', 'Business Continuity',              'ISO_22301', 67),
  ('ABM', 'Anti-bribery',                     'ISO_37001', 68);

-- Type codes are unique across the catalog, so a document code always tells the type.
create table public.dms_catalog_doc_types (
  code                   text primary key check (code ~ '^[A-Z]{2,4}$'),
  folder_code            text not null references public.dms_catalog_folders (code),
  name                   text not null,
  field_schema           jsonb not null default '[]',
  has_expiry             boolean not null default false,
  expiry_default         text not null default 'none' check (expiry_default in ('none', 'fiscal_year_end')),
  review_months          smallint check (review_months is null or review_months between 1 and 120),
  default_classification text not null default 'internal'
                         check (default_classification in ('public', 'internal', 'confidential', 'restricted')),
  sort                   smallint not null
);

insert into public.dms_catalog_doc_types (code, folder_code, name, field_schema, has_expiry, expiry_default, review_months, default_classification, sort)
select v.code, v.folder_code, v.name,
       case v.fields
         when 'licence' then '[{"key":"licence_no","label":"Licence / certificate number","type":"text","required":true},
                               {"key":"authority","label":"Issuing authority","type":"text","required":true},
                               {"key":"issue_date","label":"Issue date","type":"date"}]'::jsonb
         when 'contract' then '[{"key":"party","label":"Other party","type":"text","required":true},
                                {"key":"start_date","label":"Start date","type":"date"}]'::jsonb
         when 'audit' then '[{"key":"auditor","label":"Auditor / body","type":"text"},
                             {"key":"audit_date","label":"Audit date","type":"date"}]'::jsonb
         else '[]'::jsonb
       end,
       v.has_expiry, v.expiry_default, v.review_months, v.cls, v.sort
from (values
  -- License & Compliance (BD statutory). Trade licence and IRC / ERC run to 30 June.
  ('TRD', 'LIC', 'Trade Licence',                          'licence',  true,  'fiscal_year_end', null::smallint, 'internal', 1),
  ('FCT', 'LIC', 'Factory Licence',                        'licence',  true,  'none',            null, 'internal', 2),
  ('FIR', 'LIC', 'Fire Licence',                           'licence',  true,  'none',            null, 'internal', 3),
  ('BLR', 'LIC', 'Boiler Certificate',                     'licence',  true,  'none',            null, 'internal', 4),
  ('ENV', 'LIC', 'Environmental Clearance Certificate',    'licence',  true,  'none',            null, 'internal', 5),
  ('REG', 'LIC', 'Import / Export Registration (IRC/ERC)', 'licence',  true,  'fiscal_year_end', null, 'internal', 6),
  ('TAX', 'LIC', 'TIN / VAT / BIN Certificate',            'licence',  false, 'none',            null, 'internal', 7),
  -- Buyer Compliance
  ('SAR', 'BUY', 'Social Audit Report',                    'audit',    false, 'none',            null, 'internal', 1),
  ('CAP', 'BUY', 'Corrective Action Plan',                 'none',     false, 'none',            null, 'internal', 2),
  ('BCT', 'BUY', 'Buyer Certificate',                      'licence',  true,  'none',            null, 'internal', 3),
  ('BCA', 'BUY', 'Code of Conduct Acknowledgement',        'none',     false, 'none',            null, 'internal', 4),
  -- HR Policy
  ('POL', 'HRP', 'HR Policy',                              'none',     false, 'none',            12,   'internal', 1),
  ('COC', 'HRP', 'Code of Conduct',                        'none',     false, 'none',            24,   'internal', 2),
  ('HBK', 'HRP', 'Employee Handbook',                      'none',     false, 'none',            24,   'internal', 3),
  -- Contracts
  ('SUP', 'CON', 'Supplier Contract',                      'contract', true,  'none',            null, 'confidential', 1),
  ('CUS', 'CON', 'Customer Contract',                      'contract', true,  'none',            null, 'confidential', 2),
  ('LSE', 'CON', 'Lease Agreement',                        'contract', true,  'none',            null, 'confidential', 3),
  ('NDA', 'CON', 'Non-disclosure Agreement',               'contract', false, 'none',            null, 'confidential', 4),
  -- Records & Audits
  ('IAR', 'REC', 'Internal Audit Report',                  'audit',    false, 'none',            null, 'internal', 1),
  ('MRV', 'REC', 'Management Review',                      'none',     false, 'none',            null, 'internal', 2),
  ('CAR', 'REC', 'Corrective Action Record',               'none',     false, 'none',            null, 'internal', 3),
  ('TRN', 'REC', 'Training Record',                        'none',     false, 'none',            null, 'internal', 4),
  -- General
  ('DOC', 'GEN', 'General Document',                       'none',     false, 'none',            null, 'internal', 1),
  -- ISO 9001
  ('QMN', 'QMS', 'Quality Manual',                         'none',     false, 'none',            12,   'internal', 1),
  ('QPL', 'QMS', 'Quality Policy',                         'none',     false, 'none',            12,   'internal', 2),
  ('OBJ', 'QMS', 'Quality Objectives',                     'none',     false, 'none',            12,   'internal', 3),
  ('PRC', 'PRC', 'Procedure',                              'none',     false, 'none',            12,   'internal', 1),
  ('WIN', 'PRC', 'Work Instruction',                       'none',     false, 'none',            12,   'internal', 2),
  ('FRM', 'PRC', 'Form / Template',                        'none',     false, 'none',            24,   'internal', 3),
  -- ISO 27001
  ('SCP', 'ISM', 'ISMS Scope',                             'none',     false, 'none',            12,   'internal', 1),
  ('RSK', 'ISM', 'Risk Assessment',                        'none',     false, 'none',            12,   'confidential', 2),
  ('SOA', 'ISM', 'Statement of Applicability',             'none',     false, 'none',            12,   'confidential', 3),
  ('AST', 'ISM', 'Asset Inventory',                        'none',     false, 'none',            12,   'confidential', 4),
  ('INC', 'ISM', 'Security Incident Report',               'none',     false, 'none',            null, 'confidential', 5),
  ('BKP', 'ISM', 'Backup / Restore Test',                  'none',     false, 'none',            null, 'internal', 6),
  -- ISO 14001
  ('ASP', 'ENV', 'Aspect & Impact Register',               'none',     false, 'none',            12,   'internal', 1),
  ('LEG', 'ENV', 'Legal Register',                         'none',     false, 'none',            12,   'internal', 2),
  ('WST', 'ENV', 'Waste Record',                           'none',     false, 'none',            null, 'internal', 3),
  ('EDR', 'ENV', 'Environmental Emergency Drill',          'none',     false, 'none',            null, 'internal', 4),
  -- ISO 45001
  ('HAZ', 'OHS', 'Hazard & Risk Register',                 'none',     false, 'none',            12,   'internal', 1),
  ('NMS', 'OHS', 'Incident & Near-miss Report',            'none',     false, 'none',            null, 'internal', 2),
  ('SCM', 'OHS', 'Safety Committee Minutes',               'none',     false, 'none',            null, 'internal', 3),
  ('PPE', 'OHS', 'PPE Register',                           'none',     false, 'none',            12,   'internal', 4),
  ('DRL', 'OHS', 'Fire & Evacuation Drill',                'none',     false, 'none',            null, 'internal', 5),
  -- ISO 50001, 22000, 22301, 37001
  ('EGY', 'ENR', 'Energy Review',                          'none',     false, 'none',            12,   'internal', 1),
  ('EPI', 'ENR', 'Energy Performance Indicators',          'none',     false, 'none',            12,   'internal', 2),
  ('HAC', 'FSM', 'HACCP Plan',                             'none',     false, 'none',            12,   'internal', 1),
  ('PRP', 'FSM', 'Prerequisite Programme',                 'none',     false, 'none',            12,   'internal', 2),
  ('BIA', 'BCM', 'Business Impact Analysis',               'none',     false, 'none',            12,   'confidential', 1),
  ('BCP', 'BCM', 'Business Continuity Plan',               'none',     false, 'none',            12,   'internal', 2),
  ('ABP', 'ABM', 'Anti-bribery Policy',                    'none',     false, 'none',            12,   'internal', 1),
  ('DDR', 'ABM', 'Due Diligence Record',                   'none',     false, 'none',            null, 'confidential', 2)
) as v (code, folder_code, name, fields, has_expiry, expiry_default, review_months, cls, sort);

-- -----------------------------------------------------------------------------
-- Company tables
-- -----------------------------------------------------------------------------
create table public.dms_settings (
  org_id     uuid primary key references public.organizations (id),
  enabled    boolean not null default true,
  profiles   text[] not null default '{}',
  no_iso     boolean not null default false,     -- "we use no ISO standard" (setup step 1 done)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id)
);
create trigger set_row_meta before insert or update on public.dms_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.dms_settings
  for each row execute function private.audit_row_change();

create table public.dms_folders (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  parent_id    uuid,
  origin       text not null check (origin in ('base', 'iso', 'custom')),
  catalog_code text references public.dms_catalog_folders (code),
  name         text not null check (char_length(btrim(name)) between 2 and 80),
  enabled      boolean not null default true,
  sort         smallint not null default 100,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint dms_folders_org_id_id_uq unique (org_id, id),
  constraint dms_folders_parent_fk foreign key (org_id, parent_id) references public.dms_folders (org_id, id),
  constraint dms_folders_catalog_uq unique (org_id, catalog_code),
  constraint dms_folders_origin_catalog check ((origin = 'custom') = (catalog_code is null)),
  constraint dms_folders_not_own_parent check (parent_id is distinct from id)
);
create unique index dms_folders_sibling_name_uq
  on public.dms_folders (org_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(btrim(name)));
select private.attach_standard_triggers('public.dms_folders');

create table public.dms_doc_types (
  id                     uuid primary key default gen_random_uuid(),
  org_id                 uuid not null references public.organizations (id),
  folder_id              uuid not null,       -- home folder: where uploads of this type are offered first
  code                   text not null check (code ~ '^[A-Z]{2,4}$'),
  name                   text not null check (char_length(btrim(name)) between 2 and 80),
  origin                 text not null check (origin in ('catalog', 'custom')),
  field_schema           jsonb not null default '[]' check (jsonb_typeof(field_schema) = 'array'),
  has_expiry             boolean not null default false,
  expiry_default         text not null default 'none' check (expiry_default in ('none', 'fiscal_year_end')),
  review_months          smallint check (review_months is null or review_months between 1 and 120),
  default_classification text not null default 'internal'
                         check (default_classification in ('public', 'internal', 'confidential', 'restricted')),
  active                 boolean not null default true,
  sort                   smallint not null default 100,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  created_by             uuid references public.user_profiles (id),
  updated_by             uuid references public.user_profiles (id),
  constraint dms_doc_types_org_id_id_uq unique (org_id, id),
  constraint dms_doc_types_code_uq unique (org_id, code),
  constraint dms_doc_types_folder_fk foreign key (org_id, folder_id) references public.dms_folders (org_id, id)
);
select private.attach_standard_triggers('public.dms_doc_types');

-- One counter per company, department code and type code. A number is never handed out twice.
create table public.dms_code_sequences (
  org_id    uuid not null references public.organizations (id),
  dept_code text not null,
  type_code text not null,
  last_seq  integer not null default 0 check (last_seq between 0 and 999999),
  primary key (org_id, dept_code, type_code)
);

create table public.dms_documents (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null references public.organizations (id),
  doc_code             text not null check (doc_code ~ '^[A-Z0-9]{1,20}-[A-Z]{2,4}-[0-9]{4,6}$'),
  dept_code            text not null,
  seq                  integer not null,
  title                text not null check (char_length(btrim(title)) between 3 and 200),
  folder_id            uuid not null,
  doc_type_id          uuid not null,
  department_id        uuid not null,
  owner_user_id        uuid not null references public.user_profiles (id),
  classification       text not null check (classification in ('public', 'internal', 'confidential', 'restricted')),
  scope                text not null default 'company' check (scope in ('company', 'departments')),
  scope_department_ids uuid[] not null default '{}',
  restricted_role_ids  uuid[] not null default '{}',
  language             text not null default 'en' check (language in ('en', 'bn', 'both')),
  fields               jsonb not null default '{}' check (jsonb_typeof(fields) = 'object'),
  expiry_date          date,
  next_review_date     date,
  -- pending: first file not confirmed yet; cancelled: first upload abandoned (the code stays used).
  lifecycle            text not null default 'pending' check (lifecycle in ('pending', 'published', 'archived', 'cancelled')),
  current_version      integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint dms_documents_org_id_id_uq unique (org_id, id),
  constraint dms_documents_code_uq unique (org_id, doc_code),
  constraint dms_documents_folder_fk foreign key (org_id, folder_id) references public.dms_folders (org_id, id),
  constraint dms_documents_type_fk foreign key (org_id, doc_type_id) references public.dms_doc_types (org_id, id),
  constraint dms_documents_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint dms_documents_scope_ok check (scope = 'company' or cardinality(scope_department_ids) > 0),
  constraint dms_documents_restricted_ok check (classification <> 'restricted' or cardinality(restricted_role_ids) > 0)
);
create index dms_documents_folder_idx on public.dms_documents (org_id, folder_id, lifecycle);
create index dms_documents_expiry_idx on public.dms_documents (org_id, expiry_date) where expiry_date is not null;
create index dms_documents_type_dept_idx on public.dms_documents (org_id, doc_type_id, department_id);
select private.attach_standard_triggers('public.dms_documents');

create table public.dms_versions (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  document_id        uuid not null,
  version            integer not null check (version between 1 and 9999),
  original_file_name text not null check (char_length(original_file_name) between 1 and 255),
  file_kind          text not null check (file_kind in ('pdf', 'docx', 'xlsx', 'json', 'jpg', 'png')),
  mime               text not null,
  size_bytes         integer not null check (size_bytes between 1 and 26214400),
  file_hash          text not null check (file_hash ~ '^[0-9a-f]{64}$'),
  file_path          text not null,
  status             text not null default 'uploading' check (status in ('uploading', 'current', 'superseded', 'cancelled')),
  change_note        text check (change_note is null or char_length(change_note) <= 500),
  expiry_date        date,              -- the expiry this file carries (licence history)
  fields             jsonb not null default '{}',
  uploaded_by        uuid not null references public.user_profiles (id),
  uploaded_at        timestamptz not null default now(),
  published_at       timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint dms_versions_org_id_id_uq unique (org_id, id),
  constraint dms_versions_doc_version_uq unique (org_id, document_id, version),
  constraint dms_versions_document_fk foreign key (org_id, document_id) references public.dms_documents (org_id, id)
);
create unique index dms_versions_hash_uq on public.dms_versions (org_id, file_hash) where status <> 'cancelled';
create index dms_versions_document_idx on public.dms_versions (org_id, document_id, version desc);
select private.attach_standard_triggers('public.dms_versions');

-- Downloads (high volume, insert-only, no row audit).
create table public.dms_access_log (
  id          bigint generated always as identity primary key,
  org_id      uuid not null references public.organizations (id),
  document_id uuid not null,
  version_id  uuid not null,
  user_id     uuid not null,
  action      text not null default 'download' check (action in ('download')),
  at          timestamptz not null default now(),
  constraint dms_access_log_version_fk foreign key (org_id, version_id) references public.dms_versions (org_id, id)
);
create index dms_access_log_doc_idx on public.dms_access_log (org_id, document_id, at desc);

-- -----------------------------------------------------------------------------
-- Seeding: base folders and their types for every company; ISO folders on selection
-- -----------------------------------------------------------------------------
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
                                    review_months, default_classification, sort)
  select p_org_id, fo.id, t.code, t.name, 'catalog', t.field_schema, t.has_expiry, t.expiry_default, t.review_months,
         t.default_classification, t.sort
  from public.dms_catalog_doc_types t
  join public.dms_catalog_folders f on f.code = t.folder_code
  join public.dms_folders fo on fo.org_id = p_org_id and fo.catalog_code = f.code
  where f.profile_code is not distinct from p_profile
  on conflict (org_id, code) do update set active = true;
end;
$$;

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
    when 'hr_manager' then array['dms.manage', 'dms.upload', 'dms.upload_all', 'dms.view_confidential']
    when 'manager'    then array['dms.upload', 'dms.view_confidential']
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
  perform private.seed_assistant_defaults(p_org_id);
  perform private.seed_dms_defaults(p_org_id);
end;
$$;

select private.seed_dms_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
-- 30 June on or after the date (end of the Bangladesh fiscal year).
create or replace function private.dms_fiscal_year_end(p_from date)
returns date
language sql
immutable
set search_path = ''
as $$
  select case when p_from <= make_date(extract(year from p_from)::int, 6, 30)
              then make_date(extract(year from p_from)::int, 6, 30)
              else make_date(extract(year from p_from)::int + 1, 6, 30) end
$$;

create or replace function private.dms_expiry_status(p_expiry date)
returns text
language sql
stable
set search_path = ''
as $$
  select case when p_expiry is null then null
              when p_expiry < current_date then 'expired'
              when p_expiry <= current_date + 60 then 'due'
              else 'active' end
$$;

-- The department code used in document codes: letters and digits only, upper case.
create or replace function private.dms_dept_code(p_department_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select nullif(upper(regexp_replace(coalesce(d.code, ''), '[^A-Za-z0-9]', '', 'g')), '')
  from public.departments d where d.id = p_department_id
$$;

create or replace function private.dms_my_department()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select e.department_id from public.employees e where e.id = private.current_employee_id()
$$;

create or replace function private.dms_can_upload()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('dms.manage') or private.has_permission('dms.upload_all') or private.has_permission('dms.upload')
$$;

-- May the caller upload for / edit documents of this department?
create or replace function private.dms_can_use_department(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('dms.manage') or private.has_permission('dms.upload_all')
      or (private.has_permission('dms.upload') and p_department_id = private.dms_my_department())
$$;

-- The one read rule (security.md section 2). Lists, files, counts and later the AI all use it.
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
          or (private.has_permission('dms.upload') and (d.department_id = private.dms_my_department() or d.owner_user_id = auth.uid())))
$$;

create or replace function private.load_dms_document(p_id uuid)
returns public.dms_documents
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v public.dms_documents;
begin
  select * into v from public.dms_documents where id = p_id and org_id = private.current_org_id();
  if not found or not private.dms_can_read(v) then
    raise exception 'Document not found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

create or replace function private.dms_require_enabled(p_org_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce((select s.enabled from public.dms_settings s where s.org_id = p_org_id), false) then
    raise exception 'The document library is switched off for your company' using errcode = '23514';
  end if;
end;
$$;

-- Keeps only the fields the type defines; checks required ones and value types.
create or replace function private.dms_clean_fields(p_schema jsonb, p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  f     jsonb;
  v     text;
  v_out jsonb := '{}';
begin
  for f in select x from jsonb_array_elements(coalesce(p_schema, '[]')) x loop
    v := nullif(btrim(coalesce(p ->> (f ->> 'key'), '')), '');
    if v is null then
      if coalesce((f ->> 'required')::boolean, false) then
        raise exception 'Fill in "%"', f ->> 'label' using errcode = '22023';
      end if;
      continue;
    end if;
    case f ->> 'type'
      when 'date' then
        begin
          v := v::date::text;
        exception when others then
          raise exception '"%" must be a date', f ->> 'label' using errcode = '22023';
        end;
      when 'number' then
        if v !~ '^-?[0-9]+(\.[0-9]+)?$' then
          raise exception '"%" must be a number', f ->> 'label' using errcode = '22023';
        end if;
      else
        if char_length(v) > 200 then
          raise exception '"%" is too long (200 characters at most)', f ->> 'label' using errcode = '22023';
        end if;
    end case;
    v_out := v_out || jsonb_build_object(f ->> 'key', v);
  end loop;
  return v_out;
end;
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
    'next_review_date', d.next_review_date, 'lifecycle', d.lifecycle, 'created_at', d.created_at, 'updated_at', d.updated_at)
  from public.dms_doc_types t where t.id = d.doc_type_id
$$;

-- -----------------------------------------------------------------------------
-- API: setup (dms.manage)
-- -----------------------------------------------------------------------------
create or replace function private.dms_folder_counts(p_org_id uuid)
returns table (folder_id uuid, documents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select d.folder_id, count(*) from public.dms_documents d
  where d.org_id = p_org_id and d.lifecycle = 'published' and private.dms_can_read(d)
  group by d.folder_id
$$;

create or replace function private.dms_folders_json(p_org_id uuid, p_all boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'parent_id', f.parent_id, 'name', f.name, 'origin', f.origin, 'catalog_code', f.catalog_code,
           'profile_code', (select cf.profile_code from public.dms_catalog_folders cf where cf.code = f.catalog_code),
           'enabled', f.enabled, 'sort', f.sort, 'created_by_me', f.created_by = auth.uid(),
           'documents', coalesce(c.documents, 0))
         order by f.sort, f.name), '[]'::jsonb)
  from public.dms_folders f
  left join private.dms_folder_counts(p_org_id) c on c.folder_id = f.id
  where f.org_id = p_org_id and (p_all or f.enabled)
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
           -- Setup only: the count includes documents the caller may not read.
           'documents', case when p_all then (select count(*) from public.dms_documents d
                                              where d.doc_type_id = t.id and d.lifecycle <> 'cancelled') end)
         order by t.sort, t.name), '[]'::jsonb)
  from public.dms_doc_types t
  join public.dms_folders f on f.id = t.folder_id
  where t.org_id = p_org_id and (p_all or (t.active and f.enabled))
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
    'catalog', (select jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'edition', p.edition, 'summary', p.summary,
                                                    'who_needs_it', p.who_needs_it, 'selected', p.code = any (s.profiles),
                                                    'folders', (select jsonb_agg(c.name order by c.sort) from public.dms_catalog_folders c
                                                                where c.profile_code = p.code))
                                 order by p.sort) from public.dms_iso_profiles p),
    'folders', private.dms_folders_json(v_org, true),
    'types', private.dms_types_json(v_org, true),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'code', private.dms_dept_code(d.id))
                                              order by d.name)
                             from public.departments d where d.org_id = v_org and d.status = 'active'), '[]'::jsonb));
end;
$$;

-- Selecting a standard adds its folders and types; deselecting hides its empty folders (folders with documents stay).
create or replace function public.set_dms_profiles(p_codes text[], p_no_iso boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_codes text[] := coalesce((select array_agg(distinct c) from unnest(coalesce(p_codes, '{}')) c), '{}');
  v_code  text;
begin
  perform private.require_permission('dms.manage');
  perform private.seed_dms_defaults(v_org);
  if (select count(*) from public.dms_iso_profiles where code = any (v_codes)) <> cardinality(v_codes) then
    raise exception 'Unknown ISO standard' using errcode = '22023';
  end if;
  foreach v_code in array v_codes loop
    perform private.dms_add_catalog_folders(v_org, v_code);
  end loop;
  update public.dms_folders f set enabled = false
   where f.org_id = v_org and f.origin = 'iso' and f.enabled
     and (select c.profile_code from public.dms_catalog_folders c where c.code = f.catalog_code) <> all (v_codes)
     and not exists (select 1 from public.dms_documents d where d.folder_id = f.id and d.lifecycle <> 'cancelled')
     and not exists (select 1 from public.dms_folders ch where ch.parent_id = f.id and ch.enabled);
  update public.dms_doc_types t set active = false
   where t.org_id = v_org and t.active
     and exists (select 1 from public.dms_folders f where f.id = t.folder_id and not f.enabled);
  update public.dms_settings set profiles = v_codes, no_iso = cardinality(v_codes) = 0 and coalesce(p_no_iso, false)
   where org_id = v_org;
end;
$$;

-- p: {name, parent_id, enabled, sort}. New folders are custom; dms.upload holders may create and rename their own.
create or replace function public.save_dms_folder(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_manage  boolean := private.has_permission('dms.manage');
  v_old     public.dms_folders;
  v_parent  uuid := case when p ? 'parent_id' then nullif(p ->> 'parent_id', '')::uuid end;
  v_name    text := nullif(btrim(coalesce(p ->> 'name', '')), '');
  v_depth   integer;
  v_id      uuid;
begin
  if not private.dms_can_upload() then
    raise exception 'You do not have permission for this action (dms.upload)' using errcode = '42501';
  end if;
  perform private.dms_require_enabled(v_org);
  if p_id is not null then
    select * into v_old from public.dms_folders where id = p_id and org_id = v_org for update;
    if not found then
      raise exception 'Folder not found' using errcode = 'P0002';
    end if;
    if not v_manage and not (v_old.origin = 'custom' and v_old.created_by = auth.uid()) then
      raise exception 'You can only change folders you created' using errcode = '42501';
    end if;
  end if;
  if v_name is not null and char_length(v_name) not between 2 and 80 then
    raise exception 'A folder name needs 2 to 80 characters' using errcode = '22023';
  end if;

  -- Parent: same company, enabled, not inside itself, custom folders at most 3 levels deep.
  if p ? 'parent_id' and v_parent is not null then
    if not exists (select 1 from public.dms_folders where id = v_parent and org_id = v_org and enabled) then
      raise exception 'Choose an open folder of your company' using errcode = '22023';
    end if;
    if p_id is not null and (v_parent = p_id or exists (
         with recursive up as (select f.id, f.parent_id from public.dms_folders f where f.id = v_parent
                               union all select f.id, f.parent_id from public.dms_folders f join up on f.id = up.parent_id)
         select 1 from up where up.id = p_id)) then
      raise exception 'A folder cannot be moved inside itself' using errcode = '22023';
    end if;
    with recursive up as (select f.id, f.parent_id, 1 as depth from public.dms_folders f where f.id = v_parent
                          union all select f.id, f.parent_id, up.depth + 1 from public.dms_folders f join up on f.id = up.parent_id)
    select max(depth) into v_depth from up;
    if v_depth >= 3 then
      raise exception 'Folders can be nested 3 levels deep at most' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    if v_name is null then
      raise exception 'Give the folder a name' using errcode = '22023';
    end if;
    begin
      insert into public.dms_folders (org_id, parent_id, origin, name, sort)
      values (v_org, v_parent, 'custom', v_name, coalesce((p ->> 'sort')::smallint, 100))
      returning id into v_id;
    exception when unique_violation then
      raise exception 'A folder with this name already exists here' using errcode = '23505';
    end;
    return v_id;
  end if;

  if p ? 'parent_id' and v_old.origin <> 'custom' and v_parent is distinct from v_old.parent_id then
    raise exception 'Built-in folders stay where they are; you can rename or switch them off' using errcode = '23514';
  end if;
  if p ? 'enabled' and (p ->> 'enabled')::boolean is distinct from v_old.enabled then
    if not v_manage then
      raise exception 'You do not have permission for this action (dms.manage)' using errcode = '42501';
    end if;
    if not (p ->> 'enabled')::boolean and (
         exists (select 1 from public.dms_documents d where d.folder_id = p_id and d.lifecycle <> 'cancelled')
         or exists (select 1 from public.dms_folders ch where ch.parent_id = p_id and ch.enabled)) then
      raise exception 'This folder still holds documents or open folders; move them first' using errcode = '23514';
    end if;
  end if;
  begin
    update public.dms_folders
       set name = coalesce(v_name, name),
           parent_id = case when p ? 'parent_id' and origin = 'custom' then v_parent else parent_id end,
           enabled = coalesce((p ->> 'enabled')::boolean, enabled),
           sort = coalesce((p ->> 'sort')::smallint, sort)
     where id = p_id;
  exception when unique_violation then
    raise exception 'A folder with this name already exists here' using errcode = '23505';
  end;
  if p ? 'enabled' and not (p ->> 'enabled')::boolean then
    update public.dms_doc_types set active = false where folder_id = p_id and active;
  end if;
  return p_id;
end;
$$;

-- p: {code, name, folder_id, has_expiry, expiry_default, review_months, default_classification, active}.
-- Built-in types keep their code and fields; custom types have no extra fields.
create or replace function public.save_dms_doc_type(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_old    public.dms_doc_types;
  v_code   text := upper(nullif(btrim(coalesce(p ->> 'code', '')), ''));
  v_folder uuid := nullif(p ->> 'folder_id', '')::uuid;
  v_cls    text := p ->> 'default_classification';
  v_def    text := p ->> 'expiry_default';
  v_months smallint := nullif(p ->> 'review_months', '')::smallint;
  v_id     uuid;
begin
  perform private.require_permission('dms.manage');
  if v_folder is not null and not exists (select 1 from public.dms_folders where id = v_folder and org_id = v_org and enabled) then
    raise exception 'Choose an open folder of your company' using errcode = '22023';
  end if;
  if v_cls is not null and v_cls not in ('public', 'internal', 'confidential', 'restricted') then
    raise exception 'Unknown classification' using errcode = '22023';
  end if;
  if v_def is not null and v_def not in ('none', 'fiscal_year_end') then
    raise exception 'Unknown expiry default' using errcode = '22023';
  end if;
  if v_months is not null and v_months not between 1 and 120 then
    raise exception 'The review period must be 1 to 120 months' using errcode = '22023';
  end if;
  if p_id is null then
    if v_code is null or v_code !~ '^[A-Z]{2,4}$' then
      raise exception 'The type code must be 2 to 4 letters' using errcode = '22023';
    end if;
    if v_folder is null or char_length(coalesce(btrim(p ->> 'name'), '')) < 2 then
      raise exception 'Give the type a name and a folder' using errcode = '22023';
    end if;
    if exists (select 1 from public.dms_catalog_doc_types where code = v_code) then
      raise exception 'The code % is reserved for a built-in type; choose another', v_code using errcode = '23505';
    end if;
    begin
      insert into public.dms_doc_types (org_id, folder_id, code, name, origin, has_expiry, expiry_default, review_months, default_classification)
      values (v_org, v_folder, v_code, btrim(p ->> 'name'), 'custom', coalesce((p ->> 'has_expiry')::boolean, false),
              coalesce(v_def, 'none'), v_months, coalesce(v_cls, 'internal'))
      returning id into v_id;
    exception when unique_violation then
      raise exception 'The type code % is already used', v_code using errcode = '23505';
    end;
    return v_id;
  end if;
  select * into v_old from public.dms_doc_types where id = p_id and org_id = v_org for update;
  if not found then
    raise exception 'Document type not found' using errcode = 'P0002';
  end if;
  if v_code is not null and v_code <> v_old.code then
    raise exception 'A type code never changes: documents are named with it' using errcode = '23514';
  end if;
  update public.dms_doc_types
     set name = coalesce(nullif(btrim(p ->> 'name'), ''), name),
         folder_id = coalesce(v_folder, folder_id),
         has_expiry = case when origin = 'custom' then coalesce((p ->> 'has_expiry')::boolean, has_expiry) else has_expiry end,
         expiry_default = coalesce(v_def, expiry_default),
         review_months = case when p ? 'review_months' then v_months else review_months end,
         default_classification = coalesce(v_cls, default_classification),
         active = coalesce((p ->> 'active')::boolean, active)
   where id = p_id;
  return p_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: library (every member; rows filtered by the read rule)
-- -----------------------------------------------------------------------------
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
    'can', jsonb_build_object('manage', private.has_permission('dms.manage'), 'upload', v_upload, 'upload_all', v_all),
    'my_department_id', private.dms_my_department(),
    'folders', private.dms_folders_json(v_org, false),
    'types', case when v_upload then private.dms_types_json(v_org, false) else '[]'::jsonb end,
    'departments', case when v_upload then coalesce((
        select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name, 'code', private.dms_dept_code(d.id)) order by d.name)
        from public.departments d
        where d.org_id = v_org and d.status = 'active' and (v_all or d.id = private.dms_my_department())), '[]'::jsonb)
      else '[]'::jsonb end,
    'all_departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name)
                                 from public.departments d where d.org_id = v_org and d.status = 'active'), '[]'::jsonb),
    'roles', case when v_upload then coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) order by r.name)
                                               from public.roles r where r.org_id = v_org and r.status = 'active'), '[]'::jsonb)
             else '[]'::jsonb end);
end;
$$;

-- p: {folder_id, include_subfolders, q, department_id, doc_type_id, expiry: expired|due|active, archived, limit}
create or replace function public.list_dms_documents(p jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org     uuid := private.current_org_id();
  v_folder  uuid := nullif(p ->> 'folder_id', '')::uuid;
  v_folders uuid[];
  v_q       text := nullif(btrim(coalesce(p ->> 'q', '')), '');
  v_limit   integer := least(greatest(coalesce((p ->> 'limit')::integer, 200), 1), 500);
begin
  if v_folder is not null then
    if coalesce((p ->> 'include_subfolders')::boolean, true) then
      with recursive down as (select f.id from public.dms_folders f where f.id = v_folder and f.org_id = v_org
                              union all select f.id from public.dms_folders f join down on f.parent_id = down.id)
      select array_agg(id) into v_folders from down;
    else
      v_folders := array[v_folder];
    end if;
  end if;
  return coalesce((
    select jsonb_agg(x.j order by x.sort_key desc)
    from (
      select private.dms_doc_json(d) as j, d.updated_at as sort_key
      from public.dms_documents d
      where d.org_id = v_org
        and d.lifecycle = case when coalesce((p ->> 'archived')::boolean, false) then 'archived' else 'published' end
        and (v_folders is null or d.folder_id = any (v_folders))
        and (nullif(p ->> 'department_id', '') is null or d.department_id = (p ->> 'department_id')::uuid)
        and (nullif(p ->> 'doc_type_id', '') is null or d.doc_type_id = (p ->> 'doc_type_id')::uuid)
        and (nullif(p ->> 'expiry', '') is null or private.dms_expiry_status(d.expiry_date) = p ->> 'expiry')
        and (v_q is null or d.doc_code ilike '%' || v_q || '%' or d.title ilike '%' || v_q || '%')
        and private.dms_can_read(d)
      order by d.updated_at desc
      limit v_limit) x), '[]'::jsonb);
end;
$$;

create or replace function public.get_dms_document(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  d      public.dms_documents := private.load_dms_document(p_id);
  v_edit boolean := private.dms_can_edit(d);
begin
  return private.dms_doc_json(d) || jsonb_build_object(
    'can_edit', v_edit, 'can_manage', private.has_permission('dms.manage'),
    'versions', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', v.id, 'version', v.version, 'version_name', d.doc_code || '_v' || v.version, 'status', v.status,
               'original_file_name', v.original_file_name, 'file_kind', v.file_kind, 'size_bytes', v.size_bytes,
               'expiry_date', v.expiry_date, 'change_note', v.change_note, 'uploaded_at', v.uploaded_at,
               'published_at', v.published_at,
               'uploaded_by', (select up.full_name from public.user_profiles up where up.id = v.uploaded_by))
             order by v.version desc)
      from public.dms_versions v
      where v.document_id = d.id and v.status in ('current', 'superseded')
        and (v.status = 'current' or v_edit)), '[]'::jsonb));
end;
$$;

-- The code a new document of this type and department would get (shown before saving; not reserved).
create or replace function public.dms_next_code(p_doc_type_id uuid, p_department_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_type text := (select t.code from public.dms_doc_types t where t.id = p_doc_type_id and t.org_id = v_org);
  v_dept text := (select private.dms_dept_code(d.id) from public.departments d where d.id = p_department_id and d.org_id = v_org);
begin
  if not private.dms_can_upload() then
    raise exception 'You do not have permission for this action (dms.upload)' using errcode = '42501';
  end if;
  if v_type is null or v_dept is null then
    return null;
  end if;
  return v_dept || '-' || v_type || '-' || lpad((coalesce((select s.last_seq from public.dms_code_sequences s
           where s.org_id = v_org and s.dept_code = v_dept and s.type_code = v_type), 0) + 1)::text, 4, '0');
end;
$$;

-- -----------------------------------------------------------------------------
-- API: upload
-- -----------------------------------------------------------------------------
create or replace function private.dms_kind_mime_ok(p_kind text, p_mime text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_kind
    when 'pdf'  then p_mime = 'application/pdf'
    when 'docx' then p_mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    when 'xlsx' then p_mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    when 'json' then p_mime = 'application/json'
    when 'jpg'  then p_mime = 'image/jpeg'
    when 'png'  then p_mime = 'image/png'
    else false end
$$;

-- p: {document_id (new version) | title, folder_id, doc_type_id, department_id, classification, scope,
--     scope_department_ids, restricted_role_ids, language, fields, expiry_date, next_review_date;
--     file: {name, kind, mime, size_bytes, hash}, change_note}
-- Returns {document_id, version_id, version, doc_code, version_name, path}. Upload the file to that path, then confirm.
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
  v_doc     public.dms_documents;
  v_type    public.dms_doc_types;
  v_dup     text;
  v_dept    uuid;
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
  if not private.dms_can_upload() then
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
  where v.org_id = v_org and v.file_hash = v_hash and v.status <> 'cancelled'
    and not (v.status = 'uploading' and v.uploaded_by = auth.uid())   -- own abandoned attempt: replaced below
  limit 1;
  if v_dup is not null then
    raise exception 'This file is already saved as %', v_dup using errcode = '23505';
  end if;
  update public.dms_versions set status = 'cancelled'
   where org_id = v_org and file_hash = v_hash and status = 'uploading' and uploaded_by = auth.uid();
  update public.dms_documents d set lifecycle = 'cancelled'
   where d.org_id = v_org and d.lifecycle = 'pending'
     and not exists (select 1 from public.dms_versions v where v.document_id = d.id and v.status <> 'cancelled');

  if nullif(p ->> 'document_id', '') is not null then
    -- A new version of an existing document.
    select * into v_doc from public.dms_documents where id = (p ->> 'document_id')::uuid and org_id = v_org for update;
    if not found or not private.dms_can_read(v_doc) then
      raise exception 'Document not found' using errcode = 'P0002';
    end if;
    if not private.dms_can_edit(v_doc) then
      raise exception 'You can only upload new versions for your own department' using errcode = '42501';
    end if;
    if v_doc.lifecycle <> 'published' then
      raise exception 'Only a published document gets a new version' using errcode = '23514';
    end if;
    select * into v_type from public.dms_doc_types where id = v_doc.doc_type_id;
    -- An older unfinished upload of this document (over an hour) is dropped; a fresh one blocks.
    update public.dms_versions set status = 'cancelled'
     where document_id = v_doc.id and status = 'uploading' and (uploaded_at < now() - interval '1 hour' or uploaded_by = auth.uid());
    if exists (select 1 from public.dms_versions where document_id = v_doc.id and status = 'uploading') then
      raise exception 'Someone is uploading a new version of this document right now; try again in a moment' using errcode = '23514';
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
    where id = nullif(p ->> 'doc_type_id', '')::uuid and org_id = v_org and active;
    if not found then
      raise exception 'Choose a document type' using errcode = '22023';
    end if;
    if not exists (select 1 from public.dms_folders where id = nullif(p ->> 'folder_id', '')::uuid and org_id = v_org and enabled) then
      raise exception 'Choose an open folder' using errcode = '22023';
    end if;
    v_dept := coalesce(nullif(p ->> 'department_id', '')::uuid, private.dms_my_department());
    if v_dept is null or not exists (select 1 from public.departments where id = v_dept and org_id = v_org and status = 'active') then
      raise exception 'Choose a department' using errcode = '22023';
    end if;
    if not private.dms_can_use_department(v_dept) then
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
            (p ->> 'folder_id')::uuid, v_type.id, v_dept, auth.uid(), v_cls, v_scope, v_sdepts, v_roles,
            coalesce(p ->> 'language', 'en'), v_fields, v_expiry, v_review)
    returning * into v_doc;
    v_ver := 1;
  end if;

  v_path := v_org || '/' || v_doc.id || '/v' || v_ver || '.' || v_kind;
  insert into public.dms_versions (id, org_id, document_id, version, original_file_name, file_kind, mime, size_bytes,
                                   file_hash, file_path, change_note, expiry_date, fields, uploaded_by)
  values (v_vid, v_org, v_doc.id, v_ver, left(btrim(v_file ->> 'name'), 255), v_kind, v_file ->> 'mime', v_size, v_hash,
          v_path, left(nullif(btrim(coalesce(p ->> 'change_note', '')), ''), 500), v_expiry, v_fields, auth.uid());
  return jsonb_build_object('document_id', v_doc.id, 'version_id', v_vid, 'version', v_ver, 'doc_code', v_doc.doc_code,
                            'version_name', v_doc.doc_code || '_v' || v_ver, 'path', v_path, 'expiry_date', v_expiry);
end;
$$;

-- The file is in storage: publish it. The previous version is superseded in the same transaction.
create or replace function public.dms_confirm_upload(p_version_id uuid)
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
  update public.dms_versions set status = 'superseded'
   where document_id = v.document_id and status = 'current';
  update public.dms_versions set status = 'current', published_at = now() where id = v.id;
  update public.dms_documents
     set lifecycle = 'published', current_version = v.version,
         expiry_date = coalesce(v.expiry_date, expiry_date), fields = v.fields
   where id = v.document_id
  returning * into d;
  perform private.write_audit(v_org, case when v.version = 1 then 'dms.document_published' else 'dms.version_published' end,
    'dms_documents', d.id, null, jsonb_build_object('doc_code', d.doc_code, 'version', v.version, 'file_hash', v.file_hash));
  return private.dms_doc_json(d);
end;
$$;

create or replace function public.dms_cancel_upload(p_version_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.dms_versions;
begin
  select * into v from public.dms_versions where id = p_version_id and org_id = private.current_org_id() for update;
  if not found or v.uploaded_by is distinct from auth.uid() or v.status <> 'uploading' then
    return;
  end if;
  update public.dms_versions set status = 'cancelled' where id = v.id;
  update public.dms_documents d set lifecycle = 'cancelled'
   where d.id = v.document_id and d.lifecycle = 'pending'
     and not exists (select 1 from public.dms_versions x where x.document_id = d.id and x.status <> 'cancelled');
end;
$$;

-- -----------------------------------------------------------------------------
-- API: change, move, archive, download
-- -----------------------------------------------------------------------------
-- p: {title, folder_id, classification, scope, scope_department_ids, restricted_role_ids, language, fields,
--     expiry_date, next_review_date}. Never changes the code, the version or the file.
create or replace function public.update_dms_document(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  d        public.dms_documents := private.load_dms_document(p_id);
  t        public.dms_doc_types;
  v_title  text := coalesce(nullif(btrim(coalesce(p ->> 'title', '')), ''), d.title);
  v_folder uuid := coalesce(nullif(p ->> 'folder_id', '')::uuid, d.folder_id);
  v_cls    text := coalesce(nullif(p ->> 'classification', ''), d.classification);
  v_scope  text := coalesce(nullif(p ->> 'scope', ''), d.scope);
  v_sdepts uuid[] := case when p ? 'scope_department_ids' then private.uuid_array(p, 'scope_department_ids') else d.scope_department_ids end;
  v_roles  uuid[] := case when p ? 'restricted_role_ids' then private.uuid_array(p, 'restricted_role_ids') else d.restricted_role_ids end;
  v_expiry date := case when p ? 'expiry_date' then nullif(p ->> 'expiry_date', '')::date else d.expiry_date end;
begin
  if not private.dms_can_edit(d) then
    raise exception 'You can only change documents of your own department' using errcode = '42501';
  end if;
  if d.lifecycle not in ('published', 'archived') then
    raise exception 'Finish the upload first' using errcode = '23514';
  end if;
  select * into t from public.dms_doc_types where id = d.doc_type_id;
  if char_length(v_title) not between 3 and 200 then
    raise exception 'The title needs 3 to 200 characters' using errcode = '22023';
  end if;
  if lower(v_title) <> lower(d.title) and exists (
       select 1 from public.dms_documents x where x.org_id = v_org and x.id <> d.id and x.doc_type_id = d.doc_type_id
         and x.department_id = d.department_id and lower(x.title) = lower(v_title) and x.lifecycle in ('published', 'pending')) then
    raise exception 'Another document of this type and department already has this title' using errcode = '23505';
  end if;
  if v_folder <> d.folder_id and not exists (select 1 from public.dms_folders where id = v_folder and org_id = v_org and enabled) then
    raise exception 'Choose an open folder' using errcode = '22023';
  end if;
  if v_cls not in ('public', 'internal', 'confidential', 'restricted') or v_scope not in ('company', 'departments') then
    raise exception 'Unknown classification or scope' using errcode = '22023';
  end if;
  if v_scope = 'company' then
    v_sdepts := '{}';
  elsif cardinality(v_sdepts) = 0 or (select count(*) from public.departments where id = any (v_sdepts) and org_id = v_org) <> cardinality(v_sdepts) then
    raise exception 'Choose departments of your company' using errcode = '22023';
  end if;
  if v_cls <> 'restricted' then
    v_roles := '{}';
  elsif cardinality(v_roles) = 0 or (select count(*) from public.roles where id = any (v_roles) and org_id = v_org) <> cardinality(v_roles) then
    raise exception 'A restricted document needs the roles that may read it' using errcode = '22023';
  end if;
  if t.has_expiry and v_expiry is null then
    raise exception 'Enter the expiry date' using errcode = '22023';
  end if;
  update public.dms_documents
     set title = v_title, folder_id = v_folder, classification = v_cls, scope = v_scope, scope_department_ids = v_sdepts,
         restricted_role_ids = v_roles, language = coalesce(nullif(p ->> 'language', ''), language),
         fields = case when p ? 'fields' then private.dms_clean_fields(t.field_schema, p -> 'fields') else fields end,
         expiry_date = case when t.has_expiry then v_expiry end,
         next_review_date = case when p ? 'next_review_date' then nullif(p ->> 'next_review_date', '')::date else next_review_date end
   where id = d.id
  returning * into d;
  return private.dms_doc_json(d);
end;
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
    update public.dms_documents set lifecycle = 'archived' where id = d.id;
  else
    if d.lifecycle <> 'archived' then
      raise exception 'Only an archived document can be restored' using errcode = '23514';
    end if;
    if exists (select 1 from public.dms_documents x where x.org_id = d.org_id and x.id <> d.id and x.doc_type_id = d.doc_type_id
               and x.department_id = d.department_id and lower(x.title) = lower(d.title) and x.lifecycle in ('published', 'pending')) then
      raise exception 'A published document with the same title exists; archive it first' using errcode = '23505';
    end if;
    update public.dms_documents set lifecycle = 'published' where id = d.id;
  end if;
end;
$$;

-- Returns the storage path (the browser makes a 60-second signed URL) and logs the download.
-- Readers get the current file; editors may also open older versions.
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
  if not (v.status = 'current' or (v.status = 'superseded' and private.dms_can_edit(d))) then
    raise exception 'File not found' using errcode = 'P0002';
  end if;
  insert into public.dms_access_log (org_id, document_id, version_id, user_id) values (v_org, d.id, v.id, auth.uid());
  return jsonb_build_object('path', v.file_path, 'file_name', d.doc_code || '_v' || v.version || '.' || v.file_kind,
                            'mime', v.mime);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: overview (setup steps, counts, licences by expiry)
-- -----------------------------------------------------------------------------
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
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  if v_to < v_from or v_to > v_from + 3660 then
    raise exception 'Choose a date range of at most 10 years' using errcode = '22023';
  end if;
  perform private.seed_dms_defaults(v_org);
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
        'awaiting_approval', 0,
        'indexed', 0),
      'expiring', coalesce((
        select jsonb_agg(private.dms_doc_json(r.doc) order by r.expiry_date)
        from readable r
        where r.expiry_date is not null and r.expiry_date <= v_to and (r.expiry_date >= v_from or r.expiry_date < current_date)), '[]'::jsonb))
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: dms-documents/{org}/{document}/v{n}.{ext}
-- Insert: only the path reserved for the caller's unfinished upload. Read: the read rule
-- (current file; older versions for editors). No update or delete from clients.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('dms-documents', 'dms-documents', false, 26214400,
   array['application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'application/json', 'image/jpeg', 'image/png'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

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
  return private.dms_can_read(d) and (v.status = 'current' or (v.status = 'superseded' and private.dms_can_edit(d)));
end;
$$;

drop policy if exists olympus_dms_files_select on storage.objects;
drop policy if exists olympus_dms_files_insert on storage.objects;
create policy olympus_dms_files_select on storage.objects for select to authenticated
  using (bucket_id = 'dms-documents' and private.dms_file_access(name, false));
create policy olympus_dms_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'dms-documents' and private.dms_file_access(name, true));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.dms_iso_profiles      enable row level security;
alter table public.dms_catalog_folders   enable row level security;
alter table public.dms_catalog_doc_types enable row level security;
alter table public.dms_settings          enable row level security;
alter table public.dms_folders           enable row level security;
alter table public.dms_doc_types         enable row level security;
alter table public.dms_code_sequences    enable row level security;
alter table public.dms_documents         enable row level security;
alter table public.dms_versions          enable row level security;
alter table public.dms_access_log        enable row level security;
revoke all on table
  public.dms_iso_profiles, public.dms_catalog_folders, public.dms_catalog_doc_types, public.dms_settings, public.dms_folders,
  public.dms_doc_types, public.dms_code_sequences, public.dms_documents, public.dms_versions, public.dms_access_log
from anon, authenticated;

revoke all on function
  public.get_dms_setup(), public.set_dms_profiles(text[], boolean), public.save_dms_folder(uuid, jsonb),
  public.save_dms_doc_type(uuid, jsonb), public.get_dms_library(), public.list_dms_documents(jsonb),
  public.get_dms_document(uuid), public.dms_next_code(uuid, uuid), public.dms_register_upload(jsonb),
  public.dms_confirm_upload(uuid), public.dms_cancel_upload(uuid), public.update_dms_document(uuid, jsonb),
  public.archive_dms_document(uuid, boolean), public.dms_file_path(uuid), public.get_dms_overview(date, date)
from public, anon;
grant execute on function
  public.get_dms_setup(), public.set_dms_profiles(text[], boolean), public.save_dms_folder(uuid, jsonb),
  public.save_dms_doc_type(uuid, jsonb), public.get_dms_library(), public.list_dms_documents(jsonb),
  public.get_dms_document(uuid), public.dms_next_code(uuid, uuid), public.dms_register_upload(jsonb),
  public.dms_confirm_upload(uuid), public.dms_cancel_upload(uuid), public.update_dms_document(uuid, jsonb),
  public.archive_dms_document(uuid, boolean), public.dms_file_path(uuid), public.get_dms_overview(date, date)
to authenticated;

revoke all on function
  private.dms_add_catalog_folders(uuid, text), private.seed_dms_defaults(uuid), private.dms_fiscal_year_end(date),
  private.dms_expiry_status(date), private.dms_dept_code(uuid), private.dms_my_department(), private.dms_can_upload(),
  private.dms_can_use_department(uuid), private.dms_can_read(public.dms_documents), private.dms_can_edit(public.dms_documents),
  private.load_dms_document(uuid), private.dms_require_enabled(uuid), private.dms_clean_fields(jsonb, jsonb),
  private.dms_doc_json(public.dms_documents), private.dms_folder_counts(uuid), private.dms_folders_json(uuid, boolean),
  private.dms_types_json(uuid, boolean), private.dms_kind_mime_ok(text, text)
from public, anon, authenticated;
-- Storage policies run as the caller.
grant execute on function private.dms_file_access(text, boolean) to authenticated;
revoke all on function private.dms_file_access(text, boolean) from public, anon;
