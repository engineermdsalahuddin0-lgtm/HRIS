// Part 3C (tax / TDS, provident fund, gratuity), the law & policy reference
// library and the performance-scoring demo: types and React Query hooks.
// Every number is calculated in the database; this file reads and triggers.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

// ---------------------------------------------------------------- references --
export type ReferenceCategory = 'law' | 'company_policy' | 'company_setting'

export interface StatutoryReference {
  key: string; category: ReferenceCategory; area: string; title: string; title_bn: string | null
  law_name: string | null; section: string | null; summary: string; summary_bn: string | null
  source_url: string | null; verified_on: string | null; status: 'verified' | 'needs_confirmation'; sort_order: number
}

export function useStatutoryReferences() {
  return useQuery({
    queryKey: ['statutory', 'references'],
    staleTime: 60 * 60 * 1000,
    queryFn: () => callRpc<StatutoryReference[]>('list_statutory_references'),
  })
}

// ------------------------------------------------------------------------ tax --
export type TaxpayerType = 'general' | 'woman_senior' | 'disabled' | 'third_gender' | 'freedom_fighter'

export const TAXPAYER_TYPE_LABEL: Record<TaxpayerType, string> = {
  general: 'General',
  woman_senior: 'Woman or aged 65+',
  disabled: 'Person with disability',
  third_gender: 'Third gender',
  freedom_fighter: 'War-wounded freedom fighter',
}

export interface TaxBand { from: number; to: number | null; rate: number; amount_in_band: number; tax: number }

/** The working of one annual tax calculation (calculator and payslips). */
export interface TaxDetail {
  fiscal_year: string; taxpayer_type: TaxpayerType; annual_income: number; exempt: number
  exempt_rule: { divisor: number; cap: number }; taxable_income: number; threshold: number; bands: TaxBand[]
  gross_tax: number; investment: number
  rebate: { by_income: number; income_percent: number; by_investment: number; investment_percent: number; cap: number; applied: number }
  tax_after_rebate: number; minimum_tax: number; annual_tax: number; references: string[]
  monthly_tds?: number
  // Only on payslips (projection method).
  projection?: {
    ytd_income: number; this_month: number; regular_monthly: number; future_months: number; months_remaining: number
    projected_income: number; declared_investment: number; pf_investment: number
  }
  ytd_tds?: number; auto_tds?: boolean; has_profile?: boolean; has_tin?: boolean
}

export interface TaxYear {
  id: string; code: string; from_date: string; to_date: string; salary_exempt_divisor: number; salary_exempt_cap: number
  rebate_income_percent: number; rebate_investment_percent: number; rebate_cap: number; minimum_tax: number
  minimum_tax_new: number; parent_disabled_extra: number; thresholds: Record<TaxpayerType, number>
  slabs: { band_order: number; width: number | null; rate: number }[]
}

export function useTaxTables() {
  return useQuery({ queryKey: ['statutory', 'tax-tables'], queryFn: () => callRpc<TaxYear[]>('get_tax_tables') })
}

export interface TaxPreviewInput {
  annual_income: number; investment: number; taxpayer_type: TaxpayerType; is_new_taxpayer: boolean
  parent_of_disabled: boolean
}

export function useTaxPreview(input: TaxPreviewInput | null) {
  return useQuery({
    queryKey: ['statutory', 'tax-preview', input],
    enabled: !!input,
    queryFn: () => callRpc<TaxDetail>('preview_tax', { p: input }),
  })
}

export interface TaxProfileRow {
  employee_id: string; full_name: string; card_id: string; department_name: string | null; profile_id: string | null
  tin: string | null; taxpayer_type: TaxpayerType; is_new_taxpayer: boolean; parent_of_disabled: boolean
  declared_investment: number; note: string | null; ytd_tds: number
}

export function useTaxProfiles() {
  return useQuery({ queryKey: ['statutory', 'tax-profiles'], queryFn: () => callRpc<TaxProfileRow[]>('list_tax_profiles') })
}

