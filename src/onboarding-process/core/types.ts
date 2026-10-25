// Shared types of the onboarding-process module (R1: workforce planning).
// Field names match the JSON the database returns (snake_case).

export type WorkloadMethod = 'hours' | 'output_smv' | 'volume_std' | 'ratio'
export type Band = 'critical' | 'overload' | 'watch' | 'balanced' | 'underloaded'
export type WorkloadAction = 'hire' | 'watch' | 'hold' | 'underloaded' | 'balanced'
export type BudgetStatus = 'ok' | 'blocked' | 'unknown'

export interface Bands {
  underload: number; watch: number; overload: number; critical: number
  sustain_months: number; attrition_flag_percent: number
}

/** Inputs of the pure calculation (private.workload_figures). */
export interface WorkloadInput {
  demand_hours: number
  capacity_per_fte: number
  active: number
  sanctioned: number
  separations?: number
  avg_headcount?: number | null
  prior_overload_months?: number
  cost_per_seat?: number | null
  budget_remaining?: number | null
  bands?: Bands
}

/** Output of the calculation; snapshots add the facts they were built from. */
export interface WorkloadFigures {
  demand_hours: number; capacity_per_fte: number; capacity_hours: number
  active: number; sanctioned: number; vacancy: number; vacancy_rate: number | null
  required_fte: number; gap: number; index: number | null; band: Band
  overload_months: number; overload_rule: boolean
  backfill_seats: number; new_positions: number; hold_seats: number; seats_total: number
  budget_status: BudgetStatus; budget_ok_seats: number; budget_ok_backfill: number; budget_ok_new: number
  budget_blocked_seats: number
  /** Hidden from roles without compensation.view. */
  cost_per_seat?: number | null
  budget_remaining?: number | null
  separations: number; avg_headcount: number | null; attrition_percent: number | null; attrition_flag: boolean
  action: WorkloadAction
  bands: Bands
}

export interface SnapshotFigures extends WorkloadFigures {
  period_month: string; method: WorkloadMethod; availability: number
  capacity_hours_setting: number; availability_source: 'attendance' | 'fixed'
  scheduled_workdays: number | null; lost_workdays: number | null
  regular_hours: number; overtime_hours: number
  org_headcount: number; per_employees: number | null
  monthly_budget?: number | null; department_payroll?: number | null
  built_at?: string
}

export interface WorkloadInputRow { metric_key: string; label: string | null; quantity: number; std_minutes: number; source?: 'manual' | 'csv' }

export interface WorkforceSettings {
  capacity_hours: number; availability_source: 'attendance' | 'fixed'; fixed_availability_percent: number
  band_underload: number; band_watch: number; band_overload: number; band_critical: number
  sustain_months: number; attrition_flag_percent: number; confirmed_at: string | null
}

export interface PlanRow {
  designation_id: string; designation_name: string; grade_code: string
  sanctioned: number; planned: boolean; active: number
}

export interface DepartmentWorkforce {
  id: string; name: string; method: WorkloadMethod; per_employees: number | null; monthly_budget?: number | null
  plan: PlanRow[]; inputs: WorkloadInputRow[]; snapshot: SnapshotFigures | null
  trend: { period_month: string; index: number | null; band: Band }[]
  open_seats: number
}

export interface WorkforceDashboard {
  period_month: string
  settings: WorkforceSettings | null
  can: { manage: boolean; headcount: boolean; request: boolean; review: boolean; approve: boolean; money: boolean }
  departments: DepartmentWorkforce[]
}

export type VacancyStatus = 'draft' | 'hr_reviewed' | 'approved' | 'on_hold' | 'rejected' | 'cancelled' | 'filled'
export type VacancyReason = 'replacement' | 'new_position'

export interface VacancyEvent { event: string; from_status: string | null; to_status: string | null; note: string | null; actor_name: string | null; created_at: string }

export interface Vacancy {
  id: string; department_id: string; department_name: string; designation_id: string; designation_name: string
  grade_code: string; office_name: string | null; seats: number; reason: VacancyReason
  origin: 'separation' | 'snapshot' | 'manual'; separated_employee_name: string | null; period_month: string | null
  estimated_monthly_cost?: number | null; budget_status: BudgetStatus
  recommendation: SnapshotFigures | null; latest_snapshot: SnapshotFigures | null
  note: string | null; status: VacancyStatus; decision_note: string | null; created_at: string
  drafted_by_name: string | null; hr_reviewed_by: string | null; hr_reviewed_by_name: string | null
  hr_reviewed_at: string | null; decided_by_name: string | null; decided_at: string | null
  events: VacancyEvent[]
}
