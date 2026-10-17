// Compensation: current pay of every employee, increment approvals (maker-checker),
// bonuses with eligibility preview, and loans/advances.
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Eye, Pencil, Plus, Search, TrendingUp } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, today } from '@/lib/options'
import type { Bonus, BonusType, DeductionRow, IncrementRow, PayRow } from '@/lib/payroll'
import {
  BONUS_TYPE_LABEL, CHANGE_LABEL, formatMonth, formatTaka, parseMoney, useBonusPreview, useBonuses, useDeductions,
  useIncrementArrears, useIncrements, usePayList, usePayrollAction,
} from '@/lib/payroll'
import { useEmployeeOptions, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, EmptyState, Input, Spinner } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'
import { CompensationStatTiles } from './SalaryStructurePage'
import { DeductionDialog, IncrementDialog, SetPayDialog } from './dialogs'

type Tab = 'pay' | 'increments' | 'bonuses' | 'deductions'
const INCREMENT_TONE = { pending: 'orange', approved: 'green', rejected: 'red', cancelled: 'slate' } as const

export default function CompensationPage() {
  const context = useMyContext()
  const can = (permission: string) => context.permissions.includes(permission)
  const tabs = ([
    { key: 'pay', label: 'Employee pay', show: can('compensation.view') },
    { key: 'increments', label: 'Increments', show: can('compensation.view') || can('increments.approve') },
    { key: 'bonuses', label: 'Bonuses', show: can('bonuses.manage') || can('compensation.view') },
    { key: 'deductions', label: 'Loans & advances', show: can('deductions.manage') || can('compensation.view') },
  ] as { key: Tab; label: string; show: boolean }[]).filter((t) => t.show)
  const [tab, setTab] = useState<Tab>(tabs[0]?.key ?? 'pay')

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Compensation" description="Pay is versioned: every change opens a new record from its effective date, and history is never edited." />
      {can('compensation.view') && <CompensationStatTiles />}
      <Tabs<Tab> tabs={tabs} value={tab} onChange={setTab} />
      {tab === 'pay' && <PayTab canEdit={can('compensation.edit')} />}
      {tab === 'increments' && <IncrementsTab canApprove={can('increments.approve')} canEdit={can('compensation.edit')} />}
      {tab === 'bonuses' && <BonusesTab canManage={can('bonuses.manage')} />}
      {tab === 'deductions' && <DeductionsTab canManage={can('deductions.manage')} />}
    </div>
  )
}

// ------------------------------------------------------------------- pay list --
function PayTab({ canEdit }: { canEdit: boolean }) {
  const list = usePayList()
  const [query, setQuery] = useState('')
  const [missingOnly, setMissingOnly] = useState(false)
  const [settingPay, setSettingPay] = useState<PayRow | null>(null)
  const [incrementFor, setIncrementFor] = useState<PayRow | null>(null)

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (list.data ?? []).filter((r) =>
      (!missingOnly || r.gross === null) && (!q || `${r.full_name} ${r.card_id} ${r.department_name ?? ''}`.toLowerCase().includes(q)))
  }, [list.data, query, missingOnly])

  if (list.isPending) return <Spinner />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-60 flex-1 sm:max-w-sm">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name, card ID, department" aria-label="Search"
            className="w-full rounded-xl border border-slate-300 bg-white py-2.5 pr-3 pl-9 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
        </div>
        <Checkbox label="Without pay only" checked={missingOnly} onChange={setMissingOnly} />
      </div>
      {visible.length === 0 ? <EmptyState title="No employees match" /> : (
        <Table minWidth={900} head={
          <tr><th className={th}>Employee</th><th className={th}>Grade</th><th className={th}>Template</th><th className={th}>Basic</th>
            <th className={th}>Gross</th><th className={th}>Since</th><th className={th} /></tr>
        }>
          {visible.map((row) => (
            <tr key={row.employee_id}>
              <td className={td}>
                <Link to={`/employees/${row.employee_id}?tab=financial`} className="font-medium text-slate-900 hover:text-primary-700">{row.full_name}</Link>
                <p className="text-xs text-slate-400">{row.card_id} · {row.department_name ?? '—'}</p>
              </td>
              <td className={td}>{row.grade_code ?? '—'}</td>
              <td className={td}>{row.template_name ?? '—'}</td>
              <td className={`${td} tabular-nums`}>{formatTaka(row.basic)}</td>
              <td className={`${td} font-medium tabular-nums`}>
                {row.gross === null ? <Badge tone="orange">Not set</Badge> : formatTaka(row.gross)}
                {row.pending_increment_id && <span className="ml-2"><Badge tone="orange">Change pending</Badge></span>}
              </td>
              <td className={td}>{row.effective_from ? <>{formatDate(row.effective_from)}<p className="text-xs text-slate-400">{row.change_type && CHANGE_LABEL[row.change_type]}</p></> : '—'}</td>
              <td className="px-4 py-3 text-right">
                {canEdit && row.gross === null && <Button onClick={() => setSettingPay(row)}>Set pay</Button>}
                {canEdit && row.gross !== null && !row.pending_increment_id && (
                  <Button variant="secondary" onClick={() => setIncrementFor(row)}><TrendingUp className="size-4" />Change</Button>
                )}
              </td>
            </tr>
          ))}
        </Table>
      )}
      <SetPayDialog open={!!settingPay} onClose={() => setSettingPay(null)}
        employee={settingPay && { id: settingPay.employee_id, full_name: settingPay.full_name, join_date: settingPay.join_date }} />
      <IncrementDialog open={!!incrementFor} onClose={() => setIncrementFor(null)}
        employee={incrementFor && { id: incrementFor.employee_id, full_name: incrementFor.full_name, gross: incrementFor.gross,
          template_id: incrementFor.template_id, effective_from: incrementFor.effective_from }} />
    </div>
  )
}

