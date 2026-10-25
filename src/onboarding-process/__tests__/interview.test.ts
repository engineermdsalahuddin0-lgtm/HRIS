import { describe, expect, it } from 'vitest'
import { compositeFigures } from '@/onboarding-process/core/composite'
import { meanOf, renderTemplate, suggestedQuestions } from '@/onboarding-process/core/interview'

const W = { ats: 10, objective: 25, written: 20, interview: 45 }

describe('composite (same numbers as recruit_r5_messages_interviews_test.sql)', () => {
  it('1 all four components -> 76.2', () => {
    const f = compositeFigures({ weights: W, ats: 72, objective: 80, written: 65, interview_means: [4.2] })
    expect([f.interview_percent, f.composite]).toEqual([80, 76.2])
    expect(f.components.map((c) => c.points)).toEqual([7.2, 20, 13, 36])
  })
  it('2 no written test -> weights renormalised -> 79.0', () => {
    expect(compositeFigures({ weights: W, ats: 72, objective: 80, interview_means: [4.2] }).composite).toBe(79)
  })
  it('3 interviewers 4.6 and 3.0 -> 70 %, spread 1.6 flagged', () => {
    const f = compositeFigures({ weights: W, interview_means: [4.6, 3.0] })
    expect([f.interview_percent, f.spread, f.spread_flag, f.composite]).toEqual([70, 1.6, true, 70])
  })
  it('Rahim: objective 60, written 70, panel 4 / 5 / 3.8 -> 81.67 % -> 73.06', () => {
    const f = compositeFigures({ weights: W, ats: null, objective: 60, written: 70, interview_means: [4, 5, 3.8] })
    expect([f.panel_mean, f.interview_percent, f.spread, f.spread_flag, f.composite]).toEqual([4.27, 81.67, 1.2, false, 73.06])
  })
})

describe('interview helpers', () => {
  it('mean needs all five categories', () => {
    expect(meanOf({ job_knowledge: 4, communication: 4, problem_solving: 4, confidence: 3, culture_fit: 4 })).toBe(3.8)
    expect(meanOf({ job_knowledge: 4 })).toBeNull()
  })
  it('fills placeholders like the database', () => {
    expect(renderTemplate('Hi {name}, {job_title} {unknown}', { name: 'Rahim', job_title: 'Senior Executive' }))
      .toBe('Hi Rahim, Senior Executive {unknown}')
  })
  it('suggests questions for missing skills and weak sections', () => {
    const q = suggestedQuestions({
      job: { title: 'Senior Executive', profile: { duties: '- Prepare vouchers\n- Bank reconciliation', required_skills: ['Tally', 'VAT'], experience_min_years: 2 } },
      screening: { matched_required: ['Tally'], years: 1 },
      objective: { sections: { aptitude: { percent: 0 }, language: { percent: 100 } } },
    })
    expect(q[0].text).toContain('does not show VAT')
    expect(q.some((x) => x.text.includes('Prepare vouchers'))).toBe(true)
    expect(q.some((x) => x.text.includes('weak in aptitude'))).toBe(true)
    expect(q.some((x) => x.category === 'confidence' && x.text.includes('less experience'))).toBe(true)
  })
})
