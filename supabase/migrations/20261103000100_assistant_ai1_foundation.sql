-- =============================================================================
-- AI assistant AI1: foundation (settings, keys, role matrix, messages, tables
-- for resources, the app guide, the per-company vector store, chats and logs).
-- Design: docs/Part04Architecture.md (sections 5, 8, 12 = revision 2).
--
-- The company gives every credential in the UI: a chat key (Anthropic, OpenAI or
-- Google) and an embedding key (the same key for OpenAI / Google; a second key,
-- Voyage recommended, when chat is Claude). Keys are encrypted and never come
-- back to the browser (last 4 only); the Edge Function reads them with the
-- service role. Vectors are always 1024 dimensions, one store for every
-- company, every row scoped by org_id and closed to the API.
-- assistant.manage: Admin implicit; HR Manager only when an Admin hands it over
-- (it cannot be given to any other role). A matrix tick only works when the
-- role holds one of the topic's permissions; sensitive topics for HR Manager
-- are Admin-only ticks.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.password_requests') is null then
    raise exception 'Apply 20261102000300_comm_c3_password_requests.sql first, then run this file again';
  end if;
end;
$guard$;

create extension if not exists vector with schema extensions;

-- -----------------------------------------------------------------------------
-- Permissions
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('assistant.manage',     'assistant', 'Set up the AI assistant (keys, resources, model, role access, messages)', false),
  ('assistant.view_usage', 'assistant', 'See AI assistant usage and the question log',                           true)
on conflict (key) do nothing;

-- Only the HR Manager role may receive assistant.manage (Admin holds it implicitly).
create or replace function private.assistant_manage_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.permission_key = 'assistant.manage'
     and (select r.system_key from public.roles r where r.id = new.role_id) is distinct from 'hr_manager' then
    raise exception 'The AI assistant setup can only be handed to the HR Manager role' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger assistant_manage_guard before insert or update on public.role_permissions
  for each row execute function private.assistant_manage_guard();

-- -----------------------------------------------------------------------------
-- Keys: two slots in org_integrations
-- -----------------------------------------------------------------------------
alter table public.org_integrations drop constraint if exists org_integrations_kind_check;
alter table public.org_integrations drop constraint if exists org_integrations_provider_check;
alter table public.org_integrations drop constraint if exists org_integrations_model_check;
alter table public.org_integrations add constraint org_integrations_kind_check
  check (kind in ('ai', 'assistant_chat', 'assistant_embed'));
alter table public.org_integrations add constraint org_integrations_provider_check check (
  (kind = 'ai' and provider = 'anthropic')
  or (kind = 'assistant_chat' and provider in ('anthropic', 'openai', 'google'))
  or (kind = 'assistant_embed' and provider in ('openai', 'google', 'voyage')));
alter table public.org_integrations add constraint org_integrations_model_check check (
  (kind = 'ai' and model in ('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'))
  or (kind <> 'ai' and char_length(model) between 3 and 80));

-- Models the assistant offers (the UI reads this list).
create or replace function private.assistant_models()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{
    "chat": {
      "anthropic": [{"id":"claude-sonnet-5-5","label":"Claude Sonnet 5.5"},{"id":"claude-haiku-5-5","label":"Claude Haiku 5.5"},{"id":"claude-opus-5-5","label":"Claude Opus 5.5"}],
      "openai":    [{"id":"gpt-4.1","label":"GPT-4.1"},{"id":"gpt-4.1-mini","label":"GPT-4.1 mini"}],
      "google":    [{"id":"gemini-2.5-pro","label":"Gemini 2.5 Pro"},{"id":"gemini-2.5-flash","label":"Gemini 2.5 Flash"}]
    },
    "embed": {
      "openai": [{"id":"text-embedding-3-small","label":"text-embedding-3-small"},{"id":"text-embedding-3-large","label":"text-embedding-3-large"}],
      "google": [{"id":"gemini-embedding-001","label":"gemini-embedding-001"}],
      "voyage": [{"id":"voyage-3.5","label":"voyage-3.5"},{"id":"voyage-3.5-lite","label":"voyage-3.5-lite"}]
    }
  }'::jsonb
$$;

