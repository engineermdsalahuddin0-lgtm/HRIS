-- =============================================================================
-- TMS T2: trips — request, approval, assignment, start / end with odometer and GPS,
-- trip expenses, the driver view.
-- Module handbook: src/TMS/architecture.md section 3 (trip flow), security.md.
--
--   * Anyone in the company may request a vehicle (like a helpdesk ticket). A request
--     waits for the Manager of the requester's department (tms.approve) or the
--     transport desk (tms.manage); nobody approves their own request. Trips the desk
--     creates itself (deliveries, field routes) are approved at once.
--   * Assignment (desk) refuses: an inactive / off-road / in-maintenance vehicle, an
--     inactive driver, an expired licence, a licence class too low for the vehicle,
--     and any time clash of the vehicle or the driver with another assigned or
--     running trip.
--   * Start / End by the trip's driver (or the desk): the odometer never goes back;
--     a GPS point is stored only at these moments (no background tracking).
--   * Expenses on a trip: toll, parking, fine, food, other (receipt optional).
--   * Access rules never return NULL (coalesce): a login without a department or a
--     driver record is refused, not let through.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.get_tms_fleet') is null then
    raise exception 'Apply 20261105000100_tms_t1_fleet.sql first, then run this file again';
  end if;
end;
$guard$;

alter table public.notifications drop constraint if exists notifications_source_check;
alter table public.notifications add constraint notifications_source_check
  check (source in ('recruit', 'notice', 'helpdesk', 'dms', 'tms'));

create or replace function private.can_send_messages()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_permission('recruit.manage') or private.has_permission('notices.manage')
      or private.has_permission('notices.department') or private.has_permission('users.reset_password')
      or private.has_permission('dms.manage') or private.has_permission('dms.upload') or private.has_permission('dms.approve')
      or private.has_permission('tms.manage') or private.has_permission('tms.approve')
$$;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------
create table public.tms_trips (
  id             uuid primary key default gen_random_uuid(),
  org_id         uuid not null references public.organizations (id),
  kind           text not null default 'staff' check (kind in ('staff', 'delivery', 'field')),
  requested_by   uuid not null references public.user_profiles (id),
  department_id  uuid,
  purpose        text not null check (char_length(btrim(purpose)) between 3 and 500),
  from_place     text not null check (char_length(btrim(from_place)) between 2 and 200),
  to_place       text not null check (char_length(btrim(to_place)) between 2 and 200),
  stops          text check (stops is null or char_length(stops) <= 500),
  planned_start  timestamptz not null,
  planned_end    timestamptz not null,
  passengers     smallint check (passengers is null or passengers between 1 and 100),
  cargo          text check (cargo is null or char_length(cargo) <= 300),
  customer       text check (customer is null or char_length(customer) <= 200),
  status         text not null default 'requested'
                 check (status in ('requested', 'approved', 'rejected', 'assigned', 'in_progress', 'completed', 'cancelled')),
  decided_by     uuid references public.user_profiles (id),
  decided_at     timestamptz,
  decision_note  text check (decision_note is null or char_length(decision_note) <= 500),
  vehicle_id     uuid,
  driver_id      uuid,
  start_odometer numeric(10, 1),
  end_odometer   numeric(10, 1),
  started_at     timestamptz,
  ended_at       timestamptz,
  start_lat      numeric(9, 6),
  start_lng      numeric(9, 6),
  end_lat        numeric(9, 6),
  end_lng        numeric(9, 6),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references public.user_profiles (id),
  updated_by     uuid references public.user_profiles (id),
  constraint tms_trips_org_id_id_uq unique (org_id, id),
  constraint tms_trips_department_fk foreign key (org_id, department_id) references public.departments (org_id, id),
  constraint tms_trips_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_trips_driver_fk foreign key (org_id, driver_id) references public.tms_drivers (org_id, id),
  constraint tms_trips_times check (planned_end > planned_start),
  constraint tms_trips_odometer check (end_odometer is null or start_odometer is null or end_odometer >= start_odometer),
  constraint tms_trips_assigned check (status not in ('assigned', 'in_progress', 'completed') or (vehicle_id is not null and driver_id is not null))
);
create index tms_trips_status_idx on public.tms_trips (org_id, status, planned_start);
create index tms_trips_vehicle_idx on public.tms_trips (org_id, vehicle_id, planned_start) where vehicle_id is not null;
create index tms_trips_driver_idx on public.tms_trips (org_id, driver_id, planned_start) where driver_id is not null;
select private.attach_standard_triggers('public.tms_trips');

