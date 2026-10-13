// Part 2 (time & attendance) types and React Query hooks.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export interface Shift {
  id: string; name: string; code: string; start_time: string; end_time: string; crosses_midnight: boolean
  break_minutes: number; checkin_earliest_minutes: number; late_grace_minutes: number; checkin_latest_minutes: number
  checkout_latest_minutes: number; early_out_grace_minutes: number; auto_checkout: boolean
  half_day_threshold_minutes: number; status: 'active' | 'inactive'
}
export interface Roster { id: string; employee_id: string; shift_id: string; date_from: string; date_to: string; is_override: boolean; note: string | null; status: 'active' | 'inactive' }
export interface Holiday { id: string; name: string; date: string; type: 'public' | 'company' | 'optional'; branch_ids: string[]; status: 'active' | 'inactive' }
export interface LeaveType {
  id: string; name: string; code: string; days_per_year: number | null; paid: boolean; carry_forward: boolean
  carry_forward_cap: number | null; accrual: 'yearly' | 'monthly'; allows_half_day: boolean; document_required: boolean
  counts_off_days: boolean; status: 'active' | 'inactive'
}
export interface WorkSettings {
  org_id: string; labor_regime: 'bd_labour_act' | 'bd_epz_labour_act'; weekly_off_days: number[]; default_shift_id: string | null
  month_days: number; late_deduction_mode: 'none' | 'days_per_lates' | 'amount_per_late'; lates_per_deduction: number
  late_deduction_days: number; late_amount_per_late: number; qr_rotation_seconds: number; require_location: boolean
}
export interface OvertimePolicy {
  org_id: string; weekday_multiplier: number; weekend_multiplier: number; holiday_multiplier: number; minimum_minutes: number
  rounding_minutes: number; daily_cap_minutes: number; monthly_cap_minutes: number | null; auto_capture: boolean; requires_approval: boolean
}
export interface Geofence { id: string; name: string; branch_id: string | null; office_id: string | null; latitude: number; longitude: number; radius_meters: number; status: 'active' | 'inactive' }
export interface PeriodLock { id: string; period_start: string; period_end: string; note: string | null; status: 'locked' | 'unlocked' }

export interface TimeConfig {
  shifts: Shift[]; holidays: Holiday[]; leaveTypes: LeaveType[]; settings: WorkSettings | null
  policy: OvertimePolicy | null; geofences: Geofence[]; locks: PeriodLock[]
}

export type AttendanceStatus = 'present' | 'late' | 'absent' | 'half_day' | 'early_out' | 'on_leave' | 'weekend' | 'holiday'
export interface AttendanceRow {
  id: string; employee_id: string; work_date: string; shift_id: string | null; office_id: string | null
  day_type: 'workday' | 'weekend' | 'holiday'; status: AttendanceStatus; check_in_at: string | null; check_out_at: string | null
  source_in: string | null; source_out: string | null; is_late: boolean; late_minutes: number; early_out_minutes: number
  worked_minutes: number; break_minutes: number; overtime_minutes: number; outside_geofence: boolean; auto_checked_out: boolean
  note: string | null; locked: boolean; full_name: string; card_id: string; department_name: string | null
  office_name: string | null; shift_name: string | null; shift_code: string | null; is_self: boolean
}
export interface OvertimeRow {
  id: string; employee_id: string; work_date: string; minutes: number; day_type: string; multiplier: number
  status: 'pending' | 'approved' | 'rejected'; source: 'auto' | 'manual'; reason: string | null; decision_note: string | null
  locked: boolean; full_name: string; card_id: string; department_name: string | null; is_self: boolean
}
export interface LeaveBalance {
  leave_type_id: string; code: string; name: string; paid: boolean; allows_half_day: boolean; document_required: boolean
  year: number; entitled: number | null; carried_forward: number; used: number; pending: number; available: number | null
}
export interface LeaveRequestRow {
  id: string; employee_id: string; leave_type_id: string; from_date: string; to_date: string; half_day: boolean; days: number
  reason: string | null; status: 'pending' | 'approved' | 'rejected' | 'cancelled'; decision_note: string | null
  decided_at: string | null; created_at: string; full_name: string; card_id: string; department_name: string | null
  leave_type_name: string; leave_type_code: string; approver_name: string | null; is_self: boolean; can_decide: boolean
}
export interface SwapRow {
  id: string; requester_employee_id: string; target_employee_id: string; work_date: string; reason: string | null
  status: 'pending' | 'peer_accepted' | 'approved' | 'rejected' | 'cancelled'; requester_name: string; target_name: string
  requester_shift_name: string; target_shift_name: string; is_requester: boolean; is_target: boolean; created_at: string
}
export interface MyToday {
  employee_id: string; date: string; day_type: string
  shift: { name: string; start_time: string; end_time: string; crosses_midnight: boolean; late_grace_minutes: number } | null
  record: AttendanceRow | null
  punches: { punched_at: string; source: string; outside_geofence: boolean }[]
  open_break: { id: string; break_start: string; type: string } | null
  has_geofences: boolean
}
export interface SummaryRow {
  employee_id: string; full_name: string; card_id: string; present_days: number; late_count: number; absent_days: number
  half_days: number; early_out_days: number; leave_days: number; off_days: number; worked_minutes: number; late_minutes: number
  approved_overtime_minutes: number; late_deduction_days: number; late_deduction_amount: number
}
export interface Summary {
  month: string; month_days: number
  policy: { mode: WorkSettings['late_deduction_mode']; lates_per_deduction: number; deduction_days: number; amount_per_late: number }
  rows: SummaryRow[]
}