-- -----------------------------------------------------------------------------
-- Setup tables
-- -----------------------------------------------------------------------------
create table public.assistant_settings (
  org_id            uuid primary key references public.organizations (id),
  enabled           boolean not null default true,
  name              text not null default 'Olympus Assistant' check (char_length(btrim(name)) between 2 and 40),
  language_mode     text not null default 'follow' check (language_mode in ('follow', 'bn', 'en')),
  hyper             jsonb not null default '{"temperature":0.2,"max_answer_tokens":600,"answer_style":"short","top_k":6,"min_score":0.3,"chunk_size":400,"chunk_overlap":15}',
  monthly_token_cap integer check (monthly_token_cap is null or monthly_token_cap between 1000 and 1000000000),
  retention_days    smallint not null default 90 check (retention_days between 7 and 365),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references public.user_profiles (id),
  updated_by        uuid references public.user_profiles (id)
);
create trigger set_row_meta before insert or update on public.assistant_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.assistant_settings
  for each row execute function private.audit_row_change();

create table public.assistant_topics (
  key          text primary key,
  topic_group  text not null check (topic_group in ('updates', 'knowledge')),
  label        text not null,
  hint         text not null,
  needs_any_of text[] not null default '{}',
  is_sensitive boolean not null default false,
  sort         smallint not null
);
insert into public.assistant_topics (key, topic_group, label, hint, needs_any_of, is_sensitive, sort) values
  ('up.my_day',          'updates',   'My day',               'My check-in today and shift',                 '{attendance.view_own}', false, 1),
  ('up.my_leave',        'updates',   'My leave',             'Balance and pending requests',                '{leave.request}', false, 2),
  ('up.my_payslip',      'updates',   'My payslip',           '"Your payslip is ready" (no amounts)',        '{payroll.view_own}', false, 3),
  ('up.team_today',      'updates',   'Team today',           'Present / late / absent counts of my team',   '{attendance.view_team,attendance.view_all}', false, 4),
  ('up.approvals',       'updates',   'Approvals waiting',    'Leave, overtime, swap requests for me',       '{leave.approve,overtime.approve,swaps.approve}', false, 5),
  ('up.headcount',       'updates',   'Headcount',            'Total, active, new this month',               '{employees.view}', false, 6),
  ('up.payroll_status',  'updates',   'Payroll status',       'Run status only, no amounts',                 '{payroll.prepare,payroll.approve}', true, 7),
  ('up.hiring',          'updates',   'Hiring',               'Open vacancies and applicants waiting',       '{recruit.manage,workforce.view}', false, 8),
  ('up.new_resources',   'updates',   'New policies',         '"New policy published" for readable documents', '{}', false, 9),
  ('kb.app_guide',       'knowledge', 'App guide',            'How to use Olympus pages and features',       '{}', false, 10),
  ('kb.company_policy',  'knowledge', 'Company policies',     'Leave, attendance, conduct, dress code',      '{}', false, 11),
  ('kb.hr_rules',        'knowledge', 'HR rules & procedures', 'Joining, transfer, resignation, settlement', '{}', false, 12),
  ('kb.circulars',       'knowledge', 'Notices & circulars',  'Holiday notices, office closures',            '{}', false, 13),
  ('kb.labour_law',      'knowledge', 'Labour law',           'Bangladesh Labour Act / EPZ Act',             '{}', false, 14),
  ('kb.tax_pf_gratuity', 'knowledge', 'Tax, PF & gratuity',   'Statutory rules',                             '{}', false, 15),
  ('kb.pay_policy',      'knowledge', 'Pay & benefits policy', 'Salary structure, bonus, allowances',        '{}', false, 16),
  ('kb.manager_guide',   'knowledge', 'Manager guide',        'Approving requests, reviews',                 '{}', false, 17),
  ('kb.confidential',    'knowledge', 'Confidential HR',      'Disciplinary and investigation SOPs',         '{}', true, 18);

create table public.assistant_role_settings (
  role_id             uuid primary key,
  org_id              uuid not null,
  enabled             boolean not null default true,
  daily_limit         integer check (daily_limit is null or daily_limit between 1 and 500),
  greeting            text not null check (char_length(btrim(greeting)) between 2 and 240),
  suggestions         text[] not null default '{}' check (cardinality(suggestions) <= 6),
  notice              text not null default '' check (char_length(notice) <= 160),
  not_allowed_message text not null check (char_length(btrim(not_allowed_message)) between 2 and 240),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id),
  updated_by          uuid references public.user_profiles (id),
  constraint assistant_role_settings_role_fk foreign key (org_id, role_id) references public.roles (org_id, id)
);
create trigger set_row_meta before insert or update on public.assistant_role_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.assistant_role_settings
  for each row execute function private.audit_row_change();

