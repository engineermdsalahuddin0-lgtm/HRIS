-- =============================================================================
-- Onboarding process R3: CV reading, must-have gate, ATS score, shortlist,
-- question bank and per-post question papers, AI settings.
-- Module handbook: src/onboarding-process/architecture.md (sections 2, 5-9).
--
-- CV reading has two modes (company setting, a post can override):
--   ai    : the Edge Function recruit-ai sends the CV to Claude with the
--           company's own API key and saves the extracted facts;
--   basic : no AI. The Edge Function turns the PDF / DOCX into markdown and
--           the database finds skills by keyword, estimates years from date
--           ranges and the education level from degree names.
-- AI mode falls back to basic when no key is set or the call fails.
-- The ATS score and the must-have gate are computed here, from the same pure
-- function in both modes (mirrored in src/onboarding-process/core/ats.ts).
-- Nobody is rejected automatically: HR shortlists or screens out.
--
-- Question bank per designation; each post gets its own papers (objective,
-- written or both) copied from the bank and editable; saving can update the
-- bank for next time. Papers lock when a test starts (R4).
--
-- Who: Admin and HR Manager (recruit.manage) everything; Manager
-- (recruit.department) sees the posts and applicants of the own department and
-- sets their question papers; employees nothing. The AI key: Admin only,
-- write-only, stored encrypted; only the Edge Function (service role) reads it.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.job_posts') is null then
    raise exception 'Apply 20261026000100_recruit_r2_job_posts.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('recruit.department', 'recruitment', 'See job posts and applicants of the own department and set their question papers', false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.recruit_settings (
  org_id     uuid primary key references public.organizations (id),
  cv_mode    text not null default 'basic' check (cv_mode in ('basic', 'ai')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id)
);
select private.attach_standard_triggers('public.recruit_settings');

alter table public.job_posts add column cv_mode text check (cv_mode is null or cv_mode in ('basic', 'ai'));

-- The company's own AI key. Never audited by the row trigger (the RPCs log the event without the key).
create table public.org_integrations (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations (id),
  kind          text not null check (kind in ('ai')),
  provider      text not null default 'anthropic' check (provider in ('anthropic')),
  enabled       boolean not null default true,
  model         text not null default 'claude-opus-5-5'
                check (model in ('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5')),
  secret_enc    bytea,
  secret_last4  text,
  tested_at     timestamptz,
  test_status   text check (test_status is null or test_status in ('ok', 'failed')),
  test_message  text check (test_message is null or char_length(test_message) <= 300),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint org_integrations_kind_uq unique (org_id, kind)
);
create trigger set_row_meta before insert or update on public.org_integrations
  for each row execute function private.set_row_meta();

-- What was read from a CV and the resulting score. Holds personal data: no row audit,
-- the RPCs log ids, score and gate only. Removed by the purge (R7).
create table public.applicant_profiles (
  applicant_id       uuid primary key,
  org_id             uuid not null,
  job_post_id        uuid not null,
  status             text not null default 'reading' check (status in ('reading', 'done', 'failed')),
  mode_used          text check (mode_used in ('ai', 'basic', 'manual')),
  markdown           text check (markdown is null or char_length(markdown) <= 200000),
  summary            text check (summary is null or char_length(summary) <= 2000),
  years              numeric(4, 1),
  years_source       text check (years_source in ('ai', 'estimate', 'hr')),
  education_level    text check (education_level in ('ssc', 'hsc', 'diploma', 'bachelor', 'masters', 'phd')),
  education_source   text check (education_source in ('ai', 'estimate', 'hr')),
  skills_found       text[] not null default '{}',
  matched_required   text[] not null default '{}',
  matched_nice       text[] not null default '{}',
  subject_matched    boolean not null default false,
  relevance          numeric(4, 1) check (relevance is null or relevance between 0 and 15),
  relevance_reason   text check (relevance_reason is null or char_length(relevance_reason) <= 500),
  relevance_source   text check (relevance_source in ('ai', 'hr')),
  figures            jsonb,
  ats_score          numeric(5, 1),
  gate               text check (gate in ('pass', 'fail', 'review')),
  ai_model           text,
  ai_error           text check (ai_error is null or char_length(ai_error) <= 500),
  error              text check (error is null or char_length(error) <= 500),
  claimed_at         timestamptz,
  read_at            timestamptz,
  updated_at         timestamptz not null default now(),
  updated_by         uuid references public.user_profiles (id),
  constraint applicant_profiles_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint applicant_profiles_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id)
);
create index applicant_profiles_post_idx on public.applicant_profiles (job_post_id);

create table public.applicant_decisions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  applicant_id  uuid not null,
  from_status   text not null,
  to_status     text not null,
  gate          text,
  note          text check (note is null or char_length(note) <= 500),
  actor_user_id uuid references public.user_profiles (id) default auth.uid(),
  created_at    timestamptz not null default now(),
  constraint applicant_decisions_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id)
);
create trigger applicant_decisions_append_only before update or delete on public.applicant_decisions
  for each row execute function private.history_append_only();

-- Question bank: the questions a designation's posts start from.
create table public.question_bank (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  designation_id uuid not null,
  kind           text not null check (kind in ('objective', 'written')),
  position       integer not null,
  section        text not null check (section in ('aptitude', 'job_knowledge', 'language', 'situational', 'general')),
  stem           text not null check (char_length(stem) between 3 and 2000),
  options        jsonb,
  correct_index  smallint,
  model_answer   text check (model_answer is null or char_length(model_answer) <= 4000),
  marks          numeric(5, 2) not null check (marks between 0.25 and 100),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint question_bank_designation_fk foreign key (org_id, designation_id) references public.designations (org_id, id)
);
create index question_bank_designation_idx on public.question_bank (designation_id, kind, position);
create trigger set_row_meta before insert or update on public.question_bank
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.question_bank
  for each row execute function private.audit_row_change();

create table public.question_papers (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  job_post_id      uuid not null,
  kind             text not null check (kind in ('objective', 'written')),
  duration_minutes smallint check (duration_minutes is null or duration_minutes between 5 and 300),
  pass_percent     numeric(5, 2) check (pass_percent is null or pass_percent between 0 and 100),
  total_marks      numeric(7, 2) not null default 0,
  question_count   integer not null default 0,
  version          integer not null default 1,
  locked_at        timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint question_papers_org_id_id_uq unique (org_id, id),
  constraint question_papers_post_kind_uq unique (job_post_id, kind),
  constraint question_papers_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id)
);
create trigger set_row_meta before insert or update on public.question_papers
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.question_papers
  for each row execute function private.audit_row_change();