// ------------------------------------------------------------------ increments --
function IncrementsTab({ canApprove, canEdit }: { canApprove: boolean; canEdit: boolean }) {
  const list = useIncrements()
  const cancel = usePayrollAction<{ p_increment_id: string }>('cancel_increment')
  const [status, setStatus] = useState('pending')
  const [deciding, setDeciding] = useState<IncrementRow | null>(null)
  const rows = (list.data ?? []).filter((r) => !status || r.status === status)

  if (list.isPending) return <Spinner />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)} placeholder="All"
          options={[{ value: 'pending', label: 'Pending' }, { value: 'approved', label: 'Approved' }, { value: 'rejected', label: 'Rejected' }, { value: 'cancelled', label: 'Cancelled' }]} />
        <span className="text-sm text-slate-500">The person who requests a change can never approve it.</span>
      </div>
      {cancel.isError && <Alert>{errorMessage(cancel.error)}</Alert>}
      {rows.length === 0 ? <EmptyState title="No increments here" /> : (
        <Table minWidth={960} head={
          <tr><th className={th}>Employee</th><th className={th}>Type</th><th className={th}>Gross</th><th className={th}>Effective</th>
            <th className={th}>Requested by</th><th className={th}>Status</th><th className={th} /></tr>
        }>
          {rows.map((row) => (
            <tr key={row.id}>
              <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p>
                <p className="max-w-56 truncate text-xs italic text-slate-400" title={row.reason}>{row.reason}</p></td>
              <td className={td}>{CHANGE_LABEL[row.type]}</td>
              <td className={`${td} tabular-nums`}>{formatTaka(row.old_gross)} → <span className="font-medium text-slate-900">{formatTaka(row.new_gross)}</span></td>
              <td className={td}>{formatDate(row.effective_date)}</td>
              <td className={td}>{row.requested_by_name ?? '—'}<p className="text-xs text-slate-400">{formatDate(row.created_at)}</p></td>
              <td className={td}><Badge tone={INCREMENT_TONE[row.status]}>{row.status}</Badge>
                {row.approved_by_name && <p className="text-xs text-slate-400">by {row.approved_by_name}</p>}</td>
              <td className="px-4 py-3 text-right">
                <div className="flex justify-end gap-2">
                  {row.status === 'pending' && canApprove && !row.is_requester && !row.is_self && (
                    <Button onClick={() => setDeciding(row)}>Review</Button>
                  )}
                  {row.status === 'pending' && canEdit && (
                    <Button variant="secondary" loading={cancel.isPending && cancel.variables?.p_increment_id === row.id}
                      onClick={() => cancel.mutate({ p_increment_id: row.id })}>Cancel</Button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </Table>
      )}
      <DecideIncrementDialog increment={deciding} onClose={() => setDeciding(null)} />
    </div>
  )
}

function DecideIncrementDialog({ increment, onClose }: { increment: IncrementRow | null; onClose: () => void }) {
  const decide = usePayrollAction<{ p_increment_id: string; p_approve: boolean; p_note: string | null }>('decide_increment')
  const arrears = useIncrementArrears(increment?.id ?? null)
  const [note, setNote] = useState('')
  const [error, setError] = useState<string | null>(null)
  useEffect(() => { setNote(''); setError(null) }, [increment])

  const submit = async (approve: boolean) => {
    if (!increment) return
    setError(null)
    try {
      await decide.mutateAsync({ p_increment_id: increment.id, p_approve: approve, p_note: note.trim() || null })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }
  return (
    <Modal open={!!increment} onClose={onClose} title="Review pay change" description={increment?.full_name}
      footer={<><Button variant="secondary" loading={decide.isPending} onClick={() => submit(false)}>Reject</Button>
        <Button loading={decide.isPending} onClick={() => submit(true)}>Approve</Button></>}
    >
      {increment && (
        <div className="space-y-4 text-sm">
          {error && <Alert>{error}</Alert>}
          <dl className="grid grid-cols-2 gap-3">
            <div><dt className="text-xs text-slate-400">Current gross</dt><dd className="tabular-nums">{formatTaka(increment.old_gross)}</dd></div>
            <div><dt className="text-xs text-slate-400">New gross</dt><dd className="font-semibold tabular-nums">{formatTaka(increment.new_gross)}</dd></div>
            <div><dt className="text-xs text-slate-400">Change</dt><dd className="tabular-nums">
              {formatTaka(increment.new_gross - increment.old_gross)} ({(((increment.new_gross - increment.old_gross) / increment.old_gross) * 100).toFixed(1)}%)</dd></div>
            <div><dt className="text-xs text-slate-400">Effective</dt><dd>{formatDate(increment.effective_date)}</dd></div>
            <div className="col-span-2"><dt className="text-xs text-slate-400">Reason</dt><dd>{increment.reason}</dd></div>
          </dl>
          {arrears.data?.back_dated && (
            <Alert tone="info">Back-dated: arrears of <b>{formatTaka(arrears.data.amount)}</b> for the months before {formatMonth(arrears.data.until_month)} will be paid by payroll.</Alert>
          )}
          <Textarea label="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
        </div>
      )}
    </Modal>
  )
}

// --------------------------------------------------------------------- bonuses --
function BonusesTab({ canManage }: { canManage: boolean }) {
  const data = useBonuses()
  const [editing, setEditing] = useState<Bonus | 'new' | null>(null)
  const [previewing, setPreviewing] = useState<Bonus | null>(null)

  if (data.isPending) return <Spinner />
  if (data.isError) return <Alert>{errorMessage(data.error)}</Alert>
  const { bonuses, eligibility } = data.data
  return (
    <div className="space-y-4">
      {canManage && <div className="flex justify-end"><Button onClick={() => setEditing('new')}><Plus className="size-4" />New bonus</Button></div>}
      {bonuses.length === 0 ? <EmptyState title="No bonuses yet">Festival bonuses, incentives and one-off payments are set up here.</EmptyState> : (
        <Table minWidth={860} head={
          <tr><th className={th}>Bonus</th><th className={th}>Month</th><th className={th}>Amount</th><th className={th}>Who</th>
            <th className={th}>Min. service</th><th className={th}>Status</th><th className={th} /></tr>
        }>
          {bonuses.map((bonus) => (
            <tr key={bonus.id}>
              <td className={td}><p className="font-medium text-slate-900">{bonus.name}</p><p className="text-xs text-slate-400">{BONUS_TYPE_LABEL[bonus.type]}</p></td>
              <td className={td}>{formatMonth(bonus.payment_month)}</td>
              <td className={`${td} tabular-nums`}>{bonus.basis === 'fixed' ? formatTaka(bonus.amount) : `${bonus.percent}% of ${bonus.percent_base}`}</td>
              <td className={td}>{bonus.scope === 'all' ? 'Everyone' : `${eligibility.filter((e) => e.bonus_id === bonus.id).length} ${bonus.scope}`}</td>
              <td className={td}>{bonus.min_service_months ? `${bonus.min_service_months} months` : 'None'}</td>
              <td className={td}><Badge tone={bonus.status === 'active' ? 'green' : 'slate'}>{bonus.status}</Badge></td>
              <td className="px-4 py-3 text-right">
                <div className="flex justify-end gap-1">
                  <Button variant="ghost" onClick={() => setPreviewing(bonus)} aria-label={`Preview ${bonus.name}`}><Eye className="size-4" /></Button>
                  {canManage && <Button variant="ghost" onClick={() => setEditing(bonus)} aria-label={`Edit ${bonus.name}`}><Pencil className="size-4" /></Button>}
                </div>
              </td>
            </tr>
          ))}
        </Table>
      )}
      <BonusDialog open={editing !== null} onClose={() => setEditing(null)} bonus={editing === 'new' ? null : editing}
        targets={editing && editing !== 'new' ? eligibility.filter((e) => e.bonus_id === editing.id) : []} />
      <BonusPreviewDialog bonus={previewing} onClose={() => setPreviewing(null)} />
    </div>
  )
}

function BonusDialog({ open, onClose, bonus, targets }: {
  open: boolean; onClose: () => void; bonus: Bonus | null; targets: { department_id: string | null; employee_id: string | null }[]
}) {
  const save = usePayrollAction<{ p_bonus_id: string | null; p: Record<string, unknown> }>('save_bonus')
  const structure = useOrgStructure()
  const people = useEmployeeOptions(open)
  const [form, setForm] = useState({
    name: '', type: 'festival' as BonusType, basis: 'percent' as 'fixed' | 'percent', amount: '', percent: '', percent_base: 'basic',
    payment_month: today().slice(0, 7), min_service_months: '0', scope: 'all' as Bonus['scope'], active: true,
  })
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open) return
    setError(null)
    setForm({
      name: bonus?.name ?? '', type: bonus?.type ?? 'festival', basis: bonus?.basis ?? 'percent',
      amount: bonus?.amount != null ? String(bonus.amount) : '', percent: bonus?.percent != null ? String(bonus.percent) : '',
      percent_base: bonus?.percent_base ?? 'basic', payment_month: bonus?.payment_month.slice(0, 7) ?? today().slice(0, 7),
      min_service_months: String(bonus?.min_service_months ?? 0), scope: bonus?.scope ?? 'all', active: (bonus?.status ?? 'active') === 'active',
    })
    setSelected(new Set(targets.map((t) => t.department_id ?? t.employee_id ?? '').filter(Boolean)))
    // `targets` is derived from `bonus`, so the form resets only when the dialog opens for another bonus.
  }, [open, bonus])

  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) => setForm((f) => ({ ...f, [key]: value }))
  const toggle = (id: string) => setSelected((current) => {
    const next = new Set(current)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    return next
  })
  const amountValid = form.basis === 'fixed' ? parseMoney(form.amount) !== null : parseMoney(form.percent) !== null

  const submit = async () => {
    setError(null)
    try {
      await save.mutateAsync({ p_bonus_id: bonus?.id ?? null, p: {
        name: form.name.trim(), type: form.type, basis: form.basis,
        amount: form.basis === 'fixed' ? parseMoney(form.amount) : null,
        percent: form.basis === 'percent' ? parseMoney(form.percent) : null,
        percent_base: form.basis === 'percent' ? form.percent_base : null,
        payment_month: `${form.payment_month}-01`, min_service_months: Number(form.min_service_months) || 0,
        scope: form.scope, status: form.active ? 'active' : 'inactive',
        department_ids: form.scope === 'departments' ? [...selected] : [],
        employee_ids: form.scope === 'employees' ? [...selected] : [],
      } })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  const choices = form.scope === 'departments'
    ? (structure.data?.departments ?? []).filter((d) => d.status === 'active').map((d) => ({ id: d.id, label: d.name }))
    : (people.data ?? []).map((p) => ({ id: p.id, label: `${p.full_name} (${p.card_id})` }))
  return (
    <Modal open={open} onClose={onClose} size="lg" title={bonus ? 'Edit bonus' : 'New bonus'}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button disabled={form.name.trim().length < 2 || !amountValid || (form.scope !== 'all' && selected.size === 0)} loading={save.isPending} onClick={submit}>Save</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Name" name="bonus_name" value={form.name} onChange={(e) => set('name', e.target.value)} maxLength={100} placeholder="e.g. Eid-ul-Fitr 2027" />
          <Select label="Type" value={form.type} onChange={(e) => set('type', e.target.value as BonusType)}
            options={Object.entries(BONUS_TYPE_LABEL).map(([value, label]) => ({ value, label }))} />
          <Select label="Amount" value={form.basis} onChange={(e) => set('basis', e.target.value as 'fixed' | 'percent')}
            options={[{ value: 'percent', label: 'Percent of pay' }, { value: 'fixed', label: 'Fixed amount' }]} />
          {form.basis === 'fixed' ? (
            <Input label="Amount (৳)" name="bonus_amount" inputMode="decimal" value={form.amount} onChange={(e) => set('amount', e.target.value)} />
          ) : (
            <div className="grid grid-cols-2 gap-2">
              <Input label="Percent" name="bonus_percent" inputMode="decimal" value={form.percent} onChange={(e) => set('percent', e.target.value)} />
              <Select label="of" value={form.percent_base} onChange={(e) => set('percent_base', e.target.value)}
                options={[{ value: 'basic', label: 'Basic' }, { value: 'gross', label: 'Gross' }]} />
            </div>
          )}
          <Input label="Payment month" type="month" name="bonus_month" value={form.payment_month} onChange={(e) => e.target.value && set('payment_month', e.target.value)} />
          <Input label="Minimum service (months)" type="number" name="bonus_min_service" min={0} max={600} value={form.min_service_months}
            onChange={(e) => set('min_service_months', e.target.value)} hint="Completed months at the end of the payment month" />
          <Select label="Who gets it" value={form.scope} onChange={(e) => { set('scope', e.target.value as Bonus['scope']); setSelected(new Set()) }}
            options={[{ value: 'all', label: 'Everyone' }, { value: 'departments', label: 'Chosen departments' }, { value: 'employees', label: 'Chosen employees' }]} />
          {bonus && <Checkbox label="Active" checked={form.active} onChange={(v) => set('active', v)} />}
        </div>
        {form.scope !== 'all' && (
          <div className="max-h-56 space-y-1 overflow-y-auto rounded-xl p-3 ring-1 ring-slate-200">
            {choices.length === 0 ? <p className="text-sm text-slate-500">Nothing to choose from.</p>
              : choices.map((choice) => <div key={choice.id}><Checkbox label={choice.label} checked={selected.has(choice.id)} onChange={() => toggle(choice.id)} /></div>)}
          </div>
        )}
      </div>
    </Modal>
  )
}

function BonusPreviewDialog({ bonus, onClose }: { bonus: Bonus | null; onClose: () => void }) {
  const preview = useBonusPreview(bonus?.id ?? null)
  const eligible = (preview.data ?? []).filter((r) => r.eligible)
  const total = eligible.reduce((sum, r) => sum + Number(r.amount), 0)
  return (
    <Modal open={!!bonus} onClose={onClose} size="xl" title={bonus ? `${bonus.name} — eligibility` : 'Eligibility'}
      description={bonus ? `${eligible.length} eligible · total ${formatTaka(total)} · ${formatMonth(bonus.payment_month)}` : undefined}
    >
      {preview.isPending ? <Spinner /> : preview.isError ? <Alert>{errorMessage(preview.error)}</Alert> : (preview.data ?? []).length === 0 ? (
        <EmptyState title="Nobody is in scope" />
      ) : (
        <Table minWidth={680} head={<tr><th className={th}>Employee</th><th className={th}>Service</th><th className={th}>Base</th><th className={th}>Bonus</th></tr>}>
          {(preview.data ?? []).map((row) => (
            <tr key={row.employee_id} className={row.eligible ? '' : 'opacity-60'}>
              <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p><p className="text-xs text-slate-400">{row.card_id} · {row.department_name ?? '—'}</p></td>
              <td className={td}>{row.service_months} months</td>
              <td className={`${td} tabular-nums`}>{bonus?.basis === 'percent' ? formatTaka(bonus.percent_base === 'basic' ? row.basic : row.gross) : '—'}</td>
              <td className={`${td} tabular-nums`}>{row.eligible ? <span className="font-medium text-slate-900">{formatTaka(row.amount)}</span> : <span className="text-xs">{row.reason}</span>}</td>
            </tr>
          ))}
        </Table>
      )}
    </Modal>
  )
}

// ------------------------------------------------------------ loans & advances --
function DeductionsTab({ canManage }: { canManage: boolean }) {
  const list = useDeductions()
  const cancel = usePayrollAction<{ p_deduction_id: string; p_reason: string }>('cancel_deduction')
  const [adding, setAdding] = useState(false)
  const [cancelling, setCancelling] = useState<string | null>(null)
  const [reason, setReason] = useState('')
  const [status, setStatus] = useState('active')
  const rows = (list.data ?? []).filter((r) => !status || r.status === status)

  if (list.isPending) return <Spinner />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)} placeholder="All"
          options={[{ value: 'active', label: 'Active' }, { value: 'completed', label: 'Completed' }, { value: 'cancelled', label: 'Cancelled' }]} />
        {canManage && <Button onClick={() => setAdding(true)}><Plus className="size-4" />Add loan / advance</Button>}
      </div>
      {rows.length === 0 ? <EmptyState title="No loans or advances" /> : <DeductionTable rows={rows} onCancel={canManage ? (id) => { setReason(''); setCancelling(id) } : undefined} />}
      <DeductionDialog open={adding} onClose={() => setAdding(false)} />
      <Modal open={!!cancelling} onClose={() => setCancelling(null)} size="sm" title="Cancel deduction"
        description="Payroll stops taking installments. The record is kept."
        footer={<><Button variant="secondary" onClick={() => setCancelling(null)}>Back</Button>
          <Button variant="danger" disabled={reason.trim().length < 3} loading={cancel.isPending}
            onClick={async () => { if (cancelling) { await cancel.mutateAsync({ p_deduction_id: cancelling, p_reason: reason.trim() }).catch(() => undefined); setCancelling(null) } }}>Cancel deduction</Button></>}
      >
        {cancel.isError && <Alert>{errorMessage(cancel.error)}</Alert>}
        <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
      </Modal>
    </div>
  )
}

