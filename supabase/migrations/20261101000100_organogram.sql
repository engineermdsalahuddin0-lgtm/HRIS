-- =============================================================================
-- Department organogram: positions driven by the headcount budget.
-- Handbook: src/onboarding-process/architecture.md (Organogram section).
--
-- Grades for the chart live in their own table (CEO > ED > GM > DGM > AGM >
-- Senior Executive > Executive > Junior Executive by default; each company can
-- edit them). A designation points to one organogram grade.
-- Per department HR sets the approved headcount budget and the slots per
-- grade. The tree is made of POSITIONS, not people: a position stays when its
-- holder leaves. States (computed when read):
--   filled          an active employee sits in a planned position
--   extra           an active employee above the grade's planned slots
--   vacant          planned, open to hire, nobody yet
--   in_recruitment  vacant and covered by an approved requisition (stage, candidates)
--   blocked         planned but frozen (per-slot toggle vacant <-> blocked)
-- Positions are kept in step automatically (employee joins / leaves / moves,
-- designation remapped, slots changed): people fill planned open slots of
-- their grade first; beyond that an extra position is created; a leaver's
-- position goes back to vacant or blocked (department setting).
-- Hard rule: filled + offers in process never exceed the approved budget
-- (checked whenever an offer is created, approved, sent or accepted).
-- The budget is now the single source of a department's sanctioned headcount
-- (R1 workload, vacancy drafting and approval read it); designation plans stay
-- only as an optional breakdown.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.onboarding_cases') is null then
    raise exception 'Apply 20261031000100_recruit_r7_joining.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.organogram_grades (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  code       text not null check (code ~ '^[A-Z0-9]{2,12}$'),
  name       text not null check (char_length(btrim(name)) between 2 and 60),
  rank       smallint not null check (rank between 1 and 99),   -- 1 = top
  status     text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  constraint organogram_grades_org_id_id_uq unique (org_id, id),
  constraint organogram_grades_code_uq unique (org_id, code)
);
select private.attach_standard_triggers('public.organogram_grades');

alter table public.designations add column organogram_grade_id uuid;
alter table public.designations add constraint designations_organogram_grade_fk
  foreign key (org_id, organogram_grade_id) references public.organogram_grades (org_id, id);

create table public.department_budgets (
  department_id      uuid primary key,
  org_id             uuid not null,
  approved_headcount integer not null check (approved_headcount between 0 and 100000),
  after_separation   text not null default 'vacant' check (after_separation in ('vacant', 'blocked')),
  note               text check (note is null or char_length(note) <= 500),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint department_budgets_department_fk foreign key (org_id, department_id) references public.departments (org_id, id)
);
select private.attach_standard_triggers('public.department_budgets');

create table public.grade_slots (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  department_id uuid not null,
  grade_id      uuid not null,
  planned       integer not null check (planned between 0 and 10000),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint grade_slots_uq unique (department_id, grade_id),
  constraint grade_slots_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint grade_slots_grade_fk foreign key (org_id, grade_id) references public.organogram_grades (org_id, id)
);
create trigger set_row_meta before insert or update on public.grade_slots
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.grade_slots
  for each row execute function private.audit_row_change();

-- Positions are maintained by private.sync_department_positions; rows may be deleted (empty surplus / extras).
create table public.positions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  department_id uuid not null,
  grade_id      uuid not null,
  slot_no       integer not null,
  kind          text not null check (kind in ('planned', 'extra')),
  hold_state    text not null default 'open' check (hold_state in ('open', 'blocked')),
  employee_id   uuid unique,
  filled_since  date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint positions_slot_uq unique (department_id, grade_id, kind, slot_no),
  constraint positions_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint positions_grade_fk foreign key (org_id, grade_id) references public.organogram_grades (org_id, id),
  constraint positions_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint positions_extra_filled check (kind = 'planned' or employee_id is not null)
);
create index positions_department_idx on public.positions (department_id, grade_id);
create trigger audit after insert or update or delete on public.positions
  for each row execute function private.audit_row_change();