create table public.assistant_role_topics (
  role_id   uuid not null,
  org_id    uuid not null,
  topic_key text not null references public.assistant_topics (key),
  allowed   boolean not null,
  primary key (role_id, topic_key),
  constraint assistant_role_topics_role_fk foreign key (org_id, role_id) references public.roles (org_id, id)
);
create trigger audit after insert or update on public.assistant_role_topics
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Knowledge: resources (upload now, DMS later), the app guide, the vector store
-- -----------------------------------------------------------------------------
create table public.assistant_resources (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations (id),
  source          text not null default 'upload' check (source in ('upload', 'dms')),
  dms_document_id uuid,
  dms_version_id  uuid,
  name            text not null check (char_length(btrim(name)) between 1 and 200),
  kind            text not null check (kind in ('pdf', 'docx', 'json')),
  size_bytes      integer not null check (size_bytes between 1 and 20971520),
  file_hash       text not null check (file_hash ~ '^[0-9a-f]{64}$'),
  file_path       text,
  topic_key       text not null references public.assistant_topics (key),
  audience_role_ids uuid[] not null default '{}',
  version         integer not null default 1,
  replaces_id     uuid,
  status          text not null default 'uploading' check (status in ('uploading', 'processing', 'ready', 'failed', 'archived')),
  error           text check (error is null or char_length(error) <= 500),
  units           integer,
  chunks          integer,
  processed_through integer not null default 0,
  embedding_model text,
  uploaded_by     uuid references public.user_profiles (id) default auth.uid(),
  uploaded_at     timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid references public.user_profiles (id),
  updated_by      uuid references public.user_profiles (id),
  constraint assistant_resources_org_id_id_uq unique (org_id, id),
  constraint assistant_resources_dms check (source = 'upload' or dms_document_id is not null)
);
create unique index assistant_resources_hash_uq on public.assistant_resources (org_id, file_hash) where status <> 'archived';
select private.attach_standard_triggers('public.assistant_resources');

-- Written by us (platform), the same for every company; indexed per company with its own key.
create table public.assistant_guide_articles (
  key          text primary key check (key ~ '^[a-z0-9_.-]{2,60}$'),
  route        text not null,
  title        text not null,
  title_bn     text,
  body         text not null,
  needs_any_of text[] not null default '{}',
  tour_targets text[] not null default '{}',
  keywords     text[] not null default '{}',
  sort         smallint not null default 0,
  updated_at   timestamptz not null default now()
);

-- The per-company vector store: every row has org_id; the API never reads it directly.
create table public.assistant_chunks (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null references public.organizations (id),
  source          text not null check (source in ('resource', 'guide')),
  resource_id     uuid,
  guide_key       text references public.assistant_guide_articles (key),
  chunk_index     integer not null,
  location        text not null,
  section         text not null default '',
  passage         text not null,
  token_count     integer not null default 0,
  embedding       extensions.vector(1024),
  embedding_model text not null,
  fts             tsvector generated always as (to_tsvector('simple', section || ' ' || passage)) stored,
  created_at      timestamptz not null default now(),
  constraint assistant_chunks_resource_fk foreign key (org_id, resource_id) references public.assistant_resources (org_id, id),
  constraint assistant_chunks_source check ((source = 'resource') = (resource_id is not null) and (source = 'guide') = (guide_key is not null))
);
create index assistant_chunks_org_idx on public.assistant_chunks (org_id, source);
create index assistant_chunks_resource_idx on public.assistant_chunks (resource_id, chunk_index);
create index assistant_chunks_fts_idx on public.assistant_chunks using gin (fts);
create index assistant_chunks_embedding_idx on public.assistant_chunks using hnsw (embedding extensions.vector_cosine_ops);

-- -----------------------------------------------------------------------------
-- Chats and the question log (D6: own history 90 days; D7: question text 90 days)
-- -----------------------------------------------------------------------------
create table public.assistant_conversations (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  user_id    uuid not null references public.user_profiles (id),
  started_at timestamptz not null default now(),
  last_at    timestamptz not null default now(),
  constraint assistant_conversations_org_id_id_uq unique (org_id, id)
);
create index assistant_conversations_user_idx on public.assistant_conversations (user_id, last_at desc);

create table public.assistant_messages (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null,
  conversation_id uuid not null,
  sender          text not null check (sender in ('user', 'ai')),
  content         text not null check (char_length(content) <= 20000),
  kind            text check (kind is null or kind in ('answer', 'dont_know', 'not_allowed', 'personal_data', 'updates', 'refused')),
  citations       jsonb not null default '[]',
  route           text,
  created_at      timestamptz not null default now(),
  constraint assistant_messages_conversation_fk foreign key (org_id, conversation_id) references public.assistant_conversations (org_id, id)
);
create index assistant_messages_conversation_idx on public.assistant_messages (conversation_id, created_at);

