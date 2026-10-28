-- =============================================================================
-- TMS T5: cost dashboard and the owner's live view.
-- Module handbook: src/TMS/features.md (T5), security.md (costs only for tms.view_costs).
--
-- Per vehicle and period:
--   distance  = highest − lowest odometer reading in the period (trip start / end,
--               fuel fills, job cards)
--   fuel      = quantity per unit and cost (disputed fills left out)
--   repairs   = closed job cards (labour + outside parts + parts issued to them)
--               + parts issued straight to the vehicle
--   trip cost = tolls, parking, fines, food, other on trips started in the period
--   total, cost per km, average km per unit (from the fills that have it)
-- Live: vehicles on a trip now with their driver and the last GPS point.
-- Only tms.view_costs (and the Admin) see money totals.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.tms_stock_move') is null then
    raise exception 'Apply 20261105000400_tms_t4_maintenance.sql first, then run this file again';
  end if;
end;
$guard$;

create or replace function public.get_tms_costs(p_from date default null, p_to date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_from timestamptz := coalesce(p_from, date_trunc('month', current_date)::date)::timestamptz;
  v_to   timestamptz := (coalesce(p_to, current_date) + 1)::timestamptz;
begin
  perform private.require_permission('tms.view_costs');
  if v_to <= v_from or v_to > v_from + interval '3 years 1 day' then
    raise exception 'Choose a period of at most 3 years' using errcode = '22023';
  end if;
  return (
    with readings as (
      select t.vehicle_id, t.start_odometer as km from public.tms_trips t
      where t.org_id = v_org and t.started_at >= v_from and t.started_at < v_to and t.start_odometer is not null
      union all
      select t.vehicle_id, t.end_odometer from public.tms_trips t
      where t.org_id = v_org and t.ended_at >= v_from and t.ended_at < v_to and t.end_odometer is not null
      union all
      select f.vehicle_id, f.odometer_km from public.tms_fuel_logs f
      where f.org_id = v_org and f.filled_at >= v_from and f.filled_at < v_to and f.status <> 'disputed'
      union all
      select j.vehicle_id, j.odometer_km from public.tms_job_cards j
      where j.org_id = v_org and j.closed_at >= v_from and j.closed_at < v_to and j.status = 'closed' and j.odometer_km is not null
    ), per_vehicle as (
      select v.id, v.reg_no, v.vtype, v.status,
             coalesce((select max(r.km) - min(r.km) from readings r where r.vehicle_id = v.id), 0) as distance_km,
             coalesce((select sum(f.amount) from public.tms_fuel_logs f
                       where f.vehicle_id = v.id and f.filled_at >= v_from and f.filled_at < v_to and f.status <> 'disputed'), 0) as fuel_cost,
             coalesce((select jsonb_object_agg(x.unit, x.qty) from (
                         select f.unit, sum(f.quantity) as qty from public.tms_fuel_logs f
                         where f.vehicle_id = v.id and f.filled_at >= v_from and f.filled_at < v_to and f.status <> 'disputed'
                         group by f.unit) x), '{}'::jsonb) as fuel_qty,
             (select round(avg(f.km_per_unit), 2) from public.tms_fuel_logs f
              where f.vehicle_id = v.id and f.filled_at >= v_from and f.filled_at < v_to and f.status <> 'disputed' and f.km_per_unit is not null) as km_per_unit,
             coalesce((select sum(j.labour_cost + j.outside_parts_cost) from public.tms_job_cards j
                       where j.vehicle_id = v.id and j.status = 'closed' and j.closed_at >= v_from and j.closed_at < v_to), 0)
             + coalesce((select sum(m.qty * m.unit_cost) from public.tms_stock_moves m
                         left join public.tms_job_cards j on j.id = m.job_card_id
                         where m.vehicle_id = v.id and m.kind = 'issue'
                           and ((m.job_card_id is null and m.moved_at >= v_from and m.moved_at < v_to)
                                or (j.status = 'closed' and j.closed_at >= v_from and j.closed_at < v_to))), 0) as repair_cost,
             coalesce((select sum(x.amount) from public.tms_trip_expenses x join public.tms_trips t on t.id = x.trip_id
                       where t.vehicle_id = v.id and x.status = 'active' and t.started_at >= v_from and t.started_at < v_to), 0) as trip_cost,
             (select count(*) from public.tms_trips t where t.vehicle_id = v.id and t.status = 'completed'
                and t.started_at >= v_from and t.started_at < v_to) as trips,
             (select count(*) from public.tms_fuel_logs f where f.vehicle_id = v.id and f.status = 'flagged') as flagged_fills
      from public.tms_vehicles v
      where v.org_id = v_org and (v.status <> 'disposed' or exists (select 1 from readings r where r.vehicle_id = v.id))
    ), rows as (
      select pv.*, pv.fuel_cost + pv.repair_cost + pv.trip_cost as total_cost from per_vehicle pv
    )
    select jsonb_build_object(
      'from', v_from::date, 'to', (v_to - interval '1 day')::date,
      'vehicles', coalesce((select jsonb_agg(jsonb_build_object(
                    'id', r.id, 'reg_no', r.reg_no, 'vtype', r.vtype, 'status', r.status, 'distance_km', r.distance_km,
                    'fuel_cost', r.fuel_cost, 'fuel_qty', r.fuel_qty, 'km_per_unit', r.km_per_unit, 'repair_cost', r.repair_cost,
                    'trip_cost', r.trip_cost, 'total_cost', r.total_cost, 'trips', r.trips, 'flagged_fills', r.flagged_fills,
                    'cost_per_km', case when r.distance_km > 0 then round(r.total_cost / r.distance_km, 2) end)
                    order by r.total_cost desc, r.reg_no) from rows r), '[]'::jsonb),
      'totals', (select jsonb_build_object(
                   'distance_km', coalesce(sum(r.distance_km), 0), 'fuel_cost', coalesce(sum(r.fuel_cost), 0),
                   'repair_cost', coalesce(sum(r.repair_cost), 0), 'trip_cost', coalesce(sum(r.trip_cost), 0),
                   'total_cost', coalesce(sum(r.total_cost), 0), 'trips', coalesce(sum(r.trips), 0),
                   'cost_per_km', case when sum(r.distance_km) > 0 then round(sum(r.total_cost) / sum(r.distance_km), 2) end)
                 from rows r),
      'live', coalesce((select jsonb_agg(jsonb_build_object(
                  'trip_id', t.id, 'reg_no', v.reg_no, 'driver', private.tms_driver_name(d), 'from_place', t.from_place, 'to_place', t.to_place,
                  'started_at', t.started_at,
                  'last_point', (select jsonb_build_object('lat', l.lat, 'lng', l.lng, 'at', l.recorded_at, 'event', l.event)
                                 from public.tms_locations l where l.vehicle_id = v.id order by l.recorded_at desc limit 1))
                  order by t.started_at)
                from public.tms_trips t join public.tms_vehicles v on v.id = t.vehicle_id join public.tms_drivers d on d.id = t.driver_id
                where t.org_id = v_org and t.status = 'in_progress'), '[]'::jsonb))
  );
end;
$$;

revoke all on function public.get_tms_costs(date, date) from public, anon;
grant execute on function public.get_tms_costs(date, date) to authenticated;
