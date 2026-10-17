import { useMemo, useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { formatTaka } from '@/lib/payroll'
import { formatDate, today } from '@/lib/options'
import { useEmployeeOptions } from '@/lib/hr'
import type { GratuityPreview } from '@/lib/statutory'
import { useGratuityLiability, useGratuityPreview, useStatutorySettings } from '@/lib/statutory'
import { gratuityDays } from '@/lib/calculationGuide'
import { ReferenceChips } from '@/components/references'
import { Alert, Card, EmptyState, Input, PageLoader, Spinner, cx } from '@/components/ui'
import { PageHeader, Select, Table, Tabs, td, th } from '@/components/kit'

/** Gratuity: liability of every active employee, provisions, and the payout calculator. */
export default function GratuityPage() {
  const [tab, setTab] = useState<'liability' | 'calculator'>('calculator')
  const settings = useStatutorySettings()
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Gratuity" description="What each person would receive on leaving, and how it is worked out from the law and company rules." />
      {settings.data && !settings.data.switches.gratuity_enabled && (
        <Alert tone="info">Gratuity is switched off. Calculations still work; provisions are posted only when it is on.</Alert>
      )}
      {settings.data && (
        <Card className="flex flex-wrap items-center gap-x-8 gap-y-3 p-4 text-sm">
          {[...settings.data.gratuity.bands].sort((a, b) => a.min_years - b.min_years).map((band) => (
            <span key={band.min_years}><span className="font-semibold">{band.days} days</span> of basic per year from {band.min_years} counted year(s)</span>
          ))}
          <span>Minimum service {settings.data.gratuity.min_service_months} months</span>
          <ReferenceChips keys={['labour.gratuity', 'policy.gratuity_rules']} />
        </Card>
      )}
      <Tabs tabs={[{ key: 'calculator' as const, label: 'Payout calculator' }, { key: 'liability' as const, label: 'Liability & provisions' }]}
        value={tab} onChange={setTab} />
      {tab === 'calculator' ? <CalculatorTab /> : <LiabilityTab />}
    </div>
  )
}

function CalculatorTab() {
  const employees = useEmployeeOptions()
  const [employeeId, setEmployeeId] = useState('')
  const [leaving, setLeaving] = useState(today())
  const preview = useGratuityPreview(employeeId, leaving)
  return (
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <Card className="h-fit space-y-4">
        <Select label="Employee" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} placeholder="Choose…"
          options={(employees.data ?? []).map((e) => ({ value: e.id, label: `${e.full_name} (${e.card_id})` }))} />
        <Input label="Leaving date" type="date" value={leaving} onChange={(e) => setLeaving(e.target.value)} />
      </Card>
      <div>
        {!employeeId ? <EmptyState title="Choose an employee to see the gratuity" />
          : preview.isPending ? <div className="flex justify-center py-16 text-primary-600"><Spinner /></div>
          : preview.isError ? <Alert>{errorMessage(preview.error)}</Alert>
          : <GratuityWorking preview={preview.data} />}
      </div>
    </div>
  )
}

