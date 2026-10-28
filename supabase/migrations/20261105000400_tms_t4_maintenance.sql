-- =============================================================================
-- TMS T4: maintenance (service plans, job cards) and inventory (parts, tyres).
-- Module handbook: src/TMS/architecture.md section 3 (maintenance flow), features.md (T4).
--
--   * Service plans per vehicle: every N km and / or every N months since the last
--     service. Status: overdue, due soon (within 500 km or 15 days), ok.
--   * Job cards (tms.manage): service / repair / accident, workshop, odometer,
--     labour and outside parts cost, parts issued from stock. Opening one puts the
--     vehicle in maintenance; closing the last open one makes it active again and
--     moves its service plan's "last done" to this km and date.
--   * Stock (tms.inventory): parts, tyres, lubricants, batteries with a minimum level.
--     Moves only (insert-only history): receive (weighted average cost), issue to a
--     job card or a vehicle (never below zero, at average cost), adjust (needs a
--     reason). The desk (tms.manage) may also issue to its job cards.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.log_tms_fuel') is null then
    raise exception 'Apply 20261105000300_tms_t3_fuel.sql first, then run this file again';
  end if;
end;
$guard$;

create table public.tms_service_plans (
  id           uuid primary key default gen_random_uuid(),
  org_id       uuid not null references public.organizations (id),
  vehicle_id   uuid not null,
  name         text not null check (char_length(btrim(name)) between 2 and 80),
  every_km     integer check (every_km is null or every_km between 100 and 500000),
  every_months smallint check (every_months is null or every_months between 1 and 120),
  last_km      numeric(10, 1),
  last_date    date,
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references public.user_profiles (id),
  updated_by   uuid references public.user_profiles (id),
  constraint tms_service_plans_org_id_id_uq unique (org_id, id),
  constraint tms_service_plans_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_service_plans_rule check (every_km is not null or every_months is not null)
);
select private.attach_standard_triggers('public.tms_service_plans');

create table public.tms_job_cards (
  id                 uuid primary key default gen_random_uuid(),
  org_id             uuid not null references public.organizations (id),
  vehicle_id         uuid not null,
  plan_id            uuid,
  kind               text not null check (kind in ('service', 'repair', 'accident')),
  workshop           text check (workshop is null or char_length(workshop) <= 120),
  description        text not null check (char_length(btrim(description)) between 3 and 1000),
  odometer_km        numeric(10, 1),
  opened_at          timestamptz not null default now(),
  closed_at          timestamptz,
  labour_cost        numeric(12, 2) not null default 0 check (labour_cost >= 0),
  outside_parts_cost numeric(12, 2) not null default 0 check (outside_parts_cost >= 0),
  status             text not null default 'open' check (status in ('open', 'closed', 'cancelled')),
  close_note         text check (close_note is null or char_length(close_note) <= 500),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid references public.user_profiles (id),
  updated_by         uuid references public.user_profiles (id),
  constraint tms_job_cards_org_id_id_uq unique (org_id, id),
  constraint tms_job_cards_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_job_cards_plan_fk foreign key (org_id, plan_id) references public.tms_service_plans (org_id, id)
);
create index tms_job_cards_vehicle_idx on public.tms_job_cards (org_id, vehicle_id, status);
select private.attach_standard_triggers('public.tms_job_cards');

create table public.tms_parts (
  id         uuid primary key default gen_random_uuid(),
  org_id     uuid not null references public.organizations (id),
  code       text not null check (code ~ '^[A-Za-z0-9._/-]{1,30}$'),
  name       text not null check (char_length(btrim(name)) between 2 and 120),
  category   text not null default 'part' check (category in ('part', 'tyre', 'lubricant', 'battery', 'other')),
  unit       text not null default 'pcs' check (char_length(unit) between 1 and 12),
  on_hand    numeric(12, 2) not null default 0 check (on_hand >= 0),
  avg_cost   numeric(12, 2) not null default 0 check (avg_cost >= 0),
  min_stock  numeric(12, 2) not null default 0 check (min_stock >= 0),
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references public.user_profiles (id),
  updated_by uuid references public.user_profiles (id),
  constraint tms_parts_org_id_id_uq unique (org_id, id),
  constraint tms_parts_code_uq unique (org_id, code)
);
select private.attach_standard_triggers('public.tms_parts');

