-- =============================================================================
-- Onboarding process R2: job profiles, job posts, careers page, applications.
-- Module handbook: src/onboarding-process/architecture.md (sections 5-8).
--
-- An approved vacancy becomes a job post filled from the designation's job
-- profile (the post keeps a copy, so later profile edits never change it).
-- Salary is shown only when the post's toggle is on; otherwise "Negotiable".
-- Published posts appear on the company's public careers page
-- (/careers/<org code>). People apply there without logging in:
--   submit_job_application -> upload the CV to the private bucket at the path it
--   returns (allowed for one hour, once) -> confirm_cv_upload with the token.
-- HR can also add applicants who sent CVs by email, LinkedIn, Bdjobs ...
-- CVs are temporary: the purge on vacancy close (R7) removes them.
-- The audit log keeps applicant ids, status and changed field names only,
-- never names, emails, phones or CV text.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.vacancies') is null then
    raise exception 'Apply 20261025000100_recruit_r1_workforce.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('recruit.manage', 'recruitment', 'Job profiles, job posts and applicants', false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
-- What a designation needs: the source every job post is filled from.
create table public.job_profiles (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null,
  department_id        uuid not null,
  designation_id       uuid not null unique,
  experience_min_years numeric(4, 1) not null default 0 check (experience_min_years between 0 and 50),
  experience_max_years numeric(4, 1) check (experience_max_years is null or experience_max_years between 0 and 60),
  education_level      text not null default 'any'
                       check (education_level in ('any', 'ssc', 'hsc', 'diploma', 'bachelor', 'masters', 'phd')),
  education_subjects   text[] not null default '{}',
  required_skills      text[] not null default '{}',
  nice_skills          text[] not null default '{}',
  duties               text not null check (char_length(duties) between 10 and 4000),
  employment_type      text not null default 'permanent'
                       check (employment_type in ('permanent', 'contract', 'probation', 'intern', 'part_time')),
  version              integer not null default 1,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint job_profiles_org_id_id_uq unique (org_id, id),
  constraint job_profiles_designation_fk foreign key (org_id, department_id, designation_id)
    references public.designations (org_id, department_id, id),
  constraint job_profiles_experience check (experience_max_years is null or experience_max_years >= experience_min_years)
);
select private.attach_standard_triggers('public.job_profiles');

create table public.job_posts (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  vacancy_id       uuid not null unique,
  department_id    uuid not null,
  designation_id   uuid not null,
  profile          jsonb not null,
  profile_version  integer not null,
  title            text not null check (char_length(btrim(title)) between 3 and 120),
  description_md   text not null check (char_length(description_md) between 1 and 10000),
  location         text check (location is null or char_length(location) <= 120),
  seats            smallint not null check (seats between 1 and 500),
  employment_type  text not null,
  show_salary      boolean not null default false,
  salary_min       numeric(12, 2),
  salary_max       numeric(12, 2),
  deadline         date not null,
  public_slug      text not null check (public_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(public_slug) <= 80),
  poster           jsonb not null default '{"theme":"orange"}',
  weights          jsonb not null default '{"ats":10,"objective":25,"written":20,"interview":45}',
  has_written_test boolean not null default true,
  status           text not null default 'draft' check (status in ('draft', 'published', 'closed', 'cancelled')),
  published_at     timestamptz,
  published_by     uuid references public.user_profiles (id),
  closed_at        timestamptz,
  closed_by        uuid references public.user_profiles (id),
  close_note       text check (close_note is null or char_length(close_note) <= 500),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint job_posts_org_id_id_uq unique (org_id, id),
  constraint job_posts_slug_uq unique (org_id, public_slug),
  constraint job_posts_vacancy_fk foreign key (org_id, vacancy_id) references public.vacancies (org_id, id),
  constraint job_posts_designation_fk foreign key (org_id, department_id, designation_id)
    references public.designations (org_id, department_id, id),
  constraint job_posts_salary check (not show_salary or (salary_min > 0 and salary_max >= salary_min))
);
create index job_posts_public_idx on public.job_posts (org_id, status, deadline);
select private.attach_standard_triggers('public.job_posts');

create table public.applicants (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null,
  job_post_id          uuid not null,
  full_name            text check (full_name is null or char_length(btrim(full_name)) between 2 and 120),
  email                text check (email is null or (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  phone                text,
  source               text not null check (source in ('form', 'email', 'linkedin', 'bdjobs', 'referral', 'other')),
  consent_at           timestamptz,
  cover_note           text check (cover_note is null or char_length(cover_note) <= 1000),
  cv_path              text,
  cv_uploaded_at       timestamptz,
  cv_upload_token_hash text,
  is_internal          boolean not null default false,
  employee_id          uuid,
  status               text not null default 'applied'
                       check (status in ('applied', 'screened_out', 'shortlisted', 'test_invited', 'test_done',
                                         'written_done', 'interview_scheduled', 'interviewed', 'selected', 'rejected',
                                         'offer_sent', 'offer_accepted', 'offer_declined', 'prejoining_done', 'joined',
                                         'purged')),
  purged_at            timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint applicants_org_id_id_uq unique (org_id, id),
  constraint applicants_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id),
  constraint applicants_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint applicants_identity check (purged_at is not null or (full_name is not null and email is not null))
);
create unique index applicants_post_email_uq on public.applicants (job_post_id, lower(email)) where purged_at is null;
create index applicants_post_idx on public.applicants (job_post_id, created_at);
create index applicants_cv_path_idx on public.applicants (cv_path) where cv_uploaded_at is null;

create table public.applicant_events (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  applicant_id  uuid not null,
  event         text not null,
  from_status   text,
  to_status     text,
  actor_user_id uuid references public.user_profiles (id) default auth.uid(),
  created_at    timestamptz not null default now(),
  constraint applicant_events_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id)
);
create index applicant_events_applicant_idx on public.applicant_events (applicant_id, created_at);

