// Money dialogs shared by the Compensation page and the employee Financial tab.
// Every amount is validated here for a friendly message, and again by the
// database, which is the only place an amount is calculated and stored.
import { useEffect, useState } from 'react'
import { Eye, EyeOff } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { today } from '@/lib/options'
import type { IncrementType, PaymentAccountRow, PaymentMethod, ResolvedSalary } from '@/lib/payroll'
import {
  CALC_LABEL, WALLET_LABEL, formatTaka, installmentSchedule, parseMoney, revealPaymentAccount, usePayrollAction,
  useSalaryConfig, useSalaryPreview,
} from '@/lib/payroll'
import { useEmployeeOptions } from '@/lib/hr'
import { Alert, Button, Input, Spinner } from '@/components/ui'
import { Checkbox, Modal, Select, Textarea } from '@/components/kit'

/** Waits until typing pauses before a value is used for a server preview. */
function useDebounced<T>(value: T, delayMs = 400): T {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delayMs)
    return () => clearTimeout(timer)
  }, [value, delayMs])
  return debounced
}

/** Resolved lines of a salary preview, as the payslip will show them. */
export function ResolvedLines({ salary }: { salary: Pick<ResolvedSalary, 'lines' | 'gross' | 'total_deductions'> }) {
  return (
    <div className="overflow-hidden rounded-xl ring-1 ring-slate-200">
      <table className="w-full text-sm">
        <tbody className="divide-y divide-slate-100">
          {salary.lines.map((line) => (
            <tr key={line.code}>
              <td className="px-3 py-2 text-slate-700">
                {line.name}
                <span className="ml-2 text-xs text-slate-400">
                  {line.rate !== null ? `${line.rate}${CALC_LABEL[line.calc]}` : line.kind === 'deduction' ? 'deduction' : ''}
                </span>
              </td>
              <td className={`px-3 py-2 text-right tabular-nums ${line.kind === 'deduction' ? 'text-red-600' : 'text-slate-900'}`}>
                {line.kind === 'deduction' ? '−' : ''}{formatTaka(line.amount)}
              </td>
            </tr>
          ))}
          <tr className="bg-slate-50 font-semibold">
            <td className="px-3 py-2 text-slate-900">Gross</td>
            <td className="px-3 py-2 text-right tabular-nums text-slate-900">{formatTaka(salary.gross)}</td>
          </tr>
          {salary.total_deductions > 0 && (
            <tr className="text-slate-600">
              <td className="px-3 py-2">Fixed deductions</td>
              <td className="px-3 py-2 text-right tabular-nums">−{formatTaka(salary.total_deductions)}</td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  )
}

function ServerPreview({ templateId, basic, gross }: { templateId: string; basic: number | null; gross: number | null }) {
  const preview = useSalaryPreview(templateId, useDebounced(basic), useDebounced(gross))
  if (!templateId || (basic === null && gross === null)) return null
  if (preview.isPending) return <Spinner />
  if (preview.isError) return <Alert>{errorMessage(preview.error)}</Alert>
  return <ResolvedLines salary={preview.data} />
}

// --------------------------------------------------------------- starting pay --
export function SetPayDialog({ open, onClose, employee }: {
  open: boolean; onClose: () => void; employee: { id: string; full_name: string; join_date: string | null } | null
}) {
  const config = useSalaryConfig(open)
  const setPay = usePayrollAction<{
    p_employee_id: string; p_template_id: string; p_basic: number | null; p_gross: number | null; p_effective_from: string; p_reason: string | null
  }>('set_initial_compensation')
  const [templateId, setTemplateId] = useState('')
  const [mode, setMode] = useState<'basic' | 'gross'>('gross')
  const [amountText, setAmountText] = useState('')
  const [effectiveFrom, setEffectiveFrom] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setTemplateId(''); setAmountText(''); setReason(''); setError(null); setMode('gross')
      setEffectiveFrom(employee?.join_date ?? today())
    }
  }, [open, employee])

  const activeTemplates = (config.data?.templates ?? []).filter((t) => t.status === 'active')
  const amount = parseMoney(amountText)
  const chosenTemplate = activeTemplates.find((t) => t.id === templateId)

  const submit = async () => {
    if (!employee || !templateId || amount === null) return
    setError(null)
    try {
      await setPay.mutateAsync({
        p_employee_id: employee.id, p_template_id: templateId, p_basic: mode === 'basic' ? amount : null,
        p_gross: mode === 'gross' ? amount : null, p_effective_from: effectiveFrom, p_reason: reason.trim() || null,
      })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="lg" title="Set starting pay"
      description={employee ? `${employee.full_name} — later changes go through an increment and need approval.` : undefined}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button disabled={!templateId || amount === null || !effectiveFrom} loading={setPay.isPending} onClick={submit}>Save pay</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        {config.isError && <Alert>{errorMessage(config.error)}</Alert>}
        <Select label="Salary template" value={templateId} onChange={(e) => {
          setTemplateId(e.target.value)
          const template = activeTemplates.find((t) => t.id === e.target.value)
          if (template && !amountText) { setMode('basic'); setAmountText(String(template.basic_amount)) }
        }} placeholder="Select…" options={activeTemplates.map((t) => ({ value: t.id, label: t.name }))}
          hint={activeTemplates.length === 0 ? 'Create a salary template first (Salary structure).' : undefined} />
        <div className="grid gap-4 sm:grid-cols-2">
          <Select label="Enter amount as" value={mode} onChange={(e) => setMode(e.target.value as 'basic' | 'gross')}
            options={[{ value: 'gross', label: 'Gross (basic is worked out)' }, { value: 'basic', label: 'Basic' }]} />
          <Input label={mode === 'gross' ? 'Monthly gross (৳)' : 'Monthly basic (৳)'} name="pay_amount" inputMode="decimal"
            value={amountText} onChange={(e) => setAmountText(e.target.value)}
            error={amountText && amount === null ? 'Enter an amount with up to 2 decimals' : undefined}
            placeholder={chosenTemplate ? String(chosenTemplate.basic_amount) : ''} />
        </div>
        <Input label="Effective from" type="date" name="pay_effective_from" value={effectiveFrom} min={employee?.join_date ?? undefined}
          onChange={(e) => setEffectiveFrom(e.target.value)} />
        <Textarea label="Note (optional)" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        <ServerPreview templateId={templateId} basic={mode === 'basic' ? amount : null} gross={mode === 'gross' ? amount : null} />
      </div>
    </Modal>
  )
}

