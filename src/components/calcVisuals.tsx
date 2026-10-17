// Visual explanations of payroll calculations: the tax working as a step
// list with bars, the slab bands as a stacked bar, and a gross -> net flow.
// Plain HTML bars (no chart library) so they print and scale to phones.
import { ArrowDown, ArrowRight } from 'lucide-react'
import type { TaxDetail } from '@/lib/statutory'
import { bandLabel, effectiveRate, taxSteps } from '@/lib/calculationGuide'
import { formatTaka } from '@/lib/payroll'
import { ReferenceChips } from '@/components/references'
import { cx } from '@/components/ui'

const BAND_COLORS = ['bg-slate-200', 'bg-amber-200', 'bg-amber-300', 'bg-orange-400', 'bg-orange-500', 'bg-red-500', 'bg-red-700']

/** Taxable income split into the slab bands, with the tax of each band. */
export function SlabBar({ detail }: { detail: TaxDetail }) {
  const total = Math.max(detail.taxable_income, 1)
  const bands = detail.bands.filter((b) => b.amount_in_band > 0)
  return (
    <div>
      <div className="flex h-7 w-full overflow-hidden rounded-lg ring-1 ring-slate-200" role="img"
        aria-label={`Taxable income ${formatTaka(detail.taxable_income)} split into tax bands`}>
        {bands.map((band, index) => (
          <div key={band.from} title={`${bandLabel(band.from, band.to)} at ${band.rate}%`}
            className={cx('flex items-center justify-center text-[10px] font-semibold text-slate-900', BAND_COLORS[index] ?? 'bg-red-800')}
            style={{ width: `${(band.amount_in_band / total) * 100}%` }}>
            {band.amount_in_band / total > 0.08 ? `${band.rate}%` : ''}
          </div>
        ))}
      </div>
      <table className="mt-3 w-full text-xs">
        <thead className="text-slate-500">
          <tr><th className="pb-1 text-left font-medium">Band</th><th className="pb-1 text-right font-medium">Rate</th>
            <th className="pb-1 text-right font-medium">Income in band</th><th className="pb-1 text-right font-medium">Tax</th></tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {detail.bands.map((band, index) => (
            <tr key={band.from} className={band.amount_in_band > 0 ? 'text-slate-800' : 'text-slate-400'}>
              <td className="py-1">
                <span className={cx('mr-1.5 inline-block size-2.5 rounded-sm align-middle', BAND_COLORS[index] ?? 'bg-red-800')} />
                {index === 0 ? `Tax-free (first ${formatTaka(band.to)})` : bandLabel(band.from, band.to)}
              </td>
              <td className="py-1 text-right">{band.rate}%</td>
              <td className="py-1 text-right tabular-nums">{formatTaka(band.amount_in_band)}</td>
              <td className="py-1 text-right tabular-nums">{formatTaka(band.tax)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

/** The annual tax working, step by step, each with its rule. */
export function TaxBreakdown({ detail, showMonthly = true }: { detail: TaxDetail; showMonthly?: boolean }) {
  const steps = taxSteps(detail).filter((s) => showMonthly || s.key !== 'monthly')
  const incomeMax = Math.max(detail.projection?.projected_income ?? detail.annual_income, 1)
  const taxMax = Math.max(detail.gross_tax, detail.annual_tax, 1)
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <Kpi label="Taxable income" value={formatTaka(detail.taxable_income)} />
        <Kpi label={`Tax for ${detail.fiscal_year}`} value={formatTaka(detail.annual_tax)}
          hint={`Effective rate ${effectiveRate(detail.annual_tax, detail.projection?.projected_income ?? detail.annual_income)}%`} />
        {detail.monthly_tds !== undefined && (
          <Kpi label="Monthly TDS" value={formatTaka(detail.monthly_tds)} accent />
        )}
      </div>

      <ol className="space-y-2">
        {steps.map((step, index) => {
          const isTax = ['gross_tax', 'rebate', 'minimum', 'annual', 'monthly'].includes(step.key)
          const max = isTax ? taxMax : incomeMax
          const negative = step.value < 0
          const total = ['taxable', 'annual', 'monthly'].includes(step.key)
          return (
            <li key={step.key} className={cx('rounded-xl p-3 ring-1', total ? 'bg-primary-50/60 ring-primary-100' : 'bg-white ring-slate-200')}>
              <div className="flex flex-wrap items-baseline justify-between gap-2">
                <p className="text-sm font-medium text-slate-900">
                  <span className="mr-2 inline-flex size-5 items-center justify-center rounded-full bg-slate-900 text-[10px] text-white">{index + 1}</span>
                  {step.label}
                </p>
                <p className={cx('text-sm font-semibold tabular-nums', negative ? 'text-green-700' : 'text-slate-900')}>
                  {negative ? '−' : step.key === 'minimum' ? '+' : ''}{formatTaka(Math.abs(step.value))}
                </p>
              </div>
              <div className="mt-2 h-2 w-full rounded-full bg-slate-100">
                <div className={cx('h-2 rounded-full', negative ? 'bg-green-500' : isTax ? 'bg-primary-500' : 'bg-sky-500')}
                  style={{ width: `${Math.min(100, (Math.abs(step.value) / max) * 100)}%` }} />
              </div>
              {step.note && <p className="mt-1.5 text-xs text-slate-500">{step.note}</p>}
              {step.referenceKey && <ReferenceChips keys={[step.referenceKey]} className="mt-1.5" />}
            </li>
          )
        })}
      </ol>

      <div className="rounded-xl bg-white p-4 ring-1 ring-slate-200">
        <p className="mb-2 text-sm font-medium text-slate-900">How the taxable income is split into slabs</p>
        <SlabBar detail={detail} />
      </div>
    </div>
  )
}

function Kpi({ label, value, hint, accent }: { label: string; value: string; hint?: string; accent?: boolean }) {
  return (
    <div className={cx('rounded-xl p-3 ring-1', accent ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white ring-slate-200')}>
      <p className={cx('text-xs', accent ? 'text-primary-100' : 'text-slate-500')}>{label}</p>
      <p className="mt-0.5 text-lg font-semibold tabular-nums">{value}</p>
      {hint && <p className={cx('text-xs', accent ? 'text-primary-100' : 'text-slate-500')}>{hint}</p>}
    </div>
  )
}

/** Gross -> deductions -> net as proportional bars. */
export function NetFlow({ gross, deductions, net, employerPf }: { gross: number; deductions: number; net: number; employerPf?: number }) {
  const max = Math.max(gross, 1)
  const row = (label: string, value: number, color: string) => (
    <div>
      <div className="flex justify-between text-xs text-slate-600"><span>{label}</span><span className="tabular-nums">{formatTaka(value)}</span></div>
      <div className="mt-1 h-3 w-full rounded-full bg-slate-100">
        <div className={cx('h-3 rounded-full', color)} style={{ width: `${Math.min(100, (value / max) * 100)}%` }} />
      </div>
    </div>
  )
  return (
    <div className="space-y-2" role="img" aria-label={`Gross ${formatTaka(gross)} minus deductions ${formatTaka(deductions)} equals net ${formatTaka(net)}`}>
      {row('Gross earnings', gross, 'bg-sky-500')}
      <div className="flex justify-center text-slate-400"><ArrowDown className="size-4" /></div>
      {row('Deductions', deductions, 'bg-red-400')}
      <div className="flex justify-center text-slate-400"><ArrowDown className="size-4" /></div>
      {row('Net pay', net, 'bg-green-500')}
      {employerPf !== undefined && employerPf > 0 && (
        <p className="flex items-center gap-1 pt-1 text-xs text-slate-500">
          <ArrowRight className="size-3" />Employer also puts {formatTaka(employerPf)} into the provident fund (not taken from pay).
        </p>
      )}
    </div>
  )
}
