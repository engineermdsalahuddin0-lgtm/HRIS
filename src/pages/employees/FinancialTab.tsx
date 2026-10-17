// Employee profile → Financial tab: current pay with its lines, pay history,
// payment accounts (masked) and loans. Each card appears only when the role may
// see it; the employee sees their own payment accounts and loans, never the pay
// table itself (payslips come with Part 3B).
import { useState } from 'react'
import { Pencil, Plus, TrendingUp } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { PaymentAccountRow } from '@/lib/payroll'
import {
  CHANGE_LABEL, WALLET_LABEL, formatTaka, useDeductions, useEmployeeCompensation, useIncrements, usePaymentAccounts,
} from '@/lib/payroll'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, Spinner } from '@/components/ui'
import { DeductionTable } from '../salary/CompensationPage'
import {
  DeductionDialog, IncrementDialog, MaskedNumber, PaymentAccountDialog, ResolvedLines, SetPayDialog,
} from '../salary/dialogs'

/** Whether the Financial tab has anything to show for this viewer. */
export function canSeeFinancialTab(permissions: string[], isSelf: boolean): boolean {
  return isSelf || ['compensation.view', 'payment_accounts.view', 'payment_accounts.edit', 'deductions.manage']
    .some((permission) => permissions.includes(permission))
}

export function FinancialTab({ employee }: {
  employee: { id: string; full_name: string; join_date: string | null; status: string; is_self: boolean }
}) {
  const context = useMyContext()
  const can = (permission: string) => context.permissions.includes(permission)
  const isAdmin = context.role?.system_key === 'admin'
  // Nobody changes their own pay or payment data except the Admin (the database enforces the same rule).
  const mayChangeOwn = !employee.is_self || isAdmin
  const seePay = can('compensation.view')
  const seeAccounts = can('payment_accounts.view') || can('payment_accounts.edit') || employee.is_self
  const seeDeductions = can('compensation.view') || can('deductions.manage') || employee.is_self

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      {seePay && <PayCard employee={employee} canEdit={can('compensation.edit') && mayChangeOwn && employee.status === 'active'} />}
      {seeAccounts && (
        <AccountsCard employeeId={employee.id} canEdit={can('payment_accounts.edit') && mayChangeOwn} canReveal={can('payment_accounts.view')} />
      )}
      {seeDeductions && <DeductionsCard employeeId={employee.id} canAdd={can('deductions.manage') && mayChangeOwn} />}
    </div>
  )
}

function PayCard({ employee, canEdit }: { employee: { id: string; full_name: string; join_date: string | null }; canEdit: boolean }) {
  const history = useEmployeeCompensation(employee.id)
  const pending = useIncrements(employee.id)
  const [dialog, setDialog] = useState<'set' | 'increment' | null>(null)
  const current = history.data?.find((version) => !version.effective_to) ?? null
  const pendingChange = pending.data?.find((row) => row.status === 'pending')

  return (
    <>
      <Card>
        <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
          <h3 className="font-semibold text-slate-900">Current pay</h3>
          {canEdit && !history.isPending && (current
            ? !pendingChange && <Button variant="secondary" onClick={() => setDialog('increment')}><TrendingUp className="size-4" />Request change</Button>
            : <Button onClick={() => setDialog('set')}><Plus className="size-4" />Set starting pay</Button>)}
        </div>
        {history.isPending ? <Spinner /> : history.isError ? <Alert>{errorMessage(history.error)}</Alert> : !current ? (
          <p className="text-sm text-slate-500">No pay recorded yet.</p>
        ) : (
          <div className="space-y-3">
            <p className="text-sm text-slate-500">{current.template_name ?? 'No template'} · since {formatDate(current.effective_from)}</p>
            <ResolvedLines salary={{ gross: current.gross, total_deductions: current.total_deductions,
              lines: current.lines.map((line) => ({ ...line, component_id: line.code })) }} />
            {pendingChange && (
              <Alert tone="info">Pending {CHANGE_LABEL[pendingChange.type].toLowerCase()}: {formatTaka(pendingChange.new_gross)} from {formatDate(pendingChange.effective_date)}.</Alert>
            )}
          </div>
        )}
      </Card>
      <Card>
        <h3 className="mb-4 font-semibold text-slate-900">Pay history</h3>
        {history.isPending ? <Spinner /> : !history.data?.length ? <p className="text-sm text-slate-500">No history yet.</p> : (
          <ol className="relative space-y-4 border-l border-slate-200 pl-5">
            {history.data.map((version) => (
              <li key={version.id}>
                <span className="absolute -left-1.5 mt-1.5 size-3 rounded-full bg-primary-500 ring-4 ring-white" aria-hidden />
                <p className="text-sm font-medium text-slate-900">{formatTaka(version.gross)} <span className="font-normal text-slate-500">— {CHANGE_LABEL[version.change_type]}</span></p>
                <p className="text-xs text-slate-500">
                  {formatDate(version.effective_from)} – {version.effective_to ? formatDate(version.effective_to) : 'now'} · basic {formatTaka(version.basic)}
                </p>
                {version.reason && <p className="text-xs italic text-slate-400">{version.reason}</p>}
              </li>
            ))}
          </ol>
        )}
      </Card>
      <SetPayDialog open={dialog === 'set'} onClose={() => setDialog(null)} employee={employee} />
      <IncrementDialog open={dialog === 'increment'} onClose={() => setDialog(null)}
        employee={current && { id: employee.id, full_name: employee.full_name, gross: current.gross, template_id: current.template_id, effective_from: current.effective_from }} />
    </>
  )
}

