-- =============================================================================
-- Onboarding process R4: online objective test on our own page, written-test
-- marks, interview scheduling within 15 days.
-- Module handbook: src/onboarding-process/architecture.md (sections 4-8).
--
-- Objective test: HR invites shortlisted applicants; each gets a private link
-- (/t/<token>, only the sha-256 of the token is stored). The first invite locks
-- the paper. The applicant starts once; the server keeps the clock
-- (deadline = start + duration, answers accepted 30 s longer for slow
-- networks); answers autosave; submitting (or the clock running out) scores the
-- test at once, so HR sees it on the board immediately. The answer key never
-- leaves the database. Question order is shuffled per applicant.
-- Written test: on paper; HR enters marks per question (the paper locks).
-- Interview: due within 15 days of the last result; the system proposes the
-- first slot (from 2 days ahead, 10:00-16:00 in 45-minute slots) that is a
-- working day for every panel member, nobody on leave and no clash; HR or the
-- department Manager may change, reschedule or cancel it. Panel: 1-4 employees.
-- Scores never move anyone by themselves; HR decides.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.question_papers') is null then
    raise exception 'Apply 20261027000100_recruit_r3_screening.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.assessment_invites (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null,
  applicant_id   uuid not null,
  paper_id       uuid not null,
  paper_version  integer not null,
  token_hash     text not null unique,
  question_order integer[] not null,
  status         text not null default 'invited' check (status in ('invited', 'started', 'submitted', 'expired', 'cancelled')),
  expires_at     timestamptz not null,
  started_at     timestamptz,
  deadline_at    timestamptz,
  submitted_at   timestamptz,
  auto_submitted boolean not null default false,
  created_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id) default auth.uid(),
  constraint assessment_invites_org_id_id_uq unique (org_id, id),
  constraint assessment_invites_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint assessment_invites_paper_fk foreign key (org_id, paper_id) references public.question_papers (org_id, id)
);
create unique index assessment_invites_open_uq on public.assessment_invites (applicant_id, paper_id)
  where status in ('invited', 'started', 'submitted');

create table public.assessment_answers (
  invite_id    uuid not null,
  org_id       uuid not null,
  position     integer not null,
  chosen_index smallint not null,
  answered_at  timestamptz not null default now(),
  primary key (invite_id, position),
  constraint assessment_answers_invite_fk foreign key (org_id, invite_id) references public.assessment_invites (org_id, id)
);

create table public.assessment_results (
  invite_id      uuid primary key,
  org_id         uuid not null,
  applicant_id   uuid not null,
  paper_id       uuid not null,
  score          numeric(7, 2) not null,
  total          numeric(7, 2) not null,
  percent        numeric(5, 1) not null,
  answered       integer not null,
  correct        integer not null,
  section_scores jsonb not null,
  passed         boolean,
  created_at     timestamptz not null default now(),
  constraint assessment_results_invite_fk foreign key (org_id, invite_id) references public.assessment_invites (org_id, id),
  constraint assessment_results_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id)
);

create table public.written_marks (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null,
  applicant_id uuid not null,
  paper_id     uuid not null,
  marks        jsonb not null,
  score        numeric(7, 2) not null,
  total        numeric(7, 2) not null,
  percent      numeric(5, 1) not null,
  passed       boolean,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint written_marks_applicant_paper_uq unique (applicant_id, paper_id),
  constraint written_marks_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint written_marks_paper_fk foreign key (org_id, paper_id) references public.question_papers (org_id, id)
);
create trigger set_row_meta before insert or update on public.written_marks
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.written_marks
  for each row execute function private.audit_row_change();