-- -----------------------------------------------------------------------------
-- Defaults
-- -----------------------------------------------------------------------------
create or replace function private.seed_organogram_defaults(p_org_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.organogram_grades (org_id, code, name, rank) values
    (p_org_id, 'CEO', 'CEO', 1), (p_org_id, 'ED', 'ED', 2), (p_org_id, 'GM', 'GM', 3), (p_org_id, 'DGM', 'DGM', 4),
    (p_org_id, 'AGM', 'AGM', 5), (p_org_id, 'SREXEC', 'Senior Executive', 6), (p_org_id, 'EXEC', 'Executive', 7),
    (p_org_id, 'JREXEC', 'Junior Executive', 8)
  on conflict (org_id, code) do nothing
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
end;
$$;

select private.seed_organogram_defaults(id) from public.organizations;

-- The budget starts from the existing designation plans (one total per department).
insert into public.department_budgets (department_id, org_id, approved_headcount)
select hp.department_id, hp.org_id, sum(hp.sanctioned)::integer
from public.headcount_plans hp group by hp.department_id, hp.org_id
on conflict (department_id) do nothing;

-- -----------------------------------------------------------------------------
-- Counts and the hard budget rule
-- -----------------------------------------------------------------------------
-- Offers still on their way to a seat: approved, sent, or accepted but not yet joined.
create or replace function private.department_counts(p_department_id uuid, p_exclude_offer uuid default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with b as (select approved_headcount from public.department_budgets where department_id = p_department_id),
  f as (select count(*)::integer as filled from public.employees e
        where e.department_id = p_department_id and e.status = 'active'),
  o as (select count(*) filter (where o.status in ('approved', 'sent', 'accepted'))::integer as in_process,
               count(*) filter (where o.status = 'accepted')::integer as accepted
        from public.offers o
        where o.department_id = p_department_id and o.id is distinct from p_exclude_offer
          and not exists (select 1 from public.onboarding_cases c where c.offer_id = o.id))
  select jsonb_build_object(
    'budget', (select approved_headcount from b), 'filled', f.filled, 'offers_in_process', o.in_process,
    'offers_accepted', o.accepted,
    'available', (select approved_headcount from b) - f.filled - o.in_process,
    'headroom', (select approved_headcount from b) - f.filled - o.accepted)
  from f, o
$$;

-- Offers count against the budget from the moment they exist; refuses one more than the budget allows.
create or replace function private.offer_budget_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_c     jsonb;
  v_name  text;
begin
  if tg_op = 'UPDATE' and (new.status = old.status or new.status not in ('approved', 'sent', 'accepted')) then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status in ('approved', 'sent') and new.status in ('sent', 'accepted') then
    return new;   -- already counted
  end if;
  if not exists (select 1 from public.department_budgets where department_id = new.department_id) then
    return new;
  end if;
  v_c := private.department_counts(new.department_id, new.id);
  if (v_c ->> 'available')::integer < 1 then
    select d.name into v_name from public.departments d where d.id = new.department_id;
    raise exception 'Headcount budget of % is full: % approved, % filled, % offer(s) in process. Raise the budget or free a seat first.',
      v_name, v_c ->> 'budget', v_c ->> 'filled', v_c ->> 'offers_in_process' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger offer_budget_guard before insert or update of status on public.offers
  for each row execute function private.offer_budget_guard();

-- -----------------------------------------------------------------------------
-- Keeping positions in step with people and slots
-- -----------------------------------------------------------------------------
create or replace function private.sync_department_positions(p_department_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_b     public.department_budgets;
  v_slot  record;
  v_have  integer;
  v_e     record;
  v_pos   uuid;
  v_x     record;
begin
  select * into v_b from public.department_budgets where department_id = p_department_id;
  if not found then
    return;
  end if;

  -- 1. Release people who left, moved away or changed grade. A planned position takes the
  --    department's after-separation state; an extra position disappears.
  update public.positions p
     set employee_id = null, filled_since = null, updated_at = now(),
         hold_state = case when v_b.after_separation = 'blocked' then 'blocked' else 'open' end
   where p.department_id = p_department_id and p.kind = 'planned' and p.employee_id is not null
     and not exists (select 1 from public.employees e join public.designations ds on ds.id = e.designation_id
                     where e.id = p.employee_id and e.status = 'active' and e.department_id = p_department_id
                       and ds.organogram_grade_id = p.grade_id);
  delete from public.positions p
   where p.department_id = p_department_id and p.kind = 'extra'
     and not exists (select 1 from public.employees e join public.designations ds on ds.id = e.designation_id
                     where e.id = p.employee_id and e.status = 'active' and e.department_id = p_department_id
                       and ds.organogram_grade_id = p.grade_id);

  -- 2. Planned positions = planned slots per grade. Surplus: empty ones go (highest first), filled ones become extra.
  for v_slot in
    select g.id as grade_id, coalesce(s.planned, 0) as planned
    from public.organogram_grades g
    left join public.grade_slots s on s.grade_id = g.id and s.department_id = p_department_id
    where g.org_id = v_b.org_id
  loop
    select count(*) into v_have from public.positions
     where department_id = p_department_id and grade_id = v_slot.grade_id and kind = 'planned';
    if v_have < v_slot.planned then
      insert into public.positions (org_id, department_id, grade_id, slot_no, kind)
      select v_b.org_id, p_department_id, v_slot.grade_id, n, 'planned'
      from generate_series(1, v_slot.planned) n
      where not exists (select 1 from public.positions p where p.department_id = p_department_id
                        and p.grade_id = v_slot.grade_id and p.kind = 'planned' and p.slot_no = n)
      limit v_slot.planned - v_have;
    elsif v_have > v_slot.planned then
      delete from public.positions where id in (
        select id from public.positions
        where department_id = p_department_id and grade_id = v_slot.grade_id and kind = 'planned' and employee_id is null
        order by slot_no desc limit v_have - v_slot.planned);
      for v_x in
        select id from public.positions
        where department_id = p_department_id and grade_id = v_slot.grade_id and kind = 'planned'
        order by slot_no desc
        limit greatest((select count(*) from public.positions where department_id = p_department_id
                        and grade_id = v_slot.grade_id and kind = 'planned') - v_slot.planned, 0)
      loop
        update public.positions
           set kind = 'extra', updated_at = now(),
               slot_no = coalesce((select max(slot_no) from public.positions where department_id = p_department_id
                                   and grade_id = v_slot.grade_id and kind = 'extra'), 0) + 1
         where id = v_x.id;
      end loop;
      -- Renumber the remaining planned slots 1..n.
      update public.positions p set slot_no = r.n
        from (select id, row_number() over (order by slot_no) as n from public.positions
              where department_id = p_department_id and grade_id = v_slot.grade_id and kind = 'planned') r
       where p.id = r.id and p.slot_no <> r.n;
    end if;
  end loop;

  -- 3. Extras move into a planned open slot of their grade when one is free.
  for v_x in
    select p.id, p.grade_id, p.employee_id, p.filled_since from public.positions p
    where p.department_id = p_department_id and p.kind = 'extra' order by p.slot_no
  loop
    select id into v_pos from public.positions
     where department_id = p_department_id and grade_id = v_x.grade_id and kind = 'planned'
       and employee_id is null and hold_state = 'open'
     order by slot_no limit 1;
    if v_pos is not null then
      delete from public.positions where id = v_x.id;
      update public.positions set employee_id = v_x.employee_id, filled_since = v_x.filled_since, updated_at = now() where id = v_pos;
    end if;
  end loop;

  -- 4. Seat everyone of the department who has an organogram grade and no position yet.
  for v_e in
    select e.id, e.join_date, ds.organogram_grade_id as grade_id
    from public.employees e join public.designations ds on ds.id = e.designation_id
    where e.department_id = p_department_id and e.status = 'active' and ds.organogram_grade_id is not null
      and not exists (select 1 from public.positions p where p.employee_id = e.id)
    order by e.join_date, e.id
  loop
    select id into v_pos from public.positions
     where department_id = p_department_id and grade_id = v_e.grade_id and kind = 'planned'
       and employee_id is null and hold_state = 'open'
     order by slot_no limit 1;
    if v_pos is not null then
      update public.positions set employee_id = v_e.id, filled_since = v_e.join_date, updated_at = now() where id = v_pos;
    else
      insert into public.positions (org_id, department_id, grade_id, slot_no, kind, employee_id, filled_since)
      values (v_b.org_id, p_department_id, v_e.grade_id,
              coalesce((select max(slot_no) from public.positions where department_id = p_department_id
                        and grade_id = v_e.grade_id and kind = 'extra'), 0) + 1,
              'extra', v_e.id, v_e.join_date);
    end if;
  end loop;
end;
$$;

create or replace function private.employees_organogram_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.department_id is distinct from new.department_id and old.department_id is not null then
    perform private.sync_department_positions(old.department_id);
  end if;
  if new.department_id is not null then
    perform private.sync_department_positions(new.department_id);
  end if;
  return null;
end;
$$;
create trigger organogram_sync after insert or update of status, department_id, designation_id on public.employees
  for each row execute function private.employees_organogram_sync();

create or replace function private.designations_organogram_sync()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_department_positions(new.department_id);
  return null;
end;
$$;
create trigger organogram_sync after update of organogram_grade_id on public.designations
  for each row execute function private.designations_organogram_sync();

-- -----------------------------------------------------------------------------
-- API
-- -----------------------------------------------------------------------------
create or replace function private.organogram_viewer(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('workforce.view') or private.has_permission('workforce.manage')
      or private.has_permission('headcount.manage') or private.has_permission('recruit.manage')
      or ((private.has_permission('vacancy.request') or private.has_permission('recruit.department'))
          and p_department_id is not distinct from (select e.department_id from public.employees e where e.id = private.current_employee_id()))
$$;

create or replace function public.list_organogram_grades()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  if not (private.has_permission('workforce.view') or private.has_permission('workforce.manage') or private.has_permission('headcount.manage')
          or private.has_permission('recruit.manage') or private.has_permission('vacancy.request')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  perform private.seed_organogram_defaults(v_org_id);
  return jsonb_build_object(
    'can', jsonb_build_object('manage', private.has_permission('headcount.manage')),
    'grades', (select jsonb_agg(jsonb_build_object('id', g.id, 'code', g.code, 'name', g.name, 'rank', g.rank, 'status', g.status,
                                                   'designations', (select count(*) from public.designations ds where ds.organogram_grade_id = g.id))
                                order by g.rank, g.name)
               from public.organogram_grades g where g.org_id = v_org_id),
    'designations', coalesce((select jsonb_agg(jsonb_build_object('id', ds.id, 'name', ds.name, 'department_id', d.id, 'department_name', d.name,
                                                                  'pay_grade', gr.code, 'organogram_grade_id', ds.organogram_grade_id)
                                               order by d.name, ds.name)
                              from public.designations ds join public.departments d on d.id = ds.department_id
                              join public.grades gr on gr.id = ds.grade_id
                              where ds.org_id = v_org_id and ds.status = 'active' and d.status = 'active'), '[]'::jsonb));
end;
$$;

-- p: code, name, rank, status. p_id null = new grade.
create or replace function public.save_organogram_grade(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_code   text := upper(btrim(coalesce(p ->> 'code', '')));
  v_name   text := btrim(coalesce(p ->> 'name', ''));
  v_rank   integer := (private.jtext(p, 'rank'))::integer;
  v_status text := coalesce(p ->> 'status', 'active');
  v_id     uuid;
begin
  perform private.require_permission('headcount.manage');
  if v_code !~ '^[A-Z0-9]{2,12}$' then
    raise exception 'The code has 2 to 12 capital letters or digits' using errcode = '22023';
  end if;
  if char_length(v_name) not between 2 and 60 then
    raise exception 'Give the grade a name' using errcode = '22023';
  end if;
  if v_rank is null or v_rank not between 1 and 99 then
    raise exception 'Rank is 1 (top) to 99' using errcode = '22023';
  end if;
  if v_status not in ('active', 'inactive') then
    raise exception 'Status is active or inactive' using errcode = '22023';
  end if;
  if exists (select 1 from public.organogram_grades where org_id = v_org_id and code = v_code and id is distinct from p_id) then
    raise exception 'Another grade already uses the code %', v_code using errcode = '23505';
  end if;
  if v_status = 'inactive' and p_id is not null and (exists (select 1 from public.grade_slots where grade_id = p_id and planned > 0)
                                                     or exists (select 1 from public.positions where grade_id = p_id)) then
    raise exception 'This grade still has slots or positions; move them first' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.organogram_grades (org_id, code, name, rank, status) values (v_org_id, v_code, v_name, v_rank, v_status)
    returning id into v_id;
  else
    update public.organogram_grades set code = v_code, name = v_name, rank = v_rank, status = v_status
     where id = p_id and org_id = v_org_id returning id into v_id;
    if v_id is null then
      raise exception 'Grade not found' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.set_designation_organogram_grade(p_designation_id uuid, p_grade_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('headcount.manage');
  if p_grade_id is not null and not exists (select 1 from public.organogram_grades where id = p_grade_id and org_id = private.current_org_id()
                                            and status = 'active') then
    raise exception 'Choose an active organogram grade' using errcode = '22023';
  end if;
  update public.designations set organogram_grade_id = p_grade_id where id = p_designation_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Designation not found' using errcode = 'P0002';
  end if;
end;
$$;

-- Every department with its budget numbers (for the picker and the overview).
create or replace function public.list_department_budgets()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'department_id', d.id, 'name', d.name, 'has_budget', b.department_id is not null,
      'slots', (select coalesce(sum(s.planned), 0) from public.grade_slots s where s.department_id = d.id),
      'counts', private.department_counts(d.id)) order by d.name)
    from public.departments d left join public.department_budgets b on b.department_id = d.id
    where d.org_id = v_org_id and d.status = 'active' and private.organogram_viewer(d.id)), '[]'::jsonb);
end;
$$;

-- The tree of one department: every position with its state, plus the numbers.
create or replace function public.get_department_organogram(p_department_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_d public.departments;
  v_b public.department_budgets;
begin
  select * into v_d from public.departments where id = p_department_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if not private.organogram_viewer(v_d.id) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  select * into v_b from public.department_budgets where department_id = v_d.id;
  return jsonb_build_object(
    'department', jsonb_build_object('id', v_d.id, 'name', v_d.name,
                                     'head', (select jsonb_build_object('id', e.id, 'full_name', e.full_name) from public.employees e where e.id = v_d.head_employee_id)),
    'can', jsonb_build_object('budget', private.has_permission('headcount.manage'),
                              'toggle', private.has_permission('headcount.manage') or private.has_permission('workforce.manage')),
    'budget', case when v_b.department_id is null then null else jsonb_build_object(
                'approved_headcount', v_b.approved_headcount, 'after_separation', v_b.after_separation, 'note', v_b.note,
                'updated_at', v_b.updated_at) end,
    'counts', private.department_counts(v_d.id),
    'grades', (
      with g as (select * from public.organogram_grades where org_id = v_d.org_id and status = 'active'),
      -- Seats being recruited per grade: approved requisitions not yet joined.
      rec as (
        select ds.organogram_grade_id as grade_id, v.id as vacancy_id, v.seats,
               jp.id as post_id, jp.title, jp.status as post_status,
               (select count(*) from public.applicants a where a.job_post_id = jp.id and a.purged_at is null
                  and a.status not in ('screened_out', 'rejected', 'offer_declined', 'purged', 'joined')) as candidates,
               (select count(*) from public.applicants a where a.job_post_id = jp.id and a.status = 'joined') as joined,
               (select max(case a.status when 'applied' then 1 when 'shortlisted' then 2 when 'test_invited' then 3 when 'test_done' then 3
                                         when 'written_done' then 3 when 'interview_scheduled' then 4 when 'interviewed' then 4
                                         when 'selected' then 5 when 'offer_sent' then 5 when 'offer_accepted' then 6
                                         when 'prejoining_done' then 6 else 0 end)
                  from public.applicants a where a.job_post_id = jp.id and a.purged_at is null) as stage_no
        from public.vacancies v
        join public.designations ds on ds.id = v.designation_id
        left join public.job_posts jp on jp.vacancy_id = v.id
        where v.department_id = v_d.id and v.status = 'approved' and ds.organogram_grade_id is not null),
      pos as (
        select p.*, row_number() over (partition by p.grade_id, (p.employee_id is null and p.hold_state = 'open' and p.kind = 'planned')
                                       order by p.slot_no) as free_no
        from public.positions p where p.department_id = v_d.id)
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'code', g.code, 'name', g.name, 'rank', g.rank,
        'planned', coalesce((select s.planned from public.grade_slots s where s.department_id = v_d.id and s.grade_id = g.id), 0),
        'positions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', p.id, 'slot_no', p.slot_no, 'kind', p.kind, 'hold_state', p.hold_state,
            'state', case
              when p.employee_id is not null and p.kind = 'extra' then 'extra'
              when p.employee_id is not null then 'filled'
              when p.hold_state = 'blocked' then 'blocked'
              when p.free_no <= coalesce((select sum(greatest(r.seats - r.joined, 0)) from rec r where r.grade_id = g.id), 0) then 'in_recruitment'
              else 'vacant' end,
            'employee', (select jsonb_build_object('id', e.id, 'full_name', e.full_name, 'card_id', e.card_id, 'designation', ds.name,
                                                   'join_date', e.join_date)
                         from public.employees e left join public.designations ds on ds.id = e.designation_id where e.id = p.employee_id),
            'recruitment', case when p.employee_id is null and p.hold_state = 'open' and p.kind = 'planned' then (
              select jsonb_build_object('vacancy_id', r.vacancy_id, 'post_id', r.post_id, 'title', r.title, 'candidates', r.candidates,
                                        'stage', case when r.post_id is null then 'Requisition approved'
                                                      when r.post_status = 'draft' then 'Job post draft'
                                                      else (array['Applications open', 'Applications', 'Shortlisted', 'Tests', 'Interviews', 'Offer', 'Joining'])[coalesce(r.stage_no, 0) + 1] end)
              from rec r where r.grade_id = g.id and r.seats > r.joined order by r.vacancy_id limit 1) end)
            order by p.kind desc, p.slot_no)
          from pos p where p.grade_id = g.id), '[]'::jsonb))
        order by g.rank), '[]'::jsonb)
      from g),
    'unmapped', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'full_name', e.full_name, 'designation', ds.name) order by e.full_name)
                          from public.employees e left join public.designations ds on ds.id = e.designation_id
                          where e.department_id = v_d.id and e.status = 'active' and ds.organogram_grade_id is null), '[]'::jsonb));
