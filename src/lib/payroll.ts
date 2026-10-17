// Part 3A (salary structure) types, React Query hooks and money helpers.
// The database is the authority for every amount; the helpers here only
// preview what the server will calculate and format values for display.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export type Status = 'active' | 'inactive'
export type Calc = 'fixed' | 'percent_of_basic' | 'percent_of_gross'
export type ComponentKind = 'earning' | 'deduction'

export interface SalaryComponent {
  id: string; name: string; code: string; kind: ComponentKind; calc: Calc; default_value: number
  taxable: boolean; pf_applicable: boolean; is_basic: boolean; sort_order: number; status: Status
}
export interface SalaryTemplate {
  id: string; name: string; description: string | null; grade_id: string | null; basic_amount: number; status: Status
}
export interface TemplateLine { id: string; template_id: string; component_id: string; calc: Calc; value: number; sort_order: number }

export interface ResolvedLine {
  component_id: string; code: string; name: string; kind: ComponentKind; calc: Calc; rate: number | null; amount: number
}
export interface ResolvedSalary { template_id: string; basic: number; gross: number; total_deductions: number; lines: ResolvedLine[] }

export type ChangeType = 'initial' | 'increment' | 'promotion' | 'correction'
export interface PayRow {
  employee_id: string; full_name: string; card_id: string; employee_status: string; join_date: string
  department_id: string | null; department_name: string | null; grade_code: string | null
  compensation_id: string | null; template_id: string | null; template_name: string | null
  basic: number | null; gross: number | null; total_deductions: number | null; effective_from: string | null
  change_type: ChangeType | null; pending_increment_id: string | null
}
export interface CompensationVersion {
  id: string; template_id: string | null; template_name: string | null; basic: number; gross: number
  total_deductions: number; effective_from: string; effective_to: string | null; change_type: ChangeType
  reason: string | null; created_at: string
  lines: { code: string; name: string; kind: ComponentKind; calc: Calc; rate: number | null; amount: number }[]
}
export type IncrementType = 'increment' | 'promotion' | 'correction'
export interface IncrementRow {
  id: string; employee_id: string; type: IncrementType; template_id: string; old_gross: number; new_gross: number
  effective_date: string; reason: string; status: 'pending' | 'approved' | 'rejected' | 'cancelled'
  decided_at: string | null; decision_note: string | null; created_at: string; full_name: string; card_id: string
  template_name: string | null; requested_by_name: string | null; approved_by_name: string | null
  is_requester: boolean; is_self: boolean
}
export type BonusType = 'festival' | 'performance' | 'incentive' | 'annual' | 'ad_hoc'
export interface Bonus {
  id: string; name: string; type: BonusType; basis: 'fixed' | 'percent'; amount: number | null; percent: number | null
  percent_base: 'basic' | 'gross' | null; payment_month: string; min_service_months: number
  scope: 'all' | 'departments' | 'employees'; status: Status
}
export interface BonusEligibility { bonus_id: string; department_id: string | null; employee_id: string | null }
export interface BonusPreviewRow {
  employee_id: string; full_name: string; card_id: string; department_name: string | null; service_months: number
  basic: number | null; gross: number | null; eligible: boolean; reason: string | null; amount: number
}
export interface DeductionRow {
  id: string; employee_id: string; type: 'loan' | 'advance' | 'other'; description: string | null; total: number
  installment: number; start_month: string; remaining: number; status: 'active' | 'completed' | 'cancelled'
  note: string | null; created_at: string; full_name: string; card_id: string; is_self: boolean
}
export type PaymentMethod = 'bank' | 'mobile_wallet' | 'cash'
export interface PaymentAccountRow {
  id: string; employee_id: string; full_name: string; card_id: string; method: PaymentMethod; bank_name: string | null
  branch_name: string | null; routing_number: string | null; account_name: string | null
  wallet_provider: 'bkash' | 'nagad' | 'rocket' | 'upay' | 'other' | null; masked_number: string | null
  is_primary: boolean; status: Status; is_self: boolean
}
export interface PayrollSettings {
  org_id: string; deduct_base: 'basic' | 'gross'; ot_rate_basis: 'basic' | 'gross'; ot_hourly_divisor: number
  pay_weekly_off: boolean; pay_holidays: boolean; half_day_deduction_percent: number; unpaid_leave_base: 'basic' | 'gross'
  net_rounding: 'none' | 'nearest_taka' | 'up_taka' | 'down_taka'; negative_net_rule: 'zero_and_carry' | 'block'
  payslip_release: 'approved' | 'paid'; large_change_percent: number; auto_tds: boolean; pf_enabled: boolean
  gratuity_enabled: boolean; statutory_confirmed_at: string | null
}
export interface CompensationStats {
  active_employees: number; with_pay: number; monthly_gross: number; templates: number; pending_increments: number
}