-- Rate limiting for the public apply form (hashes only).
create table private.apply_log (
  id         bigserial primary key,
  org_id     uuid not null,
  ip_hash    text,
  email_hash text not null,
  created_at timestamptz not null default now()
);
create index apply_log_created_idx on private.apply_log (created_at);

create or replace function private.history_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'History rows in % cannot be changed', tg_table_name using errcode = '42501';
end;
$$;
create trigger applicant_events_append_only before update or delete on public.applicant_events
  for each row execute function private.history_append_only();

-- Applicants are audited without personal data: ids, status and the names of changed fields.
create or replace function private.audit_applicant_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old     jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_new     jsonb := to_jsonb(new);
  v_changed text[];
begin
  if tg_op = 'UPDATE' then
    select array_agg(n.key order by n.key) into v_changed
    from jsonb_each(v_new) n
    where n.key not in ('updated_at', 'updated_by') and (v_old -> n.key) is distinct from n.value;
    if v_changed is null then
      return null;
    end if;
  end if;
  perform private.write_audit(
    new.org_id, lower(tg_op), 'applicants', new.id,
    case when tg_op = 'UPDATE' then jsonb_build_object('status', old.status) end,
    jsonb_build_object('status', new.status, 'job_post_id', new.job_post_id, 'source', new.source,
                       'has_cv', new.cv_uploaded_at is not null, 'changed', to_jsonb(v_changed)));
  return null;
end;
$$;
create trigger set_row_meta before insert or update on public.applicants
  for each row execute function private.set_row_meta();
create trigger prevent_delete before delete on public.applicants
  for each row execute function private.prevent_delete();
create trigger audit after insert or update on public.applicants
  for each row execute function private.audit_applicant_change();

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
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, 'recruit.manage'
  from public.roles r
  where r.org_id = p_org_id and r.system_key = 'hr_manager'
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
end;
$$;

select private.seed_recruit_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.education_label(p_level text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_level
    when 'ssc' then 'SSC or equivalent'
    when 'hsc' then 'HSC or equivalent'
    when 'diploma' then 'Diploma'
    when 'bachelor' then 'Bachelor''s degree (Pass or Honours)'
    when 'masters' then 'Master''s degree'
    when 'phd' then 'PhD'
    else 'Any'
  end
$$;

-- jsonb list of strings -> trimmed text[] without blanks (max items, max length each).
create or replace function private.text_list(p jsonb, p_label text, p_max_items integer, p_max_len integer)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_list text[];
begin
  if p is null or p = 'null'::jsonb then
    return '{}';
  end if;
  if jsonb_typeof(p) <> 'array' then
    raise exception '% must be a list', p_label using errcode = '22023';
  end if;
  select coalesce(array_agg(btrim(x) order by n), '{}') into v_list
  from jsonb_array_elements_text(p) with ordinality as t(x, n)
  where btrim(x) <> '';
  if cardinality(v_list) > p_max_items then
    raise exception '% may have at most % items', p_label, p_max_items using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_list) x where char_length(x) > p_max_len) then
    raise exception 'Each item of % may have at most % characters', p_label, p_max_len using errcode = '22023';
  end if;
  return v_list;
end;
$$;

