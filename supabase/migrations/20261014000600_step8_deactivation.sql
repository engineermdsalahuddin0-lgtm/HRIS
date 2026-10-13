-- =============================================================================
-- Olympus HRIS — Part 1, Step 8: Deactivation flows
--   Branch  -> employees move to a target branch + office (chosen by Admin/HR);
--              the branch's offices are deactivated with it.
--   Office  -> employees move to a target office (any active branch).
--   Department / designation -> blocked while active employees remain.
-- Every move writes a history row; every change is audited.
-- =============================================================================

-- Direct "set inactive" on these tables is blocked; the functions below set a
-- transaction-local flag after doing the checks and transfers.
create or replace function private.structure_status_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'active' and new.status <> 'active'
     and coalesce(current_setting('olympus.structure_flow', true), '') <> 'on' then
    raise exception 'Use the Deactivate action for this %', rtrim(tg_table_name, 's') using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger structure_status_guard before update of status on public.departments
  for each row execute function private.structure_status_guard();
create trigger structure_status_guard before update of status on public.designations
  for each row execute function private.structure_status_guard();
create trigger structure_status_guard before update of status on public.branches
  for each row execute function private.structure_status_guard();
create trigger structure_status_guard before update of status on public.offices
  for each row execute function private.structure_status_guard();

-- Grades and operations can be switched off directly, but not while in use.
create or replace function private.grades_status_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'active' and new.status <> 'active'
     and exists (select 1 from public.designations where grade_id = old.id and status = 'active') then
    raise exception 'Active designations use this grade; change or deactivate them first' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger grades_status_guard before update of status on public.grades
  for each row execute function private.grades_status_guard();

create or replace function private.operations_status_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_count int;
begin
  if old.status = 'active' and new.status <> 'active' then
    select count(*) into v_count from public.employees where operation_id = old.id and status = 'active';
    if v_count > 0 then
      raise exception '% active employee(s) work in this operation; transfer them first', v_count using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger operations_status_guard before update of status on public.operations
  for each row execute function private.operations_status_guard();

-- -----------------------------------------------------------------------------
-- Helpers
-- -----------------------------------------------------------------------------
create or replace function private.begin_structure_flow()
returns void
language sql
set search_path = ''
as $$
  select set_config('olympus.structure_flow', 'on', true)
$$;

-- Switched off again right after the status change, so the flag never leaks to
-- later statements in the same transaction.
create or replace function private.end_structure_flow()
returns void
language sql
set search_path = ''
as $$
  select set_config('olympus.structure_flow', 'off', true)
$$;

