-- =============================================================================
-- Olympus HRIS — Part 1, Step 6: History, reporting chain and nominees
-- =============================================================================

-- Transfer (department / branch / office / operation) and promotion
-- (designation -> grade). Writes one history row with before/after.
-- p: { department_id, designation_id, branch_id, office_id, operation_id, effective_date, reason }
create or replace function public.transfer_employee(p_employee_id uuid, p jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old     public.employees;
  v_from    jsonb;
  v_to      jsonb;
  v_event   text;
  v_eff     date := coalesce(private.jtext(p, 'effective_date')::date, current_date);
  v_dept    uuid;
  v_desig   uuid;
  v_branch  uuid;
  v_office  uuid;
  v_op      uuid;
begin
  perform private.require_permission('employees.transfer');
  select * into v_old from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if v_old.status <> 'active' then
    raise exception 'Only active employees can be transferred' using errcode = '23514';
  end if;
  if v_eff < v_old.join_date then
    raise exception 'Effective date cannot be before the join date' using errcode = '22023';
  end if;

  v_dept   := case when p ? 'department_id'  then private.jtext(p, 'department_id')::uuid  else v_old.department_id end;
  v_desig  := case when p ? 'designation_id' then private.jtext(p, 'designation_id')::uuid else v_old.designation_id end;
  v_branch := case when p ? 'branch_id'      then private.jtext(p, 'branch_id')::uuid      else v_old.branch_id end;
  v_office := case when p ? 'office_id'      then private.jtext(p, 'office_id')::uuid      else v_old.office_id end;
  v_op     := case when p ? 'operation_id'   then private.jtext(p, 'operation_id')::uuid   else v_old.operation_id end;

  if v_dept is null or v_desig is null or v_branch is null or v_office is null then
    raise exception 'Department, designation, branch and office are required' using errcode = '23502';
  end if;
  if v_dept is not distinct from v_old.department_id and v_desig is not distinct from v_old.designation_id
     and v_branch is not distinct from v_old.branch_id and v_office is not distinct from v_old.office_id
     and v_op is not distinct from v_old.operation_id then
    raise exception 'Nothing changed' using errcode = '22023';
  end if;

  v_from := private.placement_snapshot(p_employee_id);
  update public.employees
     set department_id = v_dept, designation_id = v_desig, branch_id = v_branch,
         office_id = v_office, operation_id = v_op
   where id = p_employee_id;
  v_to := private.placement_snapshot(p_employee_id);

  v_event := case
    when (v_to ->> 'grade_level')::int > (v_from ->> 'grade_level')::int then 'promotion'
    when (v_to ->> 'grade_level')::int < (v_from ->> 'grade_level')::int then 'demotion'
    when v_dept is distinct from v_old.department_id
      or v_branch is distinct from v_old.branch_id
      or v_office is distinct from v_old.office_id then 'transfer'
    when v_desig is distinct from v_old.designation_id then 'designation'
    else 'operation'
  end;

  insert into public.employment_history (org_id, employee_id, event_type, from_value, to_value, effective_date, reason)
  values (v_old.org_id, p_employee_id, v_event, v_from, v_to, v_eff, private.jtext(p, 'reason'));

  perform private.write_audit(v_old.org_id, 'employee.' || v_event, 'employees', p_employee_id, v_from, v_to);
  return v_event;
end;
$$;

-- Change (or clear, with p_manager_id = null) one reporting line.
create or replace function public.set_reporting_line(
  p_employee_id    uuid,
  p_line_type      text,
  p_manager_id     uuid,
  p_effective_date date default null,
  p_reason         text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_emp public.employees;
begin
  perform private.require_permission('employees.reporting');
  select * into v_emp from public.employees
   where id = p_employee_id and org_id = private.current_org_id() for update;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_line_type not in ('reporting_manager', 'supervisor', 'it_manager', 'finance_manager') then
    raise exception 'Unknown line type %', p_line_type using errcode = '22023';
  end if;
  if p_manager_id = p_employee_id then
    raise exception 'An employee cannot report to themselves' using errcode = '23514';
  end if;
  if exists (select 1 from public.reporting_lines
             where employee_id = p_employee_id and line_type = p_line_type and end_date is null
               and manager_employee_id is not distinct from p_manager_id) then
    raise exception 'This is already the current %', replace(p_line_type, '_', ' ') using errcode = '22023';
  end if;
  perform private.set_reporting_line_internal(
    p_employee_id, p_line_type, p_manager_id,
    coalesce(p_effective_date, current_date), nullif(btrim(p_reason), ''));
end;
$$;

-- Everything the profile screen needs, masked by the caller's rights.
create or replace function public.get_employee_profile(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_emp      jsonb;
  v_viewer   record;
  v_self     boolean;
  v_portal   jsonb;
  v_can_hist boolean;
begin
  select to_jsonb(ev) into v_emp from public.employees_v ev where ev.id = p_employee_id;
  if v_emp is null then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  select * into v_viewer from private.viewer();
  v_self := (v_emp ->> 'is_self')::boolean;
  v_can_hist := v_self or v_viewer.can_list;

  if private.has_permission('employees.portal_access') or private.has_permission('users.reset_password') then
    select jsonb_build_object(
      'user_id', u.id, 'email', u.email, 'phone', u.phone, 'user_status', u.status,
      'last_login_at', u.last_login_at, 'must_change_password', u.must_change_password,
      'membership_status', m.status, 'role_id', m.role_id, 'role_name', r.name, 'role_key', r.system_key)
    into v_portal
    from public.employees e
    join public.user_profiles u on u.id = e.user_id
    left join public.org_members m on m.employee_id = e.id and m.user_id = u.id
      and m.created_at = (select max(created_at) from public.org_members where employee_id = e.id)
    left join public.roles r on r.id = m.role_id
    where e.id = p_employee_id;
  end if;

  return jsonb_build_object(
    'employee', v_emp,
    'editable_fields', to_jsonb(private.editable_fields(p_employee_id)),
    'nominees', case when v_viewer.see_all or v_self or 'employees.nominees' = any (v_viewer.fields) then
      coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'name', n.name, 'phone', n.phone, 'relation', n.relation)
                                 order by n.created_at)
                from public.employee_nominees n
                where n.employee_id = p_employee_id and n.status = 'active'), '[]'::jsonb) end,
    'history', case when v_can_hist then
      coalesce((select jsonb_agg(jsonb_build_object(
                  'id', h.id, 'event_type', h.event_type, 'from', h.from_value, 'to', h.to_value,
                  'effective_date', h.effective_date, 'reason', h.reason, 'created_at', h.created_at,
                  'created_by_name', u.full_name)
                  order by h.effective_date desc, h.created_at desc)
                from public.employment_history h
                left join public.user_profiles u on u.id = h.created_by
                where h.employee_id = p_employee_id), '[]'::jsonb) end,
    'reporting', case when v_can_hist then
      coalesce((select jsonb_agg(jsonb_build_object(
                  'id', rl.id, 'line_type', rl.line_type, 'start_date', rl.start_date, 'end_date', rl.end_date,
                  'reason', rl.reason, 'manager_id', me.id, 'manager_name', me.full_name,
                  'manager_card_id', me.card_id, 'manager_status', me.status)
                  order by rl.end_date desc nulls first, rl.start_date desc)
                from public.reporting_lines rl
                join public.employees me on me.id = rl.manager_employee_id
                where rl.employee_id = p_employee_id), '[]'::jsonb) end,
    'direct_reports', case when v_can_hist then
      coalesce((select jsonb_agg(jsonb_build_object(
                  'id', se.id, 'full_name', se.full_name, 'card_id', se.card_id, 'line_type', rl.line_type)
                  order by se.full_name)
                from public.reporting_lines rl
                join public.employees se on se.id = rl.employee_id
                where rl.manager_employee_id = p_employee_id and rl.end_date is null and se.status = 'active'),
               '[]'::jsonb) end,
    'portal', v_portal);
end;
$$;

revoke all on function
  public.transfer_employee(uuid, jsonb),
  public.set_reporting_line(uuid, text, uuid, date, text),
  public.get_employee_profile(uuid)
from public, anon;
grant execute on function
  public.transfer_employee(uuid, jsonb),
  public.set_reporting_line(uuid, text, uuid, date, text),
  public.get_employee_profile(uuid)
to authenticated;