-- The text of a new job post, written from the job profile (Markdown: ## headings and - lists).
create or replace function private.job_post_markdown(p_org_name text, p_department text, p_title text, p_seats integer,
                                                     p_profile jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_min    numeric := trim_scale(coalesce((p_profile ->> 'experience_min_years')::numeric, 0));
  v_max    numeric := trim_scale((p_profile ->> 'experience_max_years')::numeric);
  v_level  text := coalesce(p_profile ->> 'education_level', 'any');
  v_subj   text := (select string_agg(x, ' / ') from jsonb_array_elements_text(coalesce(p_profile -> 'education_subjects', '[]')) x);
  v_skills text := (select string_agg(x, ', ') from jsonb_array_elements_text(coalesce(p_profile -> 'required_skills', '[]')) x);
  v_duties text;
  v_nice   text;
  v_out    text;
begin
  select string_agg('- ' || btrim(regexp_replace(line, '^\s*[-*•]+\s*', '')), E'\n')
    into v_duties
  from regexp_split_to_table(coalesce(p_profile ->> 'duties', ''), E'\r?\n') as line
  where btrim(regexp_replace(line, '^\s*[-*•]+\s*', '')) <> '';
  select string_agg('- ' || x, E'\n') into v_nice
  from jsonb_array_elements_text(coalesce(p_profile -> 'nice_skills', '[]')) x;

  v_out := format(E'## About the role\n**%s** is hiring %s (%s %s) in the %s department.\n',
                  p_org_name, p_title, p_seats, case when p_seats = 1 then 'position' else 'positions' end, p_department);
  if v_duties is not null then
    v_out := v_out || E'\n## Responsibilities\n' || v_duties || E'\n';
  end if;
  v_out := v_out || E'\n## Requirements\n- ' || case
    when v_min = 0 and v_max is null then 'No prior experience required'
    when v_min = 0 then format('Up to %s years of experience', v_max)
    when v_max is null then format('At least %s years of experience', v_min)
    when v_max = v_min then format('%s years of experience', v_min)
    else format('%s to %s years of experience', v_min, v_max)
  end || E'\n';
  if v_level <> 'any' then
    v_out := v_out || '- Education: ' || private.education_label(v_level)
             || coalesce(' in ' || v_subj, '') || E'\n';
  end if;
  if v_skills is not null then
    v_out := v_out || '- Skills: ' || v_skills || E'\n';
  end if;
  if v_nice is not null then
    v_out := v_out || E'\n## Nice to have\n' || v_nice || E'\n';
  end if;
  v_out := v_out || E'\n## Employment\n- Type: '
           || initcap(replace(coalesce(p_profile ->> 'employment_type', 'permanent'), '_', ' ')) || E'\n';
  return v_out;
end;
$$;

-- URL-safe slug from a title, with a short random suffix (unique within the org).
create or replace function private.job_post_slug(p_org_id uuid, p_title text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_base text := left(btrim(regexp_replace(lower(coalesce(p_title, '')), '[^a-z0-9]+', '-', 'g'), '-'), 50);
  v_slug text;
begin
  v_base := btrim(v_base, '-');
  if v_base = '' then
    v_base := 'job';
  end if;
  loop
    v_slug := v_base || '-' || left(encode(extensions.gen_random_bytes(3), 'hex'), 5);
    exit when not exists (select 1 from public.job_posts where org_id = p_org_id and public_slug = v_slug);
  end loop;
  return v_slug;
end;
$$;

create or replace function private.applicant_event(p_applicant_id uuid, p_event text, p_from text, p_to text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.applicant_events (org_id, applicant_id, event, from_status, to_status)
  select a.org_id, a.id, p_event, p_from, p_to from public.applicants a where a.id = p_applicant_id
$$;

create or replace function private.cv_extension(p_file_name text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(substring(coalesce(p_file_name, '') from '\.([A-Za-z0-9]+)$'))
$$;

-- recruit-cvs/{org}/{job post}/{applicant}.{pdf|docx}
create or replace function private.cv_path(p_org_id uuid, p_post_id uuid, p_applicant_id uuid, p_ext text)
returns text
language sql
immutable
set search_path = ''
as $$
  select p_org_id::text || '/' || p_post_id::text || '/' || p_applicant_id::text || '.' || p_ext
$$;

-- Validates a candidate's name / email / phone; returns them cleaned.
create or replace function private.clean_applicant(p jsonb, p_phone_required boolean)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_name  text := btrim(coalesce(p ->> 'full_name', ''));
  v_email text := lower(btrim(coalesce(p ->> 'email', '')));
  v_phone text := nullif(btrim(coalesce(p ->> 'phone', '')), '');
begin
  if char_length(v_name) not between 2 and 120 then
    raise exception 'Enter the full name (2 to 120 characters)' using errcode = '22023';
  end if;
  if char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address (%)', left(v_name, 40) using errcode = '22023';
  end if;
  if v_phone is null and p_phone_required then
    raise exception 'Enter a mobile number' using errcode = '23502';
  end if;
  return jsonb_build_object('full_name', v_name, 'email', v_email, 'phone', private.normalize_bd_phone(v_phone));
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: temporary CVs (private bucket)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('recruit-cvs', 'recruit-cvs', false, 5242880,
   array['application/pdf', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Storage policies call their functions as the caller. The public upload check lives in its own
-- schema so that anon gets this one function and nothing of `private` (not exposed by the API).
create schema if not exists policy_checks;
revoke all on schema policy_checks from public;
grant usage on schema policy_checks to anon, authenticated;

-- A public applicant may upload exactly the file their application asked for, within an hour.
create or replace function policy_checks.recruit_cv_pending(p_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.applicants a
    where a.cv_path = p_name and a.cv_uploaded_at is null and a.cv_upload_token_hash is not null
      and a.purged_at is null and a.created_at > now() - interval '1 hour')
$$;

-- HR with recruit.manage: files of applicants in their own organization.
create or replace function private.recruit_cv_access(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
begin
  if array_length(v_parts, 1) <> 3 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[2] !~ '^[0-9a-f-]{36}$'
     or v_parts[3] !~ '^[0-9a-f-]{36}\.(pdf|docx)$' then
    return false;
  end if;
  if v_parts[1]::uuid is distinct from private.current_org_id() or not private.has_permission('recruit.manage') then
    return false;
  end if;
  return exists (select 1 from public.applicants a
                 where a.id = split_part(v_parts[3], '.', 1)::uuid and a.job_post_id = v_parts[2]::uuid
                   and a.org_id = v_parts[1]::uuid and a.purged_at is null);
end;
$$;

revoke all on function policy_checks.recruit_cv_pending(text), private.recruit_cv_access(text) from public, anon;
grant execute on function policy_checks.recruit_cv_pending(text) to anon, authenticated;
grant execute on function private.recruit_cv_access(text) to authenticated;

drop policy if exists olympus_recruit_cvs_apply on storage.objects;
drop policy if exists olympus_recruit_cvs_select on storage.objects;
drop policy if exists olympus_recruit_cvs_insert on storage.objects;
drop policy if exists olympus_recruit_cvs_update on storage.objects;
drop policy if exists olympus_recruit_cvs_delete on storage.objects;

create policy olympus_recruit_cvs_apply on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'recruit-cvs' and policy_checks.recruit_cv_pending(name));
create policy olympus_recruit_cvs_select on storage.objects for select to authenticated
  using (bucket_id = 'recruit-cvs' and private.recruit_cv_access(name));
create policy olympus_recruit_cvs_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'recruit-cvs' and private.recruit_cv_access(name));
create policy olympus_recruit_cvs_update on storage.objects for update to authenticated
  using (bucket_id = 'recruit-cvs' and private.recruit_cv_access(name))
  with check (bucket_id = 'recruit-cvs' and private.recruit_cv_access(name));
create policy olympus_recruit_cvs_delete on storage.objects for delete to authenticated
  using (bucket_id = 'recruit-cvs' and private.recruit_cv_access(name));

-- -----------------------------------------------------------------------------
-- API: job profiles
-- -----------------------------------------------------------------------------
create or replace function public.list_job_profiles()
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
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'designation_id', ds.id, 'designation_name', ds.name, 'department_id', d.id, 'department_name', d.name,
      'grade_code', g.code,
      'profile', (select to_jsonb(jp) - array['org_id', 'created_by', 'updated_by'] from public.job_profiles jp
                  where jp.designation_id = ds.id))
      order by d.name, ds.name)
    from public.designations ds
    join public.departments d on d.id = ds.department_id
    join public.grades g on g.id = ds.grade_id
    where ds.org_id = v_org_id and ds.status = 'active' and d.status = 'active'), '[]'::jsonb);
end;
$$;

-- p: experience_min_years, experience_max_years, education_level, education_subjects[],
--    required_skills[], nice_skills[], duties, employment_type
create or replace function public.save_job_profile(p_designation_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_dept   uuid;
  v_min    numeric := coalesce((private.jtext(p, 'experience_min_years'))::numeric, 0);
  v_max    numeric := (private.jtext(p, 'experience_max_years'))::numeric;
  v_level  text := coalesce(private.jtext(p, 'education_level'), 'any');
  v_type   text := coalesce(private.jtext(p, 'employment_type'), 'permanent');
  v_duties text := btrim(coalesce(p ->> 'duties', ''));
  v_id     uuid;
begin
  perform private.require_permission('recruit.manage');
  select ds.department_id into v_dept from public.designations ds
   where ds.id = p_designation_id and ds.org_id = v_org_id and ds.status = 'active';
  if not found then
    raise exception 'Designation not found' using errcode = 'P0002';
  end if;
  if v_min not between 0 and 50 or (v_max is not null and (v_max < v_min or v_max > 60)) then
    raise exception 'Experience: minimum 0 to 50 years, maximum (optional) not below the minimum' using errcode = '22023';
  end if;
  if v_level not in ('any', 'ssc', 'hsc', 'diploma', 'bachelor', 'masters', 'phd') then
    raise exception 'Unknown education level' using errcode = '22023';
  end if;
  if v_type not in ('permanent', 'contract', 'probation', 'intern', 'part_time') then
    raise exception 'Unknown employment type' using errcode = '22023';
  end if;
  if char_length(v_duties) not between 10 and 4000 then
    raise exception 'Describe the duties (10 to 4,000 characters)' using errcode = '22023';
  end if;

  insert into public.job_profiles (org_id, department_id, designation_id, experience_min_years, experience_max_years,
                                   education_level, education_subjects, required_skills, nice_skills, duties,
                                   employment_type)
  values (v_org_id, v_dept, p_designation_id, v_min, v_max, v_level,
          private.text_list(p -> 'education_subjects', 'Subjects', 10, 60),
          private.text_list(p -> 'required_skills', 'Required skills', 20, 60),
          private.text_list(p -> 'nice_skills', 'Nice-to-have skills', 20, 60),
          v_duties, v_type)
  on conflict (designation_id) do update
    set experience_min_years = excluded.experience_min_years, experience_max_years = excluded.experience_max_years,
        education_level = excluded.education_level, education_subjects = excluded.education_subjects,
        required_skills = excluded.required_skills, nice_skills = excluded.nice_skills, duties = excluded.duties,
        employment_type = excluded.employment_type, version = public.job_profiles.version + 1
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: job posts (HR)
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
begin
  perform private.require_permission('recruit.manage');
  return jsonb_build_object(
    'org_code', (select o.org_code from public.organizations o where o.id = v_org_id),
    'posts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', jp.id, 'vacancy_id', jp.vacancy_id, 'title', jp.title, 'status', jp.status, 'deadline', jp.deadline,
        'public_slug', jp.public_slug, 'department_name', d.name, 'designation_name', ds.name, 'seats', jp.seats,
        'show_salary', jp.show_salary, 'salary_min', jp.salary_min, 'salary_max', jp.salary_max,
        'published_at', jp.published_at, 'created_at', jp.created_at,
        'applicants', (select count(*) from public.applicants a where a.job_post_id = jp.id and a.purged_at is null),
        'with_cv', (select count(*) from public.applicants a
                    where a.job_post_id = jp.id and a.purged_at is null and a.cv_uploaded_at is not null))
        order by jp.created_at desc)
      from public.job_posts jp
      join public.departments d on d.id = jp.department_id
      join public.designations ds on ds.id = jp.designation_id
      where jp.org_id = v_org_id), '[]'::jsonb),
    'ready', coalesce((
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
        and not exists (select 1 from public.job_posts jp where jp.vacancy_id = v.id)), '[]'::jsonb));
