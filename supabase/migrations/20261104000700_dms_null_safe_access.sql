-- =============================================================================
-- DMS fix: access rules never return NULL.
--
-- The rules compare a document's department with the caller's department. For a
-- login without an employee department that comparison is NULL, and `if not rule`
-- treats NULL as "not false", so the check let the caller through:
--   * dms_can_read: a person without a department could open a document meant for
--     some departments only (through get_dms_document);
--   * dms_can_edit / dms_can_use_department: an uploader without a department could
--     change or upload documents of any department;
--   * dms_can_review: a reviewer without a department could review any document.
-- Each rule is now wrapped in coalesce(…, false). Same logic otherwise.
-- =============================================================================

do $guard$
begin
  if to_regproc('public.list_dms_audit') is null then
    raise exception 'Apply 20261104000600_dms_d6_audit.sql first, then run this file again';
  end if;
end;
$guard$;

create or replace function private.dms_can_use_department(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.has_permission('dms.manage') or private.has_permission('dms.upload_all')
      or (private.has_permission('dms.upload') and p_department_id = private.dms_my_department()), false)
$$;

create or replace function private.dms_can_review(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(d.org_id = private.current_org_id()
     and (private.is_org_admin()
          or (private.has_permission('dms.approve')
              and (private.has_permission('dms.upload_all') or private.has_permission('dms.manage')
                   or d.department_id = private.dms_my_department()))), false)
$$;

create or replace function private.dms_can_read(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(d.org_id = private.current_org_id() and d.lifecycle <> 'cancelled' and (
    private.has_permission('dms.manage') or private.has_permission('dms.audit')
    or d.owner_user_id = auth.uid() or d.created_by = auth.uid()
    or private.dms_is_custodian(d.folder_id)
    or (exists (select 1 from public.dms_versions v where v.document_id = d.id and v.status = 'in_review') and private.dms_can_review(d))
    or (d.lifecycle = 'published' and coalesce(case d.classification
          when 'restricted' then private.current_role_id() = any (d.restricted_role_ids)
          when 'confidential' then private.has_permission('dms.view_confidential')
                                   and (private.has_permission('dms.upload_all') or d.department_id = private.dms_my_department())
          else d.scope = 'company' or private.has_permission('dms.upload_all')
               or private.dms_my_department() = any (d.scope_department_ids)
        end, false))), false)
$$;

create or replace function private.dms_can_edit(d public.dms_documents)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(d.org_id = private.current_org_id() and d.lifecycle <> 'cancelled'
     and (private.has_permission('dms.manage') or private.has_permission('dms.upload_all')
          or (private.has_permission('dms.upload') and (d.department_id = private.dms_my_department() or d.owner_user_id = auth.uid()))
          or private.dms_is_custodian(d.folder_id)), false)
$$;
