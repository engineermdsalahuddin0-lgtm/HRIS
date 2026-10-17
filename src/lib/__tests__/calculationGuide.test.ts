import { describe, expect, it } from 'vitest'
import {
  bandLabel, effectiveRate, explainLine, gratuityDays, ratingFor, taxSteps, vestedPercent, weightedScore,
} from '@/lib/calculationGuide'
import type { PayslipLine } from '@/lib/payrollRuns'
import type { TaxDetail } from '@/lib/statutory'

const line = (partial: Partial<PayslipLine>): PayslipLine => ({
  direction: 'deduction', line_type: 'absence', code: 'ABSENCE', label: 'Absent days', base: null, rate: null,
  quantity: null, amount: 0, ...partial,
})

describe('explainLine', () => {
  it('shows absence with the daily rate and links the law', () => {
    const explained = explainLine(line({ base: 333.3333, quantity: 2, amount: 666.67 }))
    expect(explained.formula).toBe('2 day(s) × ৳333.33 daily rate (monthly ÷ 30) = ৳666.67')
    expect(explained.source).toBe('law')
    expect(explained.referenceKeys).toContain('labour.absence_deduction')
  })
  it('explains TDS as tax still due divided by months left', () => {
    const explained = explainLine(line({ line_type: 'tax', code: 'TDS', base: 23250, quantity: 11, amount: 2113.64 }))
    expect(explained.formula).toBe('(৳23,250 tax still due this year) ÷ 11 month(s) left = ৳2,113.64')
    expect(explained.referenceKeys).toEqual(['tax.tds_salary', 'tax.slabs'])
  })
  it('marks the late penalty as company policy', () => {
    expect(explainLine(line({ line_type: 'late', label: '3 lates', base: 200, quantity: 3, amount: 600 })).source).toBe('company_policy')
  })
  it('explains overtime hours × rate × multiplier', () => {
    expect(explainLine(line({ direction: 'earning', line_type: 'overtime', base: 48.0769, rate: 2, quantity: 2, amount: 192.31 })).formula)
      .toBe('2 h × ৳48.08 hourly rate × 2 = ৳192.31')
  })
})

const detail: TaxDetail = {
  fiscal_year: '2026-27', taxpayer_type: 'general', annual_income: 1200000, exempt: 400000,
  exempt_rule: { divisor: 3, cap: 500000 }, taxable_income: 800000, threshold: 400000,
  bands: [], gross_tax: 45000, investment: 340000,
  rebate: { by_income: 24000, income_percent: 3, by_investment: 34000, investment_percent: 10, cap: 750000, applied: 24000 },
  tax_after_rebate: 21000, minimum_tax: 5000, annual_tax: 21000, references: [],
  projection: { ytd_income: 0, this_month: 100000, regular_monthly: 100000, future_months: 11, months_remaining: 12,
                projected_income: 1200000, declared_investment: 100000, pf_investment: 240000 },
  ytd_tds: 0, monthly_tds: 1750,
}

describe('taxSteps', () => {
  it('lists the projection, exemption, slabs, rebate and the monthly TDS', () => {
    const steps = taxSteps(detail)
    expect(steps.map((s) => s.key)).toEqual(['projected', 'exempt', 'taxable', 'gross_tax', 'rebate', 'annual', 'monthly'])
    expect(steps.find((s) => s.key === 'exempt')?.value).toBe(-400000)
    expect(steps.find((s) => s.key === 'monthly')?.note).toBe('(৳21,000 − ৳0 already deducted) ÷ 12 month(s)')
  })
  it('adds the minimum-tax step only when it raises the tax', () => {
    const steps = taxSteps({ ...detail, projection: undefined, gross_tax: 3333.33, tax_after_rebate: 3333.33, annual_tax: 5000,
                             rebate: { ...detail.rebate, applied: 0 } })
    expect(steps.find((s) => s.key === 'minimum')?.value).toBeCloseTo(1666.67)
  })
})

describe('small helpers', () => {
  it('formats band labels and effective rate', () => {
    expect(bandLabel(400000, 700000)).toBe('৳4,00,000 – ৳7,00,000')
    expect(bandLabel(3600000, null)).toBe('Above ৳36,00,000')
    expect(effectiveRate(21000, 1200000)).toBe(1.75)
  })
  it('picks the highest vesting and gratuity band reached', () => {
    const vesting = [{ min_years: 0, percent: 0 }, { min_years: 3, percent: 50 }, { min_years: 5, percent: 100 }]
    expect(vestedPercent(vesting, 2)).toBe(0)
    expect(vestedPercent(vesting, 4)).toBe(50)
    expect(vestedPercent(vesting, 9)).toBe(100)
    const bands = [{ min_years: 1, days: 30 }, { min_years: 11, days: 45 }]
    expect(gratuityDays(bands, 0)).toBe(0)
    expect(gratuityDays(bands, 10)).toBe(30)
    expect(gratuityDays(bands, 13)).toBe(45)
  })
  it('computes the weighted performance score and rating like the database', () => {
    expect(weightedScore([{ weight: 40, score: 5 }, { weight: 30, score: 3 }, { weight: 30, score: 4 }])).toBe(4.1)
    expect(weightedScore([{ weight: 40, score: null }])).toBeNull()
    expect(ratingFor(4.1)).toBe('Exceeds expectations')
    expect(ratingFor(4.5)).toBe('Outstanding')
    expect(ratingFor(1.2)).toBe('Unsatisfactory')
  })
})
