import { useState } from 'react'
import { Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { LeaveRequestRow } from '@/lib/time'
import { useLeaveBalances, useLeaveRequests, useTimeAction, useTimeConfig } from '@/lib/time'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Spinner } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'

type Tab = 'mine' | 'approvals' | 'all'

const TONE = { pending: 'orange', approved: 'green', rejected: 'red', cancelled: 'slate' } as const

export default function LeavePage() {
  const ctx = useMyContext()
  const can = (p: string) => ctx.permissions.includes(p)
  const tabs: { key: Tab; label: string }[] = [
    ...(can('leave.request') ? [{ key: 'mine' as Tab, label: 'My leave' }] : []),
    ...(can('leave.approve') ? [{ key: 'approvals' as Tab, label: 'Approvals' }] : []),
    ...(can('leave.view_all') ? [{ key: 'all' as Tab, label: 'All requests' }] : []),
  ]
  const [tab, setTab] = useState<Tab>(tabs[0]?.key ?? 'mine')
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Leave" description="Requests go to your reporting manager; HR decides when there is none. Nobody approves their own leave." />
      {tabs.length > 1 && <Tabs tabs={tabs} value={tab} onChange={setTab} />}
      {tab === 'mine' && <MyLeave />}
      {tab === 'approvals' && <RequestList filter={{ status: 'pending' }} decideOnly />}
      {tab === 'all' && <RequestList filter={{}} />}
    </div>
  )
}

function MyLeave() {
  const year = new Date().getFullYear()
  const balances = useLeaveBalances(undefined, year)
  const [open, setOpen] = useState(false)
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h3 className="font-semibold text-slate-900">Balances {year}</h3>
        <Button onClick={() => setOpen(true)}><Plus className="size-4" />Request leave</Button>
      </div>
      {balances.isPending ? <Spinner /> : balances.isError ? <Alert>{errorMessage(balances.error)}</Alert> : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {balances.data.map((b) => (
            <Card key={b.leave_type_id} className="p-4">
              <p className="text-xs font-medium text-slate-500">{b.name} <span className="font-mono">({b.code})</span></p>
              <p className="mt-1 text-2xl font-semibold tabular-nums text-slate-900">{b.available ?? '∞'}</p>
              <p className="text-xs text-slate-500">
                {b.entitled === null ? 'No limit' : `of ${Number(b.entitled) + Number(b.carried_forward)}`} · used {b.used}{Number(b.pending) > 0 ? ` · ${b.pending} pending` : ''}
              </p>
              {!b.paid && <Badge>Unpaid</Badge>}
            </Card>
          ))}
        </div>
      )}
      <RequestList filter={{ self: true }} mine />
      <RequestDialog open={open} onClose={() => setOpen(false)} />
    </div>
  )
}

