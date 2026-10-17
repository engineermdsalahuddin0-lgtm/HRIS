// Explains payroll numbers in plain language: for every payslip line the
// formula with the real numbers, and the law / company policy it comes from
// (keys of the statutory_references library). Pure functions, unit-tested.
import type { PayslipLine } from '@/lib/payrollRuns'
import type { GratuityBand, ReferenceCategory, TaxDetail, VestingBand } from '@/lib/statutory'

const amount = (value: number | null | undefined, digits = 2) =>
  Number(value ?? 0).toLocaleString('en-IN', { minimumFractionDigits: 0, maximumFractionDigits: digits })
const taka = (value: number | null | undefined) => `৳${amount(value)}`

export interface LineExplanation {
  /** Formula with the real numbers, e.g. "2 days × ৳333.33 (daily rate) = ৳666.67". */
  formula: string
  /** Where the rule comes from: the law, a company policy or a company setting. */
  source: ReferenceCategory
  referenceKeys: string[]
}

/** How one payslip line was calculated, and which rule it follows. */
export function explainLine(line: PayslipLine): LineExplanation {
  const result = taka(Math.abs(line.amount))
  switch (line.line_type) {
    case 'earning':
    case 'component_deduction':
      return {
        formula: `${line.label} from the employee's salary structure = ${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.salary_structure'],
      }
    case 'proration':
      return {
        formula: `${taka(line.base)} gross × ${amount(line.quantity)} days not employed ÷ 30 = −${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.month_30_days'],
      }
    case 'overtime':
      return {
        formula: `${amount(line.quantity)} h × ${taka(line.base)} hourly rate × ${amount(line.rate)} = ${result}`,
        source: 'law',
        referenceKeys: ['labour.overtime'],
      }
    case 'bonus':
      return {
        formula: line.rate !== null && line.rate !== undefined
          ? `${taka(line.base)} × ${amount(line.rate)}% = ${result}`
          : `Fixed bonus = ${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.bonus'],
      }
    case 'arrear':
      return {
        formula: `Pay difference of a back-dated increment for ${amount(line.quantity)} paid month(s), on the 30-day basis = ${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.month_30_days'],
      }
    case 'adjustment':
      return { formula: `Approved adjustment: ${line.label} = ${result}`, source: 'company_policy', referenceKeys: [] }
    case 'absence':
    case 'unpaid_leave':
    case 'unpaid_off_day':
      return {
        formula: `${amount(line.quantity)} day(s) × ${taka(line.base)} daily rate (monthly ÷ 30) = ${result}`,
        source: 'law',
        referenceKeys: ['labour.absence_deduction', 'policy.deduction_base', 'policy.month_30_days'],
      }
    case 'half_day':
      return {
        formula: `${amount(line.quantity)} half day(s) × ${taka(line.base)} daily rate × ${amount(line.rate)}% = ${result}`,
        source: 'company_setting',
        referenceKeys: ['policy.deduction_base', 'policy.month_30_days'],
      }
    case 'late':
      return {
        formula: line.label.includes('lates') && line.base !== null && Number(line.quantity) > 0
          ? `${line.label}: ${amount(line.quantity)} × ${taka(line.base)} = ${result}`
          : `Late penalty = ${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.late_deduction'],
      }
    case 'loan':
      return {
        formula: `Installment (never more than the ${taka(line.base)} left) = ${result}`,
        source: 'company_policy',
        referenceKeys: ['policy.loans'],
      }
    case 'carry_forward':
      return { formula: `Shortfall carried from last month = ${result}`, source: 'company_setting', referenceKeys: ['policy.net_rules'] }
    case 'pf':
      return {
        formula: `${taka(line.base)} PF basis × ${amount(line.rate)}% = ${result} (the employer adds its own share)`,
        source: 'law',
        referenceKeys: ['labour.provident_fund', 'policy.pf_rules'],
      }
    case 'tax':
      return {
        formula: `(${taka(line.base)} tax still due this year) ÷ ${amount(line.quantity, 0)} month(s) left = ${result}`,
        source: 'law',
        referenceKeys: ['tax.tds_salary', 'tax.slabs'],
      }
    default:
      return { formula: `${line.label} = ${result}`, source: 'company_policy', referenceKeys: [] }
  }
}

export interface TaxStep {
  key: string
  label: string
  /** Signed effect on the running figure (income steps, then tax steps). */
  value: number
  note: string
  referenceKey?: string
}

/** The annual tax working as an ordered list of steps (for lists and charts). */
export function taxSteps(detail: TaxDetail): TaxStep[] {
  const steps: TaxStep[] = []
  if (detail.projection) {
    const p = detail.projection
    steps.push({
      key: 'projected', label: 'Projected income for the year', value: p.projected_income,
      note: `${taka(p.ytd_income)} paid so far + ${taka(p.this_month)} this month + ${taka(p.regular_monthly)} × ${p.future_months} month(s) to come`,
      referenceKey: 'tax.tds_salary',
    })
  } else {
    steps.push({ key: 'income', label: 'Annual income', value: detail.annual_income, note: 'As entered' })
  }
  steps.push({
    key: 'exempt', label: 'Exempt part', value: -detail.exempt,
    note: `Lower of income ÷ ${amount(detail.exempt_rule.divisor)} and ${taka(detail.exempt_rule.cap)}`,
    referenceKey: 'tax.salary_exemption',
  })
  steps.push({ key: 'taxable', label: 'Taxable income', value: detail.taxable_income, note: 'Income − exempt part' })
  steps.push({
    key: 'gross_tax', label: 'Tax by slabs', value: detail.gross_tax,
    note: `First ${taka(detail.threshold)} tax-free, then the slab rates`, referenceKey: 'tax.slabs',
  })
  steps.push({
    key: 'rebate', label: 'Investment rebate', value: -detail.rebate.applied,
    note: `Lowest of ${detail.rebate.income_percent}% of taxable income (${taka(detail.rebate.by_income)}), `
      + `${detail.rebate.investment_percent}% of ${taka(detail.investment)} investment (${taka(detail.rebate.by_investment)}) `
      + `and ${taka(detail.rebate.cap)}`,
    referenceKey: 'tax.investment_rebate',
  })
  if (detail.minimum_tax > detail.tax_after_rebate) {
    steps.push({
      key: 'minimum', label: 'Raised to the minimum tax', value: detail.minimum_tax - detail.tax_after_rebate,
      note: `Income is above the threshold, so at least ${taka(detail.minimum_tax)}`, referenceKey: 'tax.minimum_tax',
    })
  }
  steps.push({ key: 'annual', label: 'Tax for the year', value: detail.annual_tax, note: '' })
  if (detail.ytd_tds !== undefined && detail.monthly_tds !== undefined && detail.projection) {
    steps.push({
      key: 'monthly', label: 'TDS this month', value: detail.monthly_tds,
      note: `(${taka(detail.annual_tax)} − ${taka(detail.ytd_tds)} already deducted) ÷ ${detail.projection.months_remaining} month(s)`,
      referenceKey: 'tax.tds_salary',
    })
  }
  return steps
}

/** "Tk 0 – 400,000" style label for a band. */
export function bandLabel(from: number, to: number | null): string {
  return to === null ? `Above ${taka(from)}` : `${taka(from)} – ${taka(to)}`
}

/** Effective (average) tax rate in percent, 2 decimals. */
export function effectiveRate(annualTax: number, income: number): number {
  if (!income) return 0
  return Math.round((annualTax / income) * 10000) / 100
}

/** Vested employer share for completed years (highest band reached). */
export function vestedPercent(vesting: VestingBand[], years: number): number {
  return [...vesting].sort((a, b) => b.min_years - a.min_years).find((band) => band.min_years <= years)?.percent ?? 0
}

/** Gratuity days per year for counted years (the highest band reached applies to all years). */
export function gratuityDays(bands: GratuityBand[], countedYears: number): number {
  return [...bands].sort((a, b) => b.min_years - a.min_years).find((band) => band.min_years <= countedYears)?.days ?? 0
}

/** Weighted score of a review: sum(score × weight) / sum(weight of scored criteria), 2 decimals. */
export function weightedScore(criteria: { weight: number; score: number | null }[]): number | null {
  const scored = criteria.filter((c) => c.score !== null)
  const weight = scored.reduce((sum, c) => sum + Number(c.weight), 0)
  if (!weight) return null
  return Math.round((scored.reduce((sum, c) => sum + Number(c.score) * Number(c.weight), 0) / weight) * 100) / 100
}

/** Same bands as the database (company policy). */
export function ratingFor(score: number | null): string | null {
  if (score === null) return null
  if (score >= 4.5) return 'Outstanding'
  if (score >= 3.5) return 'Exceeds expectations'
  if (score >= 2.5) return 'Meets expectations'
  if (score >= 1.5) return 'Needs improvement'
  return 'Unsatisfactory'
}
