// Text for every (?) tooltip on the workforce screens: the formula, the same
// formula with this month's numbers filled in, and the reference keys
// (statutory_references, area "workforce") that say where the rule comes from.
import type { SnapshotFigures, WorkloadFigures, WorkloadInputRow, WorkloadMethod } from './types'
import { METHOD_LABEL } from './workload'

export interface Explanation { title: string; formula: string; working: string; references: string[] }

export type ExplainKey =
  | 'demand' | 'capacity' | 'index' | 'required' | 'gap' | 'vacancy' | 'backfill' | 'new_positions'
  | 'hold' | 'budget' | 'attrition' | 'band'

/** Figures plus whatever facts are known (snapshots know them all, the demo knows the method inputs). */
export type ExplainSource = WorkloadFigures & Partial<Pick<SnapshotFigures,
  'method' | 'availability' | 'capacity_hours_setting' | 'availability_source' | 'regular_hours' | 'overtime_hours'
  | 'org_headcount' | 'per_employees' | 'department_payroll' | 'monthly_budget'>> & { inputs?: WorkloadInputRow[] }

const num = (value: number | null | undefined, digits = 2) =>
  value === null || value === undefined ? '—' : value.toLocaleString('en-US', { maximumFractionDigits: digits })
const taka = (value: number | null | undefined) => (value === null || value === undefined ? 'hidden' : `Tk ${num(value)}`)

function demandWorking(f: ExplainSource): { formula: string; working: string; references: string[] } {
  const method: WorkloadMethod = f.method ?? 'hours'
  if (method === 'output_smv' || method === 'volume_std') {
    const rows = f.inputs ?? []
    const minutes = rows.length
      ? rows.map((r) => `${num(r.quantity)} × ${num(r.std_minutes, 3)}`).join(' + ')
      : 'no figures entered'
    return {
      formula: method === 'output_smv' ? 'Σ (pieces × SMV minutes) ÷ 60' : 'Σ (count × standard minutes) ÷ 60',
      working: `(${minutes}) ÷ 60 = ${num(f.demand_hours)} h`,
      references: [method === 'output_smv' ? 'workforce.smv' : 'workforce.standard_time'],
    }
  }
  if (method === 'ratio') {
    return {
      formula: '(organization employees ÷ people served per person) × capacity per person',
      working: `(${num(f.org_headcount)} ÷ ${num(f.per_employees)}) × ${num(f.capacity_per_fte)} = ${num(f.demand_hours)} h`,
      references: ['workforce.staffing_ratio'],
    }
  }
  return {
    formula: 'regular worked hours + approved overtime hours (pending or rejected OT not counted)',
    working: f.regular_hours !== undefined
      ? `${num(f.regular_hours)} + ${num(f.overtime_hours)} = ${num(f.demand_hours)} h`
      : `${num(f.demand_hours)} h`,
    references: ['workforce.capacity'],
  }
}