create table public.assistant_query_log (
  id          bigserial primary key,
  org_id      uuid not null references public.organizations (id),
  user_id     uuid not null,
  role_id     uuid,
  asked_at    timestamptz not null default now(),
  question    text check (question is null or char_length(question) <= 4000),
  route       text,
  kind        text not null,
  topics_used text[] not null default '{}',
  chunk_ids   uuid[] not null default '{}',
  tokens_in   integer not null default 0,
  tokens_out  integer not null default 0,
  helpful     boolean
);
create index assistant_query_log_user_day_idx on public.assistant_query_log (user_id, asked_at);
create index assistant_query_log_org_idx on public.assistant_query_log (org_id, asked_at);

-- -----------------------------------------------------------------------------
-- Defaults per company (same as DEFAULT_SETUP in src/AIassistant/core/catalog.ts)
-- -----------------------------------------------------------------------------
create or replace function private.assistant_default_topics(p_system_key text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case p_system_key
    when 'hr_manager' then array['up.my_day', 'up.my_leave', 'up.my_payslip', 'up.new_resources', 'up.team_today', 'up.approvals',
                                 'up.headcount', 'up.payroll_status', 'up.hiring', 'kb.app_guide', 'kb.company_policy', 'kb.hr_rules',
                                 'kb.circulars', 'kb.labour_law', 'kb.tax_pf_gratuity', 'kb.pay_policy', 'kb.manager_guide']
    when 'manager' then array['up.my_day', 'up.my_leave', 'up.my_payslip', 'up.new_resources', 'up.team_today', 'up.approvals',
                              'kb.app_guide', 'kb.company_policy', 'kb.hr_rules', 'kb.circulars', 'kb.labour_law', 'kb.manager_guide']
    else array['up.my_day', 'up.my_leave', 'up.my_payslip', 'up.new_resources', 'kb.app_guide', 'kb.company_policy', 'kb.hr_rules', 'kb.circulars']
  end
$$;

-- Missing rows only, so it can run any time (new roles get defaults the next time setup is read).
create or replace function private.seed_assistant_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.assistant_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.assistant_role_settings (role_id, org_id, daily_limit, greeting, suggestions, not_allowed_message)
  select r.id, r.org_id,
         case r.system_key when 'admin' then null when 'hr_manager' then 50 when 'manager' then 30 else 20 end,
         case r.system_key when 'admin' then 'Hi! Ask me about any company document, the app or today''s updates.'
                           when 'hr_manager' then 'Hi! I can answer from company policies, labour law, the app guide and your updates.'
                           when 'manager' then 'Hi! Ask me about policies, the app, or what is waiting for your approval.'
                           else 'Hi! Ask me about company policies, how to use the app and your own updates.' end,
         case r.system_key when 'manager' then array['What is waiting for my approval?', 'How do I approve overtime?']
                           when 'hr_manager' then array['How many casual leaves per year?', 'How do I run payroll?']
                           when 'admin' then array['How do I add an employee?', 'Payroll status this month?']
                           else array['How do I apply for leave?', 'অফিস কয়টায় শুরু হয়?'] end,
         'This topic is not open for your role. Please ask HR.'
  from public.roles r
  where r.org_id = p_org_id
  on conflict (role_id) do nothing;
  insert into public.assistant_role_topics (role_id, org_id, topic_key, allowed)
  select r.id, r.org_id, t.key, r.system_key = 'admin' or t.key = any (private.assistant_default_topics(r.system_key))
  from public.roles r cross join public.assistant_topics t
  where r.org_id = p_org_id
  on conflict (role_id, topic_key) do nothing;
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
end;
$$;

select private.seed_assistant_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.role_has_permission(p_role_id uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.roles r where r.id = p_role_id and r.system_key = 'admin')
      or exists (select 1 from public.role_permissions rp where rp.role_id = p_role_id and rp.permission_key = p_key)
$$;

-- A topic works for a role only when the role holds one of its permissions (or it needs none).
create or replace function private.role_can_use_topic(p_role_id uuid, p_topic public.assistant_topics)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select cardinality(p_topic.needs_any_of) = 0
      or exists (select 1 from unnest(p_topic.needs_any_of) k where private.role_has_permission(p_role_id, k))
$$;

-- Topics the assistant may use for a role right now (org on, role on, tick, permission).
create or replace function private.assistant_allowed_topics(p_role_id uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(t.key order by t.sort), '{}')
  from public.assistant_topics t
  join public.roles r on r.id = p_role_id
  join public.assistant_settings s on s.org_id = r.org_id and s.enabled
  join public.assistant_role_settings rs on rs.role_id = r.id and rs.enabled
  left join public.assistant_role_topics rt on rt.role_id = r.id and rt.topic_key = t.key
  where (r.system_key = 'admin' or coalesce(rt.allowed, false)) and private.role_can_use_topic(r.id, t)
$$;

create or replace function private.validate_assistant_hyper(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_t   numeric := (p ->> 'temperature')::numeric;
  v_max integer := (p ->> 'max_answer_tokens')::integer;
  v_k   integer := (p ->> 'top_k')::integer;
  v_min numeric := (p ->> 'min_score')::numeric;
  v_cs  integer := (p ->> 'chunk_size')::integer;
  v_ov  integer := (p ->> 'chunk_overlap')::integer;
  v_st  text := p ->> 'answer_style';
begin
  if v_t is null or v_t not between 0 and 1 then raise exception 'Creativity must be between 0 and 1' using errcode = '22023'; end if;
  if v_max is null or v_max not between 200 and 2000 then raise exception 'Answer length must be between 200 and 2000' using errcode = '22023'; end if;
  if v_k is null or v_k not between 2 and 12 then raise exception 'Sources per answer must be between 2 and 12' using errcode = '22023'; end if;
  if v_min is null or v_min not between 0 and 0.9 then raise exception 'Minimum match must be between 0 and 0.9' using errcode = '22023'; end if;
  if v_cs is null or v_cs not between 200 and 1000 then raise exception 'Chunk size must be between 200 and 1000' using errcode = '22023'; end if;
  if v_ov is null or v_ov not between 0 and 30 then raise exception 'Overlap must be between 0 and 30' using errcode = '22023'; end if;
  if v_st is null or v_st not in ('short', 'detailed') then raise exception 'Answer style must be short or detailed' using errcode = '22023'; end if;
  return jsonb_build_object('temperature', v_t, 'max_answer_tokens', v_max, 'top_k', v_k, 'min_score', v_min,
                            'chunk_size', v_cs, 'chunk_overlap', v_ov, 'answer_style', v_st);
end;
$$;

-- The embedding slot actually used: the explicit one, else the chat key when it can embed.
create or replace function private.assistant_embed_source(p_org_id uuid)
returns table (kind text, provider text, model text, ready boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select * from (
    select 'assistant_embed'::text, i.provider, i.model, i.test_status = 'ok' and i.enabled and i.secret_enc is not null
    from public.org_integrations i where i.org_id = p_org_id and i.kind = 'assistant_embed'
    union all
    select 'assistant_chat', i.provider,
           case i.provider when 'openai' then 'text-embedding-3-small' else 'gemini-embedding-001' end,
           i.test_status = 'ok' and i.enabled and i.secret_enc is not null
    from public.org_integrations i
    where i.org_id = p_org_id and i.kind = 'assistant_chat' and i.provider in ('openai', 'google')
      and not exists (select 1 from public.org_integrations e where e.org_id = p_org_id and e.kind = 'assistant_embed')
  ) x limit 1
$$;

create or replace function private.assistant_key_json(p_org_id uuid, p_kind text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('provider', i.provider, 'model', i.model, 'last4', i.secret_last4, 'status',
                            case when i.test_status = 'ok' then 'tested' when i.test_status = 'failed' then 'failed' else 'saved' end,
                            'tested_at', i.tested_at, 'message', i.test_message)
  from public.org_integrations i where i.org_id = p_org_id and i.kind = p_kind
$$;

-- -----------------------------------------------------------------------------
-- API: setup (assistant.manage)
-- -----------------------------------------------------------------------------
create or replace function public.get_assistant_setup()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_hr  uuid := (select id from public.roles where org_id = private.current_org_id() and system_key = 'hr_manager');
  e     record;
begin
  perform private.require_permission('assistant.manage');
  perform private.seed_assistant_defaults(v_org);
  select * into e from private.assistant_embed_source(v_org);
  return (
    select jsonb_build_object(
      'is_admin', private.is_org_admin(),
      'settings', jsonb_build_object('enabled', s.enabled, 'name', s.name, 'language_mode', s.language_mode, 'hyper', s.hyper,
                                     'monthly_token_cap', s.monthly_token_cap, 'retention_days', s.retention_days),
      'hr_can_manage', v_hr is not null and exists (select 1 from public.role_permissions rp where rp.role_id = v_hr and rp.permission_key = 'assistant.manage'),
      'keys', jsonb_build_object('chat', private.assistant_key_json(v_org, 'assistant_chat'), 'embed', private.assistant_key_json(v_org, 'assistant_embed'),
                                 'embed_effective', case when e.provider is null then null else
                                   jsonb_build_object('slot', case e.kind when 'assistant_chat' then 'chat' else 'embed' end,
                                                      'provider', e.provider, 'model', e.model, 'ready', e.ready) end),
      'models', private.assistant_models(),
      'topics', (select jsonb_agg(jsonb_build_object('key', t.key, 'group', t.topic_group, 'label', t.label, 'hint', t.hint,
                                                     'needs_any_of', to_jsonb(t.needs_any_of), 'sensitive', t.is_sensitive) order by t.sort)
                 from public.assistant_topics t),
      'roles', (select jsonb_agg(jsonb_build_object(
                  'id', r.id, 'name', r.name, 'system_key', r.system_key, 'status', r.status,
                  'enabled', rs.enabled, 'daily_limit', rs.daily_limit,
                  'messages', jsonb_build_object('greeting', rs.greeting, 'suggestions', to_jsonb(rs.suggestions), 'notice', rs.notice,
                                                 'not_allowed', rs.not_allowed_message),
                  'ticks', (select jsonb_object_agg(rt.topic_key, rt.allowed) from public.assistant_role_topics rt where rt.role_id = r.id),
                  'usable', (select jsonb_object_agg(t.key, private.role_can_use_topic(r.id, t)) from public.assistant_topics t))
                order by case r.system_key when 'admin' then 0 when 'hr_manager' then 1 when 'manager' then 2 when 'employee' then 3 else 4 end, r.name)
                from public.roles r join public.assistant_role_settings rs on rs.role_id = r.id
                where r.org_id = v_org and r.status = 'active'),
      'resources_ready', (select count(*) from public.assistant_resources x where x.org_id = v_org and x.status = 'ready'))
    from public.assistant_settings s where s.org_id = v_org);
end;
$$;

create or replace function public.save_assistant_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_name text := btrim(coalesce(p ->> 'name', ''));
  v_lang text := coalesce(p ->> 'language_mode', 'follow');
begin
  perform private.require_permission('assistant.manage');
  if char_length(v_name) not between 2 and 40 then
    raise exception 'The assistant name needs 2 to 40 characters' using errcode = '22023';
  end if;
  if v_lang not in ('follow', 'bn', 'en') then
    raise exception 'Unknown language mode' using errcode = '22023';
  end if;
  perform private.seed_assistant_defaults(v_org);
  update public.assistant_settings
     set enabled = coalesce((p ->> 'enabled')::boolean, enabled), name = v_name, language_mode = v_lang,
         monthly_token_cap = case when p ? 'monthly_token_cap' then nullif(p ->> 'monthly_token_cap', '')::integer else monthly_token_cap end
   where org_id = v_org;
end;
$$;

-- Admin only: hand the setup to the HR Manager role, or take it back.
create or replace function public.set_assistant_delegation(p_on boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_hr  uuid := (select id from public.roles where org_id = private.current_org_id() and system_key = 'hr_manager');
begin
  if not private.is_org_admin() then
    raise exception 'Only an Admin can hand over the AI assistant setup' using errcode = '42501';
  end if;
  if v_hr is null then
    raise exception 'This company has no HR Manager role' using errcode = 'P0002';
  end if;
  if p_on then
    insert into public.role_permissions (org_id, role_id, permission_key) values (v_org, v_hr, 'assistant.manage') on conflict do nothing;
  else
    delete from public.role_permissions where role_id = v_hr and permission_key = 'assistant.manage';
  end if;
  perform private.write_audit(v_org, case when p_on then 'assistant.delegated' else 'assistant.delegation_removed' end,
                              'roles', v_hr, null, null);
end;
$$;

-- p: {slot: chat|embed, provider, model, api_key}. The key is encrypted; only the last 4 characters are kept readable.
create or replace function public.save_assistant_key(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org      uuid := private.current_org_id();
  v_slot     text := p ->> 'slot';
  v_kind     text := case p ->> 'slot' when 'chat' then 'assistant_chat' when 'embed' then 'assistant_embed' end;
  v_provider text := p ->> 'provider';
  v_model    text := p ->> 'model';
  v_key      text := nullif(btrim(coalesce(p ->> 'api_key', '')), '');
  v_exists   boolean;
begin
  perform private.require_permission('assistant.manage');
  if v_kind is null then
    raise exception 'Unknown key slot' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(private.assistant_models() -> v_slot -> v_provider, '[]'::jsonb)) m
                 where m ->> 'id' = v_model) then
    raise exception 'Choose a model of this provider' using errcode = '22023';
  end if;
  v_exists := exists (select 1 from public.org_integrations where org_id = v_org and kind = v_kind);
  if v_key is null and not v_exists then
    raise exception 'Enter the API key' using errcode = '22023';
  end if;
  if v_key is not null then
    if char_length(v_key) not between 20 and 300 or v_key ~ '\s'
       or (v_provider = 'anthropic' and v_key !~ '^sk-ant-')
       or (v_provider = 'openai' and v_key !~ '^sk-')
       or (v_provider = 'google' and v_key !~ '^AIza') then
      raise exception 'This does not look like a % key', v_provider using errcode = '22023';
    end if;
  end if;
  if v_exists then
    update public.org_integrations
       set provider = v_provider, model = v_model, enabled = true,
           secret_enc = coalesce(private.encrypt_secret(v_key), secret_enc),
           secret_last4 = coalesce(right(v_key, 4), secret_last4),
           -- A new key or provider must be tested again.
           test_status = case when v_key is not null or provider <> v_provider then null else test_status end,
           tested_at = case when v_key is not null or provider <> v_provider then null else tested_at end
     where org_id = v_org and kind = v_kind;
  else
    insert into public.org_integrations (org_id, kind, provider, model, secret_enc, secret_last4)
    values (v_org, v_kind, v_provider, v_model, private.encrypt_secret(v_key), right(v_key, 4));
  end if;
  perform private.write_audit(v_org, 'assistant.key_saved', 'org_integrations', null, null,
                              jsonb_build_object('slot', v_slot, 'provider', v_provider, 'model', v_model, 'new_key', v_key is not null));
end;
$$;

create or replace function public.record_assistant_key_test(p_slot text, p_ok boolean, p_message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('assistant.manage');
  update public.org_integrations
     set tested_at = now(), test_status = case when p_ok then 'ok' else 'failed' end, test_message = left(nullif(btrim(p_message), ''), 300)
   where org_id = private.current_org_id() and kind = case p_slot when 'chat' then 'assistant_chat' else 'assistant_embed' end;
end;
$$;

create or replace function public.remove_assistant_key(p_slot text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('assistant.manage');
  delete from public.org_integrations where org_id = v_org and kind = case p_slot when 'chat' then 'assistant_chat' else 'assistant_embed' end;
  perform private.write_audit(v_org, 'assistant.key_removed', 'org_integrations', null, null, jsonb_build_object('slot', p_slot));
end;
$$;

-- Returns the ids of resources that must be processed again (chunk size or overlap changed).
create or replace function public.save_assistant_hyper(p jsonb)
returns uuid[]
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_new   jsonb := private.validate_assistant_hyper(p);
  v_old   jsonb;
  v_ids   uuid[] := '{}';
begin
  perform private.require_permission('assistant.manage');
  perform private.seed_assistant_defaults(v_org);
  select hyper into v_old from public.assistant_settings where org_id = v_org for update;
  update public.assistant_settings set hyper = v_new where org_id = v_org;
  if (v_old ->> 'chunk_size') is distinct from (v_new ->> 'chunk_size') or (v_old ->> 'chunk_overlap') is distinct from (v_new ->> 'chunk_overlap') then
    with redo as (
      update public.assistant_resources set status = 'processing', processed_through = 0
       where org_id = v_org and status = 'ready' and kind <> 'json'
      returning id)
    select coalesce(array_agg(id), '{}') into v_ids from redo;
  end if;
  return v_ids;
end;
$$;

-- p: {roles: [{role_id, enabled, daily_limit, ticks: {topic_key: bool}}]}
create or replace function public.save_assistant_role_matrix(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_admin boolean := private.is_org_admin();
  x       jsonb;
  r       public.roles;
  t       public.assistant_topics;
  v_want  boolean;
  v_old   boolean;
  v_limit integer;
begin
  perform private.require_permission('assistant.manage');
  perform private.seed_assistant_defaults(v_org);
  for x in select * from jsonb_array_elements(coalesce(p -> 'roles', '[]'::jsonb)) loop
    select * into r from public.roles where id = (x ->> 'role_id')::uuid and org_id = v_org;
    if not found then
      raise exception 'Role not found' using errcode = 'P0002';
    end if;
    -- Admin always has everything.
    continue when r.system_key = 'admin';
    v_limit := nullif(x ->> 'daily_limit', '')::integer;
    if v_limit is not null and v_limit not between 1 and 500 then
      raise exception 'Questions per day must be 1 to 500 (empty = no limit)' using errcode = '22023';
    end if;
    update public.assistant_role_settings
       set enabled = coalesce((x ->> 'enabled')::boolean, enabled), daily_limit = case when x ? 'daily_limit' then v_limit else daily_limit end
     where role_id = r.id;
    for t in select * from public.assistant_topics loop
      continue when not coalesce((x -> 'ticks') ? t.key, false);
      v_want := (x -> 'ticks' ->> t.key)::boolean and private.role_can_use_topic(r.id, t);
      select allowed into v_old from public.assistant_role_topics where role_id = r.id and topic_key = t.key;
      continue when v_want is not distinct from v_old;
      if t.is_sensitive and r.system_key = 'hr_manager' and not v_admin then
        raise exception 'Only an Admin can change "%" for HR Manager', t.label using errcode = '42501';
      end if;
      insert into public.assistant_role_topics (role_id, org_id, topic_key, allowed) values (r.id, v_org, t.key, v_want)
      on conflict (role_id, topic_key) do update set allowed = excluded.allowed;
    end loop;
  end loop;
end;
$$;

create or replace function public.save_assistant_role_messages(p_role_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_sugg text[] := array(select btrim(s) from jsonb_array_elements_text(coalesce(p -> 'suggestions', '[]'::jsonb)) s where btrim(s) <> '');
begin
  perform private.require_permission('assistant.manage');
  if not exists (select 1 from public.roles where id = p_role_id and org_id = v_org) then
    raise exception 'Role not found' using errcode = 'P0002';
  end if;
  if cardinality(v_sugg) > 6 then
    raise exception 'At most 6 suggested questions' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'greeting'), '')) < 2 or char_length(coalesce(btrim(p ->> 'not_allowed'), '')) < 2 then
    raise exception 'The greeting and the "not allowed" reply are needed' using errcode = '22023';
  end if;
  perform private.seed_assistant_defaults(v_org);
  update public.assistant_role_settings
     set greeting = left(btrim(p ->> 'greeting'), 240), suggestions = v_sugg, notice = left(coalesce(btrim(p ->> 'notice'), ''), 160),
         not_allowed_message = left(btrim(p ->> 'not_allowed'), 240)
   where role_id = p_role_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Service (Edge Function, service role only)
-- -----------------------------------------------------------------------------
create or replace function public.service_assistant_keys(p_org_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e record;
begin
  select * into e from private.assistant_embed_source(p_org_id);
  return jsonb_build_object(
    'chat', (select jsonb_build_object('provider', i.provider, 'model', i.model, 'api_key', private.decrypt_secret(i.secret_enc))
             from public.org_integrations i where i.org_id = p_org_id and i.kind = 'assistant_chat' and i.secret_enc is not null),
    'embed', (select jsonb_build_object('provider', e.provider, 'model', e.model, 'api_key', private.decrypt_secret(i.secret_enc))
              from public.org_integrations i where i.org_id = p_org_id and i.kind = e.kind and i.secret_enc is not null));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.assistant_settings       enable row level security;
alter table public.assistant_topics         enable row level security;
alter table public.assistant_role_settings  enable row level security;
alter table public.assistant_role_topics    enable row level security;
alter table public.assistant_resources      enable row level security;
alter table public.assistant_guide_articles enable row level security;
alter table public.assistant_chunks         enable row level security;
alter table public.assistant_conversations  enable row level security;
alter table public.assistant_messages       enable row level security;
alter table public.assistant_query_log      enable row level security;
revoke all on table public.assistant_settings, public.assistant_topics, public.assistant_role_settings, public.assistant_role_topics,
  public.assistant_resources, public.assistant_guide_articles, public.assistant_chunks, public.assistant_conversations,
  public.assistant_messages, public.assistant_query_log from anon, authenticated;

revoke all on function
  public.get_assistant_setup(), public.save_assistant_settings(jsonb), public.set_assistant_delegation(boolean),
  public.save_assistant_key(jsonb), public.record_assistant_key_test(text, boolean, text), public.remove_assistant_key(text),
  public.save_assistant_hyper(jsonb), public.save_assistant_role_matrix(jsonb), public.save_assistant_role_messages(uuid, jsonb),
  public.service_assistant_keys(uuid)
from public, anon;
grant execute on function
  public.get_assistant_setup(), public.save_assistant_settings(jsonb), public.set_assistant_delegation(boolean),
  public.save_assistant_key(jsonb), public.record_assistant_key_test(text, boolean, text), public.remove_assistant_key(text),
  public.save_assistant_hyper(jsonb), public.save_assistant_role_matrix(jsonb), public.save_assistant_role_messages(uuid, jsonb)
to authenticated;
revoke all on function public.service_assistant_keys(uuid) from authenticated;
grant execute on function public.service_assistant_keys(uuid) to service_role;

revoke all on function
  private.assistant_manage_guard(), private.assistant_models(), private.assistant_default_topics(text),
  private.seed_assistant_defaults(uuid), private.role_has_permission(uuid, text),
  private.role_can_use_topic(uuid, public.assistant_topics), private.assistant_allowed_topics(uuid),
  private.validate_assistant_hyper(jsonb), private.assistant_embed_source(uuid), private.assistant_key_json(uuid, text)
from public, anon, authenticated;