create table public.tms_stock_moves (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  part_id     uuid not null,
  kind        text not null check (kind in ('receive', 'issue', 'adjust')),
  qty         numeric(12, 2) not null check (qty <> 0),
  unit_cost   numeric(12, 2) not null default 0 check (unit_cost >= 0),
  vehicle_id  uuid,
  job_card_id uuid,
  supplier    text check (supplier is null or char_length(supplier) <= 120),
  ref         text check (ref is null or char_length(ref) <= 60),
  note        text check (note is null or char_length(note) <= 300),
  moved_at    timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id),
  constraint tms_stock_moves_part_fk foreign key (org_id, part_id) references public.tms_parts (org_id, id),
  constraint tms_stock_moves_vehicle_fk foreign key (org_id, vehicle_id) references public.tms_vehicles (org_id, id),
  constraint tms_stock_moves_job_fk foreign key (org_id, job_card_id) references public.tms_job_cards (org_id, id),
  constraint tms_stock_moves_sign check ((kind = 'adjust') or qty > 0)
);
create index tms_stock_moves_part_idx on public.tms_stock_moves (org_id, part_id, moved_at desc);
create index tms_stock_moves_job_idx on public.tms_stock_moves (job_card_id) where job_card_id is not null;
select private.attach_standard_triggers('public.tms_stock_moves');

-- Stock history is never edited.
create or replace function private.tms_stock_moves_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'Stock moves cannot be changed; make an adjustment instead' using errcode = '42501';
end;
$$;
create trigger tms_stock_moves_frozen before update on public.tms_stock_moves
  for each row execute function private.tms_stock_moves_frozen();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.tms_plan_json(sp public.tms_service_plans)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', sp.id, 'vehicle_id', sp.vehicle_id, 'reg_no', v.reg_no, 'name', sp.name, 'every_km', sp.every_km, 'every_months', sp.every_months,
    'last_km', sp.last_km, 'last_date', sp.last_date, 'active', sp.active, 'odometer_km', v.odometer_km,
    'next_km', case when sp.every_km is not null then coalesce(sp.last_km, 0) + sp.every_km end,
    'next_date', case when sp.every_months is not null and sp.last_date is not null then (sp.last_date + make_interval(months => sp.every_months))::date end,
    'km_left', case when sp.every_km is not null then coalesce(sp.last_km, 0) + sp.every_km - v.odometer_km end,
    'status', case
      when (sp.every_km is not null and v.odometer_km >= coalesce(sp.last_km, 0) + sp.every_km)
        or (sp.every_months is not null and sp.last_date is not null and current_date >= (sp.last_date + make_interval(months => sp.every_months))::date) then 'overdue'
      when (sp.every_km is not null and v.odometer_km >= coalesce(sp.last_km, 0) + sp.every_km - 500)
        or (sp.every_months is not null and sp.last_date is not null and current_date >= (sp.last_date + make_interval(months => sp.every_months))::date - 15) then 'due_soon'
      else 'ok' end)
  from public.tms_vehicles v where v.id = sp.vehicle_id
$$;

