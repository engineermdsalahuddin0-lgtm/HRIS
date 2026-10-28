-- =============================================================================
-- TMS T3: fuel — fill log, company prices, km per unit, fraud flags, verification.
-- Module handbook: src/TMS/architecture.md section 3 (fuel flow), features.md (T3).
--
--   * A fill: vehicle, fuel (one of the vehicle's fuels), quantity in the fuel's unit
--     (litres for octane / petrol / diesel / LPG, m³ for CNG, kWh for electric), unit
--     price, amount, odometer, full tank or not, station, who paid, receipt, one GPS
--     point. Logged by the vehicle's driver (default driver, or driver of a running
--     trip on it) or the transport desk.
--   * km per unit is measured between two full-tank fills of the same fuel: distance
--     ÷ everything filled after the first full fill up to this one.
--   * Flags (the fill is saved, then waits for the desk): over_tank (more than the
--     tank / cylinder holds + 5%), odometer_back (below the vehicle's reading),
--     price_off (unit price off the company price by more than the tolerance),
--     low_efficiency (km per unit below the vehicle's normal by more than the
--     tolerance). The desk verifies or disputes (a dispute needs a reason).
-- =============================================================================

do $guard$
begin
  if to_regproc('public.create_tms_trip') is null then
    raise exception 'Apply 20261105000200_tms_t2_trips.sql first, then run this file again';
  end if;
end;
$guard$;

create table public.tms_fuel_logs (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.organizations (id),
  vehicle_id    uuid not null,
  driver_id     uuid,
  trip_id       uuid,
  fuel          text not null check (fuel in ('octane', 'petrol', 'diesel', 'cng', 'lpg', 'electric')),
  unit          text not null check (unit in ('l', 'm3', 'kwh')),
  quantity      numeric(9, 2) not null check (quantity > 0 and quantity <= 5000),
  unit_price    numeric(9, 2) not null check (unit_price > 0 and unit_price <= 10000),
  amount        numeric(12, 2) not null check (amount > 0),
  odometer_km   numeric(10, 1) not null check (odometer_km >= 0),
  full_tank     boolean not null default true,
  station       text check (station is null or char_length(station) <= 120),
  paid_by       text not null default 'company' check (paid_by in ('company', 'driver_cash', 'card')),
  receipt_path  text,
  lat           numeric(9, 6),
  lng           numeric(9, 6),
  filled_at     timestamptz not null default now(),
  km_per_unit   numeric(8, 2),
  flags         text[] not null default '{}',
  status        text not null default 'recorded' check (status in ('recorded', 'flagged', 'verified', 'disputed')),
  review_note   text check (review_note is null or char_length(review_note) <= 500),
  reviewed_by   uuid references public.user_profiles (id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint tms_fuel_logs_org_id_id_uq unique (org_id, id),
  constraint tms_fuel_logs_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_fuel_logs_driver_fk foreign key (org_id, driver_id) references public.tms_drivers (org_id, id),
  constraint tms_fuel_logs_trip_fk foreign key (org_id, trip_id) references public.tms_trips (org_id, id)
);
create index tms_fuel_logs_vehicle_idx on public.tms_fuel_logs (org_id, vehicle_id, filled_at desc);
create index tms_fuel_logs_flagged_idx on public.tms_fuel_logs (org_id, status) where status = 'flagged';
select private.attach_standard_triggers('public.tms_fuel_logs');

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.tms_fuel_unit(p_fuel text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_fuel when 'cng' then 'm3' when 'electric' then 'kwh' else 'l' end
$$;

-- The caller drives this vehicle now (its default driver, or the driver of a running trip on it).
create or replace function private.tms_drives_vehicle(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.tms_my_driver_id() is not null and (
           exists (select 1 from public.tms_vehicles v where v.id = p_vehicle_id and v.driver_id = private.tms_my_driver_id())
           or exists (select 1 from public.tms_trips t where t.vehicle_id = p_vehicle_id and t.status = 'in_progress'
                      and t.driver_id = private.tms_my_driver_id())), false)
$$;

create or replace function private.tms_fuel_json(f public.tms_fuel_logs)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', f.id, 'vehicle_id', f.vehicle_id, 'reg_no', (select v.reg_no from public.tms_vehicles v where v.id = f.vehicle_id),
    'driver', (select private.tms_driver_name(d) from public.tms_drivers d where d.id = f.driver_id),
    'trip_id', f.trip_id, 'fuel', f.fuel, 'unit', f.unit, 'quantity', f.quantity, 'unit_price', f.unit_price, 'amount', f.amount,
    'odometer_km', f.odometer_km, 'full_tank', f.full_tank, 'station', f.station, 'paid_by', f.paid_by, 'receipt_path', f.receipt_path,
    'point', case when f.lat is not null then jsonb_build_object('lat', f.lat, 'lng', f.lng) end,
    'filled_at', f.filled_at, 'km_per_unit', f.km_per_unit, 'flags', to_jsonb(f.flags), 'status', f.status,
    'review_note', f.review_note, 'reviewed_by', private.dms_user_name(f.reviewed_by), 'reviewed_at', f.reviewed_at,
    'logged_by', private.dms_user_name(f.created_by))
$$;

-- -----------------------------------------------------------------------------
-- API
-- -----------------------------------------------------------------------------
-- p: {vehicle_id, fuel, quantity, unit_price, amount, odometer_km, full_tank, station, paid_by, receipt_path, lat, lng, filled_at, trip_id}
create or replace function public.log_tms_fuel(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v        public.tms_vehicles;
  s        public.tms_settings;
  f        public.tms_fuel_logs;
  v_fuel   text := p ->> 'fuel';
  v_qty    numeric := nullif(p ->> 'quantity', '')::numeric;
  v_price  numeric := nullif(p ->> 'unit_price', '')::numeric;
  v_amount numeric := nullif(p ->> 'amount', '')::numeric;
  v_odo    numeric := nullif(p ->> 'odometer_km', '')::numeric;
  v_full   boolean := coalesce((p ->> 'full_tank')::boolean, true);
  v_flags  text[] := '{}';
  v_kpu    numeric;
  v_prev   public.tms_fuel_logs;
  v_cap    numeric;
  v_list   numeric;
  v_path   text := private.jtext(p, 'receipt_path');
  v_trip   uuid := nullif(p ->> 'trip_id', '')::uuid;
begin
  select * into v from public.tms_vehicles where id = nullif(p ->> 'vehicle_id', '')::uuid and org_id = v_org for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if not (private.has_permission('tms.manage') or private.tms_drives_vehicle(v.id)) then
    raise exception 'Only the vehicle''s driver or the transport desk can log fuel' using errcode = '42501';
  end if;
  if v_fuel is null or v_fuel not in (v.fuel, coalesce(v.fuel2, v.fuel)) then
    raise exception 'This vehicle runs on %', v.fuel || coalesce(' or ' || v.fuel2, '') using errcode = '22023';
  end if;
  if v_qty is null or v_qty <= 0 then
    raise exception 'Enter the quantity' using errcode = '22023';
  end if;
  if v_odo is null then
    raise exception 'Enter the odometer reading' using errcode = '22023';
  end if;
  -- Unit price and amount: either one is enough; both must agree within ৳1.
  if v_price is null and v_amount is not null then v_price := round(v_amount / v_qty, 2); end if;
  if v_amount is null and v_price is not null then v_amount := round(v_qty * v_price, 2); end if;
  if v_price is null or v_amount is null then
    raise exception 'Enter the unit price or the amount' using errcode = '22023';
  end if;
  if abs(v_amount - v_qty * v_price) > greatest(1, v_amount * 0.01) then
    raise exception 'Quantity × price (৳%) does not match the amount (৳%)', round(v_qty * v_price, 2), v_amount using errcode = '22023';
  end if;
  if coalesce(p ->> 'paid_by', 'company') not in ('company', 'driver_cash', 'card') then
    raise exception 'Unknown payer' using errcode = '22023';
  end if;
  if v_path is not null and v_path not like v_org || '/fuel/' || v.id || '/%' then
    raise exception 'The receipt must be uploaded for this vehicle' using errcode = '22023';
  end if;
  if v_trip is not null and not exists (select 1 from public.tms_trips t where t.id = v_trip and t.org_id = v_org and t.vehicle_id = v.id) then
    raise exception 'That trip is not on this vehicle' using errcode = '22023';
  end if;
  select * into s from public.tms_settings where org_id = v_org;

  -- Flags
  v_cap := case when v_fuel = 'cng' then v.cng_m3 when v_fuel = 'electric' then null else v.tank_l end;
  if v_cap is not null and v_qty > v_cap * 1.05 then
    v_flags := array_append(v_flags, 'over_tank'::text);
  end if;
  if v_odo < v.odometer_km then
    v_flags := array_append(v_flags, 'odometer_back'::text);
  end if;
  v_list := nullif(s.fuel_prices ->> v_fuel, '')::numeric;
  if v_list is not null and abs(v_price - v_list) > v_list * s.price_tolerance_pct / 100.0 then
    v_flags := array_append(v_flags, 'price_off'::text);
  end if;
  -- km per unit since the previous full fill of the same fuel.
  if v_full then
    select * into v_prev from public.tms_fuel_logs
    where vehicle_id = v.id and fuel = v_fuel and full_tank and status <> 'disputed' and odometer_km < v_odo
    order by odometer_km desc limit 1;
    if v_prev.id is not null then
      v_kpu := round((v_odo - v_prev.odometer_km) / (v_qty + coalesce((
                 select sum(x.quantity) from public.tms_fuel_logs x
                 where x.vehicle_id = v.id and x.fuel = v_fuel and x.status <> 'disputed'
                   and x.odometer_km > v_prev.odometer_km and x.odometer_km < v_odo), 0)), 2);
      if v.normal_km_per_unit is not null and v_kpu < v.normal_km_per_unit * (1 - s.efficiency_tolerance_pct / 100.0) then
        v_flags := array_append(v_flags, 'low_efficiency'::text);
      end if;
    end if;
  end if;

  insert into public.tms_fuel_logs (org_id, vehicle_id, driver_id, trip_id, fuel, unit, quantity, unit_price, amount, odometer_km, full_tank,
                                    station, paid_by, receipt_path, lat, lng, filled_at, km_per_unit, flags, status)
  values (v_org, v.id, private.tms_my_driver_id(), v_trip, v_fuel, private.tms_fuel_unit(v_fuel), v_qty, v_price, v_amount, v_odo, v_full,
          private.jtext(p, 'station'), coalesce(p ->> 'paid_by', 'company'), v_path, nullif(p ->> 'lat', '')::numeric,
          nullif(p ->> 'lng', '')::numeric, coalesce(nullif(p ->> 'filled_at', '')::timestamptz, now()), v_kpu, v_flags,
          case when cardinality(v_flags) > 0 then 'flagged' else 'recorded' end)
  returning * into f;
  if v_odo > v.odometer_km then
    update public.tms_vehicles set odometer_km = v_odo where id = v.id;
  end if;
  if f.lat is not null and f.lng is not null then
    insert into public.tms_locations (org_id, vehicle_id, driver_id, trip_id, event, lat, lng)
    values (v_org, v.id, f.driver_id, f.trip_id, 'fuel', f.lat, f.lng);
  end if;
  return private.tms_fuel_json(f);
end;
$$;

create or replace function public.review_tms_fuel(p_id uuid, p_ok boolean, p_note text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.tms_fuel_logs;
begin
  perform private.require_permission('tms.manage');
  select * into f from public.tms_fuel_logs where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Fuel record not found' using errcode = 'P0002';
  end if;
  if not coalesce(p_ok, false) and char_length(btrim(coalesce(p_note, ''))) < 3 then
    raise exception 'Write why the fill is disputed' using errcode = '22023';
  end if;
  update public.tms_fuel_logs set status = case when p_ok then 'verified' else 'disputed' end,
         review_note = nullif(btrim(coalesce(p_note, '')), ''), reviewed_by = auth.uid(), reviewed_at = now()
   where id = f.id;
end;
$$;

-- p: {scope: mine | all, vehicle_id, flagged, from, to}
create or replace function public.list_tms_fuel(p jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_all  boolean := coalesce(p ->> 'scope', 'all') = 'all';
  v_from timestamptz := coalesce(nullif(p ->> 'from', '')::date, current_date - 90)::timestamptz;
  v_to   timestamptz := (coalesce(nullif(p ->> 'to', '')::date, current_date) + 1)::timestamptz;
begin
  if v_all and not (private.has_permission('tms.manage') or private.has_permission('tms.view_costs')) then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(private.tms_fuel_json(f) order by f.filled_at desc)
    from public.tms_fuel_logs f
    where f.org_id = v_org and f.filled_at >= v_from and f.filled_at < v_to
      and (v_all or f.created_by = auth.uid())
      and (nullif(p ->> 'vehicle_id', '') is null or f.vehicle_id = (p ->> 'vehicle_id')::uuid)
      and (not coalesce((p ->> 'flagged')::boolean, false) or f.status = 'flagged')), '[]'::jsonb);
end;
$$;

-- Vehicles the caller may log fuel for (the desk: every active vehicle; a driver: the ones they drive now).
create or replace function public.tms_fuel_vehicles()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'reg_no', v.reg_no, 'fuel', v.fuel, 'fuel2', v.fuel2, 'odometer_km', v.odometer_km,
                                               'tank_l', v.tank_l, 'cng_m3', v.cng_m3,
                                               'price', (select s.fuel_prices from public.tms_settings s where s.org_id = v.org_id),
                                               'trip_id', (select t.id from public.tms_trips t where t.vehicle_id = v.id and t.status = 'in_progress' limit 1))
                            order by v.reg_no), '[]'::jsonb)
  from public.tms_vehicles v
  where v.org_id = private.current_org_id() and v.status in ('active', 'in_maintenance')
    and (private.has_permission('tms.manage') or private.tms_drives_vehicle(v.id))
