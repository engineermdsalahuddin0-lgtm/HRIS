// Online test scoring and interview dates: mirror of private.score_invite and
// private.interview_due_by (recruit_r4_tests_interviews_test.sql uses the same numbers).
// Objective % = marks of correct answers ÷ total marks × 100 (1 decimal), also per section.
// Written % = entered marks ÷ total × 100. Interview due = last result date + 15 days.
import type { QuestionSection } from './types'
import { roundTo } from './workload'

export interface ScoredQuestion { position: number; section: QuestionSection; marks: number; correct_index: number }
export interface SectionScore { score: number; total: number; percent: number | null }
export interface ObjectiveScore {
  score: number; total: number; percent: number | null; answered: number; correct: number
  sections: Partial<Record<QuestionSection, SectionScore>>; passed: boolean | null
}

export function scoreObjective(questions: ScoredQuestion[], answers: Record<number, number>, passPercent: number | null): ObjectiveScore {
  const sections: Partial<Record<QuestionSection, SectionScore>> = {}
  let score = 0
  let total = 0
  let answered = 0
  let correct = 0
  for (const q of questions) {
    const s = sections[q.section] ?? { score: 0, total: 0, percent: null }
    const chosen = answers[q.position]
    const right = chosen === q.correct_index
    if (chosen !== undefined) answered += 1
    if (right) { correct += 1; score += q.marks; s.score += q.marks }
    total += q.marks
    s.total += q.marks
    sections[q.section] = s
  }
  for (const s of Object.values(sections)) if (s) s.percent = s.total > 0 ? roundTo((s.score / s.total) * 100, 1) : null
  const percent = total > 0 ? roundTo((score / total) * 100, 1) : null
  return { score, total, percent, answered, correct, sections, passed: passPercent == null || percent == null ? null : percent >= passPercent }
}

export function writtenPercent(marks: number[], total: number): number | null {
  return total > 0 ? roundTo((marks.reduce((a, b) => a + b, 0) / total) * 100, 1) : null
}

/** "mm:ss" (or "h:mm:ss") for the test timer. */
export function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`
}

export const testPath = (token: string) => `/t/${token}`

export const INVITE_STATUS_LABEL = {
  invited: 'Link sent', started: 'Taking the test', submitted: 'Submitted', expired: 'Link expired', cancelled: 'Link cancelled',
} as const

/** Local date + time (HH:MM) in a time zone → ISO instant. Bangladesh has no daylight saving; the offset is read from Intl. */
export function zonedToIso(date: string, time: string, timeZone: string): string {
  const guess = new Date(`${date}T${time}:00Z`)
  const parts = new Intl.DateTimeFormat('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
    .formatToParts(guess)
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value)
  const asZoned = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'))
  return new Date(guess.getTime() - (asZoned - guess.getTime())).toISOString()
}

/** ISO instant → { date, time } as seen in a time zone. */
export function isoToZoned(iso: string, timeZone: string): { date: string; time: string } {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
    .formatToParts(new Date(iso))
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '00'
  return { date: `${get('year')}-${get('month')}-${get('day')}`, time: `${get('hour')}:${get('minute')}` }
}
