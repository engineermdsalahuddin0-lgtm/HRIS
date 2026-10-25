// The 10 demo cases (architecture.md §6.7). Each one exercises a different
// outcome of the rules. The same numbers are asserted in
// supabase/tests/recruit_r1_workforce_test.sql and in the vitest suite.
import type { WorkloadAction, WorkloadInput, WorkloadInputRow, WorkloadMethod, Band } from '../core/types'
import { inputHours, ratioHours } from '../core/workload'

export const DEMO_CAPACITY = 200

export interface DemoCase {
  id: number
  department: string
  method: WorkloadMethod
  /** What the department enters (output / volume methods). */
  inputs?: WorkloadInputRow[]
  /** Hours method: regular worked hours and approved OT. */
  hours?: { regular: number; overtime: number }
  /** Ratio method. */
  ratio?: { orgHeadcount: number; perEmployees: number }
  active: number
  sanctioned: number
  separations: number
  avgHeadcount: number | null
  priorOverloadMonths: number
  /** Budget case: remaining = monthly budget − department gross pay; a seat costs the average gross. */
  budget?: { monthly: number; payroll: number; costPerSeat: number }
  story: string
  expected: {
    index: number; band: Band; required: number; gap: number
    backfill: number; newPositions: number; hold: number; budgetBlocked: number; action: WorkloadAction
  }
}