export interface TdsLedgerRow {
  id: string; employee_id: string; full_name: string; card_id: string; tin: string | null; fiscal_year: string
  period_month: string; tds_amount: number; challan_reference: string | null; challan_date: string | null
  status: 'posted' | 'deposited'
}

export function useTdsLedger(fiscalYear: string | null) {
  return useQuery({
    queryKey: ['statutory', 'tds-ledger', fiscalYear],
    queryFn: () => callRpc<TdsLedgerRow[]>('list_tds_ledger', { p_fiscal_year: fiscalYear }),
  })
}

export interface RunStatutoryRow {
  slip_id: string; employee_id: string; taxable_earnings: number; tds: number; tds_preview: number
  annual_tax: number | null; pf_employee: number; pf_employer: number
}

export function useRunStatutorySummary(runId: string | undefined) {
  return useQuery({
    queryKey: ['payroll', 'run-statutory', runId],
    enabled: !!runId,
    queryFn: () => callRpc<RunStatutoryRow[]>('get_run_statutory_summary', { p_run_id: runId }),
  })
}

// ------------------------------------------------------------------ settings --
export interface VestingBand { min_years: number; percent: number }
export interface GratuityBand { min_years: number; days: number }

export interface PfSettings {
  employee_rate: number; employer_rate: number; basis: 'basic' | 'gross'; min_service_months: number
  interest_rate: number; vesting: VestingBand[]; is_recognised: boolean; confirmed_at: string | null
}

export interface GratuitySettings {
  basis: 'last_basic' | 'average_last_3_basic'; min_service_months: number; partial_year_months: number
  bands: GratuityBand[]; provision_enabled: boolean; confirmed_at: string | null
}

export interface StatutorySettings {
  switches: { auto_tds: boolean; tds_apply_minimum_tax: boolean; tds_confirmed_at: string | null; pf_enabled: boolean; gratuity_enabled: boolean }
  pf: PfSettings
  gratuity: GratuitySettings
  can_edit: boolean
}

export function useStatutorySettings() {
  return useQuery({ queryKey: ['statutory', 'settings'], queryFn: () => callRpc<StatutorySettings>('get_statutory_settings') })
}

// ------------------------------------------------------------------------- PF --
export interface PfMemberRow {
  employee_id: string; full_name: string; card_id: string; join_date: string
  member_status: 'active' | 'left' | null; enrolled_from: string | null; left_on: string | null
  employee_total: number; employer_total: number; interest_total: number
}

export function usePfMembers() {
  return useQuery({ queryKey: ['statutory', 'pf-members'], queryFn: () => callRpc<PfMemberRow[]>('list_pf_members') })
}

export interface PfStatementRow {
  period_month: string; entry_type: 'contribution' | 'interest'; employee_amount: number; employer_amount: number
  interest_amount: number; note: string | null; balance: number
}

export function usePfStatement(employeeId: string | null) {
  return useQuery({
    queryKey: ['statutory', 'pf-statement', employeeId],
    enabled: !!employeeId,
    queryFn: () => callRpc<{ rows: PfStatementRow[] }>('get_pf_statement', { p_employee_id: employeeId }),
  })
}

export interface PfWithdrawalPreview {
  join_date: string; leaving_date: string; service_years: number; employee_portion: number; employer_portion: number
  vested_percent: number; employer_vested: number; interest: number; total: number; vesting: VestingBand[]
  references: string[]
}

export function usePfWithdrawalPreview(employeeId: string, leavingDate: string) {
  return useQuery({
    queryKey: ['statutory', 'pf-withdrawal', employeeId, leavingDate],
    enabled: !!employeeId && !!leavingDate,
    queryFn: () => callRpc<PfWithdrawalPreview>('preview_pf_withdrawal', { p_employee_id: employeeId, p_leaving_date: leavingDate }),
  })
}

// ------------------------------------------------------------------- gratuity --
export interface GratuityPreview {
  join_date: string; until: string
  service: { years: number; months: number; days: number; total_months: number }
  counted_years: number; partial_year_months: number; days_per_year: number; bands: GratuityBand[]
  basis: GratuitySettings['basis']; basic: number; daily_basic: number; min_service_months: number; amount: number
  not_eligible_reason: string | null; references: string[]
}