end;
$$;

-- p: approved_headcount, after_separation (vacant | blocked), note, slots [{grade_id, planned}].
create or replace function public.save_department_budget(p_department_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id   uuid := private.current_org_id();
  v_approved integer := (private.jtext(p, 'approved_headcount'))::integer;
  v_after    text := coalesce(p ->> 'after_separation', 'vacant');
  v_row      jsonb;
  v_total    integer := 0;
  v_c        jsonb;
  v_planned  integer;
begin
  perform private.require_permission('headcount.manage');
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org_id) then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if v_approved is null or v_approved not between 0 and 100000 then
    raise exception 'Enter the approved headcount (0 or more)' using errcode = '22023';
  end if;
  if v_after not in ('vacant', 'blocked') then
    raise exception 'After a separation the position becomes vacant or blocked' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p -> 'slots', '[]')) <> 'array' then
    raise exception 'Send the slots as a list' using errcode = '22023';
  end if;
  for v_row in select * from jsonb_array_elements(coalesce(p -> 'slots', '[]')) loop
    v_planned := (v_row ->> 'planned')::integer;
    if v_planned is null or v_planned not between 0 and 10000 then
      raise exception 'Slots per grade are whole numbers from 0' using errcode = '22023';
    end if;
    if not exists (select 1 from public.organogram_grades where id = (v_row ->> 'grade_id')::uuid and org_id = v_org_id and status = 'active') then
      raise exception 'Unknown organogram grade' using errcode = '22023';
    end if;
    v_total := v_total + v_planned;
  end loop;
  if v_total > v_approved then
    raise exception 'The grade slots add up to %, more than the approved headcount of %', v_total, v_approved using errcode = '23514';
  end if;
  v_c := private.department_counts(p_department_id);
  if v_approved < (v_c ->> 'filled')::integer + (v_c ->> 'offers_in_process')::integer then
    raise exception 'The budget cannot go below % filled + % offer(s) in process', v_c ->> 'filled', v_c ->> 'offers_in_process'
      using errcode = '23514';
  end if;

  insert into public.department_budgets (department_id, org_id, approved_headcount, after_separation, note)
  values (p_department_id, v_org_id, v_approved, v_after, left(nullif(btrim(coalesce(p ->> 'note', '')), ''), 500))
  on conflict (department_id) do update
    set approved_headcount = excluded.approved_headcount, after_separation = excluded.after_separation, note = excluded.note;
  for v_row in select * from jsonb_array_elements(coalesce(p -> 'slots', '[]')) loop
    insert into public.grade_slots (org_id, department_id, grade_id, planned)
    values (v_org_id, p_department_id, (v_row ->> 'grade_id')::uuid, (v_row ->> 'planned')::integer)
    on conflict (department_id, grade_id) do update set planned = excluded.planned;
  end loop;
  perform private.sync_department_positions(p_department_id);
  return private.department_counts(p_department_id);