create table public.interview_schedules (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  applicant_id     uuid not null,
  job_post_id      uuid not null,
  starts_at        timestamptz not null,
  duration_minutes smallint not null default 45 check (duration_minutes between 15 and 240),
  mode             text not null default 'in_person' check (mode in ('in_person', 'online')),
  location         text check (location is null or char_length(location) <= 200),
  online_link      text check (online_link is null or (char_length(online_link) <= 500 and online_link ~ '^https://')),
  panel            uuid[] not null check (cardinality(panel) between 1 and 4),
  due_by           date not null,
  late_reason      text check (late_reason is null or char_length(late_reason) <= 300),
  status           text not null default 'scheduled' check (status in ('scheduled', 'done', 'cancelled')),
  prev_status      text not null,
  note             text check (note is null or char_length(note) <= 500),
  cancel_reason    text check (cancel_reason is null or char_length(cancel_reason) <= 300),
  proposed_by      text not null default 'user' check (proposed_by in ('system', 'user')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint interview_schedules_applicant_fk foreign key (org_id, applicant_id) references public.applicants (org_id, id),
  constraint interview_schedules_post_fk foreign key (org_id, job_post_id) references public.job_posts (org_id, id)
);
create unique index interview_schedules_active_uq on public.interview_schedules (applicant_id) where status = 'scheduled';
create index interview_schedules_time_idx on public.interview_schedules (org_id, starts_at) where status = 'scheduled';
create trigger set_row_meta before insert or update on public.interview_schedules
  for each row execute function private.set_row_meta();
create trigger audit after insert or update on public.interview_schedules
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Scoring (mirror: src/onboarding-process/core/assessment.ts)
-- -----------------------------------------------------------------------------
-- Scores an invite from its saved answers and stores the result (idempotent).
create or replace function private.score_invite(p_invite_id uuid, p_auto boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv     public.assessment_invites;
  v_pass    numeric;
  v_score   numeric;
  v_total   numeric;
  v_answer  integer;
  v_correct integer;
  v_sections jsonb;
begin
  select * into v_inv from public.assessment_invites where id = p_invite_id for update;
  if v_inv.status = 'submitted' then
    return;
  end if;
  select qp.pass_percent into v_pass from public.question_papers qp where qp.id = v_inv.paper_id;

  select coalesce(sum(q.marks) filter (where a.chosen_index = q.correct_index), 0), coalesce(sum(q.marks), 0),
         count(a.position), count(*) filter (where a.chosen_index = q.correct_index)
    into v_score, v_total, v_answer, v_correct
  from public.paper_questions q
  left join public.assessment_answers a on a.invite_id = v_inv.id and a.position = q.position
  where q.paper_id = v_inv.paper_id;

  select coalesce(jsonb_object_agg(section, jsonb_build_object(
           'score', score, 'total', total, 'percent', round(score / nullif(total, 0) * 100, 1))), '{}'::jsonb)
    into v_sections
  from (select q.section, coalesce(sum(q.marks) filter (where a.chosen_index = q.correct_index), 0) as score, sum(q.marks) as total
        from public.paper_questions q
        left join public.assessment_answers a on a.invite_id = v_inv.id and a.position = q.position
        where q.paper_id = v_inv.paper_id
        group by q.section) s;

  insert into public.assessment_results (invite_id, org_id, applicant_id, paper_id, score, total, percent, answered, correct,
                                         section_scores, passed)
  values (v_inv.id, v_inv.org_id, v_inv.applicant_id, v_inv.paper_id, v_score, v_total,
          round(v_score / nullif(v_total, 0) * 100, 1), v_answer, v_correct, v_sections,
          case when v_pass is not null then round(v_score / nullif(v_total, 0) * 100, 1) >= v_pass end)
  on conflict (invite_id) do nothing;
  update public.assessment_invites set status = 'submitted', submitted_at = now(), auto_submitted = p_auto where id = v_inv.id;
  update public.applicants set status = 'test_done' where id = v_inv.applicant_id and status = 'test_invited';
  perform private.applicant_event(v_inv.applicant_id, case when p_auto then 'test_time_up' else 'test_submitted' end,
                                  'test_invited', 'test_done');
end;
$$;

-- Closes tests whose time has run out (and unused links past their expiry) for one post.
create or replace function private.close_overdue_tests(p_job_post_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  for v_id in
    select i.id from public.assessment_invites i
    join public.question_papers qp on qp.id = i.paper_id
    where qp.job_post_id = p_job_post_id and i.status = 'started' and now() > i.deadline_at + interval '30 seconds'
  loop
    perform private.score_invite(v_id, true);
  end loop;
  update public.assessment_invites i set status = 'expired'
    from public.question_papers qp
   where qp.id = i.paper_id and qp.job_post_id = p_job_post_id and i.status = 'invited' and now() > i.expires_at;
end;
$$;

-- The date an interview is due: 15 days after the latest of shortlisting, test and written result.
create or replace function private.interview_due_by(p_applicant_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (greatest(
            (select max(e.created_at) from public.applicant_events e
              where e.applicant_id = p_applicant_id and e.event in ('moved_shortlisted', 'test_submitted', 'test_time_up')),
            (select max(w.updated_at) from public.written_marks w where w.applicant_id = p_applicant_id),
            (select a.created_at from public.applicants a where a.id = p_applicant_id))
          at time zone (select o.timezone from public.organizations o join public.applicants a on a.org_id = o.id
                        where a.id = p_applicant_id))::date + 15
$$;

-- The first free 45-minute slot from p_from (10:00-16:00 local) that is a working day for every
-- panel member, nobody on full-day leave, no clash with their other interviews. Null if none by p_until.
create or replace function private.first_free_slot(p_org_id uuid, p_panel uuid[], p_from date, p_until date,
                                                   p_minutes integer, p_skip uuid)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz    text := (select timezone from public.organizations where id = p_org_id);
  v_day   date := p_from;
  v_start timestamptz;
  v_slot  integer;
begin
  while v_day <= p_until loop
    if not exists (select 1 from public.employees e where e.id = any (p_panel)
                   and (private.day_type(p_org_id, e.branch_id, v_day) <> 'workday' or private.on_leave(e.id, v_day))) then
      for v_slot in 0..7 loop
        v_start := ((v_day + time '10:00') + make_interval(mins => v_slot * 45)) at time zone v_tz;
        exit when (v_start at time zone v_tz)::time + make_interval(mins => p_minutes) > time '16:30';
        if not exists (select 1 from public.interview_schedules s
                       where s.org_id = p_org_id and s.status = 'scheduled' and s.panel && p_panel
                         and s.id is distinct from p_skip
                         and tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.duration_minutes))
                             && tstzrange(v_start, v_start + make_interval(mins => p_minutes))) then
          return v_start;
        end if;
      end loop;
    end if;
    v_day := v_day + 1;
  end loop;
  return null;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: HR / Manager
-- -----------------------------------------------------------------------------
-- Everything about the shortlisted applicants of a post: tests, marks, interviews.
create or replace function public.get_assessment_board(p_job_post_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post public.job_posts := private.recruit_post(p_job_post_id);
begin
  perform private.close_overdue_tests(v_post.id);
  return jsonb_build_object(
    'can', jsonb_build_object('manage', private.has_permission('recruit.manage'), 'schedule', true),
    'today', private.org_today(v_post.org_id),
    'timezone', (select o.timezone from public.organizations o where o.id = v_post.org_id),
    'papers', (select coalesce(jsonb_object_agg(qp.kind, jsonb_build_object(
                 'id', qp.id, 'question_count', qp.question_count, 'total_marks', qp.total_marks,
                 'duration_minutes', qp.duration_minutes, 'pass_percent', qp.pass_percent, 'locked', qp.locked_at is not null,
                 'questions', case when qp.kind = 'written' then (
                   select jsonb_agg(jsonb_build_object('position', q.position, 'stem', q.stem, 'marks', q.marks,
                                                       'model_answer', q.model_answer) order by q.position)
                   from public.paper_questions q where q.paper_id = qp.id) end)), '{}'::jsonb)
               from public.question_papers qp where qp.job_post_id = v_post.id),
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'applicant_id', a.id, 'full_name', a.full_name, 'email', a.email, 'phone', a.phone, 'status', a.status,
        'ats_score', ap.ats_score, 'gate', ap.gate,
        'invite', (select jsonb_build_object('id', i.id, 'status', i.status, 'expires_at', i.expires_at,
                                             'started_at', i.started_at, 'submitted_at', i.submitted_at,
                                             'auto_submitted', i.auto_submitted, 'created_at', i.created_at)
                   from public.assessment_invites i join public.question_papers qp on qp.id = i.paper_id
                   where i.applicant_id = a.id and qp.job_post_id = v_post.id
                   order by i.created_at desc limit 1),
        'objective', (select jsonb_build_object('score', r.score, 'total', r.total, 'percent', r.percent, 'passed', r.passed,
                                                'answered', r.answered, 'correct', r.correct, 'sections', r.section_scores)
                      from public.assessment_results r join public.question_papers qp on qp.id = r.paper_id
                      where r.applicant_id = a.id and qp.job_post_id = v_post.id
                      order by r.created_at desc limit 1),
        'written', (select jsonb_build_object('score', w.score, 'total', w.total, 'percent', w.percent, 'passed', w.passed,
                                              'marks', w.marks, 'updated_at', w.updated_at)
                    from public.written_marks w join public.question_papers qp on qp.id = w.paper_id
                    where w.applicant_id = a.id and qp.job_post_id = v_post.id),
        'interview', (select jsonb_build_object(
                         'id', s.id, 'starts_at', s.starts_at, 'duration_minutes', s.duration_minutes, 'mode', s.mode,
                         'location', s.location, 'online_link', s.online_link, 'panel', to_jsonb(s.panel),
                         'panel_names', (select jsonb_agg(e.full_name order by e.full_name) from public.employees e where e.id = any (s.panel)),
                         'due_by', s.due_by, 'late_reason', s.late_reason, 'note', s.note, 'proposed_by', s.proposed_by)
                       from public.interview_schedules s where s.applicant_id = a.id and s.status = 'scheduled'),
        'due_by', private.interview_due_by(a.id))
        order by ap.ats_score desc nulls last, a.created_at)
      from public.applicants a
      left join public.applicant_profiles ap on ap.applicant_id = a.id
      where a.job_post_id = v_post.id and a.purged_at is null
        and a.status in ('shortlisted', 'test_invited', 'test_done', 'written_done', 'interview_scheduled')), '[]'::jsonb));