create table public.tms_trip_expenses (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  trip_id      uuid not null,
  kind         text not null check (kind in ('toll', 'parking', 'fine', 'food', 'other')),
  amount       numeric(12, 2) not null check (amount > 0 and amount <= 1000000),
  note         text check (note is null or char_length(note) <= 300),
  receipt_path text,
  status       text not null default 'active' check (status in ('active', 'void')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint tms_trip_expenses_org_id_id_uq unique (org_id, id),
  constraint tms_trip_expenses_trip_fk foreign key (org_id, trip_id) references public.tms_trips (org_id, id)
);
select private.attach_standard_triggers('public.tms_trip_expenses');

-- GPS points: only at trip start / end and fuel fills (phone); devices come in Phase 2. Insert-only.
create table public.tms_locations (
  id          bigint generated always as identity primary key,
  org_id      uuid not null references public.organizations (id),
  vehicle_id  uuid,
  driver_id   uuid,
  trip_id     uuid,
  source      text not null default 'phone' check (source in ('phone', 'device')),
  event       text not null check (event in ('trip_start', 'trip_end', 'fuel', 'point')),
  lat         numeric(9, 6) not null check (lat between -90 and 90),
  lng         numeric(9, 6) not null check (lng between -180 and 180),
  accuracy_m  numeric(8, 1),
  recorded_at timestamptz not null default now(),
  recorded_by uuid default auth.uid(),
  constraint tms_locations_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_locations_trip_fk foreign key (org_id, trip_id) references public.tms_trips (org_id, id)
);
create index tms_locations_vehicle_idx on public.tms_locations (org_id, vehicle_id, recorded_at desc);

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.tms_my_driver_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select d.id from public.tms_drivers d
  where d.org_id = private.current_org_id() and d.status <> 'inactive'
    and (d.user_id = auth.uid() or d.employee_id = private.current_employee_id())
  limit 1
$$;

create or replace function private.tms_can_approve(t public.tms_trips)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(t.org_id = private.current_org_id()
     and (private.has_permission('tms.manage')
          or (private.has_permission('tms.approve') and t.department_id = private.dms_my_department())), false)
$$;

create or replace function private.tms_can_see_trip(t public.tms_trips)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(t.org_id = private.current_org_id()
     and (t.requested_by = auth.uid() or private.has_permission('tms.manage') or private.has_permission('tms.view_costs')
          or private.tms_can_approve(t) or coalesce(t.driver_id = private.tms_my_driver_id(), false)), false)
$$;

create or replace function private.load_tms_trip(p_id uuid)
returns public.tms_trips
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tms_trips;
begin
  select * into t from public.tms_trips where id = p_id and org_id = private.current_org_id();
  if not found or not private.tms_can_see_trip(t) then
    raise exception 'Trip not found' using errcode = 'P0002';
  end if;
  return t;
end;
$$;

-- Same as the DMS helper, for transport emails.
create or replace function private.tms_queue_email(p_org_id uuid, p_user_id uuid, p_ref uuid, p_template text, p_subject text, p_body text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp  uuid;
  v_addr text;
begin
  if p_user_id is null or not private.email_channel_ready(p_org_id) then
    return false;
  end if;
  select m.employee_id, coalesce(e.email, up.email) into v_emp, v_addr
  from public.org_members m
  left join public.employees e on e.id = m.employee_id
  left join public.user_profiles up on up.id = m.user_id
  where m.org_id = p_org_id and m.user_id = p_user_id and m.status = 'active'
  limit 1;
  if v_emp is null or v_addr is null then
    return false;
  end if;
  insert into public.notifications (org_id, source, employee_id, ref_id, template_key, channel, to_address, subject, body)
  values (p_org_id, 'tms', v_emp, p_ref, p_template, 'email', v_addr, left(p_subject, 200),
          left(p_body || E'\n\n' || (select o.name from public.organizations o where o.id = p_org_id), 20000));
  return true;
end;
$$;

create or replace function private.tms_trip_json(t public.tms_trips)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', t.id, 'kind', t.kind, 'status', t.status, 'purpose', t.purpose, 'from_place', t.from_place, 'to_place', t.to_place,
    'stops', t.stops, 'planned_start', t.planned_start, 'planned_end', t.planned_end, 'passengers', t.passengers,
    'cargo', t.cargo, 'customer', t.customer, 'decision_note', t.decision_note, 'decided_at', t.decided_at,
    'requested_by', private.dms_user_name(t.requested_by), 'requested_by_me', t.requested_by = auth.uid(),
    'decided_by', private.dms_user_name(t.decided_by),
    'department_id', t.department_id, 'department', (select d.name from public.departments d where d.id = t.department_id),
    'vehicle', (select jsonb_build_object('id', v.id, 'reg_no', v.reg_no, 'vtype', v.vtype) from public.tms_vehicles v where v.id = t.vehicle_id),
    'driver', (select jsonb_build_object('id', d.id, 'name', private.tms_driver_name(d),
                                         'phone', coalesce(d.phone, (select e.phone from public.employees e where e.id = d.employee_id)))
               from public.tms_drivers d where d.id = t.driver_id),
    'i_drive', coalesce(t.driver_id = private.tms_my_driver_id(), false),
    'can_approve', t.status = 'requested' and t.requested_by <> auth.uid() and private.tms_can_approve(t),
    'start_odometer', t.start_odometer, 'end_odometer', t.end_odometer,
    'distance_km', case when t.end_odometer is not null then t.end_odometer - t.start_odometer end,
    'started_at', t.started_at, 'ended_at', t.ended_at,
    'start_point', case when t.start_lat is not null then jsonb_build_object('lat', t.start_lat, 'lng', t.start_lng) end,
    'end_point', case when t.end_lat is not null then jsonb_build_object('lat', t.end_lat, 'lng', t.end_lng) end,
    'expenses_total', (select coalesce(sum(x.amount), 0) from public.tms_trip_expenses x where x.trip_id = t.id and x.status = 'active'),
    'created_at', t.created_at)
$$;

-- -----------------------------------------------------------------------------
-- API: request, decide, assign
-- -----------------------------------------------------------------------------
-- p: {kind, purpose, from_place, to_place, stops, planned_start, planned_end, passengers, cargo, customer, department_id}
-- The desk's own trips (deliveries, routes) are approved at once.
create or replace function public.create_tms_trip(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_desk  boolean := private.has_permission('tms.manage');
  v_start timestamptz := nullif(p ->> 'planned_start', '')::timestamptz;
  v_end   timestamptz := nullif(p ->> 'planned_end', '')::timestamptz;
  v_dept  uuid := case when v_desk then coalesce(nullif(p ->> 'department_id', '')::uuid, private.dms_my_department()) else private.dms_my_department() end;
  v_id    uuid;
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  if coalesce(p ->> 'kind', 'staff') not in ('staff', 'delivery', 'field') then
    raise exception 'Unknown trip kind' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'purpose'), '')) < 3 then
    raise exception 'Write the purpose of the trip' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'from_place'), '')) < 2 or char_length(coalesce(btrim(p ->> 'to_place'), '')) < 2 then
    raise exception 'Enter where from and where to' using errcode = '22023';
  end if;
  if v_start is null or v_end is null or v_end <= v_start then
    raise exception 'The trip must end after it starts' using errcode = '22023';
  end if;
  if v_start < now() - interval '1 day' then
    raise exception 'The start time is in the past' using errcode = '22023';
  end if;
  if v_dept is not null and not exists (select 1 from public.departments where id = v_dept and org_id = v_org) then
    raise exception 'Choose a department of your company' using errcode = '22023';
  end if;
  insert into public.tms_trips (org_id, kind, requested_by, department_id, purpose, from_place, to_place, stops, planned_start, planned_end,
                                passengers, cargo, customer, status, decided_by, decided_at)
  values (v_org, coalesce(p ->> 'kind', 'staff'), auth.uid(), v_dept, btrim(p ->> 'purpose'), btrim(p ->> 'from_place'), btrim(p ->> 'to_place'),
          private.jtext(p, 'stops'), v_start, v_end, nullif(p ->> 'passengers', '')::smallint, private.jtext(p, 'cargo'),
          private.jtext(p, 'customer'), case when v_desk then 'approved' else 'requested' end,
          case when v_desk then auth.uid() end, case when v_desk then now() end)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.decide_tms_trip(p_id uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.tms_trips := private.load_tms_trip(p_id);
begin
  if not private.tms_can_approve(t) then
    raise exception 'You do not have permission for this action (tms.approve)' using errcode = '42501';
  end if;
  if t.status <> 'requested' then
    raise exception 'This request is already decided' using errcode = '23514';
  end if;
  if t.requested_by = auth.uid() then
    raise exception 'You cannot approve your own request' using errcode = '23514';
  end if;
  if not coalesce(p_approve, false) and char_length(btrim(coalesce(p_note, ''))) < 3 then
    raise exception 'Write why the request is refused' using errcode = '22023';
  end if;
  update public.tms_trips set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
   where id = t.id;
  perform private.tms_queue_email(t.org_id, t.requested_by, t.id, 'tms_decision',
    case when p_approve then 'Vehicle request approved' else 'Vehicle request refused' end || ': ' || t.purpose,
    'Your vehicle request (' || t.from_place || ' → ' || t.to_place || ', ' || to_char(t.planned_start, 'DD Mon HH24:MI') || ') was '
    || case when p_approve then 'approved. The transport desk will assign a vehicle and a driver.' else 'refused.' end
    || coalesce(E'\nNote: ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
end;
$$;

-- What stops a vehicle + driver from taking this trip (empty = fine). Also used by the UI before assigning.
create or replace function private.tms_assign_problems(t public.tms_trips, p_vehicle uuid, p_driver uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v   public.tms_vehicles;
  d   public.tms_drivers;
  out text[] := '{}';
begin
  select * into v from public.tms_vehicles where id = p_vehicle and org_id = t.org_id;
  select * into d from public.tms_drivers where id = p_driver and org_id = t.org_id;
  if v.id is null then out := array_append(out, 'Vehicle not found'::text); end if;
  if d.id is null then out := array_append(out, 'Driver not found'::text); end if;
  if v.id is not null and v.status <> 'active' then out := out || ('The vehicle is ' || replace(v.status, '_', ' ')); end if;
  if d.id is not null and d.status <> 'active' then out := out || ('The driver is ' || replace(d.status, '_', ' ')); end if;
  if d.id is not null and d.licence_expiry < (t.planned_end at time zone 'UTC')::date then
    out := array_append(out, 'The driver''s licence expires on ' || to_char(d.licence_expiry, 'DD Mon YYYY'));
  end if;
  if v.id is not null and d.id is not null and not private.tms_class_ok(d.licence_class, v.vtype) then
    out := array_append(out, 'A ' || d.licence_class || ' licence does not cover this ' || replace(v.vtype, '_', ' '));
  end if;
  if exists (select 1 from public.tms_trips x where x.org_id = t.org_id and x.id <> t.id and x.vehicle_id = p_vehicle
             and x.status in ('assigned', 'in_progress') and tstzrange(x.planned_start, x.planned_end) && tstzrange(t.planned_start, t.planned_end)) then
    out := array_append(out, 'The vehicle is booked for another trip at that time'::text);
  end if;
  if exists (select 1 from public.tms_trips x where x.org_id = t.org_id and x.id <> t.id and x.driver_id = p_driver
             and x.status in ('assigned', 'in_progress') and tstzrange(x.planned_start, x.planned_end) && tstzrange(t.planned_start, t.planned_end)) then
    out := array_append(out, 'The driver has another trip at that time'::text);
  end if;
  return out;
end;
$$;

create or replace function public.assign_tms_trip(p_id uuid, p_vehicle_id uuid, p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t      public.tms_trips := private.load_tms_trip(p_id);
  v_prob text[];
  d      public.tms_drivers;
begin
  perform private.require_permission('tms.manage');
  if t.status not in ('approved', 'assigned') then
    raise exception 'Only an approved trip can get a vehicle' using errcode = '23514';
  end if;
  v_prob := private.tms_assign_problems(t, p_vehicle_id, p_driver_id);
  if cardinality(v_prob) > 0 then
    raise exception '%', array_to_string(v_prob, '; ') using errcode = '23514';
  end if;
  update public.tms_trips set status = 'assigned', vehicle_id = p_vehicle_id, driver_id = p_driver_id where id = t.id returning * into t;
  select * into d from public.tms_drivers where id = p_driver_id;
  perform private.tms_queue_email(t.org_id, d.user_id, t.id, 'tms_assigned', 'Trip assigned: ' || t.from_place || ' → ' || t.to_place,
    'You drive ' || (select v.reg_no from public.tms_vehicles v where v.id = p_vehicle_id) || ' on ' || to_char(t.planned_start, 'DD Mon HH24:MI')
    || E'.\n' || t.purpose || E'\nOpen Olympus HRIS → Transport → My trips to start it.');
  perform private.tms_queue_email(t.org_id, t.requested_by, t.id, 'tms_assigned_requester', 'Vehicle assigned: ' || t.purpose,
    'Your trip has a vehicle: ' || (select v.reg_no from public.tms_vehicles v where v.id = p_vehicle_id) || ', driver ' || private.tms_driver_name(d)
    || coalesce(' (' || coalesce(d.phone, (select e.phone from public.employees e where e.id = d.employee_id)) || ')', '') || '.');
  return private.tms_trip_json(t);
end;
$$;

-- For the assignment dialog: every active vehicle and driver with the reasons it cannot take this trip.
create or replace function public.tms_assign_options(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tms_trips := private.load_tms_trip(p_id);
begin
  perform private.require_permission('tms.manage');
  return jsonb_build_object(
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'reg_no', v.reg_no, 'vtype', v.vtype, 'seats', v.seats,
                                                               'default_driver_id', v.driver_id,
                                                               'problems', to_jsonb(private.tms_assign_problems(t, v.id, null))
                                                                           - 'Driver not found')
                                           order by v.reg_no)
                          from public.tms_vehicles v where v.org_id = t.org_id and v.status <> 'disposed'), '[]'::jsonb),
    'drivers', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', private.tms_driver_name(d), 'licence_class', d.licence_class,
                                                              'problems', to_jsonb(private.tms_assign_problems(t, null, d.id)) - 'Vehicle not found')
                                          order by private.tms_driver_name(d))
                         from public.tms_drivers d where d.org_id = t.org_id and d.status <> 'inactive'), '[]'::jsonb));