end;
$$;

create or replace function public.create_job_post_from_vacancy(p_vacancy_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id  uuid := private.current_org_id();
  v_vac     public.vacancies;
  v_profile public.job_profiles;
  v_snap    jsonb;
  v_title   text;
  v_dept    text;
  v_org     text;
  v_office  text;
  v_id      uuid;
begin
  perform private.require_permission('recruit.manage');
  select * into v_vac from public.vacancies where id = p_vacancy_id and org_id = v_org_id;
  if not found then
    raise exception 'Vacancy not found' using errcode = 'P0002';
  end if;
  if v_vac.status <> 'approved' then
    raise exception 'Only an approved vacancy can be posted (now %)', v_vac.status using errcode = '22023';
  end if;
  if exists (select 1 from public.job_posts where vacancy_id = p_vacancy_id) then
    raise exception 'This vacancy already has a job post' using errcode = '23505';
  end if;
  select ds.name into v_title from public.designations ds where ds.id = v_vac.designation_id;
  select * into v_profile from public.job_profiles where designation_id = v_vac.designation_id;
  if not found then
    raise exception 'Set up the job profile for % first', v_title using errcode = 'P0002';
  end if;
  select d.name into v_dept from public.departments d where d.id = v_vac.department_id;
  select o.name into v_org from public.organizations o where o.id = v_org_id;
  -- Location: the vacancy's office, else where most of the department works.
  select o.name into v_office from public.offices o
   where o.id = coalesce(v_vac.office_id, (select e.office_id from public.employees e
                                           where e.department_id = v_vac.department_id and e.status = 'active'
                                             and e.office_id is not null
                                           group by e.office_id order by count(*) desc, e.office_id limit 1));

  v_snap := to_jsonb(v_profile) - array['id', 'org_id', 'created_at', 'updated_at', 'created_by', 'updated_by'];
  insert into public.job_posts (org_id, vacancy_id, department_id, designation_id, profile, profile_version, title,
                                description_md, location, seats, employment_type, deadline, public_slug)
  values (v_org_id, v_vac.id, v_vac.department_id, v_vac.designation_id, v_snap, v_profile.version, v_title,
          private.job_post_markdown(v_org, v_dept, v_title, v_vac.seats, v_snap), v_office, v_vac.seats,
          v_profile.employment_type, private.org_today(v_org_id) + 14, private.job_post_slug(v_org_id, v_title))
  returning id into v_id;
  return v_id;
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
  v_org_id uuid := private.current_org_id();
  v_out    jsonb;
begin
  perform private.require_permission('recruit.manage');
  select to_jsonb(jp) - array['org_id', 'created_by', 'updated_by']
         || jsonb_build_object(
              'department_name', d.name, 'designation_name', ds.name, 'grade_code', g.code,
              'org_code', o.org_code, 'org_name', o.name,
              'vacancy_status', v.status, 'vacancy_reason', v.reason,
              'profile_current_version', (select p.version from public.job_profiles p where p.designation_id = jp.designation_id),
              'today', private.org_today(v_org_id))
    into v_out
  from public.job_posts jp
  join public.departments d on d.id = jp.department_id
  join public.designations ds on ds.id = jp.designation_id
  join public.grades g on g.id = ds.grade_id
  join public.organizations o on o.id = jp.org_id
  join public.vacancies v on v.id = jp.vacancy_id
  where jp.id = p_id and jp.org_id = v_org_id;
  if v_out is null then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  return v_out;
end;
$$;

-- p: title, description_md, location, show_salary, salary_min, salary_max, deadline, poster {theme},
--    weights {ats, objective, written, interview} (whole numbers, sum 100), has_written_test,
--    public_slug (draft only). Keys left out keep their value.
create or replace function public.update_job_post(p_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_post   public.job_posts;
  v_today  date := private.org_today(v_org_id);
  v_key    text;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_id and org_id = v_org_id for update;
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if v_post.status not in ('draft', 'published') then
    raise exception 'A % job post cannot be edited', v_post.status using errcode = '22023';
  end if;

  if p ? 'title' then
    v_post.title := btrim(coalesce(p ->> 'title', ''));
    if char_length(v_post.title) not between 3 and 120 then
      raise exception 'The title needs 3 to 120 characters' using errcode = '22023';
    end if;
  end if;
  if p ? 'description_md' then
    v_post.description_md := btrim(coalesce(p ->> 'description_md', ''));
    if char_length(v_post.description_md) not between 1 and 10000 then
      raise exception 'The description needs 1 to 10,000 characters' using errcode = '22023';
    end if;
  end if;
  if p ? 'location' then
    v_post.location := nullif(btrim(coalesce(p ->> 'location', '')), '');
    if char_length(v_post.location) > 120 then
      raise exception 'The location may have at most 120 characters' using errcode = '22023';
    end if;
  end if;
  if p ? 'show_salary' then
    v_post.show_salary := coalesce((p ->> 'show_salary')::boolean, false);
  end if;
  if p ? 'salary_min' then
    v_post.salary_min := (private.jtext(p, 'salary_min'))::numeric;
  end if;
  if p ? 'salary_max' then
    v_post.salary_max := (private.jtext(p, 'salary_max'))::numeric;
  end if;
  if v_post.show_salary and (v_post.salary_min is null or v_post.salary_min <= 0 or v_post.salary_max is null
                             or v_post.salary_max < v_post.salary_min or v_post.salary_max > 99999999) then
    raise exception 'With the salary shown, enter a minimum above zero and a maximum not below it' using errcode = '23514';
  end if;
  if p ? 'deadline' then
    v_post.deadline := (private.jtext(p, 'deadline'))::date;
    if v_post.deadline is null or v_post.deadline < v_today or v_post.deadline > v_today + 90 then
      raise exception 'The deadline must be between today and 90 days from now' using errcode = '22023';
    end if;
  end if;
  if p ? 'poster' then
    if coalesce(p -> 'poster' ->> 'theme', '') not in ('orange', 'navy', 'green', 'maroon') then
      raise exception 'Unknown poster theme' using errcode = '22023';
    end if;
    v_post.poster := jsonb_build_object('theme', p -> 'poster' ->> 'theme');
  end if;
  if p ? 'weights' then
    if jsonb_typeof(p -> 'weights') <> 'object'
       or (select array_agg(k order by k) from jsonb_object_keys(p -> 'weights') k)
          is distinct from array['ats', 'interview', 'objective', 'written'] then
      raise exception 'Weights need exactly: ats, objective, written, interview' using errcode = '22023';
    end if;
    foreach v_key in array array['ats', 'objective', 'written', 'interview'] loop
      if jsonb_typeof(p -> 'weights' -> v_key) <> 'number' or (p -> 'weights' ->> v_key)::numeric not between 0 and 100
         or (p -> 'weights' ->> v_key)::numeric <> trunc((p -> 'weights' ->> v_key)::numeric) then
        raise exception 'Each weight is a whole number from 0 to 100' using errcode = '22023';
      end if;
    end loop;
    if (select sum(value::numeric) from jsonb_each_text(p -> 'weights')) <> 100 then
      raise exception 'The weights must add up to 100' using errcode = '22023';
    end if;
    v_post.weights := p -> 'weights';
  end if;
  if p ? 'has_written_test' then
    v_post.has_written_test := coalesce((p ->> 'has_written_test')::boolean, true);
  end if;
  if p ? 'public_slug' and (p ->> 'public_slug') is distinct from v_post.public_slug then
    if v_post.status <> 'draft' then
      raise exception 'The link cannot change after publishing' using errcode = '22023';
    end if;
    v_post.public_slug := lower(btrim(coalesce(p ->> 'public_slug', '')));
    if v_post.public_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(v_post.public_slug) > 80 then
      raise exception 'The link may use a-z, 0-9 and single dashes (up to 80 characters)' using errcode = '22023';
    end if;
    if exists (select 1 from public.job_posts where org_id = v_org_id and public_slug = v_post.public_slug and id <> p_id) then
      raise exception 'Another job post already uses this link' using errcode = '23505';
    end if;
  end if;

  update public.job_posts
     set title = v_post.title, description_md = v_post.description_md, location = v_post.location,
         show_salary = v_post.show_salary,
         salary_min = case when v_post.show_salary then v_post.salary_min end,
         salary_max = case when v_post.show_salary then v_post.salary_max end,
         deadline = v_post.deadline, poster = v_post.poster, weights = v_post.weights,
         has_written_test = v_post.has_written_test, public_slug = v_post.public_slug
   where id = p_id;
end;
$$;

create or replace function public.publish_job_post(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_post   public.job_posts;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_id and org_id = v_org_id for update;
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if v_post.status <> 'draft' then
    raise exception 'Only a draft can be published (now %)', v_post.status using errcode = '22023';
  end if;
  if (select v.status from public.vacancies v where v.id = v_post.vacancy_id) <> 'approved' then
    raise exception 'The vacancy is no longer approved' using errcode = '22023';
  end if;
  if v_post.deadline < private.org_today(v_org_id) then
    raise exception 'The deadline has passed; pick a new one first' using errcode = '22023';
  end if;
  update public.job_posts set status = 'published', published_at = now(), published_by = auth.uid() where id = p_id;
end;
$$;

-- Draft -> cancelled; published -> closed (no more applications).
create or replace function public.close_job_post(p_id uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if v_post.status not in ('draft', 'published') then
    raise exception 'This job post is already %', v_post.status using errcode = '22023';
  end if;
  update public.job_posts
     set status = case when v_post.status = 'draft' then 'cancelled' else 'closed' end,
         closed_at = now(), closed_by = auth.uid(), close_note = nullif(left(btrim(p_note), 500), '')
   where id = p_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: applicants (HR)
-- -----------------------------------------------------------------------------
-- Candidates who sent their CV another way. p_rows: [{full_name, email, phone}]
create or replace function public.add_applicants(p_job_post_id uuid, p_rows jsonb, p_source text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_post   public.job_posts;
  v_row    jsonb;
  v_clean  jsonb;
  v_id     uuid;
  v_ids    uuid[] := '{}';
  v_dupes  integer := 0;
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = v_org_id;
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  if v_post.status not in ('published', 'closed') then
    raise exception 'Publish the job post before adding applicants' using errcode = '22023';
  end if;
  if coalesce(p_source, '') not in ('email', 'linkedin', 'bdjobs', 'referral', 'other') then
    raise exception 'Source must be email, LinkedIn, Bdjobs, referral or other' using errcode = '22023';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 200 then
    raise exception 'Send 1 to 200 applicants as a list' using errcode = '22023';
  end if;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    v_clean := private.clean_applicant(v_row, false);
    if exists (select 1 from public.applicants a where a.job_post_id = p_job_post_id and a.purged_at is null
               and lower(a.email) = v_clean ->> 'email') then
      v_dupes := v_dupes + 1;
      continue;
    end if;
    insert into public.applicants (org_id, job_post_id, full_name, email, phone, source)
    values (v_org_id, p_job_post_id, v_clean ->> 'full_name', v_clean ->> 'email', v_clean ->> 'phone', p_source)
    returning id into v_id;
    perform private.applicant_event(v_id, 'added_by_hr', null, 'applied');
    v_ids := v_ids || v_id;
  end loop;
  return jsonb_build_object('added', cardinality(v_ids), 'duplicates', v_dupes, 'ids', to_jsonb(v_ids));
end;
$$;

-- After HR uploads a CV to recruit-cvs/{org}/{post}/{applicant}.{ext}.
create or replace function public.attach_applicant_cv(p_applicant_id uuid, p_ext text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app  public.applicants;
  v_path text;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants
   where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null for update;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  if coalesce(p_ext, '') not in ('pdf', 'docx') then
    raise exception 'A CV must be a PDF or DOCX file' using errcode = '22023';
  end if;
  v_path := private.cv_path(v_app.org_id, v_app.job_post_id, v_app.id, p_ext);
  if not exists (select 1 from storage.objects o where o.bucket_id = 'recruit-cvs' and o.name = v_path) then
    raise exception 'The CV file was not found; upload it again' using errcode = 'P0002';
  end if;
  update public.applicants set cv_path = v_path, cv_uploaded_at = now(), cv_upload_token_hash = null
   where id = p_applicant_id;
  perform private.applicant_event(p_applicant_id, 'cv_attached', v_app.status, v_app.status);
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
  v_org_id uuid := private.current_org_id();
begin
  perform private.require_permission('recruit.manage');
  if not exists (select 1 from public.job_posts where id = p_job_post_id and org_id = v_org_id) then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', a.id, 'full_name', a.full_name, 'email', a.email, 'phone', a.phone, 'source', a.source,
      'status', a.status, 'has_cv', a.cv_uploaded_at is not null,
      'cv_path', case when a.cv_uploaded_at is not null then a.cv_path end,
      'cover_note', a.cover_note, 'consent_at', a.consent_at, 'is_internal', a.is_internal,
      'created_at', a.created_at,
      'events', coalesce((
        select jsonb_agg(jsonb_build_object('event', e.event, 'from_status', e.from_status, 'to_status', e.to_status,
                                            'actor_name', u.full_name, 'created_at', e.created_at) order by e.created_at)
        from public.applicant_events e
        left join public.user_profiles u on u.id = e.actor_user_id
        where e.applicant_id = a.id), '[]'::jsonb))
      order by a.created_at desc)
    from public.applicants a
    where a.job_post_id = p_job_post_id and a.purged_at is null), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- API: public careers page and apply form (no login)
-- -----------------------------------------------------------------------------
create or replace function private.public_post_json(p_post public.job_posts, p_today date)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'slug', p_post.public_slug, 'title', p_post.title, 'location', p_post.location, 'seats', p_post.seats,
    'employment_type', p_post.employment_type, 'deadline', p_post.deadline, 'published_at', p_post.published_at,
    'department_name', (select d.name from public.departments d where d.id = p_post.department_id),
    'show_salary', p_post.show_salary,
    'salary_min', case when p_post.show_salary then p_post.salary_min end,
    'salary_max', case when p_post.show_salary then p_post.salary_max end,
    'is_open', p_post.status = 'published' and p_post.deadline >= p_today)
$$;

create or replace function public.get_public_careers(p_org_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org   public.organizations;
  v_today date;
begin
  select * into v_org from public.organizations where org_code = btrim(coalesce(p_org_code, '')) and status = 'active';
  if not found then
    raise exception 'Careers page not found' using errcode = 'P0002';
  end if;
  v_today := private.org_today(v_org.id);
  return jsonb_build_object(
    'organization', jsonb_build_object('name', v_org.name, 'org_code', v_org.org_code),
    'posts', coalesce((
      select jsonb_agg(private.public_post_json(jp, v_today) order by jp.published_at desc)
      from public.job_posts jp
      where jp.org_id = v_org.id and jp.status = 'published' and jp.deadline >= v_today), '[]'::jsonb));
end;
$$;

create or replace function public.get_public_job_post(p_org_code text, p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  public.organizations;
  v_post public.job_posts;
begin
  select * into v_org from public.organizations where org_code = btrim(coalesce(p_org_code, '')) and status = 'active';
  if found then
    select * into v_post from public.job_posts
     where org_id = v_org.id and public_slug = lower(btrim(coalesce(p_slug, ''))) and status in ('published', 'closed');
  end if;
  if v_post.id is null then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  return private.public_post_json(v_post, private.org_today(v_org.id))
         || jsonb_build_object('description_md', v_post.description_md,
                               'organization', jsonb_build_object('name', v_org.name, 'org_code', v_org.org_code));
end;
$$;

-- p: full_name, email, phone, cover_note, consent (true), website (must stay empty),
--    cv_file_name, cv_size (bytes), cv_type (MIME).
-- Returns where to upload the CV and the one-time token for confirm_cv_upload.
create or replace function public.submit_job_application(p_org_code text, p_slug text, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org     public.organizations;
  v_post    public.job_posts;
  v_today   date;
  v_clean   jsonb;
  v_ext     text := private.cv_extension(p ->> 'cv_file_name');
  v_size    bigint := (private.jtext(p, 'cv_size'))::bigint;
  v_type    text := coalesce(p ->> 'cv_type', '');
  v_ip      text := nullif(btrim(split_part(coalesce(private.request_header('x-forwarded-for'), ''), ',', 1)), '');
  v_ip_hash text := case when v_ip is not null then encode(extensions.digest(v_ip, 'sha256'), 'hex') end;
  v_mail_h  text;
  v_id      uuid := gen_random_uuid();
  v_token   text := encode(extensions.gen_random_bytes(24), 'hex');
  v_path    text;
begin
  select * into v_org from public.organizations where org_code = btrim(coalesce(p_org_code, '')) and status = 'active';
  if found then
    select * into v_post from public.job_posts
     where org_id = v_org.id and public_slug = lower(btrim(coalesce(p_slug, ''))) and status in ('published', 'closed');
  end if;
  if v_post.id is null then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  v_today := private.org_today(v_org.id);
  if v_post.status <> 'published' or v_post.deadline < v_today then
    raise exception 'This job is no longer accepting applications' using errcode = '22023';
  end if;
  if coalesce(p ->> 'website', '') <> '' then
    raise exception 'The application could not be accepted' using errcode = '22023';
  end if;
  v_clean := private.clean_applicant(p, true);
  if not coalesce((p ->> 'consent')::boolean, false) then
    raise exception 'Please agree to the use of your data for this application' using errcode = '23502';
  end if;
  if char_length(coalesce(p ->> 'cover_note', '')) > 1000 then
    raise exception 'The note may have at most 1,000 characters' using errcode = '22023';
  end if;
  if v_ext is null or v_ext not in ('pdf', 'docx')
     or v_type <> (case v_ext when 'pdf' then 'application/pdf'
                              else 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' end) then
    raise exception 'Attach your CV as a PDF or DOCX file' using errcode = '22023';
  end if;
  if v_size is null or v_size not between 1 and 5242880 then
    raise exception 'The CV must be smaller than 5 MB' using errcode = '22023';
  end if;

  v_mail_h := encode(extensions.digest(v_clean ->> 'email', 'sha256'), 'hex');
  delete from private.apply_log where created_at < now() - interval '1 day';
  if (v_ip_hash is not null and (select count(*) from private.apply_log
                                 where ip_hash = v_ip_hash and created_at > now() - interval '1 hour') >= 10)
     or (select count(*) from private.apply_log
         where email_hash = v_mail_h and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many applications in a short time; please try again in an hour' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.applicants a where a.job_post_id = v_post.id and a.purged_at is null
             and lower(a.email) = v_clean ->> 'email') then
    raise exception 'You have already applied for this job with this email' using errcode = '23505';
  end if;
  insert into private.apply_log (org_id, ip_hash, email_hash) values (v_org.id, v_ip_hash, v_mail_h);

  v_path := private.cv_path(v_org.id, v_post.id, v_id, v_ext);
  insert into public.applicants (id, org_id, job_post_id, full_name, email, phone, source, consent_at, cover_note,
                                 cv_path, cv_upload_token_hash)
  values (v_id, v_org.id, v_post.id, v_clean ->> 'full_name', v_clean ->> 'email', v_clean ->> 'phone', 'form', now(),
          nullif(btrim(p ->> 'cover_note'), ''), v_path, encode(extensions.digest(v_token, 'sha256'), 'hex'));
  perform private.applicant_event(v_id, 'applied', null, 'applied');
  return jsonb_build_object('applicant_id', v_id, 'bucket', 'recruit-cvs', 'upload_path', v_path, 'upload_token', v_token);
end;
$$;

create or replace function public.confirm_cv_upload(p_applicant_id uuid, p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app public.applicants;
begin
  select * into v_app from public.applicants
   where id = p_applicant_id and cv_uploaded_at is null and purged_at is null
     and cv_upload_token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
  for update;
  if not found then
    raise exception 'This upload link is not valid' using errcode = 'P0002';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'recruit-cvs' and o.name = v_app.cv_path) then
    raise exception 'The CV file did not arrive; please upload it again' using errcode = '22023';
  end if;
  update public.applicants set cv_uploaded_at = now(), cv_upload_token_hash = null where id = p_applicant_id;
  perform private.applicant_event(p_applicant_id, 'cv_uploaded', v_app.status, v_app.status);
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges: tables closed, functions only
-- -----------------------------------------------------------------------------
alter table public.job_profiles     enable row level security;
alter table public.job_posts        enable row level security;
alter table public.applicants       enable row level security;
alter table public.applicant_events enable row level security;
revoke all on table public.job_profiles, public.job_posts, public.applicants, public.applicant_events
from anon, authenticated;
revoke all on table private.apply_log from public, anon, authenticated;

revoke all on function
  public.list_job_profiles(), public.save_job_profile(uuid, jsonb), public.list_job_posts(),
  public.create_job_post_from_vacancy(uuid), public.get_job_post(uuid), public.update_job_post(uuid, jsonb),
  public.publish_job_post(uuid), public.close_job_post(uuid, text), public.add_applicants(uuid, jsonb, text),
  public.attach_applicant_cv(uuid, text), public.list_applicants(uuid),
  public.get_public_careers(text), public.get_public_job_post(text, text),
  public.submit_job_application(text, text, jsonb), public.confirm_cv_upload(uuid, text)
from public, anon;
grant execute on function
  public.list_job_profiles(), public.save_job_profile(uuid, jsonb), public.list_job_posts(),
  public.create_job_post_from_vacancy(uuid), public.get_job_post(uuid), public.update_job_post(uuid, jsonb),
  public.publish_job_post(uuid), public.close_job_post(uuid, text), public.add_applicants(uuid, jsonb, text),
  public.attach_applicant_cv(uuid, text), public.list_applicants(uuid)
to authenticated;
grant execute on function
  public.get_public_careers(text), public.get_public_job_post(text, text),
  public.submit_job_application(text, text, jsonb), public.confirm_cv_upload(uuid, text)
to anon, authenticated;

revoke all on function
  private.seed_recruit_defaults(uuid), private.seed_org_defaults(uuid), private.education_label(text),
  private.text_list(jsonb, text, integer, integer), private.job_post_markdown(text, text, text, integer, jsonb),
  private.job_post_slug(uuid, text), private.applicant_event(uuid, text, text, text), private.cv_extension(text),
  private.cv_path(uuid, uuid, uuid, text), private.clean_applicant(jsonb, boolean),
  private.public_post_json(public.job_posts, date), private.audit_applicant_change(), private.history_append_only()
from public, anon, authenticated;