create or replace function private.tms_job_json(j public.tms_job_cards)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', j.id, 'vehicle_id', j.vehicle_id, 'reg_no', (select v.reg_no from public.tms_vehicles v where v.id = j.vehicle_id),
    'plan_id', j.plan_id, 'plan', (select sp.name from public.tms_service_plans sp where sp.id = j.plan_id),
    'kind', j.kind, 'workshop', j.workshop, 'description', j.description, 'odometer_km', j.odometer_km,
    'opened_at', j.opened_at, 'closed_at', j.closed_at, 'labour_cost', j.labour_cost, 'outside_parts_cost', j.outside_parts_cost,
    'stock_parts_cost', coalesce((select sum(m.qty * m.unit_cost) from public.tms_stock_moves m where m.job_card_id = j.id and m.kind = 'issue'), 0),
    'total_cost', j.labour_cost + j.outside_parts_cost
                  + coalesce((select sum(m.qty * m.unit_cost) from public.tms_stock_moves m where m.job_card_id = j.id and m.kind = 'issue'), 0),
    'parts', coalesce((select jsonb_agg(jsonb_build_object('part', p.name, 'code', p.code, 'qty', m.qty, 'unit', p.unit, 'unit_cost', m.unit_cost)
                                        order by m.moved_at)
                       from public.tms_stock_moves m join public.tms_parts p on p.id = m.part_id
                       where m.job_card_id = j.id and m.kind = 'issue'), '[]'::jsonb),
    'status', j.status, 'close_note', j.close_note, 'opened_by', private.dms_user_name(j.created_by))
$$;

-- -----------------------------------------------------------------------------
-- API: maintenance (tms.manage)
-- -----------------------------------------------------------------------------
-- p: {vehicle_id, name, every_km, every_months, last_km, last_date, active}
create or replace function public.save_tms_service_plan(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_id  uuid;
  v_km  integer := nullif(p ->> 'every_km', '')::integer;
  v_mo  smallint := nullif(p ->> 'every_months', '')::smallint;
begin
  perform private.require_permission('tms.manage');
  if v_km is null and v_mo is null then
    raise exception 'Set every how many km or months' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'name'), '')) < 2 then
    raise exception 'Name the service (e.g. Engine oil)' using errcode = '22023';
  end if;
  if p_id is null then
    if not exists (select 1 from public.tms_vehicles where id = nullif(p ->> 'vehicle_id', '')::uuid and org_id = v_org) then
      raise exception 'Vehicle not found' using errcode = 'P0002';
    end if;
    insert into public.tms_service_plans (org_id, vehicle_id, name, every_km, every_months, last_km, last_date)
    values (v_org, (p ->> 'vehicle_id')::uuid, btrim(p ->> 'name'), v_km, v_mo,
            coalesce(nullif(p ->> 'last_km', '')::numeric, (select v.odometer_km from public.tms_vehicles v where v.id = (p ->> 'vehicle_id')::uuid)),
            coalesce(nullif(p ->> 'last_date', '')::date, current_date))
    returning id into v_id;
    return v_id;
  end if;
  update public.tms_service_plans
     set name = btrim(p ->> 'name'), every_km = v_km, every_months = v_mo,
         last_km = case when p ? 'last_km' then nullif(p ->> 'last_km', '')::numeric else last_km end,
         last_date = case when p ? 'last_date' then nullif(p ->> 'last_date', '')::date else last_date end,
         active = coalesce((p ->> 'active')::boolean, active)
   where id = p_id and org_id = v_org;
  if not found then
    raise exception 'Service plan not found' using errcode = 'P0002';
  end if;
  return p_id;
end;
$$;

