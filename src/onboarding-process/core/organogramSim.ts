// Organogram simulator for the demo: the same rules as the database, run in the browser.
// Mirrors private.sync_department_positions (planned slots, extras, after-separation),
// private.offer_budget_guard (an offer needs a free budget seat) and save_department_budget.
// Every action returns a new state, or an error and the old state.
import type { ChartGrade, ChartPosition, DepartmentCounts } from './organogram'
import { budgetError } from './organogram'

export interface SimEmployee { id: string; full_name: string; card_id: string; designation: string; join_date: string }
export interface SimGrade { id: string; code: string; name: string; rank: number; designation: string; slots: number }
export interface SimPosition { id: string; grade_id: string; kind: 'planned' | 'extra'; slot_no: number; hold: 'open' | 'blocked'; employee: SimEmployee | null }
/** Seats being recruited for a grade (an approved requisition), with how far hiring has got. */
export interface SimRecruitment { seats: number; stage: string; candidates: number }
export interface SimOffer { id: string; grade_id: string; name: string; status: 'sent' | 'accepted' }

export interface SimState {
  department: { id: string; name: string; head: string | null }
  budget: number
  after_separation: 'vacant' | 'blocked'
  grades: SimGrade[]
  positions: SimPosition[]
  recruitment: Record<string, SimRecruitment>
  offers: SimOffer[]
  seq: number
  names: string[]
}

export type SimResult = { state: SimState; error: string | null; note: string | null }

const ok = (state: SimState, note: string | null = null): SimResult => ({ state, error: null, note })
const fail = (state: SimState, error: string): SimResult => ({ state, error, note: null })

export function simCounts(s: SimState): DepartmentCounts {
  const filled = s.positions.filter((p) => p.employee).length
  const inProcess = s.offers.length
  const accepted = s.offers.filter((o) => o.status === 'accepted').length
  return { budget: s.budget, filled, offers_in_process: inProcess, offers_accepted: accepted,
    available: s.budget - filled - inProcess, headroom: s.budget - filled - accepted }
}

const byGrade = (s: SimState, gradeId: string, kind?: SimPosition['kind']) =>
  s.positions.filter((p) => p.grade_id === gradeId && (!kind || p.kind === kind)).sort((a, b) => a.slot_no - b.slot_no)
const isFree = (p: SimPosition) => p.kind === 'planned' && !p.employee && p.hold === 'open'
const nextExtraNo = (s: SimState, gradeId: string) => Math.max(0, ...byGrade(s, gradeId, 'extra').map((p) => p.slot_no)) + 1

/** Steps 2 and 3 of sync_department_positions: planned positions follow the slots; extras take free slots. */
export function syncPositions(input: SimState): SimState {
  const s: SimState = { ...input, positions: input.positions.map((p) => ({ ...p })) }
  for (const g of s.grades) {
    let planned = byGrade(s, g.id, 'planned')
    if (planned.length < g.slots) {
      const used = new Set(planned.map((p) => p.slot_no))
      for (let n = 1, add = g.slots - planned.length; add > 0; n++) {
        if (used.has(n)) continue
        s.positions.push({ id: `${g.id}-p${s.seq++}`, grade_id: g.id, kind: 'planned', slot_no: n, hold: 'open', employee: null })
        add--
      }
    } else if (planned.length > g.slots) {
      // Empty ones go first (highest slot first), then filled ones become extra.
      const drop = new Set(planned.filter((p) => !p.employee).reverse().slice(0, planned.length - g.slots).map((p) => p.id))
      s.positions = s.positions.filter((p) => !drop.has(p.id))
      planned = byGrade(s, g.id, 'planned')
      for (const p of planned.slice(g.slots).reverse()) {
        p.slot_no = nextExtraNo(s, g.id)
        p.kind = 'extra'
        p.hold = 'open'
      }
      byGrade(s, g.id, 'planned').forEach((p, i) => { p.slot_no = i + 1 })
    }
    for (const x of byGrade(s, g.id, 'extra')) {
      const free = byGrade(s, g.id, 'planned').find(isFree)
      if (!free) break
      free.employee = x.employee
      s.positions = s.positions.filter((p) => p.id !== x.id)
    }
  }
  return s
}