// ---------------------------------------------------------------- data access --
async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

async function rows<T>(query: PromiseLike<{ data: unknown; error: unknown }>): Promise<T[]> {
  const { data, error } = await query
  if (error) throw error
  return (data ?? []) as T[]
}

/** Every query key that holds money data; refreshed together after any change. */
export const PAYROLL_KEYS = ['salary-config', 'pay', 'compensation', 'increments', 'bonuses', 'deductions', 'payment-accounts', 'payroll-settings']

export function useInvalidatePayroll() {
  const queryClient = useQueryClient()
  return () => Promise.all(PAYROLL_KEYS.map((key) => queryClient.invalidateQueries({ queryKey: [key] })))
}

export function useSalaryConfig(enabled = true) {
  return useQuery({
    queryKey: ['salary-config'],
    enabled,
    queryFn: async () => {
      const [components, templates, lines] = await Promise.all([
        rows<SalaryComponent>(supabase.from('salary_components').select('*').order('sort_order').order('code')),
        rows<SalaryTemplate>(supabase.from('salary_templates').select('*').order('name')),
        rows<TemplateLine>(supabase.from('salary_template_lines').select('*').order('sort_order')),
      ])
      return { components, templates, lines }
    },
  })
}

export function useCompensationStats() {
  return useQuery({ queryKey: ['pay', 'stats'], queryFn: () => rpc<CompensationStats>('get_compensation_stats') })
}

export function usePayList() {
  return useQuery({
    queryKey: ['pay', 'list'],
    queryFn: () => rows<PayRow>(supabase.from('employee_pay_v').select('*').eq('employee_status', 'active').order('full_name')),
  })
}

export function useEmployeeCompensation(employeeId: string | undefined, enabled = true) {
  return useQuery({
    queryKey: ['compensation', employeeId],
    enabled: enabled && !!employeeId,
    queryFn: () => rpc<CompensationVersion[]>('get_employee_compensation', { p_employee_id: employeeId }),
  })
}

/** Server-side preview for a saved template (used when a target gross is given). */
export function useSalaryPreview(templateId: string, basic: number | null, gross: number | null) {
  return useQuery({
    queryKey: ['salary-config', 'preview', templateId, basic, gross],
    enabled: !!templateId && (basic !== null || gross !== null),
    queryFn: () => rpc<ResolvedSalary>('preview_salary', { p_template_id: templateId, p_basic: basic, p_gross: gross }),
    retry: false,
  })
}

export function useIncrements(employeeId?: string, enabled = true) {
  return useQuery({
    queryKey: ['increments', employeeId],
    enabled,
    queryFn: () => {
      let query = supabase.from('salary_increments_v').select('*').order('created_at', { ascending: false }).limit(300)
      if (employeeId) query = query.eq('employee_id', employeeId)
      return rows<IncrementRow>(query)
    },
  })
}

export function useIncrementArrears(incrementId: string | null) {
  return useQuery({
    queryKey: ['increments', 'arrears', incrementId],
    enabled: !!incrementId,
    queryFn: () => rpc<{ until_month: string; back_dated: boolean; amount: number }>('get_increment_arrears', { p_increment_id: incrementId }),
  })
}

export function useBonuses(enabled = true) {
  return useQuery({
    queryKey: ['bonuses'],
    enabled,
    queryFn: async () => {
      const [bonuses, eligibility] = await Promise.all([
        rows<Bonus>(supabase.from('bonuses').select('*').order('payment_month', { ascending: false })),
        rows<BonusEligibility>(supabase.from('bonus_eligibility').select('bonus_id, department_id, employee_id')),
      ])
      return { bonuses, eligibility }
    },
  })
}