-- p: {vehicle_id, plan_id, kind, workshop, description, odometer_km}
create or replace function public.open_tms_job_card(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v     public.tms_vehicles;
  v_id  uuid;
begin
  perform private.require_permission('tms.manage');
  select * into v from public.tms_vehicles where id = nullif(p ->> 'vehicle_id', '')::uuid and org_id = v_org for update;
  if not found or v.status = 'disposed' then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if coalesce(p ->> 'kind', '') not in ('service', 'repair', 'accident') then
    raise exception 'Choose service, repair or accident' using errcode = '22023';
  end if;
  if char_length(coalesce(btrim(p ->> 'description'), '')) < 3 then
    raise exception 'Describe the work' using errcode = '22023';
  end if;
  if nullif(p ->> 'plan_id', '') is not null
     and not exists (select 1 from public.tms_service_plans sp where sp.id = (p ->> 'plan_id')::uuid and sp.vehicle_id = v.id) then
    raise exception 'That service plan is not for this vehicle' using errcode = '22023';
  end if;
  if exists (select 1 from public.tms_trips t where t.vehicle_id = v.id and t.status = 'in_progress') then
    raise exception 'The vehicle is on a trip; end the trip first' using errcode = '23514';
  end if;
  insert into public.tms_job_cards (org_id, vehicle_id, plan_id, kind, workshop, description, odometer_km)
  values (v_org, v.id, nullif(p ->> 'plan_id', '')::uuid, p ->> 'kind', private.jtext(p, 'workshop'), btrim(p ->> 'description'),
          coalesce(nullif(p ->> 'odometer_km', '')::numeric, v.odometer_km))
  returning id into v_id;
  update public.tms_vehicles set status = 'in_maintenance' where id = v.id and status = 'active';
  return v_id;
end;
$$;

-- p: {labour_cost, outside_parts_cost, odometer_km, close_note, cancel}
create or replace function public.close_tms_job_card(p_id uuid, p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  j      public.tms_job_cards;
  v      public.tms_vehicles;
  v_odo  numeric;
  v_cancel boolean := coalesce((p ->> 'cancel')::boolean, false);
begin
  perform private.require_permission('tms.manage');
  select * into j from public.tms_job_cards where id = p_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Job card not found' using errcode = 'P0002';
  end if;
  if j.status <> 'open' then
    raise exception 'This job card is already closed' using errcode = '23514';
  end if;
  select * into v from public.tms_vehicles where id = j.vehicle_id for update;
  if v_cancel then
    if exists (select 1 from public.tms_stock_moves m where m.job_card_id = j.id) then
      raise exception 'Parts were issued to this job card; close it instead' using errcode = '23514';
    end if;
    update public.tms_job_cards set status = 'cancelled', closed_at = now(), close_note = private.jtext(p, 'close_note') where id = j.id returning * into j;
  else
    v_odo := coalesce(nullif(p ->> 'odometer_km', '')::numeric, j.odometer_km, v.odometer_km);
    if v_odo < v.odometer_km then
      raise exception 'The odometer cannot go back (now % km)', v.odometer_km using errcode = '23514';
    end if;
    update public.tms_job_cards
       set status = 'closed', closed_at = now(), odometer_km = v_odo,
           labour_cost = coalesce(nullif(p ->> 'labour_cost', '')::numeric, labour_cost),
           outside_parts_cost = coalesce(nullif(p ->> 'outside_parts_cost', '')::numeric, outside_parts_cost),
           close_note = private.jtext(p, 'close_note')
     where id = j.id returning * into j;
    update public.tms_vehicles set odometer_km = greatest(odometer_km, v_odo) where id = v.id;
    if j.plan_id is not null then
      update public.tms_service_plans set last_km = v_odo, last_date = current_date where id = j.plan_id;
    end if;
  end if;
  if not exists (select 1 from public.tms_job_cards x where x.vehicle_id = v.id and x.status = 'open') then
    update public.tms_vehicles set status = 'active' where id = v.id and status = 'in_maintenance';
  end if;
  return private.tms_job_json(j);
end;
$$;

create or replace function public.get_tms_maintenance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if not (private.has_permission('tms.manage') or private.has_permission('tms.view_costs')) then
    raise exception 'You do not have permission for this action (tms.manage)' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'plans', coalesce((select jsonb_agg(x order by (x ->> 'status') = 'ok', x ->> 'reg_no')
                       from (select private.tms_plan_json(sp) as x from public.tms_service_plans sp
                             join public.tms_vehicles v on v.id = sp.vehicle_id
                             where sp.org_id = v_org and sp.active and v.status <> 'disposed') s), '[]'::jsonb),
    'open', coalesce((select jsonb_agg(private.tms_job_json(j) order by j.opened_at)
                      from public.tms_job_cards j where j.org_id = v_org and j.status = 'open'), '[]'::jsonb),
    'closed', coalesce((select jsonb_agg(private.tms_job_json(j) order by j.closed_at desc)
                        from (select * from public.tms_job_cards j where j.org_id = v_org and j.status = 'closed'
                              order by j.closed_at desc limit 50) j), '[]'::jsonb));
end;
$$;

-- -----------------------------------------------------------------------------
-- API: inventory
-- -----------------------------------------------------------------------------
-- p: {code, name, category, unit, min_stock, active}
create or replace function public.save_tms_part(p_id uuid, p jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_id  uuid;
begin
  perform private.require_permission('tms.inventory');
  begin
    if p_id is null then
      insert into public.tms_parts (org_id, code, name, category, unit, min_stock)
      values (v_org, btrim(p ->> 'code'), btrim(p ->> 'name'), coalesce(nullif(p ->> 'category', ''), 'part'),
              coalesce(nullif(btrim(p ->> 'unit'), ''), 'pcs'), coalesce(nullif(p ->> 'min_stock', '')::numeric, 0))
      returning id into v_id;
      return v_id;
    end if;
    update public.tms_parts
       set name = coalesce(nullif(btrim(p ->> 'name'), ''), name), category = coalesce(nullif(p ->> 'category', ''), category),
           unit = coalesce(nullif(btrim(p ->> 'unit'), ''), unit), min_stock = coalesce(nullif(p ->> 'min_stock', '')::numeric, min_stock),
           active = coalesce((p ->> 'active')::boolean, active)
     where id = p_id and org_id = v_org;
    if not found then
      raise exception 'Part not found' using errcode = 'P0002';
    end if;
    return p_id;
  exception when unique_violation then
    raise exception 'This part code is already used' using errcode = '23505';
  end;
end;
$$;

-- p: {part_id, kind: receive | issue | adjust, qty, unit_cost (receive), job_card_id | vehicle_id (issue), supplier, ref, note}
create or replace function public.tms_stock_move(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  pt     public.tms_parts;
  v_kind text := p ->> 'kind';
  v_qty  numeric := nullif(p ->> 'qty', '')::numeric;
  v_cost numeric := nullif(p ->> 'unit_cost', '')::numeric;
  v_job  public.tms_job_cards;
  v_veh  uuid := nullif(p ->> 'vehicle_id', '')::uuid;
begin
  if not (private.has_permission('tms.inventory') or (v_kind = 'issue' and private.has_permission('tms.manage'))) then
    raise exception 'You do not have permission for this action (tms.inventory)' using errcode = '42501';
  end if;
  select * into pt from public.tms_parts where id = nullif(p ->> 'part_id', '')::uuid and org_id = v_org for update;
  if not found then
    raise exception 'Part not found' using errcode = 'P0002';
  end if;
  if v_qty is null or v_qty = 0 or (v_kind <> 'adjust' and v_qty < 0) then
    raise exception 'Enter a quantity' using errcode = '22023';
  end if;
  case v_kind
    when 'receive' then
      if v_cost is null or v_cost < 0 then
        raise exception 'Enter the unit cost' using errcode = '22023';
      end if;
      update public.tms_parts
         set avg_cost = round((on_hand * avg_cost + v_qty * v_cost) / (on_hand + v_qty), 2), on_hand = on_hand + v_qty
       where id = pt.id;
    when 'issue' then
      if nullif(p ->> 'job_card_id', '') is not null then
        select * into v_job from public.tms_job_cards where id = (p ->> 'job_card_id')::uuid and org_id = v_org;
        if not found or v_job.status <> 'open' then
          raise exception 'Issue parts to an open job card' using errcode = '23514';
        end if;
        v_veh := v_job.vehicle_id;
      elsif v_veh is null or not exists (select 1 from public.tms_vehicles where id = v_veh and org_id = v_org) then
        raise exception 'Issue to a job card or a vehicle' using errcode = '22023';
      end if;
      if v_qty > pt.on_hand then
        raise exception 'Only % % in stock', pt.on_hand, pt.unit using errcode = '23514';
      end if;
      v_cost := pt.avg_cost;
      update public.tms_parts set on_hand = on_hand - v_qty where id = pt.id;
    when 'adjust' then
      if char_length(coalesce(btrim(p ->> 'note'), '')) < 3 then
        raise exception 'Write why the stock is adjusted' using errcode = '22023';
      end if;
      if pt.on_hand + v_qty < 0 then
        raise exception 'Stock cannot go below zero (now % %)', pt.on_hand, pt.unit using errcode = '23514';
      end if;
      v_cost := pt.avg_cost;
      update public.tms_parts set on_hand = on_hand + v_qty where id = pt.id;
    else
      raise exception 'Unknown stock move' using errcode = '22023';
  end case;
  insert into public.tms_stock_moves (org_id, part_id, kind, qty, unit_cost, vehicle_id, job_card_id, supplier, ref, note)
  values (v_org, pt.id, v_kind, v_qty, coalesce(v_cost, 0), v_veh, v_job.id, private.jtext(p, 'supplier'), private.jtext(p, 'ref'), private.jtext(p, 'note'));
  select * into pt from public.tms_parts where id = pt.id;
  return jsonb_build_object('on_hand', pt.on_hand, 'avg_cost', pt.avg_cost);
end;
$$;

create or replace function public.get_tms_inventory()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if not (private.has_permission('tms.inventory') or private.has_permission('tms.manage')) then
    raise exception 'You do not have permission for this action (tms.inventory)' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'parts', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'category', p.category, 'unit', p.unit,
                                                           'on_hand', p.on_hand, 'avg_cost', p.avg_cost, 'min_stock', p.min_stock, 'active', p.active,
                                                           'value', round(p.on_hand * p.avg_cost, 2), 'low', p.on_hand <= p.min_stock and p.min_stock > 0)
                                        order by p.active desc, p.category, p.name)
                       from public.tms_parts p where p.org_id = v_org), '[]'::jsonb),
    'moves', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'part', p.name, 'code', p.code, 'kind', m.kind, 'qty', m.qty, 'unit', p.unit,
                                                           'unit_cost', m.unit_cost, 'reg_no', (select v.reg_no from public.tms_vehicles v where v.id = m.vehicle_id),
                                                           'job_card_id', m.job_card_id, 'supplier', m.supplier, 'ref', m.ref, 'note', m.note,
                                                           'moved_at', m.moved_at, 'by', private.dms_user_name(m.created_by))
                                        order by m.moved_at desc)
                       from (select * from public.tms_stock_moves x where x.org_id = v_org order by x.moved_at desc limit 100) m
                       join public.tms_parts p on p.id = m.part_id), '[]'::jsonb),
    'can_manage_stock', private.has_permission('tms.inventory'));
end;
$$;

alter table public.tms_service_plans enable row level security;
alter table public.tms_job_cards     enable row level security;
alter table public.tms_parts         enable row level security;
alter table public.tms_stock_moves   enable row level security;
revoke all on table public.tms_service_plans, public.tms_job_cards, public.tms_parts, public.tms_stock_moves from anon, authenticated;
revoke all on function public.save_tms_service_plan(uuid, jsonb), public.open_tms_job_card(jsonb), public.close_tms_job_card(uuid, jsonb),
  public.get_tms_maintenance(), public.save_tms_part(uuid, jsonb), public.tms_stock_move(jsonb), public.get_tms_inventory() from public, anon;
grant execute on function public.save_tms_service_plan(uuid, jsonb), public.open_tms_job_card(jsonb), public.close_tms_job_card(uuid, jsonb),
  public.get_tms_maintenance(), public.save_tms_part(uuid, jsonb), public.tms_stock_move(jsonb), public.get_tms_inventory() to authenticated;
revoke all on function private.tms_plan_json(public.tms_service_plans), private.tms_job_json(public.tms_job_cards), private.tms_stock_moves_frozen()
from public, anon, authenticated;
