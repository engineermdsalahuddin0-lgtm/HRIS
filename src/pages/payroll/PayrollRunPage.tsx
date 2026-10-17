import { useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, Check, Download, Lock, RefreshCw, RotateCcw, Search, ShieldCheck, XCircle } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatTaka } from '@/lib/payroll'
import type { PayrollRunDetail } from '@/lib/payrollRuns'
import { RUN_STEPS, RUN_STATUS_LABEL, downloadText, fetchPaymentSheet, formatPeriod, toCsv, usePayrollAction, usePayrollRun } from '@/lib/payrollRuns'
import { useMyContext } from '@/lib/appContext'
import type { RunStatutoryRow } from '@/lib/statutory'
import { useRunStatutorySummary } from '@/lib/statutory'
import { Alert, Badge, Button, Card, PageLoader, cx } from '@/components/ui'
import { Modal, PageHeader, Table, Textarea, td, th } from '@/components/kit'
import { RunStatusBadge } from './PayrollRunsPage'
import { PayslipDialog } from './PayslipView'

const METHOD_LABEL: Record<string, string> = { bank: 'Bank', mobile_wallet: 'Mobile wallet', cash: 'Cash', unassigned: 'No account' }

function StatusStepper({ status }: { status: PayrollRunDetail['run']['status'] }) {
  const currentIndex = RUN_STEPS.indexOf(status)
  return (
    <ol className="flex flex-wrap items-center gap-2" aria-label="Run status">
      {RUN_STEPS.map((step, index) => {
        const done = currentIndex > index
        const current = currentIndex === index
        return (
          <li key={step} className="flex items-center gap-2">
            <span className={cx('flex size-7 items-center justify-center rounded-full text-xs font-semibold',
              done ? 'bg-green-600 text-white' : current ? 'bg-primary-600 text-white' : 'bg-slate-200 text-slate-500')}
              aria-current={current ? 'step' : undefined}>
              {done ? <Check className="size-4" /> : index + 1}
            </span>
            <span className={cx('text-sm', current ? 'font-medium text-slate-900' : 'text-slate-500')}>{RUN_STATUS_LABEL[step]}</span>
            {index < RUN_STEPS.length - 1 && <span className="hidden h-px w-6 bg-slate-300 sm:block" aria-hidden />}
          </li>
        )
      })}
    </ol>
  )
}

/** TDS and PF columns: TDS deducted, or the preview in grey when auto-TDS is off. */
function StatutoryCells({ row }: { row: RunStatutoryRow | undefined }) {
  if (!row) return (<><td className={td}>—</td><td className={td}>—</td></>)
  return (
    <>
      <td className={td + ' tabular-nums'}>
        {row.tds > 0 ? formatTaka(row.tds)
          : row.tds_preview > 0 ? <span className="text-slate-400" title="Preview: auto-TDS is off">{formatTaka(row.tds_preview)}*</span>
          : <span className="text-slate-400">—</span>}
      </td>
      <td className={td + ' tabular-nums'}>
        {row.pf_employee > 0 || row.pf_employer > 0
          ? <span title="Employee / employer">{formatTaka(row.pf_employee)}<span className="block text-xs text-slate-400">+{formatTaka(row.pf_employer)} er</span></span>
          : <span className="text-slate-400">—</span>}
      </td>
    </>
  )
}

