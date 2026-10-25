// Workforce setup tabs: output / volume figures per month, the headcount plan
// with workload methods and budgets, and the company thresholds.
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Plus, Save, Trash2, Upload } from 'lucide-react'
import type { DepartmentWorkforce, WorkforceDashboard, WorkloadInputRow, WorkloadMethod } from '@/onboarding-process/core/types'
import { inputHours, METHOD_LABEL } from '@/onboarding-process/core/workload'
import type { InputDraftRow } from '@/onboarding-process/core/inputCsv'
import { parseInputCsv } from '@/onboarding-process/core/inputCsv'
import { useWorkforceAction } from '@/lib/onboarding'
import { errorMessage } from '@/lib/identity'
import { formatMonth } from '@/lib/payroll'
import { formatDateTime } from '@/lib/options'
import { ReferenceChips } from '@/components/references'
import { Alert, Button, Card, EmptyState, Input, cx } from '@/components/ui'
import { Select, Table, Textarea, td, th } from '@/components/kit'

const METHOD_OPTIONS = (Object.keys(METHOD_LABEL) as WorkloadMethod[]).map((value) => ({ value, label: METHOD_LABEL[value] }))
const METHOD_HINT: Record<WorkloadMethod, string> = {
  hours: 'Uses Part 2 attendance: regular worked hours plus approved overtime.',
  output_smv: 'Enter pieces made per style and the SMV (minutes per piece) each month.',
  volume_std: 'Enter counts of repeated tasks and the standard minutes each takes.',
  ratio: 'Sized by the people served, e.g. one HR person per 100 employees.',
}

type DraftRow = InputDraftRow
const toDraft = (rows: WorkloadInputRow[]): DraftRow[] => rows.map((r) => ({
  metric_key: r.metric_key, label: r.label ?? '', quantity: String(r.quantity), std_minutes: String(r.std_minutes) }))

export function InputsPanel({ data }: { data: WorkforceDashboard }) {
  const measured = data.departments.filter((d) => d.method === 'output_smv' || d.method === 'volume_std')
  const [departmentId, setDepartmentId] = useState(measured[0]?.id ?? '')
  const department = measured.find((d) => d.id === departmentId) ?? measured[0]
  if (!data.can.manage) return <Alert tone="info">Only people who manage workforce data can enter output figures.</Alert>
  if (!department) {
    return <EmptyState title="No department uses output or volume figures">Set a department's method to "Output × SMV" or "Volume × standard time" in the Plan & methods tab.</EmptyState>
  }
  return (
    <div className="space-y-4">
      <Select label="Department" value={department.id} onChange={(e) => setDepartmentId(e.target.value)} className="max-w-sm"
        options={measured.map((d) => ({ value: d.id, label: `${d.name} · ${METHOD_LABEL[d.method]}` }))} />
      <InputsEditor key={`${department.id}-${data.period_month}`} department={department} month={data.period_month} />
    </div>
  )
}