function accountTitle(account: PaymentAccountRow): string {
  if (account.method === 'bank') return `${account.bank_name ?? 'Bank'}${account.branch_name ? ` · ${account.branch_name}` : ''}`
  if (account.method === 'mobile_wallet') return account.wallet_provider ? WALLET_LABEL[account.wallet_provider] : 'Mobile wallet'
  return 'Cash'
}

function AccountsCard({ employeeId, canEdit, canReveal }: { employeeId: string; canEdit: boolean; canReveal: boolean }) {
  const accounts = usePaymentAccounts(employeeId)
  const [editing, setEditing] = useState<PaymentAccountRow | 'new' | null>(null)
  return (
    <Card>
      <div className="mb-4 flex items-center justify-between">
        <h3 className="font-semibold text-slate-900">Payment accounts</h3>
        {canEdit && <Button variant="secondary" onClick={() => setEditing('new')}><Plus className="size-4" />Add</Button>}
      </div>
      {accounts.isPending ? <Spinner /> : accounts.isError ? <Alert>{errorMessage(accounts.error)}</Alert> : !accounts.data?.length ? (
        <p className="text-sm text-slate-500">No payment account yet. Salary would be paid in cash.</p>
      ) : (
        <ul className="divide-y divide-slate-100">
          {accounts.data.map((account) => (
            <li key={account.id} className={`flex flex-wrap items-center justify-between gap-2 py-3 ${account.status === 'inactive' ? 'opacity-50' : ''}`}>
              <div>
                <p className="text-sm font-medium text-slate-900">
                  {accountTitle(account)} {account.is_primary && <Badge tone="green">Primary</Badge>} {account.status === 'inactive' && <Badge>Inactive</Badge>}
                </p>
                <p className="text-sm text-slate-600"><MaskedNumber account={account} canReveal={canReveal} /></p>
                {account.account_name && <p className="text-xs text-slate-400">{account.account_name}</p>}
              </div>
              {canEdit && <Button variant="ghost" onClick={() => setEditing(account)} aria-label="Edit account"><Pencil className="size-4" /></Button>}
            </li>
          ))}
        </ul>
      )}
      <PaymentAccountDialog open={editing !== null} onClose={() => setEditing(null)} employeeId={employeeId}
        account={editing === 'new' ? null : editing} />
    </Card>
  )
}

function DeductionsCard({ employeeId, canAdd }: { employeeId: string; canAdd: boolean }) {
  const deductions = useDeductions(employeeId)
  const [adding, setAdding] = useState(false)
  return (
    <Card className="lg:col-span-2">
      <div className="mb-4 flex items-center justify-between">
        <h3 className="font-semibold text-slate-900">Loans & advances</h3>
        {canAdd && <Button variant="secondary" onClick={() => setAdding(true)}><Plus className="size-4" />Add</Button>}
      </div>
      {deductions.isPending ? <Spinner /> : deductions.isError ? <Alert>{errorMessage(deductions.error)}</Alert> : !deductions.data?.length ? (
        <p className="text-sm text-slate-500">No loans or advances.</p>
      ) : <DeductionTable rows={deductions.data} showEmployee={false} />}
      <DeductionDialog open={adding} onClose={() => setAdding(false)} employeeId={employeeId} />
    </Card>
  )
}
