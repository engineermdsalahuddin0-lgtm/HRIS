// Part 3B (payroll engine) types, React Query hooks and export helpers.
// Every amount comes from the database; this file only reads, triggers
// lifecycle actions and formats.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export type RunStatus = 'draft' | 'calculated' | 'reviewed' | 'approved' | 'paid' | 'locked' | 'cancelled'
export type RunScope = 'all' | 'branch' | 'department'
export type WarningSeverity = 'warning' | 'blocker'

export interface PayrollWarning { code: string; severity: WarningSeverity; message: string }

export interface PayrollRunSummary {
  id: string; period_month: string; scope: RunScope; scope_id: string | null; scope_name: string | null
  status: RunStatus; employee_count: number; total_gross: number; total_deductions: number; total_net: number
  warning_count: number; blocker_count: number; calculated_at: string | null; approved_at: string | null; created_at: string
}

export interface PayrollRunDetail {
  run: PayrollRunSummary & {
    run_warnings: PayrollWarning[]; is_stale: boolean; is_preparer: boolean; reopen_count: number; note: string | null
    prepared_by_name: string | null; reviewed_by_name: string | null; approved_by_name: string | null
    reviewed_at: string | null; paid_at: string | null; locked_at: string | null
  }
  slips: {
    id: string; employee_id: string; full_name: string; card_id: string; department_name: string | null
    grade_code: string | null; monthly_gross: number; payable_days: number; absent_days: number; overtime_minutes: number
    gross_earnings: number; total_deductions: number; net: number; carry_forward_out: number
    payment_method: 'bank' | 'mobile_wallet' | 'cash' | null; payment_status: 'pending' | 'paid'
    warnings: PayrollWarning[]; has_blocker: boolean
  }[]
  batches: {
    id: string; method: 'bank' | 'mobile_wallet' | 'cash' | 'unassigned'; row_count: number; total: number
    status: 'generated' | 'exported' | 'paid'; exported_at: string | null; paid_at: string | null; reference: string | null
  }[]
}

export interface PayslipLine {
  direction: 'earning' | 'deduction'; line_type: string; code: string; label: string
  base: number | null; rate: number | null; quantity: number | null; amount: number
}

export interface Payslip {
  slip: {
    id: string; employee_id: string; period_month: string; monthly_basic: number; monthly_gross: number
    employed_days: number; payable_days: number; absent_days: number; half_days: number; unpaid_leave_days: number
    late_count: number; overtime_minutes: number; gross_earnings: number; total_deductions: number
    net_before_rounding: number; rounding_adjustment: number; net: number; carry_forward_out: number
    payment_method: string | null; payment_status: 'pending' | 'paid'; warnings: PayrollWarning[]
  }
  run: { id: string; status: RunStatus; period_month: string; approved_at: string | null }
  employee: {
    full_name: string; card_id: string; join_date: string; department_name: string | null
    designation_name: string | null; grade_code: string | null; branch_name: string | null
  }
  organization: { name: string; org_code: string }
  payment: { method: string; bank_name: string | null; wallet_provider: string | null; masked_number: string | null } | null
  lines: PayslipLine[]
}

export interface MyPayslipRow {
  id: string; period_month: string; gross_earnings: number; total_deductions: number; net: number
  payment_status: 'pending' | 'paid'; run_status: RunStatus
}

export interface AdjustmentRow {
  id: string; employee_id: string; full_name: string; card_id: string; apply_month: string
  type: 'arrear' | 'correction' | 'manual'; direction: 'earning' | 'deduction'; amount: number; reason: string
  status: 'pending' | 'approved' | 'rejected' | 'applied' | 'cancelled'
  created_by_name: string | null; approved_by_name: string | null; is_creator: boolean; created_at: string
}

export interface PaymentSheet {
  method: string; total: number; row_count: number
  rows: {
    card_id: string; full_name: string; account_name: string | null; bank_name: string | null; branch_name: string | null
    routing_number: string | null; account_number: string | null; wallet_provider: string | null
    wallet_number: string | null; amount: number
  }[]
}

export const RUN_STEPS: RunStatus[] = ['draft', 'calculated', 'reviewed', 'approved', 'paid', 'locked']
export const RUN_STATUS_LABEL: Record<RunStatus, string> = {
  draft: 'Draft', calculated: 'Calculated', reviewed: 'Reviewed', approved: 'Approved', paid: 'Paid', locked: 'Locked',
  cancelled: 'Cancelled',
}

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

export function usePayrollRuns() {
  return useQuery({ queryKey: ['payroll', 'runs'], queryFn: () => callRpc<PayrollRunSummary[]>('list_payroll_runs') })
}

export function usePayrollRun(runId: string | undefined) {
  return useQuery({
    queryKey: ['payroll', 'run', runId],
    enabled: !!runId,
    queryFn: () => callRpc<PayrollRunDetail>('get_payroll_run', { p_run_id: runId }),
  })
}

export function usePayslip(slipId: string | null) {
  return useQuery({
    queryKey: ['payroll', 'payslip', slipId],
    enabled: !!slipId,
    queryFn: () => callRpc<Payslip>('get_payslip', { p_slip_id: slipId }),
  })
}

export function useMyPayslips() {
  return useQuery({ queryKey: ['payroll', 'mine'], queryFn: () => callRpc<MyPayslipRow[]>('list_my_payslips') })
}

export function usePayrollAdjustments(status: string | null) {
  return useQuery({
    queryKey: ['payroll', 'adjustments', status],
    queryFn: () => callRpc<AdjustmentRow[]>('list_payroll_adjustments', { p_status: status }),
  })
}

/** Lifecycle or adjustment action; refreshes every payroll screen afterwards. */
export function usePayrollAction<TArgs extends Record<string, unknown>, TResult = unknown>(fn: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (args: TArgs) => callRpc<TResult>(fn, args),
    onSuccess: () => Promise.all([
      queryClient.invalidateQueries({ queryKey: ['payroll'] }),
      queryClient.invalidateQueries({ queryKey: ['compensation'] }),
    ]),
  })
}

export function fetchPaymentSheet(batchId: string) {
  return callRpc<PaymentSheet>('get_payment_sheet', { p_batch_id: batchId })
}

/** "2026-03-01" -> "March 2026" */
export function formatPeriod(periodMonth: string, locale: string = 'en-GB'): string {
  return new Date(`${periodMonth.slice(0, 10)}T00:00:00`).toLocaleDateString(locale, { month: 'long', year: 'numeric' })
}

/**
 * One CSV cell. Quotes when needed and neutralises spreadsheet formulas
 * (cells starting with = + - @ tab or CR), so an employee name can never run
 * as a formula when the sheet is opened in Excel.
 */
export function csvCell(value: unknown): string {
  if (value === null || value === undefined) return ''
  let text = String(value)
  if (typeof value === 'string' && /^[=+\-@\t\r]/.test(text)) text = `'${text}`
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text
}

export function toCsv(header: string[], rows: unknown[][]): string {
  return [header, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n')
}

/** Starts a browser download of text content (UTF-8 with BOM so Excel shows Bangla). */
export function downloadText(fileName: string, content: string, mime = 'text/csv') {
  const blob = new Blob(['﻿', content], { type: `${mime};charset=utf-8` })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}