export function explain(key: ExplainKey, f: ExplainSource): Explanation {
  switch (key) {
    case 'demand': {
      const d = demandWorking(f)
      return { title: `Demand hours · ${METHOD_LABEL[f.method ?? 'hours']}`, ...d }
    }
    case 'capacity':
      return {
        title: 'Capacity per person',
        formula: 'monthly hours × availability',
        working: f.capacity_hours_setting !== undefined
          ? `${num(f.capacity_hours_setting)} × ${num(f.availability, 4)} = ${num(f.capacity_per_fte)} h` +
            (f.availability_source === 'attendance' ? ' (availability from the last 3 months of attendance)' : ' (fixed availability)')
          : `${num(f.capacity_per_fte)} h per person`,
        references: ['workforce.capacity'],
      }
    case 'index':
      return {
        title: 'Workload index',
        formula: 'demand hours ÷ (active people × capacity per person)',
        working: f.index === null
          ? `${num(f.demand_hours)} h of work and nobody in the department`
          : `${num(f.demand_hours)} ÷ (${f.active} × ${num(f.capacity_per_fte)}) = ${num(f.index, 3)}`,
        references: ['workforce.index'],
      }
    case 'band':
      return {
        title: 'Band and the overload rule',
        formula: `≥ ${f.bands.critical} critical · ≥ ${f.bands.overload} overload · > ${f.bands.watch} watch · ≥ ${f.bands.underload} balanced · below underloaded. ` +
          `New positions: overload ${f.bands.sustain_months} months in a row, or critical once.`,
        working: `Index ${num(f.index, 3)} → ${f.band}; overload months in a row: ${f.overload_months}` +
          ` → rule ${f.overload_rule ? 'met' : 'not met'}`,
        references: ['workforce.index'],
      }
    case 'required':
      return {
        title: 'People needed',
        formula: 'demand hours ÷ capacity per person',
        working: `${num(f.demand_hours)} ÷ ${num(f.capacity_per_fte)} = ${num(f.required_fte)}`,
        references: ['workforce.index'],
      }
    case 'gap':
      return {
        title: 'Gap',
        formula: 'people needed − active people',
        working: `${num(f.required_fte)} − ${f.active} = ${num(f.gap)}`,
        references: ['workforce.index'],
      }
    case 'vacancy':
      return {
        title: 'Vacancy',
        formula: 'sanctioned positions − active people (not below 0); rate = vacancy ÷ sanctioned × 100',
        working: `${f.sanctioned} − ${f.active} = ${f.vacancy}` + (f.vacancy_rate !== null ? ` (${num(f.vacancy_rate, 1)} %)` : ''),
        references: ['workforce.vacancy_rate'],
      }
    case 'backfill':
      return {
        title: 'Backfill (inside the sanction)',
        formula: 'min(vacancy, ⌈gap⌉) when both are above 0',
        working: f.vacancy > 0 && f.gap > 0
          ? `min(${f.vacancy}, ⌈${num(f.gap)}⌉ = ${Math.ceil(f.gap)}) = ${f.backfill_seats}`
          : `vacancy ${f.vacancy}, gap ${num(f.gap)} → 0`,
        references: ['workforce.vacancy_rate', 'workforce.index'],
      }
    case 'new_positions':
      return {
        title: 'New positions (raise the sanction)',
        formula: 'when the overload rule is met: ⌈people needed⌉ − sanctioned',
        working: f.overload_rule
          ? `⌈${num(f.required_fte)}⌉ − ${f.sanctioned} = ${f.new_positions}`
          : 'overload rule not met → 0',
        references: ['workforce.index'],
      }
    case 'hold':
      return {
        title: 'Vacancies kept on hold',
        formula: 'vacancy − backfill seats',
        working: `${f.vacancy} − ${f.backfill_seats} = ${f.hold_seats}`,
        references: ['workforce.vacancy_rate'],
      }
    case 'budget':
      return {
        title: 'Budget check',
        formula: 'seats that fit = ⌊remaining budget ÷ cost per seat⌋; remaining = monthly budget − department gross pay',
        working: f.budget_status === 'unknown'
          ? 'No budget set (or no pay on record) → not checked'
          : `${taka(f.monthly_budget ?? null)} − ${taka(f.department_payroll ?? null)} = ${taka(f.budget_remaining)}; ` +
            `÷ ${taka(f.cost_per_seat)} → ${f.budget_ok_seats} of ${f.seats_total} seat(s) fit`,
        references: ['workforce.budget'],
      }
    case 'attrition':
      return {
        title: 'Attrition (last 3 months)',
        formula: 'people who left ÷ average headcount × 100',
        working: f.attrition_percent === null
          ? 'No headcount in the period'
          : `${f.separations} ÷ ${num(f.avg_headcount)} × 100 = ${num(f.attrition_percent, 1)} %` +
            (f.attrition_flag ? ` (above ${f.bands.attrition_flag_percent} %: check exit reasons)` : ''),
        references: ['workforce.attrition'],
      }
  }
}
