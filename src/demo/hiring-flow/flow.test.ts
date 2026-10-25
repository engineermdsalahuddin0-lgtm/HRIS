import { describe, expect, it } from 'vitest'
import { joinOffer, sendOffer, simCounts } from '@/onboarding-process/core/organogramSim'
import { CANDIDATES, accountsOrganogram, defaultShortlist, results, screen, workload } from './flow'

describe('hiring flow demo story', () => {
  it('R1: Accounts is overloaded and the plan has one vacant seat to back-fill', () => {
    const f = workload()
    expect([f.index, f.band, f.backfill_seats, f.new_positions, f.action]).toEqual([1.15, 'overload', 1, 0, 'hire'])
  })

  it('R3: three meet the must-haves, two do not', () => {
    expect(defaultShortlist()).toEqual(['c1', 'c2', 'c3'])
    expect(CANDIDATES.map((c) => screen(c).gate)).toEqual(['pass', 'pass', 'pass', 'fail', 'fail'])
  })

  it('R4–R5: Rahim leads the composite; lowering his interview hands it to Sadia', () => {
    const rows = results(defaultShortlist(), {})
    expect(rows.map((r) => r.c.name)).toEqual(['Rahim Uddin', 'Sadia Islam', 'Karim Ahmed'])
    expect(rows[0].figures.composite).toBeGreaterThan(rows[1].figures.composite!)
    expect(results(defaultShortlist(), { c1: [2.5, 2.5] })[0].c.name).toBe('Sadia Islam')
  })

  it('R6–R7: the offer fits the budget and the joiner fills the recruited slot', () => {
    let s = accountsOrganogram()
    expect(simCounts(s).available).toBe(1)
    s = sendOffer(s, 'f-sr').state
    s = joinOffer(s, s.offers[0].id).state
    expect(simCounts(s)).toMatchObject({ filled: 6, available: 0 })
    expect(s.positions.filter((p) => p.kind === 'extra')).toHaveLength(0)
  })
})
