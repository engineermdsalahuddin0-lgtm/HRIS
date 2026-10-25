// Hiring flow demo: one story from workload to joining, calculated by the real core code
// (workload, ATS, objective / written scores, composite, organogram rules). Browser only;
// nothing is stored. The whole src/demo folder can be deleted (see README.md).
import type { EducationLevel, WorkloadInput } from '@/onboarding-process/core/types'
import type { ScoredQuestion } from '@/onboarding-process/core/assessment'
import { scoreObjective, writtenPercent } from '@/onboarding-process/core/assessment'
import type { AtsFigures } from '@/onboarding-process/core/ats'
import { atsFigures } from '@/onboarding-process/core/ats'
import type { CompositeFigures } from '@/onboarding-process/core/composite'
import { compositeFigures } from '@/onboarding-process/core/composite'
import { DEFAULT_WEIGHTS } from '@/onboarding-process/core/jobPost'
import { workloadFigures } from '@/onboarding-process/core/workload'
import type { SimState } from '@/onboarding-process/core/organogramSim'
import { seedState } from '@/onboarding-process/core/organogramSim'

export const STEPS = [
  { key: 'workforce', step: 'R1', title: 'Workload & vacancy', who: 'Manager → HR → Admin' },
  { key: 'post', step: 'R2', title: 'Job post & applicants', who: 'HR' },
  { key: 'screening', step: 'R3', title: 'CV screening', who: 'HR / Manager (AI or basic reading)' },
  { key: 'tests', step: 'R4', title: 'Online & written tests', who: 'Applicants, HR' },
  { key: 'interview', step: 'R5', title: 'Interviews & results', who: 'Assigned interviewers' },
  { key: 'offer', step: 'R6', title: 'Decision, offer & pre-joining', who: 'HR prepares, Admin approves, applicant' },
  { key: 'joining', step: 'R7', title: 'Joining & organogram', who: 'HR, new employee' },
] as const
export type StepKey = (typeof STEPS)[number]['key']

export const COMPANY = 'Alpha Garments Ltd.'
export const TODAY = '2026-10-25'

/** Accounts: 5 people, 6 sanctioned; 1,150 h of work a month at 200 h per person. */
export const WORKLOAD: WorkloadInput = { demand_hours: 1150, capacity_per_fte: 200, active: 5, sanctioned: 6, separations: 1, avg_headcount: 5.5 }
export const workload = () => workloadFigures(WORKLOAD)

export const POST = {
  title: 'Senior Executive, Accounts', department: 'Accounts', seats: 1, salary_min: 30000, salary_max: 40000,
  deadline: '2026-11-10', min_years: 3, required_level: 'bachelor' as EducationLevel,
  must_have: ['Voucher checking', 'VAT & tax returns', 'Bank reconciliation', 'Tally / ERP'], nice_to_have: ['IFRS', 'Excel pivot tables'],
  pass_percent: 50, written_total: 20, weights: DEFAULT_WEIGHTS,
}

/** Online test: 10 questions, 2 marks each. Correct option is 0 for every question in the demo. */
export const OBJECTIVE: ScoredQuestion[] = Array.from({ length: 10 }, (_, i) => ({
  position: i + 1, section: i < 4 ? 'job_knowledge' : i < 7 ? 'aptitude' : 'language', marks: 2, correct_index: 0,
}))

export interface Candidate {
  id: string; name: string; email: string; source: 'careers page' | 'referral' | 'job portal'
  years: number | null; level: Exclude<EducationLevel, 'any'> | null; matched: number; nice: number
  correct: number; written: number[]; interview: [number, number]
}

export const CANDIDATES: Candidate[] = [
  { id: 'c1', name: 'Rahim Uddin', email: 'rahim@example.com', source: 'careers page', years: 5, level: 'bachelor', matched: 3, nice: 1, correct: 8, written: [8, 7], interview: [4.8, 4.6] },
  { id: 'c2', name: 'Sadia Islam', email: 'sadia@example.com', source: 'referral', years: 4, level: 'masters', matched: 4, nice: 2, correct: 7, written: [9, 8], interview: [3.8, 4.0] },
  { id: 'c3', name: 'Karim Ahmed', email: 'karim@example.com', source: 'job portal', years: 3, level: 'bachelor', matched: 2, nice: 0, correct: 5, written: [5, 5], interview: [2.6, 3.0] },
  { id: 'c4', name: 'Nusrat Jahan', email: 'nusrat@example.com', source: 'careers page', years: 2, level: 'bachelor', matched: 3, nice: 1, correct: 0, written: [], interview: [1, 1] },
  { id: 'c5', name: 'Tanvir Hasan', email: 'tanvir@example.com', source: 'job portal', years: null, level: 'hsc', matched: 1, nice: 0, correct: 0, written: [], interview: [1, 1] },
]

