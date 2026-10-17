import { useMemo, useState } from 'react'
import { Calculator, Pencil, Receipt } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatTaka, parseMoney } from '@/lib/payroll'
import { formatPeriod } from '@/lib/payrollRuns'
import { formatDate, today } from '@/lib/options'
import { useMyContext } from '@/lib/appContext'
import type { TaxPreviewInput, TaxProfileRow, TaxpayerType } from '@/lib/statutory'
import {
  TAXPAYER_TYPE_LABEL, useStatutoryAction, useTaxPreview, useTaxProfiles, useTaxTables, useTdsLedger,
} from '@/lib/statutory'
import { bandLabel } from '@/lib/calculationGuide'
import { TaxBreakdown } from '@/components/calcVisuals'
import { ReferenceChips } from '@/components/references'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, Spinner } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'

type TabKey = 'calculator' | 'tables' | 'profiles' | 'ledger'

const TYPE_OPTIONS = (Object.keys(TAXPAYER_TYPE_LABEL) as TaxpayerType[]).map((value) => ({ value, label: TAXPAYER_TYPE_LABEL[value] }))

/** Tax & TDS: calculator with the full working, the tax tables with their law, profiles and the TDS ledger. */
export default function TaxPage() {
  const ctx = useMyContext()
  const canViewProfiles = ctx.permissions.includes('tax.view_profiles')
  const tabs = [
    { key: 'calculator' as const, label: 'Calculator' },
    { key: 'tables' as const, label: 'Tax tables' },
    ...(canViewProfiles ? [{ key: 'profiles' as const, label: 'Tax profiles' }, { key: 'ledger' as const, label: 'TDS ledger' }] : []),
  ]
  const [tab, setTab] = useState<TabKey>('calculator')
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Income tax & TDS"
        description="See exactly how tax is worked out from the current law, keep TIN and investment details, and record challans." />
      <Tabs tabs={tabs} value={tab} onChange={setTab} />
      {tab === 'calculator' && <CalculatorTab />}
      {tab === 'tables' && <TablesTab />}
      {tab === 'profiles' && <ProfilesTab canEdit={ctx.permissions.includes('tax.manage')} />}
      {tab === 'ledger' && <LedgerTab canEdit={ctx.permissions.includes('tax.manage')} />}
    </div>
  )
}

function CalculatorTab() {
  const [mode, setMode] = useState<'monthly' | 'annual'>('monthly')
  const [income, setIncome] = useState('100000')
  const [investment, setInvestment] = useState('0')
  const [type, setType] = useState<TaxpayerType>('general')
  const [isNew, setIsNew] = useState(false)
  const [parent, setParent] = useState(false)
  const parsedIncome = parseMoney(income)
  const parsedInvestment = parseMoney(investment || '0')
  const input: TaxPreviewInput | null = parsedIncome === null || parsedInvestment === null ? null : {
    annual_income: mode === 'monthly' ? parsedIncome * 12 : parsedIncome, investment: parsedInvestment,
    taxpayer_type: type, is_new_taxpayer: isNew, parent_of_disabled: parent,
  }
  const preview = useTaxPreview(input)
  return (
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <Card className="h-fit space-y-4">
        <p className="flex items-center gap-2 font-medium text-slate-900"><Calculator className="size-4 text-primary-600" />Your numbers</p>
        <Select label="Income is" value={mode} onChange={(e) => setMode(e.target.value as 'monthly' | 'annual')}
          options={[{ value: 'monthly', label: 'Monthly (× 12)' }, { value: 'annual', label: 'For the whole year' }]} />
        <Input label={mode === 'monthly' ? 'Monthly salary (৳)' : 'Annual salary (৳)'} inputMode="decimal" value={income}
          onChange={(e) => setIncome(e.target.value)} error={parsedIncome === null ? 'Enter an amount' : undefined} />
        <Input label="Eligible investment this year (৳)" inputMode="decimal" value={investment}
          onChange={(e) => setInvestment(e.target.value)} hint="Savings certificates, DPS, life insurance, PF contributions…"
          error={parsedInvestment === null ? 'Enter an amount' : undefined} />
        <Select label="Taxpayer type" value={type} onChange={(e) => setType(e.target.value as TaxpayerType)} options={TYPE_OPTIONS} />
        <Checkbox label="First-time taxpayer" checked={isNew} onChange={setIsNew} />
        <Checkbox label="Parent / guardian of a person with disability" checked={parent} onChange={setParent} />
      </Card>
      <div>
        {!input ? <EmptyState title="Enter your income to see the calculation" />
          : preview.isPending ? <div className="flex justify-center py-16 text-primary-600"><Spinner /></div>
          : preview.isError ? <Alert>{errorMessage(preview.error)}</Alert>
          : <TaxBreakdown detail={preview.data} />}
      </div>
    </div>
  )
}

