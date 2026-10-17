// Types and React Query hooks for HR data (Steps 3-9).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

// ---------------------------------------------------------------- types --
export type Status = 'active' | 'inactive'

export interface Grade { id: string; code: string; category: 'EM' | 'MS' | 'OWNER'; level: number; description: string | null; status: Status }
export interface Department { id: string; name: string; code: string | null; description: string | null; head_employee_id: string | null; status: Status }
export interface Designation { id: string; department_id: string; grade_id: string; name: string; description: string | null; status: Status }
export interface Branch { id: string; name: string; code: string | null; address: string | null; phone: string | null; head_employee_id: string | null; status: Status }
export interface Office { id: string; branch_id: string; name: string; code: string | null; layout: string | null; address: string | null; status: Status }
export interface Operation { id: string; name: string; description: string | null; status: Status }
export interface OfficeOperation { office_id: string; operation_id: string }

export interface OrgStructure {
  grades: Grade[]
  departments: Department[]
  designations: Designation[]
  branches: Branch[]
  offices: Office[]
  operations: Operation[]
  officeOperations: OfficeOperation[]
}

export interface Employee {
  id: string
  card_id: string
  full_name: string
  status: 'active' | 'inactive' | 'terminated'
  exit_date: string | null
  department_id: string | null; department_name: string | null
  designation_id: string | null; designation_name: string | null
  grade_id: string | null; grade_code: string | null; grade_level: number | null
  branch_id: string | null; branch_name: string | null
  office_id: string | null; office_name: string | null
  operation_id: string | null; operation_name: string | null
  user_id: string | null
  has_portal_access: boolean
  portal_role_id: string | null; portal_role_name: string | null; portal_role_key: string | null
  is_self: boolean
  phone: string | null
  email: string | null
  date_of_birth: string | null
  gender: string | null
  marital_status: string | null
  religion: string | null
  blood_group: string | null
  join_date: string | null
  employment_type: string | null
  present_address: string | null
  permanent_address: string | null
  probation_end_date: string | null
  confirmation_date: string | null
  nid_number: string | null
}

export interface Nominee { id?: string; name: string; phone: string | null; relation: string }
export interface HistoryRow {
  id: string
  event_type: string
  from: Record<string, unknown> | null
  to: Record<string, unknown> | null
  effective_date: string
  reason: string | null
  created_at: string
  created_by_name: string | null
}
export interface ReportingRow {
  id: string; line_type: string; start_date: string; end_date: string | null; reason: string | null
  manager_id: string; manager_name: string; manager_card_id: string; manager_status: string
}
export interface EmployeeProfile {
  employee: Employee
  editable_fields: string[] | null
  nominees: Nominee[] | null
  history: HistoryRow[] | null
  reporting: ReportingRow[] | null
  direct_reports: { id: string; full_name: string; card_id: string; line_type: string }[] | null
  portal: {
    user_id: string; email: string | null; phone: string | null; user_status: string
    last_login_at: string | null; must_change_password: boolean
    membership_status: string | null; role_id: string | null; role_name: string | null; role_key: string | null
  } | null
}

export interface Role { id: string; name: string; description: string | null; system_key: string | null; is_system: boolean; status: Status }
export interface Permission { key: string; module: string; description: string; admin_only: boolean }
export interface FieldDef { resource: string; field_key: string; label: string; group_name: string; sensitive: boolean; sort: number }
export interface FieldAccess { role_id: string; resource: string; field_key: string; can_view: boolean; can_edit: boolean }

// --------------------------------------------------------------- helpers --
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

async function selectAll<T>(table: string, order = 'name'): Promise<T[]> {
  const { data, error } = await supabase.from(table).select('*').order(order)
  if (error) throw error
  return data as T[]
}

// ------------------------------------------------------------- structure --
export function useOrgStructure() {
  return useQuery({
    queryKey: ['org-structure'],
    queryFn: async (): Promise<OrgStructure> => {
      const [grades, departments, designations, branches, offices, operations, officeOperations] = await Promise.all([
        selectAll<Grade>('grades', 'level'),
        selectAll<Department>('departments'),
        selectAll<Designation>('designations'),
        selectAll<Branch>('branches'),
        selectAll<Office>('offices'),
        selectAll<Operation>('operations'),
        selectAll<OfficeOperation>('office_operations', 'office_id'),
      ])
      return { grades, departments, designations, branches, offices, operations, officeOperations }
    },
  })
}

export function useInvalidate() {
  const qc = useQueryClient()
  return (...keys: string[]) => Promise.all(keys.map((k) => qc.invalidateQueries({ queryKey: [k] })))
}

/** Insert or update one structure row (RLS + column grants decide what is allowed). */
export function useSaveStructure(table: string) {
  const invalidate = useInvalidate()
  return useMutation({
    mutationFn: async ({ id, values }: { id?: string; values: Record<string, unknown> }) => {
      const q = id ? supabase.from(table).update(values).eq('id', id) : supabase.from(table).insert(values)
      const { error } = await q
      if (error) throw error
    },
    onSuccess: () => invalidate('org-structure', 'employees', 'dashboard', 'time-config', 'attendance', 'salary-config'),
  })
}

// ------------------------------------------------------------- employees --
export interface EmployeeFilters {
  search: string
  status: string
  department_id: string
  branch_id: string
  employment_type: string
  page: number
  pageSize: number
}

