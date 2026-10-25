// One department's workload: index gauge, the figures with (?) explanations,
// and the suggestion. Used by the live dashboard, the vacancy dialog and the demo.
import type { ReactNode } from 'react'
import type { Band } from '@/onboarding-process/core/types'
import type { ExplainKey, ExplainSource } from '@/onboarding-process/core/explain'
import { explain } from '@/onboarding-process/core/explain'
import { BAND_LABEL, METHOD_LABEL, suggestionText } from '@/onboarding-process/core/workload'
import { InfoTip } from '@/components/InfoTip'
import { formatTaka } from '@/lib/payroll'
import { cx } from '@/components/ui'

export const BAND_STYLE: Record<Band, { badge: string; bar: string }> = {
  critical:    { badge: 'bg-red-100 text-red-700',       bar: 'bg-red-500' },
  overload:    { badge: 'bg-primary-100 text-primary-700', bar: 'bg-primary-500' },
  watch:       { badge: 'bg-amber-100 text-amber-800',   bar: 'bg-amber-400' },
  balanced:    { badge: 'bg-green-100 text-green-700',   bar: 'bg-green-500' },
  underloaded: { badge: 'bg-sky-100 text-sky-700',       bar: 'bg-sky-400' },
}

export function BandBadge({ band }: { band: Band }) {
  return <span className={cx('inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium', BAND_STYLE[band].badge)}>{BAND_LABEL[band]}</span>
}

const num = (value: number | null | undefined, digits = 2) =>
  value === null || value === undefined ? '—' : Number(value).toLocaleString('en-US', { maximumFractionDigits: digits })

/** Index on a 0–1.5 scale with the band limits marked. */
export function IndexGauge({ figures }: { figures: ExplainSource }) {
  const scale = 1.5
  const position = Math.min((figures.index ?? scale) / scale, 1) * 100
  const marks = [figures.bands.underload, figures.bands.watch, figures.bands.overload, figures.bands.critical]
  return (
    <div className="relative mt-2 h-2.5 rounded-full bg-slate-100" aria-hidden>
      <div className={cx('h-2.5 rounded-full', BAND_STYLE[figures.band].bar)} style={{ width: `${position}%` }} />
      {marks.map((mark) => (
        <span key={mark} className="absolute top-[-3px] h-4 w-px bg-slate-400/70" style={{ left: `${(mark / scale) * 100}%` }} />
      ))}
    </div>
  )
}

function Metric({ label, value, tip, f, align }: { label: string; value: ReactNode; tip?: ExplainKey; f: ExplainSource; align?: 'right' }) {
  return (
    <div className="min-w-0">
      <dt className="flex items-center gap-1 text-xs text-slate-500">{label}{tip && <InfoTip explanation={explain(tip, f)} align={align} />}</dt>
      <dd className="mt-0.5 font-semibold tabular-nums text-slate-900">{value}</dd>
    </div>
  )
}

export function WorkloadCard({ name, figures, footer, header }: {
  name: string; figures: ExplainSource; footer?: ReactNode; header?: ReactNode
}) {
  const f = figures
  return (
    <div className="space-y-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="truncate font-semibold text-slate-900">{name}</p>
          <p className="text-xs text-slate-500">{METHOD_LABEL[f.method ?? 'hours']}</p>
        </div>
        <div className="flex shrink-0 items-center gap-2">{header}<BandBadge band={f.band} /></div>
      </div>
      <div>
        <div className="flex items-end justify-between">
          <span className="flex items-center gap-1 text-xs text-slate-500">Workload index <InfoTip explanation={explain('index', f)} /></span>
          <span className="flex items-center gap-1 text-2xl font-bold tabular-nums text-slate-900">
            {f.index === null ? '—' : num(f.index, 3)}<InfoTip explanation={explain('band', f)} align="right" />
          </span>
        </div>
        <IndexGauge figures={f} />
      </div>
      <dl className="grid grid-cols-3 gap-x-3 gap-y-2 text-sm">
        <Metric label="Demand" value={`${num(f.demand_hours)} h`} tip="demand" f={f} />
        <Metric label="Capacity / person" value={`${num(f.capacity_per_fte)} h`} tip="capacity" f={f} />
        <Metric label="Active / sanctioned" value={`${f.active} / ${f.sanctioned}`} tip="vacancy" f={f} align="right" />
        <Metric label="People needed" value={num(f.required_fte)} tip="required" f={f} />
        <Metric label="Gap" value={f.gap > 0 ? `+${num(f.gap)}` : num(f.gap)} tip="gap" f={f} />
        <Metric label="Attrition 3m" value={f.attrition_percent === null ? '—' : `${num(f.attrition_percent, 1)} %`} tip="attrition" f={f} align="right" />
      </dl>
      <div className={cx('rounded-xl px-3 py-2 text-sm', f.seats_total > 0 ? 'bg-primary-50 text-primary-800' : 'bg-slate-50 text-slate-700')}>
        <p className="font-medium">{suggestionText(f)}</p>
        <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1 text-xs">
          <span className="inline-flex items-center gap-1">Backfill {f.backfill_seats}<InfoTip explanation={explain('backfill', f)} /></span>
          <span className="inline-flex items-center gap-1">New {f.new_positions}<InfoTip explanation={explain('new_positions', f)} /></span>
          <span className="inline-flex items-center gap-1">Hold {f.hold_seats}<InfoTip explanation={explain('hold', f)} /></span>
          <span className="inline-flex items-center gap-1">
            Budget {f.budget_status === 'unknown' ? 'not checked' : f.budget_status === 'ok' ? 'ok' : `${f.budget_blocked_seats} blocked`}
            {f.cost_per_seat !== undefined && f.budget_status !== 'unknown' ? ` · seat ${formatTaka(f.cost_per_seat)}` : ''}
            <InfoTip explanation={explain('budget', f)} align="right" />
          </span>
        </div>
        {f.attrition_flag && <p className="mt-1 text-xs font-medium text-red-700">High attrition: check why people leave.</p>}
      </div>
      {footer}
    </div>
  )
}
