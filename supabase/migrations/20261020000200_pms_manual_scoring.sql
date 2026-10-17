-- =============================================================================
-- Performance management demo: manual scoring (Part 3 doc section 9, note 15).
--
-- A visible, simple review flow that a full PMS can replace later:
--   HR creates a review cycle with weighted criteria (weights add up to 100)
--   -> opens it -> HR (anyone) or a manager (own team) scores each person 1-5
--   per criterion with a comment -> submits -> the employee sees the review and
--   acknowledges it with an optional comment -> HR closes the cycle.
-- Overall score = sum(score x weight) / sum(weight), shown with every step.
-- Rating bands (company policy): 4.5+ Outstanding, 3.5+ Exceeds expectations,
-- 2.5+ Meets expectations, 1.5+ Needs improvement, below 1.5 Unsatisfactory.
-- Nobody reviews themself; a submitted review is final.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.statutory_references') is null then
    raise exception 'Apply 20261020000100_part3c_tax_pf_gratuity.sql first, then run this file again';
  end if;
end;
$guard$;

insert into public.permissions (key, module, description, admin_only) values
  ('performance.manage', 'performance', 'Create review cycles and criteria, see and score everyone', false),
  ('performance.review', 'performance', 'Score the people in your own team',                         false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.performance_cycles (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  name        text not null check (char_length(btrim(name)) between 3 and 80),
  period_from date not null,
  period_to   date not null,
  status      text not null default 'draft' check (status in ('draft', 'open', 'closed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint performance_cycles_org_id_id_uq unique (org_id, id),
  constraint performance_cycles_period check (period_to >= period_from)
);
select private.attach_standard_triggers('public.performance_cycles');

create table public.performance_criteria (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  cycle_id    uuid not null,
  name        text not null check (char_length(btrim(name)) between 2 and 80),
  description text check (description is null or char_length(description) <= 300),
  weight      numeric(5, 2) not null check (weight > 0 and weight <= 100),
  sort_order  smallint not null default 100,
  status      text not null default 'active' check (status in ('active', 'removed')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint performance_criteria_org_id_id_uq unique (org_id, id),
  constraint performance_criteria_cycle_fk foreign key (org_id, cycle_id) references public.performance_cycles (org_id, id)
);
select private.attach_standard_triggers('public.performance_criteria');

create table public.performance_reviews (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  cycle_id         uuid not null,
  employee_id      uuid not null,
  reviewer_user_id uuid references public.user_profiles (id),
  status           text not null default 'draft' check (status in ('draft', 'submitted', 'acknowledged')),
  overall_score    numeric(4, 2) check (overall_score is null or overall_score between 1 and 5),
  rating           text,
  strengths        text check (strengths is null or char_length(strengths) <= 1000),
  improvements     text check (improvements is null or char_length(improvements) <= 1000),
  employee_comment text check (employee_comment is null or char_length(employee_comment) <= 1000),
  submitted_at     timestamptz,
  acknowledged_at  timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id),
  updated_by       uuid references public.user_profiles (id),
  constraint performance_reviews_org_id_id_uq unique (org_id, id),
  constraint performance_reviews_cycle_fk foreign key (org_id, cycle_id) references public.performance_cycles (org_id, id),
  constraint performance_reviews_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint performance_reviews_one_uq unique (cycle_id, employee_id)
);
select private.attach_standard_triggers('public.performance_reviews');

create table public.performance_scores (
  org_id       uuid not null,
  review_id    uuid not null,
  criterion_id uuid not null,
  score        smallint not null check (score between 1 and 5),
  comment      text check (comment is null or char_length(comment) <= 500),
  primary key (review_id, criterion_id),
  constraint performance_scores_review_fk foreign key (org_id, review_id) references public.performance_reviews (org_id, id),
  constraint performance_scores_criterion_fk foreign key (org_id, criterion_id)
    references public.performance_criteria (org_id, id)
);
create trigger audit after insert or update or delete on public.performance_scores
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Defaults
-- -----------------------------------------------------------------------------
create or replace function private.seed_performance_defaults(p_org_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['performance.manage', 'performance.review']
    when 'manager'    then array['performance.review']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing
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
end;
$$;

select private.seed_performance_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.performance_rating(p_score numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_score is null then null
    when p_score >= 4.5 then 'Outstanding'
    when p_score >= 3.5 then 'Exceeds expectations'
    when p_score >= 2.5 then 'Meets expectations'
    when p_score >= 1.5 then 'Needs improvement'
    else 'Unsatisfactory'
  end
$$;

-- May the caller score this employee? HR (manage) anyone but themself;
-- a reviewer only their own team.
create or replace function private.can_score_employee(p_employee_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_employee_id is distinct from private.current_employee_id()
         and (private.has_permission('performance.manage')
              or (private.has_permission('performance.review')
                  and p_employee_id in (select private.team_employee_ids())))
$$;

-- Full review with criteria, scores and the weighted working.
create or replace function private.performance_review_detail(p_cycle_id uuid, p_employee_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'cycle', (select jsonb_build_object('id', c.id, 'name', c.name, 'period_from', c.period_from,
                                        'period_to', c.period_to, 'status', c.status)
              from public.performance_cycles c where c.id = p_cycle_id),
    'employee', (select jsonb_build_object('id', e.id, 'full_name', e.full_name, 'card_id', e.card_id,
                                           'designation_name', ds.name, 'department_name', d.name)
                 from public.employees e
                 left join public.designations ds on ds.id = e.designation_id
                 left join public.departments d on d.id = e.department_id
                 where e.id = p_employee_id),
    'review', (select to_jsonb(r) - array['org_id', 'created_by', 'updated_by']
                      || jsonb_build_object('reviewer_name', (select full_name from public.user_profiles
                                                              where id = r.reviewer_user_id))
               from public.performance_reviews r where r.cycle_id = p_cycle_id and r.employee_id = p_employee_id),
    'criteria', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', cr.id, 'name', cr.name, 'description', cr.description, 'weight', cr.weight,
               'score', s.score, 'comment', s.comment,
               'weighted', case when s.score is not null then round(s.score * cr.weight / 100, 4) end)
             order by cr.sort_order, cr.name)
      from public.performance_criteria cr
      left join public.performance_reviews r on r.cycle_id = p_cycle_id and r.employee_id = p_employee_id
      left join public.performance_scores s on s.review_id = r.id and s.criterion_id = cr.id
      where cr.cycle_id = p_cycle_id and cr.status = 'active'), '[]'::jsonb),
    'references', jsonb_build_array('policy.performance'))
$$;

-- -----------------------------------------------------------------------------
-- API
-- -----------------------------------------------------------------------------
create or replace function public.save_performance_cycle(p_cycle_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id    uuid := private.current_org_id();
  v_cycle     public.performance_cycles;
  v_criterion jsonb;
  v_total     numeric;
  v_kept      uuid[] := '{}';
  v_id        uuid;
  v_order     integer := 0;
begin
  perform private.require_permission('performance.manage');
  if char_length(btrim(coalesce(p ->> 'name', ''))) < 3 then
    raise exception 'Give the cycle a name (at least 3 characters)' using errcode = '23502';
  end if;
  if (p ->> 'period_from') is null or (p ->> 'period_to') is null
     or (p ->> 'period_to')::date < (p ->> 'period_from')::date then
    raise exception 'Enter a review period whose end is not before its start' using errcode = '22023';
  end if;
  if jsonb_typeof(p -> 'criteria') is distinct from 'array' or jsonb_array_length(p -> 'criteria') = 0 then
    raise exception 'Add at least one criterion' using errcode = '23502';
  end if;
  select coalesce(sum((c ->> 'weight')::numeric), 0) into v_total from jsonb_array_elements(p -> 'criteria') c;
  if v_total <> 100 then
    raise exception 'Criteria weights must add up to 100 (now %)', v_total using errcode = '23514';
  end if;

  if p_cycle_id is null then
    insert into public.performance_cycles (org_id, name, period_from, period_to)
    values (v_org_id, btrim(p ->> 'name'), (p ->> 'period_from')::date, (p ->> 'period_to')::date)
    returning * into v_cycle;
  else
    select * into v_cycle from public.performance_cycles where id = p_cycle_id and org_id = v_org_id for update;
    if not found then
      raise exception 'Review cycle not found' using errcode = 'P0002';
    end if;
    if v_cycle.status <> 'draft' then
      raise exception 'Only a draft cycle can be changed' using errcode = '22023';
    end if;
    update public.performance_cycles
       set name = btrim(p ->> 'name'), period_from = (p ->> 'period_from')::date, period_to = (p ->> 'period_to')::date
     where id = p_cycle_id;
  end if;

  for v_criterion in select * from jsonb_array_elements(p -> 'criteria') loop
    v_order := v_order + 10;
    if char_length(btrim(coalesce(v_criterion ->> 'name', ''))) < 2 then
      raise exception 'Each criterion needs a name' using errcode = '23502';
    end if;
    if nullif(v_criterion ->> 'id', '') is not null then
      update public.performance_criteria
         set name = btrim(v_criterion ->> 'name'), description = nullif(btrim(v_criterion ->> 'description'), ''),
             weight = (v_criterion ->> 'weight')::numeric, sort_order = v_order, status = 'active'
       where id = (v_criterion ->> 'id')::uuid and cycle_id = v_cycle.id
      returning id into v_id;
      if v_id is null then
        raise exception 'Criterion not found' using errcode = 'P0002';
      end if;
    else
      insert into public.performance_criteria (org_id, cycle_id, name, description, weight, sort_order)
      values (v_org_id, v_cycle.id, btrim(v_criterion ->> 'name'), nullif(btrim(v_criterion ->> 'description'), ''),
              (v_criterion ->> 'weight')::numeric, v_order)
      returning id into v_id;
    end if;
    v_kept := v_kept || v_id;
    v_id := null;
  end loop;
  update public.performance_criteria set status = 'removed'
   where cycle_id = v_cycle.id and status = 'active' and not (id = any (v_kept));
  return v_cycle.id;
end;
$$;

create or replace function public.set_performance_cycle_status(p_cycle_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cycle public.performance_cycles;
begin
  perform private.require_permission('performance.manage');
  select * into v_cycle from public.performance_cycles where id = p_cycle_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Review cycle not found' using errcode = 'P0002';
  end if;
  if not ((v_cycle.status = 'draft' and p_status = 'open') or (v_cycle.status = 'open' and p_status = 'closed')) then
    raise exception 'A cycle goes draft -> open -> closed (now %)', v_cycle.status using errcode = '22023';
  end if;
  update public.performance_cycles set status = p_status where id = p_cycle_id;
end;
$$;

create or replace function public.list_performance_cycles()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (private.has_permission('performance.manage') or private.has_permission('performance.review')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'name', c.name, 'period_from', c.period_from, 'period_to', c.period_to, 'status', c.status,
      'criteria', (select coalesce(jsonb_agg(jsonb_build_object('id', cr.id, 'name', cr.name,
                                                                 'description', cr.description, 'weight', cr.weight)
                                             order by cr.sort_order), '[]'::jsonb)
                   from public.performance_criteria cr where cr.cycle_id = c.id and cr.status = 'active'),
      'submitted', (select count(*) from public.performance_reviews r
                    where r.cycle_id = c.id and r.status in ('submitted', 'acknowledged')),
      'average_score', (select round(avg(r.overall_score), 2) from public.performance_reviews r
                        where r.cycle_id = c.id and r.status in ('submitted', 'acknowledged')))
      order by c.period_from desc, c.created_at desc)
    from public.performance_cycles c
    where c.org_id = private.current_org_id()
      and (c.status <> 'draft' or private.has_permission('performance.manage'))), '[]'::jsonb);
end;
$$;

-- People the caller can score in a cycle, with their review status and score.
create or replace function public.get_performance_cycle(p_cycle_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cycle public.performance_cycles;
begin
  if not (private.has_permission('performance.manage') or private.has_permission('performance.review')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  select * into v_cycle from public.performance_cycles where id = p_cycle_id and org_id = private.current_org_id();
  if not found or (v_cycle.status = 'draft' and not private.has_permission('performance.manage')) then
    raise exception 'Review cycle not found' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'cycle', to_jsonb(v_cycle) - array['org_id', 'created_by', 'updated_by'],
    'can_manage', private.has_permission('performance.manage'),
    'people', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id, 'department_name', d.name,
        'designation_name', ds.name, 'review_status', coalesce(r.status, 'not_started'),
        'overall_score', r.overall_score, 'rating', r.rating) order by e.full_name)
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.designations ds on ds.id = e.designation_id
      left join public.performance_reviews r on r.cycle_id = p_cycle_id and r.employee_id = e.id
      where e.org_id = v_cycle.org_id and e.status = 'active' and private.can_score_employee(e.id)), '[]'::jsonb));