function TablesTab() {
  const tables = useTaxTables()
  if (tables.isPending) return <PageLoader />
  if (tables.isError) return <Alert>{errorMessage(tables.error)}</Alert>
  if (tables.data.length === 0) return <EmptyState title="No tax tables loaded" />
  return (
    <div className="space-y-6">
      {tables.data.map((year) => {
        let from = year.thresholds.general
        return (
          <Card key={year.id} className="space-y-5">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="text-lg font-semibold text-slate-900">Fiscal year {year.code}</p>
                <p className="text-sm text-slate-500">{formatDate(year.from_date)} – {formatDate(year.to_date)}</p>
              </div>
              <ReferenceChips keys={['tax.slabs', 'tax.thresholds']} />
            </div>
            <div className="grid gap-6 lg:grid-cols-2">
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Tax-free threshold</p>
                <Table minWidth={320} head={<tr><th className={th}>Taxpayer</th><th className={`${th} text-right`}>Tax-free up to</th></tr>}>
                  {(Object.keys(TAXPAYER_TYPE_LABEL) as TaxpayerType[]).map((type) => (
                    <tr key={type}><td className={td}>{TAXPAYER_TYPE_LABEL[type]}</td>
                      <td className={`${td} text-right tabular-nums`}>{formatTaka(year.thresholds[type])}</td></tr>
                  ))}
                </Table>
                <p className="mt-2 text-xs text-slate-500">Parent / guardian of a person with disability: +{formatTaka(year.parent_disabled_extra)}.</p>
              </div>
              <div>
                <p className="mb-2 text-sm font-medium text-slate-700">Rates after the threshold (general taxpayer)</p>
                <Table minWidth={320} head={<tr><th className={th}>Income band</th><th className={`${th} text-right`}>Rate</th></tr>}>
                  <tr><td className={td}>{bandLabel(0, year.thresholds.general)}</td><td className={`${td} text-right`}>0%</td></tr>
                  {year.slabs.map((slab) => {
                    const label = bandLabel(from, slab.width === null ? null : from + Number(slab.width))
                    from += Number(slab.width ?? 0)
                    return <tr key={slab.band_order}><td className={td}>{label}</td><td className={`${td} text-right`}>{slab.rate}%</td></tr>
                  })}
                </Table>
              </div>
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
              <Rule title="Exempt part of salary" text={`Lower of income ÷ ${year.salary_exempt_divisor} and ${formatTaka(year.salary_exempt_cap)}`} refKey="tax.salary_exemption" />
              <Rule title="Investment rebate" text={`Lowest of ${year.rebate_income_percent}% of taxable income, ${year.rebate_investment_percent}% of investment, ${formatTaka(year.rebate_cap)}`} refKey="tax.investment_rebate" />
              <Rule title="Minimum tax" text={`${formatTaka(year.minimum_tax)} (new taxpayer ${formatTaka(year.minimum_tax_new)}) when income is above the threshold`} refKey="tax.minimum_tax" />
            </div>
          </Card>
        )
      })}
    </div>
  )
}

function Rule({ title, text, refKey }: { title: string; text: string; refKey: string }) {
  return (
    <div className="rounded-xl bg-slate-50 p-3">
      <p className="text-sm font-medium text-slate-900">{title}</p>
      <p className="mt-1 text-xs text-slate-600">{text}</p>
      <ReferenceChips keys={[refKey]} className="mt-2" />
    </div>
  )
}