export function useBonusPreview(bonusId: string | null) {
  return useQuery({
    queryKey: ['bonuses', 'preview', bonusId],
    enabled: !!bonusId,
    queryFn: () => rpc<BonusPreviewRow[]>('get_bonus_preview', { p_bonus_id: bonusId }),
  })
}

export function useDeductions(employeeId?: string, enabled = true) {
  return useQuery({
    queryKey: ['deductions', employeeId],
    enabled,
    queryFn: () => {
      let query = supabase.from('employee_deductions_v').select('*').order('created_at', { ascending: false }).limit(500)
      if (employeeId) query = query.eq('employee_id', employeeId)
      return rows<DeductionRow>(query)
    },
  })
}

export function usePaymentAccounts(employeeId?: string, enabled = true) {
  return useQuery({
    queryKey: ['payment-accounts', employeeId],
    enabled,
    queryFn: () => {
      let query = supabase.from('payment_accounts_v').select('*').order('is_primary', { ascending: false }).order('created_at')
      if (employeeId) query = query.eq('employee_id', employeeId)
      return rows<PaymentAccountRow>(query)
    },
  })
}

export function usePayrollSettings() {
  return useQuery({
    queryKey: ['payroll-settings'],
    queryFn: async () => (await rows<PayrollSettings>(supabase.from('payroll_settings').select('*')))[0] ?? null,
  })
}

/** RPC mutation that refreshes all money data afterwards. */
export function usePayrollAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const invalidate = useInvalidatePayroll()
  return useMutation({ mutationFn: (args: A) => rpc<R>(fn, args), onSuccess: () => invalidate() })
}

/** Direct insert/update for tables that allow it (RLS + column grants decide). */
export function useSavePayrollRow(table: 'salary_components' | 'payroll_settings') {
  const invalidate = useInvalidatePayroll()
  return useMutation({
    mutationFn: async ({ id, values, key = 'id' }: { id?: string; values: Record<string, unknown>; key?: string }) => {
      const { error } = id ? await supabase.from(table).update(values).eq(key, id) : await supabase.from(table).insert(values)
      if (error) throw error
    },
    onSuccess: () => invalidate(),
  })
}

/** Reveals one account number. Not cached: the number is shown once and every reveal is audited. */
export async function revealPaymentAccount(accountId: string): Promise<string> {
  return rpc<string>('reveal_payment_account', { p_account_id: accountId })
}

