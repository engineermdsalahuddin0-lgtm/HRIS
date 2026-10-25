// Demo organograms (browser only, never stored): every position state on one chart.
// Finance & Accounts uses the numbers of the spec: budget 30; ED 1 · GM 3 · DGM 3 · AGM 3 ·
// Senior Executive 10 · Junior Executive 10. One DGM of three hired (two blocked), five AGM on
// three slots (two extra), recruitment running for Senior and Junior Executives.
// The seeds feed the simulator (core/organogramSim), so the demo can be played with.
import type { ChartGrade, DepartmentCounts } from '../core/organogram'
import type { SeedCell, SimState } from '../core/organogramSim'
import { seedState, simChart } from '../core/organogramSim'

export interface DemoChart {
  department: { id: string; name: string; head: { id: string; full_name: string } | null }
  can: { budget: boolean; toggle: boolean }
  budget: { approved_headcount: number; after_separation: 'vacant' | 'blocked'; note: string | null; updated_at: string }
  counts: DepartmentCounts
  grades: ChartGrade[]
  unmapped: { id: string; full_name: string; designation: string | null }[]
}

const NAMES = ['Rahim Uddin', 'Karim Ahmed', 'Sadia Islam', 'Nusrat Jahan', 'Tanvir Hasan', 'Farhana Akter', 'Mahmudul Hasan', 'Sharmin Sultana',
  'Arif Hossain', 'Tahmina Begum', 'Rakib Hasan', 'Jannatul Ferdous', 'Shakil Ahmed', 'Mitu Rahman', 'Imran Khan', 'Lamia Chowdhury',
  'Sohel Rana', 'Rumana Afroz', 'Nazmul Huda', 'Sabrina Yasmin', 'Fahim Shahriar', 'Moushumi Das', 'Asif Iqbal', 'Rezaul Karim',
  'Nadia Hossain', 'Habibur Rahman', 'Shirin Akter', 'Kamrul Islam', 'Tasnim Ara', 'Rafiqul Alam', 'Sumaiya Khatun', 'Jahid Hasan']

const rep = (n: number, v: SeedCell): SeedCell[] => Array.from({ length: n }, () => v)

export interface DemoSeed { seed: () => SimState; story: string }

export const DEMO_SEEDS: DemoSeed[] = [
  {
    seed: () => seedState({
      department: { id: 'demo-finance', name: 'Finance & Accounts', head: NAMES[0] }, budget: 30, after_separation: 'vacant', names: NAMES,
      grades: [
        { id: 'd-ed', code: 'ED', name: 'ED', rank: 2, designation: 'Executive Director, Finance', slots: 1, cells: ['filled'] },
        { id: 'd-gm', code: 'GM', name: 'GM', rank: 3, designation: 'GM Finance', slots: 3, cells: ['filled', 'filled', 'blocked'] },
        { id: 'd-dgm', code: 'DGM', name: 'DGM', rank: 4, designation: 'DGM Accounts', slots: 3, cells: ['filled', 'blocked', 'blocked'] },
        { id: 'd-agm', code: 'AGM', name: 'AGM', rank: 5, designation: 'AGM Accounts', slots: 3, cells: rep(3, 'filled'), extras: 2 },
        { id: 'd-sr', code: 'SREXEC', name: 'Senior Executive', rank: 6, designation: 'Senior Executive, Accounts', slots: 10,
          cells: [...rep(6, 'filled'), 'recruiting', 'recruiting', 'vacant', 'vacant'], stage: 'Interviews', candidates: 4 },
        { id: 'd-jr', code: 'JREXEC', name: 'Junior Executive', rank: 8, designation: 'Junior Executive, Accounts', slots: 10,
          cells: [...rep(8, 'filled'), 'recruiting', 'vacant'], stage: 'Applications', candidates: 12 },
      ],
      offers: [{ code: 'SREXEC', status: 'accepted' }, { code: 'JREXEC', status: 'sent' }],
    }),
    story: 'Budget 30 with slots ED 1 · GM 3 · DGM 3 · AGM 3 · Sr Exec 10 · Jr Exec 10. Only 1 of 3 DGM hired, the other two slots are blocked; '
      + 'five AGM sit on three slots, so two are extra (allowed because the budget still has room); Senior and Junior Executives are being recruited; '
      + 'two offers are in process, so 23 filled + 2 offers leaves 5 seats free to hire.',
  },
  {
    seed: () => seedState({
      department: { id: 'demo-hr', name: 'HR & Admin', head: null }, budget: 6, after_separation: 'blocked', names: NAMES.slice(20),
      grades: [
        { id: 'h-gm', code: 'GM', name: 'GM', rank: 3, designation: 'GM HR & Admin', slots: 1, cells: ['recruiting'], stage: 'Offer', candidates: 1 },
        { id: 'h-agm', code: 'AGM', name: 'AGM', rank: 5, designation: 'AGM HR', slots: 1, cells: ['filled'] },
        { id: 'h-sr', code: 'SREXEC', name: 'Senior Executive', rank: 6, designation: 'Senior Executive, HR', slots: 2, cells: ['filled', 'blocked'] },
        { id: 'h-ex', code: 'EXEC', name: 'Executive', rank: 7, designation: 'Executive, Admin', slots: 2, cells: ['filled', 'filled'] },
      ],
      offers: [{ code: 'GM', status: 'accepted' }],
    }),
    story: 'Budget 6, fully planned. The GM left and is being replaced (an offer is out). This department blocks a position when someone leaves, '
      + 'so a Senior Executive slot is frozen. 4 filled + 1 offer leaves 1 seat of budget: the blocked slot frees it, so it could be used for one extra hire.',
  },
]

/** A simulator state as the chart the real page shows. */
export function demoChart(s: SimState): DemoChart {
  const { counts, grades } = simChart(s)
  return {
    department: { id: s.department.id, name: s.department.name, head: s.department.head ? { id: `${s.department.id}-head`, full_name: s.department.head } : null },
    can: { budget: false, toggle: false },
    budget: { approved_headcount: s.budget, after_separation: s.after_separation, note: null, updated_at: '2026-10-25T00:00:00Z' },
    counts, grades, unmapped: [],
  }
}

export const DEMO_ORGANOGRAMS: (DemoChart & { story: string })[] = DEMO_SEEDS.map((d) => ({ ...demoChart(d.seed()), story: d.story }))
