import { describe, expect, it } from 'vitest'
import { hhmm, minutesToHm, monthBounds, STATUS_STYLE } from '@/lib/time'

describe('minutesToHm', () => {
  it('formats minutes', () => {
    expect(minutesToHm(0)).toBe('0h')
    expect(minutesToHm(null)).toBe('0h')
    expect(minutesToHm(60)).toBe('1h')
    expect(minutesToHm(125)).toBe('2h 5m')
  })
})

describe('monthBounds', () => {
  it('handles 30/31-day months and February', () => {
    expect(monthBounds('2026-03')).toEqual({ from: '2026-03-01', to: '2026-03-31' })
    expect(monthBounds('2026-04')).toEqual({ from: '2026-04-01', to: '2026-04-30' })
    expect(monthBounds('2026-02')).toEqual({ from: '2026-02-01', to: '2026-02-28' })
    expect(monthBounds('2028-02')).toEqual({ from: '2028-02-01', to: '2028-02-29' })
  })
})

describe('hhmm', () => {
  it('trims seconds from Postgres time', () => {
    expect(hhmm('09:00:00')).toBe('09:00')
    expect(hhmm(null)).toBe('—')
  })
})

describe('STATUS_STYLE', () => {
  it('has a label for every attendance status the database can return', () => {
    for (const s of ['present', 'late', 'absent', 'half_day', 'early_out', 'on_leave', 'weekend', 'holiday'] as const) {
      expect(STATUS_STYLE[s].label).toBeTruthy()
    }
  })
})
