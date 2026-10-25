// Demo organograms (browser only, never stored): every position state on one chart.
// Finance & Accounts uses the numbers of the spec: budget 30; ED 1 · GM 3 · DGM 3 · AGM 3 ·
// Senior Executive 10 · Junior Executive 10. One DGM of three hired (two blocked), five AGM on
// three slots (two extra), recruitment running for Senior and Junior Executives.
import type { ChartGrade, ChartPosition, DepartmentCounts, PositionState } from '../core/organogram'

export interface DemoChart {
  department: { id: string; name: string; head: { id: string; full_name: string } | null }
  can: { budget: boolean; toggle: boolean }
  budget: { approved_headcount: number; after_separation: 'vacant' | 'blocked'; note: string | null; updated_at: string }
  counts: DepartmentCounts
  grades: ChartGrade[]
  unmapped: { id: string; full_name: string; designation: string | null }[]
  story: string
}

const NAMES = ['Rahim Uddin', 'Karim Ahmed', 'Sadia Islam', 'Nusrat Jahan', 'Tanvir Hasan', 'Farhana Akter', 'Mahmudul Hasan', 'Sharmin Sultana',
  'Arif Hossain', 'Tahmina Begum', 'Rakib Hasan', 'Jannatul Ferdous', 'Shakil Ahmed', 'Mitu Rahman', 'Imran Khan', 'Lamia Chowdhury',
  'Sohel Rana', 'Rumana Afroz', 'Nazmul Huda', 'Sabrina Yasmin', 'Fahim Shahriar', 'Moushumi Das', 'Asif Iqbal', 'Rezaul Karim',
  'Nadia Hossain', 'Habibur Rahman', 'Shirin Akter', 'Kamrul Islam']

let nameAt = 0
const person = (designation: string, year: number): ChartPosition['employee'] => {
  const n = nameAt++
  return { id: `demo-emp-${n}`, full_name: NAMES[n % NAMES.length], card_id: `EMP${String(2600 + n)}`, designation, join_date: `${year}-0${(n % 9) + 1}-01` }
}

function grade(id: string, code: string, name: string, rank: number, planned: number, designation: string,
  cells: (PositionState | { state: 'in_recruitment'; stage: string; candidates: number; title: string })[]): ChartGrade {
  let planNo = 0
  let extraNo = 0
  const positions = cells.map((c, i): ChartPosition => {
    const state = typeof c === 'string' ? c : c.state
    const kind = state === 'extra' ? 'extra' : 'planned'
    const slot = kind === 'extra' ? ++extraNo : ++planNo
    return {
      id: `${id}-${kind}-${slot}`, slot_no: slot, kind, hold_state: state === 'blocked' ? 'blocked' : 'open', state,
      employee: state === 'filled' || state === 'extra' ? person(designation, 2016 + (i % 9)) : null,
      recruitment: typeof c === 'string' ? null : { vacancy_id: `${id}-vac`, post_id: null, title: c.title, candidates: c.candidates, stage: c.stage },
    }
  })
  return { id, code, name, rank, planned, positions }
}

function counts(grades: ChartGrade[], budget: number, inProcess: number, accepted: number): DepartmentCounts {
  const filled = grades.reduce((s, g) => s + g.positions.filter((p) => p.employee).length, 0)
  return { budget, filled, offers_in_process: inProcess, offers_accepted: accepted, available: budget - filled - inProcess, headroom: budget - filled - accepted }
}

function finance(): DemoChart {
  nameAt = 0
  const grades = [
    grade('d-ed', 'ED', 'ED', 2, 1, 'Executive Director, Finance', ['filled']),
    grade('d-gm', 'GM', 'GM', 3, 3, 'GM Finance', ['filled', 'filled', 'blocked']),
    grade('d-dgm', 'DGM', 'DGM', 4, 3, 'DGM Accounts', ['filled', 'blocked', 'blocked']),
    grade('d-agm', 'AGM', 'AGM', 5, 3, 'AGM Accounts', ['filled', 'filled', 'filled', 'extra', 'extra']),
    grade('d-sr', 'SREXEC', 'Senior Executive', 6, 10, 'Senior Executive, Accounts', [
      'filled', 'filled', 'filled', 'filled', 'filled', 'filled',
      { state: 'in_recruitment', stage: 'Interviews', candidates: 4, title: 'Senior Executive, Accounts' },
      { state: 'in_recruitment', stage: 'Interviews', candidates: 4, title: 'Senior Executive, Accounts' }, 'vacant', 'vacant']),
    grade('d-jr', 'JREXEC', 'Junior Executive', 8, 10, 'Junior Executive, Accounts', [
      'filled', 'filled', 'filled', 'filled', 'filled', 'filled', 'filled', 'filled',
      { state: 'in_recruitment', stage: 'Applications', candidates: 12, title: 'Junior Executive, Accounts' }, 'vacant']),
  ]
  return {
    department: { id: 'demo-finance', name: 'Finance & Accounts', head: { id: 'demo-emp-0', full_name: NAMES[0] } },
    can: { budget: false, toggle: false },
    budget: { approved_headcount: 30, after_separation: 'vacant', note: null, updated_at: '2026-10-25T00:00:00Z' },
    counts: counts(grades, 30, 2, 1), grades, unmapped: [],
    story: 'Budget 30 with slots ED 1 · GM 3 · DGM 3 · AGM 3 · Sr Exec 10 · Jr Exec 10. Only 1 of 3 DGM hired, the other two slots are blocked; '
      + 'five AGM sit on three slots, so two are extra (allowed because the budget still has room); Senior and Junior Executives are being recruited; '
      + 'two offers are in process, so 23 filled + 2 offers leaves 5 seats free to hire.',
  }
}

function hrAdmin(): DemoChart {
  nameAt = 20
  const grades = [
    grade('h-gm', 'GM', 'GM', 3, 1, 'GM HR & Admin', [{ state: 'in_recruitment', stage: 'Offer', candidates: 1, title: 'GM HR & Admin' }]),
    grade('h-agm', 'AGM', 'AGM', 5, 1, 'AGM HR', ['filled']),
    grade('h-sr', 'SREXEC', 'Senior Executive', 6, 2, 'Senior Executive, HR', ['filled', 'blocked']),
    grade('h-ex', 'EXEC', 'Executive', 7, 2, 'Executive, Admin', ['filled', 'filled']),
  ]
  return {
    department: { id: 'demo-hr', name: 'HR & Admin', head: null },
    can: { budget: false, toggle: false },
    budget: { approved_headcount: 6, after_separation: 'blocked', note: null, updated_at: '2026-10-25T00:00:00Z' },
    counts: counts(grades, 6, 1, 1), grades, unmapped: [],
    story: 'Budget 6, fully planned. The GM left and is being replaced (an offer is out). This department blocks a position when someone leaves, '
      + 'so a Senior Executive slot is frozen. 4 filled + 1 offer leaves 1 seat of budget: the blocked slot frees it, so it could be used for one extra hire.',
  }
}

export const DEMO_ORGANOGRAMS: DemoChart[] = [finance(), hrAdmin()]