end;
$$;

create or replace function public.cancel_tms_trip(p_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.tms_trips := private.load_tms_trip(p_id);
begin
  if not (t.requested_by = auth.uid() or private.has_permission('tms.manage')) then
    raise exception 'Only the requester or the transport desk can cancel a trip' using errcode = '42501';
  end if;
  if t.status not in ('requested', 'approved', 'assigned') then
    raise exception 'A trip that has started or ended cannot be cancelled' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Write why the trip is cancelled' using errcode = '22023';
  end if;
  update public.tms_trips set status = 'cancelled', decision_note = btrim(p_reason) where id = t.id;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: the driver starts and ends, adds expenses
-- -----------------------------------------------------------------------------
create or replace function private.tms_require_trip_driver(t public.tms_trips)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (private.has_permission('tms.manage') or coalesce(t.driver_id = private.tms_my_driver_id(), false)) then
    raise exception 'Only the trip''s driver or the transport desk can do this' using errcode = '42501';
  end if;
end;
$$;

-- p: {odometer_km, lat, lng, accuracy_m}
create or replace function public.start_tms_trip(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t     public.tms_trips := private.load_tms_trip(p_id);
  v     public.tms_vehicles;
  v_odo numeric := nullif(p ->> 'odometer_km', '')::numeric;
  v_lat numeric := nullif(p ->> 'lat', '')::numeric;
  v_lng numeric := nullif(p ->> 'lng', '')::numeric;
begin
  perform private.tms_require_trip_driver(t);
  if t.status <> 'assigned' then
    raise exception 'Only an assigned trip can start' using errcode = '23514';
  end if;
  select * into v from public.tms_vehicles where id = t.vehicle_id for update;
  if v_odo is null then
    raise exception 'Enter the odometer reading' using errcode = '22023';
  end if;
  if v_odo < v.odometer_km then
    raise exception 'The odometer cannot be lower than the last reading (% km)', v.odometer_km using errcode = '23514';
  end if;
  update public.tms_trips set status = 'in_progress', started_at = now(), start_odometer = v_odo, start_lat = v_lat, start_lng = v_lng
   where id = t.id returning * into t;
  update public.tms_vehicles set odometer_km = v_odo where id = v.id;
  if v_lat is not null and v_lng is not null then
    insert into public.tms_locations (org_id, vehicle_id, driver_id, trip_id, event, lat, lng, accuracy_m)
    values (t.org_id, t.vehicle_id, t.driver_id, t.id, 'trip_start', v_lat, v_lng, nullif(p ->> 'accuracy_m', '')::numeric);
  end if;
  return private.tms_trip_json(t);
end;
$$;

create or replace function public.end_tms_trip(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  t     public.tms_trips := private.load_tms_trip(p_id);
  v_odo numeric := nullif(p ->> 'odometer_km', '')::numeric;
  v_lat numeric := nullif(p ->> 'lat', '')::numeric;
  v_lng numeric := nullif(p ->> 'lng', '')::numeric;
begin
  perform private.tms_require_trip_driver(t);
  if t.status <> 'in_progress' then
    raise exception 'Only a running trip can end' using errcode = '23514';
  end if;
  if v_odo is null or v_odo < t.start_odometer then
    raise exception 'The end odometer must be at least the start reading (% km)', t.start_odometer using errcode = '23514';
  end if;
  update public.tms_trips set status = 'completed', ended_at = now(), end_odometer = v_odo, end_lat = v_lat, end_lng = v_lng
   where id = t.id returning * into t;
  update public.tms_vehicles set odometer_km = greatest(odometer_km, v_odo) where id = t.vehicle_id;
  if v_lat is not null and v_lng is not null then
    insert into public.tms_locations (org_id, vehicle_id, driver_id, trip_id, event, lat, lng, accuracy_m)
    values (t.org_id, t.vehicle_id, t.driver_id, t.id, 'trip_end', v_lat, v_lng, nullif(p ->> 'accuracy_m', '')::numeric);
  end if;
  return private.tms_trip_json(t);
end;
$$;

-- p: {kind, amount, note, receipt_path}
create or replace function public.add_tms_trip_expense(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  t    public.tms_trips := private.load_tms_trip(p_id);
  v_id uuid;
  v_path text := private.jtext(p, 'receipt_path');
begin
  perform private.tms_require_trip_driver(t);
  if t.status not in ('in_progress', 'completed') then
    raise exception 'Expenses are added to a running or finished trip' using errcode = '23514';
  end if;
  if coalesce(p ->> 'kind', '') not in ('toll', 'parking', 'fine', 'food', 'other') then
    raise exception 'Choose the kind of expense' using errcode = '22023';
  end if;
  if coalesce(nullif(p ->> 'amount', '')::numeric, 0) <= 0 then
    raise exception 'Enter the amount' using errcode = '22023';
  end if;
  if v_path is not null and v_path not like t.org_id || '/trip/' || t.id || '/%' then
    raise exception 'The receipt must be uploaded for this trip' using errcode = '22023';
  end if;
  insert into public.tms_trip_expenses (org_id, trip_id, kind, amount, note, receipt_path)
  values (t.org_id, t.id, p ->> 'kind', (p ->> 'amount')::numeric, private.jtext(p, 'note'), v_path)
  returning id into v_id;
  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- API: lists
-- -----------------------------------------------------------------------------
-- p: {scope: mine | approve | all | driver, status, from, to}
create or replace function public.list_tms_trips(p jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_scope text := coalesce(nullif(p ->> 'scope', ''), 'mine');
  v_me    uuid := private.tms_my_driver_id();
  v_from  timestamptz := coalesce(nullif(p ->> 'from', '')::date, current_date - 60)::timestamptz;
  v_to    timestamptz := (coalesce(nullif(p ->> 'to', '')::date, current_date + 60) + 1)::timestamptz;
begin
  if v_scope = 'all' and not (private.has_permission('tms.manage') or private.has_permission('tms.view_costs')) then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(private.tms_trip_json(t) order by t.planned_start desc)
    from public.tms_trips t
    where t.org_id = v_org and t.planned_start >= v_from and t.planned_start < v_to
      and (nullif(p ->> 'status', '') is null or t.status = p ->> 'status')
      and case v_scope
            when 'mine' then t.requested_by = auth.uid()
            when 'approve' then t.status = 'requested' and t.requested_by <> auth.uid() and private.tms_can_approve(t)
            when 'driver' then v_me is not null and t.driver_id = v_me
            when 'all' then true
            else false end), '[]'::jsonb);
end;
$$;

create or replace function public.get_tms_trip(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tms_trips := private.load_tms_trip(p_id);
begin
  return private.tms_trip_json(t) || jsonb_build_object(
    'expenses', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind, 'amount', x.amount, 'note', x.note,
                                                              'receipt_path', x.receipt_path, 'created_at', x.created_at,
                                                              'by', private.dms_user_name(x.created_by)) order by x.created_at)
                          from public.tms_trip_expenses x where x.trip_id = t.id and x.status = 'active'), '[]'::jsonb),
    'points', coalesce((select jsonb_agg(jsonb_build_object('event', l.event, 'lat', l.lat, 'lng', l.lng, 'accuracy_m', l.accuracy_m,
                                                            'at', l.recorded_at) order by l.recorded_at)
                        from public.tms_locations l where l.trip_id = t.id), '[]'::jsonb));