export const INTERVIEWERS = ['Accounts Manager', 'HR Manager'] as const

export function screen(c: Candidate): AtsFigures {
  return atsFigures({ req_total: POST.must_have.length, req_matched: c.matched, nice_total: POST.nice_to_have.length, nice_matched: c.nice,
    min_years: POST.min_years, years: c.years, required_level: POST.required_level, applicant_level: c.level, relevance: null })
}

/** The answers a candidate gave: the first `correct` questions right, the rest wrong. */
export function objective(c: Candidate) {
  const answers = Object.fromEntries(OBJECTIVE.map((q, i) => [q.position, i < c.correct ? 0 : 1]))
  return scoreObjective(OBJECTIVE, answers, POST.pass_percent)
}

export interface ResultRow { c: Candidate; ats: AtsFigures; objective: number | null; passed: boolean | null; written: number | null; figures: CompositeFigures }

/** Results of the shortlisted candidates, best composite first (ties by name). */
export function results(shortlist: string[], interview: Record<string, [number, number]>): ResultRow[] {
  return CANDIDATES.filter((c) => shortlist.includes(c.id)).map((c): ResultRow => {
    const ats = screen(c)
    const o = objective(c)
    const written = o.passed ? writtenPercent(c.written, POST.written_total) : null
    const means = o.passed ? interview[c.id] ?? c.interview : []
    return { c, ats, objective: o.percent, passed: o.passed, written,
      figures: compositeFigures({ weights: POST.weights, ats: ats.score, objective: o.percent, written, interview_means: means }) }
  }).sort((a, b) => (b.passed ? 1 : 0) - (a.passed ? 1 : 0) || (b.figures.composite ?? -1) - (a.figures.composite ?? -1) || a.c.name.localeCompare(b.c.name))
}

export const defaultShortlist = () => CANDIDATES.filter((c) => screen(c).gate === 'pass').map((c) => c.id)

/** The offer HR prepares for the selected candidate. */
export const OFFER = { gross: 35000, joining_date: '2026-11-15', expires_on: '2026-11-05', probation_months: 6 }

export const OFFER_STEPS = [
  { key: 'draft', label: 'HR prepares the offer', who: 'HR Manager' },
  { key: 'approved', label: 'Admin approves (never the preparer)', who: 'Admin' },
  { key: 'sent', label: 'Offer link emailed', who: 'System' },
  { key: 'accepted', label: 'Candidate accepts on the link', who: 'Candidate' },
  { key: 'submitted', label: 'Pre-joining form: photo, NID, bank, nominee', who: 'Candidate' },
  { key: 'verified', label: 'HR checks and verifies the form', who: 'HR Manager' },
] as const

/** Accounts department before the hire: budget 6, Senior Executive slots 3 with one vacant. */
export function accountsOrganogram(): SimState {
  return seedState({
    department: { id: 'flow-accounts', name: 'Accounts', head: 'Accounts Manager' }, budget: 6, after_separation: 'vacant',
    names: ['Accounts Manager', 'Shirin Akter', 'Kamrul Islam', 'Tasnim Ara', 'Rafiqul Alam'],
    grades: [
      { id: 'f-mgr', code: 'MGR', name: 'Manager', rank: 4, designation: 'Accounts Manager', slots: 1, cells: ['filled'] },
      { id: 'f-sr', code: 'SREXEC', name: 'Senior Executive', rank: 6, designation: 'Senior Executive, Accounts', slots: 3, cells: ['filled', 'filled', 'recruiting'],
        stage: 'Interviews', candidates: 3 },
      { id: 'f-ex', code: 'EXEC', name: 'Executive', rank: 7, designation: 'Executive, Accounts', slots: 2, cells: ['filled', 'filled'] },
    ],
  })
}

/** Masks every digit but the last four, as the HR view of the pre-joining form shows them. */
export const last4 = (value: string) => `•••• ${value.slice(-4)}`