end;
$$;

-- Creates test links. Returns the raw tokens once (they are not stored); the paper locks.
create or replace function public.invite_to_test(p_job_post_id uuid, p_ids uuid[], p_valid_days integer default 3)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_post   public.job_posts;
  v_paper  public.question_papers;
  v_app    record;
  v_token  text;
  v_out    jsonb := '[]'::jsonb;
  v_days   integer := coalesce(p_valid_days, 3);
begin
  perform private.require_permission('recruit.manage');
  select * into v_post from public.job_posts where id = p_job_post_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Job post not found' using errcode = 'P0002';
  end if;
  select * into v_paper from public.question_papers where job_post_id = v_post.id and kind = 'objective' for update;
  if not found or v_paper.question_count = 0 then
    raise exception 'Set the objective paper first (Question papers tab)' using errcode = 'P0002';
  end if;
  if v_days not between 1 and 14 then
    raise exception 'A link may stay valid for 1 to 14 days' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_ids), 0) = 0 then
    raise exception 'Pick at least one applicant' using errcode = '22023';
  end if;
  update public.question_papers set locked_at = coalesce(locked_at, now()) where id = v_paper.id;

  for v_app in
    select a.id, a.full_name, a.email, a.status from public.applicants a
    where a.id = any (p_ids) and a.job_post_id = v_post.id and a.purged_at is null for update
  loop
    if v_app.status not in ('shortlisted', 'test_invited') then
      raise exception '% is % and cannot be invited to the test', v_app.full_name, v_app.status using errcode = '22023';
    end if;
    if exists (select 1 from public.assessment_invites where applicant_id = v_app.id and paper_id = v_paper.id
               and status in ('started', 'submitted')) then
      raise exception '% has already started or taken the test', v_app.full_name using errcode = '22023';
    end if;
    update public.assessment_invites set status = 'cancelled'
     where applicant_id = v_app.id and paper_id = v_paper.id and status = 'invited';
    v_token := encode(extensions.gen_random_bytes(24), 'hex');
    insert into public.assessment_invites (org_id, applicant_id, paper_id, paper_version, token_hash, question_order, expires_at)
    values (v_post.org_id, v_app.id, v_paper.id, v_paper.version, encode(extensions.digest(v_token, 'sha256'), 'hex'),
            (select array_agg(q.position order by random()) from public.paper_questions q where q.paper_id = v_paper.id),
            now() + make_interval(days => v_days));
    update public.applicants set status = 'test_invited' where id = v_app.id;
    perform private.applicant_event(v_app.id, 'test_invited', v_app.status, 'test_invited');
    v_out := v_out || jsonb_build_array(jsonb_build_object('applicant_id', v_app.id, 'full_name', v_app.full_name,
                                                           'email', v_app.email, 'token', v_token));
  end loop;
  if jsonb_array_length(v_out) <> cardinality(p_ids) then
    raise exception 'Some applicants were not found in this job post' using errcode = 'P0002';
  end if;
  return v_out;
