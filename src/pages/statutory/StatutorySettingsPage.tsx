import { useEffect, useState } from 'react'
import { Plus, Trash2, TriangleAlert } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import type { GratuitySettings, PfSettings } from '@/lib/statutory'
import { useStatutoryAction, useStatutorySettings } from '@/lib/statutory'
import { ReferenceChips } from '@/components/references'
import { Alert, Button, Card, Input, PageLoader } from '@/components/ui'
import { Checkbox, PageHeader, Select, Switch } from '@/components/kit'

const num = (value: string) => (value.trim() === '' || Number.isNaN(Number(value)) ? NaN : Number(value))

/** Switches and values for TDS, provident fund and gratuity, each next to the rule it follows. */
export default function StatutorySettingsPage() {
  const settings = useStatutorySettings()
  const save = useStatutoryAction<{ p: Record<string, unknown> }>('save_statutory_settings')
  const [autoTds, setAutoTds] = useState(false)
  const [minimumTax, setMinimumTax] = useState(true)
  const [pfEnabled, setPfEnabled] = useState(false)
  const [gratuityEnabled, setGratuityEnabled] = useState(false)
  const [pf, setPf] = useState<PfSettings | null>(null)
  const [gratuity, setGratuity] = useState<GratuitySettings | null>(null)
  const [confirmed, setConfirmed] = useState(false)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    if (!settings.data) return
    setAutoTds(settings.data.switches.auto_tds)
    setMinimumTax(settings.data.switches.tds_apply_minimum_tax)
    setPfEnabled(settings.data.switches.pf_enabled)
    setGratuityEnabled(settings.data.switches.gratuity_enabled)
    setPf(settings.data.pf)
    setGratuity(settings.data.gratuity)
  }, [settings.data])

  if (settings.isPending || !pf || !gratuity) return settings.isError ? <Alert>{errorMessage(settings.error)}</Alert> : <PageLoader />
  const canEdit = settings.data?.can_edit ?? false
  const anyOn = autoTds || pfEnabled || gratuityEnabled
  const invalid = [pf.employee_rate, pf.employer_rate, pf.interest_rate, pf.min_service_months, gratuity.min_service_months,
    gratuity.partial_year_months].some((v) => Number.isNaN(Number(v)))
    || pf.vesting.some((b) => Number.isNaN(Number(b.min_years)) || Number.isNaN(Number(b.percent)))
    || gratuity.bands.length === 0 || gratuity.bands.some((b) => Number.isNaN(Number(b.min_years)) || Number.isNaN(Number(b.days)))

  const submit = () => {
    setSaved(false)
    save.mutate({ p: {
      auto_tds: autoTds, tds_apply_minimum_tax: minimumTax, pf_enabled: pfEnabled, gratuity_enabled: gratuityEnabled,
      confirm: confirmed, pf, gratuity,
    } }, { onSuccess: () => { setSaved(true); setConfirmed(false) } })
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="Statutory settings" description="Income tax, provident fund and gratuity. Each value sits next to the law it must follow." />
      <Alert tone="info">
        <span className="flex gap-2"><TriangleAlert className="mt-0.5 size-4 shrink-0" />
          Tax tables are loaded from the Finance Act and are the same for every company. PF and gratuity values below are
          your company's rules: check them with your legal or tax adviser before switching them on.</span>
      </Alert>
      {!canEdit && <Alert tone="info">Only the Admin (or a role with payroll settings) can change these values.</Alert>}

      <Card className="space-y-4">
        <Row title="Deduct income tax (TDS) automatically" hint="Off: payroll shows a TDS preview only. On: a TDS line is added to every slip that owes tax."
          control={<Switch label="Automatic TDS" checked={autoTds} onChange={setAutoTds} disabled={!canEdit} />} />
        <Row title="Apply the minimum tax" hint="When income is above the threshold, tax is at least the minimum."
          control={<Switch label="Apply minimum tax" checked={minimumTax} onChange={setMinimumTax} disabled={!canEdit} />} />
        <ReferenceChips keys={['tax.tds_salary', 'tax.minimum_tax']} />
        {settings.data?.switches.tds_confirmed_at && <p className="text-xs text-slate-500">Last confirmed {formatDateTime(settings.data.switches.tds_confirmed_at)}</p>}
      </Card>

      <Card className="space-y-4">
        <Row title="Provident fund" hint="Employee share is deducted; employer share is a company cost posted to the PF ledger."
          control={<Switch label="Provident fund" checked={pfEnabled} onChange={setPfEnabled} disabled={!canEdit} />} />
        <div className="grid gap-4 sm:grid-cols-3">
          <Input label="Employee rate (%)" inputMode="decimal" value={String(pf.employee_rate)} disabled={!canEdit}
            onChange={(e) => setPf({ ...pf, employee_rate: num(e.target.value) })} />
          <Input label="Employer rate (%)" inputMode="decimal" value={String(pf.employer_rate)} disabled={!canEdit}
            onChange={(e) => setPf({ ...pf, employer_rate: num(e.target.value) })} />
          <Select label="Rate applies to" value={pf.basis} disabled={!canEdit} onChange={(e) => setPf({ ...pf, basis: e.target.value as PfSettings['basis'] })}
            options={[{ value: 'basic', label: 'Basic salary' }, { value: 'gross', label: 'Gross salary' }]} />
          <Input label="Minimum service (months)" inputMode="numeric" value={String(pf.min_service_months)} disabled={!canEdit}
            onChange={(e) => setPf({ ...pf, min_service_months: num(e.target.value) })} />
          <Input label="Yearly interest (%)" inputMode="decimal" value={String(pf.interest_rate)} disabled={!canEdit}
            onChange={(e) => setPf({ ...pf, interest_rate: num(e.target.value) })} />
          <div className="flex items-end pb-2.5">
            <Checkbox label="Recognised fund (counts as tax investment)" checked={pf.is_recognised} disabled={!canEdit}
              onChange={(v) => setPf({ ...pf, is_recognised: v })} />
          </div>
        </div>
        <BandEditor title="Employer share vested on leaving" unit="%" valueKey="percent" disabled={!canEdit}
          bands={pf.vesting} onChange={(vesting) => setPf({ ...pf, vesting })} />
        <ReferenceChips keys={['labour.provident_fund', 'tax.recognised_pf']} />
        {pf.confirmed_at && <p className="text-xs text-slate-500">Last confirmed {formatDateTime(pf.confirmed_at)}</p>}
      </Card>

      <Card className="space-y-4">
        <Row title="Gratuity" hint="Payout on leaving; with provisions on, a monthly provision is posted when payroll is locked."
          control={<Switch label="Gratuity" checked={gratuityEnabled} onChange={setGratuityEnabled} disabled={!canEdit} />} />
        <div className="grid gap-4 sm:grid-cols-3">
          <Select label="Basis" value={gratuity.basis} disabled={!canEdit}
            onChange={(e) => setGratuity({ ...gratuity, basis: e.target.value as GratuitySettings['basis'] })}
            options={[{ value: 'last_basic', label: 'Last basic' }, { value: 'average_last_3_basic', label: 'Average basic, last 3 months' }]} />
          <Input label="Minimum service (months)" inputMode="numeric" value={String(gratuity.min_service_months)} disabled={!canEdit}
            onChange={(e) => setGratuity({ ...gratuity, min_service_months: num(e.target.value) })} />
          <Input label="Part year counts after (months)" inputMode="numeric" value={String(gratuity.partial_year_months)} disabled={!canEdit}
            hint="Law: more than six months = a full year" onChange={(e) => setGratuity({ ...gratuity, partial_year_months: num(e.target.value) })} />
        </div>
        <BandEditor title="Days of basic per counted year (highest band reached applies to all years)" unit="days" valueKey="days"
          disabled={!canEdit} bands={gratuity.bands} onChange={(bands) => setGratuity({ ...gratuity, bands })} />
        <Checkbox label="Post a monthly gratuity provision when payroll is locked" checked={gratuity.provision_enabled} disabled={!canEdit}
          onChange={(v) => setGratuity({ ...gratuity, provision_enabled: v })} />
        <ReferenceChips keys={['labour.gratuity', 'policy.gratuity_rules']} />
        {gratuity.confirmed_at && <p className="text-xs text-slate-500">Last confirmed {formatDateTime(gratuity.confirmed_at)}</p>}
      </Card>

      {canEdit && (
        <Card className="space-y-4">
          <Checkbox checked={confirmed} onChange={setConfirmed}
            label="I confirm these values were checked against the current Bangladesh law (Labour Act / EPZ Labour Act, Income Tax Act and Finance Act) and our fund rules." />
          {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
          {saved && <Alert tone="success">Settings saved. Recalculate open payroll runs to apply them.</Alert>}
          <div className="flex justify-end">
            <Button loading={save.isPending} disabled={invalid || (anyOn && !confirmed)} onClick={submit}>Save settings</Button>
          </div>
          {anyOn && !confirmed && <p className="text-right text-xs text-slate-500">Tick the confirmation to save while a switch is on.</p>}
        </Card>
      )}
    </div>
  )
}

