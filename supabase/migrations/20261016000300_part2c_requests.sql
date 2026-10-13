-- =============================================================================
-- Olympus HRIS — Part 2C: Requests
-- Leave balances, requests and approvals; overtime approval and manual
-- overtime; breaks; shift swaps. Approvals follow the reporting chain; HR
-- (view-all permission) can always decide; nobody decides their own request.
-- =============================================================================

create table public.leave_balances (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null,
  employee_id     uuid not null,
  leave_type_id   uuid not null,
  year            smallint not null check (year between 2000 and 2100),
  entitled        numeric(6, 1),                         -- null = unlimited type
  carried_forward numeric(6, 1) not null default 0,
  used            numeric(6, 1) not null default 0 check (used >= 0),
  pending         numeric(6, 1) not null default 0 check (pending >= 0),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint leave_balances_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint leave_balances_type_fk foreign key (org_id, leave_type_id) references public.leave_types (org_id, id),
  constraint leave_balances_uq unique (employee_id, leave_type_id, year)
);

create table public.leave_requests (
  id                   uuid primary key default gen_random_uuid(),
  org_id               uuid not null,
  employee_id          uuid not null,
  leave_type_id        uuid not null,
  from_date            date not null,
  to_date              date not null,
  half_day             boolean not null default false,
  days                 numeric(5, 1) not null check (days > 0),
  reason               text,
  status               text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  approver_employee_id uuid,              -- reporting manager at request time (null = HR)
  decided_by           uuid references public.user_profiles (id),
  decided_at           timestamptz,
  decision_note        text,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id),
  constraint leave_requests_dates check (to_date >= from_date and (not half_day or to_date = from_date)),
  constraint leave_requests_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint leave_requests_type_fk foreign key (org_id, leave_type_id) references public.leave_types (org_id, id)
);
create index leave_requests_employee_idx on public.leave_requests (employee_id, from_date) where status in ('pending', 'approved');

create table public.shift_swaps (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid not null,
  requester_employee_id uuid not null,
  target_employee_id    uuid not null,
  work_date             date not null,
  requester_shift_id    uuid not null,
  target_shift_id       uuid not null,
  reason                text,
  status                text not null default 'pending'
                        check (status in ('pending', 'peer_accepted', 'approved', 'rejected', 'cancelled')),
  target_responded_at   timestamptz,
  decided_by            uuid references public.user_profiles (id),
  decided_at            timestamptz,
  decision_note         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  created_by            uuid references public.user_profiles (id),
  updated_by            uuid references public.user_profiles (id),
  constraint shift_swaps_not_self check (requester_employee_id <> target_employee_id),
  constraint shift_swaps_requester_fk foreign key (org_id, requester_employee_id) references public.employees (org_id, id),
  constraint shift_swaps_target_fk foreign key (org_id, target_employee_id) references public.employees (org_id, id)
);

create trigger touch before update on public.leave_balances
  for each row execute function private.touch_updated_at();
create trigger audit after insert or update or delete on public.leave_balances
  for each row execute function private.audit_row_change();