end;
$$;

create or replace function public.get_performance_review(p_cycle_id uuid, p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_review public.performance_reviews;
begin
  if not exists (select 1 from public.performance_cycles where id = p_cycle_id and org_id = private.current_org_id()) then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  select * into v_review from public.performance_reviews where cycle_id = p_cycle_id and employee_id = p_employee_id;
  if not (private.can_score_employee(p_employee_id)
          or (p_employee_id = private.current_employee_id() and v_review.status in ('submitted', 'acknowledged'))) then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  return private.performance_review_detail(p_cycle_id, p_employee_id)
         || jsonb_build_object('can_edit', private.can_score_employee(p_employee_id)
                                           and coalesce(v_review.status, 'draft') = 'draft');
end;
$$;

-- Saves scores (draft) or submits them. Submitting needs every criterion scored.
create or replace function public.save_performance_review(p_cycle_id uuid, p_employee_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id  uuid := private.current_org_id();
  v_cycle   public.performance_cycles;
  v_review  public.performance_reviews;
  v_score   jsonb;
  v_submit  boolean := coalesce((p ->> 'submit')::boolean, false);
  v_missing integer;
  v_overall numeric;
begin
  select * into v_cycle from public.performance_cycles where id = p_cycle_id and org_id = v_org_id;
  if not found then
    raise exception 'Review cycle not found' using errcode = 'P0002';
  end if;
  if v_cycle.status <> 'open' then
    raise exception 'Scores can be entered only while the cycle is open' using errcode = '22023';
  end if;
  if p_employee_id = private.current_employee_id() then
    raise exception 'You cannot review yourself' using errcode = '42501';
  end if;
  if not private.can_score_employee(p_employee_id)
     or not exists (select 1 from public.employees where id = p_employee_id and org_id = v_org_id and status = 'active') then
    raise exception 'You can score only the people in your team' using errcode = '42501';
  end if;

  select * into v_review from public.performance_reviews where cycle_id = p_cycle_id and employee_id = p_employee_id for update;
  if found and v_review.status <> 'draft' then
    raise exception 'This review was already submitted' using errcode = '22023';
  end if;
  if not found then
    insert into public.performance_reviews (org_id, cycle_id, employee_id, reviewer_user_id)
    values (v_org_id, p_cycle_id, p_employee_id, auth.uid())
    returning * into v_review;
  end if;

  for v_score in select * from jsonb_array_elements(coalesce(p -> 'scores', '[]'::jsonb)) loop
    if not exists (select 1 from public.performance_criteria
                   where id = (v_score ->> 'criterion_id')::uuid and cycle_id = p_cycle_id and status = 'active') then
      raise exception 'Criterion not found' using errcode = 'P0002';
    end if;
    if (v_score ->> 'score') is null then
      delete from public.performance_scores
       where review_id = v_review.id and criterion_id = (v_score ->> 'criterion_id')::uuid;
      continue;
    end if;
    if (v_score ->> 'score')::numeric not in (1, 2, 3, 4, 5) then
      raise exception 'Scores are whole numbers from 1 to 5' using errcode = '22023';
    end if;
    insert into public.performance_scores (org_id, review_id, criterion_id, score, comment)
    values (v_org_id, v_review.id, (v_score ->> 'criterion_id')::uuid, (v_score ->> 'score')::smallint,
            nullif(left(btrim(v_score ->> 'comment'), 500), ''))
    on conflict (review_id, criterion_id) do update set score = excluded.score, comment = excluded.comment;
  end loop;

  select count(*) into v_missing
  from public.performance_criteria cr
  where cr.cycle_id = p_cycle_id and cr.status = 'active'
    and not exists (select 1 from public.performance_scores s where s.review_id = v_review.id and s.criterion_id = cr.id);
  if v_submit and v_missing > 0 then
    raise exception 'Score every criterion before submitting (% left)', v_missing using errcode = '23502';
  end if;

  -- Weighted average over the scored criteria (all of them once submitted).
  select round(sum(s.score * cr.weight) / nullif(sum(cr.weight), 0), 2) into v_overall
  from public.performance_scores s join public.performance_criteria cr on cr.id = s.criterion_id and cr.status = 'active'
  where s.review_id = v_review.id;

  update public.performance_reviews
     set overall_score = v_overall, rating = private.performance_rating(v_overall),
         strengths = nullif(left(btrim(p ->> 'strengths'), 1000), ''),
         improvements = nullif(left(btrim(p ->> 'improvements'), 1000), ''),
         reviewer_user_id = auth.uid(),
         status = case when v_submit then 'submitted' else 'draft' end,
         submitted_at = case when v_submit then now() end
   where id = v_review.id;
  return private.performance_review_detail(p_cycle_id, p_employee_id);
end;
$$;

create or replace function public.list_my_performance_reviews()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(private.performance_review_detail(r.cycle_id, r.employee_id) order by c.period_from desc), '[]'::jsonb)
  from public.performance_reviews r
  join public.performance_cycles c on c.id = r.cycle_id
  where r.employee_id = private.current_employee_id() and r.org_id = private.current_org_id()
    and r.status in ('submitted', 'acknowledged')
$$;

create or replace function public.acknowledge_performance_review(p_review_id uuid, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review public.performance_reviews;
begin
  select * into v_review from public.performance_reviews
   where id = p_review_id and org_id = private.current_org_id() for update;
  if not found or v_review.employee_id is distinct from private.current_employee_id() then
    raise exception 'Review not found' using errcode = 'P0002';
  end if;
  if v_review.status <> 'submitted' then
    raise exception 'Only a submitted review can be acknowledged' using errcode = '22023';
  end if;
  update public.performance_reviews
     set status = 'acknowledged', acknowledged_at = now(),
         employee_comment = nullif(left(btrim(p_comment), 1000), '')
   where id = p_review_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges: tables closed, functions only
-- -----------------------------------------------------------------------------
alter table public.performance_cycles   enable row level security;
alter table public.performance_criteria enable row level security;
alter table public.performance_reviews  enable row level security;
alter table public.performance_scores   enable row level security;
revoke all on table public.performance_cycles, public.performance_criteria, public.performance_reviews,
                    public.performance_scores from anon, authenticated;

revoke all on function
  public.save_performance_cycle(uuid, jsonb), public.set_performance_cycle_status(uuid, text),
  public.list_performance_cycles(), public.get_performance_cycle(uuid), public.get_performance_review(uuid, uuid),
  public.save_performance_review(uuid, uuid, jsonb), public.list_my_performance_reviews(),
  public.acknowledge_performance_review(uuid, text)
from public, anon;
grant execute on function
  public.save_performance_cycle(uuid, jsonb), public.set_performance_cycle_status(uuid, text),
  public.list_performance_cycles(), public.get_performance_cycle(uuid), public.get_performance_review(uuid, uuid),
  public.save_performance_review(uuid, uuid, jsonb), public.list_my_performance_reviews(),
  public.acknowledge_performance_review(uuid, text)
to authenticated;

revoke all on function
  private.seed_performance_defaults(uuid), private.seed_org_defaults(uuid), private.performance_rating(numeric),
  private.can_score_employee(uuid), private.performance_review_detail(uuid, uuid)
from public, anon, authenticated;
