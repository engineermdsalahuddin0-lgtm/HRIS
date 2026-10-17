import { Info } from 'lucide-react'
import type { Payslip, PayslipLine } from '@/lib/payrollRuns'
import { explainLine } from '@/lib/calculationGuide'
import { formatTaka } from '@/lib/payroll'
import { NetFlow, TaxBreakdown } from '@/components/calcVisuals'
import { ReferenceChips, SourceBadge } from '@/components/references'
import { Alert, cx } from '@/components/ui'

function LineExplained({ line }: { line: PayslipLine }) {
  const explained = explainLine(line)
  const negative = line.direction === 'deduction' || line.amount < 0
  return (
    <li className="rounded-xl bg-white p-3 ring-1 ring-slate-200">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-medium text-slate-900">{line.label}</p>
          <p className="mt-0.5 text-xs text-slate-600">{explained.formula}</p>
        </div>
        <div className="flex items-center gap-2">
          <SourceBadge category={explained.source} />
          <span className={cx('text-sm font-semibold tabular-nums', negative ? 'text-red-600' : 'text-slate-900')}>
            {negative ? '−' : '+'}{formatTaka(Math.abs(line.amount))}
          </span>
        </div>
      </div>
      <ReferenceChips keys={explained.referenceKeys} className="mt-2" />
    </li>
  )
}

/**
 * "How was this calculated?": gross -> net flow, every line with its formula
 * and the law or company policy behind it, and the full income-tax working.
 */
export function CalculationExplainer({ payslip }: { payslip: Payslip }) {
  const { slip, lines } = payslip
  const earnings = lines.filter((l) => l.direction === 'earning')
  const deductions = lines.filter((l) => l.direction === 'deduction')
  const tdsLine = lines.find((l) => l.code === 'TDS')
  return (
    <div className="space-y-6">
      <Alert tone="info">
        <span className="inline-flex items-start gap-2">
          <Info className="mt-0.5 size-4 shrink-0" />
          Every amount below shows its formula with the real numbers, and whether it comes from the law, a company
          policy or a company setting. Click a chip to read the rule and its source.
        </span>
      </Alert>

      <section className="grid gap-6 lg:grid-cols-[1fr_1.4fr]">
        <div className="rounded-2xl bg-slate-50 p-4">
          <h3 className="mb-3 text-sm font-semibold text-slate-900">From gross to net</h3>
          <NetFlow gross={slip.gross_earnings} deductions={slip.total_deductions} net={slip.net} employerPf={slip.employer_pf} />
          <dl className="mt-4 grid grid-cols-2 gap-2 text-xs text-slate-600">
            <dt>Daily rate basis</dt><dd className="text-right">monthly ÷ 30</dd>
            <dt>Employed days</dt><dd className="text-right">{slip.employed_days} / 30</dd>
            <dt>Payable days</dt><dd className="text-right">{slip.payable_days}</dd>
            {Number(slip.rounding_adjustment) !== 0 && (<><dt>Rounding</dt><dd className="text-right">{formatTaka(slip.rounding_adjustment)}</dd></>)}
          </dl>
          <ReferenceChips keys={['policy.month_30_days', 'policy.net_rules']} className="mt-3" />
        </div>
        <div className="space-y-4">
          <div>
            <h3 className="mb-2 text-sm font-semibold text-slate-900">Earnings</h3>
            <ul className="space-y-2">{earnings.map((line, i) => <LineExplained key={`${line.code}-${i}`} line={line} />)}</ul>
          </div>
          <div>
            <h3 className="mb-2 text-sm font-semibold text-slate-900">Deductions</h3>
            {deductions.length === 0
              ? <p className="text-sm text-slate-500">No deductions this month.</p>
              : <ul className="space-y-2">{deductions.map((line, i) => <LineExplained key={`${line.code}-${i}`} line={line} />)}</ul>}
          </div>
        </div>
      </section>

      {slip.tax_detail ? (
        <section>
          <h3 className="mb-1 text-sm font-semibold text-slate-900">Income tax working ({slip.tax_detail.fiscal_year})</h3>
          <p className="mb-3 text-xs text-slate-500">
            {tdsLine
              ? 'Tax is deducted every month at the average rate of the estimated yearly tax (projection method).'
              : slip.tax_detail.auto_tds
                ? 'No tax is due this month.'
                : 'Preview only: automatic TDS is switched off, so nothing was deducted. The Admin can switch it on in Statutory settings.'}
          </p>
          {!slip.tax_detail.has_tin && Number(slip.tax_detail.annual_tax) > 0 && (
            <div className="mb-3"><Alert>Tax is due but no TIN is on record for this employee.</Alert></div>
          )}
          <TaxBreakdown detail={slip.tax_detail} />
        </section>
      ) : (
        <p className="text-sm text-slate-500">No income-tax working for this month (no tax table for the period).</p>
      )}
    </div>
  )
}
