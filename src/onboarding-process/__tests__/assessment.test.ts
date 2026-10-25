import { describe, expect, it } from 'vitest'
import { clock, isoToZoned, scoreObjective, writtenPercent, zonedToIso } from '@/onboarding-process/core/assessment'

// The objective paper of recruit_r4_tests_interviews_test.sql.
const PAPER = [
  { position: 1, section: 'job_knowledge' as const, marks: 1, correct_index: 0 },
  { position: 2, section: 'aptitude' as const, marks: 2, correct_index: 1 },
  { position: 3, section: 'language' as const, marks: 2, correct_index: 2 },
]

describe('objective scoring (same numbers as the SQL test)', () => {
  it('Rahim: A, A, C -> 3 / 5 = 60.0 %, pass at 50', () => {
    const r = scoreObjective(PAPER, { 1: 0, 2: 0, 3: 2 }, 50)
    expect([r.score, r.total, r.percent, r.answered, r.correct, r.passed]).toEqual([3, 5, 60, 3, 2, true])
    expect(r.sections.job_knowledge?.percent).toBe(100)
    expect(r.sections.aptitude?.percent).toBe(0)
    expect(r.sections.language?.percent).toBe(100)
  })
  it('Karim: only Q2 = B, time up -> 2 / 5 = 40.0 %, fail', () => {
    const r = scoreObjective(PAPER, { 2: 1 }, 50)
    expect([r.score, r.percent, r.answered, r.passed]).toEqual([2, 40, 1, false])
  })
  it('no pass mark -> passed is null', () => {
    expect(scoreObjective(PAPER, {}, null).passed).toBeNull()
  })
})

describe('written, clock and time zones', () => {
  it('7 of 10 = 70.0 %', () => expect(writtenPercent([7], 10)).toBe(70))
  it('formats the timer', () => {
    expect(clock(1200)).toBe('20:00')
    expect(clock(65)).toBe('01:05')
    expect(clock(3725)).toBe('1:02:05')
    expect(clock(-3)).toBe('00:00')
  })
  it('converts Dhaka local time (UTC+6) both ways', () => {
    expect(zonedToIso('2026-11-02', '10:00', 'Asia/Dhaka')).toBe('2026-11-02T04:00:00.000Z')
    expect(isoToZoned('2026-11-02T04:45:00Z', 'Asia/Dhaka')).toEqual({ date: '2026-11-02', time: '10:45' })
  })
})