$$;

-- p: {fuel_prices: {octane: 130, …}, price_tolerance_pct, efficiency_tolerance_pct}
create or replace function public.save_tms_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  k text;
begin
  perform private.require_permission('tms.manage');
  if p ? 'fuel_prices' then
    if jsonb_typeof(p -> 'fuel_prices') <> 'object' then
      raise exception 'Fuel prices must be a list per fuel' using errcode = '22023';
    end if;
    for k in select jsonb_object_keys(p -> 'fuel_prices') loop
      if k not in ('octane', 'petrol', 'diesel', 'cng', 'lpg', 'electric')
         or (nullif(p -> 'fuel_prices' ->> k, '') is not null and (p -> 'fuel_prices' ->> k)::numeric <= 0) then
        raise exception 'Unknown fuel or price: %', k using errcode = '22023';
      end if;
    end loop;
  end if;
  if coalesce((p ->> 'price_tolerance_pct')::int, 10) not between 0 and 100
     or coalesce((p ->> 'efficiency_tolerance_pct')::int, 25) not between 0 and 100 then
    raise exception 'Tolerances are 0 to 100 percent' using errcode = '22023';
  end if;
  update public.tms_settings
     set fuel_prices = case when p ? 'fuel_prices' then jsonb_strip_nulls(p -> 'fuel_prices') else fuel_prices end,
         price_tolerance_pct = coalesce((p ->> 'price_tolerance_pct')::smallint, price_tolerance_pct),
         efficiency_tolerance_pct = coalesce((p ->> 'efficiency_tolerance_pct')::smallint, efficiency_tolerance_pct)
   where org_id = private.current_org_id();
