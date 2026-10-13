-- =============================================================================
-- Olympus HRIS — Part 1, Step 9: Audit log viewer and dashboard data
-- =============================================================================

-- Read-only audit list with filters. Admin-only (audit.view is admin-only).
create or replace function public.list_audit_logs(
  p_actor  uuid default null,
  p_action text default null,
  p_entity text default null,
  p_from   date default null,
  p_to     date default null,
  p_limit  int  default 50,
  p_offset int  default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('audit.view');
  return (
    with filtered as (
      select a.*
      from public.audit_logs a
      where a.org_id = v_org
        and (p_actor  is null or a.actor_user_id = p_actor)
        and (p_action is null or a.action = p_action)
        and (p_entity is null or a.entity = p_entity)
        and (p_from   is null or a.created_at >= p_from::timestamptz)
        and (p_to     is null or a.created_at < (p_to + 1)::timestamptz)
    )
    select jsonb_build_object(
      'total', (select count(*) from filtered),
      'rows', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', f.id, 'created_at', f.created_at, 'action', f.action, 'entity', f.entity,
          'entity_id', f.entity_id, 'old_value', f.old_value, 'new_value', f.new_value,
          'ip', f.ip, 'user_agent', f.user_agent,
          'actor_user_id', f.actor_user_id,
          'actor_name', coalesce(nullif(u.full_name, ''), u.email, u.phone))
          order by f.created_at desc)
        from (select * from filtered order by created_at desc
              limit least(greatest(p_limit, 1), 200) offset greatest(p_offset, 0)) f
        left join public.user_profiles u on u.id = f.actor_user_id
      ), '[]'::jsonb))
  );
end;
$$;

-- Values for the filter dropdowns.
create or replace function public.get_audit_filter_options()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  perform private.require_permission('audit.view');
  return jsonb_build_object(
    'actors', coalesce((
      select jsonb_agg(jsonb_build_object('id', x.actor_user_id,
                                          'name', coalesce(nullif(u.full_name, ''), u.email, u.phone, 'System'))
                       order by u.full_name)
      from (select distinct actor_user_id from public.audit_logs where org_id = v_org and actor_user_id is not null) x
      left join public.user_profiles u on u.id = x.actor_user_id), '[]'::jsonb),
    'actions', coalesce((select jsonb_agg(distinct action) from public.audit_logs where org_id = v_org), '[]'::jsonb),
    'entities', coalesce((select jsonb_agg(distinct entity) from public.audit_logs where org_id = v_org), '[]'::jsonb));
end;
$$;

-- Dashboard figures. Without employees.view only the organization basics return.
create or replace function public.get_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
begin
  if v_org is null or not private.has_permission('employees.view') then
    return null;
  end if;

  return jsonb_build_object(
    'kpis', jsonb_build_object(
      'total',          (select count(*) from public.employees where org_id = v_org),
      'active',         (select count(*) from public.employees where org_id = v_org and status = 'active'),
      'new_this_month', (select count(*) from public.employees
                         where org_id = v_org and join_date >= date_trunc('month', current_date)::date),
      'portal_access',  (select count(*) from public.org_members
                         where org_id = v_org and status = 'active' and employee_id is not null),
      'departments',    (select count(*) from public.departments where org_id = v_org and status = 'active'),
      'branches',       (select count(*) from public.branches where org_id = v_org and status = 'active')),

    'headcount_trend', (
      select jsonb_agg(jsonb_build_object('month', to_char(m, 'Mon'), 'headcount', (
        select count(*) from public.employees e
        where e.org_id = v_org
          and e.join_date <= least((m + interval '1 month - 1 day')::date, current_date)
          and (e.exit_date is null or e.exit_date > least((m + interval '1 month - 1 day')::date, current_date))
      )) order by m)
      from generate_series(date_trunc('month', current_date) - interval '11 months',
                           date_trunc('month', current_date), interval '1 month') m),

    'employment_types', coalesce((
      select jsonb_agg(jsonb_build_object('type', initcap(replace(employment_type, '_', ' ')), 'count', n) order by n desc)
      from (select employment_type, count(*) n from public.employees
            where org_id = v_org and status = 'active' group by employment_type) t), '[]'::jsonb),

    'by_department', coalesce((
      select jsonb_agg(jsonb_build_object('department', name, 'count', n) order by n desc, name)
      from (select coalesce(d.name, 'Unassigned') as name, count(*) n
            from public.employees e left join public.departments d on d.id = e.department_id
            where e.org_id = v_org and e.status = 'active'
            group by coalesce(d.name, 'Unassigned')
            order by n desc limit 10) t), '[]'::jsonb),

    'joiners_leavers', (
      select jsonb_agg(jsonb_build_object(
        'month', to_char(m, 'Mon'),
        'joiners', (select count(*) from public.employees
                    where org_id = v_org and join_date >= m::date and join_date < (m + interval '1 month')::date),
        'leavers', (select count(*) from public.employees
                    where org_id = v_org and exit_date >= m::date and exit_date < (m + interval '1 month')::date))
        order by m)
      from generate_series(date_trunc('month', current_date) - interval '5 months',
                           date_trunc('month', current_date), interval '1 month') m),

    'recent_activity', coalesce((
      select jsonb_agg(x order by x ->> 'created_at' desc)
      from (select jsonb_build_object('employee_id', e.id, 'who', e.full_name, 'event_type', h.event_type,
                                      'to', h.to_value, 'effective_date', h.effective_date,
                                      'created_at', h.created_at) as x
            from public.employment_history h
            join public.employees e on e.id = h.employee_id
            where h.org_id = v_org
            order by h.created_at desc limit 8) r), '[]'::jsonb));
end;
$$;

revoke all on function
  public.list_audit_logs(uuid, text, text, date, date, int, int),
  public.get_audit_filter_options(),
  public.get_dashboard_stats()
from public, anon;
grant execute on function
  public.list_audit_logs(uuid, text, text, date, date, int, int),
  public.get_audit_filter_options(),
  public.get_dashboard_stats()
to authenticated;