export function DeductionTable({ rows, onCancel, showEmployee = true }: {
  rows: DeductionRow[]; onCancel?: (id: string) => void; showEmployee?: boolean
}) {
  return (
    <Table minWidth={760} head={
      <tr>{showEmployee && <th className={th}>Employee</th>}<th className={th}>Type</th><th className={th}>Total</th><th className={th}>Installment</th>
        <th className={th}>From</th><th className={th}>Remaining</th><th className={th}>Status</th>{onCancel && <th className={th} />}</tr>
    }>
      {rows.map((row) => (
        <tr key={row.id}>
          {showEmployee && <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p><p className="text-xs text-slate-400">{row.card_id}</p></td>}
          <td className={td}><span className="capitalize">{row.type}</span>{row.description && <p className="max-w-48 truncate text-xs text-slate-400">{row.description}</p>}</td>
          <td className={`${td} tabular-nums`}>{formatTaka(row.total)}</td>
          <td className={`${td} tabular-nums`}>{formatTaka(row.installment)}</td>
          <td className={td}>{formatMonth(row.start_month)}</td>
          <td className={`${td} font-medium tabular-nums`}>{formatTaka(row.remaining)}</td>
          <td className={td}><Badge tone={row.status === 'active' ? 'orange' : row.status === 'completed' ? 'green' : 'slate'}>{row.status}</Badge></td>
          {onCancel && <td className="px-4 py-3 text-right">{row.status === 'active' && <Button variant="secondary" onClick={() => onCancel(row.id)}>Cancel</Button>}</td>}
        </tr>
      ))}
    </Table>
  )
}