end;
$$;

create or replace function public.get_tms_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('fuel_prices', s.fuel_prices, 'price_tolerance_pct', s.price_tolerance_pct,
                            'efficiency_tolerance_pct', s.efficiency_tolerance_pct)
  from public.tms_settings s where s.org_id = private.current_org_id() and private.tms_can_see()
$$;

-- Storage: fuel receipts at tms-files/{org}/fuel/{vehicle}/{file}: the desk, or a driver of that vehicle.
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
  if v_parts[2] = 'fuel' then
    return private.tms_drives_vehicle(v_parts[3]::uuid);
  end if;
  return false;
end;
$$;

alter table public.tms_fuel_logs enable row level security;
revoke all on table public.tms_fuel_logs from anon, authenticated;
revoke all on function public.log_tms_fuel(jsonb), public.review_tms_fuel(uuid, boolean, text), public.list_tms_fuel(jsonb),
  public.tms_fuel_vehicles(), public.save_tms_settings(jsonb), public.get_tms_settings() from public, anon;
grant execute on function public.log_tms_fuel(jsonb), public.review_tms_fuel(uuid, boolean, text), public.list_tms_fuel(jsonb),
  public.tms_fuel_vehicles(), public.save_tms_settings(jsonb), public.get_tms_settings() to authenticated;
revoke all on function private.tms_fuel_unit(text), private.tms_drives_vehicle(uuid), private.tms_fuel_json(public.tms_fuel_logs)
from public, anon, authenticated;