select private.attach_standard_triggers('public.leave_requests');
select private.attach_standard_triggers('public.shift_swaps');

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.current_manager_of(p_employee_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select manager_employee_id from public.reporting_lines
  where employee_id = p_employee_id and line_type = 'reporting_manager' and end_date is null
$$;

-- May the caller decide (approve/reject) for this employee? Never for themselves.
create or replace function private.can_decide_for(p_employee_id uuid, p_permission text, p_view_all text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_employee_id is distinct from private.current_employee_id()
     and private.has_permission(p_permission)
     and exists (select 1 from public.employees where id = p_employee_id and org_id = private.current_org_id())
     and (private.has_permission(p_view_all) or p_employee_id in (select private.team_employee_ids()))
$$;

create or replace function private.on_leave(p_employee_id uuid, p_date date)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (select 1 from public.leave_requests
                 where employee_id = p_employee_id and status = 'approved' and not half_day
                   and p_date between from_date and to_date);
end;
$$;

-- Creates/refreshes a balance row. Yearly types get the full year (prorated in
-- the joining year); monthly types accrue 1/12 per started month.
create or replace function private.ensure_leave_balance(p_employee_id uuid, p_type_id uuid, p_year int)
returns public.leave_balances
language plpgsql
security definer
set search_path = ''
as $$
declare
  e        public.employees;
  t        public.leave_types;
  v_months numeric;
  v_ent    numeric;
  v_today  date;
  b        public.leave_balances;
begin
  select * into e from public.employees where id = p_employee_id;
  select * into t from public.leave_types where id = p_type_id and org_id = e.org_id;
  v_today := private.org_today(e.org_id);
  if t.days_per_year is null then
    v_ent := null;
  else
    -- Months of the year the person is employed for (joining month counts).
    v_months := greatest(0, least(12,
      case when t.accrual = 'monthly' and p_year = extract(year from v_today)
           then extract(month from v_today) else 12 end
      - case when extract(year from e.join_date) = p_year then extract(month from e.join_date) - 1
             when extract(year from e.join_date) > p_year then 12 else 0 end));
    v_ent := round(t.days_per_year * v_months / 12 * 2) / 2;   -- nearest half day
  end if;

  insert into public.leave_balances as lb (org_id, employee_id, leave_type_id, year, entitled)
  values (e.org_id, p_employee_id, p_type_id, p_year, v_ent)
  on conflict (employee_id, leave_type_id, year) do update
    set entitled = excluded.entitled
    where lb.entitled is distinct from excluded.entitled
  returning * into b;
  if b.id is null then
    select * into b from public.leave_balances where employee_id = p_employee_id and leave_type_id = p_type_id and year = p_year;
  end if;
  return b;
end;
$$;

-- Days a request costs: weekly offs and holidays are skipped unless the type counts them.
create or replace function private.leave_days(p_employee_id uuid, p_type_id uuid, p_from date, p_to date, p_half boolean)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e public.employees;
  t public.leave_types;
  d date;
  n numeric := 0;
begin
  select * into e from public.employees where id = p_employee_id;
  select * into t from public.leave_types where id = p_type_id;
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    if t.counts_off_days or private.day_type(e.org_id, e.branch_id, d) = 'workday' then
      n := n + 1;
    end if;
  end loop;
  if p_half then
    return case when n > 0 then 0.5 else 0 end;
  end if;
  return n;
end;
$$;

create or replace function private.rebuild_range(p_employee_id uuid, p_from date, p_to date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  d date;
begin
  for d in select generate_series(p_from, p_to, interval '1 day')::date loop
    perform private.rebuild_attendance_day(p_employee_id, d);
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Leave RPCs
-- -----------------------------------------------------------------------------
create or replace function public.get_leave_balances(p_employee_id uuid default null, p_year int default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp  uuid := coalesce(p_employee_id, private.current_employee_id());
  v_org  uuid := private.current_org_id();
  v_year int;
  t      record;
begin
  if v_emp is null or not private.can_see_time(v_emp) then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  v_year := coalesce(p_year, extract(year from private.org_today(v_org))::int);
  for t in select id from public.leave_types where org_id = v_org and status = 'active' loop
    perform private.ensure_leave_balance(v_emp, t.id, v_year);
  end loop;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'leave_type_id', lt.id, 'code', lt.code, 'name', lt.name, 'paid', lt.paid, 'allows_half_day', lt.allows_half_day,
      'document_required', lt.document_required, 'year', b.year, 'entitled', b.entitled,
      'carried_forward', b.carried_forward, 'used', b.used, 'pending', b.pending,
      'available', case when b.entitled is null then null else b.entitled + b.carried_forward - b.used - b.pending end)
      order by lt.code)
    from public.leave_balances b
    join public.leave_types lt on lt.id = b.leave_type_id
    where b.employee_id = v_emp and b.year = v_year and lt.status = 'active'), '[]'::jsonb);
end;
$$;