export function useEmployees(f: EmployeeFilters) {
  return useQuery({
    queryKey: ['employees', f],
    queryFn: async () => {
      let q = supabase.from('employees_v').select('*', { count: 'exact' }).order('full_name')
      if (f.status) q = q.eq('status', f.status)
      if (f.department_id) q = q.eq('department_id', f.department_id)
      if (f.branch_id) q = q.eq('branch_id', f.branch_id)
      if (f.employment_type) q = q.eq('employment_type', f.employment_type)
      const s = f.search.trim().replace(/[,()*]/g, ' ')
      if (s) q = q.or(`full_name.ilike.*${s}*,card_id.ilike.*${s}*,phone.ilike.*${s}*`)
      const from = f.page * f.pageSize
      const { data, error, count } = await q.range(from, from + f.pageSize - 1)
      if (error) throw error
      return { rows: data as Employee[], total: count ?? 0 }
    },
    placeholderData: (prev) => prev,
  })
}

/** Active employees for pickers (managers, heads). */
export function useEmployeeOptions(enabled = true) {
  return useQuery({
    queryKey: ['employees', 'options'],
    enabled,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('employees_v')
        .select('id, full_name, card_id, designation_name')
        .eq('status', 'active')
        .order('full_name')
      if (error) throw error
      return data as Pick<Employee, 'id' | 'full_name' | 'card_id' | 'designation_name'>[]
    },
  })
}

export function useEmployeeStats() {
  return useQuery({
    queryKey: ['employees', 'stats'],
    queryFn: () => rpc<{ total: number; active: number; inactive: number; portal_access: number; departments: number }>('get_employee_stats'),
  })
}

export function useEmployeeProfile(id: string | undefined) {
  return useQuery({
    queryKey: ['employees', 'profile', id],
    enabled: !!id,
    queryFn: () => rpc<EmployeeProfile>('get_employee_profile', { p_employee_id: id }),
  })
}

/** Generic RPC mutation that refreshes employee + dashboard data. */
export function useHrAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const invalidate = useInvalidate()
  return useMutation({
    mutationFn: (args: A) => rpc<R>(fn, args),
    onSuccess: () => invalidate('employees', 'dashboard', 'org-structure'),
  })
}

// ------------------------------------------------------------------ roles --
export function useRolesData() {
  return useQuery({
    queryKey: ['roles'],
    queryFn: async () => {
      const [roles, permissions, rolePerms, fields, access] = await Promise.all([
        selectAll<Role>('roles'),
        selectAll<Permission>('permissions', 'key'),
        supabase.from('role_permissions').select('role_id, permission_key').then(({ data, error }) => {
          if (error) throw error
          return data as { role_id: string; permission_key: string }[]
        }),
        selectAll<FieldDef>('field_catalog', 'sort'),
        supabase.from('role_field_access').select('role_id, resource, field_key, can_view, can_edit').then(({ data, error }) => {
          if (error) throw error
          return data as FieldAccess[]
        }),
      ])
      return { roles, permissions, rolePerms, fields, access }
    },
  })
}

// -------------------------------------------------------------- dashboard --
export interface DashboardStats {
  kpis: { total: number; active: number; new_this_month: number; portal_access: number; departments: number; branches: number }
  headcount_trend: { month: string; headcount: number }[]
  employment_types: { type: string; count: number }[]
  by_department: { department: string; count: number }[]
  joiners_leavers: { month: string; joiners: number; leavers: number }[]
  recent_activity: { employee_id: string; who: string; event_type: string; to: Record<string, unknown> | null; effective_date: string; created_at: string }[]
}

export function useDashboardStats(enabled: boolean) {
  return useQuery({
    queryKey: ['dashboard'],
    enabled,
    queryFn: () => rpc<DashboardStats | null>('get_dashboard_stats'),
  })
}

// ------------------------------------------------------------------ audit --
export interface AuditRow {
  id: string; created_at: string; action: string; entity: string; entity_id: string | null
  old_value: Record<string, unknown> | null; new_value: Record<string, unknown> | null
  ip: string | null; user_agent: string | null; actor_user_id: string | null; actor_name: string | null
}
export interface AuditFilters { actor: string; action: string; entity: string; from: string; to: string; page: number }

export function useAuditLogs(f: AuditFilters, pageSize = 50) {
  return useQuery({
    queryKey: ['audit', f],
    placeholderData: (prev) => prev,
    queryFn: () =>
      rpc<{ total: number; rows: AuditRow[] }>('list_audit_logs', {
        p_actor: f.actor || null,
        p_action: f.action || null,
        p_entity: f.entity || null,
        p_from: f.from || null,
        p_to: f.to || null,
        p_limit: pageSize,
        p_offset: f.page * pageSize,
      }),
  })
}

export function useAuditFilterOptions() {
  return useQuery({
    queryKey: ['audit', 'options'],
    queryFn: () => rpc<{ actors: { id: string; name: string }[]; actions: string[]; entities: string[] }>('get_audit_filter_options'),
  })
}

export function useSettingsSave() {
  const invalidate = useInvalidate()
  return useMutation({
    mutationFn: async ({ id, values }: { id: string; values: Record<string, unknown> }) => {
      const { error } = await supabase.from('organizations').update(values).eq('id', id)
      if (error) throw error
    },
    onSuccess: () => invalidate('org-settings'),
  })
}

export function useOrgSettings(id: string | undefined) {
  return useQuery({
    queryKey: ['org-settings', id],
    enabled: !!id,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('organizations')
        .select('id, name, org_code, timezone, card_id_mode, card_id_length, status')
        .eq('id', id!)
        .single()
      if (error) throw error
      return data as { id: string; name: string; org_code: string; timezone: string; card_id_mode: 'auto' | 'custom'; card_id_length: number; status: string }
    },
  })
}