/** Same chart shape the database returns (get_department_organogram). */
export function simChart(s: SimState): { counts: DepartmentCounts; grades: ChartGrade[] } {
  const grades = [...s.grades].sort((a, b) => a.rank - b.rank).map((g): ChartGrade => {
    const rec = s.recruitment[g.id]
    let freeNo = 0
    const positions = [...byGrade(s, g.id, 'planned'), ...byGrade(s, g.id, 'extra')].map((p): ChartPosition => {
      const free = isFree(p)
      const recruiting = free && rec != null && ++freeNo <= rec.seats
      return {
        id: p.id, slot_no: p.slot_no, kind: p.kind, hold_state: p.hold,
        state: p.employee ? (p.kind === 'extra' ? 'extra' : 'filled') : p.hold === 'blocked' ? 'blocked' : recruiting ? 'in_recruitment' : 'vacant',
        employee: p.employee,
        recruitment: free && rec && rec.seats > 0
          ? { vacancy_id: `${g.id}-vac`, post_id: null, title: g.designation, candidates: rec.candidates, stage: rec.stage } : null,
      }
    })
    return { id: g.id, code: g.code, name: g.name, rank: g.rank, planned: g.slots, positions }
  })
  return { counts: simCounts(s), grades }
}

// ---------------------------------------------------------------------------- actions

/** save_department_budget: approved headcount, slots per grade, after-separation rule. */
export function applyBudget(s: SimState, approved: number, slots: Record<string, number>, after: SimState['after_separation']): SimResult {
  const c = simCounts(s)
  const err = budgetError(approved, s.grades.map((g) => slots[g.id] ?? g.slots), c)
  if (err) return fail(s, err)
  const next = syncPositions({ ...s, budget: approved, after_separation: after, grades: s.grades.map((g) => ({ ...g, slots: slots[g.id] ?? g.slots })) })
  return ok(next, 'Budget saved; positions redrawn.')
}

/** set_position_hold: only an empty planned slot can be blocked or opened. */
export function toggleHold(s: SimState, positionId: string): SimResult {
  const p = s.positions.find((x) => x.id === positionId)
  if (!p || p.employee || p.kind !== 'planned') return fail(s, 'Only an empty planned slot can be blocked or opened')
  const hold = p.hold === 'blocked' ? 'open' : 'blocked'
  const next = syncPositions({ ...s, positions: s.positions.map((x) => (x.id === positionId ? { ...x, hold } : x)) })
  return ok(next, hold === 'blocked' ? 'Slot blocked: nobody can be hired against it.' : 'Slot opened for hiring.')
}

/** An approved requisition for one more seat of the grade (R1 vacancy). */
export function startRecruiting(s: SimState, gradeId: string): SimResult {
  const rec = s.recruitment[gradeId]
  const free = byGrade(s, gradeId, 'planned').filter(isFree).length
  if ((rec?.seats ?? 0) >= free) return fail(s, 'Every open slot of this grade is already being recruited. Add a slot or open a blocked one first.')
  return ok({ ...s, recruitment: { ...s.recruitment, [gradeId]: { seats: (rec?.seats ?? 0) + 1, stage: rec?.stage ?? 'Applications open', candidates: rec?.candidates ?? 0 } } },
    'Vacancy approved: the slot is now in recruitment.')
}

/** offer_budget_guard: an offer counts against the budget from the moment it exists. */
export function sendOffer(s: SimState, gradeId: string): SimResult {
  const c = simCounts(s)
  if ((c.available ?? 0) < 1) {
    return fail(s, `Headcount budget is full: ${c.budget} approved, ${c.filled} filled, ${c.offers_in_process} offer(s) in process. Raise the budget or free a seat first.`)
  }
  const name = s.names[s.seq % s.names.length]
  const rec = s.recruitment[gradeId]
  return ok({ ...s, seq: s.seq + 1, offers: [...s.offers, { id: `offer-${s.seq}`, grade_id: gradeId, name, status: 'sent' }],
    recruitment: rec ? { ...s.recruitment, [gradeId]: { ...rec, stage: 'Offer' } } : s.recruitment }, `Offer sent to ${name}.`)
}

export function acceptOffer(s: SimState, offerId: string): SimResult {
  return ok({ ...s, offers: s.offers.map((o) => (o.id === offerId ? { ...o, status: 'accepted' } : o)) }, 'Offer accepted; the seat is held.')
}

export function dropOffer(s: SimState, offerId: string): SimResult {
  return ok({ ...s, offers: s.offers.filter((o) => o.id !== offerId) }, 'Offer declined; its budget seat is free again.')
}

