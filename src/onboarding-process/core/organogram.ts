// Department organogram: position states, their look, the numbers and the tree layout.
// States are computed in the database (get_department_organogram); this file decides how
// they are shown and checks the budget form like save_department_budget does.

export type PositionState = 'filled' | 'vacant' | 'in_recruitment' | 'blocked' | 'extra'

export const STATE_META: Record<PositionState, { label: string; card: string; badge: string }> = {
  filled: { label: 'Filled', card: 'border-green-300 bg-green-50', badge: 'bg-green-100 text-green-800' },
  extra: { label: 'Extra', card: 'border-green-400 border-dashed bg-green-50', badge: 'bg-green-200 text-green-900' },
  vacant: { label: 'Vacant', card: 'border-amber-300 bg-amber-50', badge: 'bg-amber-100 text-amber-800' },
  in_recruitment: { label: 'In recruitment', card: 'border-sky-300 bg-sky-50', badge: 'bg-sky-100 text-sky-800' },
  blocked: { label: 'Blocked', card: 'border-slate-300 border-dashed bg-slate-100 text-slate-500', badge: 'bg-slate-200 text-slate-600' },
}

export const STATE_ORDER: PositionState[] = ['filled', 'extra', 'in_recruitment', 'vacant', 'blocked']

export interface ChartPosition {
  id: string; slot_no: number; kind: 'planned' | 'extra'; hold_state: 'open' | 'blocked'; state: PositionState
  employee: { id: string; full_name: string; card_id: string; designation: string | null; join_date: string } | null
  recruitment: { vacancy_id: string; post_id: string | null; title: string | null; candidates: number; stage: string } | null
}
export interface ChartGrade { id: string; code: string; name: string; rank: number; planned: number; positions: ChartPosition[] }

export interface DepartmentCounts {
  budget: number | null; filled: number; offers_in_process: number; offers_accepted: number
  available: number | null; headroom: number | null
}

/** Count of positions per state across the chart. */
export function stateCounts(grades: ChartGrade[]): Record<PositionState, number> {
  const out: Record<PositionState, number> = { filled: 0, extra: 0, vacant: 0, in_recruitment: 0, blocked: 0 }
  for (const g of grades) for (const p of g.positions) out[p.state] += 1
  return out
}

/** Grades that have something to show, top first (rank 1 = top). */
export function chartLevels(grades: ChartGrade[]): ChartGrade[] {
  return [...grades].filter((g) => g.positions.length > 0 || g.planned > 0).sort((a, b) => a.rank - b.rank || a.name.localeCompare(b.name))
}

/** Same checks as save_department_budget: slots ≤ budget, budget ≥ filled + offers in process. */
export function budgetError(approved: number, slots: number[], counts: Pick<DepartmentCounts, 'filled' | 'offers_in_process'>): string | null {
  if (!Number.isInteger(approved) || approved < 0) return 'Enter the approved headcount (0 or more)'
  if (slots.some((s) => !Number.isInteger(s) || s < 0)) return 'Slots per grade are whole numbers from 0'
  const total = slots.reduce((a, b) => a + b, 0)
  if (total > approved) return `The grade slots add up to ${total}, more than the approved headcount of ${approved}`
  const floor = counts.filled + counts.offers_in_process
  if (approved < floor) return `The budget cannot go below ${counts.filled} filled + ${counts.offers_in_process} offer(s) in process`
  return null
}

/** Short sentence about the budget for the header. */
export function budgetSentence(c: DepartmentCounts): string {
  if (c.budget == null) return 'No headcount budget set yet.'
  const parts = [`${c.filled} of ${c.budget} filled`]
  if (c.offers_in_process) parts.push(`${c.offers_in_process} offer${c.offers_in_process === 1 ? '' : 's'} in process`)
  parts.push(c.available != null && c.available > 0 ? `${c.available} seat${c.available === 1 ? '' : 's'} free to hire` : 'budget full')
  return parts.join(' · ')
}