function RequestList({ filter, decideOnly, mine }: { filter: { self?: boolean; status?: string }; decideOnly?: boolean; mine?: boolean }) {
  const list = useLeaveRequests(filter)
  const decide = useTimeAction<{ p_request_id: string; p_approve: boolean; p_note: string | null }>('decide_leave')
  const cancel = useTimeAction<{ p_request_id: string; p_reason: string | null }>('cancel_leave')
  const [deciding, setDeciding] = useState<{ row: LeaveRequestRow; approve: boolean } | null>(null)
  const [note, setNote] = useState('')
  const rows = (list.data ?? []).filter((r) => !decideOnly || r.can_decide)

  if (list.isPending) return <Spinner />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  return (
    <div className="space-y-3">
      {mine && <h3 className="font-semibold text-slate-900">My requests</h3>}
      {(decide.isError || cancel.isError) && <Alert>{errorMessage(decide.error ?? cancel.error)}</Alert>}
      {rows.length === 0 ? <EmptyState title={decideOnly ? 'Nothing waiting for you' : 'No leave requests'} /> : (
        <Table minWidth={780} head={
          <tr>
            {!mine && <th className={th}>Employee</th>}
            <th className={th}>Type</th><th className={th}>Dates</th><th className={th}>Days</th><th className={th}>Reason</th>
            <th className={th}>Status</th><th className={th} />
          </tr>
        }>
          {rows.map((r) => (
            <tr key={r.id}>
              {!mine && <td className={td}><p className="font-medium text-slate-900">{r.full_name}</p><p className="text-xs text-slate-400">{r.department_name ?? ''}</p></td>}
              <td className={td}>{r.leave_type_name}</td>
              <td className={td}>{formatDate(r.from_date)}{r.to_date !== r.from_date && <> → {formatDate(r.to_date)}</>}{r.half_day && ' (half)'}</td>
              <td className={td}>{r.days}</td>
              <td className={`${td} max-w-56 truncate`} title={r.reason ?? ''}>{r.reason ?? '—'}</td>
              <td className={td}>
                <Badge tone={TONE[r.status]}>{r.status}</Badge>
                {r.decision_note && <p className="mt-0.5 text-xs italic text-slate-400">{r.decision_note}</p>}
              </td>
              <td className="px-4 py-3 text-right">
                <div className="flex justify-end gap-2">
                  {r.can_decide && (
                    <>
                      <Button onClick={() => { setNote(''); setDeciding({ row: r, approve: true }) }}>Approve</Button>
                      <Button variant="secondary" onClick={() => { setNote(''); setDeciding({ row: r, approve: false }) }}>Reject</Button>
                    </>
                  )}
                  {r.is_self && (r.status === 'pending' || r.status === 'approved') && (
                    <Button variant="ghost" loading={cancel.isPending}
                      onClick={() => confirm('Cancel this leave request?') && cancel.mutate({ p_request_id: r.id, p_reason: null })}>
                      Cancel
                    </Button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </Table>
      )}
      <Modal open={!!deciding} onClose={() => setDeciding(null)} size="sm"
        title={deciding?.approve ? 'Approve leave' : 'Reject leave'}
        description={deciding ? `${deciding.row.full_name} · ${deciding.row.leave_type_name} · ${deciding.row.days} day(s)` : undefined}
        footer={<>
          <Button variant="secondary" onClick={() => setDeciding(null)}>Cancel</Button>
          <Button variant={deciding?.approve ? 'primary' : 'danger'} loading={decide.isPending}
            onClick={async () => {
              if (!deciding) return
              await decide.mutateAsync({ p_request_id: deciding.row.id, p_approve: deciding.approve, p_note: note || null }).catch(() => null)
              setDeciding(null)
            }}>
            {deciding?.approve ? 'Approve' : 'Reject'}
          </Button>
        </>}
      >
        <Textarea label="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
      </Modal>
    </div>
  )
}

function RequestDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const config = useTimeConfig()
  const request = useTimeAction<{ p_leave_type_id: string; p_from: string; p_to: string; p_half_day: boolean; p_reason: string }>('request_leave')
  const [type, setType] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [half, setHalf] = useState(false)
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const types = (config.data?.leaveTypes ?? []).filter((t) => t.status === 'active')
  const t = types.find((x) => x.id === type)

  const submit = async () => {
    setError(null)
    try {
      await request.mutateAsync({ p_leave_type_id: type, p_from: from, p_to: half ? from : to || from, p_half_day: half, p_reason: reason })
      setType(''); setFrom(''); setTo(''); setHalf(false); setReason('')
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="sm" title="Request leave"
      description="Weekly offs and holidays inside the range are not counted (unless the leave type says so)."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!type || !from} loading={request.isPending} onClick={submit}>Submit</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Leave type" value={type} onChange={(e) => setType(e.target.value)} placeholder="Select…"
          options={types.map((x) => ({ value: x.id, label: `${x.name} (${x.code})${x.paid ? '' : ' — unpaid'}` }))} />
        <div className="grid grid-cols-2 gap-3">
          <label className="text-sm font-medium text-slate-700">From
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="mt-1.5 block w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm" />
          </label>
          <label className="text-sm font-medium text-slate-700">To
            <input type="date" value={half ? from : to} min={from} disabled={half} onChange={(e) => setTo(e.target.value)} className="mt-1.5 block w-full rounded-xl border border-slate-300 px-3 py-2.5 text-sm disabled:bg-slate-50" />
          </label>
        </div>
        {t?.allows_half_day && <Checkbox label="Half day" checked={half} onChange={setHalf} />}
        <Textarea label={t?.document_required ? 'Reason / document reference (required)' : 'Reason'} value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}
