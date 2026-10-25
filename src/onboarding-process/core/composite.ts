// Composite result: mirror of private.composite_figures (recruit_r5_messages_interviews_test.sql
// and __tests__/interview.test.ts use the same numbers).
// interview % = (mean of the interviewers' means - 1) / 4 x 100 (2 decimals)
// composite = sum(weight x %) / sum(weights of the components present) (2 decimals)
// spread = highest - lowest interviewer mean; flagged above 1.5.
import type { Weights } from './types'
import { roundTo } from './workload'

export type ComponentKey = keyof Weights
export interface CompositeComponent { key: ComponentKey; percent: number; weight: number; effective_weight: number; points: number }
export interface CompositeFigures {
  components: CompositeComponent[]; composite: number | null; interview_percent: number | null
  panel_mean: number | null; interviewers: number; spread: number | null; spread_flag: boolean
}

export function compositeFigures(p: {
  weights: Weights; ats?: number | null; objective?: number | null; written?: number | null; interview_means?: number[]
}): CompositeFigures {
  const means = p.interview_means ?? []
  const panelMean = means.length ? means.reduce((a, b) => a + b, 0) / means.length : null
  const interview = panelMean == null ? null : roundTo(((panelMean - 1) / 4) * 100, 2)
  const spread = means.length ? Math.max(...means) - Math.min(...means) : null
  const values: Record<ComponentKey, number | null | undefined> = { ats: p.ats, objective: p.objective, written: p.written, interview }
  const present = (Object.keys(values) as ComponentKey[])
    .filter((k) => values[k] != null && p.weights[k] > 0)
    .map((k) => ({ key: k, percent: Number(values[k]), weight: p.weights[k] }))
  const sumW = present.reduce((s, c) => s + c.weight, 0)
  return {
    components: present.map((c) => ({ ...c, effective_weight: roundTo((c.weight / sumW) * 100, 2), points: roundTo((c.weight * c.percent) / sumW, 2) })),
    composite: sumW > 0 ? roundTo(present.reduce((s, c) => s + c.weight * c.percent, 0) / sumW, 2) : null,
    interview_percent: interview,
    panel_mean: panelMean == null ? null : roundTo(panelMean, 2),
    interviewers: means.length,
    spread: spread == null ? null : roundTo(spread, 2),
    spread_flag: spread != null && spread > 1.5,
  }
}

export const COMPONENT_LABEL: Record<ComponentKey, string> = { ats: 'CV (ATS)', objective: 'Objective', written: 'Written', interview: 'Interview' }