end;
$$;

create or replace function public.cancel_test_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.assessment_invites;
begin
  perform private.require_permission('recruit.manage');
  select * into v_inv from public.assessment_invites where id = p_invite_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Test link not found' using errcode = 'P0002';
  end if;
  if v_inv.status <> 'invited' then
    raise exception 'Only an unused link can be cancelled (now %)', v_inv.status using errcode = '22023';
  end if;
  update public.assessment_invites set status = 'cancelled' where id = p_invite_id;
  update public.applicants set status = 'shortlisted' where id = v_inv.applicant_id and status = 'test_invited';
  perform private.applicant_event(v_inv.applicant_id, 'test_link_cancelled', 'test_invited', 'shortlisted');
end;
$$;

-- p_marks: [{position, marks}] for every question of the written paper.
create or replace function public.save_written_marks(p_applicant_id uuid, p_marks jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app   public.applicants;
  v_paper public.question_papers;
  v_q     record;
  v_given numeric;
  v_score numeric := 0;
  v_clean jsonb := '[]'::jsonb;
  v_pct   numeric;
begin
  perform private.require_permission('recruit.manage');
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null for update;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  if v_app.status not in ('shortlisted', 'test_invited', 'test_done', 'written_done', 'interview_scheduled') then
    raise exception 'Marks can be entered for shortlisted applicants only (now %)', v_app.status using errcode = '22023';
  end if;
  select * into v_paper from public.question_papers where job_post_id = v_app.job_post_id and kind = 'written' for update;
  if not found or v_paper.question_count = 0 then
    raise exception 'This post has no written paper' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_marks) is distinct from 'array' then
    raise exception 'Send the marks as a list' using errcode = '22023';
  end if;
  for v_q in select q.position, q.marks from public.paper_questions q where q.paper_id = v_paper.id order by q.position loop
    v_given := (select (m ->> 'marks')::numeric from jsonb_array_elements(p_marks) m where (m ->> 'position')::integer = v_q.position);
    if v_given is null or v_given < 0 or v_given > v_q.marks then
      raise exception 'Question %: give 0 to % marks', v_q.position, v_q.marks using errcode = '22023';
    end if;
    v_score := v_score + v_given;
    v_clean := v_clean || jsonb_build_array(jsonb_build_object('position', v_q.position, 'marks', v_given));
  end loop;
  v_pct := round(v_score / nullif(v_paper.total_marks, 0) * 100, 1);

  update public.question_papers set locked_at = coalesce(locked_at, now()) where id = v_paper.id;
  insert into public.written_marks (org_id, applicant_id, paper_id, marks, score, total, percent, passed)
  values (v_app.org_id, v_app.id, v_paper.id, v_clean, v_score, v_paper.total_marks, v_pct,
          case when v_paper.pass_percent is not null then v_pct >= v_paper.pass_percent end)
  on conflict (applicant_id, paper_id) do update
    set marks = excluded.marks, score = excluded.score, total = excluded.total, percent = excluded.percent, passed = excluded.passed;
  if v_app.status in ('shortlisted', 'test_invited', 'test_done') then
    update public.applicants set status = 'written_done' where id = v_app.id;
    perform private.applicant_event(v_app.id, 'written_marked', v_app.status, 'written_done');
  end if;
  return jsonb_build_object('score', v_score, 'total', v_paper.total_marks, 'percent', v_pct);