-- Moves one active employee to a new branch/office; writes history.
create or replace function private.move_employee(
  p_employee_id uuid, p_branch_id uuid, p_office_id uuid, p_event text, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp  public.employees;
  v_from jsonb;
begin
  select * into v_emp from public.employees where id = p_employee_id for update;
  v_from := private.placement_snapshot(p_employee_id);
  update public.employees
     set branch_id = p_branch_id,
         office_id = p_office_id,
         operation_id = case
           when operation_id is not null and exists (
             select 1 from public.office_operations where office_id = p_office_id and operation_id = v_emp.operation_id)
           then operation_id end
   where id = p_employee_id;
  insert into public.employment_history (org_id, employee_id, event_type, from_value, to_value, effective_date, reason)
  values (v_emp.org_id, p_employee_id, p_event, v_from, private.placement_snapshot(p_employee_id), current_date, p_reason);
end;
$$;

-- -----------------------------------------------------------------------------
-- Public RPCs
-- -----------------------------------------------------------------------------
-- How many people/units a deactivation would affect (for the confirm dialog).
create or replace function public.get_deactivation_impact(p_kind text, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('org.manage');
  return case p_kind
    when 'branch' then jsonb_build_object(
      'employees', (select count(*) from public.employees where org_id = v_org and branch_id = p_id and status = 'active'),
      'offices',   (select count(*) from public.offices where org_id = v_org and branch_id = p_id and status = 'active'))
    when 'office' then jsonb_build_object(
      'employees', (select count(*) from public.employees where org_id = v_org and office_id = p_id and status = 'active'))
    when 'department' then jsonb_build_object(
      'employees',    (select count(*) from public.employees where org_id = v_org and department_id = p_id and status = 'active'),
      'designations', (select count(*) from public.designations where org_id = v_org and department_id = p_id and status = 'active'))
    when 'designation' then jsonb_build_object(
      'employees', (select count(*) from public.employees where org_id = v_org and designation_id = p_id and status = 'active'))
    else null
  end;
end;
$$;

create or replace function public.deactivate_branch(
  p_branch_id        uuid,
  p_target_branch_id uuid,
  p_target_office_id uuid,
  p_reason           text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_branch public.branches;
  v_target public.branches;
  v_emp    record;
  v_moved  int := 0;
begin
  perform private.require_permission('org.manage');
  select * into v_branch from public.branches where id = p_branch_id and org_id = v_org for update;
  if not found or v_branch.status <> 'active' then
    raise exception 'Active branch not found' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.employees where branch_id = p_branch_id and status = 'active') then
    if p_target_branch_id is null or p_target_office_id is null then
      raise exception 'Choose a target branch and office for the employees' using errcode = '23502';
    end if;
    if p_target_branch_id = p_branch_id then
      raise exception 'The target branch must be a different branch' using errcode = '22023';
    end if;
    select * into v_target from public.branches where id = p_target_branch_id and org_id = v_org;
    if not found or v_target.status <> 'active' then
      raise exception 'The target branch must be active' using errcode = '23514';
    end if;
    if not exists (select 1 from public.offices
                   where id = p_target_office_id and branch_id = p_target_branch_id and status = 'active') then
      raise exception 'The target office must be an active office of the target branch' using errcode = '23514';
    end if;

    for v_emp in select id from public.employees where branch_id = p_branch_id and status = 'active' loop
      perform private.move_employee(v_emp.id, p_target_branch_id, p_target_office_id, 'branch',
        coalesce(nullif(btrim(p_reason), ''), 'Branch deactivated') || ' (' || v_branch.name || ' -> ' || v_target.name || ')');
      v_moved := v_moved + 1;
    end loop;
  end if;

  perform private.begin_structure_flow();
  update public.offices set status = 'inactive' where branch_id = p_branch_id and status = 'active';
  update public.branches set status = 'inactive' where id = p_branch_id;
  perform private.end_structure_flow();

  perform private.write_audit(v_org, 'branch.deactivated', 'branches', p_branch_id, null,
    jsonb_build_object('target_branch_id', p_target_branch_id, 'target_office_id', p_target_office_id,
                       'employees_moved', v_moved, 'reason', nullif(btrim(p_reason), '')));
  return v_moved;
end;
$$;

create or replace function public.deactivate_office(
  p_office_id        uuid,
  p_target_office_id uuid,
  p_reason           text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org    uuid := private.current_org_id();
  v_office public.offices;
  v_target public.offices;
  v_emp    record;
  v_moved  int := 0;
begin
  perform private.require_permission('org.manage');
  select * into v_office from public.offices where id = p_office_id and org_id = v_org for update;
  if not found or v_office.status <> 'active' then
    raise exception 'Active office not found' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.employees where office_id = p_office_id and status = 'active') then
    if p_target_office_id is null then
      raise exception 'Choose a target office for the employees' using errcode = '23502';
    end if;
    if p_target_office_id = p_office_id then
      raise exception 'The target office must be a different office' using errcode = '22023';
    end if;
    select * into v_target from public.offices where id = p_target_office_id and org_id = v_org;
    if not found or v_target.status <> 'active' then
      raise exception 'The target office must be active' using errcode = '23514';
    end if;

    for v_emp in select id from public.employees where office_id = p_office_id and status = 'active' loop
      perform private.move_employee(v_emp.id, v_target.branch_id, v_target.id,
        case when v_target.branch_id = v_office.branch_id then 'office' else 'branch' end,
        coalesce(nullif(btrim(p_reason), ''), 'Office deactivated') || ' (' || v_office.name || ' -> ' || v_target.name || ')');
      v_moved := v_moved + 1;
    end loop;
  end if;

  perform private.begin_structure_flow();
  update public.offices set status = 'inactive' where id = p_office_id;
  perform private.end_structure_flow();

  perform private.write_audit(v_org, 'office.deactivated', 'offices', p_office_id, null,
    jsonb_build_object('target_office_id', p_target_office_id, 'employees_moved', v_moved,
                       'reason', nullif(btrim(p_reason), '')));
  return v_moved;
end;
$$;

create or replace function public.deactivate_department(p_department_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_count int;
begin
  perform private.require_permission('org.manage');
  if not exists (select 1 from public.departments where id = p_department_id and org_id = v_org and status = 'active') then
    raise exception 'Active department not found' using errcode = 'P0002';
  end if;
  select count(*) into v_count from public.employees where department_id = p_department_id and status = 'active';
  if v_count > 0 then
    raise exception '% active employee(s) are in this department; transfer them first', v_count using errcode = '23514';
  end if;
  perform private.begin_structure_flow();
  update public.designations set status = 'inactive' where department_id = p_department_id and status = 'active';
  update public.departments set status = 'inactive' where id = p_department_id;
  perform private.end_structure_flow();
  perform private.write_audit(v_org, 'department.deactivated', 'departments', p_department_id, null,
                              jsonb_build_object('reason', nullif(btrim(p_reason), '')));
end;
$$;

create or replace function public.deactivate_designation(p_designation_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_count int;
begin
  perform private.require_permission('org.manage');
  if not exists (select 1 from public.designations where id = p_designation_id and org_id = v_org and status = 'active') then
    raise exception 'Active designation not found' using errcode = 'P0002';
  end if;
  select count(*) into v_count from public.employees where designation_id = p_designation_id and status = 'active';
  if v_count > 0 then
    raise exception '% active employee(s) hold this designation; transfer or promote them first', v_count
      using errcode = '23514';
  end if;
  perform private.begin_structure_flow();
  update public.designations set status = 'inactive' where id = p_designation_id;
  perform private.end_structure_flow();
  perform private.write_audit(v_org, 'designation.deactivated', 'designations', p_designation_id, null,
                              jsonb_build_object('reason', nullif(btrim(p_reason), '')));
end;
$$;

revoke all on function
  public.get_deactivation_impact(text, uuid),
  public.deactivate_branch(uuid, uuid, uuid, text),
  public.deactivate_office(uuid, uuid, text),
  public.deactivate_department(uuid, text),
  public.deactivate_designation(uuid, text)
from public, anon;
grant execute on function
  public.get_deactivation_impact(text, uuid),
  public.deactivate_branch(uuid, uuid, uuid, text),
  public.deactivate_office(uuid, uuid, text),
  public.deactivate_department(uuid, text),
  public.deactivate_designation(uuid, text)
to authenticated;

revoke all on function private.begin_structure_flow(), private.end_structure_flow(), private.move_employee(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