end;
$$;

-- Who am I in transport: what tabs to show.
create or replace function public.get_tms_me()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if v_org is null then
    raise exception 'You are not a member of a company' using errcode = '42501';
  end if;
  perform private.seed_tms_defaults(v_org);
  return jsonb_build_object(
    'can', jsonb_build_object('manage', private.has_permission('tms.manage'), 'approve', private.has_permission('tms.approve'),
                              'inventory', private.has_permission('tms.inventory'), 'view_costs', private.has_permission('tms.view_costs'),
                              'see_fleet', private.tms_can_see()),
    'driver', public.my_tms_driver(),
    'to_approve', (select count(*) from public.tms_trips t where t.org_id = v_org and t.status = 'requested'
                   and t.requested_by <> auth.uid() and private.tms_can_approve(t)),
    'to_assign', case when private.has_permission('tms.manage') then (select count(*) from public.tms_trips t where t.org_id = v_org and t.status = 'approved') else 0 end,
    'my_open_trips', (select count(*) from public.tms_trips t where t.org_id = v_org and t.status in ('assigned', 'in_progress')
                      and t.driver_id = private.tms_my_driver_id()));
end;
$$;

-- -----------------------------------------------------------------------------
-- Storage: tms-files/{org}/{kind}/{id}/{file} (receipts, photos)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('tms-files', 'tms-files', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.tms_file_access(p_name text, p_write boolean)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  t       public.tms_trips;
begin
  if array_length(v_parts, 1) <> 4 or v_parts[1] !~ '^[0-9a-f-]{36}$' or v_parts[3] !~ '^[0-9a-f-]{36}$'
     or v_parts[1]::uuid is distinct from private.current_org_id() then
    return false;
  end if;
  if private.has_permission('tms.manage') then
    return true;
  end if;
  if v_parts[2] = 'trip' then
    select * into t from public.tms_trips where id = v_parts[3]::uuid and org_id = v_parts[1]::uuid;
    return found and coalesce(t.driver_id = private.tms_my_driver_id(), false);
  end if;
  return false;
end;
$$;

drop policy if exists olympus_tms_files_select on storage.objects;
drop policy if exists olympus_tms_files_insert on storage.objects;
create policy olympus_tms_files_select on storage.objects for select to authenticated
  using (bucket_id = 'tms-files' and private.tms_file_access(name, false));
create policy olympus_tms_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'tms-files' and private.tms_file_access(name, true));