export function useGratuityPreview(employeeId: string, leavingDate: string) {
  return useQuery({
    queryKey: ['statutory', 'gratuity-preview', employeeId, leavingDate],
    enabled: !!employeeId && !!leavingDate,
    queryFn: () => callRpc<GratuityPreview>('preview_gratuity', { p_employee_id: employeeId, p_leaving_date: leavingDate }),
  })
}

export interface GratuityLiabilityRow {
  employee_id: string; full_name: string; card_id: string; join_date: string; counted_years: number
  days_per_year: number; basic: number; liability: number; provisioned: number
}

export function useGratuityLiability() {
  return useQuery({
    queryKey: ['statutory', 'gratuity-liability'],
    queryFn: () => callRpc<GratuityLiabilityRow[]>('list_gratuity_liability'),
  })
}

// --------------------------------------------------------------- performance --
export interface PerformanceCriterion { id: string; name: string; description: string | null; weight: number }

export interface PerformanceCycle {
  id: string; name: string; period_from: string; period_to: string; status: 'draft' | 'open' | 'closed'
  criteria: PerformanceCriterion[]; submitted: number; average_score: number | null
}

export interface PerformancePerson {
  employee_id: string; full_name: string; card_id: string; department_name: string | null
  designation_name: string | null; review_status: 'not_started' | 'draft' | 'submitted' | 'acknowledged'
  overall_score: number | null; rating: string | null
}

export interface PerformanceReviewDetail {
  cycle: { id: string; name: string; period_from: string; period_to: string; status: PerformanceCycle['status'] }
  employee: { id: string; full_name: string; card_id: string; designation_name: string | null; department_name: string | null }
  review: {
    id: string; status: 'draft' | 'submitted' | 'acknowledged'; overall_score: number | null; rating: string | null
    strengths: string | null; improvements: string | null; employee_comment: string | null; reviewer_name: string | null
    submitted_at: string | null; acknowledged_at: string | null
  } | null
  criteria: (PerformanceCriterion & { score: number | null; comment: string | null; weighted: number | null })[]
  references: string[]
  can_edit?: boolean
}

export function usePerformanceCycles(enabled = true) {
  return useQuery({
    queryKey: ['performance', 'cycles'],
    enabled,
    queryFn: () => callRpc<PerformanceCycle[]>('list_performance_cycles'),
  })
}

export function usePerformanceCycle(cycleId: string | null) {
  return useQuery({
    queryKey: ['performance', 'cycle', cycleId],
    enabled: !!cycleId,
    queryFn: () => callRpc<{ cycle: PerformanceCycle; can_manage: boolean; people: PerformancePerson[] }>(
      'get_performance_cycle', { p_cycle_id: cycleId }),
  })
}

export function usePerformanceReview(cycleId: string | null, employeeId: string | null) {
  return useQuery({
    queryKey: ['performance', 'review', cycleId, employeeId],
    enabled: !!cycleId && !!employeeId,
    queryFn: () => callRpc<PerformanceReviewDetail>('get_performance_review', { p_cycle_id: cycleId, p_employee_id: employeeId }),
  })
}

export function useMyPerformanceReviews() {
  return useQuery({
    queryKey: ['performance', 'mine'],
    queryFn: () => callRpc<PerformanceReviewDetail[]>('list_my_performance_reviews'),
  })
}

// -------------------------------------------------------------------- actions --
/** Any 3C / PMS write; refreshes statutory, payroll and performance screens. */
export function useStatutoryAction<TArgs extends Record<string, unknown>, TResult = unknown>(fn: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (args: TArgs) => callRpc<TResult>(fn, args),
    onSuccess: () => Promise.all([
      queryClient.invalidateQueries({ queryKey: ['statutory'] }),
      queryClient.invalidateQueries({ queryKey: ['payroll'] }),
      queryClient.invalidateQueries({ queryKey: ['performance'] }),
    ]),
  })
}