export const DEMO_CASES: DemoCase[] = [
  {
    id: 1, department: 'Sewing Line 1', method: 'output_smv',
    inputs: [{ metric_key: 'POLO-26', label: 'Polo shirt', quantity: 54000, std_minutes: 12 }],
    active: 50, sanctioned: 55, separations: 3, avgHeadcount: 52, priorOverloadMonths: 0,
    story: '5 operators short, but the work needs only 4 more: backfill 4, keep 1 on hold.',
    expected: { index: 1.08, band: 'watch', required: 54, gap: 4, backfill: 4, newPositions: 0, hold: 1, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 2, department: 'Cutting', method: 'output_smv',
    inputs: [{ metric_key: 'POLO-26', label: 'Polo shirt panels', quantity: 120000, std_minutes: 1.2 }],
    active: 10, sanctioned: 10, separations: 0, avgHeadcount: 10, priorOverloadMonths: 1,
    story: 'No vacancy, but overloaded for the 2nd month in a row: 2 new positions for the Admin to approve.',
    expected: { index: 1.2, band: 'overload', required: 12, gap: 2, backfill: 0, newPositions: 2, hold: 0, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 3, department: 'Quality', method: 'hours', hours: { regular: 3000, overtime: 150 },
    active: 15, sanctioned: 16, separations: 1, avgHeadcount: 15.67, priorOverloadMonths: 0,
    story: 'Slightly above capacity and one person left: backfill 1.',
    expected: { index: 1.05, band: 'watch', required: 15.75, gap: 0.75, backfill: 1, newPositions: 0, hold: 0, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 4, department: 'Finishing', method: 'hours', hours: { regular: 4200, overtime: 0 },
    active: 25, sanctioned: 27, separations: 2, avgHeadcount: 26, priorOverloadMonths: 0,
    story: 'Two people left, yet the team has spare capacity: keep both vacancies on hold and save the cost.',
    expected: { index: 0.84, band: 'underloaded', required: 21, gap: -4, backfill: 0, newPositions: 0, hold: 2, budgetBlocked: 0, action: 'hold' },
  },
  {
    id: 5, department: 'Accounts', method: 'volume_std',
    inputs: [
      { metric_key: 'voucher', label: 'Vouchers posted', quantity: 6000, std_minutes: 15 },
      { metric_key: 'month-close', label: 'Month-close (hours)', quantity: 300, std_minutes: 60 },
    ],
    active: 8, sanctioned: 9, separations: 1, avgHeadcount: 8.33, priorOverloadMonths: 1,
    story: 'A Senior Executive resigned: backfill 1 (the job post fills itself from the designation profile).',
    expected: { index: 1.125, band: 'overload', required: 9, gap: 1, backfill: 1, newPositions: 0, hold: 0, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 6, department: 'HR & Admin', method: 'ratio', ratio: { orgHeadcount: 850, perEmployees: 100 },
    active: 6, sanctioned: 8, separations: 1, avgHeadcount: 6.33, priorOverloadMonths: 0,
    story: '850 employees at 1 HR per 100 need 8.5 people: backfill 2 and 1 new position.',
    expected: { index: 1.417, band: 'critical', required: 8.5, gap: 2.5, backfill: 2, newPositions: 1, hold: 0, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 7, department: 'Sales', method: 'hours', hours: { regular: 2400, overtime: 240 },
    active: 12, sanctioned: 12, separations: 0, avgHeadcount: 12, priorOverloadMonths: 0,
    story: 'Overload for the first month only (for example, before Eid): watch, no hiring yet.',
    expected: { index: 1.1, band: 'overload', required: 13.2, gap: 1.2, backfill: 0, newPositions: 0, hold: 0, budgetBlocked: 0, action: 'watch' },
  },
  {
    id: 8, department: 'Customer Service', method: 'volume_std',
    inputs: [
      { metric_key: 'call', label: 'Calls answered', quantity: 9000, std_minutes: 6 },
      { metric_key: 'ticket', label: 'Tickets closed', quantity: 3000, std_minutes: 12 },
    ],
    active: 6, sanctioned: 8, separations: 2, avgHeadcount: 7, priorOverloadMonths: 0,
    story: 'Critical load and 28.6 % attrition: backfill 2 and check why people leave.',
    expected: { index: 1.25, band: 'critical', required: 7.5, gap: 1.5, backfill: 2, newPositions: 0, hold: 0, budgetBlocked: 0, action: 'hire' },
  },
  {
    id: 9, department: 'IT', method: 'hours', hours: { regular: 1000, overtime: 0 },
    active: 5, sanctioned: 5, separations: 0, avgHeadcount: 5, priorOverloadMonths: 0,
    story: 'Work equals capacity: nothing to do.',
    expected: { index: 1, band: 'balanced', required: 5, gap: 0, backfill: 0, newPositions: 0, hold: 0, budgetBlocked: 0, action: 'balanced' },
  },
  {
    id: 10, department: 'Store / Warehouse', method: 'volume_std',
    inputs: [
      { metric_key: 'grn-line', label: 'Goods received lines', quantity: 8400, std_minutes: 10 },
      { metric_key: 'issue-line', label: 'Issue lines', quantity: 6000, std_minutes: 10 },
    ],
    active: 10, sanctioned: 12, separations: 2, avgHeadcount: 11, priorOverloadMonths: 1,
    budget: { monthly: 205000, payroll: 180000, costPerSeat: 18000 },
    story: 'Two seats needed but the budget fits one: 1 approved, 1 budget blocked (compare with the OT cost).',
    expected: { index: 1.2, band: 'overload', required: 12, gap: 2, backfill: 2, newPositions: 0, hold: 0, budgetBlocked: 1, action: 'hire' },
  },
]

export function demoDemandHours(demo: DemoCase): number {
  if (demo.inputs) return inputHours(demo.inputs)
  if (demo.ratio) return ratioHours(demo.ratio.orgHeadcount, demo.ratio.perEmployees, DEMO_CAPACITY)
  return (demo.hours?.regular ?? 0) + (demo.hours?.overtime ?? 0)
}

export function demoInput(demo: DemoCase): WorkloadInput {
  return {
    demand_hours: demoDemandHours(demo), capacity_per_fte: DEMO_CAPACITY, active: demo.active,
    sanctioned: demo.sanctioned, separations: demo.separations, avg_headcount: demo.avgHeadcount,
    prior_overload_months: demo.priorOverloadMonths, cost_per_seat: demo.budget?.costPerSeat ?? null,
    budget_remaining: demo.budget ? demo.budget.monthly - demo.budget.payroll : null,
  }
}