-- -----------------------------------------------------------------------------
-- Privileges
-- -----------------------------------------------------------------------------
alter table public.tms_trips         enable row level security;
alter table public.tms_trip_expenses enable row level security;
alter table public.tms_locations     enable row level security;
revoke all on table public.tms_trips, public.tms_trip_expenses, public.tms_locations from anon, authenticated;

revoke all on function
  public.create_tms_trip(jsonb), public.decide_tms_trip(uuid, boolean, text), public.assign_tms_trip(uuid, uuid, uuid),
  public.tms_assign_options(uuid), public.cancel_tms_trip(uuid, text), public.start_tms_trip(uuid, jsonb), public.end_tms_trip(uuid, jsonb),
  public.add_tms_trip_expense(uuid, jsonb), public.list_tms_trips(jsonb), public.get_tms_trip(uuid), public.get_tms_me()
from public, anon;
grant execute on function
  public.create_tms_trip(jsonb), public.decide_tms_trip(uuid, boolean, text), public.assign_tms_trip(uuid, uuid, uuid),
  public.tms_assign_options(uuid), public.cancel_tms_trip(uuid, text), public.start_tms_trip(uuid, jsonb), public.end_tms_trip(uuid, jsonb),
  public.add_tms_trip_expense(uuid, jsonb), public.list_tms_trips(jsonb), public.get_tms_trip(uuid), public.get_tms_me()
to authenticated;
revoke all on function
  private.tms_my_driver_id(), private.tms_can_approve(public.tms_trips), private.tms_can_see_trip(public.tms_trips),
  private.load_tms_trip(uuid), private.tms_queue_email(uuid, uuid, uuid, text, text, text), private.tms_trip_json(public.tms_trips),
  private.tms_assign_problems(public.tms_trips, uuid, uuid), private.tms_require_trip_driver(public.tms_trips)
from public, anon, authenticated;
grant execute on function private.tms_file_access(text, boolean) to authenticated;
revoke all on function private.tms_file_access(text, boolean) from public, anon;