/** Service timeline (one block per counted year, coloured by band) and the formula. */
export function GratuityWorking({ preview }: { preview: GratuityPreview }) {
  const years = Array.from({ length: Math.max(preview.counted_years, 0) }, (_, i) => i + 1)
  const highBand = preview.days_per_year > Math.min(...preview.bands.map((b) => b.days))
  return (
    <Card className="space-y-5">
      <div>
        <p className="text-sm text-slate-600">
          Service {formatDate(preview.join_date)} – {formatDate(preview.until)}:{' '}
          <span className="font-medium text-slate-900">{preview.service.years} y {preview.service.months} m {preview.service.days} d</span>
        </p>
        <p className="mt-1 text-xs text-slate-500">
          More than {preview.partial_year_months} months beyond whole years counts as one more year → <span className="font-medium">{preview.counted_years} counted year(s)</span>.
        </p>
      </div>
      {years.length > 0 && (
        <div>
          <div className="flex flex-wrap gap-1" role="img" aria-label={`${preview.counted_years} counted years at ${preview.days_per_year} days each`}>
            {years.map((year) => (
              <div key={year} title={`Year ${year}`}
                className={cx('flex h-9 min-w-9 flex-1 items-center justify-center rounded-md text-[11px] font-medium',
                  highBand ? 'bg-primary-500 text-white' : 'bg-sky-500 text-white')}>{year}</div>
            ))}
          </div>
          <p className="mt-2 text-xs text-slate-500">
            {highBand
              ? `Service reached the ${preview.days_per_year}-day band, so every year counts at ${preview.days_per_year} days.`
              : `Each year counts at ${preview.days_per_year} days (bands: ${preview.bands.map((b) => `${b.days} d from ${b.min_years} y`).join(', ')}).`}
          </p>
        </div>
      )}
      {preview.not_eligible_reason ? (
        <Alert tone="info">{preview.not_eligible_reason}. No gratuity is payable.</Alert>
      ) : (
        <div className="rounded-xl bg-slate-50 p-4">
          <p className="text-xs text-slate-500">{preview.basis === 'last_basic' ? 'Last basic' : 'Average basic of the last 3 months'} ÷ 30 × days per year × counted years</p>
          <p className="mt-1 font-mono text-sm text-slate-800">
            {formatTaka(preview.basic)} ÷ 30 × {preview.days_per_year} × {preview.counted_years}
            {' '}= {formatTaka(preview.daily_basic)} × {preview.days_per_year * preview.counted_years} days
          </p>
          <p className="mt-3 flex items-center justify-between rounded-xl bg-primary-600 p-3 font-semibold text-white">
            <span>Gratuity payable</span><span className="tabular-nums">{formatTaka(preview.amount)}</span>
          </p>
        </div>
      )}
      <ReferenceChips keys={preview.references} />
    </Card>
  )
}

function LiabilityTab() {
  const liability = useGratuityLiability()
  const settings = useStatutorySettings()
  const rows = liability.data ?? []
  const totals = useMemo(() => rows.reduce((t, r) => ({ liability: t.liability + Number(r.liability), provisioned: t.provisioned + Number(r.provisioned) }),
    { liability: 0, provisioned: 0 }), [rows])
  if (liability.isPending) return <PageLoader />
  if (liability.isError) return <Alert>{errorMessage(liability.error)}</Alert>
  const max = Math.max(...rows.map((r) => Number(r.liability)), 1)
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <Card className="p-4"><p className="text-xs text-slate-500">Liability if everyone left today</p><p className="mt-1 text-xl font-semibold">{formatTaka(totals.liability)}</p></Card>
        <Card className="p-4"><p className="text-xs text-slate-500">Provisions posted</p><p className="mt-1 text-xl font-semibold">{formatTaka(totals.provisioned)}</p></Card>
        <Card className="p-4"><p className="text-xs text-slate-500">Not yet provided</p><p className="mt-1 text-xl font-semibold text-primary-700">{formatTaka(Math.max(totals.liability - totals.provisioned, 0))}</p></Card>
      </div>
      <Table minWidth={760} head={
        <tr><th className={th}>Employee</th><th className={th}>Counted years</th><th className={`${th} text-right`}>Basic</th>
          <th className={th}>Liability</th><th className={`${th} text-right`}>Provisioned</th></tr>
      }>
        {rows.map((row) => (
          <tr key={row.employee_id}>
            <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p>
              <p className="text-xs text-slate-400">joined {formatDate(row.join_date)}</p></td>
            <td className={td}>{row.counted_years} × {row.days_per_year || (settings.data ? gratuityDays(settings.data.gratuity.bands, row.counted_years) : 0)} d</td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.basic)}</td>
            <td className={td}>
              <div className="flex items-center gap-2">
                <div className="h-2 w-24 rounded-full bg-slate-100"><div className="h-2 rounded-full bg-primary-500" style={{ width: `${(Number(row.liability) / max) * 100}%` }} /></div>
                <span className="tabular-nums">{formatTaka(row.liability)}</span>
              </div>
            </td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.provisioned)}</td>
          </tr>
        ))}
      </Table>
    </div>
  )
}