function InputsEditor({ department, month }: { department: DepartmentWorkforce; month: string }) {
  const save = useWorkforceAction<{ p_department_id: string; p_month: string; p_rows: unknown[]; p_source: string }, number>('save_workload_inputs')
  const [rows, setRows] = useState<DraftRow[]>(() => toDraft(department.inputs))
  const [source, setSource] = useState<'manual' | 'csv'>('manual')
  const [csv, setCsv] = useState('')
  const hours = inputHours(rows.map((r) => ({ quantity: Number(r.quantity), std_minutes: Number(r.std_minutes) })))
  const update = (index: number, patch: Partial<DraftRow>) => setRows(rows.map((r, i) => (i === index ? { ...r, ...patch } : r)))
  const smv = department.method === 'output_smv'
  return (
    <Card className="space-y-4 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm font-medium text-slate-900">{department.name} · {formatMonth(month)}</p>
        <p className="text-sm text-slate-600">Demand: <span className="font-semibold tabular-nums text-slate-900">{hours.toLocaleString('en-US')} h</span></p>
      </div>
      <ReferenceChips keys={[smv ? 'workforce.smv' : 'workforce.standard_time']} />
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {save.isSuccess && <Alert tone="success">Saved {save.data} row(s). Build the snapshot to update the figures.</Alert>}
      <div className="space-y-2">
        {rows.map((row, index) => (
          <div key={index} className="grid gap-2 rounded-xl p-2 ring-1 ring-slate-200 sm:grid-cols-[1fr_1.4fr_1fr_1fr_auto]">
            <input aria-label="Item code" placeholder={smv ? 'Style code' : 'Task code'} value={row.metric_key} maxLength={40}
              onChange={(e) => update(index, { metric_key: e.target.value })} className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-sm" />
            <input aria-label="Label" placeholder="Description" value={row.label} maxLength={80}
              onChange={(e) => update(index, { label: e.target.value })} className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-sm" />
            <input aria-label={smv ? 'Pieces' : 'Count'} placeholder={smv ? 'Pieces' : 'Count'} inputMode="decimal" value={row.quantity}
              onChange={(e) => update(index, { quantity: e.target.value })} className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm" />
            <input aria-label={smv ? 'SMV minutes' : 'Minutes each'} placeholder={smv ? 'SMV (min)' : 'Minutes each'} inputMode="decimal" value={row.std_minutes}
              onChange={(e) => update(index, { std_minutes: e.target.value })} className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm" />
            <button type="button" aria-label="Remove row" onClick={() => setRows(rows.filter((_, i) => i !== index))}
              className="justify-self-end rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-red-600"><Trash2 className="size-4" /></button>
          </div>
        ))}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button variant="ghost" onClick={() => setRows([...rows, { metric_key: '', label: '', quantity: '', std_minutes: '' }])}><Plus className="size-4" />Add row</Button>
      </div>
      <details className="rounded-xl bg-slate-50 p-3 text-sm">
        <summary className="cursor-pointer font-medium text-slate-700">Paste from a spreadsheet (CSV)</summary>
        <p className="mt-2 text-xs text-slate-500">One row per line: item code, description, quantity, minutes per unit. Pasting replaces the rows above.</p>
        <Textarea aria-label="CSV rows" value={csv} onChange={(e) => setCsv(e.target.value)} rows={4} className="mt-2"
          placeholder={'POLO-26, Polo shirt, 54000, 12\nTEE-11, T-shirt, 20000, 8.5'} />
        <Button variant="secondary" className="mt-2" disabled={!parseInputCsv(csv).length}
          onClick={() => { setRows(parseInputCsv(csv)); setSource('csv'); setCsv('') }}><Upload className="size-4" />Use these rows</Button>
      </details>
      <div className="flex justify-end">
        <Button loading={save.isPending} onClick={() => save.mutate({
          p_department_id: department.id, p_month: month, p_source: source,
          p_rows: rows.filter((r) => r.metric_key.trim()).map((r) => ({
            metric_key: r.metric_key.trim(), label: r.label.trim(), quantity: Number(r.quantity), std_minutes: Number(r.std_minutes) })),
        })}><Save className="size-4" />Save figures</Button>
      </div>
    </Card>
  )
}

export function PlanPanel({ data }: { data: WorkforceDashboard }) {
  if (!data.can.manage && !data.can.headcount) return <Alert tone="info">You can view the plan; changing it needs workforce or headcount rights.</Alert>
  if (!data.departments.length) return <EmptyState title="No departments yet">Add departments and designations in Organization first.</EmptyState>
  return (
    <div className="space-y-4">
      <Alert tone="info">
        The department's approved headcount now lives in the <Link to="/organogram" className="font-medium underline">Organogram</Link> (budget + slots per grade).
        Saving a designation plan here sets that budget to the plan's total. Workload methods are set by HR.
        {!data.can.money && ' Salary budgets are hidden because your role cannot see salary figures.'}
      </Alert>
      {data.departments.map((department) => (
        <DepartmentPlan key={department.id} department={department} can={data.can} />
      ))}
    </div>
  )
}