async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

async function rows<T>(q: PromiseLike<{ data: unknown; error: unknown }>): Promise<T[]> {
  const { data, error } = await q
  if (error) throw error
  return (data ?? []) as T[]
}

export const TIME_KEYS = ['time-config', 'attendance', 'my-today', 'leave', 'overtime', 'swaps', 'summary', 'dashboard']

export function useInvalidateTime() {
  const qc = useQueryClient()
  return () => Promise.all(TIME_KEYS.map((k) => qc.invalidateQueries({ queryKey: [k] })))
}

export function useTimeConfig() {
  return useQuery({
    queryKey: ['time-config'],
    queryFn: async (): Promise<TimeConfig> => {
      const [shifts, holidays, leaveTypes, settings, policy, geofences, locks] = await Promise.all([
        rows<Shift>(supabase.from('shifts').select('*').order('start_time')),
        rows<Holiday>(supabase.from('holidays').select('*').order('date')),
        rows<LeaveType>(supabase.from('leave_types').select('*').order('code')),
        rows<WorkSettings>(supabase.from('org_work_settings').select('*')),
        rows<OvertimePolicy>(supabase.from('overtime_policy').select('*')),
        rows<Geofence>(supabase.from('geofences').select('*').order('name')),
        rows<PeriodLock>(supabase.from('period_locks').select('*').order('period_start', { ascending: false })),
      ])
      return { shifts, holidays, leaveTypes, settings: settings[0] ?? null, policy: policy[0] ?? null, geofences, locks }
    },
  })
}

export function useRosters(enabled = true) {
  return useQuery({
    queryKey: ['time-config', 'rosters'],
    enabled,
    queryFn: () => rows<Roster>(supabase.from('shift_rosters').select('*').eq('status', 'active').order('date_from', { ascending: false })),
  })
}

export function useAttendanceDay(date: string) {
  return useQuery({
    queryKey: ['attendance', 'day', date],
    queryFn: () => rows<AttendanceRow>(supabase.from('attendance_v').select('*').eq('work_date', date).order('full_name')),
  })
}

export function useAttendanceRange(from: string, to: string, employeeId?: string) {
  return useQuery({
    queryKey: ['attendance', 'range', from, to, employeeId],
    queryFn: () => {
      let q = supabase.from('attendance_v').select('*').gte('work_date', from).lte('work_date', to).order('work_date')
      if (employeeId) q = q.eq('employee_id', employeeId)
      return rows<AttendanceRow>(q)
    },
  })
}

export function useMyToday() {
  return useQuery({ queryKey: ['my-today'], queryFn: () => rpc<MyToday | null>('get_my_today'), refetchInterval: 60_000 })
}

export function useSummary(month: string) {
  return useQuery({ queryKey: ['summary', month], queryFn: () => rpc<Summary>('get_attendance_summary', { p_month: month }) })
}

export function useReconciliation(from: string, to: string, enabled: boolean) {
  return useQuery({
    queryKey: ['attendance', 'reconciliation', from, to],
    enabled,
    queryFn: () => rpc<{ record_id: string; employee_id: string; full_name: string; card_id: string; work_date: string; status: string;
      check_in_at: string | null; check_out_at: string | null; issue: 'missing_checkout' | 'outside_geofence'; locked: boolean }[]>(
      'get_reconciliation', { p_from: from, p_to: to }),
  })
}

