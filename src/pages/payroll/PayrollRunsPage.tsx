import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatTaka, parseMoney } from '@/lib/payroll'
import type { AdjustmentRow, RunStatus } from '@/lib/payrollRuns'
import { RUN_STATUS_LABEL, formatPeriod, usePayrollAction, usePayrollAdjustments, usePayrollRuns } from '@/lib/payrollRuns'
import { useEmployeeOptions, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'

export function RunStatusBadge({ status }: { status: RunStatus }) {
  const tone = status === 'locked' || status === 'paid' ? 'green' : status === 'approved' ? 'green'
    : status === 'cancelled' ? 'slate' : 'orange'
  return <Badge tone={tone}>{RUN_STATUS_LABEL[status]}</Badge>
}

/** Payroll home: runs by month and the adjustment queue. */
export default function PayrollRunsPage() {
  const ctx = useMyContext()
  const canPrepare = ctx.permissions.includes('payroll.prepare')
  const [tab, setTab] = useState<'runs' | 'adjustments'>('runs')
  const [creating, setCreating] = useState(false)

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Payroll" description="Prepare, review and approve monthly payroll. The person who prepares a run cannot approve it."
        actions={canPrepare && tab === 'runs' && <Button onClick={() => setCreating(true)}><Plus className="size-4" />New run</Button>} />
      <Tabs tabs={[{ key: 'runs', label: 'Runs' }, { key: 'adjustments', label: 'Adjustments' }]} value={tab} onChange={setTab} />
      {tab === 'runs' ? <RunList /> : <AdjustmentList canPrepare={canPrepare} canApprove={ctx.permissions.includes('payroll.approve')} />}
      <CreateRunDialog open={creating} onClose={() => setCreating(false)} />
    </div>
  )
}

function RunList() {
  const navigate = useNavigate()
  const runs = usePayrollRuns()
  if (runs.isPending) return <PageLoader />
  if (runs.isError) return <Alert>{errorMessage(runs.error)}</Alert>
  if (runs.data.length === 0) return <EmptyState title="No payroll runs yet">Create the first run for a month.</EmptyState>
  return (
    <Table minWidth={820} head={
      <tr><th className={th}>Month</th><th className={th}>Scope</th><th className={th}>Status</th><th className={th}>Employees</th>
        <th className={th}>Gross</th><th className={th}>Net</th><th className={th}>Checks</th></tr>
    }>
      {runs.data.map((run) => (
        <tr key={run.id} className="cursor-pointer hover:bg-slate-50" onClick={() => navigate(`/payroll/runs/${run.id}`)}>
          <td className={td}><Link to={`/payroll/runs/${run.id}`} className="font-medium text-slate-900" onClick={(e) => e.stopPropagation()}>{formatPeriod(run.period_month)}</Link></td>
          <td className={td}>{run.scope === 'all' ? 'Whole organization' : `${run.scope === 'branch' ? 'Branch' : 'Department'}: ${run.scope_name ?? ''}`}</td>
          <td className={td}><RunStatusBadge status={run.status} /></td>
          <td className={`${td} tabular-nums`}>{run.employee_count}</td>
          <td className={`${td} tabular-nums`}>{formatTaka(run.total_gross)}</td>
          <td className={`${td} tabular-nums font-medium`}>{formatTaka(run.total_net)}</td>
          <td className={td}>
            {run.blocker_count > 0 && <Badge tone="red">{run.blocker_count} blocker(s)</Badge>}{' '}
            {run.warning_count > 0 && <Badge tone="orange">{run.warning_count} warning(s)</Badge>}
            {run.blocker_count === 0 && run.warning_count === 0 && run.status !== 'draft' && <span className="text-xs text-slate-400">None</span>}
          </td>
        </tr>
      ))}
    </Table>
  )
}

function CreateRunDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const navigate = useNavigate()
  const structure = useOrgStructure()
  const create = usePayrollAction<{ p_period_month: string; p_scope: string; p_scope_id: string | null; p_note: string | null }, string>('create_payroll_run')
  const calculate = usePayrollAction<{ p_run_id: string }>('calculate_payroll_run')
  const lastMonth = new Date(new Date().getFullYear(), new Date().getMonth() - 1, 1)
  const [month, setMonth] = useState(`${lastMonth.getFullYear()}-${String(lastMonth.getMonth() + 1).padStart(2, '0')}`)
  const [scope, setScope] = useState<'all' | 'branch' | 'department'>('all')
  const [scopeId, setScopeId] = useState('')
  const [error, setError] = useState<string | null>(null)

  const scopeOptions = scope === 'branch'
    ? (structure.data?.branches ?? []).filter((b) => b.status === 'active').map((b) => ({ value: b.id, label: b.name }))
    : (structure.data?.departments ?? []).filter((d) => d.status === 'active').map((d) => ({ value: d.id, label: d.name }))

  const submit = async () => {
    setError(null)
    try {
      const runId = await create.mutateAsync({ p_period_month: `${month}-01`, p_scope: scope, p_scope_id: scope === 'all' ? null : scopeId || null, p_note: null })
      await calculate.mutateAsync({ p_run_id: runId })
      onClose()
      navigate(`/payroll/runs/${runId}`)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="sm" title="New payroll run" description="The run is calculated right away; you can recalculate until it is approved."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={create.isPending || calculate.isPending} disabled={scope !== 'all' && !scopeId} onClick={submit}>Create and calculate</Button></>}>
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <label className="block text-sm font-medium text-slate-700">Month
          <input type="month" value={month} onChange={(e) => e.target.value && setMonth(e.target.value)}
            className="mt-1.5 block w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm" />
        </label>
        <Select label="Scope" value={scope} onChange={(e) => { setScope(e.target.value as typeof scope); setScopeId('') }}
          options={[{ value: 'all', label: 'Whole organization' }, { value: 'branch', label: 'One branch' }, { value: 'department', label: 'One department' }]} />
        {scope !== 'all' && (
          <Select label={scope === 'branch' ? 'Branch' : 'Department'} value={scopeId} onChange={(e) => setScopeId(e.target.value)}
            options={scopeOptions} placeholder="Select…" />
        )}
      </div>
    </Modal>
  )
}

