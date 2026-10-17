import { describe, expect, it } from 'vitest'
import type { DraftLine } from '@/lib/payroll'
import { formatMonth, formatTaka, installmentSchedule, parseMoney, previewTemplate } from '@/lib/payroll'

const line = (code: string, calc: DraftLine['calc'], value: number, kind: DraftLine['kind'] = 'earning'): DraftLine =>
  ({ component_id: code, code, name: code, kind, calc, value })

describe('previewTemplate (mirrors private.resolve_salary)', () => {
  it('gives the same golden amounts as the database test', () => {
    // 10,000 + 50% house rent + 750 + 450 + 1,250 = 17,450.00
    const standard = previewTemplate(10000, [
      line('HOUSE_RENT', 'percent_of_basic', 50), line('MEDICAL', 'fixed', 750),
      line('CONVEYANCE', 'fixed', 450), line('FOOD', 'fixed', 1250),
    ])
    expect(standard.valid && standard.gross).toBe(17450)

    // Percent of gross: 30,750 / 0.9 = 34,166.666… -> special 3,416.67, gross 34,166.67
    const withGrossPercent = previewTemplate(20000, [
      line('HOUSE_RENT', 'percent_of_basic', 50), line('MEDICAL', 'fixed', 750), line('SPECIAL', 'percent_of_gross', 10),
    ])
    expect(withGrossPercent.valid && withGrossPercent.lines.find((l) => l.code === 'SPECIAL')?.amount).toBe(3416.67)
    expect(withGrossPercent.valid && withGrossPercent.gross).toBe(34166.67)
  })

  it('rounds half away from zero to paisa', () => {
    const result = previewTemplate(15033.33, [line('HOUSE_RENT', 'percent_of_basic', 50)])
    expect(result.valid && result.lines[0].amount).toBe(7516.67)
  })

  it('keeps deductions out of the gross', () => {
    const result = previewTemplate(10000, [line('STAMP', 'fixed', 10, 'deduction')])
    expect(result.valid && result.gross).toBe(10000)
    expect(result.valid && result.totalDeductions).toBe(10)
  })

  it('refuses percent-of-gross earnings of 100% or more', () => {
    expect(previewTemplate(10000, [line('X', 'percent_of_gross', 100)]).valid).toBe(false)
  })
})

describe('installmentSchedule', () => {
  it('reduces the balance to zero and stops', () => {
    expect(installmentSchedule(10000, 3000, '2026-11')).toEqual([
      { month: '2026-11', amount: 3000, remaining: 7000 },
      { month: '2026-12', amount: 3000, remaining: 4000 },
      { month: '2027-01', amount: 3000, remaining: 1000 },
      { month: '2027-02', amount: 1000, remaining: 0 },
    ])
  })
  it('returns nothing for invalid input', () => {
    expect(installmentSchedule(0, 100, '2026-01')).toEqual([])
    expect(installmentSchedule(100, 0, '2026-01')).toEqual([])
  })
})

describe('parseMoney / formatTaka / formatMonth', () => {
  it('accepts up to two decimals and rejects junk', () => {
    expect(parseMoney('17,450.50')).toBe(17450.5)
    expect(parseMoney('৳ 1000')).toBe(1000)
    expect(parseMoney('-5')).toBeNull()
    expect(parseMoney('1.234')).toBeNull()
    expect(parseMoney('abc')).toBeNull()
  })
  it('formats taka with Bangladeshi grouping', () => {
    expect(formatTaka(1745000)).toBe('৳17,45,000.00')
    expect(formatTaka(null)).toBe('—')
  })
  it('formats months', () => {
    expect(formatMonth('2026-06-01')).toBe('Jun 2026')
  })
})
