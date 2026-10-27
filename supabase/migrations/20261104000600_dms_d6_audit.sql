-- =============================================================================
-- DMS D6: document audit log, downloads, export, quarterly access review.
-- Module handbook: src/DMS/features.md (Audit and access review).
--
--   * list_dms_audit: changes (row audit + named events such as approvals, holds,
--     disposals) and downloads of the DMS, newest first, filterable. For dms.manage
--     and dms.audit. The browser exports what it shows as CSV.
--   * Access review (ISO 27001 evidence): who holds which DMS right, by role and
--     person; a dms.manage holder signs it off with a note; sign-offs are kept.
--     Due again 90 days after the last one.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.get_dms_document_ai') is null then
    raise exception 'Apply 20261104000500_dms_d5_ai.sql first, then run this file again';
  end if;
end;
$guard$;

create table public.dms_access_reviews (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references public.organizations (id),
  reviewed_by uuid not null references public.user_profiles (id),
  reviewed_at timestamptz not null default now(),
  note        text check (note is null or char_length(note) <= 1000),
  holders     jsonb not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references public.user_profiles (id),
  updated_by  uuid references public.user_profiles (id)
);
create index dms_access_reviews_org_idx on public.dms_access_reviews (org_id, reviewed_at desc);
select private.attach_standard_triggers('public.dms_access_reviews');

-- Who holds which DMS right now (Admins hold all), plus the custodians.
create or replace function private.dms_rights_snapshot(p_org_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
               'role', r.name, 'system_key', r.system_key,
               'rights', case when r.system_key = 'admin' then (select jsonb_agg(p.key order by p.key) from public.permissions p where p.module = 'dms')
                              else coalesce((select jsonb_agg(rp.permission_key order by rp.permission_key) from public.role_permissions rp
                                             where rp.role_id = r.id and rp.permission_key like 'dms.%'), '[]'::jsonb) end,
               'people', coalesce((select jsonb_agg(coalesce(e.full_name, up.full_name) order by coalesce(e.full_name, up.full_name))
                                   from public.org_members m left join public.employees e on e.id = m.employee_id
                                   left join public.user_profiles up on up.id = m.user_id
                                   where m.role_id = r.id and m.status = 'active'), '[]'::jsonb))
             order by r.system_key = 'admin' desc, r.name)
      from public.roles r
      where r.org_id = p_org_id and r.status = 'active'
        and (r.system_key = 'admin' or exists (select 1 from public.role_permissions rp where rp.role_id = r.id and rp.permission_key like 'dms.%'))), '[]'::jsonb),
    'custodians', coalesce((
      select jsonb_agg(jsonb_build_object('folder', f.name, 'person', private.dms_user_name(c.user_id)) order by f.name)
      from public.dms_custodians c join public.dms_folders f on f.id = c.folder_id
      where c.org_id = p_org_id and c.active), '[]'::jsonb))
$$;

create or replace function public.get_dms_access_review()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org  uuid := private.current_org_id();
  v_last timestamptz;
begin
  if not private.dms_can_audit() then
    raise exception 'You do not have permission for this action (dms.audit)' using errcode = '42501';
  end if;
  v_last := (select max(x.reviewed_at) from public.dms_access_reviews x where x.org_id = v_org);
  return jsonb_build_object(
    'current', private.dms_rights_snapshot(v_org),
    'last_reviewed_at', v_last,
    'due', v_last is null or v_last < now() - interval '90 days',
    'can_sign', private.has_permission('dms.manage'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'reviewed_at', x.reviewed_at, 'reviewed_by', private.dms_user_name(x.reviewed_by),
                                                            'note', x.note, 'holders', x.holders) order by x.reviewed_at desc)
                         from (select * from public.dms_access_reviews y where y.org_id = v_org order by y.reviewed_at desc limit 12) x), '[]'::jsonb));
end;
$$;