function DepartmentPlan({ department, can }: { department: DepartmentWorkforce; can: WorkforceDashboard['can'] }) {
  const saveMethod = useWorkforceAction<{ p_department_id: string; p: Record<string, unknown> }>('save_department_workforce')
  const savePlan = useWorkforceAction<{ p_department_id: string; p_rows: unknown[] }>('save_headcount_plan')
  const [method, setMethod] = useState<WorkloadMethod>(department.method)
  const [ratio, setRatio] = useState(department.per_employees ? String(department.per_employees) : '100')
  const [budget, setBudget] = useState(department.monthly_budget != null ? String(department.monthly_budget) : '')
  const [plan, setPlan] = useState<Record<string, string>>({})
  useEffect(() => {
    setPlan(Object.fromEntries(department.plan.map((p) => [p.designation_id, String(p.sanctioned)])))
  }, [department.plan])
  const totals = useMemo(() => ({
    sanctioned: Object.values(plan).reduce((sum, v) => sum + (Number(v) || 0), 0),
    active: department.plan.reduce((sum, p) => sum + p.active, 0),
  }), [plan, department.plan])
  const error = saveMethod.error ?? savePlan.error
  const save = () => {
    const p: Record<string, unknown> = {}
    if (can.manage) Object.assign(p, { method, per_employees: method === 'ratio' ? Number(ratio) : null })
    if (can.headcount && can.money) p.monthly_budget = budget.trim() === '' ? null : Number(budget)
    const steps: Promise<unknown>[] = []
    if (Object.keys(p).length) steps.push(saveMethod.mutateAsync({ p_department_id: department.id, p }))
    if (can.headcount && department.plan.length) {
      steps.push(savePlan.mutateAsync({ p_department_id: department.id,
        p_rows: department.plan.map((row) => ({ designation_id: row.designation_id, sanctioned: Number(plan[row.designation_id] || 0) })) }))
    }
    Promise.all(steps).catch(() => undefined)
  }
  return (
    <Card className="space-y-4 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-semibold text-slate-900">{department.name}</p>
        <p className="text-sm text-slate-600">Sanctioned {totals.sanctioned} · active {totals.active} · vacancy {Math.max(totals.sanctioned - totals.active, 0)}</p>
      </div>
      {error && <Alert>{errorMessage(error)}</Alert>}
      {(saveMethod.isSuccess || savePlan.isSuccess) && !error && <Alert tone="success">Saved.</Alert>}
      <div className="grid gap-3 sm:grid-cols-3">
        <Select label="Workload method" value={method} disabled={!can.manage} hint={METHOD_HINT[method]}
          onChange={(e) => setMethod(e.target.value as WorkloadMethod)} options={METHOD_OPTIONS} />
        {method === 'ratio' && (
          <Input label="Employees served per person" inputMode="numeric" value={ratio} disabled={!can.manage}
            onChange={(e) => setRatio(e.target.value)} hint="e.g. 100 → one person per 100 employees" />
        )}
        {can.money && (
          <Input label="Monthly salary budget (Tk)" inputMode="decimal" value={budget} disabled={!can.headcount}
            onChange={(e) => setBudget(e.target.value)} hint="Empty = no budget check" />
        )}
      </div>
      {department.plan.length === 0 ? (
        <p className="text-sm text-slate-500">This department has no active designations.</p>
      ) : (
        <Table minWidth={480} head={<tr><th className={th}>Designation</th><th className={th}>Grade</th><th className={th}>Active</th><th className={th}>Sanctioned</th></tr>}>
          {department.plan.map((row) => (
            <tr key={row.designation_id}>
              <td className={td}>{row.designation_name}{!row.planned && <span className="ml-1 text-xs text-slate-400">(not planned)</span>}</td>
              <td className={td}>{row.grade_code}</td>
              <td className={`${td} tabular-nums`}>{row.active}</td>
              <td className={td}>
                <input aria-label={`Sanctioned ${row.designation_name}`} inputMode="numeric" disabled={!can.headcount}
                  value={plan[row.designation_id] ?? '0'} onChange={(e) => setPlan({ ...plan, [row.designation_id]: e.target.value })}
                  className="w-20 rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm disabled:bg-slate-50" />
              </td>
            </tr>
          ))}
        </Table>
      )}
      <div className="flex justify-end">
        <Button loading={saveMethod.isPending || savePlan.isPending} onClick={save}><Save className="size-4" />Save {department.name}</Button>
      </div>
    </Card>
  )
}