export function useOvertime(from: string, to: string) {
  return useQuery({
    queryKey: ['overtime', from, to],
    queryFn: () => rows<OvertimeRow>(supabase.from('overtime_v').select('*').gte('work_date', from).lte('work_date', to).order('work_date', { ascending: false })),
  })
}

export function useLeaveBalances(employeeId?: string, year?: number) {
  return useQuery({
    queryKey: ['leave', 'balances', employeeId, year],
    queryFn: () => rpc<LeaveBalance[]>('get_leave_balances', { p_employee_id: employeeId ?? null, p_year: year ?? null }),
  })
}

export function useLeaveRequests(filter: { self?: boolean; status?: string }) {
  return useQuery({
    queryKey: ['leave', 'requests', filter],
    queryFn: () => {
      let q = supabase.from('leave_requests_v').select('*').order('from_date', { ascending: false }).limit(200)
      if (filter.self) q = q.eq('is_self', true)
      if (filter.status) q = q.eq('status', filter.status)
      return rows<LeaveRequestRow>(q)
    },
  })
}

export function useSwaps() {
  return useQuery({
    queryKey: ['swaps'],
    queryFn: () => rows<SwapRow>(supabase.from('shift_swaps_v').select('*').order('work_date', { ascending: false }).limit(100)),
  })
}

/** RPC mutation that refreshes all time data afterwards. */
export function useTimeAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const invalidate = useInvalidateTime()
  return useMutation({ mutationFn: (args: A) => rpc<R>(fn, args), onSuccess: () => invalidate() })
}

export function useSaveRow(table: string) {
  const invalidate = useInvalidateTime()
  return useMutation({
    mutationFn: async ({ id, values, key = 'id' }: { id?: string; values: Record<string, unknown>; key?: string }) => {
      const { error } = id ? await supabase.from(table).update(values).eq(key, id) : await supabase.from(table).insert(values)
      if (error) throw error
    },
    onSuccess: () => invalidate(),
  })
}

// ---------------------------------------------------------------- helpers --
export const STATUS_STYLE: Record<AttendanceStatus, { label: string; cls: string }> = {
  present: { label: 'Present', cls: 'bg-green-100 text-green-700' },
  late: { label: 'Late', cls: 'bg-amber-100 text-amber-800' },
  absent: { label: 'Absent', cls: 'bg-red-100 text-red-700' },
  half_day: { label: 'Half day', cls: 'bg-orange-100 text-orange-700' },
  early_out: { label: 'Early out', cls: 'bg-yellow-100 text-yellow-800' },
  on_leave: { label: 'On leave', cls: 'bg-blue-100 text-blue-700' },
  weekend: { label: 'Weekend', cls: 'bg-slate-100 text-slate-600' },
  holiday: { label: 'Holiday', cls: 'bg-purple-100 text-purple-700' },
}

export function minutesToHm(m: number | null | undefined): string {
  if (!m) return '0h'
  const h = Math.floor(m / 60)
  const r = m % 60
  return r ? `${h}h ${r}m` : `${h}h`
}

export function timeOf(iso: string | null | undefined): string {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
}

export function hhmm(t: string | null | undefined): string {
  return t ? t.slice(0, 5) : '—'
}

export const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

export function monthBounds(month: string): { from: string; to: string } {
  const [y, m] = month.split('-').map(Number)
  const last = new Date(Date.UTC(y, m, 0)).getUTCDate()
  return { from: `${month}-01`, to: `${month}-${String(last).padStart(2, '0')}` }
}

export function localDateString(d = new Date()): string {
  const off = d.getTimezoneOffset()
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 10)
}

/** Browser location for GPS punches (the future mobile app will send exact location). */
export function getBrowserLocation(timeoutMs = 10_000): Promise<{ lat: number; lng: number; accuracy: number } | null> {
  if (!('geolocation' in navigator)) return Promise.resolve(null)
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy: p.coords.accuracy }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: timeoutMs, maximumAge: 0 },
    )
  })
}

export function useColleagues(enabled = true) {
  return useQuery({
    queryKey: ['time-config', 'colleagues'],
    enabled,
    queryFn: () => rpc<{ id: string; full_name: string; card_id: string; department_name: string | null }[]>('list_colleagues'),
  })
}