function Row({ title, hint, control }: { title: string; hint: string; control: React.ReactNode }) {
  return (
    <div className="flex items-start justify-between gap-4">
      <div><p className="font-medium text-slate-900">{title}</p><p className="text-sm text-slate-500">{hint}</p></div>
      {control}
    </div>
  )
}

/** Editable list of "from N years -> value" bands. */
function BandEditor<K extends 'percent' | 'days'>({ title, unit, valueKey, bands, onChange, disabled }: {
  title: string; unit: string; valueKey: K; disabled: boolean
  bands: ({ min_years: number } & Record<K, number>)[]; onChange: (bands: ({ min_years: number } & Record<K, number>)[]) => void
}) {
  const update = (index: number, patch: Partial<{ min_years: number } & Record<K, number>>) =>
    onChange(bands.map((band, i) => (i === index ? { ...band, ...patch } : band)))
  return (
    <div>
      <p className="mb-2 text-sm font-medium text-slate-700">{title}</p>
      <div className="space-y-2">
        {bands.map((band, index) => (
          <div key={index} className="flex flex-wrap items-center gap-2 text-sm">
            <span className="text-slate-500">From</span>
            <input aria-label="From years" inputMode="numeric" disabled={disabled} value={String(band.min_years)}
              onChange={(e) => update(index, { min_years: num(e.target.value) } as Partial<{ min_years: number } & Record<K, number>>)}
              className="w-16 rounded-lg border border-slate-300 px-2 py-1.5 text-right" />
            <span className="text-slate-500">year(s):</span>
            <input aria-label={unit} inputMode="decimal" disabled={disabled} value={String(band[valueKey])}
              onChange={(e) => update(index, { [valueKey]: num(e.target.value) } as Partial<{ min_years: number } & Record<K, number>>)}
              className="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-right" />
            <span className="text-slate-500">{unit}</span>
            {!disabled && bands.length > 1 && (
              <button type="button" aria-label="Remove band" onClick={() => onChange(bands.filter((_, i) => i !== index))}
                className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-red-600"><Trash2 className="size-4" /></button>
            )}
          </div>
        ))}
      </div>
      {!disabled && (
        <Button variant="ghost" className="mt-1" onClick={() => onChange([...bands, { min_years: 0, [valueKey]: 0 } as { min_years: number } & Record<K, number>])}>
          <Plus className="size-4" />Add band
        </Button>
      )}
    </div>
  )
}
