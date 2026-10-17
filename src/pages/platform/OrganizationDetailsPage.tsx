import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Building2, CreditCard, Plus, Power, Users } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime, today } from '@/lib/options'
import { formatTaka, parseMoney } from '@/lib/payroll'
import type { OrganizationDetails, OrgPayment, PaymentStatus, SubscriptionStatus } from '@/lib/platform'
import { PAYMENT_METHODS, SUBSCRIPTION_LABELS, useOrganizationDetails, usePlatformAction, usePublicPlans } from '@/lib/platform'
import { Alert, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Textarea, td, th } from '@/components/kit'
import { OrgStatusBadge, PaymentBadge } from './PlatformDashboardPage'

const methodOptions = PAYMENT_METHODS.map((m) => ({ value: m, label: m === 'bkash' ? 'bKash' : m.charAt(0).toUpperCase() + m.slice(1) }))

/** Everything a platform admin needs about one organization. */
export default function OrganizationDetailsPage() {
  const { id } = useParams()
  const details = useOrganizationDetails(id)
  const [dialog, setDialog] = useState<'status' | 'subscription' | 'payment' | null>(null)
  const [paying, setPaying] = useState<OrgPayment | null>(null)

  if (details.isPending) return <PageLoader />
  if (details.isError) return <Alert>{errorMessage(details.error)}</Alert>
  const d = details.data
  const org = d.organization
  const close = () => setDialog(null)

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <Link to="/platform" className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
        <ArrowLeft className="size-4" /> Platform
      </Link>
      <PageHeader
        title={org.name}
        description={`Org code ${org.org_code} · joined ${formatDate(org.created_at)} · ${org.labor_regime === 'bd_epz_labour_act' ? 'EPZ Labour Act' : 'Labour Act 2006'}`}
        actions={
          <Button variant={org.status === 'active' ? 'danger' : 'primary'} onClick={() => setDialog('status')}>
            <Power className="size-4" />{org.status === 'active' ? 'Deactivate' : 'Activate'}
          </Button>
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card className="p-5"><p className="text-sm text-slate-500">Status</p><div className="mt-2"><OrgStatusBadge status={org.status} /></div></Card>
        <Card className="p-5"><p className="text-sm text-slate-500">Active employees</p><p className="mt-1 text-2xl font-semibold tabular-nums">{d.employees.active}</p></Card>
        <Card className="p-5"><p className="text-sm text-slate-500">Subscription</p><p className="mt-1 text-lg font-semibold">{d.subscription ? `${d.subscription.plan_name} · ${SUBSCRIPTION_LABELS[d.subscription.status]}` : '—'}</p></Card>
        <Card className="p-5"><p className="text-sm text-slate-500">Payment</p><div className="mt-2"><PaymentBadge status={d.payment_status} /></div></Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <h3 className="mb-4 flex items-center gap-2 font-semibold text-slate-900"><Users className="size-4" />Employee volume</h3>
          <dl className="grid grid-cols-2 gap-4 text-sm sm:grid-cols-3">
            <Stat label="Total" value={d.employees.total} />
            <Stat label="Active" value={d.employees.active} />
            <Stat label="Inactive" value={d.employees.inactive} />
            <Stat label="Terminated" value={d.employees.terminated} />
            <Stat label="Portal users" value={d.employees.portal_users} />
            <Stat label="Branches" value={d.employees.branches} />
          </dl>
          {d.subscription?.seats && d.employees.active > d.subscription.seats && (
            <div className="mt-4"><Alert>Active employees ({d.employees.active}) exceed the licensed seats ({d.subscription.seats}).</Alert></div>
          )}
        </Card>

        <Card>
          <div className="mb-4 flex items-center justify-between">
            <h3 className="flex items-center gap-2 font-semibold text-slate-900"><Building2 className="size-4" />Subscription</h3>
            <Button variant="secondary" onClick={() => setDialog('subscription')}>Change</Button>
          </div>
          {d.subscription ? (
            <dl className="grid grid-cols-2 gap-4 text-sm">
              <Field label="Plan" value={d.subscription.plan_name} />
              <Field label="Status" value={SUBSCRIPTION_LABELS[d.subscription.status]} />
              <Field label="Billing" value={d.subscription.billing_cycle === 'yearly' ? 'Yearly' : 'Monthly'} />
              <Field label="Seats" value={d.subscription.seats?.toString() ?? 'Unlimited'} />
              <Field label="Price / employee" value={d.subscription.price_per_employee === null ? 'Custom' : formatTaka(d.subscription.price_per_employee)} />
              <Field label="Current period ends" value={formatDate(d.subscription.current_period_end)} />
              {d.subscription.trial_ends_on && <Field label="Trial ends" value={formatDate(d.subscription.trial_ends_on)} />}
              {d.subscription.note && <div className="col-span-2"><Field label="Note" value={d.subscription.note} /></div>}
            </dl>
          ) : <p className="text-sm text-slate-500">No subscription.</p>}
        </Card>

        <Card>
          <h3 className="mb-4 font-semibold text-slate-900">Admins</h3>
          {d.admins.length === 0 ? <p className="text-sm text-slate-500">No active admin.</p> : (
            <ul className="divide-y divide-slate-100 text-sm">
              {d.admins.map((admin) => (
                <li key={(admin.email ?? '') + admin.full_name} className="py-2">
                  <p className="font-medium text-slate-900">{admin.full_name || '—'}</p>
                  <p className="text-xs text-slate-500">{[admin.email, admin.phone].filter(Boolean).join(' · ')}</p>
                  <p className="text-xs text-slate-400">Last login {admin.last_login_at ? formatDateTime(admin.last_login_at) : 'never'}</p>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <h3 className="mb-4 font-semibold text-slate-900">Application</h3>
          {d.application ? (
            <dl className="grid grid-cols-2 gap-4 text-sm">
              <Field label="Contact" value={d.application.contact_name} />
              <Field label="Email" value={d.application.applicant_email} />
              <Field label="Phone" value={d.application.contact_phone} />
              <Field label="Size" value={d.application.employee_range} />
              <Field label="Industry" value={d.application.industry} />
              <Field label="Interested plan" value={d.application.plan_interest} />
              <div className="col-span-2"><Field label="Address" value={d.application.address} /></div>
            </dl>
          ) : <p className="text-sm text-slate-500">Created before applications were recorded.</p>}
        </Card>
      </div>

      <Card className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="flex items-center gap-2 font-semibold text-slate-900"><CreditCard className="size-4" />Payments</h3>
            <p className="text-sm text-slate-500">Paid {formatTaka(d.payment_totals.paid)} · Outstanding {formatTaka(d.payment_totals.outstanding)}</p>
          </div>
          <Button onClick={() => setDialog('payment')}><Plus className="size-4" />Record invoice / payment</Button>
        </div>
        {d.payments.length === 0 ? <EmptyState title="No invoices or payments yet" /> : (
          <Table minWidth={760} head={
            <tr><th className={th}>Period</th><th className={th}>Amount</th><th className={th}>Due</th><th className={th}>Status</th>
              <th className={th}>Paid on</th><th className={th}>Method / ref.</th><th className={th} /></tr>
          }>
            {d.payments.map((p) => (
              <tr key={p.id}>
                <td className={td}>{formatDate(p.period_start)} – {formatDate(p.period_end)}</td>
                <td className={`${td} tabular-nums`}>{formatTaka(p.amount)}</td>
                <td className={td}>{formatDate(p.due_date)}</td>
                <td className={td}><PaymentBadge status={p.status} /></td>
                <td className={td}>{formatDate(p.paid_on)}</td>
                <td className={td}>{p.method ?? '—'}{p.reference && <span className="block font-mono text-xs text-slate-400">{p.reference}</span>}</td>
                <td className="px-4 py-3 text-right">
                  {(p.status === 'due' || p.status === 'overdue') && <Button variant="ghost" onClick={() => setPaying(p)}>Mark paid</Button>}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <StatusDialog open={dialog === 'status'} onClose={close} details={d} />
      <SubscriptionDialog open={dialog === 'subscription'} onClose={close} details={d} />
      <PaymentDialog open={dialog === 'payment'} onClose={close} orgId={org.id} />
      <MarkPaidDialog payment={paying} onClose={() => setPaying(null)} />
    </div>
  )
}

function Stat({ label, value }: { label: string; value: number }) {
  return <div><dt className="text-slate-500">{label}</dt><dd className="text-xl font-semibold tabular-nums text-slate-900">{value}</dd></div>
}

function Field({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-slate-400">{label}</dt>
      <dd className="mt-0.5 text-slate-800">{value || '—'}</dd>
    </div>
  )
}

function StatusDialog({ open, onClose, details }: { open: boolean; onClose: () => void; details: OrganizationDetails }) {
  const setStatus = usePlatformAction<{ p_org_id: string; p_status: string; p_note: string | null }>('platform_set_organization_status')
  const isActive = details.organization.status === 'active'
  const [nextStatus, setNextStatus] = useState<'suspended' | 'inactive'>('suspended')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setError(null)
    try {
      await setStatus.mutateAsync({ p_org_id: details.organization.id, p_status: isActive ? nextStatus : 'active', p_note: reason.trim() || null })
      setReason('')
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="sm" title={isActive ? 'Deactivate organization' : 'Activate organization'}
      description={details.organization.name}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button variant={isActive ? 'danger' : 'primary'} loading={setStatus.isPending} disabled={isActive && !reason.trim()} onClick={submit}>
          {isActive ? 'Deactivate' : 'Activate'}
        </Button>
      </>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        {isActive ? (
          <>
            <Alert tone="info">Everyone in this organization loses access on their next action. No data is deleted; you can activate it again.</Alert>
            <Select label="New status" value={nextStatus} onChange={(e) => setNextStatus(e.target.value as 'suspended' | 'inactive')}
              options={[{ value: 'suspended', label: 'Suspended (e.g. unpaid)' }, { value: 'inactive', label: 'Inactive (closed)' }]} />
            <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} />
          </>
        ) : (
          <Textarea label="Note (optional)" value={reason} onChange={(e) => setReason(e.target.value)} />
        )}
      </div>
    </Modal>
  )
}

function SubscriptionDialog({ open, onClose, details }: { open: boolean; onClose: () => void; details: OrganizationDetails }) {
  const plans = usePublicPlans()
  const update = usePlatformAction<Record<string, unknown>>('platform_update_subscription')
  const current = details.subscription
  const [form, setForm] = useState({
    plan: current?.plan_code ?? 'TRIAL',
    status: (current?.status ?? 'trial') as SubscriptionStatus,
    cycle: current?.billing_cycle ?? 'monthly',
    seats: current?.seats?.toString() ?? '',
    price: current?.price_per_employee?.toString() ?? '',
    periodEnd: current?.current_period_end ?? '',
    note: current?.note ?? '',
  })
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setError(null)
    const price = form.price.trim() === '' ? null : parseMoney(form.price)
    if (form.price.trim() !== '' && price === null) return setError('Price must be a number with up to 2 decimals')
    const seats = form.seats.trim() === '' ? null : Number(form.seats)
    if (seats !== null && (!Number.isInteger(seats) || seats <= 0)) return setError('Seats must be a whole number above zero')
    try {
      await update.mutateAsync({
        p_org_id: details.organization.id, p_plan_code: form.plan, p_status: form.status, p_billing_cycle: form.cycle,
        p_seats: seats, p_price_per_employee: price, p_current_period_end: form.periodEnd || null, p_note: form.note.trim() || null,
      })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="md" title="Change subscription" description={details.organization.name}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={update.isPending} onClick={submit}>Save</Button></>}>
      <div className="grid gap-4 sm:grid-cols-2">
        {error && <div className="sm:col-span-2"><Alert>{error}</Alert></div>}
        <Select label="Plan" value={form.plan} onChange={(e) => setForm({ ...form, plan: e.target.value })}
          options={(plans.data ?? []).map((p) => ({ value: p.code, label: p.name }))} />
        <Select label="Status" value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as SubscriptionStatus })}
          options={(Object.keys(SUBSCRIPTION_LABELS) as SubscriptionStatus[]).map((s) => ({ value: s, label: SUBSCRIPTION_LABELS[s] }))} />
        <Select label="Billing cycle" value={form.cycle} onChange={(e) => setForm({ ...form, cycle: e.target.value as 'monthly' | 'yearly' })}
          options={[{ value: 'monthly', label: 'Monthly' }, { value: 'yearly', label: 'Yearly' }]} />
        <Input label="Seats (licensed employees)" name="seats" inputMode="numeric" value={form.seats} onChange={(e) => setForm({ ...form, seats: e.target.value })} hint="Empty = unlimited" />
        <Input label="Price per employee (৳)" name="price" inputMode="decimal" value={form.price} onChange={(e) => setForm({ ...form, price: e.target.value })} hint="Empty = custom / contract" />
        <Input label="Current period ends" type="date" name="period_end" value={form.periodEnd} onChange={(e) => setForm({ ...form, periodEnd: e.target.value })} />
        <Textarea label="Note" className="sm:col-span-2" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
      </div>
    </Modal>
  )
}

function PaymentDialog({ open, onClose, orgId }: { open: boolean; onClose: () => void; orgId: string }) {
  const record = usePlatformAction<Record<string, unknown>, string>('platform_record_payment')
  const [form, setForm] = useState({
    periodStart: today().slice(0, 8) + '01', periodEnd: today(), amount: '', dueDate: today(),
    status: 'due' as PaymentStatus, paidOn: today(), method: 'bank', reference: '', note: '',
  })
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    setError(null)
    const amount = parseMoney(form.amount)
    if (amount === null) return setError('Enter the amount in taka (up to 2 decimals)')
    try {
      await record.mutateAsync({
        p_org_id: orgId, p_period_start: form.periodStart, p_period_end: form.periodEnd, p_amount: amount,
        p_due_date: form.dueDate, p_status: form.status, p_paid_on: form.status === 'paid' ? form.paidOn : null,
        p_method: form.status === 'paid' ? form.method : null, p_reference: form.reference.trim() || null, p_note: form.note.trim() || null,
      })
      setForm({ ...form, amount: '', reference: '', note: '' })
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="md" title="Record invoice or payment"
      description="Payments are recorded by hand until a payment gateway is connected. Every entry is audited."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={record.isPending} onClick={submit}>Save</Button></>}>
      <div className="grid gap-4 sm:grid-cols-2">
        {error && <div className="sm:col-span-2"><Alert>{error}</Alert></div>}
        <Input label="Period from" type="date" name="p_from" value={form.periodStart} onChange={(e) => setForm({ ...form, periodStart: e.target.value })} />
        <Input label="Period to" type="date" name="p_to" value={form.periodEnd} onChange={(e) => setForm({ ...form, periodEnd: e.target.value })} />
        <Input label="Amount (৳)" name="amount" inputMode="decimal" value={form.amount} onChange={(e) => setForm({ ...form, amount: e.target.value })} />
        <Input label="Due date" type="date" name="due" value={form.dueDate} onChange={(e) => setForm({ ...form, dueDate: e.target.value })} />
        <Select label="Status" value={form.status} onChange={(e) => setForm({ ...form, status: e.target.value as PaymentStatus })}
          options={[{ value: 'due', label: 'Due (invoice)' }, { value: 'paid', label: 'Paid' }, { value: 'waived', label: 'Waived' }]} />
        {form.status === 'paid' && (
          <>
            <Input label="Received on" type="date" name="paid_on" value={form.paidOn} onChange={(e) => setForm({ ...form, paidOn: e.target.value })} />
            <Select label="Method" value={form.method} onChange={(e) => setForm({ ...form, method: e.target.value })} options={methodOptions} />
          </>
        )}
        <Input label="Reference / transaction ID" name="reference" value={form.reference} onChange={(e) => setForm({ ...form, reference: e.target.value })} />
        <Textarea label="Note" className="sm:col-span-2" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
      </div>
    </Modal>
  )
}

function MarkPaidDialog({ payment, onClose }: { payment: OrgPayment | null; onClose: () => void }) {
  const update = usePlatformAction<Record<string, unknown>>('platform_update_payment')
  const [paidOn, setPaidOn] = useState(today())
  const [method, setMethod] = useState('bank')
  const [reference, setReference] = useState('')
  const [error, setError] = useState<string | null>(null)

  const submit = async () => {
    if (!payment) return
    setError(null)
    try {
      await update.mutateAsync({ p_payment_id: payment.id, p_status: 'paid', p_paid_on: paidOn, p_method: method, p_reference: reference.trim() || null })
      setReference('')
      onClose()
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  return (
    <Modal open={!!payment} onClose={onClose} size="sm" title="Mark as paid"
      description={payment ? `${formatTaka(payment.amount)} · ${formatDate(payment.period_start)} – ${formatDate(payment.period_end)}` : undefined}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={update.isPending} onClick={submit}>Mark paid</Button></>}>
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Input label="Received on" type="date" name="mp_paid_on" value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
        <Select label="Method" value={method} onChange={(e) => setMethod(e.target.value)} options={methodOptions} />
        <Input label="Reference / transaction ID" name="mp_ref" value={reference} onChange={(e) => setReference(e.target.value)} />
        <p className="text-xs text-slate-400">This change is written to the organization's audit log.</p>
      </div>
    </Modal>
  )
}