create or replace function public.sign_dms_access_review(p_note text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org uuid := private.current_org_id();
  v_id  uuid;
begin
  perform private.require_permission('dms.manage');
  insert into public.dms_access_reviews (org_id, reviewed_by, note, holders)
  values (v_org, auth.uid(), left(nullif(btrim(coalesce(p_note, '')), ''), 1000), private.dms_rights_snapshot(v_org))
  returning id into v_id;
  perform private.write_audit(v_org, 'dms.access_reviewed', 'dms_access_reviews', v_id, null, jsonb_build_object('note', p_note));
  return v_id;
end;
$$;

-- p: {from, to, document_id, kind: all | changes | downloads, q (code or title), limit}
create or replace function public.list_dms_audit(p jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org   uuid := private.current_org_id();
  v_from  timestamptz := coalesce(nullif(p ->> 'from', '')::date, current_date - 30)::timestamptz;
  v_to    timestamptz := (coalesce(nullif(p ->> 'to', '')::date, current_date) + 1)::timestamptz;
  v_kind  text := coalesce(nullif(p ->> 'kind', ''), 'all');
  v_doc   uuid := nullif(p ->> 'document_id', '')::uuid;
  v_q     text := nullif(btrim(coalesce(p ->> 'q', '')), '');
  v_limit integer := least(greatest(coalesce((p ->> 'limit')::integer, 300), 1), 1000);
begin
  if not private.dms_can_audit() then
    raise exception 'You do not have permission for this action (dms.audit)' using errcode = '42501';
  end if;
  if v_kind not in ('all', 'changes', 'downloads') then
    raise exception 'Unknown kind' using errcode = '22023';
  end if;
  return coalesce((
    select jsonb_agg(x.j order by x.at desc)
    from (
      select e.at, jsonb_build_object('at', e.at, 'kind', e.kind, 'action', e.action, 'entity', e.entity, 'document_id', e.document_id,
                                      'doc_code', d.doc_code, 'title', d.title, 'by', private.dms_user_name(e.actor), 'detail', e.detail) as j
      from (
        select a.created_at as at, 'change' as kind, a.action, a.entity, a.actor_user_id as actor,
               case when a.entity in ('dms_documents') then a.entity_id
                    when a.entity = 'dms_versions' then coalesce((a.new_value ->> 'document_id')::uuid, (a.old_value ->> 'document_id')::uuid)
                    else coalesce((a.new_value ->> 'document_id')::uuid, (a.old_value ->> 'document_id')::uuid) end as document_id,
               case when a.action like 'dms.%' then a.new_value
                    when a.action = 'update' then (select jsonb_object_agg(k.key, k.value) from jsonb_each(a.new_value) k
                                                   where k.key not in ('updated_at', 'updated_by') and a.old_value -> k.key is distinct from k.value)
                    else null end as detail
        from public.audit_logs a
        where v_kind in ('all', 'changes') and a.org_id = v_org and a.created_at >= v_from and a.created_at < v_to
          and (a.entity like 'dms\_%' or a.action like 'dms.%')
        union all
        select l.at, 'download', 'dms.download', 'dms_versions', l.user_id, l.document_id,
               jsonb_build_object('version', (select v.version from public.dms_versions v where v.id = l.version_id))
        from public.dms_access_log l
        where v_kind in ('all', 'downloads') and l.org_id = v_org and l.at >= v_from and l.at < v_to
      ) e
      left join public.dms_documents d on d.id = e.document_id
      where (v_doc is null or e.document_id = v_doc)
        and (v_q is null or d.doc_code ilike '%' || v_q || '%' or d.title ilike '%' || v_q || '%')
      order by e.at desc
      limit v_limit
    ) x), '[]'::jsonb);
end;
$$;

alter table public.dms_access_reviews enable row level security;
revoke all on table public.dms_access_reviews from anon, authenticated;
revoke all on function public.get_dms_access_review(), public.sign_dms_access_review(text), public.list_dms_audit(jsonb) from public, anon;
grant execute on function public.get_dms_access_review(), public.sign_dms_access_review(text), public.list_dms_audit(jsonb) to authenticated;
revoke all on function private.dms_rights_snapshot(uuid) from public, anon, authenticated;