function ProfilesTab({ canEdit }: { canEdit: boolean }) {
  const profiles = useTaxProfiles()
  const [query, setQuery] = useState('')
  const [editing, setEditing] = useState<TaxProfileRow | null>(null)
  const rows = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return (profiles.data ?? []).filter((r) => !needle || r.full_name.toLowerCase().includes(needle) || r.card_id.toLowerCase().includes(needle))
  }, [profiles.data, query])
  if (profiles.isPending) return <PageLoader />
  if (profiles.isError) return <Alert>{errorMessage(profiles.error)}</Alert>
  const missingTin = (profiles.data ?? []).filter((r) => !r.tin).length
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name or card ID" aria-label="Search"
          className="w-full max-w-xs rounded-xl border border-slate-300 px-3.5 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
        {missingTin > 0 && <Badge tone="orange">{missingTin} without TIN</Badge>}
      </div>
      <Table minWidth={760} head={
        <tr><th className={th}>Employee</th><th className={th}>TIN</th><th className={th}>Type</th>
          <th className={`${th} text-right`}>Declared investment</th><th className={`${th} text-right`}>TDS this year</th><th className={th} /></tr>
      }>
        {rows.map((row) => (
          <tr key={row.employee_id}>
            <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p>
              <p className="text-xs text-slate-400"><span className="font-mono">{row.card_id}</span>{row.department_name ? ` · ${row.department_name}` : ''}</p></td>
            <td className={`${td} font-mono`}>{row.tin ?? <span className="font-sans text-amber-700">Missing</span>}</td>
            <td className={td}>{TAXPAYER_TYPE_LABEL[row.taxpayer_type]}{row.is_new_taxpayer ? ' · new' : ''}</td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.declared_investment)}</td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.ytd_tds)}</td>
            <td className={`${td} text-right`}>
              {canEdit && <Button variant="ghost" onClick={() => setEditing(row)} aria-label={`Edit tax profile of ${row.full_name}`}><Pencil className="size-4" /></Button>}
            </td>
          </tr>
        ))}
      </Table>
      {rows.length === 0 && <p className="text-center text-sm text-slate-400">No employees found.</p>}
      {editing && <ProfileDialog row={editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

function ProfileDialog({ row, onClose }: { row: TaxProfileRow; onClose: () => void }) {
  const save = useStatutoryAction<{ p_employee_id: string; p: Record<string, unknown> }>('save_tax_profile')
  const [tin, setTin] = useState(row.tin ?? '')
  const [type, setType] = useState<TaxpayerType>(row.taxpayer_type)
  const [isNew, setIsNew] = useState(row.is_new_taxpayer)
  const [parent, setParent] = useState(row.parent_of_disabled)
  const [investment, setInvestment] = useState(String(row.declared_investment ?? 0))
  const [note, setNote] = useState(row.note ?? '')
  const tinError = tin.trim() && !/^\d{12}$/.test(tin.replace(/\s/g, '')) ? 'A TIN has 12 digits' : undefined
  const investmentValue = parseMoney(investment || '0')
  return (
    <Modal open onClose={onClose} title={`Tax profile · ${row.full_name}`}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={!!tinError || investmentValue === null}
          onClick={() => save.mutate({ p_employee_id: row.employee_id, p: {
            tin: tin.replace(/\s/g, '') || null, taxpayer_type: type, is_new_taxpayer: isNew, parent_of_disabled: parent,
            declared_investment: investmentValue, note,
          } }, { onSuccess: onClose })}>Save</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <Input label="TIN (12 digits)" inputMode="numeric" value={tin} onChange={(e) => setTin(e.target.value)} error={tinError} />
        <Select label="Taxpayer type" value={type} onChange={(e) => setType(e.target.value as TaxpayerType)} options={TYPE_OPTIONS}
          hint="Sets the tax-free threshold." />
        <Input label="Declared investment for the year (৳)" inputMode="decimal" value={investment}
          onChange={(e) => setInvestment(e.target.value)} error={investmentValue === null ? 'Enter an amount' : undefined}
          hint="PF contributions are added automatically when the fund is recognised." />
        <Checkbox label="First-time taxpayer" checked={isNew} onChange={setIsNew} />
        <Checkbox label="Parent / guardian of a person with disability" checked={parent} onChange={setParent} />
        <Textarea label="Note" value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Modal>
  )
}

function LedgerTab({ canEdit }: { canEdit: boolean }) {
  const tables = useTaxTables()
  const [year, setYear] = useState<string>('')
  const ledger = useTdsLedger(year || null)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [challanOpen, setChallanOpen] = useState(false)
  const rows = ledger.data ?? []
  const pending = rows.filter((r) => r.status === 'posted')
  const toggle = (id: string) => setSelected((prev) => {
    const next = new Set(prev)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    return next
  })
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <Select label="Fiscal year" className="w-48" value={year} onChange={(e) => setYear(e.target.value)} placeholder="All years"
          options={(tables.data ?? []).map((y) => ({ value: y.code, label: y.code }))} />
        <div className="flex items-center gap-3 text-sm text-slate-600">
          <span>Total {formatTaka(rows.reduce((s, r) => s + Number(r.tds_amount), 0))}</span>
          {canEdit && (
            <Button disabled={selected.size === 0} onClick={() => setChallanOpen(true)}><Receipt className="size-4" />Record challan ({selected.size})</Button>
          )}
        </div>
      </div>
      <p className="text-xs text-slate-500">TDS rows are posted when a payroll run is locked. Record the treasury challan once the money is deposited.</p>
      {ledger.isPending ? <PageLoader /> : ledger.isError ? <Alert>{errorMessage(ledger.error)}</Alert>
        : rows.length === 0 ? <EmptyState title="No TDS posted yet">Lock a payroll run with tax deducted to see rows here.</EmptyState> : (
          <Table minWidth={760} head={
            <tr>{canEdit && <th className={th}><Checkbox srOnlyLabel label="Select all not deposited"
              checked={pending.length > 0 && pending.every((r) => selected.has(r.id))}
              onChange={(v) => setSelected(v ? new Set(pending.map((r) => r.id)) : new Set())} /></th>}
              <th className={th}>Month</th><th className={th}>Employee</th><th className={th}>TIN</th>
              <th className={`${th} text-right`}>TDS</th><th className={th}>Challan</th></tr>
          }>
            {rows.map((row) => (
              <tr key={row.id}>
                {canEdit && <td className={td}>{row.status === 'posted' && (
                  <Checkbox srOnlyLabel label={`Select ${row.full_name}`} checked={selected.has(row.id)} onChange={() => toggle(row.id)} />)}</td>}
                <td className={td}>{formatPeriod(row.period_month)}</td>
                <td className={td}>{row.full_name} <span className="font-mono text-xs text-slate-400">{row.card_id}</span></td>
                <td className={`${td} font-mono`}>{row.tin ?? '—'}</td>
                <td className={`${td} text-right tabular-nums`}>{formatTaka(row.tds_amount)}</td>
                <td className={td}>{row.status === 'deposited'
                  ? <span className="text-green-700">{row.challan_reference} · {formatDate(row.challan_date)}</span>
                  : <Badge tone="orange">Not deposited</Badge>}</td>
              </tr>
            ))}
          </Table>
        )}
      {challanOpen && <ChallanDialog ids={[...selected]} onClose={() => { setChallanOpen(false); setSelected(new Set()) }} />}
    </div>
  )
}

function ChallanDialog({ ids, onClose }: { ids: string[]; onClose: () => void }) {
  const save = useStatutoryAction<{ p_ledger_ids: string[]; p_reference: string; p_challan_date: string }, number>('set_tds_challan')
  const [reference, setReference] = useState('')
  const [date, setDate] = useState(today())
  return (
    <Modal open onClose={onClose} title="Record treasury challan" description={`${ids.length} TDS row(s)`}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={reference.trim().length < 3}
          onClick={() => save.mutate({ p_ledger_ids: ids, p_reference: reference.trim(), p_challan_date: date }, { onSuccess: onClose })}>Save</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <Input label="Challan reference" value={reference} maxLength={60} onChange={(e) => setReference(e.target.value)} />
        <Input label="Deposit date" type="date" max={today()} value={date} onChange={(e) => setDate(e.target.value)} />
        <ReferenceChips keys={['tax.tds_salary']} />
      </div>
    </Modal>
  )
}