end;
$$;

-- Per-slot toggle: an empty planned position is open to hire (vacant) or frozen (blocked).
create or replace function public.set_position_hold(p_position_id uuid, p_state text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_p public.positions;
begin
  if not (private.has_permission('headcount.manage') or private.has_permission('workforce.manage')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  select * into v_p from public.positions where id = p_position_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Position not found' using errcode = 'P0002';
  end if;
  if v_p.employee_id is not null or v_p.kind <> 'planned' then
    raise exception 'Only an empty planned position can be opened or blocked' using errcode = '22023';
  end if;
  if p_state not in ('vacant', 'blocked') then
    raise exception 'State is vacant or blocked' using errcode = '22023';
  end if;
  update public.positions set hold_state = case when p_state = 'blocked' then 'blocked' else 'open' end, updated_at = now()
   where id = v_p.id;
  perform private.sync_department_positions(v_p.department_id);
end;
$$;

-- Bulk: block every empty open slot of a grade (or the whole department), or open every blocked one.
create or replace function public.set_department_holds(p_department_id uuid, p_state text, p_grade_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not (private.has_permission('headcount.manage') or private.has_permission('workforce.manage')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  if p_state not in ('vacant', 'blocked') then
    raise exception 'State is vacant or blocked' using errcode = '22023';
  end if;
  update public.positions set hold_state = case when p_state = 'blocked' then 'blocked' else 'open' end, updated_at = now()
   where department_id = p_department_id and org_id = private.current_org_id() and kind = 'planned' and employee_id is null
     and (p_grade_id is null or grade_id = p_grade_id)
     and hold_state = case when p_state = 'blocked' then 'open' else 'blocked' end;
  get diagnostics v_count = row_count;
  perform private.sync_department_positions(p_department_id);
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- R1 now reads the department budget (single source of the sanctioned headcount)
-- -----------------------------------------------------------------------------
-- Sanctioned headcount of a department: the budget; departments without one fall back to their designation plans.
create or replace function private.department_sanctioned(p_department_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b.approved_headcount from public.department_budgets b where b.department_id = p_department_id),
                  (select sum(hp.sanctioned)::integer from public.headcount_plans hp where hp.department_id = p_department_id), 0)
$$;

-- R1 function, sanctioned now from the budget (the rest is unchanged).
create or replace function private.department_workload(p_org_id uuid, p_department_id uuid, p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings     public.workforce_settings;
  v_config       public.department_workforce;
  v_method       text;
  v_month_end    date := (p_month + interval '1 month' - interval '1 day')::date;
  v_window_start date := (p_month - interval '2 months')::date;
  v_active       integer;
  v_org_people   integer;
  v_sanctioned   integer;
  v_separations  integer;
  v_avg          numeric;
  v_scheduled    numeric;
  v_lost         numeric;
  v_availability numeric;
  v_capacity     numeric;
  v_regular_min  numeric := 0;
  v_overtime_min numeric := 0;
  v_demand       numeric;
  v_prior        integer := 0;
  v_check        date := (p_month - interval '1 month')::date;
  v_band         text;
  v_payroll      numeric;
  v_budget_left  numeric;
begin
  select * into v_settings from public.workforce_settings where org_id = p_org_id;
  if not found then
    raise exception 'Workforce settings are missing' using errcode = 'P0002';
  end if;
  select * into v_config from public.department_workforce where department_id = p_department_id;
  v_method := coalesce(v_config.method, 'hours');

  v_active := private.headcount_on(p_org_id, p_department_id, null, v_month_end);
  v_org_people := private.headcount_on(p_org_id, null, null, v_month_end);
  v_sanctioned := private.department_sanctioned(p_department_id);
  select count(*) into v_separations from public.employees e
   where e.org_id = p_org_id and e.department_id = p_department_id and e.exit_date between v_window_start and v_month_end;
  v_avg := round((private.headcount_on(p_org_id, p_department_id, null, (v_window_start + interval '1 month' - interval '1 day')::date)
                  + private.headcount_on(p_org_id, p_department_id, null, (p_month - interval '1 day')::date)
                  + v_active)::numeric / 3, 2);

  if v_settings.availability_source = 'fixed' then
    v_availability := round(v_settings.fixed_availability_percent / 100, 4);
  else
    select count(*) filter (where r.day_type = 'workday'),
           coalesce(sum(case when r.day_type <> 'workday' then 0
                             when r.status in ('absent', 'on_leave') then 1
                             when r.status = 'half_day' then 0.5 else 0 end), 0)
      into v_scheduled, v_lost
    from public.attendance_records r
    join public.employees e on e.id = r.employee_id
    where r.org_id = p_org_id and e.department_id = p_department_id
      and r.work_date between v_window_start and v_month_end;
    v_availability := case when v_scheduled > 0 then greatest(round(1 - v_lost / v_scheduled, 4), 0.05) else 1 end;
  end if;
  v_capacity := round(v_settings.capacity_hours * v_availability, 2);

  if v_method in ('output_smv', 'volume_std') then
    select coalesce(sum(i.quantity * i.std_minutes), 0) / 60 into v_demand
    from public.workload_inputs i where i.department_id = p_department_id and i.period_month = p_month;
  elsif v_method = 'ratio' then
    v_demand := v_org_people::numeric / v_config.per_employees * v_capacity;
  else
    select coalesce(sum(greatest(r.worked_minutes - r.overtime_minutes, 0)), 0) into v_regular_min
    from public.attendance_records r join public.employees e on e.id = r.employee_id
    where r.org_id = p_org_id and e.department_id = p_department_id and r.work_date between p_month and v_month_end;
    select coalesce(sum(o.minutes), 0) into v_overtime_min
    from public.overtime_records o join public.employees e on e.id = o.employee_id
    where o.org_id = p_org_id and e.department_id = p_department_id and o.status = 'approved'
      and o.work_date between p_month and v_month_end;
    v_demand := (v_regular_min + v_overtime_min) / 60;
  end if;

  loop
    select s.band into v_band from public.workload_snapshots s
     where s.department_id = p_department_id and s.period_month = v_check;
    exit when not found or v_band not in ('overload', 'critical') or v_prior >= 12;
    v_prior := v_prior + 1;
    v_check := (v_check - interval '1 month')::date;
  end loop;

  select coalesce(sum(c.gross), 0) into v_payroll
  from public.employees e
  join public.employee_compensation c
    on c.employee_id = e.id and c.effective_from <= v_month_end and (c.effective_to is null or c.effective_to >= v_month_end)
  where e.org_id = p_org_id and e.department_id = p_department_id
    and e.join_date <= v_month_end and (e.exit_date is null or e.exit_date > v_month_end);
  v_budget_left := case when v_config.monthly_budget is not null then v_config.monthly_budget - v_payroll end;

  return private.workload_figures(jsonb_build_object(
           'demand_hours', v_demand, 'capacity_per_fte', v_capacity, 'active', v_active, 'sanctioned', v_sanctioned,
           'separations', v_separations, 'avg_headcount', v_avg, 'prior_overload_months', v_prior,
           'cost_per_seat', private.average_gross(p_org_id, p_department_id, null, v_month_end),
           'budget_remaining', v_budget_left,
           'bands', jsonb_build_object('underload', v_settings.band_underload, 'watch', v_settings.band_watch,
                                       'overload', v_settings.band_overload, 'critical', v_settings.band_critical,
                                       'sustain_months', v_settings.sustain_months,
                                       'attrition_flag_percent', v_settings.attrition_flag_percent)))
         || jsonb_build_object(
           'period_month', p_month, 'method', v_method, 'availability', v_availability,
           'capacity_hours_setting', v_settings.capacity_hours, 'availability_source', v_settings.availability_source,
           'scheduled_workdays', v_scheduled, 'lost_workdays', v_lost,
           'regular_hours', round(v_regular_min / 60, 2), 'overtime_hours', round(v_overtime_min / 60, 2),
           'org_headcount', v_org_people, 'per_employees', v_config.per_employees,
           'monthly_budget', v_config.monthly_budget, 'department_payroll', v_payroll);
end;
$$;

-- R1 function: designation plans stay as a breakdown; the department budget follows their total while a
-- department is managed this way. (The organogram page edits the budget directly.)
create or replace function public.save_headcount_plan(p_department_id uuid, p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_row    jsonb;
  v_count  integer;
begin
  perform private.require_permission('headcount.manage');
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org_id) then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Send the plan as a list' using errcode = '22023';
  end if;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    if not exists (select 1 from public.designations
                   where id = (v_row ->> 'designation_id')::uuid and department_id = p_department_id and org_id = v_org_id) then
      raise exception 'Designation not found in this department' using errcode = 'P0002';
    end if;
    v_count := (v_row ->> 'sanctioned')::integer;
    if v_count is null or v_count not between 0 and 10000 then
      raise exception 'Sanctioned positions must be a whole number from 0 to 10,000' using errcode = '22023';
    end if;
    insert into public.headcount_plans (org_id, department_id, designation_id, sanctioned)
    values (v_org_id, p_department_id, (v_row ->> 'designation_id')::uuid, v_count)
    on conflict (designation_id) do update set sanctioned = excluded.sanctioned;
  end loop;
  insert into public.department_budgets (department_id, org_id, approved_headcount)
  values (p_department_id, v_org_id, (select coalesce(sum(sanctioned), 0) from public.headcount_plans where department_id = p_department_id))
  on conflict (department_id) do update set approved_headcount = excluded.approved_headcount;
  perform private.sync_department_positions(p_department_id);
end;
$$;

-- R1 trigger: a leaver's replacement is drafted when the department has a budget (or a designation plan)
-- and the freed position is not set to become blocked.
create or replace function private.on_employee_separation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gross numeric;
  v_after text;
begin
  if old.status = 'active' and new.status in ('inactive', 'terminated') and new.designation_id is not null then
    select b.after_separation into v_after from public.department_budgets b where b.department_id = new.department_id;
    if (v_after = 'vacant' or (v_after is null and exists (select 1 from public.headcount_plans hp where hp.designation_id = new.designation_id))) then
      select c.gross into v_gross from public.employee_compensation c where c.employee_id = new.id and c.effective_to is null;
      perform private.insert_vacancy(new.org_id, new.department_id, new.designation_id, new.office_id, 1,
                                     'replacement', 'separation', new.id, null,
                                     date_trunc('month', coalesce(new.exit_date, current_date))::date, v_gross, 'unknown',
                                     null, 'Drafted automatically when the position holder left');
    end if;
  end if;
  return new;
end;
$$;

-- R1 function: approving a new position raises the department budget (and the grade slot of the designation).
create or replace function public.decide_vacancy(p_vacancy_id uuid, p_decision text, p_note text default null,
                                                 p_over_budget boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_vac   public.vacancies;
  v_to    text;
  v_grade uuid;
begin
  perform private.require_permission('vacancy.approve');
  select * into v_vac from public.vacancies where id = p_vacancy_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Vacancy not found' using errcode = 'P0002';
  end if;
  if v_vac.status <> 'hr_reviewed' then
    raise exception 'Only a reviewed vacancy can be decided (now %)', v_vac.status using errcode = '22023';
  end if;
  if v_vac.hr_reviewed_by = auth.uid() then
    raise exception 'Someone other than the reviewer must decide this vacancy' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'hold', 'reject', 'send_back') then
    raise exception 'Decision must be approve, hold, reject or send back' using errcode = '22023';
  end if;
  if (p_decision <> 'approve' or coalesce(p_over_budget, false)) and char_length(btrim(coalesce(p_note, ''))) < 5 then
    raise exception 'Give a reason (at least 5 characters)' using errcode = '23502';
  end if;

  if p_decision = 'approve' then
    if v_vac.budget_status = 'blocked' and not coalesce(p_over_budget, false) then
      raise exception 'This vacancy is over the department budget; approve over budget with a reason' using errcode = '23514';
    end if;
    if v_vac.reason = 'new_position' then
      perform private.require_permission('headcount.manage');
      insert into public.headcount_plans (org_id, department_id, designation_id, sanctioned)
      values (v_vac.org_id, v_vac.department_id, v_vac.designation_id, v_vac.seats)
      on conflict (designation_id) do update set sanctioned = public.headcount_plans.sanctioned + excluded.sanctioned;
      insert into public.department_budgets (department_id, org_id, approved_headcount)
      values (v_vac.department_id, v_vac.org_id, private.department_sanctioned(v_vac.department_id) + v_vac.seats)
      on conflict (department_id) do update set approved_headcount = public.department_budgets.approved_headcount + v_vac.seats;
      select ds.organogram_grade_id into v_grade from public.designations ds where ds.id = v_vac.designation_id;
      if v_grade is not null then
        insert into public.grade_slots (org_id, department_id, grade_id, planned)
        values (v_vac.org_id, v_vac.department_id, v_grade, v_vac.seats)
        on conflict (department_id, grade_id) do update set planned = public.grade_slots.planned + excluded.planned;
      end if;
      perform private.sync_department_positions(v_vac.department_id);
    end if;
  end if;

  v_to := case p_decision when 'approve' then 'approved' when 'hold' then 'on_hold'
                          when 'reject' then 'rejected' else 'draft' end;
  update public.vacancies
     set status = v_to, decided_by = auth.uid(), decided_at = now(), decision_note = nullif(left(btrim(p_note), 500), '')
   where id = p_vacancy_id;
  perform private.vacancy_event(p_vacancy_id, case when p_decision = 'approve' and coalesce(p_over_budget, false)
                                                   then 'approved_over_budget' else p_decision end,
                                'hr_reviewed', v_to, p_note);
end;
$$;

-- Open sanctioned seats for a replacement: with a budget, the empty open positions of the designation's grade
-- (or the whole department's budget gap when the designation has no grade), minus replacements already open;
-- without a budget, the R1 designation plan.
create or replace function private.open_replacement_seats(p_department_id uuid, p_designation_id uuid, p_day date)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org   uuid;
  v_grade uuid;
  v_open  integer;
begin
  select org_id, organogram_grade_id into v_org, v_grade from public.designations where id = p_designation_id;
  if exists (select 1 from public.department_budgets where department_id = p_department_id) then
    if v_grade is not null then
      select count(*) into v_open from public.positions
       where department_id = p_department_id and grade_id = v_grade and kind = 'planned' and employee_id is null and hold_state = 'open';
      return v_open - coalesce((select sum(v.seats) from public.vacancies v join public.designations ds on ds.id = v.designation_id
                                where v.department_id = p_department_id and ds.organogram_grade_id = v_grade and v.reason = 'replacement'
                                  and v.status in ('draft', 'hr_reviewed', 'approved', 'on_hold')), 0);
    end if;
    return private.department_sanctioned(p_department_id) - private.headcount_on(v_org, p_department_id, null, p_day)
           - private.open_sanctioned_seats(p_department_id, null);
  end if;
  return coalesce((select hp.sanctioned from public.headcount_plans hp where hp.designation_id = p_designation_id), 0)
         - private.headcount_on(v_org, p_department_id, p_designation_id, p_day)
         - private.open_sanctioned_seats(p_department_id, p_designation_id);
end;
$$;

-- R1 function: the replacement check now uses private.open_replacement_seats (the rest is unchanged).
create or replace function public.draft_vacancy(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id      uuid := private.current_org_id();
  v_dept        uuid := (private.jtext(p, 'department_id'))::uuid;
  v_designation uuid := (private.jtext(p, 'designation_id'))::uuid;
  v_seats       integer := (private.jtext(p, 'seats'))::integer;
  v_reason      text := coalesce(private.jtext(p, 'reason'), 'replacement');
  v_today       date := private.org_today(v_org_id);
  v_open        integer;
  v_cost        numeric;
begin
  perform private.require_permission('vacancy.request');
  if not exists (select 1 from public.departments where id = v_dept and org_id = v_org_id and status = 'active') then
    raise exception 'Department not found' using errcode = 'P0002';
  end if;
  if not (private.has_permission('vacancy.review') or private.has_permission('workforce.view'))
     and v_dept is distinct from (select e.department_id from public.employees e where e.id = private.current_employee_id()) then
    raise exception 'You can request vacancies only for your own department' using errcode = '42501';
  end if;
  if not exists (select 1 from public.designations where id = v_designation and department_id = v_dept and status = 'active') then
    raise exception 'Pick a designation of this department' using errcode = '22023';
  end if;
  if v_seats is null or v_seats not between 1 and 500 then
    raise exception 'Seats must be between 1 and 500' using errcode = '22023';
  end if;
  if v_reason not in ('replacement', 'new_position') then
    raise exception 'Reason must be replacement or new position' using errcode = '22023';
  end if;
  if v_reason = 'replacement' then
    v_open := private.open_replacement_seats(v_dept, v_designation, v_today);
    if coalesce(v_open, 0) < v_seats then
      raise exception 'Only % sanctioned position(s) are open for this designation; draft a new position instead',
        greatest(coalesce(v_open, 0), 0) using errcode = '23514';
    end if;
  end if;
  v_cost := coalesce(private.average_gross(v_org_id, v_dept, v_designation, v_today),
                     private.average_gross(v_org_id, v_dept, null, v_today));
  return private.insert_vacancy(v_org_id, v_dept, v_designation, null, v_seats, v_reason, 'manual', null, null,
                                date_trunc('month', v_today)::date, v_cost, 'unknown',
                                (select s.figures from public.workload_snapshots s where s.department_id = v_dept
                                 order by s.period_month desc limit 1),
                                nullif(left(btrim(p ->> 'note'), 500), ''));
end;
$$;

-- R1 function: departments run by budget (no designation plans) draft their backfill on the designation
-- with the most open positions of its grade, else the one with the most people.
create or replace function private.draft_vacancies_from_snapshot(p_snapshot_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_snapshot    public.workload_snapshots;
  v_figures     jsonb;
  v_month_end   date;
  v_open        integer;
  v_pending_new integer;
  v_missing     integer;
  v_ok_left     integer;
  v_take        integer;
  v_drafted     integer := 0;
  v_row         record;
  v_designation uuid;
begin
  select * into v_snapshot from public.workload_snapshots where id = p_snapshot_id;
  v_figures := v_snapshot.figures;
  v_month_end := (v_snapshot.period_month + interval '1 month' - interval '1 day')::date;

  v_open := private.open_sanctioned_seats(v_snapshot.department_id, null);
  v_missing := (v_figures ->> 'backfill_seats')::integer - v_open;
  v_ok_left := (v_figures ->> 'budget_ok_backfill')::integer - v_open;
  if v_missing > 0 then
    for v_row in
      select ds.id as designation_id, private.open_replacement_seats(v_snapshot.department_id, ds.id, v_month_end) as open_positions
      from public.designations ds
      where ds.department_id = v_snapshot.department_id and ds.status = 'active'
        and (exists (select 1 from public.headcount_plans hp where hp.designation_id = ds.id)
             or exists (select 1 from public.department_budgets b where b.department_id = v_snapshot.department_id))
      order by 2 desc, private.headcount_on(v_snapshot.org_id, v_snapshot.department_id, ds.id, v_month_end) desc, ds.id
    loop
      exit when v_missing <= 0;
      continue when v_row.open_positions <= 0;
      v_take := least(v_row.open_positions, v_missing);
      v_drafted := v_drafted + private.draft_snapshot_seats(v_snapshot, v_row.designation_id, 'replacement', v_take, v_ok_left);
      v_ok_left := v_ok_left - v_take;
      v_missing := v_missing - v_take;
    end loop;
  end if;

  select coalesce(sum(v.seats), 0) into v_pending_new from public.vacancies v
   where v.department_id = v_snapshot.department_id and v.reason = 'new_position'
     and v.status in ('draft', 'hr_reviewed', 'on_hold');
  v_missing := (v_figures ->> 'new_positions')::integer - v_pending_new;
  if v_missing > 0 then
    select ds.id into v_designation
    from public.designations ds
    left join public.headcount_plans hp on hp.designation_id = ds.id
    where ds.department_id = v_snapshot.department_id and ds.status = 'active'
    order by (hp.id is not null) desc,
             private.headcount_on(v_snapshot.org_id, v_snapshot.department_id, ds.id, v_month_end) desc, ds.name
    limit 1;
    if v_designation is not null then
      v_drafted := v_drafted + private.draft_snapshot_seats(v_snapshot, v_designation, 'new_position', v_missing,
                                                             (v_figures ->> 'budget_ok_new')::integer - v_pending_new);
    end if;
  end if;
  return v_drafted;
end;
$$;

-- Build the positions of every department that already has a budget.
select private.sync_department_positions(department_id) from public.department_budgets;

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.organogram_grades  enable row level security;
alter table public.department_budgets enable row level security;
alter table public.grade_slots        enable row level security;
alter table public.positions          enable row level security;
revoke all on table public.organogram_grades, public.department_budgets, public.grade_slots, public.positions from anon, authenticated;

revoke all on function
  public.list_organogram_grades(), public.save_organogram_grade(uuid, jsonb), public.set_designation_organogram_grade(uuid, uuid),
  public.list_department_budgets(), public.get_department_organogram(uuid), public.save_department_budget(uuid, jsonb),
  public.set_position_hold(uuid, text), public.set_department_holds(uuid, text, uuid), public.save_headcount_plan(uuid, jsonb),
  public.decide_vacancy(uuid, text, text, boolean), public.draft_vacancy(jsonb)
from public, anon;
grant execute on function
  public.list_organogram_grades(), public.save_organogram_grade(uuid, jsonb), public.set_designation_organogram_grade(uuid, uuid),
  public.list_department_budgets(), public.get_department_organogram(uuid), public.save_department_budget(uuid, jsonb),
  public.set_position_hold(uuid, text), public.set_department_holds(uuid, text, uuid), public.save_headcount_plan(uuid, jsonb),
  public.decide_vacancy(uuid, text, text, boolean), public.draft_vacancy(jsonb)
to authenticated;

revoke all on function
  private.seed_organogram_defaults(uuid), private.seed_org_defaults(uuid), private.department_counts(uuid, uuid),
  private.offer_budget_guard(), private.sync_department_positions(uuid), private.employees_organogram_sync(),
  private.designations_organogram_sync(), private.organogram_viewer(uuid), private.department_sanctioned(uuid),
  private.department_workload(uuid, uuid, date), private.on_employee_separation(),
  private.open_replacement_seats(uuid, uuid, date), private.draft_vacancies_from_snapshot(uuid)
from public, anon, authenticated;