function AdjustmentList({ canPrepare, canApprove }: { canPrepare: boolean; canApprove: boolean }) {
  const [status, setStatus] = useState<string>('pending')
  const adjustments = usePayrollAdjustments(status || null)
  const decide = usePayrollAction<{ p_adjustment_id: string; p_approve: boolean }>('decide_payroll_adjustment')
  const cancel = usePayrollAction<{ p_adjustment_id: string }>('cancel_payroll_adjustment')
  const [creating, setCreating] = useState(false)
  const actionError = decide.error ?? cancel.error

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)} placeholder="All"
          options={['pending', 'approved', 'applied', 'rejected', 'cancelled'].map((s) => ({ value: s, label: s[0].toUpperCase() + s.slice(1) }))} />
        <p className="text-sm text-slate-500">Corrections for closed months are applied in an open month. Someone other than the creator approves.</p>
        {canPrepare && <Button className="ml-auto" onClick={() => setCreating(true)}><Plus className="size-4" />New adjustment</Button>}
      </div>
      {actionError && <Alert>{errorMessage(actionError)}</Alert>}
      {adjustments.isPending ? <PageLoader /> : adjustments.isError ? <Alert>{errorMessage(adjustments.error)}</Alert>
        : adjustments.data.length === 0 ? <EmptyState title="No adjustments here" /> : (
          <Table minWidth={860} head={
            <tr><th className={th}>Employee</th><th className={th}>Month</th><th className={th}>Type</th><th className={th}>Amount</th>
              <th className={th}>Reason</th><th className={th}>Status</th><th className={th} /></tr>
          }>
            {adjustments.data.map((row: AdjustmentRow) => (
              <tr key={row.id}>
                <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p><p className="font-mono text-xs text-slate-400">{row.card_id}</p></td>
                <td className={td}>{formatPeriod(row.apply_month)}</td>
                <td className={`${td} capitalize`}>{row.type}</td>
                <td className={`${td} tabular-nums ${row.direction === 'deduction' ? 'text-red-600' : 'text-green-700'}`}>
                  {row.direction === 'deduction' ? '−' : '+'}{formatTaka(row.amount)}
                </td>
                <td className={`${td} max-w-56 truncate`} title={row.reason}>{row.reason}</td>
                <td className={td}><Badge tone={row.status === 'approved' || row.status === 'applied' ? 'green' : row.status === 'pending' ? 'orange' : 'slate'}>{row.status}</Badge></td>
                <td className="px-4 py-3 text-right">
                  <div className="flex justify-end gap-2">
                    {row.status === 'pending' && canApprove && !row.is_creator && (
                      <>
                        <Button onClick={() => decide.mutate({ p_adjustment_id: row.id, p_approve: true })}>Approve</Button>
                        <Button variant="secondary" onClick={() => decide.mutate({ p_adjustment_id: row.id, p_approve: false })}>Reject</Button>
                      </>
                    )}
                    {(row.status === 'pending' || row.status === 'approved') && canPrepare && (
                      <Button variant="ghost" onClick={() => confirm('Cancel this adjustment?') && cancel.mutate({ p_adjustment_id: row.id })}>Cancel</Button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}
      <AdjustmentDialog open={creating} onClose={() => setCreating(false)} />
    </div>
  )
}

function AdjustmentDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const people = useEmployeeOptions(open)
  const create = usePayrollAction<{ p: Record<string, unknown> }, string>('create_payroll_adjustment')
  const [form, setForm] = useState({ employeeId: '', month: new Date().toISOString().slice(0, 7), type: 'correction', direction: 'earning', amount: '', reason: '' })
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setError(null)
    const amount = parseMoney(form.amount)
    if (!amount) return setError('Enter the amount in taka (up to 2 decimals)')
    try {
      await create.mutateAsync({ p: {
        employee_id: form.employeeId, apply_month: `${form.month}-01`, type: form.type, direction: form.direction,
        amount, reason: form.reason.trim(),
      } })
      setForm({ ...form, amount: '', reason: '' })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="sm" title="New payroll adjustment"
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={create.isPending} disabled={!form.employeeId || form.reason.trim().length < 3} onClick={submit}>Submit for approval</Button></>}>
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Employee" value={form.employeeId} onChange={(e) => setForm({ ...form, employeeId: e.target.value })} placeholder="Select…"
          options={(people.data ?? []).map((p) => ({ value: p.id, label: `${p.full_name} (${p.card_id})` }))} />
        <label className="block text-sm font-medium text-slate-700">Apply in month
          <input type="month" value={form.month} onChange={(e) => e.target.value && setForm({ ...form, month: e.target.value })}
            className="mt-1.5 block w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm" />
        </label>
        <div className="grid grid-cols-2 gap-3">
          <Select label="Type" value={form.type} onChange={(e) => setForm({ ...form, type: e.target.value })}
            options={[{ value: 'correction', label: 'Correction' }, { value: 'arrear', label: 'Arrear' }, { value: 'manual', label: 'Manual' }]} />
          <Select label="Effect" value={form.direction} onChange={(e) => setForm({ ...form, direction: e.target.value })}
            options={[{ value: 'earning', label: 'Adds to pay' }, { value: 'deduction', label: 'Deducts from pay' }]} />
        </div>
        <Input label="Amount (৳)" name="adj_amount" inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
        <Textarea label="Reason (required)" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
      </div>
    </Modal>
  )
}
