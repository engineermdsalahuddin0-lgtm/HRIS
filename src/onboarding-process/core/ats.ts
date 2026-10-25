// Must-have gate and ATS score: mirror of private.ats_figures (recruit_r3_screening_test.sql
// and __tests__/screening.test.ts use the same 5 hand-calculated cases).
// skills 40 (+ up to 5 for nice-to-have, capped at 40) + experience 25 + education 20 (+ relevance 15);
// without a relevance mark the total is out of 85. Score = points / max x 100, 1 decimal.
import type { EducationLevel } from './types'
import { roundTo } from './workload'

export type Gate = 'pass' | 'fail' | 'review'
export type GateReason = 'experience_below_minimum' | 'experience_unknown' | 'education_below_required' | 'education_unknown'

export interface AtsInput {
  req_total: number; req_matched: number; nice_total?: number; nice_matched?: number
  min_years: number; years: number | null
  required_level: EducationLevel; applicant_level: Exclude<EducationLevel, 'any'> | null
  subjects_required?: number; subject_matched?: boolean
  relevance: number | null
}

export interface AtsFigures extends AtsInput {
  skills: number; experience: number; education: number; max: 85 | 100; score: number
  experience_ok: boolean | null; education_ok: boolean | null; gate: Gate; reasons: GateReason[]
}

const RANK: Record<EducationLevel, number> = { any: 0, ssc: 1, hsc: 2, diploma: 3, bachelor: 4, masters: 5, phd: 6 }

export function atsFigures(p: AtsInput): AtsFigures {
  const niceTotal = p.nice_total ?? 0
  const skills = Math.min(40, roundTo(p.req_total > 0 ? (40 * p.req_matched) / p.req_total : 40, 2)
    + roundTo(niceTotal > 0 ? (5 * (p.nice_matched ?? 0)) / niceTotal : 0, 2))
  const experience = p.min_years === 0 ? 25 : p.years == null ? 0 : p.years >= p.min_years ? 25 : roundTo((25 * p.years) / p.min_years, 2)
  const levelOk = p.required_level === 'any' ? true : p.applicant_level == null ? null : RANK[p.applicant_level] >= RANK[p.required_level]
  const education = p.required_level === 'any' ? 20
    : levelOk ? 15 + ((p.subjects_required ?? 0) === 0 || p.subject_matched ? 5 : 0) : 0
  const max = p.relevance == null ? 85 : 100
  const experienceOk = p.min_years === 0 ? true : p.years == null ? null : p.years >= p.min_years
  const reasons: GateReason[] = []
  if (experienceOk === false) reasons.push('experience_below_minimum')
  if (experienceOk === null) reasons.push('experience_unknown')
  if (levelOk === false) reasons.push('education_below_required')
  if (levelOk === null) reasons.push('education_unknown')
  const gate: Gate = experienceOk === false || levelOk === false ? 'fail' : experienceOk === null || levelOk === null ? 'review' : 'pass'
  const total = roundTo(skills + experience + education + (p.relevance ?? 0), 2)
  return {
    ...p, skills: roundTo(skills, 2), experience, education, max, score: roundTo((total / max) * 100, 1),
    experience_ok: experienceOk, education_ok: levelOk, gate, reasons,
  }
}

export const GATE_LABEL: Record<Gate, string> = { pass: 'Meets must-haves', fail: 'Misses a must-have', review: 'Check by hand' }

export const REASON_TEXT: Record<GateReason, string> = {
  experience_below_minimum: 'Less experience than the minimum',
  experience_unknown: 'Years of experience not found',
  education_below_required: 'Education below the requirement',
  education_unknown: 'Education level not found',
}