/** One payroll run: status, checks, actions allowed for the role, slips and payment sheets. */
export default function PayrollRunPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const ctx = useMyContext()
  const can = (permission: string) => ctx.permissions.includes(permission)
  const runQuery = usePayrollRun(id)
  const statutory = useRunStatutorySummary(id)
  const statutoryBySlip = useMemo(() => new Map((statutory.data ?? []).map((row) => [row.slip_id, row])), [statutory.data])
  const calculate = usePayrollAction<{ p_run_id: string }>('calculate_payroll_run')
  const review = usePayrollAction<{ p_run_id: string }>('review_payroll_run')
  const approve = usePayrollAction<{ p_run_id: string }>('approve_payroll_run')
  const cancel = usePayrollAction<{ p_run_id: string }>('cancel_payroll_run')
  const lock = usePayrollAction<{ p_run_id: string }>('lock_payroll_run')
  const markPaid = usePayrollAction<{ p_batch_id: string; p_reference: string | null }>('mark_payment_batch_paid')
  const [reopenOpen, setReopenOpen] = useState(false)
  const [openSlipId, setOpenSlipId] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [onlyFlagged, setOnlyFlagged] = useState(false)
  const [exportError, setExportError] = useState<string | null>(null)

  const slips = runQuery.data?.slips ?? []
  const visibleSlips = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return slips.filter((s) => (!onlyFlagged || s.warnings.length > 0)
      && (!needle || s.full_name.toLowerCase().includes(needle) || s.card_id.toLowerCase().includes(needle)))
  }, [slips, query, onlyFlagged])

  if (runQuery.isPending) return <PageLoader />
  if (runQuery.isError) return <Alert>{errorMessage(runQuery.error)}</Alert>
  const { run, batches } = runQuery.data
  const actionError = calculate.error ?? review.error ?? approve.error ?? cancel.error ?? lock.error ?? markPaid.error
  const isOpen = run.status === 'draft' || run.status === 'calculated' || run.status === 'reviewed'

  const downloadSheet = async (batchId: string, method: string) => {
    setExportError(null)
    try {
      const sheet = await fetchPaymentSheet(batchId)
      const csv = toCsv(
        ['Card ID', 'Name', 'Account name', 'Bank', 'Branch', 'Routing', 'Account number', 'Wallet', 'Wallet number', 'Amount (BDT)'],
        sheet.rows.map((r) => [r.card_id, r.full_name, r.account_name, r.bank_name, r.branch_name, r.routing_number,
          r.account_number, r.wallet_provider, r.wallet_number, Number(r.amount).toFixed(2)]),
      )
      downloadText(`payroll-${run.period_month.slice(0, 7)}-${method}.csv`, csv)
    } catch (err) {
      setExportError(errorMessage(err))
    }
  }

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <button onClick={() => navigate('/payroll')} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
        <ArrowLeft className="size-4" /> Payroll
      </button>
      <PageHeader
        title={`Payroll — ${formatPeriod(run.period_month)}`}
        description={run.scope === 'all' ? 'Whole organization' : `${run.scope === 'branch' ? 'Branch' : 'Department'}: ${run.scope_name ?? ''}`}
        actions={<RunStatusBadge status={run.status} />}
      />

      <Card className="space-y-4">
        <StatusStepper status={run.status} />
        <div className="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
          <div><p className="text-slate-500">Employees</p><p className="text-xl font-semibold tabular-nums">{run.employee_count}</p></div>
          <div><p className="text-slate-500">Gross</p><p className="text-xl font-semibold tabular-nums">{formatTaka(run.total_gross)}</p></div>
          <div><p className="text-slate-500">Deductions</p><p className="text-xl font-semibold tabular-nums">{formatTaka(run.total_deductions)}</p></div>
          <div><p className="text-slate-500">Net pay</p><p className="text-xl font-semibold tabular-nums text-primary-700">{formatTaka(run.total_net)}</p></div>
        </div>
        <p className="text-xs text-slate-500">
          Prepared by {run.prepared_by_name ?? '—'}
          {run.reviewed_by_name && <> · reviewed by {run.reviewed_by_name}</>}
          {run.approved_by_name && <> · approved by {run.approved_by_name}</>}
          {run.reopen_count > 0 && <> · reopened {run.reopen_count}×</>}
        </p>
      </Card>

      {run.is_stale && <Alert>Inputs changed after this run was calculated (attendance, overtime, pay, bonuses…). Recalculate before reviewing.</Alert>}
      {run.blocker_count > 0 && <Alert>{run.blocker_count} employee(s) have blockers. Fix them (e.g. set their pay) and recalculate.</Alert>}
      {run.run_warnings.map((w) => <Alert key={w.code} tone="info">{w.message}</Alert>)}
      {actionError && <Alert>{errorMessage(actionError)}</Alert>}

      <div className="flex flex-wrap gap-2">
        {isOpen && can('payroll.prepare') && (
          <Button variant="secondary" loading={calculate.isPending} onClick={() => calculate.mutate({ p_run_id: run.id })}>
            <RefreshCw className="size-4" />{run.status === 'draft' ? 'Calculate' : 'Recalculate'}
          </Button>
        )}
        {run.status === 'calculated' && can('payroll.review') && (
          <Button loading={review.isPending} disabled={run.is_stale || run.blocker_count > 0} onClick={() => review.mutate({ p_run_id: run.id })}>
            <ShieldCheck className="size-4" />Mark reviewed
          </Button>
        )}
        {run.status === 'reviewed' && can('payroll.approve') && (
          run.is_preparer
            ? <Badge tone="orange">You prepared this run — another person must approve it</Badge>
            : <Button loading={approve.isPending} disabled={run.is_stale}
                onClick={() => confirm('Approve this payroll? Slips are frozen and loan installments are posted.') && approve.mutate({ p_run_id: run.id })}>
                <Check className="size-4" />Approve
              </Button>
        )}
        {run.status === 'approved' && can('payroll.reopen') && (
          <Button variant="secondary" onClick={() => setReopenOpen(true)}><RotateCcw className="size-4" />Reopen</Button>
        )}
        {run.status === 'paid' && can('payroll.lock') && (
          <Button loading={lock.isPending}
            onClick={() => confirm('Lock this run? The month\'s attendance, leave and overtime become read-only.') && lock.mutate({ p_run_id: run.id })}>
            <Lock className="size-4" />Lock
          </Button>
        )}
        {isOpen && can('payroll.prepare') && (
          <Button variant="ghost" loading={cancel.isPending}
            onClick={() => confirm('Cancel this run? Its slips are removed.') && cancel.mutate({ p_run_id: run.id })}>
            <XCircle className="size-4" />Cancel run
          </Button>
        )}
      </div>

      {batches.length > 0 && (
        <Card>
          <h3 className="mb-3 font-semibold text-slate-900">Payment sheets</h3>
          {exportError && <div className="mb-3"><Alert>{exportError}</Alert></div>}
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {batches.map((batch) => (
              <div key={batch.id} className="rounded-xl border border-slate-200 p-4">
                <p className="text-sm font-medium text-slate-900">{METHOD_LABEL[batch.method]}</p>
                <p className="text-lg font-semibold tabular-nums">{formatTaka(batch.total)}</p>
                <p className="text-xs text-slate-500">{batch.row_count} employee(s) · {batch.status}</p>
                <div className="mt-3 flex flex-wrap gap-2">
                  {can('payment.export') && batch.method !== 'unassigned' && (
                    <Button variant="secondary" onClick={() => downloadSheet(batch.id, batch.method)}><Download className="size-4" />CSV</Button>
                  )}
                  {run.status === 'approved' && batch.status !== 'paid' && can('payroll.approve') && (
                    <Button variant="ghost" loading={markPaid.isPending}
                      onClick={() => {
                        const reference = prompt('Payment reference (bank or transaction ID), optional')
                        if (reference !== null) markPaid.mutate({ p_batch_id: batch.id, p_reference: reference || null })
                      }}>
                      Mark paid
                    </Button>
                  )}
                </div>
              </div>
            ))}
          </div>
          <p className="mt-3 text-xs text-slate-400">Downloads contain full account numbers and are recorded in the audit log.</p>
        </Card>
      )}

      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-56 flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name or card ID" aria-label="Search slips"
            className="w-full rounded-xl border border-slate-300 bg-white py-2 pl-9 pr-3 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
        </div>
        <label className="flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" className="accent-primary-600" checked={onlyFlagged} onChange={(e) => setOnlyFlagged(e.target.checked)} />
          Only with warnings
        </label>
      </div>

      <Table minWidth={1120} head={
        <tr><th className={th}>Employee</th><th className={th}>Pay</th><th className={th}>Payable days</th><th className={th}>OT (h)</th>
          <th className={th}>Gross</th><th className={th}>Deductions</th><th className={th} title="Income tax deducted (or preview when auto-TDS is off)">TDS</th><th className={th} title="Provident fund: employee / employer">PF</th><th className={th}>Net</th><th className={th}>Paid by</th><th className={th}>Checks</th></tr>
      }>
        {visibleSlips.map((slip) => (
          <tr key={slip.id} className="cursor-pointer hover:bg-slate-50" onClick={() => setOpenSlipId(slip.id)}>
            <td className={td}>
              <p className="font-medium text-slate-900">{slip.full_name}</p>
              <p className="text-xs text-slate-400"><span className="font-mono">{slip.card_id}</span>{slip.grade_code ? ` · ${slip.grade_code}` : ''}</p>
            </td>
            <td className={`${td} tabular-nums`}>{formatTaka(slip.monthly_gross)}</td>
            <td className={`${td} tabular-nums`}>{slip.payable_days}{slip.absent_days > 0 && <span className="text-xs text-red-600"> ({slip.absent_days} absent)</span>}</td>
            <td className={`${td} tabular-nums`}>{slip.overtime_minutes ? (slip.overtime_minutes / 60).toFixed(1) : '—'}</td>
            <td className={`${td} tabular-nums`}>{formatTaka(slip.gross_earnings)}</td>
            <td className={`${td} tabular-nums`}>{formatTaka(slip.total_deductions)}</td>
            <StatutoryCells row={statutoryBySlip.get(slip.id)} />
            <td className={`${td} tabular-nums font-semibold`}>{formatTaka(slip.net)}
              {slip.carry_forward_out > 0 && <span className="block text-xs font-normal text-red-600">carry {formatTaka(slip.carry_forward_out)}</span>}</td>
            <td className={td}>{slip.payment_method ? METHOD_LABEL[slip.payment_method] : <span className="text-slate-400">—</span>}</td>
            <td className={td}>
              {slip.warnings.map((w) => (
                <span key={w.code} title={w.message} className={cx('mr-1 inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs',
                  w.severity === 'blocker' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-800')}>
                  <AlertTriangle className="size-3" />{w.code.replace(/_/g, ' ')}
                </span>
              ))}
            </td>
          </tr>
        ))}
      </Table>
      {visibleSlips.length === 0 && <p className="text-center text-sm text-slate-400">No slips to show.</p>}

      <PayslipDialog slipId={openSlipId} onClose={() => setOpenSlipId(null)} />
      <ReopenDialog runId={run.id} open={reopenOpen} onClose={() => setReopenOpen(false)} />
      <p className="text-xs text-slate-400"><Link to="/payroll" className="hover:underline">All runs</Link></p>
    </div>
  )
}

function ReopenDialog({ runId, open, onClose }: { runId: string; open: boolean; onClose: () => void }) {
  const reopen = usePayrollAction<{ p_run_id: string; p_reason: string }>('reopen_payroll_run')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const submit = async () => {
    setError(null)
    try {
      await reopen.mutateAsync({ p_run_id: runId, p_reason: reason.trim() })
      setReason('')
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }
  return (
    <Modal open={open} onClose={onClose} size="sm" title="Reopen payroll run"
      description="Loan installments, arrears and adjustments posted by the approval are reversed. The reason goes to the audit log."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button variant="danger" loading={reopen.isPending} disabled={reason.trim().length < 5} onClick={submit}>Reopen</Button></>}>
      <div className="space-y-3">
        {error && <Alert>{error}</Alert>}
        <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}
