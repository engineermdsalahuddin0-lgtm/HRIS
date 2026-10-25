import { describe, expect, it } from 'vitest'
import { DEMO_ORGANOGRAMS } from '@/onboarding-process/demo/organogramDemo'
import { budgetError, budgetSentence, stateCounts } from '@/onboarding-process/core/organogram'

describe('demo organograms obey the organogram rules', () => {
  it.each(DEMO_ORGANOGRAMS)('$department.name', (d) => {
    const slots = d.grades.map((g) => g.planned)
    // Slots fit the budget and the budget covers filled + offers in process.
    expect(budgetError(d.budget.approved_headcount, slots, d.counts)).toBeNull()
    for (const g of d.grades) {
      const planned = g.positions.filter((p) => p.kind === 'planned')
      expect(planned).toHaveLength(g.planned)
      // Extra positions only when every planned slot of the grade is taken.
      if (g.positions.some((p) => p.state === 'extra')) expect(planned.every((p) => p.employee)).toBe(true)
      for (const p of g.positions) expect(Boolean(p.employee)).toBe(p.state === 'filled' || p.state === 'extra')
    }
    expect(d.counts.available).toBeGreaterThanOrEqual(0)
  })
  it('Finance & Accounts shows the spec numbers', () => {
    const f = DEMO_ORGANOGRAMS[0]
    expect(f.budget.approved_headcount).toBe(30)
    expect(stateCounts(f.grades)).toEqual({ filled: 21, extra: 2, vacant: 3, in_recruitment: 3, blocked: 3 })
    expect(budgetSentence(f.counts)).toBe('23 of 30 filled · 2 offers in process · 5 seats free to hire')
  })
})