/** convert_to_employee: the candidate joins. A free open slot of the grade, else an extra position. */
export function joinOffer(s: SimState, offerId: string, today = '2026-10-25'): SimResult {
  const o = s.offers.find((x) => x.id === offerId)
  if (!o) return fail(s, 'Offer not found')
  const g = s.grades.find((x) => x.id === o.grade_id)!
  const emp: SimEmployee = { id: `sim-emp-${s.seq}`, full_name: o.name, card_id: `EMP${3000 + s.seq}`, designation: g.designation, join_date: today }
  const positions = s.positions.map((p) => ({ ...p }))
  const free = positions.filter((p) => p.grade_id === g.id).sort((a, b) => a.slot_no - b.slot_no).find(isFree)
  const base = { ...s, positions }
  if (free) free.employee = emp
  else positions.push({ id: `${g.id}-x${s.seq}`, grade_id: g.id, kind: 'extra', slot_no: nextExtraNo(base, g.id), hold: 'open', employee: emp })
  const rec = s.recruitment[g.id]
  const recruitment = { ...s.recruitment }
  if (rec && rec.seats > 0) {
    if (rec.seats === 1) delete recruitment[g.id]
    else recruitment[g.id] = { ...rec, seats: rec.seats - 1 }
  }
  return ok({ ...base, seq: s.seq + 1, recruitment, offers: s.offers.filter((x) => x.id !== offerId) },
    free ? `${o.name} joined into ${g.name} slot ${free.slot_no}.` : `${o.name} joined above the ${g.slots} planned ${g.name} slot(s): an extra position.`)
}

/** Separation (step 1 of the sync): a planned slot takes the after-separation state; an extra goes away. */
export function leave(s: SimState, positionId: string): SimResult {
  const p = s.positions.find((x) => x.id === positionId)
  if (!p?.employee) return fail(s, 'Nobody sits in this position')
  const who = p.employee.full_name
  const positions = p.kind === 'extra'
    ? s.positions.filter((x) => x.id !== positionId)
    : s.positions.map((x) => (x.id === positionId ? { ...x, employee: null, hold: s.after_separation === 'blocked' ? 'blocked' as const : 'open' as const } : x))
  const next = syncPositions({ ...s, positions })
  return ok(next, p.kind === 'extra' ? `${who} left; the extra position is gone.`
    : s.after_separation === 'blocked' ? `${who} left; the slot is blocked (this department's rule).` : `${who} left; the slot is vacant again.`)
}

// ---------------------------------------------------------------------------- seeding

export type SeedCell = 'filled' | 'blocked' | 'vacant' | 'recruiting'
export interface SeedGrade extends Omit<SimGrade, 'slots'> { slots: number; cells: SeedCell[]; extras?: number; stage?: string; candidates?: number }

/** Builds a state from a compact description: one cell per planned slot, plus extra people. */
export function seedState(p: { department: SimState['department']; budget: number; after_separation: SimState['after_separation']; names: string[];
  grades: SeedGrade[]; offers?: { code: string; status: SimOffer['status'] }[]; joinYear?: number }): SimState {
  let n = 0
  const person = (designation: string): SimEmployee => {
    const i = n++
    return { id: `demo-emp-${p.department.id}-${i}`, full_name: p.names[i % p.names.length], card_id: `EMP${2600 + i}`, designation,
      join_date: `${(p.joinYear ?? 2016) + (i % 9)}-0${(i % 9) + 1}-01` }
  }
  const positions: SimPosition[] = []
  const recruitment: Record<string, SimRecruitment> = {}
  for (const g of p.grades) {
    g.cells.forEach((c, i) => positions.push({ id: `${g.id}-p${i + 1}`, grade_id: g.id, kind: 'planned', slot_no: i + 1,
      hold: c === 'blocked' ? 'blocked' : 'open', employee: c === 'filled' ? person(g.designation) : null }))
    for (let x = 1; x <= (g.extras ?? 0); x++) {
      positions.push({ id: `${g.id}-x${x}`, grade_id: g.id, kind: 'extra', slot_no: x, hold: 'open', employee: person(g.designation) })
    }
    const seats = g.cells.filter((c) => c === 'recruiting').length
    if (seats) recruitment[g.id] = { seats, stage: g.stage ?? 'Applications open', candidates: g.candidates ?? 0 }
  }
  const grades = p.grades.map(({ cells: _c, extras: _x, stage: _s, candidates: _n, ...g }) => g)
  const offers = (p.offers ?? []).map((o, i): SimOffer => ({ id: `offer-seed-${i}`, grade_id: grades.find((g) => g.code === o.code)!.id,
    name: p.names[(n + i) % p.names.length], status: o.status }))
  return { department: p.department, budget: p.budget, after_separation: p.after_separation, grades, positions, recruitment, offers,
    seq: n + offers.length, names: p.names }
}
