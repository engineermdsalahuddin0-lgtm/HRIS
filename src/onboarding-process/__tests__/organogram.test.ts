import { describe, expect, it } from 'vitest'
import type { ChartGrade } from '@/onboarding-process/core/organogram'
import { budgetError, budgetSentence, chartLevels, stateCounts } from '@/onboarding-process/core/organogram'

const pos = (state: ChartGrade['positions'][number]['state'], slot = 1): ChartGrade['positions'][number] =>
  ({ id: `${state}-${slot}`, slot_no: slot, kind: state === 'extra' ? 'extra' : 'planned', hold_state: state === 'blocked' ? 'blocked' : 'open', state, employee: null, recruitment: null })

const GRADES: ChartGrade[] = [
  { id: 'agm', code: 'AGM', name: 'AGM', rank: 5, planned: 3, positions: [pos('filled', 1), pos('filled', 2), pos('filled', 3), pos('extra', 1), pos('extra', 2)] },
  { id: 'ed', code: 'ED', name: 'ED', rank: 2, planned: 1, positions: [pos('filled')] },
  { id: 'dgm', code: 'DGM', name: 'DGM', rank: 4, planned: 3, positions: [pos('filled', 1), pos('blocked', 2), pos('vacant', 3)] },
  { id: 'gm', code: 'GM', name: 'GM', rank: 3, planned: 0, positions: [] },
]

describe('organogram (same department as organogram_test.sql)', () => {
  it('counts states and skips empty grades, top first', () => {
    expect(stateCounts(GRADES)).toEqual({ filled: 5, extra: 2, vacant: 1, in_recruitment: 0, blocked: 1 })
    expect(chartLevels(GRADES).map((g) => g.code)).toEqual(['ED', 'DGM', 'AGM'])
  })
  it('checks the budget like save_department_budget', () => {
    expect(budgetError(9, [1, 3, 3, 3], { filled: 0, offers_in_process: 0 })).toBe('The grade slots add up to 10, more than the approved headcount of 9')
    expect(budgetError(6, [1, 3, 1, 1], { filled: 5, offers_in_process: 2 })).toBe('The budget cannot go below 5 filled + 2 offer(s) in process')
    expect(budgetError(7, [1, 3, 1, 1], { filled: 5, offers_in_process: 2 })).toBeNull()
  })
  it('describes the budget', () => {
    expect(budgetSentence({ budget: 10, filled: 7, offers_in_process: 0, offers_accepted: 0, available: 3, headroom: 3 })).toBe('7 of 10 filled · 3 seats free to hire')
    expect(budgetSentence({ budget: 7, filled: 5, offers_in_process: 2, offers_accepted: 0, available: 0, headroom: 2 })).toBe('5 of 7 filled · 2 offers in process · budget full')
    expect(budgetSentence({ budget: null, filled: 3, offers_in_process: 0, offers_accepted: 0, available: null, headroom: null })).toBe('No headcount budget set yet.')
  })
})
