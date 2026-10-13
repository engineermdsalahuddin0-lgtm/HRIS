-- =============================================================================
-- Olympus HRIS — Part 2B: Attendance core
-- Raw punches (immutable evidence) -> attendance engine -> derived daily
-- records and automatic overtime. Web / GPS / QR / manual punches. Geofences,
-- rotating QR codes, daily close, reconciliation, monthly summary with the
-- late-deduction policy. Biometric devices plug into the same punch table later.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.geofences (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null default private.current_org_id() references public.organizations (id),
  branch_id     uuid,
  office_id     uuid,
  name          text not null check (char_length(btrim(name)) between 2 and 120),
  latitude      numeric(9, 6) not null check (latitude between -90 and 90),
  longitude     numeric(9, 6) not null check (longitude between -180 and 180),
  radius_meters integer not null default 150 check (radius_meters between 10 and 5000),
  status        text not null default 'active' check (status in ('active', 'inactive')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint geofences_branch_fk foreign key (org_id, branch_id) references public.branches (org_id, id),
  constraint geofences_office_fk foreign key (org_id, office_id) references public.offices (org_id, id)
);

-- Short-lived QR codes shown at an office. Only the hash is stored.
create table public.qr_checkin_codes (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  office_id   uuid not null,
  code_hash   text not null unique,
  valid_from  timestamptz not null default now(),
  valid_until timestamptz not null,
  created_by  uuid references public.user_profiles (id) default auth.uid(),
  created_at  timestamptz not null default now(),
  constraint qr_checkin_codes_office_fk foreign key (org_id, office_id) references public.offices (org_id, id)
);
create index qr_checkin_codes_valid_idx on public.qr_checkin_codes (valid_until);

create table public.qr_code_uses (
  code_id     uuid not null references public.qr_checkin_codes (id),
  employee_id uuid not null,
  used_at     timestamptz not null default now(),
  primary key (code_id, employee_id)
);

-- Every punch from every source. Never edited or deleted.
create table public.attendance_punches (
  id               uuid primary key default gen_random_uuid(),
  org_id           uuid not null,
  employee_id      uuid not null,
  punched_at       timestamptz not null,
  source           text not null check (source in ('web', 'gps', 'qr', 'manual', 'biometric')),
  -- override_in / override_out: a manual fix that replaces the engine's choice for work_date.
  kind             text not null default 'normal' check (kind in ('normal', 'override_in', 'override_out')),
  work_date        date,
  office_id        uuid,
  latitude         numeric(9, 6),
  longitude        numeric(9, 6),
  accuracy_meters  numeric(8, 1),
  outside_geofence boolean not null default false,
  geofence_id      uuid references public.geofences (id),
  qr_code_id       uuid references public.qr_checkin_codes (id),
  device_id        uuid,              -- Part 2D (biometric devices)
  note             text,
  created_at       timestamptz not null default now(),
  created_by       uuid references public.user_profiles (id) default auth.uid(),
  constraint attendance_punches_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint attendance_punches_office_fk foreign key (org_id, office_id) references public.offices (org_id, id),
  constraint attendance_punches_override_date check (kind = 'normal' or work_date is not null),
  -- Receiving the same punch twice changes nothing.
  constraint attendance_punches_idempotent_uq unique (employee_id, punched_at, source, kind)
);
create index attendance_punches_employee_time_idx on public.attendance_punches (employee_id, punched_at);

-- One derived row per employee per date. Rebuilt from punches at any time.
create table public.attendance_records (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null,
  employee_id       uuid not null,
  work_date         date not null,
  shift_id          uuid,
  office_id         uuid,
  day_type          text not null check (day_type in ('workday', 'weekend', 'holiday')),
  status            text not null check (status in (
                      'present', 'late', 'absent', 'half_day', 'early_out', 'on_leave', 'weekend', 'holiday')),
  check_in_at       timestamptz,
  check_out_at      timestamptz,
  source_in         text,
  source_out        text,
  is_late           boolean not null default false,
  late_minutes      integer not null default 0,
  early_out_minutes integer not null default 0,
  worked_minutes    integer not null default 0,
  break_minutes     integer not null default 0,
  overtime_minutes  integer not null default 0,
  outside_geofence  boolean not null default false,
  auto_checked_out  boolean not null default false,
  note              text,
  adjusted_by       uuid references public.user_profiles (id),
  adjusted_at       timestamptz,
  locked            boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint attendance_records_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint attendance_records_employee_date_uq unique (employee_id, work_date)
);
create index attendance_records_org_date_idx on public.attendance_records (org_id, work_date);

create table public.break_records (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  employee_id uuid not null,
  work_date   date not null,
  break_start timestamptz not null,
  break_end   timestamptz,
  type        text not null default 'break' check (type in ('break', 'meal', 'prayer', 'other')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint break_records_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint break_records_dates check (break_end is null or break_end > break_start)
);
create unique index break_records_one_open_uq on public.break_records (employee_id) where break_end is null;

create table public.overtime_records (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null,
  employee_id uuid not null,
  work_date   date not null,
  minutes     integer not null check (minutes between 0 and 1440),
  day_type    text not null check (day_type in ('workday', 'weekend', 'holiday')),
  multiplier  numeric(4, 2) not null,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  source      text not null default 'auto' check (source in ('auto', 'manual')),
  reason      text,
  approved_by uuid references public.user_profiles (id),
  decided_at  timestamptz,
  decision_note text,
  locked      boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint overtime_records_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint overtime_records_employee_date_uq unique (employee_id, work_date)
);

-- -----------------------------------------------------------------------------
-- Guards and triggers
-- -----------------------------------------------------------------------------
create or replace function private.punches_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Raw punches are evidence and cannot be edited or deleted' using errcode = '42501';
end;
$$;
create trigger attendance_punches_append_only before update or delete on public.attendance_punches
  for each row execute function private.punches_append_only();
create trigger audit after insert on public.attendance_punches
  for each row execute function private.audit_row_change();

create trigger set_row_meta before insert or update on public.overtime_records
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.overtime_records
  for each row execute function private.audit_row_change();
select private.attach_standard_triggers('public.geofences');

create or replace function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger touch before update on public.attendance_records
  for each row execute function private.touch_updated_at();
create trigger touch before update on public.break_records
  for each row execute function private.touch_updated_at();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.distance_meters(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric)
returns double precision
language sql
immutable
set search_path = ''
as $$
  select 2 * 6371000 * asin(sqrt(
    power(sin(radians((lat2 - lat1)::float8) / 2), 2)
    + cos(radians(lat1::float8)) * cos(radians(lat2::float8)) * power(sin(radians((lng2 - lng1)::float8) / 2), 2)))
$$;

create or replace function private.org_today(p_org_id uuid)
returns date
language sql
stable
security definer
set search_path = ''
as $$
  select (now() at time zone (select timezone from public.organizations where id = p_org_id))::date
$$;

create or replace function private.resolve_shift_id(p_employee_id uuid, p_date date)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select shift_id from public.shift_rosters
      where employee_id = p_employee_id and status = 'active' and is_override and p_date between date_from and date_to
      order by created_at desc limit 1),
    (select shift_id from public.shift_rosters
      where employee_id = p_employee_id and status = 'active' and not is_override and p_date between date_from and date_to
      limit 1),
    (select w.default_shift_id from public.org_work_settings w
      join public.employees e on e.org_id = w.org_id where e.id = p_employee_id))
