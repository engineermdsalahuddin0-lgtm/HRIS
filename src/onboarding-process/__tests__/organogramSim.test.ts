import { describe, expect, it } from 'vitest'
import { DEMO_SEEDS } from '@/onboarding-process/demo/organogramDemo'
import { stateCounts } from '@/onboarding-process/core/organogram'
import type { SimState } from '@/onboarding-process/core/organogramSim'
import { acceptOffer, applyBudget, dropOffer, joinOffer, leave, sendOffer, simChart, simCounts, startRecruiting, toggleHold } from '@/onboarding-process/core/organogramSim'

const finance = () => DEMO_SEEDS[0].seed()
const hr = () => DEMO_SEEDS[1].seed()
const states = (s: SimState) => stateCounts(simChart(s).grades)
const slots = (s: SimState, patch: Record<string, number>) => ({ ...Object.fromEntries(s.grades.map((g) => [g.id, g.slots])), ...patch })
const pos = (s: SimState, gradeId: string, pick: (p: SimState['positions'][number]) => boolean) =>
  s.positions.filter((p) => p.grade_id === gradeId).sort((a, b) => a.slot_no - b.slot_no).find(pick)!

describe('organogram simulator follows the database rules', () => {
  it('an offer needs a free budget seat (offer_budget_guard)', () => {
    let s = hr()                                   // budget 6: 4 filled + 1 offer
    const r1 = sendOffer(s, 'h-ex')
    expect(r1.error).toBeNull()
    s = r1.state
    expect(simCounts(s).available).toBe(0)
    const r2 = sendOffer(s, 'h-ex')
    expect(r2.error).toMatch(/budget is full/)
    expect(r2.state).toBe(s)
  })

  it('joining takes a free slot, else becomes an extra; declining frees the seat', () => {
    let s = finance()
    const sr = s.offers.find((o) => o.grade_id === 'd-sr')!
    s = joinOffer(s, sr.id).state
    expect(states(s).filled).toBe(22)
    expect(s.recruitment['d-sr'].seats).toBe(1)    // one recruitment seat used
    // AGM has no free slot: a joiner there is extra.
    s = sendOffer(s, 'd-agm').state
    const agm = s.offers.find((o) => o.grade_id === 'd-agm')!
    s = joinOffer(acceptOffer(s, agm.id).state, agm.id).state
    expect(states(s).extra).toBe(3)
    const before = simCounts(s).available
    const jr = s.offers.find((o) => o.grade_id === 'd-jr')!
    expect(simCounts(dropOffer(s, jr.id).state).available).toBe(before! + 1)
  })

  it('leaving: vacant or blocked per department rule; an extra moves into an opened slot', () => {
    let s = finance()
    const agm = pos(s, 'd-agm', (p) => p.kind === 'planned')
    s = leave(s, agm.id).state                     // after_separation = vacant → an extra moves in
    expect(states(s).extra).toBe(1)
    expect(s.positions.filter((p) => p.grade_id === 'd-agm' && p.kind === 'planned').every((p) => p.employee)).toBe(true)

    let h = hr()                                   // after_separation = blocked
    const exec = pos(h, 'h-ex', (p) => !!p.employee)
    h = leave(h, exec.id).state
    expect(pos(h, 'h-ex', (p) => p.id === exec.id).hold).toBe('blocked')
  })

  it('budget and slots: the hard floor, slots within budget, surplus filled slots turn extra', () => {
    const s = finance()
    expect(applyBudget(s, 24, slots(s, {}), 'vacant').error).toMatch(/slots add up/)
    expect(applyBudget(s, 24, slots(s, { 'd-sr': 4, 'd-jr': 4 }), 'vacant').error).toMatch(/cannot go below 23 filled \+ 2/)
    const r = applyBudget(s, 30, slots(s, { 'd-sr': 4 }), 'vacant')
    expect(r.error).toBeNull()
    const sr = simChart(r.state).grades.find((g) => g.id === 'd-sr')!
    expect(sr.positions.filter((p) => p.kind === 'planned')).toHaveLength(4)
    expect(sr.positions.filter((p) => p.state === 'extra')).toHaveLength(2)
  })

  it('blocking, opening and recruiting an open slot', () => {
    let s = finance()
    const dgm = pos(s, 'd-dgm', (p) => p.hold === 'blocked')
    s = toggleHold(s, dgm.id).state
    expect(states(s).blocked).toBe(2)
    s = startRecruiting(s, 'd-dgm').state
    expect(simChart(s).grades.find((g) => g.id === 'd-dgm')!.positions.filter((p) => p.state === 'in_recruitment')).toHaveLength(1)
    expect(startRecruiting(s, 'd-dgm').error).toMatch(/already being recruited/)
    expect(toggleHold(s, pos(s, 'd-ed', () => true).id).error).toMatch(/empty planned/)
  })
})
