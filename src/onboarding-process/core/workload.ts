// Workload calculation — the TypeScript mirror of private.workload_figures
// (supabase/migrations/20261025000100_recruit_r1_workforce.sql). The database
// stays the authority; this copy powers the demo cases, live previews while
// typing, and the vitest golden tests that must match the SQL test numbers.
import type { Band, Bands, WorkloadAction, WorkloadFigures, WorkloadInput, WorkloadInputRow, WorkloadMethod } from './types'

export const DEFAULT_BANDS: Bands = {
  underload: 0.85, watch: 1.0, overload: 1.1, critical: 1.25, sustain_months: 2, attrition_flag_percent: 20,
}

/** Round half away from zero, like Postgres round(numeric, n). */
export function roundTo(value: number, digits: number): number {
  const sign = value < 0 ? -1 : 1
  const shifted = Math.round(Number(`${Math.abs(value)}e${digits}`))
  return sign * Number(`${shifted}e-${digits}`)
}

export function workloadFigures(input: WorkloadInput): WorkloadFigures {
  const bands = input.bands ?? DEFAULT_BANDS
  const demand = roundTo(input.demand_hours || 0, 2)
  const capacity = input.capacity_per_fte
  if (!(capacity > 0)) throw new Error('Capacity per person must be above zero')
  const active = input.active || 0
  const sanctioned = input.sanctioned || 0
  const separations = input.separations ?? 0
  const avg = input.avg_headcount ?? null

  const required = roundTo(demand / capacity, 2)
  const gap = roundTo(required - active, 2)
  const index = active > 0 ? roundTo(demand / (active * capacity), 3) : null
  const vacancy = Math.max(sanctioned - active, 0)
  const band: Band =
    index === null ? (demand > 0 ? 'critical' : 'balanced')
      : index >= bands.critical ? 'critical'
        : index >= bands.overload ? 'overload'
          : index > bands.watch ? 'watch'
            : index >= bands.underload ? 'balanced'
              : 'underloaded'
  const overloadMonths = band === 'overload' || band === 'critical' ? (input.prior_overload_months ?? 0) + 1 : 0
  const overloadRule = band === 'critical' || (band === 'overload' && overloadMonths >= bands.sustain_months)
  const backfill = vacancy > 0 && gap > 0 ? Math.min(vacancy, Math.ceil(gap)) : 0
  const newPositions = overloadRule ? Math.max(Math.ceil(required) - sanctioned, 0) : 0
  const hold = vacancy - backfill
  const total = backfill + newPositions

  const cost = input.cost_per_seat ?? null
  const budgetLeft = input.budget_remaining ?? null
  let ok = total
  let budgetStatus: WorkloadFigures['budget_status'] = 'unknown'
  if (cost !== null && cost > 0 && budgetLeft !== null) {
    ok = Math.min(total, Math.max(Math.floor(budgetLeft / cost), 0))
    budgetStatus = ok < total ? 'blocked' : 'ok'
  }
  const okBackfill = Math.min(backfill, ok)
  const attrition = avg !== null && avg > 0 ? roundTo((separations / avg) * 100, 1) : null
  const action: WorkloadAction =
    total > 0 ? 'hire'
      : band === 'watch' || band === 'overload' || band === 'critical' ? 'watch'
        : hold > 0 ? 'hold'
          : band === 'underloaded' ? 'underloaded'
            : 'balanced'

  return {
    demand_hours: demand, capacity_per_fte: capacity, capacity_hours: roundTo(active * capacity, 2),
    active, sanctioned, vacancy, vacancy_rate: sanctioned > 0 ? roundTo((vacancy / sanctioned) * 100, 1) : null,
    required_fte: required, gap, index, band, overload_months: overloadMonths, overload_rule: overloadRule,
    backfill_seats: backfill, new_positions: newPositions, hold_seats: hold, seats_total: total,
    budget_status: budgetStatus, budget_ok_seats: ok, budget_ok_backfill: okBackfill, budget_ok_new: ok - okBackfill,
    budget_blocked_seats: total - ok, cost_per_seat: cost, budget_remaining: budgetLeft,
    separations, avg_headcount: avg, attrition_percent: attrition,
    attrition_flag: attrition !== null && attrition > bands.attrition_flag_percent,
    action, bands,
  }
}

/** Demand hours from output / volume rows: Σ quantity × minutes ÷ 60. */
export function inputHours(rows: Pick<WorkloadInputRow, 'quantity' | 'std_minutes'>[]): number {
  return roundTo(rows.reduce((sum, row) => sum + (Number(row.quantity) || 0) * (Number(row.std_minutes) || 0), 0) / 60, 2)
}

/** Demand hours for the ratio method: (org employees ÷ ratio) × capacity per person. */
export function ratioHours(orgHeadcount: number, perEmployees: number, capacityPerFte: number): number {
  return roundTo((orgHeadcount / perEmployees) * capacityPerFte, 2)
}

/** Capacity per person = monthly hours × availability. */
export function capacityPerFte(capacityHours: number, availability: number): number {
  return roundTo(capacityHours * availability, 2)
}

export const METHOD_LABEL: Record<WorkloadMethod, string> = {
  hours: 'Worked hours + approved OT',
  output_smv: 'Output × SMV',
  volume_std: 'Volume × standard time',
  ratio: 'Staffing ratio',
}

export const BAND_LABEL: Record<Band, string> = {
  critical: 'Critical', overload: 'Overload', watch: 'Watch', balanced: 'Balanced', underloaded: 'Underloaded',
}

export const ACTION_LABEL: Record<WorkloadAction, string> = {
  hire: 'Hire', watch: 'Watch', hold: 'Hold vacancies', underloaded: 'Underloaded', balanced: 'Balanced',
}

/** Plain-language one-liner for a department's suggestion. */
export function suggestionText(f: WorkloadFigures): string {
  const parts: string[] = []
  if (f.backfill_seats > 0) parts.push(`backfill ${f.backfill_seats}`)
  if (f.new_positions > 0) parts.push(`${f.new_positions} new position${f.new_positions > 1 ? 's' : ''} (raises the sanction)`)
  if (f.hold_seats > 0) parts.push(`${f.hold_seats} vacanc${f.hold_seats > 1 ? 'ies' : 'y'} on hold`)
  if (f.budget_blocked_seats > 0) parts.push(`${f.budget_blocked_seats} over budget`)
  if (parts.length) return parts.join(' · ')
  if (f.action === 'watch') {
    return f.band === 'watch' ? 'Watch: slightly above capacity'
      : `Watch: overload for ${f.overload_months} of ${f.bands.sustain_months} months needed`
  }
  if (f.action === 'underloaded') return 'Underloaded: capacity is higher than the work'
  return 'Balanced: no change needed'
}