create or replace function public.request_leave(
  p_leave_type_id uuid, p_from date, p_to date, p_half_day boolean default false, p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  e      public.employees;
  t      public.leave_types;
  b      public.leave_balances;
  v_days numeric;
  v_id   uuid;
begin
  perform private.require_permission('leave.request');
  select * into e from public.employees where id = private.current_employee_id();
  if not found or e.status <> 'active' then
    raise exception 'Only active employees can request leave' using errcode = '42501';
  end if;
  select * into t from public.leave_types where id = p_leave_type_id and org_id = e.org_id and status = 'active';
  if not found then
    raise exception 'Leave type not found' using errcode = 'P0002';
  end if;
  if p_to < p_from then
    raise exception 'End date is before start date' using errcode = '22023';
  end if;
  if extract(year from p_from) <> extract(year from p_to) then
    raise exception 'A request cannot cross a year; split it in two' using errcode = '22023';
  end if;
  if p_to - p_from > 180 then
    raise exception 'A request can cover at most 181 days' using errcode = '22023';
  end if;
  if p_half_day and (not t.allows_half_day or p_from <> p_to) then
    raise exception 'Half day is not allowed for this request' using errcode = '22023';
  end if;
  if t.document_required and nullif(btrim(p_reason), '') is null then
    raise exception 'This leave type needs a reason / document reference' using errcode = '23502';
  end if;
  perform private.assert_not_locked(e.org_id, p_from, p_to);
  if exists (select 1 from public.leave_requests
             where employee_id = e.id and status in ('pending', 'approved')
               and daterange(from_date, to_date, '[]') && daterange(p_from, p_to, '[]')) then
    raise exception 'You already have leave on some of these dates' using errcode = '23P01';
  end if;

  v_days := private.leave_days(e.id, t.id, p_from, p_to, p_half_day);
  if v_days <= 0 then
    raise exception 'These dates are all weekly offs or holidays' using errcode = '22023';
  end if;

  -- Balance check; pending requests reserve days.
  b := private.ensure_leave_balance(e.id, t.id, extract(year from p_from)::int);
  select * into b from public.leave_balances where id = b.id for update;
  if b.entitled is not null and b.entitled + b.carried_forward - b.used - b.pending < v_days then
    raise exception 'Not enough % balance (available %, requested %)', t.code,
      b.entitled + b.carried_forward - b.used - b.pending, v_days using errcode = '23514';
  end if;
  update public.leave_balances set pending = pending + v_days where id = b.id;

  insert into public.leave_requests (org_id, employee_id, leave_type_id, from_date, to_date, half_day, days, reason,
                                     approver_employee_id)
  values (e.org_id, e.id, t.id, p_from, p_to, p_half_day, v_days, nullif(btrim(p_reason), ''),
          private.current_manager_of(e.id))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.decide_leave(p_request_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.leave_requests;
begin
  select * into r from public.leave_requests where id = p_request_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Leave request not found' using errcode = 'P0002';
  end if;
  if r.employee_id = private.current_employee_id() then
    raise exception 'You cannot approve your own request' using errcode = '42501';
  end if;
  if not private.can_decide_for(r.employee_id, 'leave.approve', 'leave.view_all') then
    raise exception 'You cannot decide this request' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    raise exception 'This request is already %', r.status using errcode = '23514';
  end if;
  perform private.assert_not_locked(r.org_id, r.from_date, r.to_date);

  update public.leave_balances
     set pending = greatest(0, pending - r.days),
         used = used + case when p_approve then r.days else 0 end
   where employee_id = r.employee_id and leave_type_id = r.leave_type_id and year = extract(year from r.from_date);
  update public.leave_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '')
   where id = r.id;
  if p_approve then
    perform private.rebuild_range(r.employee_id, r.from_date, r.to_date);
  end if;
end;
$$;

-- The requester cancels their own request, or HR cancels any. Restores balance and attendance.
create or replace function public.cancel_leave(p_request_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.leave_requests;
begin
  select * into r from public.leave_requests where id = p_request_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Leave request not found' using errcode = 'P0002';
  end if;
  if r.employee_id <> coalesce(private.current_employee_id(), '00000000-0000-0000-0000-000000000000')
     and not (private.has_permission('leave.view_all') and private.has_permission('leave.approve')) then
    raise exception 'You cannot cancel this request' using errcode = '42501';
  end if;
  if r.status not in ('pending', 'approved') then
    raise exception 'This request is already %', r.status using errcode = '23514';
  end if;
  perform private.assert_not_locked(r.org_id, r.from_date, r.to_date);

  update public.leave_balances
     set pending = greatest(0, pending - case when r.status = 'pending' then r.days else 0 end),
         used = greatest(0, used - case when r.status = 'approved' then r.days else 0 end)
   where employee_id = r.employee_id and leave_type_id = r.leave_type_id and year = extract(year from r.from_date);
  update public.leave_requests
     set status = 'cancelled', decision_note = coalesce(nullif(btrim(p_reason), ''), decision_note)
   where id = r.id;
  if r.status = 'approved' then
    perform private.rebuild_range(r.employee_id, r.from_date, r.to_date);
  end if;
end;
$$;

-- Year-start rollover: carry unused days (up to the cap) into the next year.
create or replace function private.leave_rollover_for_org(p_org_id uuid, p_from_year int)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  b   record;
  nb  public.leave_balances;
  v_n int := 0;
begin
  for b in
    select lb.*, lt.carry_forward_cap
    from public.leave_balances lb
    join public.leave_types lt on lt.id = lb.leave_type_id
    where lb.org_id = p_org_id and lb.year = p_from_year and lt.carry_forward and lb.entitled is not null
  loop
    nb := private.ensure_leave_balance(b.employee_id, b.leave_type_id, p_from_year + 1);
    update public.leave_balances
       set carried_forward = least(greatest(0, b.entitled + b.carried_forward - b.used - b.pending),
                                   coalesce(b.carry_forward_cap, 9999))
     where id = nb.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function public.run_leave_rollover(p_from_year int)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('leave.manage_types');
  return private.leave_rollover_for_org(private.current_org_id(), p_from_year);
end;
$$;

-- -----------------------------------------------------------------------------
-- Overtime
-- -----------------------------------------------------------------------------
create or replace function public.decide_overtime(p_record_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  o public.overtime_records;
begin
  select * into o from public.overtime_records where id = p_record_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Overtime record not found' using errcode = 'P0002';
  end if;
  if o.employee_id = private.current_employee_id() then
    raise exception 'You cannot approve your own overtime' using errcode = '42501';
  end if;
  if not private.can_decide_for(o.employee_id, 'overtime.approve', 'attendance.view_all') then
    raise exception 'You cannot decide this overtime' using errcode = '42501';
  end if;
  if o.locked or private.is_locked(o.org_id, o.work_date) then
    raise exception 'This period is locked for payroll and cannot be changed' using errcode = '42501';
  end if;
  if o.status <> 'pending' then
    raise exception 'This overtime is already %', o.status using errcode = '23514';
  end if;
  update public.overtime_records
     set status = case when p_approve then 'approved' else 'rejected' end,
         approved_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '')
   where id = o.id;
end;
$$;

-- HR records overtime the engine could not see. Goes to approval like any other.
create or replace function public.add_manual_overtime(p_employee_id uuid, p_date date, p_minutes int, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  e     public.employees;
  pol   public.overtime_policy;
  v_day text;
  v_id  uuid;
begin
  perform private.require_permission('attendance.adjust');
  select * into e from public.employees where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_employee_id = private.current_employee_id() then
    raise exception 'You cannot add overtime for yourself' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A reason is required' using errcode = '23502';
  end if;
  if p_minutes is null or p_minutes <= 0 or p_minutes > 1440 then
    raise exception 'Minutes must be between 1 and 1440' using errcode = '22023';
  end if;
  perform private.assert_not_locked(e.org_id, p_date);
  select * into pol from public.overtime_policy where org_id = e.org_id;
  v_day := private.day_type(e.org_id, e.branch_id, p_date);
  insert into public.overtime_records as o (org_id, employee_id, work_date, minutes, day_type, multiplier, status, source, reason)
  values (e.org_id, p_employee_id, p_date, p_minutes, v_day,
          case v_day when 'holiday' then pol.holiday_multiplier when 'weekend' then pol.weekend_multiplier
                     else pol.weekday_multiplier end, 'pending', 'manual', btrim(p_reason))
  on conflict (employee_id, work_date) do update
    set minutes = excluded.minutes, source = 'manual', status = 'pending', reason = excluded.reason,
        approved_by = null, decided_at = null
    where not o.locked
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Breaks (self)
-- -----------------------------------------------------------------------------
create or replace function public.start_break(p_type text default 'break')
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  e    public.employees;
  r    public.attendance_records;
  v_id uuid;
begin
  perform private.require_permission('attendance.view_own');
  select * into e from public.employees where id = private.current_employee_id();
  if not found then
    raise exception 'No employee record' using errcode = 'P0002';
  end if;
  select * into r from public.attendance_records
   where employee_id = e.id and check_in_at is not null and check_out_at is null
     and work_date >= private.org_today(e.org_id) - 1
   order by work_date desc limit 1;
  if not found then
    raise exception 'Check in first' using errcode = '23514';
  end if;
  begin
    insert into public.break_records (org_id, employee_id, work_date, break_start, type)
    values (e.org_id, e.id, r.work_date, now(), coalesce(p_type, 'break'))
    returning id into v_id;
  exception when unique_violation then
    raise exception 'A break is already running' using errcode = '23505';
  end;
  return v_id;
end;
$$;

create or replace function public.end_break()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  b public.break_records;
begin
  update public.break_records set break_end = greatest(now(), break_start + interval '1 second')
   where employee_id = private.current_employee_id() and break_end is null
  returning * into b;
  if b.id is null then
    raise exception 'No break is running' using errcode = 'P0002';
  end if;
  perform private.rebuild_attendance_day(b.employee_id, b.work_date);
end;
$$;

-- -----------------------------------------------------------------------------
-- Shift swaps: request -> peer accepts -> manager/HR approves -> roster overrides.
-- -----------------------------------------------------------------------------
create or replace function public.request_shift_swap(p_target_employee_id uuid, p_date date, p_reason text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me    public.employees;
  v_s1  uuid;
  v_s2  uuid;
  v_id  uuid;
begin
  perform private.require_permission('attendance.view_own');
  select * into me from public.employees where id = private.current_employee_id();
  if not found or me.status <> 'active' then
    raise exception 'Only active employees can request swaps' using errcode = '42501';
  end if;
  if p_target_employee_id = me.id then
    raise exception 'Choose a colleague, not yourself' using errcode = '22023';
  end if;
  if not exists (select 1 from public.employees where id = p_target_employee_id and org_id = me.org_id and status = 'active') then
    raise exception 'Colleague not found' using errcode = 'P0002';
  end if;
  if p_date < private.org_today(me.org_id) then
    raise exception 'The date has passed' using errcode = '22023';
  end if;
  perform private.assert_not_locked(me.org_id, p_date);
  v_s1 := private.resolve_shift_id(me.id, p_date);
  v_s2 := private.resolve_shift_id(p_target_employee_id, p_date);
  if v_s1 is null or v_s2 is null or v_s1 = v_s2 then
    raise exception 'You both have the same shift on that date' using errcode = '22023';
  end if;
  if exists (select 1 from public.shift_swaps
             where work_date = p_date and status in ('pending', 'peer_accepted')
               and (requester_employee_id in (me.id, p_target_employee_id) or target_employee_id in (me.id, p_target_employee_id))) then
    raise exception 'A swap for that date is already open' using errcode = '23505';
  end if;
  insert into public.shift_swaps (org_id, requester_employee_id, target_employee_id, work_date,
                                  requester_shift_id, target_shift_id, reason)
  values (me.org_id, me.id, p_target_employee_id, p_date, v_s1, v_s2, nullif(btrim(p_reason), ''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.respond_shift_swap(p_swap_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.shift_swaps
     set status = case when p_accept then 'peer_accepted' else 'rejected' end, target_responded_at = now()
   where id = p_swap_id and target_employee_id = private.current_employee_id() and status = 'pending';
  if not found then
    raise exception 'No pending swap for you to answer' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.decide_shift_swap(p_swap_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  w public.shift_swaps;
begin
  select * into w from public.shift_swaps where id = p_swap_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Swap not found' using errcode = 'P0002';
  end if;
  if private.current_employee_id() in (w.requester_employee_id, w.target_employee_id) then
    raise exception 'You cannot approve your own swap' using errcode = '42501';
  end if;
  if not private.can_decide_for(w.requester_employee_id, 'swaps.approve', 'attendance.view_all') then
    raise exception 'You cannot decide this swap' using errcode = '42501';
  end if;
  if w.status <> 'peer_accepted' then
    raise exception 'The colleague must accept first (status: %)', w.status using errcode = '23514';
  end if;
  perform private.assert_not_locked(w.org_id, w.work_date);

  update public.shift_swaps
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(p_note), '')
   where id = w.id;
  if p_approve then
    insert into public.shift_rosters (org_id, employee_id, shift_id, date_from, date_to, is_override, note) values
      (w.org_id, w.requester_employee_id, w.target_shift_id, w.work_date, w.work_date, true, 'Shift swap'),
      (w.org_id, w.target_employee_id, w.requester_shift_id, w.work_date, w.work_date, true, 'Shift swap');
    perform private.rebuild_attendance_day(w.requester_employee_id, w.work_date);
    perform private.rebuild_attendance_day(w.target_employee_id, w.work_date);
  end if;
end;
$$;

create or replace function public.cancel_shift_swap(p_swap_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.shift_swaps set status = 'cancelled'
   where id = p_swap_id and requester_employee_id = private.current_employee_id()
     and status in ('pending', 'peer_accepted');
  if not found then
    raise exception 'No open swap of yours found' using errcode = 'P0002';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Views (scoped like attendance_v)
-- -----------------------------------------------------------------------------
create view public.leave_requests_v with (security_barrier = true) as
select lr.*, e.full_name, e.card_id, d.name as department_name, lt.name as leave_type_name, lt.code as leave_type_code,
       am.full_name as approver_name,
       (lr.employee_id = v.employee_id) as is_self,
       (lr.employee_id is distinct from v.employee_id and lr.status = 'pending'
        and private.has_permission('leave.approve')
        and (private.has_permission('leave.view_all') or lr.employee_id = any (v.team))) as can_decide
from private.time_viewer() v
join public.leave_requests lr on lr.org_id = v.org_id
join public.employees e on e.id = lr.employee_id
join public.leave_types lt on lt.id = lr.leave_type_id
left join public.departments d on d.id = e.department_id
left join public.employees am on am.id = lr.approver_employee_id
where lr.employee_id = v.employee_id or lr.employee_id = any (v.team)
   or private.has_permission('leave.view_all') or v.see_all;

create view public.shift_swaps_v with (security_barrier = true) as
select w.*, r.full_name as requester_name, t.full_name as target_name,
       rs.name as requester_shift_name, ts.name as target_shift_name,
       (w.requester_employee_id = v.employee_id) as is_requester,
       (w.target_employee_id = v.employee_id) as is_target
from private.time_viewer() v
join public.shift_swaps w on w.org_id = v.org_id
join public.employees r on r.id = w.requester_employee_id
join public.employees t on t.id = w.target_employee_id
join public.shifts rs on rs.id = w.requester_shift_id
join public.shifts ts on ts.id = w.target_shift_id
where v.employee_id in (w.requester_employee_id, w.target_employee_id)
   or v.see_all or w.requester_employee_id = any (v.team);

create view public.break_records_v with (security_barrier = true) as
select b.*, e.full_name
from private.time_viewer() v
join public.break_records b on b.org_id = v.org_id
join public.employees e on e.id = b.employee_id
where b.employee_id = v.employee_id or v.see_all or b.employee_id = any (v.team);

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.leave_balances enable row level security;
alter table public.leave_requests enable row level security;
alter table public.shift_swaps    enable row level security;
revoke all on table public.leave_balances, public.leave_requests, public.shift_swaps from anon, authenticated;
revoke all on table public.leave_requests_v, public.shift_swaps_v, public.break_records_v from anon, authenticated;
grant select on table public.leave_requests_v, public.shift_swaps_v, public.break_records_v to authenticated;

revoke all on function
  public.get_leave_balances(uuid, int), public.request_leave(uuid, date, date, boolean, text),
  public.decide_leave(uuid, boolean, text), public.cancel_leave(uuid, text), public.run_leave_rollover(int),
  public.decide_overtime(uuid, boolean, text), public.add_manual_overtime(uuid, date, int, text),
  public.start_break(text), public.end_break(),
  public.request_shift_swap(uuid, date, text), public.respond_shift_swap(uuid, boolean),
  public.decide_shift_swap(uuid, boolean, text), public.cancel_shift_swap(uuid)
from public, anon;
grant execute on function
  public.get_leave_balances(uuid, int), public.request_leave(uuid, date, date, boolean, text),
  public.decide_leave(uuid, boolean, text), public.cancel_leave(uuid, text), public.run_leave_rollover(int),
  public.decide_overtime(uuid, boolean, text), public.add_manual_overtime(uuid, date, int, text),
  public.start_break(text), public.end_break(),
  public.request_shift_swap(uuid, date, text), public.respond_shift_swap(uuid, boolean),
  public.decide_shift_swap(uuid, boolean, text), public.cancel_shift_swap(uuid)
to authenticated;

revoke all on function
  private.ensure_leave_balance(uuid, uuid, int), private.leave_days(uuid, uuid, date, date, boolean),
  private.rebuild_range(uuid, date, date), private.leave_rollover_for_org(uuid, int)
from public, anon, authenticated;
grant execute on function private.can_decide_for(uuid, text, text), private.current_manager_of(uuid) to authenticated;
