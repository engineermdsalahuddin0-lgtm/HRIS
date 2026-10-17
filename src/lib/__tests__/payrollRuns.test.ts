import { describe, expect, it } from 'vitest'
import { csvCell, formatPeriod, toCsv } from '@/lib/payrollRuns'
import { formatMoney, formatNumber, lineLabel } from '@/lib/payslipText'

describe('csvCell', () => {
  it('quotes commas, quotes and new lines', () => {
    expect(csvCell('Rahim, Uddin')).toBe('"Rahim, Uddin"')
    expect(csvCell('say "hi"')).toBe('"say ""hi"""')
    expect(csvCell('two\nlines')).toBe('"two\nlines"')
  })
  it('neutralises spreadsheet formulas in text cells', () => {
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`)
    expect(csvCell('+8801711000000')).toBe("'+8801711000000")
    expect(csvCell('@SUM(A1)')).toBe("'@SUM(A1)")
  })
  it('keeps numbers and empty values as they are', () => {
    expect(csvCell(-120.5)).toBe('-120.5')
    expect(csvCell(null)).toBe('')
  })
  it('builds rows with CRLF', () => {
    expect(toCsv(['a', 'b'], [[1, 'x']])).toBe('a,b\r\n1,x')
  })
})

describe('payslip text', () => {
  it('formats taka in English and Bangla digits', () => {
    expect(formatMoney('en', 21450)).toBe('৳21,450.00')
    expect(formatMoney('bn', 21450)).toBe('৳২১,৪৫০.০০')
    expect(formatNumber('bn', 30)).toBe('৩০')
  })
  it('translates fixed line types but keeps component names', () => {
    expect(lineLabel('bn', 'absence', 'Absent days')).toBe('অনুপস্থিতি')
    expect(lineLabel('bn', 'earning', 'House Rent')).toBe('House Rent')
    expect(lineLabel('en', 'bonus', 'Eid bonus')).toBe('Eid bonus')
  })
  it('names the payroll month', () => {
    expect(formatPeriod('2026-03-01')).toBe('March 2026')
  })
})
