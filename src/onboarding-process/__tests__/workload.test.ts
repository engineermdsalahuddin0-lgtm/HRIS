import { describe, expect, it } from 'vitest'
import { DEMO_CASES, demoDemandHours, demoInput } from '@/onboarding-process/demo/workloadCases'
import { inputHours, ratioHours, roundTo, suggestionText, workloadFigures } from '@/onboarding-process/core/workload'
import { explain } from '@/onboarding-process/core/explain'
import { availableActions } from '@/onboarding-process/core/workflow'
import { parseInputCsv } from '@/onboarding-process/core/inputCsv'

describe('parseInputCsv', () => {
  it('reads code, description, quantity and minutes; skips the header', () => {
    expect(parseInputCsv('code,description,qty,smv\nPOLO-26, Polo shirt, 54000, 12\nTEE\t20000\t8.5')).toEqual([
      { metric_key: 'POLO-26', label: 'Polo shirt', quantity: '54000', std_minutes: '12' },
      { metric_key: 'TEE', label: '', quantity: '20000', std_minutes: '8.5' },
    ])
  })
})

describe('the 10 demo cases (same numbers as recruit_r1_workforce_test.sql)', () => {
  it.each(DEMO_CASES)('case $id $department', (demo) => {
    const f = workloadFigures(demoInput(demo))
    expect(f.index).toBe(demo.expected.index)
    expect(f.band).toBe(demo.expected.band)
    expect(f.required_fte).toBe(demo.expected.required)
    expect(f.gap).toBe(demo.expected.gap)
    expect(f.backfill_seats).toBe(demo.expected.backfill)
    expect(f.new_positions).toBe(demo.expected.newPositions)
    expect(f.hold_seats).toBe(demo.expected.hold)
    expect(f.budget_blocked_seats).toBe(demo.expected.budgetBlocked)
    expect(f.action).toBe(demo.expected.action)
  })

  it('derives demand hours from each method', () => {
    expect(demoDemandHours(DEMO_CASES[0])).toBe(10800)  // 54,000 × 12 ÷ 60
    expect(demoDemandHours(DEMO_CASES[4])).toBe(1800)   // 6,000 × 15 ÷ 60 + 300 h
    expect(demoDemandHours(DEMO_CASES[5])).toBe(1700)   // 850 ÷ 100 × 200
    expect(demoDemandHours(DEMO_CASES[7])).toBe(1500)   // 9,000 × 6 + 3,000 × 12, ÷ 60
  })

  it('flags attrition above the limit', () => {
    const f = workloadFigures(demoInput(DEMO_CASES[7]))
    expect(f.attrition_percent).toBe(28.6)
    expect(f.attrition_flag).toBe(true)
  })
})

describe('workloadFigures edge cases', () => {
  it('matches the real-data Sewing month of the SQL test', () => {
    const aug = workloadFigures({ demand_hours: inputHours([{ quantity: 4800, std_minutes: 15 }]), capacity_per_fte: 200,
      active: 5, sanctioned: 6, separations: 1, avg_headcount: 5.67, cost_per_seat: 10000, budget_remaining: 10000 })
    expect([aug.index, aug.band, aug.overload_rule, aug.backfill_seats, aug.budget_status]).toEqual([1.2, 'overload', false, 1, 'ok'])
    expect(aug.attrition_percent).toBe(17.6)
    const sep = workloadFigures({ demand_hours: 1400, capacity_per_fte: 200, active: 5, sanctioned: 6,
      prior_overload_months: 1, cost_per_seat: 10000, budget_remaining: 10000 })
    expect([sep.band, sep.new_positions, sep.budget_ok_backfill, sep.budget_ok_new, sep.budget_blocked_seats])
      .toEqual(['critical', 1, 1, 0, 1])
  })

  it('treats work with nobody in the department as critical', () => {
    const f = workloadFigures({ demand_hours: 400, capacity_per_fte: 200, active: 0, sanctioned: 2 })
    expect(f.index).toBeNull()
    expect(f.band).toBe('critical')
    expect(f.backfill_seats).toBe(2)
  })

  it('refuses a zero capacity', () => {
    expect(() => workloadFigures({ demand_hours: 1, capacity_per_fte: 0, active: 1, sanctioned: 1 })).toThrow()
  })

  it('rounds half away from zero like Postgres', () => {
    expect(roundTo(1.0005, 3)).toBe(1.001)
    expect(roundTo(-2.345, 2)).toBe(-2.35)
    expect(ratioHours(850, 100, 200)).toBe(1700)
  })

  it('writes a plain suggestion', () => {
    expect(suggestionText(workloadFigures(demoInput(DEMO_CASES[0])))).toBe('backfill 4 · 1 vacancy on hold')
    expect(suggestionText(workloadFigures(demoInput(DEMO_CASES[6])))).toMatch(/overload for 1 of 2 months/)
  })
})

describe('explain', () => {
  it('fills the formula with the numbers', () => {
    const demo = DEMO_CASES[7]
    const f = { ...workloadFigures(demoInput(demo)), method: demo.method, inputs: demo.inputs }
    expect(explain('demand', f).working).toBe('(9,000 × 6 + 3,000 × 12) ÷ 60 = 1,500 h')
    expect(explain('index', f).working).toBe('1,500 ÷ (6 × 200) = 1.25')
    expect(explain('attrition', f).working).toContain('2 ÷ 7 × 100 = 28.6 %')
    expect(explain('backfill', f).references).toContain('workforce.vacancy_rate')
  })
})

describe('vacancy actions', () => {
  const viewer = { userId: 'u1', canReview: true, canApprove: true }
  it('never lets the reviewer decide', () => {
    expect(availableActions({ status: 'hr_reviewed', hr_reviewed_by: 'u1' }, viewer)).toEqual(['cancel'])
    expect(availableActions({ status: 'hr_reviewed', hr_reviewed_by: 'u2' }, viewer)).toContain('approve')
  })
  it('offers review actions on drafts only to reviewers', () => {
    expect(availableActions({ status: 'draft', hr_reviewed_by: null }, { ...viewer, canReview: false })).toEqual([])
    expect(availableActions({ status: 'rejected', hr_reviewed_by: null }, viewer)).toEqual([])
  })
})