// ----------------------------------------------------------------- increment --
export function IncrementDialog({ open, onClose, employee }: {
  open: boolean; onClose: () => void
  employee: { id: string; full_name: string; gross: number | null; template_id: string | null; effective_from: string | null } | null
}) {
  const config = useSalaryConfig(open)
  const request = usePayrollAction<{ p_employee_id: string; p: Record<string, unknown> }>('request_increment')
  const [type, setType] = useState<IncrementType>('increment')
  const [templateId, setTemplateId] = useState('')
  const [grossText, setGrossText] = useState('')
  const [effectiveDate, setEffectiveDate] = useState(today())
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setType('increment'); setTemplateId(employee?.template_id ?? ''); setGrossText(''); setReason(''); setError(null)
      setEffectiveDate(today())
    }
  }, [open, employee])

  const newGross = parseMoney(grossText)
  const change = newGross !== null && employee?.gross ? newGross - employee.gross : null
  const submit = async () => {
    if (!employee || newGross === null) return
    setError(null)
    try {
      await request.mutateAsync({
        p_employee_id: employee.id,
        p: { type, template_id: templateId || null, new_gross: newGross, effective_date: effectiveDate, reason: reason.trim() },
      })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="lg" title="Request a pay change"
      description={employee ? `${employee.full_name} — current gross ${formatTaka(employee.gross)}. Someone other than you must approve it.` : undefined}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button disabled={newGross === null || reason.trim().length < 3} loading={request.isPending} onClick={submit}>Send for approval</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <div className="grid gap-4 sm:grid-cols-2">
          <Select label="Type" value={type} onChange={(e) => setType(e.target.value as IncrementType)}
            options={[{ value: 'increment', label: 'Increment' }, { value: 'promotion', label: 'Promotion' }, { value: 'correction', label: 'Correction' }]} />
          <Select label="Salary template" value={templateId} onChange={(e) => setTemplateId(e.target.value)}
            options={(config.data?.templates ?? []).filter((t) => t.status === 'active').map((t) => ({ value: t.id, label: t.name }))} />
          <Input label="New monthly gross (৳)" name="new_gross" inputMode="decimal" value={grossText} onChange={(e) => setGrossText(e.target.value)}
            error={grossText && newGross === null ? 'Enter an amount with up to 2 decimals' : undefined}
            hint={change !== null && employee?.gross ? `${change >= 0 ? '+' : ''}${formatTaka(change)} (${((change / employee.gross) * 100).toFixed(1)}%)` : undefined} />
          <Input label="Effective date" type="date" name="increment_effective" value={effectiveDate} onChange={(e) => setEffectiveDate(e.target.value)}
            hint="A date in an already-paid month creates arrears" />
        </div>
        <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        <ServerPreview templateId={templateId} basic={null} gross={newGross} />
      </div>
    </Modal>
  )
}