export function SettingsPanel({ data }: { data: WorkforceDashboard }) {
  const save = useWorkforceAction<{ p: Record<string, unknown> }>('save_workforce_settings')
  const s = data.settings
  const [form, setForm] = useState(() => ({
    capacity_hours: String(s?.capacity_hours ?? 208), availability_source: s?.availability_source ?? 'attendance',
    fixed_availability_percent: String(s?.fixed_availability_percent ?? 100), band_underload: String(s?.band_underload ?? 0.85),
    band_watch: String(s?.band_watch ?? 1), band_overload: String(s?.band_overload ?? 1.1), band_critical: String(s?.band_critical ?? 1.25),
    sustain_months: String(s?.sustain_months ?? 2), attrition_flag_percent: String(s?.attrition_flag_percent ?? 20),
  }))
  const set = (key: keyof typeof form) => (e: { target: { value: string } }) => setForm({ ...form, [key]: e.target.value })
  const editable = data.can.headcount
  const submit = (confirm: boolean) => save.mutate({ p: {
    ...Object.fromEntries(Object.entries(form).map(([k, v]) => [k, k === 'availability_source' ? v : Number(v)])), confirm,
  } })
  return (
    <Card className="space-y-5 p-4">
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {save.isSuccess && <Alert tone="success">Settings saved.</Alert>}
      {s?.confirmed_at
        ? <Alert tone="success">Values confirmed {formatDateTime(s.confirmed_at)}.</Alert>
        : <Alert tone="info">These values are defaults. Check them against your shifts and labour law, then save with "Confirm".</Alert>}
      <section className="space-y-3">
        <p className="text-sm font-semibold text-slate-900">Capacity per person</p>
        <div className="grid gap-3 sm:grid-cols-3">
          <Input label="Monthly working hours" inputMode="decimal" value={form.capacity_hours} onChange={set('capacity_hours')} disabled={!editable}
            hint="Default 208 = 26 days × 8 h" />
          <Select label="Availability" value={form.availability_source} onChange={set('availability_source')} disabled={!editable}
            options={[{ value: 'attendance', label: 'From attendance (last 3 months)' }, { value: 'fixed', label: 'Fixed percent' }]} />
          {form.availability_source === 'fixed' && (
            <Input label="Fixed availability %" inputMode="decimal" value={form.fixed_availability_percent} onChange={set('fixed_availability_percent')} disabled={!editable} />
          )}
        </div>
        <ReferenceChips keys={['workforce.capacity']} />
      </section>
      <section className="space-y-3">
        <p className="text-sm font-semibold text-slate-900">Bands and the overload rule</p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Input label="Underloaded below" inputMode="decimal" value={form.band_underload} onChange={set('band_underload')} disabled={!editable} />
          <Input label="Watch above" inputMode="decimal" value={form.band_watch} onChange={set('band_watch')} disabled={!editable} />
          <Input label="Overload from" inputMode="decimal" value={form.band_overload} onChange={set('band_overload')} disabled={!editable} />
          <Input label="Critical from" inputMode="decimal" value={form.band_critical} onChange={set('band_critical')} disabled={!editable} />
          <Input label="Overload months in a row" inputMode="numeric" value={form.sustain_months} onChange={set('sustain_months')} disabled={!editable}
            hint="before a new position is suggested" />
          <Input label="Attrition alert above %" inputMode="decimal" value={form.attrition_flag_percent} onChange={set('attrition_flag_percent')} disabled={!editable} />
        </div>
        <p className={cx('rounded-xl bg-slate-50 p-3 text-sm text-slate-600')}>
          Example: with overload from {form.band_overload} for {form.sustain_months} months, one busy month (such as orders before Eid)
          does not trigger hiring; a month at {form.band_critical} or more does at once.
        </p>
        <ReferenceChips keys={['workforce.index', 'workforce.attrition']} />
      </section>
      {editable && (
        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="secondary" loading={save.isPending} onClick={() => submit(false)}>Save</Button>
          <Button loading={save.isPending} onClick={() => submit(true)}>Save and confirm</Button>
        </div>
      )}
    </Card>
  )
}