// ------------------------------------------------------------- money helpers --
const takaFormatter = new Intl.NumberFormat('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

/** 17450 -> "৳17,450.00" (Indian/Bangladeshi digit grouping). */
export function formatTaka(amount: number | null | undefined): string {
  if (amount === null || amount === undefined || Number.isNaN(Number(amount))) return '—'
  return `৳${takaFormatter.format(Number(amount))}`
}

/** Parses a typed amount: up to 2 decimals, not negative. Returns null when invalid. */
export function parseMoney(input: string): number | null {
  const value = input.replace(/[,\s৳]/g, '')
  if (!/^\d{1,8}(\.\d{1,2})?$/.test(value)) return null
  return Number(value)
}

const toPaisa = (amount: number) => Math.round(amount * 100)
/** Percent with 2 decimals as an integer in hundredths (50.25% -> 5025). */
const toBasisPoints = (percent: number) => Math.round(percent * 100)

/** a / b rounded half away from zero, for non-negative integers. */
function roundDiv(numerator: bigint, denominator: bigint): bigint {
  return (2n * numerator + denominator) / (2n * denominator)
}

export interface DraftLine { component_id: string; code: string; name: string; kind: ComponentKind; calc: Calc; value: number }

/**
 * Live preview for the template builder, before the template is saved. Mirrors
 * private.resolve_salary (basic mode) in integer paisa, so it shows the same
 * amounts the server will store. Percent-of-gross earnings use the gross that
 * the formula gross = basic + fixed + basic·Σ%basic + gross·Σ%gross gives.
 */
export function previewTemplate(basic: number, lines: DraftLine[]) {
  const basicPaisa = BigInt(toPaisa(basic))
  const earnings = lines.filter((l) => l.kind === 'earning')
  const fixedPaisa = BigInt(earnings.filter((l) => l.calc === 'fixed').reduce((sum, l) => sum + toPaisa(l.value), 0))
  const basicPoints = BigInt(earnings.filter((l) => l.calc === 'percent_of_basic').reduce((sum, l) => sum + toBasisPoints(l.value), 0))
  const grossPoints = BigInt(earnings.filter((l) => l.calc === 'percent_of_gross').reduce((sum, l) => sum + toBasisPoints(l.value), 0))
  if (grossPoints >= 10000n) return { valid: false as const, error: 'Percent-of-gross earnings must add up to less than 100%' }

  // gross estimate in paisa = (basic·(10000 + Σ%basic) + fixed·10000) / (10000 − Σ%gross)
  const estimateNumerator = basicPaisa * (10000n + basicPoints) + fixedPaisa * 10000n
  const estimateDenominator = 10000n - grossPoints

  const resolved = lines.map((line) => {
    const points = BigInt(toBasisPoints(line.value))
    const amountPaisa =
      line.calc === 'fixed' ? BigInt(toPaisa(line.value))
        : line.calc === 'percent_of_basic' ? roundDiv(basicPaisa * points, 10000n)
          : roundDiv(estimateNumerator * points, estimateDenominator * 10000n)
    return { ...line, amount: Number(amountPaisa) / 100 }
  })
  const grossPaisa = resolved.filter((l) => l.kind === 'earning').reduce((sum, l) => sum + toPaisa(l.amount), toPaisa(basic))
  const deductionPaisa = resolved.filter((l) => l.kind === 'deduction').reduce((sum, l) => sum + toPaisa(l.amount), 0)
  return { valid: true as const, lines: resolved, gross: grossPaisa / 100, totalDeductions: deductionPaisa / 100 }
}

/** Month-by-month installments until the balance reaches zero (the last one may be smaller). */
export function installmentSchedule(total: number, installment: number, startMonth: string, maxRows = 120) {
  const schedule: { month: string; amount: number; remaining: number }[] = []
  if (!(total > 0) || !(installment > 0)) return schedule
  let remainingPaisa = toPaisa(total)
  const installmentPaisa = toPaisa(installment)
  const [startYear, startMonthIndex] = startMonth.split('-').map(Number)
  for (let i = 0; remainingPaisa > 0 && i < maxRows; i++) {
    const amountPaisa = Math.min(installmentPaisa, remainingPaisa)
    remainingPaisa -= amountPaisa
    const date = new Date(Date.UTC(startYear, startMonthIndex - 1 + i, 1))
    schedule.push({ month: date.toISOString().slice(0, 7), amount: amountPaisa / 100, remaining: remainingPaisa / 100 })
  }
  return schedule
}

export const CALC_LABEL: Record<Calc, string> = {
  fixed: 'Fixed amount',
  percent_of_basic: '% of basic',
  percent_of_gross: '% of gross',
}
export const CHANGE_LABEL: Record<ChangeType, string> = {
  initial: 'Starting pay', increment: 'Increment', promotion: 'Promotion', correction: 'Correction',
}
export const BONUS_TYPE_LABEL: Record<BonusType, string> = {
  festival: 'Festival', performance: 'Performance', incentive: 'Incentive', annual: 'Annual', ad_hoc: 'Ad hoc',
}
export const WALLET_LABEL: Record<NonNullable<PaymentAccountRow['wallet_provider']>, string> = {
  bkash: 'bKash', nagad: 'Nagad', rocket: 'Rocket', upay: 'Upay', other: 'Other wallet',
}

/** "2026-06-01" -> "Jun 2026". */
export function formatMonth(value: string | null | undefined): string {
  if (!value) return '—'
  const [year, month] = value.split('-').map(Number)
  return new Date(Date.UTC(year, month - 1, 1)).toLocaleDateString('en-GB', { month: 'short', year: 'numeric', timeZone: 'UTC' })
}