// ------------------------------------------------------------ loan / advance --
export function DeductionDialog({ open, onClose, employeeId }: { open: boolean; onClose: () => void; employeeId?: string }) {
  const people = useEmployeeOptions(open && !employeeId)
  const create = usePayrollAction<{ p: Record<string, unknown> }>('create_deduction')
  const [personId, setPersonId] = useState('')
  const [type, setType] = useState<'loan' | 'advance' | 'other'>('loan')
  const [description, setDescription] = useState('')
  const [totalText, setTotalText] = useState('')
  const [installmentText, setInstallmentText] = useState('')
  const [startMonth, setStartMonth] = useState(today().slice(0, 7))
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (open) {
      setPersonId(employeeId ?? ''); setType('loan'); setDescription(''); setTotalText(''); setInstallmentText('')
      setStartMonth(today().slice(0, 7)); setError(null)
    }
  }, [open, employeeId])

  const total = parseMoney(totalText)
  const installment = parseMoney(installmentText)
  const schedule = total && installment && installment <= total ? installmentSchedule(total, installment, startMonth) : []
  const submit = async () => {
    setError(null)
    try {
      await create.mutateAsync({ p: {
        employee_id: personId, type, description: description.trim() || null, total, installment, start_month: `${startMonth}-01`,
      } })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="lg" title="Add loan or advance"
      description="Installments are deducted by payroll every month until the balance is zero."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button disabled={!personId || schedule.length === 0} loading={create.isPending} onClick={submit}>Save</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        {!employeeId && (
          <Select label="Employee" value={personId} onChange={(e) => setPersonId(e.target.value)} placeholder="Select…"
            options={(people.data ?? []).map((p) => ({ value: p.id, label: `${p.full_name} (${p.card_id})` }))} />
        )}
        <div className="grid gap-4 sm:grid-cols-2">
          <Select label="Type" value={type} onChange={(e) => setType(e.target.value as typeof type)}
            options={[{ value: 'loan', label: 'Loan' }, { value: 'advance', label: 'Salary advance' }, { value: 'other', label: 'Other deduction' }]} />
          <Input label="First deduction month" type="month" name="deduction_start" value={startMonth} onChange={(e) => e.target.value && setStartMonth(e.target.value)} />
          <Input label="Total (৳)" name="deduction_total" inputMode="decimal" value={totalText} onChange={(e) => setTotalText(e.target.value)}
            error={totalText && total === null ? 'Enter an amount with up to 2 decimals' : undefined} />
          <Input label="Monthly installment (৳)" name="deduction_installment" inputMode="decimal" value={installmentText}
            onChange={(e) => setInstallmentText(e.target.value)}
            error={installment !== null && total !== null && installment > total ? 'Cannot be more than the total' : undefined} />
        </div>
        <Input label="Description" name="deduction_description" value={description} maxLength={300} onChange={(e) => setDescription(e.target.value)} />
        {schedule.length > 0 && (
          <div>
            <p className="mb-2 text-sm font-medium text-slate-700">Schedule ({schedule.length} months)</p>
            <div className="max-h-48 overflow-y-auto rounded-xl ring-1 ring-slate-200">
              <table className="w-full text-sm">
                <tbody className="divide-y divide-slate-100">
                  {schedule.map((row) => (
                    <tr key={row.month}>
                      <td className="px-3 py-1.5 text-slate-600">{row.month}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums">{formatTaka(row.amount)}</td>
                      <td className="px-3 py-1.5 text-right tabular-nums text-slate-400">left {formatTaka(row.remaining)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </Modal>
  )
}

// ----------------------------------------------------------- payment account --
export function PaymentAccountDialog({ open, onClose, employeeId, account }: {
  open: boolean; onClose: () => void; employeeId: string; account: PaymentAccountRow | null
}) {
  const save = usePayrollAction<{ p_account_id: string | null; p: Record<string, unknown> }>('save_payment_account')
  const [method, setMethod] = useState<PaymentMethod>('bank')
  const [values, setValues] = useState<Record<string, string>>({})
  const [isPrimary, setIsPrimary] = useState(true)
  const [isActive, setIsActive] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const set = (key: string) => (e: { target: { value: string } }) => setValues((v) => ({ ...v, [key]: e.target.value }))

  useEffect(() => {
    if (!open) return
    setError(null)
    setMethod(account?.method ?? 'bank')
    setIsPrimary(account?.is_primary ?? true)
    setIsActive((account?.status ?? 'active') === 'active')
    // The stored number is never loaded into the form; leaving it empty keeps it.
    setValues({
      bank_name: account?.bank_name ?? '', branch_name: account?.branch_name ?? '', routing_number: account?.routing_number ?? '',
      account_name: account?.account_name ?? '', account_number: '', wallet_provider: account?.wallet_provider ?? 'bkash', wallet_number: '',
    })
  }, [open, account])

  const submit = async () => {
    setError(null)
    try {
      await save.mutateAsync({ p_account_id: account?.id ?? null, p: {
        ...values, employee_id: employeeId, method, is_primary: isPrimary, status: isActive ? 'active' : 'inactive',
      } })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  const numberHint = account ? `Stored ${account.masked_number ?? ''} — leave empty to keep it` : undefined
  return (
    <Modal open={open} onClose={onClose} size="lg" title={account ? 'Edit payment account' : 'Add payment account'}
      description="Account and wallet numbers are stored encrypted and shown masked."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={save.isPending} onClick={submit}>Save</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Method" value={method} disabled={!!account} onChange={(e) => setMethod(e.target.value as PaymentMethod)}
          options={[{ value: 'bank', label: 'Bank account' }, { value: 'mobile_wallet', label: 'Mobile wallet' }, { value: 'cash', label: 'Cash' }]} />
        {method === 'bank' && (
          <div className="grid gap-4 sm:grid-cols-2">
            <Input label="Bank name" name="bank_name" value={values.bank_name ?? ''} onChange={set('bank_name')} maxLength={120} />
            <Input label="Branch" name="branch_name" value={values.branch_name ?? ''} onChange={set('branch_name')} maxLength={120} />
            <Input label="Account name" name="account_name" value={values.account_name ?? ''} onChange={set('account_name')} maxLength={150} />
            <Input label="Account number" name="account_number" inputMode="numeric" autoComplete="off" value={values.account_number ?? ''}
              onChange={set('account_number')} hint={numberHint} maxLength={30} />
            <Input label="Routing number (optional)" name="routing_number" inputMode="numeric" value={values.routing_number ?? ''}
              onChange={set('routing_number')} hint="9 digits" maxLength={9} />
          </div>
        )}
        {method === 'mobile_wallet' && (
          <div className="grid gap-4 sm:grid-cols-2">
            <Select label="Provider" value={values.wallet_provider ?? 'bkash'} onChange={set('wallet_provider')}
              options={Object.entries(WALLET_LABEL).map(([value, label]) => ({ value, label }))} />
            <Input label="Wallet number" name="wallet_number" inputMode="tel" autoComplete="off" value={values.wallet_number ?? ''}
              onChange={set('wallet_number')} hint={numberHint ?? '01XXXXXXXXX'} maxLength={16} />
            <Input label="Account name" name="wallet_account_name" value={values.account_name ?? ''} onChange={set('account_name')} maxLength={150} />
          </div>
        )}
        <div className="flex flex-wrap gap-6">
          <Checkbox label="Primary account for salary" checked={isPrimary} onChange={setIsPrimary} disabled={!isActive} />
          {account && <Checkbox label="Active" checked={isActive} onChange={setIsActive} />}
        </div>
      </div>
    </Modal>
  )
}

/** Masked number with an audited "show" button for roles allowed to see it. */
export function MaskedNumber({ account, canReveal }: { account: PaymentAccountRow; canReveal: boolean }) {
  const [revealed, setRevealed] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Hide the number again after 30 seconds so it does not stay on screen.
  useEffect(() => {
    if (!revealed) return
    const timer = setTimeout(() => setRevealed(null), 30_000)
    return () => clearTimeout(timer)
  }, [revealed])

  if (!account.masked_number) return <span className="text-slate-400">—</span>
  const toggle = async () => {
    if (revealed) return setRevealed(null)
    setError(null)
    setLoading(true)
    try {
      setRevealed(await revealPaymentAccount(account.id))
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setLoading(false)
    }
  }
  return (
    <span className="inline-flex items-center gap-2">
      <span className="font-mono tabular-nums">{revealed ?? account.masked_number}</span>
      {canReveal && (
        <button type="button" onClick={toggle} disabled={loading} title={revealed ? 'Hide' : 'Show full number (audited)'}
          className="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label={revealed ? 'Hide number' : 'Show full number'}>
          {loading ? <Spinner className="size-4" /> : revealed ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
        </button>
      )}
      {error && <span className="text-xs text-red-600">{error}</span>}
    </span>
  )
}