$$;

create or replace function private.day_type(p_org_id uuid, p_branch_id uuid, p_date date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.holidays h
                 where h.org_id = p_org_id and h.date = p_date and h.status = 'active'
                   and (cardinality(h.branch_ids) = 0 or p_branch_id = any (h.branch_ids))) then 'holiday'
    when extract(dow from p_date)::smallint = any (coalesce(
           (select weekly_off_days from public.org_work_settings where org_id = p_org_id), '{}'::smallint[])) then 'weekend'
    else 'workday'
  end
$$;

-- Replaced in Part 2C once leave requests exist.
create or replace function private.on_leave(p_employee_id uuid, p_date date)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return false;
end;
$$;

create or replace function private.minutes_between(a timestamptz, b timestamptz)
returns integer
language sql
immutable
set search_path = ''
as $$
  select floor(extract(epoch from (b - a)) / 60)::int
$$;

-- -----------------------------------------------------------------------------
-- The attendance engine: rebuild one employee's day from raw punches.
-- Idempotent — running it again with the same data changes nothing.
-- -----------------------------------------------------------------------------
create or replace function private.rebuild_attendance_day(p_employee_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e         public.employees;
  s         public.shifts;
  pol       public.overtime_policy;
  v_tz      text;
  v_start   timestamptz;
  v_end     timestamptz;
  v_in_from timestamptz;
  v_in_to   timestamptz;
  v_out_to  timestamptz;
  v_day     text;
  v_leave   boolean;
  v_in      public.attendance_punches;
  v_out     public.attendance_punches;
  v_out_at  timestamptz;
  v_auto    boolean := false;
  v_status  text;
  v_late    int := 0;
  v_is_late boolean := false;
  v_early   int := 0;
  v_raw     int := 0;
  v_break   int := 0;
  v_worked  int := 0;
  v_ot      int := 0;
  v_flag    boolean := false;
  v_rec     public.attendance_records;
  v_otrec   public.overtime_records;
begin
  select * into e from public.employees where id = p_employee_id;
  if not found or private.is_locked(e.org_id, p_date) then
    return;
  end if;
  select * into v_rec from public.attendance_records where employee_id = p_employee_id and work_date = p_date;
  if found and v_rec.locked then
    return;
  end if;

  -- Not employed on that date: no derived rows.
  if p_date < e.join_date or (e.exit_date is not null and p_date > e.exit_date) then
    delete from public.attendance_records where employee_id = p_employee_id and work_date = p_date and not locked;
    delete from public.overtime_records
     where employee_id = p_employee_id and work_date = p_date and source = 'auto' and status = 'pending' and not locked;
    return;
  end if;

  select * into s from public.shifts where id = private.resolve_shift_id(p_employee_id, p_date);
  if not found then
    return;
  end if;
  select timezone into v_tz from public.organizations where id = e.org_id;
  select * into pol from public.overtime_policy where org_id = e.org_id;

  -- Shift window in the organization's local time; a night shift ends next day.
  v_start   := (p_date + s.start_time) at time zone v_tz;
  v_end     := (p_date + s.end_time + case when s.crosses_midnight then interval '1 day' else interval '0' end) at time zone v_tz;
  v_in_from := v_start - make_interval(mins => s.checkin_earliest_minutes);
  v_in_to   := v_start + make_interval(mins => s.checkin_latest_minutes);
  v_out_to  := v_end + make_interval(mins => s.checkout_latest_minutes);
  v_day     := private.day_type(e.org_id, e.branch_id, p_date);
  v_leave   := private.on_leave(p_employee_id, p_date);

  -- Check-in: a manual override, else the first punch inside the check-in window.
  select * into v_in from public.attendance_punches
   where employee_id = p_employee_id and kind = 'override_in' and work_date = p_date
   order by created_at desc limit 1;
  if v_in.id is null then
    select * into v_in from public.attendance_punches
     where employee_id = p_employee_id and kind = 'normal' and punched_at between v_in_from and v_in_to
     order by punched_at limit 1;
  end if;

  -- Check-out: a manual override, else the last punch after check-in inside the window.
  select * into v_out from public.attendance_punches
   where employee_id = p_employee_id and kind = 'override_out' and work_date = p_date
   order by created_at desc limit 1;
  if v_out.id is null and v_in.id is not null then
    select * into v_out from public.attendance_punches
     where employee_id = p_employee_id and kind = 'normal'
       and punched_at > v_in.punched_at + interval '1 minute' and punched_at <= v_out_to
     order by punched_at desc limit 1;
  end if;

  if v_in.id is null then
    v_status := case
      when v_leave then 'on_leave'
      when v_day = 'holiday' then 'holiday'
      when v_day = 'weekend' then 'weekend'
      when now() > v_in_to then 'absent'
      else null                              -- the day is not decided yet
    end;
    if v_status is null then
      delete from public.attendance_records where employee_id = p_employee_id and work_date = p_date and not locked;
      return;
    end if;
  else
    v_out_at := v_out.punched_at;
    if v_out_at is null and s.auto_checkout and now() > v_out_to then
      v_out_at := v_end;
      v_auto := true;
    end if;

    v_late := greatest(0, private.minutes_between(v_start, v_in.punched_at));
    v_is_late := v_day = 'workday' and not v_leave and v_late > s.late_grace_minutes;
    if not v_is_late then
      v_late := 0;
    end if;

    if v_out_at is not null then
      v_raw := greatest(0, private.minutes_between(v_in.punched_at, v_out_at));
      select coalesce(sum(private.minutes_between(b.break_start, b.break_end)), 0)::int into v_break
        from public.break_records b
       where b.employee_id = p_employee_id and b.work_date = p_date and b.break_end is not null;
      if v_break = 0 and v_raw >= 360 then
        v_break := s.break_minutes;            -- no recorded breaks: deduct the shift's break
      end if;
      v_worked := greatest(0, v_raw - v_break);
      v_early := greatest(0, private.minutes_between(v_out_at, v_end));
      if v_early <= s.early_out_grace_minutes or v_day <> 'workday' then
        v_early := 0;
      end if;
    end if;

    v_status := case
      when v_leave then 'on_leave'
      when v_day <> 'workday' then 'present'
      when v_out_at is not null and v_worked < s.half_day_threshold_minutes then 'half_day'
      when v_early > 0 then 'early_out'
      when v_is_late then 'late'
      else 'present'
    end;

    -- Overtime: beyond the shift end on workdays; all worked time on weekends
    -- and holidays. Applies to every grade, management and owners included.
    if v_out_at is not null and pol.org_id is not null and pol.auto_capture then
      v_ot := case when v_day = 'workday' then greatest(0, private.minutes_between(v_end, v_out_at)) else v_worked end;
      if v_ot < pol.minimum_minutes then
        v_ot := 0;
      end if;
      v_ot := (v_ot / pol.rounding_minutes) * pol.rounding_minutes;
      if v_day = 'workday' then
        v_ot := least(v_ot, pol.daily_cap_minutes);
      end if;
    end if;
    v_flag := coalesce(v_in.outside_geofence, false) or coalesce(v_out.outside_geofence, false);
  end if;

  insert into public.attendance_records as r (
    org_id, employee_id, work_date, shift_id, office_id, day_type, status, check_in_at, check_out_at,
    source_in, source_out, is_late, late_minutes, early_out_minutes, worked_minutes, break_minutes,
    overtime_minutes, outside_geofence, auto_checked_out, locked)
  values (
    e.org_id, p_employee_id, p_date, s.id, coalesce(v_in.office_id, e.office_id), v_day, v_status,
    v_in.punched_at, v_out_at, v_in.source, case when v_auto then 'auto' else v_out.source end,
    v_is_late, v_late, v_early, v_worked, v_break, v_ot, v_flag, v_auto, false)
  on conflict (employee_id, work_date) do update set
    shift_id = excluded.shift_id, office_id = excluded.office_id, day_type = excluded.day_type,
    status = excluded.status, check_in_at = excluded.check_in_at, check_out_at = excluded.check_out_at,
    source_in = excluded.source_in, source_out = excluded.source_out, is_late = excluded.is_late,
    late_minutes = excluded.late_minutes, early_out_minutes = excluded.early_out_minutes,
    worked_minutes = excluded.worked_minutes, break_minutes = excluded.break_minutes,
    overtime_minutes = excluded.overtime_minutes, outside_geofence = excluded.outside_geofence,
    auto_checked_out = excluded.auto_checked_out
  where not r.locked
    and (r.status, r.check_in_at, r.check_out_at, r.worked_minutes, r.overtime_minutes, r.outside_geofence,
         r.day_type, r.late_minutes, r.early_out_minutes, r.office_id, r.shift_id, r.break_minutes)
        is distinct from
        (excluded.status, excluded.check_in_at, excluded.check_out_at, excluded.worked_minutes,
         excluded.overtime_minutes, excluded.outside_geofence, excluded.day_type, excluded.late_minutes,
         excluded.early_out_minutes, excluded.office_id, excluded.shift_id, excluded.break_minutes);

  -- Automatic overtime record (manual, decided or locked ones are left alone).
  select * into v_otrec from public.overtime_records where employee_id = p_employee_id and work_date = p_date;
  if v_otrec.id is not null and (v_otrec.source = 'manual' or v_otrec.status <> 'pending' or v_otrec.locked) then
    return;
  end if;
  if v_ot > 0 then
    insert into public.overtime_records as o (org_id, employee_id, work_date, minutes, day_type, multiplier, status, source)
    values (e.org_id, p_employee_id, p_date, v_ot, v_day,
            case v_day when 'holiday' then pol.holiday_multiplier when 'weekend' then pol.weekend_multiplier
                       else pol.weekday_multiplier end,
            case when pol.requires_approval then 'pending' else 'approved' end, 'auto')
    on conflict (employee_id, work_date) do update
      set minutes = excluded.minutes, day_type = excluded.day_type, multiplier = excluded.multiplier
      where o.minutes is distinct from excluded.minutes or o.day_type is distinct from excluded.day_type;
  elsif v_otrec.id is not null then
    delete from public.overtime_records where id = v_otrec.id;
  end if;
end;
$$;

-- A punch can belong to its local date or (night shift) the day before.
create or replace function private.rebuild_around(p_employee_id uuid, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_local date;
begin
  select (p_at at time zone o.timezone)::date into v_local
    from public.employees e join public.organizations o on o.id = e.org_id where e.id = p_employee_id;
  perform private.rebuild_attendance_day(p_employee_id, v_local - 1);
  perform private.rebuild_attendance_day(p_employee_id, v_local);
end;
$$;

-- -----------------------------------------------------------------------------
-- Punch intake
-- -----------------------------------------------------------------------------
-- Inserts one punch (idempotent) and rebuilds the affected days.
create or replace function private.record_punch(
  p_employee_id uuid, p_at timestamptz, p_source text, p_kind text, p_work_date date,
  p_office_id uuid, p_lat numeric, p_lng numeric, p_accuracy numeric, p_outside boolean,
  p_geofence_id uuid, p_qr_code_id uuid, p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid;
  v_id  uuid;
begin
  select org_id into v_org from public.employees where id = p_employee_id;
  insert into public.attendance_punches (org_id, employee_id, punched_at, source, kind, work_date, office_id,
                                         latitude, longitude, accuracy_meters, outside_geofence, geofence_id,
                                         qr_code_id, note)
  values (v_org, p_employee_id, p_at, p_source, p_kind, p_work_date, p_office_id, p_lat, p_lng, p_accuracy,
          coalesce(p_outside, false), p_geofence_id, p_qr_code_id, p_note)
  on conflict (employee_id, punched_at, source, kind) do nothing
  returning id into v_id;

  if p_kind = 'normal' then
    perform private.rebuild_around(p_employee_id, p_at);
  else
    perform private.rebuild_attendance_day(p_employee_id, p_work_date);
  end if;
  return v_id;
end;
$$;

-- An employee's own check-in / check-out from the browser (web, GPS or QR).
-- Outside the geofence is flagged for review, never blocked.
create or replace function public.punch(
  p_source   text default 'web',
  p_lat      numeric default null,
  p_lng      numeric default null,
  p_accuracy numeric default null,
  p_qr_code  text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp     public.employees;
  v_ws      public.org_work_settings;
  v_now     timestamptz := date_trunc('second', now());
  v_office  uuid;
  v_outside boolean := false;
  v_fence   public.geofences;
  v_dist    double precision;
  v_qr      public.qr_checkin_codes;
  v_id      uuid;
begin
  perform private.require_permission('attendance.view_own');
  select * into v_emp from public.employees where id = private.current_employee_id();
  if not found or v_emp.status <> 'active' then
    raise exception 'Only active employees can punch' using errcode = '42501';
  end if;
  if p_source not in ('web', 'gps', 'qr') then
    raise exception 'Unknown punch source %', p_source using errcode = '22023';
  end if;
  perform private.assert_not_locked(v_emp.org_id, private.org_today(v_emp.org_id));
  select * into v_ws from public.org_work_settings where org_id = v_emp.org_id;
  v_office := v_emp.office_id;

  if p_source = 'qr' then
    select * into v_qr from public.qr_checkin_codes
     where code_hash = encode(extensions.digest(coalesce(p_qr_code, ''), 'sha256'), 'hex') and org_id = v_emp.org_id;
    if not found then
      raise exception 'Invalid QR code' using errcode = '22023';
    end if;
    if now() < v_qr.valid_from or now() > v_qr.valid_until + interval '15 seconds' then
      raise exception 'This QR code has expired; scan the current one' using errcode = '22023';
    end if;
    begin
      insert into public.qr_code_uses (code_id, employee_id) values (v_qr.id, v_emp.id);
    exception when unique_violation then
      raise exception 'This QR code was already used; scan the current one' using errcode = '22023';
    end;
    v_office := v_qr.office_id;
  elsif p_lat is not null and p_lng is not null then
    -- Nearest active geofence of the organization.
    select g.* into v_fence
      from public.geofences g
     where g.org_id = v_emp.org_id and g.status = 'active'
     order by private.distance_meters(g.latitude, g.longitude, p_lat, p_lng) limit 1;
    if v_fence.id is not null then
      v_dist := private.distance_meters(v_fence.latitude, v_fence.longitude, p_lat, p_lng);
      v_outside := v_dist > v_fence.radius_meters or coalesce(p_accuracy, 0) > greatest(100, v_fence.radius_meters);
      if not v_outside then
        v_office := coalesce(v_fence.office_id, v_office);
      end if;
    end if;
  else
    if v_ws.require_location then
      raise exception 'Location is required to punch. Allow location access and try again.' using errcode = '22023';
    end if;
    -- No location while geofences exist: accepted, flagged for review.
    v_outside := exists (select 1 from public.geofences where org_id = v_emp.org_id and status = 'active');
  end if;

  -- Double clicks (checked after QR validation so a reused code reports itself): a punch in the last minute counts as the same punch.
  if exists (select 1 from public.attendance_punches
             where employee_id = v_emp.id and kind = 'normal' and punched_at > v_now - interval '60 seconds') then
    raise exception 'You already punched less than a minute ago' using errcode = '23505';
  end if;

  v_id := private.record_punch(v_emp.id, v_now, case when p_source = 'qr' then 'qr'
                                                     when p_lat is not null then 'gps' else 'web' end,
                               'normal', null, v_office, p_lat, p_lng, p_accuracy, v_outside,
                               case when v_fence.id is not null then v_fence.id end, v_qr.id, null);
  return jsonb_build_object('punch_id', v_id, 'punched_at', v_now, 'office_id', v_office,
                            'outside_geofence', v_outside,
                            'distance_meters', case when v_dist is not null then round(v_dist::numeric) end);
end;
$$;

-- HR adds a missing punch for someone (e.g. forgot to punch). Needs a reason.
create or replace function public.manual_punch(p_employee_id uuid, p_punched_at timestamptz, p_reason text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
  v_id  uuid;
begin
  perform private.require_permission('attendance.adjust');
  select * into v_emp from public.employees where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_employee_id = private.current_employee_id() then
    raise exception 'You cannot fix your own attendance' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A reason is required' using errcode = '23502';
  end if;
  perform private.assert_not_locked(v_emp.org_id,
    (p_punched_at at time zone (select timezone from public.organizations where id = v_emp.org_id))::date - 1,
    (p_punched_at at time zone (select timezone from public.organizations where id = v_emp.org_id))::date);
  v_id := private.record_punch(p_employee_id, date_trunc('second', p_punched_at), 'manual', 'normal', null,
                               v_emp.office_id, null, null, null, false, null, null, btrim(p_reason));
  perform private.write_audit(v_emp.org_id, 'attendance.manual_punch', 'employees', p_employee_id, null,
                              jsonb_build_object('punched_at', p_punched_at, 'reason', btrim(p_reason)));
  return v_id;
end;
$$;

-- HR sets the check-in and/or check-out for a day (overrides the engine).
create or replace function public.adjust_attendance(
  p_employee_id uuid, p_date date, p_check_in timestamptz, p_check_out timestamptz, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
  v_old jsonb;
begin
  perform private.require_permission('attendance.adjust');
  select * into v_emp from public.employees where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_employee_id = private.current_employee_id() then
    raise exception 'You cannot fix your own attendance' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A reason is required' using errcode = '23502';
  end if;
  if p_check_in is null and p_check_out is null then
    raise exception 'Give a check-in or a check-out time' using errcode = '23502';
  end if;
  if p_check_in is not null and p_check_out is not null and p_check_out <= p_check_in then
    raise exception 'Check-out must be after check-in' using errcode = '22023';
  end if;
  perform private.assert_not_locked(v_emp.org_id, p_date);

  select to_jsonb(r) into v_old from public.attendance_records r where employee_id = p_employee_id and work_date = p_date;
  if p_check_in is not null then
    perform private.record_punch(p_employee_id, date_trunc('second', p_check_in), 'manual', 'override_in', p_date,
                                 v_emp.office_id, null, null, null, false, null, null, btrim(p_reason));
  end if;
  if p_check_out is not null then
    perform private.record_punch(p_employee_id, date_trunc('second', p_check_out), 'manual', 'override_out', p_date,
                                 v_emp.office_id, null, null, null, false, null, null, btrim(p_reason));
  end if;
  update public.attendance_records
     set note = btrim(p_reason), adjusted_by = auth.uid(), adjusted_at = now()
   where employee_id = p_employee_id and work_date = p_date;
  perform private.write_audit(v_emp.org_id, 'attendance.adjusted', 'attendance_records', p_employee_id, v_old,
    jsonb_build_object('work_date', p_date, 'check_in', p_check_in, 'check_out', p_check_out, 'reason', btrim(p_reason)));
end;
$$;

-- Rotating QR code for an office screen. Returns the plain code once.
create or replace function public.issue_qr_code(p_office_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_secs  int;
  v_code  text := encode(extensions.gen_random_bytes(12), 'hex');
  v_until timestamptz;
begin
  perform private.require_permission('attendance.qr_display');
  if not exists (select 1 from public.offices where id = p_office_id and org_id = v_org and status = 'active') then
    raise exception 'Active office not found' using errcode = 'P0002';
  end if;
  select qr_rotation_seconds into v_secs from public.org_work_settings where org_id = v_org;
  v_until := now() + make_interval(secs => coalesce(v_secs, 60));
  insert into public.qr_checkin_codes (org_id, office_id, code_hash, valid_until)
  values (v_org, p_office_id, encode(extensions.digest(v_code, 'sha256'), 'hex'), v_until);
  return jsonb_build_object('code', v_code, 'valid_until', v_until, 'rotation_seconds', coalesce(v_secs, 60));
end;
$$;

-- -----------------------------------------------------------------------------
-- Jobs: daily close (absent rows, auto check-out) and rebuild. Safe to re-run.
-- -----------------------------------------------------------------------------
create or replace function private.close_day_for_org(p_org_id uuid, p_date date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp record;
  v_n   int := 0;
begin
  for v_emp in
    select id from public.employees
    where org_id = p_org_id and join_date <= p_date and (exit_date is null or exit_date >= p_date)
  loop
    perform private.rebuild_attendance_day(v_emp.id, p_date);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;

-- For pg_cron: select private.run_daily_close_all();  (closes "yesterday" in each org's timezone)
create or replace function private.run_daily_close_all(p_date date default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org record;
  v_n   int := 0;
begin
  for v_org in select id from public.organizations where status = 'active' loop
    v_n := v_n + private.close_day_for_org(v_org.id, coalesce(p_date, private.org_today(v_org.id) - 1));
  end loop;
  return v_n;
end;
$$;

create or replace function public.run_daily_close(p_date date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('attendance.adjust');
  return private.close_day_for_org(private.current_org_id(), p_date);
end;
$$;

create or replace function public.rebuild_attendance(p_from date, p_to date, p_employee_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  d     date;
  v_emp record;
  v_n   int := 0;
begin
  perform private.require_permission('attendance.adjust');
  if p_to < p_from or p_to - p_from > 92 then
    raise exception 'Choose a range of up to 93 days' using errcode = '22023';
  end if;
  for v_emp in select id from public.employees
               where org_id = v_org and (p_employee_id is null or id = p_employee_id) loop
    for d in select generate_series(p_from, p_to, interval '1 day')::date loop
      perform private.rebuild_attendance_day(v_emp.id, d);
      v_n := v_n + 1;
    end loop;
  end loop;
  return v_n;
end;
$$;

-- -----------------------------------------------------------------------------
-- Read access: views scoped to self / team / everyone.
-- -----------------------------------------------------------------------------
create or replace function private.time_viewer()
returns table (org_id uuid, employee_id uuid, see_all boolean, team uuid[])
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_org_id(), private.current_employee_id(),
         private.has_permission('attendance.view_all'),
         case when private.has_permission('attendance.view_team')
              then coalesce((select array_agg(t) from private.team_employee_ids() t), '{}') else '{}'::uuid[] end
$$;

create view public.attendance_v with (security_barrier = true) as
select r.*, e.full_name, e.card_id, e.department_id, d.name as department_name, e.branch_id,
       o.name as office_name, s.name as shift_name, s.code as shift_code,
       (r.employee_id = v.employee_id) as is_self
from private.time_viewer() v
join public.attendance_records r on r.org_id = v.org_id
join public.employees e on e.id = r.employee_id
left join public.departments d on d.id = e.department_id
left join public.offices o on o.id = r.office_id
left join public.shifts s on s.id = r.shift_id
where r.employee_id = v.employee_id or v.see_all or r.employee_id = any (v.team);

create view public.attendance_punches_v with (security_barrier = true) as
select p.id, p.org_id, p.employee_id, p.punched_at, p.source, p.kind, p.work_date, p.office_id, o.name as office_name,
       p.latitude, p.longitude, p.accuracy_meters, p.outside_geofence, p.note, p.created_at
from private.time_viewer() v
join public.attendance_punches p on p.org_id = v.org_id
left join public.offices o on o.id = p.office_id
where p.employee_id = v.employee_id or v.see_all or p.employee_id = any (v.team);

create view public.overtime_v with (security_barrier = true) as
select ot.*, e.full_name, e.card_id, d.name as department_name, (ot.employee_id = v.employee_id) as is_self
from private.time_viewer() v
join public.overtime_records ot on ot.org_id = v.org_id
join public.employees e on e.id = ot.employee_id
left join public.departments d on d.id = e.department_id
where ot.employee_id = v.employee_id
   or (private.has_permission('overtime.view') and (v.see_all or ot.employee_id = any (v.team)));

-- Days that need attention.
create or replace function public.get_reconciliation(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('attendance.adjust');
  return coalesce((
    select jsonb_agg(x order by x ->> 'work_date' desc, x ->> 'full_name')
    from (
      select jsonb_build_object(
        'record_id', r.id, 'employee_id', r.employee_id, 'full_name', e.full_name, 'card_id', e.card_id,
        'work_date', r.work_date, 'status', r.status, 'check_in_at', r.check_in_at, 'check_out_at', r.check_out_at,
        'issue', case when r.check_in_at is not null and r.check_out_at is null then 'missing_checkout'
                      else 'outside_geofence' end,
        'locked', r.locked) as x
      from public.attendance_records r
      join public.employees e on e.id = r.employee_id
      where r.org_id = v_org and r.work_date between p_from and p_to
        and ((r.check_in_at is not null and r.check_out_at is null and r.work_date < private.org_today(v_org))
             or r.outside_geofence)
    ) q), '[]'::jsonb);
end;
$$;

-- Monthly summary per visible employee, with the late-deduction policy applied.
-- The salary month is always 30 days (org_work_settings.month_days).
create or replace function public.get_attendance_summary(p_month date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v       record;
  v_from  date := date_trunc('month', p_month)::date;
  v_to    date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  ws      public.org_work_settings;
  pol     public.overtime_policy;
begin
  select * into v from private.time_viewer();
  select * into ws from public.org_work_settings where org_id = v.org_id;
  select * into pol from public.overtime_policy where org_id = v.org_id;
  return jsonb_build_object(
    'month', to_char(v_from, 'YYYY-MM'),
    'month_days', ws.month_days,
    'policy', jsonb_build_object('mode', ws.late_deduction_mode, 'lates_per_deduction', ws.lates_per_deduction,
                                 'deduction_days', ws.late_deduction_days, 'amount_per_late', ws.late_amount_per_late),
    'rows', coalesce((
      select jsonb_agg(row_to_json(t) order by t.full_name)
      from (
        select e.id as employee_id, e.full_name, e.card_id,
               count(*) filter (where r.status in ('present', 'late', 'half_day', 'early_out')) as present_days,
               count(*) filter (where r.is_late) as late_count,
               count(*) filter (where r.status = 'absent') as absent_days,
               count(*) filter (where r.status = 'half_day') as half_days,
               count(*) filter (where r.status = 'early_out') as early_out_days,
               count(*) filter (where r.status = 'on_leave') as leave_days,
               count(*) filter (where r.status in ('weekend', 'holiday')) as off_days,
               coalesce(sum(r.worked_minutes), 0) as worked_minutes,
               coalesce(sum(r.late_minutes), 0) as late_minutes,
               least(coalesce((select sum(o.minutes) from public.overtime_records o
                               where o.employee_id = e.id and o.status = 'approved'
                                 and o.work_date between v_from and v_to), 0),
                     coalesce(pol.monthly_cap_minutes, 2147483647)) as approved_overtime_minutes,
               case ws.late_deduction_mode
                 when 'days_per_lates' then
                   floor(count(*) filter (where r.is_late) / ws.lates_per_deduction::numeric) * ws.late_deduction_days
                 else 0 end as late_deduction_days,
               case ws.late_deduction_mode
                 when 'amount_per_late' then count(*) filter (where r.is_late) * ws.late_amount_per_late
                 else 0 end as late_deduction_amount
        from public.employees e
        left join public.attendance_records r on r.employee_id = e.id and r.work_date between v_from and v_to
        where e.org_id = v.org_id and e.join_date <= v_to and (e.exit_date is null or e.exit_date >= v_from)
          and (e.id = v.employee_id or v.see_all or e.id = any (v.team))
        group by e.id, e.full_name, e.card_id
      ) t), '[]'::jsonb));
end;
$$;

-- Today for the signed-in employee: shift, record, punches, open break.
create or replace function public.get_my_today()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_emp  public.employees;
  v_day  date;
  v_shift public.shifts;
begin
  select * into v_emp from public.employees where id = private.current_employee_id();
  if not found then
    return null;
  end if;
  v_day := private.org_today(v_emp.org_id);
  select * into v_shift from public.shifts where id = private.resolve_shift_id(v_emp.id, v_day);
  return jsonb_build_object(
    'employee_id', v_emp.id,
    'date', v_day,
    'day_type', private.day_type(v_emp.org_id, v_emp.branch_id, v_day),
    'shift', case when v_shift.id is not null then jsonb_build_object(
      'name', v_shift.name, 'start_time', v_shift.start_time, 'end_time', v_shift.end_time,
      'crosses_midnight', v_shift.crosses_midnight, 'late_grace_minutes', v_shift.late_grace_minutes) end,
    'record', (select to_jsonb(r) from public.attendance_records r
               where r.employee_id = v_emp.id and r.work_date in (v_day, v_day - 1)
               order by (r.check_out_at is null and r.check_in_at is not null) desc, r.work_date desc limit 1),
    'punches', coalesce((select jsonb_agg(jsonb_build_object('punched_at', p.punched_at, 'source', p.source,
                                                             'outside_geofence', p.outside_geofence) order by p.punched_at)
                         from public.attendance_punches p
                         where p.employee_id = v_emp.id and p.punched_at > now() - interval '20 hours'), '[]'::jsonb),
    'open_break', (select to_jsonb(b) from public.break_records b where b.employee_id = v_emp.id and b.break_end is null),
    'has_geofences', exists (select 1 from public.geofences where org_id = v_emp.org_id and status = 'active'));
end;
$$;

-- -----------------------------------------------------------------------------
-- Privileges and RLS
-- -----------------------------------------------------------------------------
alter table public.geofences          enable row level security;
alter table public.qr_checkin_codes   enable row level security;
alter table public.qr_code_uses       enable row level security;
alter table public.attendance_punches enable row level security;
alter table public.attendance_records enable row level security;
alter table public.break_records      enable row level security;
alter table public.overtime_records   enable row level security;

revoke all on table
  public.geofences, public.qr_checkin_codes, public.qr_code_uses, public.attendance_punches,
  public.attendance_records, public.break_records, public.overtime_records
from anon, authenticated;

grant select on table public.geofences to authenticated;
grant insert (branch_id, office_id, name, latitude, longitude, radius_meters, status),
      update (branch_id, office_id, name, latitude, longitude, radius_meters, status) on public.geofences to authenticated;
create policy geofences_select on public.geofences for select to authenticated
  using (org_id = (select private.current_org_id()));
create policy geofences_insert on public.geofences for insert to authenticated
  with check (org_id = (select private.current_org_id()) and (select private.has_permission('geofences.manage')));
create policy geofences_update on public.geofences for update to authenticated
  using (org_id = (select private.current_org_id()) and (select private.has_permission('geofences.manage')))
  with check (org_id = (select private.current_org_id()));

revoke all on table public.attendance_v, public.attendance_punches_v, public.overtime_v from anon, authenticated;
grant select on table public.attendance_v, public.attendance_punches_v, public.overtime_v to authenticated;

revoke all on function
  public.punch(text, numeric, numeric, numeric, text),
  public.manual_punch(uuid, timestamptz, text),
  public.adjust_attendance(uuid, date, timestamptz, timestamptz, text),
  public.issue_qr_code(uuid),
  public.run_daily_close(date),
  public.rebuild_attendance(date, date, uuid),
  public.get_reconciliation(date, date),
  public.get_attendance_summary(date),
  public.get_my_today()
from public, anon;
grant execute on function
  public.punch(text, numeric, numeric, numeric, text),
  public.manual_punch(uuid, timestamptz, text),
  public.adjust_attendance(uuid, date, timestamptz, timestamptz, text),
  public.issue_qr_code(uuid),
  public.run_daily_close(date),
  public.rebuild_attendance(date, date, uuid),
  public.get_reconciliation(date, date),
  public.get_attendance_summary(date),
  public.get_my_today()
to authenticated;

revoke all on function
  private.rebuild_attendance_day(uuid, date), private.rebuild_around(uuid, timestamptz),
  private.record_punch(uuid, timestamptz, text, text, date, uuid, numeric, numeric, numeric, boolean, uuid, uuid, text),
  private.close_day_for_org(uuid, date), private.run_daily_close_all(date)
from public, anon, authenticated;
grant execute on function private.time_viewer() to authenticated;