end;
$$;

-- People who may sit on an interview panel (active employees of the company).
create or replace function public.list_interviewer_options(p_job_post_id uuid)
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
    select jsonb_agg(jsonb_build_object('id', e.id, 'full_name', e.full_name, 'department_name', d.name,
                                        'designation_name', ds.name, 'same_department', e.department_id = v_post.department_id)
                     order by (e.department_id = v_post.department_id) desc, e.full_name)
    from public.employees e
    left join public.departments d on d.id = e.department_id
    left join public.designations ds on ds.id = e.designation_id
    where e.org_id = v_post.org_id and e.status = 'active'), '[]'::jsonb);
end;
$$;

-- Clean list of 1-4 active employees of the org.
create or replace function private.clean_panel(p_org_id uuid, p jsonb)
returns uuid[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_panel uuid[];
begin
  if jsonb_typeof(p) is distinct from 'array' then
    raise exception 'Pick the interview panel' using errcode = '22023';
  end if;
  select array_agg(distinct x::uuid) into v_panel from jsonb_array_elements_text(p) x;
  if coalesce(cardinality(v_panel), 0) not between 1 and 4 then
    raise exception 'The panel has 1 to 4 interviewers' using errcode = '22023';
  end if;
  if (select count(*) from public.employees e where e.id = any (v_panel) and e.org_id = p_org_id and e.status = 'active')
     <> cardinality(v_panel) then
    raise exception 'Every interviewer must be an active employee of this company' using errcode = '22023';
  end if;
  return v_panel;
end;
$$;

-- p: panel [employee ids], duration_minutes (optional). Proposes the first free slot.
create or replace function public.propose_interview_slot(p_applicant_id uuid, p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_app     public.applicants;
  v_post    public.job_posts;
  v_panel   uuid[];
  v_due     date;
  v_today   date;
  v_minutes integer := coalesce((private.jtext(p, 'duration_minutes'))::integer, 45);
  v_slot    timestamptz;
begin
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  v_post := private.recruit_post(v_app.job_post_id);
  v_panel := private.clean_panel(v_app.org_id, p -> 'panel');
  v_today := private.org_today(v_app.org_id);
  v_due := private.interview_due_by(v_app.id);
  v_slot := private.first_free_slot(v_app.org_id, v_panel, v_today + 2, greatest(v_due, v_today + 2), v_minutes,
                                    (select s.id from public.interview_schedules s where s.applicant_id = v_app.id and s.status = 'scheduled'));
  return jsonb_build_object('found', v_slot is not null, 'starts_at', v_slot, 'due_by', v_due,
                            'searched_from', v_today + 2, 'duration_minutes', v_minutes);
end;
$$;

-- Schedules (or reschedules) the applicant's interview.
-- p: starts_at, duration_minutes, mode (in_person | online), location, online_link, panel [ids], note,
--    late_reason (needed after the due date), proposed_by (system | user)
create or replace function public.save_interview(p_applicant_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_app     public.applicants;
  v_post    public.job_posts;
  v_old     public.interview_schedules;
  v_panel   uuid[];
  v_start   timestamptz := (private.jtext(p, 'starts_at'))::timestamptz;
  v_minutes integer := coalesce((private.jtext(p, 'duration_minutes'))::integer, 45);
  v_mode    text := coalesce(private.jtext(p, 'mode'), 'in_person');
  v_due     date;
  v_tz      text;
  v_late    text := nullif(btrim(coalesce(p ->> 'late_reason', '')), '');
  v_id      uuid;
begin
  select * into v_app from public.applicants where id = p_applicant_id and org_id = private.current_org_id() and purged_at is null for update;
  if not found then
    raise exception 'Applicant not found' using errcode = 'P0002';
  end if;
  v_post := private.recruit_post(v_app.job_post_id);
  select * into v_old from public.interview_schedules where applicant_id = v_app.id and status = 'scheduled' for update;
  if v_old.id is null and v_app.status not in ('shortlisted', 'test_invited', 'test_done', 'written_done') then
    raise exception '% is % and cannot be scheduled for an interview', v_app.full_name, v_app.status using errcode = '22023';
  end if;
  v_panel := private.clean_panel(v_app.org_id, p -> 'panel');
  if v_start is null or v_start < now() then
    raise exception 'Pick a time in the future' using errcode = '22023';
  end if;
  if v_minutes not between 15 and 240 then
    raise exception 'An interview lasts 15 to 240 minutes' using errcode = '22023';
  end if;
  if v_mode not in ('in_person', 'online') then
    raise exception 'Mode is in person or online' using errcode = '22023';
  end if;
  if v_mode = 'online' and coalesce(p ->> 'online_link', '') !~ '^https://' then
    raise exception 'Give the meeting link (https://...)' using errcode = '22023';
  end if;
  if v_mode = 'in_person' and char_length(btrim(coalesce(p ->> 'location', ''))) < 2 then
    raise exception 'Give the place of the interview' using errcode = '22023';
  end if;
  select o.timezone into v_tz from public.organizations o where o.id = v_app.org_id;
  v_due := private.interview_due_by(v_app.id);
  if (v_start at time zone v_tz)::date > v_due and char_length(coalesce(v_late, '')) < 5 then
    raise exception 'The interview is due by %; give a reason to hold it later', v_due using errcode = '23502';
  end if;
  if exists (select 1 from public.interview_schedules s
             where s.org_id = v_app.org_id and s.status = 'scheduled' and s.panel && v_panel and s.id is distinct from v_old.id
               and tstzrange(s.starts_at, s.starts_at + make_interval(mins => s.duration_minutes))
                   && tstzrange(v_start, v_start + make_interval(mins => v_minutes))) then
    raise exception 'A panel member already has another interview at that time' using errcode = '23P01';
  end if;

  if v_old.id is not null then
    update public.interview_schedules
       set starts_at = v_start, duration_minutes = v_minutes, mode = v_mode,
           location = nullif(btrim(coalesce(p ->> 'location', '')), ''), online_link = nullif(btrim(coalesce(p ->> 'online_link', '')), ''),
           panel = v_panel, due_by = v_due, late_reason = left(v_late, 300), note = left(nullif(btrim(coalesce(p ->> 'note', '')), ''), 500),
           proposed_by = case when p ->> 'proposed_by' = 'system' then 'system' else 'user' end
     where id = v_old.id;
    perform private.applicant_event(v_app.id, 'interview_rescheduled', v_app.status, v_app.status);
    return v_old.id;
  end if;
  insert into public.interview_schedules (org_id, applicant_id, job_post_id, starts_at, duration_minutes, mode, location,
                                          online_link, panel, due_by, late_reason, prev_status, note, proposed_by)
  values (v_app.org_id, v_app.id, v_app.job_post_id, v_start, v_minutes, v_mode,
          nullif(btrim(coalesce(p ->> 'location', '')), ''), nullif(btrim(coalesce(p ->> 'online_link', '')), ''),
          v_panel, v_due, left(v_late, 300), v_app.status, left(nullif(btrim(coalesce(p ->> 'note', '')), ''), 500),
          case when p ->> 'proposed_by' = 'system' then 'system' else 'user' end)
  returning id into v_id;
  update public.applicants set status = 'interview_scheduled' where id = v_app.id;
  perform private.applicant_event(v_app.id, 'interview_scheduled', v_app.status, 'interview_scheduled');
  return v_id;
end;
$$;

create or replace function public.cancel_interview(p_interview_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_s public.interview_schedules;
begin
  select * into v_s from public.interview_schedules where id = p_interview_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Interview not found' using errcode = 'P0002';
  end if;
  perform private.recruit_post(v_s.job_post_id);
  if v_s.status <> 'scheduled' then
    raise exception 'This interview is already %', v_s.status using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;
  update public.interview_schedules set status = 'cancelled', cancel_reason = left(btrim(p_reason), 300) where id = v_s.id;
  update public.applicants set status = v_s.prev_status where id = v_s.applicant_id and status = 'interview_scheduled';
  perform private.applicant_event(v_s.applicant_id, 'interview_cancelled', 'interview_scheduled', v_s.prev_status);
end;
$$;

-- Screening out also works after the tests now (R3 allowed it only before); open links and
-- interviews of that applicant are cancelled.
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
            or (p_to = 'screened_out' and v_app.status in ('applied', 'shortlisted', 'test_invited', 'test_done',
                                                            'written_done', 'interview_scheduled'))
            or (p_to = 'applied' and v_app.status in ('shortlisted', 'screened_out'))) then
      raise exception 'An applicant who is % cannot be moved to %', v_app.status, p_to using errcode = '22023';
    end if;
    if p_to = 'shortlisted' and coalesce(v_app.gate, 'review') <> 'pass' and char_length(coalesce(v_note, '')) < 5 then
      raise exception 'Some applicants did not pass the must-have check; give a reason to shortlist them' using errcode = '23502';
    end if;
    if p_to = 'screened_out' then
      update public.assessment_invites set status = 'cancelled' where applicant_id = v_app.id and status = 'invited';
      update public.interview_schedules set status = 'cancelled', cancel_reason = left(v_note, 300)
       where applicant_id = v_app.id and status = 'scheduled';
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
-- API: the test page (no login; the token is the key)
-- -----------------------------------------------------------------------------
create or replace function private.invite_by_token(p_token text)
returns public.assessment_invites
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.assessment_invites;
begin
  select * into v_inv from public.assessment_invites
   where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex') and status <> 'cancelled';
  if not found then
    raise exception 'This test link is not valid' using errcode = 'P0002';
  end if;
  if v_inv.status = 'started' and now() > v_inv.deadline_at + interval '30 seconds' then
    perform private.score_invite(v_inv.id, true);
    select * into v_inv from public.assessment_invites where id = v_inv.id;
  elsif v_inv.status = 'invited' and now() > v_inv.expires_at then
    update public.assessment_invites set status = 'expired' where id = v_inv.id returning * into v_inv;
  end if;
  return v_inv;
end;
$$;

-- What the page shows. Questions (never the answers) only while the test is running.
create or replace function private.test_state(v_inv public.assessment_invites)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', v_inv.status,
    'organization', o.name, 'job_title', jp.title,
    'first_name', split_part(a.full_name, ' ', 1),
    'duration_minutes', qp.duration_minutes, 'question_count', qp.question_count, 'total_marks', qp.total_marks,
    'expires_at', v_inv.expires_at, 'auto_submitted', v_inv.auto_submitted,
    'seconds_left', case when v_inv.status = 'started'
                         then greatest(0, floor(extract(epoch from v_inv.deadline_at - now())))::integer end,
    'questions', case when v_inv.status = 'started' then (
      select jsonb_agg(jsonb_build_object('position', q.position, 'section', q.section, 'stem', q.stem,
                                          'options', q.options, 'marks', q.marks) order by o2.n)
      from unnest(v_inv.question_order) with ordinality as o2(pos, n)
      join public.paper_questions q on q.paper_id = v_inv.paper_id and q.position = o2.pos) end,
    'answers', case when v_inv.status = 'started' then (
      select coalesce(jsonb_object_agg(ans.position::text, ans.chosen_index), '{}'::jsonb)
      from public.assessment_answers ans where ans.invite_id = v_inv.id) end)
  from public.applicants a
  join public.job_posts jp on jp.id = a.job_post_id
  join public.organizations o on o.id = a.org_id
  join public.question_papers qp on qp.id = v_inv.paper_id
  where a.id = v_inv.applicant_id
$$;

create or replace function public.get_test(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  return private.test_state(private.invite_by_token(p_token));
end;
$$;

create or replace function public.start_test(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.assessment_invites := private.invite_by_token(p_token);
  v_min integer;
begin
  if v_inv.status = 'invited' then
    select qp.duration_minutes into v_min from public.question_papers qp where qp.id = v_inv.paper_id;
    update public.assessment_invites set status = 'started', started_at = now(), deadline_at = now() + make_interval(mins => v_min)
     where id = v_inv.id returning * into v_inv;
    perform private.applicant_event(v_inv.applicant_id, 'test_started', 'test_invited', 'test_invited');
  elsif v_inv.status <> 'started' then
    raise exception 'This test is %', v_inv.status using errcode = '22023';
  end if;
  return private.test_state(v_inv);
end;
$$;

create or replace function public.save_test_answer(p_token text, p_position integer, p_choice integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv     public.assessment_invites := private.invite_by_token(p_token);
  v_options integer;
begin
  if v_inv.status <> 'started' then
    raise exception 'The test is not running (%)', v_inv.status using errcode = '22023';
  end if;
  select jsonb_array_length(q.options) into v_options from public.paper_questions q
   where q.paper_id = v_inv.paper_id and q.position = p_position;
  if v_options is null or p_choice is null or p_choice < 0 or p_choice >= v_options then
    raise exception 'Unknown question or option' using errcode = '22023';
  end if;
  insert into public.assessment_answers (invite_id, org_id, position, chosen_index)
  values (v_inv.id, v_inv.org_id, p_position, p_choice)
  on conflict (invite_id, position) do update set chosen_index = excluded.chosen_index, answered_at = now();
end;
$$;

create or replace function public.submit_test(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv public.assessment_invites := private.invite_by_token(p_token);
begin
  if v_inv.status = 'started' then
    perform private.score_invite(v_inv.id, false);
  elsif v_inv.status <> 'submitted' then
    raise exception 'This test is %', v_inv.status using errcode = '22023';
  end if;
  return jsonb_build_object('status', 'submitted');
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.assessment_invites  enable row level security;
alter table public.assessment_answers  enable row level security;
alter table public.assessment_results  enable row level security;
alter table public.written_marks       enable row level security;
alter table public.interview_schedules enable row level security;
revoke all on table public.assessment_invites, public.assessment_answers, public.assessment_results,
                    public.written_marks, public.interview_schedules
from anon, authenticated;

revoke all on function
  public.get_assessment_board(uuid), public.invite_to_test(uuid, uuid[], integer), public.cancel_test_invite(uuid),
  public.save_written_marks(uuid, jsonb), public.list_interviewer_options(uuid), public.propose_interview_slot(uuid, jsonb),
  public.save_interview(uuid, jsonb), public.cancel_interview(uuid, text), public.move_applicants(uuid, uuid[], text, text),
  public.get_test(text), public.start_test(text), public.save_test_answer(text, integer, integer), public.submit_test(text)
from public, anon;
grant execute on function
  public.get_assessment_board(uuid), public.invite_to_test(uuid, uuid[], integer), public.cancel_test_invite(uuid),
  public.save_written_marks(uuid, jsonb), public.list_interviewer_options(uuid), public.propose_interview_slot(uuid, jsonb),
  public.save_interview(uuid, jsonb), public.cancel_interview(uuid, text), public.move_applicants(uuid, uuid[], text, text)
to authenticated;
grant execute on function
  public.get_test(text), public.start_test(text), public.save_test_answer(text, integer, integer), public.submit_test(text)
to anon, authenticated;

revoke all on function
  private.score_invite(uuid, boolean), private.close_overdue_tests(uuid), private.interview_due_by(uuid),
  private.first_free_slot(uuid, uuid[], date, date, integer, uuid), private.clean_panel(uuid, jsonb),
  private.invite_by_token(text), private.test_state(public.assessment_invites)
from public, anon, authenticated;