create table public.paper_questions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  paper_id      uuid not null,
  position      integer not null,
  section       text not null check (section in ('aptitude', 'job_knowledge', 'language', 'situational', 'general')),
  stem          text not null check (char_length(stem) between 3 and 2000),
  options       jsonb,
  correct_index smallint,
  model_answer  text check (model_answer is null or char_length(model_answer) <= 4000),
  marks         numeric(5, 2) not null check (marks between 0.25 and 100),
  constraint paper_questions_paper_fk foreign key (org_id, paper_id) references public.question_papers (org_id, id)
);
create index paper_questions_paper_idx on public.paper_questions (paper_id, position);

-- -----------------------------------------------------------------------------
-- Defaults
-- -----------------------------------------------------------------------------
create or replace function private.seed_recruit_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.recruit_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['recruit.manage']
    when 'manager'    then array['recruit.department']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;
end;
$$;

select private.seed_recruit_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Pure calculation: must-have gate and ATS score (mirror: core/ats.ts)
-- p: req_total, req_matched, nice_total, nice_matched, min_years, years (null = unknown),
--    required_level, applicant_level (null = unknown), subjects_required, subject_matched,
--    relevance (null = not set)
-- -----------------------------------------------------------------------------
create or replace function private.education_rank(p_level text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_level when 'ssc' then 1 when 'hsc' then 2 when 'diploma' then 3 when 'bachelor' then 4
                      when 'masters' then 5 when 'phd' then 6 when 'any' then 0 end
$$;

create or replace function private.ats_figures(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_req_total    integer := coalesce((p ->> 'req_total')::integer, 0);
  v_req_matched  integer := coalesce((p ->> 'req_matched')::integer, 0);
  v_nice_total   integer := coalesce((p ->> 'nice_total')::integer, 0);
  v_nice_matched integer := coalesce((p ->> 'nice_matched')::integer, 0);
  v_min          numeric := coalesce((p ->> 'min_years')::numeric, 0);
  v_years        numeric := (p ->> 'years')::numeric;
  v_required     text := coalesce(p ->> 'required_level', 'any');
  v_level        text := p ->> 'applicant_level';
  v_subjects     integer := coalesce((p ->> 'subjects_required')::integer, 0);
  v_subject_ok   boolean := coalesce((p ->> 'subject_matched')::boolean, false);
  v_relevance    numeric := (p ->> 'relevance')::numeric;
  v_skills       numeric;
  v_exp          numeric;
  v_edu          numeric;
  v_max          integer;
  v_exp_ok       boolean;
  v_edu_ok       boolean;
  v_gate         text;
  v_reasons      text[] := '{}';
begin
  v_skills := least(40, round(case when v_req_total > 0 then 40.0 * v_req_matched / v_req_total else 40 end, 2)
                        + round(case when v_nice_total > 0 then 5.0 * v_nice_matched / v_nice_total else 0 end, 2));
  v_exp := case when v_min = 0 then 25
                when v_years is null then 0
                when v_years >= v_min then 25
                else round(25 * v_years / v_min, 2) end;
  v_edu := case when v_required = 'any' then 20
                when v_level is null then 0
                when private.education_rank(v_level) >= private.education_rank(v_required)
                  then 15 + case when v_subjects = 0 or v_subject_ok then 5 else 0 end
                else 0 end;
  v_max := case when v_relevance is null then 85 else 100 end;

  v_exp_ok := case when v_min = 0 then true when v_years is null then null else v_years >= v_min end;
  v_edu_ok := case when v_required = 'any' then true when v_level is null then null
                   else private.education_rank(v_level) >= private.education_rank(v_required) end;
  if v_exp_ok is false then v_reasons := v_reasons || 'experience_below_minimum'::text; end if;
  if v_exp_ok is null then v_reasons := v_reasons || 'experience_unknown'::text; end if;
  if v_edu_ok is false then v_reasons := v_reasons || 'education_below_required'::text; end if;
  if v_edu_ok is null then v_reasons := v_reasons || 'education_unknown'::text; end if;
  v_gate := case when v_exp_ok is false or v_edu_ok is false then 'fail'
                 when v_exp_ok is null or v_edu_ok is null then 'review'
                 else 'pass' end;

  return jsonb_build_object(
    'skills', v_skills, 'experience', v_exp, 'education', v_edu, 'relevance', v_relevance,
    'max', v_max, 'score', round((v_skills + v_exp + v_edu + coalesce(v_relevance, 0)) / v_max * 100, 1),
    'experience_ok', v_exp_ok, 'education_ok', v_edu_ok, 'gate', v_gate, 'reasons', to_jsonb(v_reasons),
    'req_total', v_req_total, 'req_matched', v_req_matched, 'nice_total', v_nice_total, 'nice_matched', v_nice_matched,
    'min_years', v_min, 'years', v_years, 'required_level', v_required, 'applicant_level', v_level,
    'subjects_required', v_subjects, 'subject_matched', v_subject_ok);
end;
$$;

-- -----------------------------------------------------------------------------
-- Basic mode: reading facts from CV markdown without AI (rough; HR can correct)
-- -----------------------------------------------------------------------------
-- Does the text contain the term as a whole word / phrase (case-insensitive)?
create or replace function private.text_has_term(p_text text, p_term text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(btrim(p_term), '') <> '' and lower(coalesce(p_text, '')) ~
    ('(^|[^a-z0-9])' || regexp_replace(lower(btrim(p_term)), '([.\\+*?\[\]^$(){}=!<>|:#/-])', '\\\1', 'g') || '($|[^a-z0-9])')
$$;

-- Highest degree named in the text.
create or replace function private.detect_education(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when t ~ '(^|[^a-z])(ph\.?\s?d|doctorate)([^a-z]|$)' then 'phd'
    when t ~ '(^|[^a-z])(master|masters|m\.?\s?sc|m\.?\s?b\.?\s?a|m\.?\s?com|m\.?\s?s\.?\s?s|m\.?\s?a\.?|ll\.?\s?m)([^a-z]|$)' then 'masters'
    when t ~ '(^|[^a-z])(bachelor|bachelors|b\.?\s?sc|b\.?\s?b\.?\s?a|b\.?\s?com|b\.?\s?s\.?\s?s|b\.?\s?a\.?|honours|hons|ll\.?\s?b|b\.?\s?tech)([^a-z]|$)' then 'bachelor'
    when t ~ '(^|[^a-z])diploma([^a-z]|$)' then 'diploma'
    when t ~ '(^|[^a-z])(hsc|h\.s\.c|higher secondary|a[ -]level)([^a-z]|$)' then 'hsc'
    when t ~ '(^|[^a-z])(ssc|s\.s\.c|secondary school|o[ -]level|dakhil)([^a-z]|$)' then 'ssc'
  end
  from (select lower(coalesce(p_text, '')) as t) x
$$;

-- Years of work from date ranges ("2019 - 2022", "Jan 2022 – Present"), merged where they
-- overlap. Lines about education are skipped. No range: "N years of experience". Else null.
create or replace function private.estimate_years(p_text text, p_today date)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_line   text;
  v_match  text[];
  v_ranges int4range[] := '{}';
  v_merged int4range;
  v_total  integer := 0;
  v_r      int4range;
  v_start  integer;
  v_end    integer;
  v_now    integer := extract(year from p_today)::integer;
begin
  for v_line in select l from regexp_split_to_table(lower(coalesce(p_text, '')), E'\n') l loop
    continue when v_line ~ '(university|college|school|institute|madrasah|degree|bachelor|master|b\.?\s?sc|b\.?\s?b\.?\s?a|m\.?\s?b\.?\s?a|honours|ssc|hsc|diploma|cgpa|gpa|passing year)';
    for v_match in
      select regexp_matches(v_line,
        '((?:19|20)[0-9]{2})\s*(?:-|–|—|to|till|until)\s*(?:[a-z]{3,9}\.?,?\s+)?((?:19|20)[0-9]{2}|present|current|now|date|continuing|running)', 'g')
    loop
      v_start := v_match[1]::integer;
      v_end := case when v_match[2] ~ '^[0-9]{4}$' then v_match[2]::integer else v_now end;
      continue when v_start > v_now or v_end <= v_start or v_end > v_now + 1;
      v_ranges := v_ranges || int4range(v_start, v_end, '[)');
    end loop;
  end loop;

  if cardinality(v_ranges) > 0 then
    for v_r in select r from unnest(v_ranges) r order by lower(r) loop
      if v_merged is null then
        v_merged := v_r;
      elsif v_r && v_merged or v_r -|- v_merged then
        v_merged := v_merged + v_r;
      else
        v_total := v_total + (upper(v_merged) - lower(v_merged));
        v_merged := v_r;
      end if;
    end loop;
    v_total := v_total + coalesce(upper(v_merged) - lower(v_merged), 0);
    return least(v_total, 50);
  end if;

  v_match := regexp_match(lower(coalesce(p_text, '')), '([0-9]{1,2}(?:\.[0-9])?)\+?\s*(?:years?|yrs?)\s+(?:of\s+)?(?:work\s+|professional\s+|job\s+)?experience');
  if v_match is not null then
    return least(v_match[1]::numeric, 50);
  end if;
  return null;
end;
$$;

-- Builds the profile row's derived fields and score from the facts it has.
create or replace function private.score_applicant_profile(p_applicant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row     public.applicant_profiles;
  v_profile jsonb;
  v_req     text[];
  v_nice    text[];
  v_subj    text[];
  v_found   text[];
  v_mreq    text[];
  v_mnice   text[];
  v_subj_ok boolean;
  v_fig     jsonb;
begin
  select * into v_row from public.applicant_profiles where applicant_id = p_applicant_id for update;
  select jp.profile into v_profile from public.job_posts jp where jp.id = v_row.job_post_id;
  v_req  := array(select jsonb_array_elements_text(coalesce(v_profile -> 'required_skills', '[]')));
  v_nice := array(select jsonb_array_elements_text(coalesce(v_profile -> 'nice_skills', '[]')));
  v_subj := array(select jsonb_array_elements_text(coalesce(v_profile -> 'education_subjects', '[]')));
  v_found := v_row.skills_found;

  -- HR-set matches are kept as they are; otherwise a skill matches when the AI listed it
  -- or the CV text names it.
  if v_row.mode_used = 'manual' then
    v_mreq := array(select s from unnest(v_req) s where lower(s) = any (select lower(x) from unnest(v_row.matched_required) x));
    v_mnice := array(select s from unnest(v_nice) s where lower(s) = any (select lower(x) from unnest(v_row.matched_nice) x));
    v_subj_ok := v_row.subject_matched;
  else
    v_mreq := array(select s from unnest(v_req) s
                    where private.text_has_term(v_row.markdown, s)
                       or exists (select 1 from unnest(v_found) f where private.text_has_term(f, s) or private.text_has_term(s, f)));
    v_mnice := array(select s from unnest(v_nice) s
                     where private.text_has_term(v_row.markdown, s)
                        or exists (select 1 from unnest(v_found) f where private.text_has_term(f, s) or private.text_has_term(s, f)));
    v_subj_ok := exists (select 1 from unnest(v_subj) s where private.text_has_term(v_row.markdown, s)
                         or private.text_has_term(v_row.summary, s));
  end if;

  v_fig := private.ats_figures(jsonb_build_object(
    'req_total', cardinality(v_req), 'req_matched', cardinality(v_mreq),
    'nice_total', cardinality(v_nice), 'nice_matched', cardinality(v_mnice),
    'min_years', coalesce((v_profile ->> 'experience_min_years')::numeric, 0), 'years', v_row.years,
    'required_level', coalesce(v_profile ->> 'education_level', 'any'), 'applicant_level', v_row.education_level,
    'subjects_required', cardinality(v_subj), 'subject_matched', v_subj_ok, 'relevance', v_row.relevance));

  update public.applicant_profiles
     set matched_required = v_mreq, matched_nice = v_mnice, subject_matched = v_subj_ok, figures = v_fig,
         ats_score = (v_fig ->> 'score')::numeric, gate = v_fig ->> 'gate', updated_at = now(), updated_by = auth.uid()
   where applicant_id = p_applicant_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Scope helpers: HR / Admin everything, Manager own department
-- -----------------------------------------------------------------------------
create or replace function private.recruit_scope(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('recruit.manage')
      or (private.has_permission('recruit.department')
          and p_department_id is not distinct from
              (select e.department_id from public.employees e where e.id = private.current_employee_id()))
$$;

-- The post if the caller may see it; raises otherwise.
create or replace function private.recruit_post(p_job_post_id uuid)
returns public.job_posts
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts;
begin
  if not (private.has_permission('recruit.manage') or private.has_permission('recruit.department')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if not private.recruit_scope(v_post.department_id) then
    raise exception 'This job post belongs to another department' using errcode = '42501';
  end if;
  return v_post;
end;
$$;

create or replace function private.post_cv_mode(p_post public.job_posts)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(p_post.cv_mode, (select s.cv_mode from public.recruit_settings s where s.org_id = p_post.org_id), 'basic')
$$;

create or replace function private.ai_ready(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.org_integrations i
                 where i.org_id = p_org_id and i.kind = 'ai' and i.enabled and i.secret_enc is not null)
$$;

-- -----------------------------------------------------------------------------
-- API: settings and the AI key
-- -----------------------------------------------------------------------------
create or replace function public.get_recruit_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  perform private.require_permission('recruit.manage');
  return jsonb_build_object(
    'cv_mode', coalesce((select s.cv_mode from public.recruit_settings s where s.org_id = v_org_id), 'basic'),
    'is_admin', private.is_org_admin(),
    'ai', (select jsonb_build_object('configured', i.secret_enc is not null, 'enabled', i.enabled, 'model', i.model,
                                     'last4', i.secret_last4, 'tested_at', i.tested_at, 'test_status', i.test_status,
                                     'test_message', i.test_message, 'updated_at', i.updated_at)
           from public.org_integrations i where i.org_id = v_org_id and i.kind = 'ai'));
end;
$$;

create or replace function public.save_recruit_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_mode   text := coalesce(p ->> 'cv_mode', 'basic');
begin
  perform private.require_permission('recruit.manage');
  if v_mode not in ('basic', 'ai') then
    raise exception 'CV reading is basic or ai' using errcode = '22023';
  end if;
  insert into public.recruit_settings (org_id, cv_mode) values (v_org_id, v_mode)
  on conflict (org_id) do update set cv_mode = excluded.cv_mode;
end;
$$;

-- p: api_key (optional, write-only), model, enabled. Admin only.
create or replace function public.save_ai_integration(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_key    text := nullif(btrim(coalesce(p ->> 'api_key', '')), '');
  v_model  text := coalesce(p ->> 'model', 'claude-opus-5-5');
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can change the AI key' using errcode = '42501';
  end if;
  if v_key is not null and (v_key !~ '^sk-ant-[A-Za-z0-9_-]+$' or char_length(v_key) not between 20 and 300) then
    raise exception 'This does not look like an Anthropic API key (it starts with sk-ant-)' using errcode = '22023';
  end if;
  if v_model not in ('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5') then
    raise exception 'Unknown model' using errcode = '22023';
  end if;
  if v_key is null and not exists (select 1 from public.org_integrations where org_id = v_org_id and kind = 'ai' and secret_enc is not null) then
    raise exception 'Paste the API key' using errcode = '23502';
  end if;
  insert into public.org_integrations (org_id, kind, model, enabled, secret_enc, secret_last4)
  values (v_org_id, 'ai', v_model, coalesce((p ->> 'enabled')::boolean, true), private.encrypt_secret(v_key), right(v_key, 4))
  on conflict (org_id, kind) do update
    set model = excluded.model, enabled = excluded.enabled,
        secret_enc = coalesce(excluded.secret_enc, public.org_integrations.secret_enc),
        secret_last4 = coalesce(excluded.secret_last4, public.org_integrations.secret_last4),
        tested_at = case when excluded.secret_enc is not null then null else public.org_integrations.tested_at end,
        test_status = case when excluded.secret_enc is not null then null else public.org_integrations.test_status end;
  perform private.write_audit(v_org_id, 'integration.ai_saved', 'org_integrations', null, null,
                              jsonb_build_object('model', v_model, 'key_changed', v_key is not null));
end;
$$;

create or replace function public.remove_ai_integration()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can change the AI key' using errcode = '42501';
  end if;
  delete from public.org_integrations where org_id = v_org_id and kind = 'ai';
  perform private.write_audit(v_org_id, 'integration.ai_removed', 'org_integrations', null, null, null);
end;
$$;

-- The Edge Function asks this (as the user) before testing the key; returns the org.
create or replace function public.ai_test_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can test the AI key' using errcode = '42501';
  end if;
  return jsonb_build_object('org_id', private.current_org_id());
end;
$$;

create or replace function public.record_ai_test(p_ok boolean, p_message text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_org_admin() then
    raise exception 'Only the company Admin can test the AI key' using errcode = '42501';
  end if;
  update public.org_integrations
     set tested_at = now(), test_status = case when p_ok then 'ok' else 'failed' end,
         test_message = left(nullif(btrim(p_message), ''), 300)
   where org_id = private.current_org_id() and kind = 'ai';
end;
$$;

-- Service role only (the Edge Function): the decrypted key and model, or null.
create or replace function public.service_ai_key(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('api_key', private.decrypt_secret(i.secret_enc), 'model', i.model)
  from public.org_integrations i
  where i.org_id = p_org_id and i.kind = 'ai' and i.enabled and i.secret_enc is not null
$$;

create or replace function public.set_post_cv_mode(p_job_post_id uuid, p_mode text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('recruit.manage');
  if p_mode is not null and p_mode not in ('basic', 'ai') then
    raise exception 'CV reading is basic or ai' using errcode = '22023';
  end if;
  update public.job_posts set cv_mode = p_mode where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: reading CVs (called by the Edge Function with the user's login)
-- -----------------------------------------------------------------------------
-- Marks up to p_limit applicants with a CV that was not read yet (p_again: also failed and
-- earlier reads, except HR corrections) as being read and returns what the function needs.
-- A read stuck for 10 minutes is retried. p_since (with p_again): only rows claimed before it, so
-- a re-read that runs in rounds never takes the same CV twice.
create or replace function public.claim_cv_reads(p_job_post_id uuid, p_limit integer default 5, p_again boolean default false,
                                                 p_since timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts;
  v_mode text;
  v_ids  uuid[];
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  v_mode := private.post_cv_mode(v_post);

  select array_agg(a.id) into v_ids from (
    select a.id from public.applicants a
    left join public.applicant_profiles ap on ap.applicant_id = a.id
    where a.job_post_id = p_job_post_id and a.purged_at is null and a.cv_uploaded_at is not null
      and (ap.applicant_id is null
           or (ap.status = 'reading' and ap.claimed_at < now() - interval '10 minutes')
           or (p_again and coalesce(ap.claimed_at, '-infinity') < coalesce(p_since, now())
               and (ap.status = 'failed' or (ap.status = 'done' and ap.mode_used <> 'manual'))))
    order by a.created_at
    limit least(greatest(coalesce(p_limit, 5), 1), 20)
    for update of a skip locked) a;

  if v_ids is null then
    return jsonb_build_object('org_id', v_post.org_id, 'mode', v_mode, 'ai_ready', private.ai_ready(v_post.org_id),
                              'started_at', coalesce(p_since, now()), 'items', '[]'::jsonb);
  end if;

  insert into public.applicant_profiles (applicant_id, org_id, job_post_id, status, claimed_at)
  select id, v_post.org_id, p_job_post_id, 'reading', now() from unnest(v_ids) id
  on conflict (applicant_id) do update set status = 'reading', claimed_at = now(), error = null;

  return jsonb_build_object(
    'org_id', v_post.org_id, 'mode', v_mode, 'ai_ready', private.ai_ready(v_post.org_id),
    'started_at', coalesce(p_since, now()), 'job', jsonb_build_object('title', v_post.title, 'profile', v_post.profile),
    'items', (select jsonb_agg(jsonb_build_object('applicant_id', a.id, 'cv_path', a.cv_path)) from public.applicants a
              where a.id = any (v_ids)));
end;
$$;

-- p: markdown, mode_used (ai | basic), error (when nothing could be read),
--    ai_error (AI failed, basic used), ai_model,
--    ai {experience_known, total_experience_years, education_level, education_subjects[], skills[],
--        relevance, relevance_reason, summary}
create or replace function public.save_cv_read(p_applicant_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row     public.applicant_profiles;
  v_ai      jsonb := case when jsonb_typeof(p -> 'ai') = 'object' then p -> 'ai' end;
  v_mode    text := coalesce(p ->> 'mode_used', 'basic');
  v_md      text := left(coalesce(p ->> 'markdown', ''), 200000);
  v_today   date := private.org_today(private.current_org_id());
  v_level   text;
  v_years   numeric;
  v_rel     numeric;
begin
  perform private.require_permission('recruit.manage');
  select * into v_row from public.applicant_profiles
   where applicant_id = p_applicant_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Claim the CV before saving what was read' using errcode = 'P0002';
  end if;
  if v_mode not in ('ai', 'basic') then
    raise exception 'Mode is ai or basic' using errcode = '22023';
  end if;

  if nullif(btrim(p ->> 'error'), '') is not null then
    update public.applicant_profiles
       set status = 'failed', error = left(p ->> 'error', 500), ai_error = left(nullif(p ->> 'ai_error', ''), 500),
           markdown = nullif(v_md, ''), updated_at = now(), updated_by = auth.uid()
     where applicant_id = p_applicant_id;
    return jsonb_build_object('status', 'failed');
  end if;

  if v_mode = 'ai' and v_ai is not null then
    v_years := case when coalesce((v_ai ->> 'experience_known')::boolean, false)
                    then least(greatest(round((v_ai ->> 'total_experience_years')::numeric, 1), 0), 50) end;
    v_level := nullif(v_ai ->> 'education_level', 'unknown');
    if v_level is not null and v_level not in ('ssc', 'hsc', 'diploma', 'bachelor', 'masters', 'phd') then
      v_level := null;
    end if;
    v_rel := least(greatest(round((v_ai ->> 'relevance')::numeric, 1), 0), 15);
    update public.applicant_profiles
       set status = 'done', mode_used = 'ai', markdown = v_md, summary = left(nullif(v_ai ->> 'summary', ''), 2000),
           years = v_years, years_source = 'ai', education_level = v_level, education_source = 'ai',
           skills_found = private.text_list(v_ai -> 'skills', 'Skills', 80, 80),
           relevance = v_rel, relevance_reason = left(nullif(v_ai ->> 'relevance_reason', ''), 500),
           relevance_source = case when v_rel is null then null else 'ai' end,
           ai_model = left(p ->> 'ai_model', 60), ai_error = null, error = null, read_at = now()
     where applicant_id = p_applicant_id;
  else
    if char_length(btrim(v_md)) < 30 then
      update public.applicant_profiles
         set status = 'failed', markdown = nullif(v_md, ''), mode_used = 'basic', ai_error = left(nullif(p ->> 'ai_error', ''), 500),
             error = 'No text found in the CV (a scanned image?). Enter the details by hand.', updated_at = now(),
             updated_by = auth.uid()
       where applicant_id = p_applicant_id;
      return jsonb_build_object('status', 'failed');
    end if;
    update public.applicant_profiles
       set status = 'done', mode_used = 'basic', markdown = v_md, summary = null,
           years = private.estimate_years(v_md, v_today), years_source = 'estimate',
           education_level = private.detect_education(v_md), education_source = 'estimate',
           skills_found = '{}',
           -- An HR relevance mark survives a re-read; an old AI one does not.
           relevance = case when v_row.relevance_source = 'hr' then v_row.relevance end,
           relevance_reason = case when v_row.relevance_source = 'hr' then v_row.relevance_reason end,
           relevance_source = case when v_row.relevance_source = 'hr' then 'hr' end,
           ai_model = null, ai_error = left(nullif(p ->> 'ai_error', ''), 500), error = null, read_at = now()
     where applicant_id = p_applicant_id;
  end if;

  perform private.score_applicant_profile(p_applicant_id);
  select * into v_row from public.applicant_profiles where applicant_id = p_applicant_id;
  perform private.write_audit(v_row.org_id, 'applicant.cv_read', 'applicant_profiles', p_applicant_id, null,
                              jsonb_build_object('mode', v_row.mode_used, 'score', v_row.ats_score, 'gate', v_row.gate));
  return jsonb_build_object('status', 'done', 'ats_score', v_row.ats_score, 'gate', v_row.gate);
end;
$$;

-- HR corrects what was read. p: years, education_level, matched_required[], matched_nice[],
-- subject_matched, relevance (0-15 or null), relevance_reason.
create or replace function public.save_applicant_profile(p_applicant_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app   public.applicants;
  v_level text := nullif(p ->> 'education_level', '');
  v_years numeric := (private.jtext(p, 'years'))::numeric;
  v_rel   numeric := (private.jtext(p, 'relevance'))::numeric;
  v_row   public.applicant_profiles;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants
   where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  if v_level is not null and v_level not in ('ssc', 'hsc', 'diploma', 'bachelor', 'masters', 'phd') then
    raise exception 'Unknown education level' using errcode = '22023';
  end if;
  if v_years is not null and v_years not between 0 and 50 then
    raise exception 'Years of experience must be between 0 and 50' using errcode = '22023';
  end if;
  if v_rel is not null and v_rel not between 0 and 15 then
    raise exception 'Relevance is 0 to 15' using errcode = '22023';
  end if;

  insert into public.applicant_profiles (applicant_id, org_id, job_post_id, status)
  values (v_app.id, v_app.org_id, v_app.job_post_id, 'done')
  on conflict (applicant_id) do nothing;
  update public.applicant_profiles
     set status = 'done', mode_used = 'manual', years = v_years, years_source = 'hr',
         education_level = v_level, education_source = 'hr',
         matched_required = private.text_list(p -> 'matched_required', 'Matched skills', 40, 80),
         matched_nice = private.text_list(p -> 'matched_nice', 'Matched nice-to-have skills', 40, 80),
         subject_matched = coalesce((p ->> 'subject_matched')::boolean, false),
         relevance = v_rel, relevance_reason = left(nullif(btrim(p ->> 'relevance_reason'), ''), 500),
         relevance_source = case when v_rel is null then null else 'hr' end, error = null
   where applicant_id = p_applicant_id;
  perform private.score_applicant_profile(p_applicant_id);
  select * into v_row from public.applicant_profiles where applicant_id = p_applicant_id;
  perform private.write_audit(v_row.org_id, 'applicant.profile_corrected', 'applicant_profiles', p_applicant_id, null,
                              jsonb_build_object('score', v_row.ats_score, 'gate', v_row.gate));
  return jsonb_build_object('ats_score', v_row.ats_score, 'gate', v_row.gate);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: shortlist / screen out (HR and Admin)
-- -----------------------------------------------------------------------------
-- p_to: shortlisted | screened_out | applied (undo). Shortlisting someone who did not pass
-- the must-have gate needs a reason; screening out always needs one.
create or replace function public.move_applicants(p_job_post_id uuid, p_ids uuid[], p_to text, p_note text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_app   record;
  v_count integer := 0;
begin
  perform private.require_permission('recruit.manage');
  if not exists (select 1 from public.job_posts where id = p_job_post_id and org_id = private.current_org_id()) then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if p_to not in ('shortlisted', 'screened_out', 'applied') then
    raise exception 'Move to shortlisted, screened out or back to applied' using errcode = '22023';
  end if;
  if p_to = 'screened_out' and char_length(coalesce(v_note, '')) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  if coalesce(cardinality(p_ids), 0) = 0 then
    raise exception 'Pick at least one applicant' using errcode = '22023';
  end if;

  for v_app in
    select a.id, a.status, ap.gate from public.applicants a
    left join public.applicant_profiles ap on ap.applicant_id = a.id
    where a.id = any (p_ids) and a.job_post_id = p_job_post_id and a.purged_at is null
    for update of a
  loop
    if not ((p_to = 'shortlisted' and v_app.status = 'applied')
            or (p_to = 'screened_out' and v_app.status in ('applied', 'shortlisted'))
            or (p_to = 'applied' and v_app.status in ('shortlisted', 'screened_out'))) then
      raise exception 'An applicant who is % cannot be moved to %', v_app.status, p_to using errcode = '22023';
    end if;
    if p_to = 'shortlisted' and coalesce(v_app.gate, 'review') <> 'pass' and char_length(coalesce(v_note, '')) < 5 then
      raise exception 'Some applicants did not pass the must-have check; give a reason to shortlist them' using errcode = '23502';
    end if;
    update public.applicants set status = p_to where id = v_app.id;
    insert into public.applicant_decisions (org_id, applicant_id, from_status, to_status, gate, note)
    select a.org_id, a.id, v_app.status, p_to, v_app.gate, left(v_note, 500) from public.applicants a where a.id = v_app.id;
    perform private.applicant_event(v_app.id, 'moved_' || p_to, v_app.status, p_to);
    v_count := v_count + 1;
  end loop;
  if v_count <> cardinality(p_ids) then
    raise exception 'Some applicants were not found in this job post' using errcode = 'P0002';
  end if;
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: R2 readers, now also for Managers (own department) and with screening data
-- -----------------------------------------------------------------------------
create or replace function public.list_job_posts()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_manage boolean := private.has_permission('recruit.manage');
begin
  if not (v_manage or private.has_permission('recruit.department')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'org_code', (select o.org_code from public.organizations o where o.id = v_org_id),
    'can', jsonb_build_object('manage', v_manage),
    'posts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', jp.id, 'vacancy_id', jp.vacancy_id, 'title', jp.title, 'status', jp.status, 'deadline', jp.deadline,
        'public_slug', jp.public_slug, 'department_name', d.name, 'designation_name', ds.name, 'seats', jp.seats,
        'show_salary', jp.show_salary, 'salary_min', jp.salary_min, 'salary_max', jp.salary_max,
        'published_at', jp.published_at, 'created_at', jp.created_at,
        'applicants', (select count(*) from public.applicants a where a.job_post_id = jp.id and a.purged_at is null),
        'with_cv', (select count(*) from public.applicants a
                    where a.job_post_id = jp.id and a.purged_at is null and a.cv_uploaded_at is not null),
        'shortlisted', (select count(*) from public.applicants a
                        where a.job_post_id = jp.id and a.purged_at is null and a.status = 'shortlisted'))
        order by jp.created_at desc)
      from public.job_posts jp
      join public.departments d on d.id = jp.department_id
      join public.designations ds on ds.id = jp.designation_id
      where jp.org_id = v_org_id and private.recruit_scope(jp.department_id)), '[]'::jsonb),
    'ready', case when v_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'vacancy_id', v.id, 'department_name', d.name, 'designation_id', ds.id, 'designation_name', ds.name,
        'grade_code', g.code, 'seats', v.seats, 'reason', v.reason, 'decided_at', v.decided_at,
        'has_profile', exists (select 1 from public.job_profiles p where p.designation_id = v.designation_id))
        order by v.decided_at)
      from public.vacancies v
      join public.departments d on d.id = v.department_id
      join public.designations ds on ds.id = v.designation_id
      join public.grades g on g.id = ds.grade_id
      where v.org_id = v_org_id and v.status = 'approved'
        and not exists (select 1 from public.job_posts jp where jp.vacancy_id = v.id)), '[]'::jsonb)
      else '[]'::jsonb end);
end;
$$;

create or replace function public.get_job_post(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_id);
  v_out  jsonb;
begin
  select to_jsonb(jp) - array['org_id', 'created_by', 'updated_by']
         || jsonb_build_object(
              'department_name', d.name, 'designation_name', ds.name, 'grade_code', g.code,
              'org_code', o.org_code, 'org_name', o.name,
              'vacancy_status', v.status, 'vacancy_reason', v.reason,
              'profile_current_version', (select p.version from public.job_profiles p where p.designation_id = jp.designation_id),
              'today', private.org_today(jp.org_id),
              'cv_mode_effective', private.post_cv_mode(jp), 'ai_ready', private.ai_ready(jp.org_id),
              'can', jsonb_build_object('manage', private.has_permission('recruit.manage')))
    into v_out
  from public.job_posts jp
  join public.departments d on d.id = jp.department_id
  join public.designations ds on ds.id = jp.designation_id
  join public.grades g on g.id = ds.grade_id
  join public.organizations o on o.id = jp.org_id
  join public.vacancies v on v.id = jp.vacancy_id
  where jp.id = v_post.id;
  return v_out;
end;
$$;

create or replace function public.list_applicants(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'full_name', a.full_name, 'email', a.email, 'phone', a.phone, 'source', a.source,
      'status', a.status, 'has_cv', a.cv_uploaded_at is not null,
      'cv_path', case when a.cv_uploaded_at is not null then a.cv_path end,
      'cover_note', a.cover_note, 'consent_at', a.consent_at, 'is_internal', a.is_internal,
      'created_at', a.created_at,
      'profile', (select to_jsonb(ap) - array['org_id', 'job_post_id', 'applicant_id', 'updated_by']
                  from public.applicant_profiles ap where ap.applicant_id = a.id),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('event', e.event, 'from_status', e.from_status, 'to_status', e.to_status,
                                            'actor_name', u.full_name, 'created_at', e.created_at) order by e.created_at)
        from public.applicant_events e
        left join public.user_profiles u on u.id = e.actor_user_id
        where e.applicant_id = a.id), '[]'::jsonb),
      'decisions', coalesce((
        select jsonb_agg(jsonb_build_object('from_status', dc.from_status, 'to_status', dc.to_status, 'gate', dc.gate,
                                            'note', dc.note, 'actor_name', u.full_name, 'created_at', dc.created_at)
                         order by dc.created_at)
        from public.applicant_decisions dc
        left join public.user_profiles u on u.id = dc.actor_user_id
        where dc.applicant_id = a.id), '[]'::jsonb))
      order by a.created_at desc)
    from public.applicants a
    where a.job_post_id = v_post.id and a.purged_at is null), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: question bank and question papers
-- -----------------------------------------------------------------------------
create or replace function private.question_json(p_section text, p_stem text, p_options jsonb, p_correct smallint,
                                                 p_answer text, p_marks numeric)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('section', p_section, 'stem', p_stem, 'options', p_options, 'correct_index', p_correct,
                            'model_answer', p_answer, 'marks', p_marks)
$$;

create or replace function public.get_question_papers(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  return jsonb_build_object(
    'job_post_id', v_post.id, 'title', v_post.title, 'designation_id', v_post.designation_id,
    'designation_name', (select ds.name from public.designations ds where ds.id = v_post.designation_id),
    'ai_available', private.post_cv_mode(v_post) = 'ai' and private.ai_ready(v_post.org_id),
    'papers', jsonb_build_object(
      'objective', (select to_jsonb(qp) - array['org_id', 'created_by', 'updated_by'] || jsonb_build_object('questions', coalesce((
                      select jsonb_agg(private.question_json(q.section, q.stem, q.options, q.correct_index, q.model_answer, q.marks)
                                       order by q.position) from public.paper_questions q where q.paper_id = qp.id), '[]'::jsonb))
                    from public.question_papers qp where qp.job_post_id = v_post.id and qp.kind = 'objective'),
      'written', (select to_jsonb(qp) - array['org_id', 'created_by', 'updated_by'] || jsonb_build_object('questions', coalesce((
                    select jsonb_agg(private.question_json(q.section, q.stem, q.options, q.correct_index, q.model_answer, q.marks)
                                     order by q.position) from public.paper_questions q where q.paper_id = qp.id), '[]'::jsonb))
                  from public.question_papers qp where qp.job_post_id = v_post.id and qp.kind = 'written')),
    'bank', jsonb_build_object(
      'objective', coalesce((select jsonb_agg(private.question_json(b.section, b.stem, b.options, b.correct_index, b.model_answer, b.marks)
                                              order by b.position)
                             from public.question_bank b where b.designation_id = v_post.designation_id and b.kind = 'objective'), '[]'::jsonb),
      'written', coalesce((select jsonb_agg(private.question_json(b.section, b.stem, b.options, b.correct_index, b.model_answer, b.marks)
                                            order by b.position)
                           from public.question_bank b where b.designation_id = v_post.designation_id and b.kind = 'written'), '[]'::jsonb)));
end;
$$;

-- Validates one question; returns it cleaned.
create or replace function private.clean_question(p_kind text, q jsonb, p_index integer)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_stem    text := btrim(coalesce(q ->> 'stem', ''));
  v_section text := coalesce(nullif(q ->> 'section', ''), 'general');
  v_marks   numeric := (q ->> 'marks')::numeric;
  v_options jsonb;
  v_correct integer;
begin
  if char_length(v_stem) not between 3 and 2000 then
    raise exception 'Question %: write the question (3 to 2,000 characters)', p_index using errcode = '22023';
  end if;
  if v_section not in ('aptitude', 'job_knowledge', 'language', 'situational', 'general') then
    raise exception 'Question %: unknown section', p_index using errcode = '22023';
  end if;
  if v_marks is null or v_marks not between 0.25 and 100 then
    raise exception 'Question %: marks must be between 0.25 and 100', p_index using errcode = '22023';
  end if;
  if p_kind = 'objective' then
    if jsonb_typeof(q -> 'options') <> 'array' then
      raise exception 'Question %: give 2 to 6 options', p_index using errcode = '22023';
    end if;
    select coalesce(jsonb_agg(to_jsonb(btrim(o)) order by n), '[]'::jsonb) into v_options
    from jsonb_array_elements_text(q -> 'options') with ordinality as t(o, n) where btrim(o) <> '';
    if jsonb_array_length(v_options) not between 2 and 6
       or exists (select 1 from jsonb_array_elements_text(v_options) o where char_length(o) > 300) then
      raise exception 'Question %: give 2 to 6 options of up to 300 characters', p_index using errcode = '22023';
    end if;
    v_correct := (q ->> 'correct_index')::integer;
    if v_correct is null or v_correct < 0 or v_correct >= jsonb_array_length(v_options) then
      raise exception 'Question %: mark the correct option', p_index using errcode = '22023';
    end if;
    return private.question_json(v_section, v_stem, v_options, v_correct::smallint, null, v_marks);
  end if;
  return private.question_json(v_section, v_stem, null, null,
                               left(nullif(btrim(coalesce(q ->> 'model_answer', '')), ''), 4000), v_marks);
end;
$$;

-- p: duration_minutes, pass_percent, questions [{section, stem, options[], correct_index, model_answer, marks}]
-- p_update_bank: also replace the designation's bank for this kind.
create or replace function public.save_question_paper(p_job_post_id uuid, p_kind text, p jsonb, p_update_bank boolean default false)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post      public.job_posts := private.recruit_post(p_job_post_id);
  v_paper     public.question_papers;
  v_questions jsonb := '[]'::jsonb;
  v_q         jsonb;
  v_i         integer := 0;
  v_duration  integer := (private.jtext(p, 'duration_minutes'))::integer;
  v_pass      numeric := (private.jtext(p, 'pass_percent'))::numeric;
begin
  if p_kind not in ('objective', 'written') then
    raise exception 'The paper is objective or written' using errcode = '22023';
  end if;
  if v_post.status in ('closed', 'cancelled') then
    raise exception 'This job post is %', v_post.status using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'questions') <> 'array' or jsonb_array_length(p -> 'questions') not between 1 and 200 then
    raise exception 'Add 1 to 200 questions' using errcode = '22023';
  end if;
  if p_kind = 'objective' and (v_duration is null or v_duration not between 5 and 300) then
    raise exception 'Set the test time (5 to 300 minutes)' using errcode = '22023';
  end if;
  if v_duration is not null and v_duration not between 5 and 300 then
    raise exception 'The time must be 5 to 300 minutes' using errcode = '22023';
  end if;
  if v_pass is not null and v_pass not between 0 and 100 then
    raise exception 'The pass mark is 0 to 100 percent' using errcode = '22023';
  end if;
  for v_q in select * from jsonb_array_elements(p -> 'questions') loop
    v_i := v_i + 1;
    v_questions := v_questions || jsonb_build_array(private.clean_question(p_kind, v_q, v_i));
  end loop;

  select * into v_paper from public.question_papers where job_post_id = v_post.id and kind = p_kind for update;
  if found and v_paper.locked_at is not null then
    raise exception 'The test has started; this paper is locked' using errcode = '22023';
  end if;
  if not found then
    insert into public.question_papers (org_id, job_post_id, kind) values (v_post.org_id, v_post.id, p_kind)
    returning * into v_paper;
  end if;

  delete from public.paper_questions where paper_id = v_paper.id;
  insert into public.paper_questions (org_id, paper_id, position, section, stem, options, correct_index, model_answer, marks)
  select v_post.org_id, v_paper.id, n, q ->> 'section', q ->> 'stem', q -> 'options',
         (q ->> 'correct_index')::smallint, q ->> 'model_answer', (q ->> 'marks')::numeric
  from jsonb_array_elements(v_questions) with ordinality as t(q, n);
  update public.question_papers
     set duration_minutes = v_duration, pass_percent = v_pass, version = case when v_paper.question_count = 0 then 1 else version + 1 end,
         total_marks = (select sum((q ->> 'marks')::numeric) from jsonb_array_elements(v_questions) q),
         question_count = jsonb_array_length(v_questions)
   where id = v_paper.id;

  if coalesce(p_update_bank, false) then
    delete from public.question_bank where designation_id = v_post.designation_id and kind = p_kind;
    insert into public.question_bank (org_id, designation_id, kind, position, section, stem, options, correct_index, model_answer, marks)
    select v_post.org_id, v_post.designation_id, p_kind, n, q ->> 'section', q ->> 'stem', q -> 'options',
           (q ->> 'correct_index')::smallint, q ->> 'model_answer', (q ->> 'marks')::numeric
    from jsonb_array_elements(v_questions) with ordinality as t(q, n);
  end if;
  return v_paper.id;
end;
$$;

create or replace function public.delete_question_paper(p_job_post_id uuid, p_kind text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post  public.job_posts := private.recruit_post(p_job_post_id);
  v_paper public.question_papers;
begin
  select * into v_paper from public.question_papers where job_post_id = v_post.id and kind = p_kind for update;
  if not found then
    return;
  end if;
  if v_paper.locked_at is not null then
    raise exception 'The test has started; this paper is locked' using errcode = '22023';
  end if;
  delete from public.paper_questions where paper_id = v_paper.id;
  delete from public.question_papers where id = v_paper.id;
end;
$$;

-- What the Edge Function needs to draft questions with AI (as the user).
create or replace function public.question_ai_context(p_job_post_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  if not (private.post_cv_mode(v_post) = 'ai' and private.ai_ready(v_post.org_id)) then
    raise exception 'AI is off for this post or no AI key is set; write the questions by hand' using errcode = '22023';
  end if;
  return jsonb_build_object('org_id', v_post.org_id, 'title', v_post.title, 'profile', v_post.profile);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.recruit_settings     enable row level security;
alter table public.org_integrations     enable row level security;
alter table public.applicant_profiles   enable row level security;
alter table public.applicant_decisions  enable row level security;
alter table public.question_bank        enable row level security;
alter table public.question_papers      enable row level security;
alter table public.paper_questions      enable row level security;
revoke all on table public.recruit_settings, public.org_integrations, public.applicant_profiles,
                    public.applicant_decisions, public.question_bank, public.question_papers, public.paper_questions
from anon, authenticated;

revoke all on function
  public.get_recruit_settings(), public.save_recruit_settings(jsonb), public.save_ai_integration(jsonb),
  public.remove_ai_integration(), public.ai_test_context(), public.record_ai_test(boolean, text),
  public.service_ai_key(uuid), public.set_post_cv_mode(uuid, text), public.claim_cv_reads(uuid, integer, boolean, timestamptz),
  public.save_cv_read(uuid, jsonb), public.save_applicant_profile(uuid, jsonb),
  public.move_applicants(uuid, uuid[], text, text), public.list_job_posts(), public.get_job_post(uuid),
  public.list_applicants(uuid), public.get_question_papers(uuid), public.save_question_paper(uuid, text, jsonb, boolean),
  public.delete_question_paper(uuid, text), public.question_ai_context(uuid)
from public, anon;
grant execute on function
  public.get_recruit_settings(), public.save_recruit_settings(jsonb), public.save_ai_integration(jsonb),
  public.remove_ai_integration(), public.ai_test_context(), public.record_ai_test(boolean, text),
  public.set_post_cv_mode(uuid, text), public.claim_cv_reads(uuid, integer, boolean, timestamptz),
  public.save_cv_read(uuid, jsonb), public.save_applicant_profile(uuid, jsonb),
  public.move_applicants(uuid, uuid[], text, text), public.list_job_posts(), public.get_job_post(uuid),
  public.list_applicants(uuid), public.get_question_papers(uuid), public.save_question_paper(uuid, text, jsonb, boolean),
  public.delete_question_paper(uuid, text), public.question_ai_context(uuid)
to authenticated;
-- The decrypted key: the Edge Function's service role only, never a logged-in user.
revoke all on function public.service_ai_key(uuid) from authenticated;
grant execute on function public.service_ai_key(uuid) to service_role;

revoke all on function
  private.seed_recruit_defaults(uuid), private.education_rank(text), private.ats_figures(jsonb),
  private.text_has_term(text, text), private.detect_education(text), private.estimate_years(text, date),
  private.score_applicant_profile(uuid), private.recruit_scope(uuid), private.recruit_post(uuid),
  private.post_cv_mode(public.job_posts), private.ai_ready(uuid),
  private.question_json(text, text, jsonb, smallint, text, numeric), private.clean_question(text, jsonb, integer)
from public, anon, authenticated;
