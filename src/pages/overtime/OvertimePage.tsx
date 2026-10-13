import { useState } from 'react'
import { Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { localDateString, minutesToHm, monthBounds, useOvertime, useTimeAction, useTimeConfig } from '@/lib/time'
import { useEmployeeOptions } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Input, Spinner } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Textarea, td, th } from '@/components/kit'
import { MonthPicker } from '../attendance/shared'

const TONE = { pending: 'orange', approved: 'green', rejected: 'red' } as const

export default function OvertimePage() {
  const ctx = useMyContext()
  const canApprove = ctx.permissions.includes('overtime.approve')
  const canAdd = ctx.permissions.includes('attendance.adjust')
  const [month, setMonth] = useState(localDateString().slice(0, 7))
  const [status, setStatus] = useState('')
  const [adding, setAdding] = useState(false)
  const { from, to } = monthBounds(month)
  const list = useOvertime(from, to)
  const config = useTimeConfig()
  const decide = useTimeAction<{ p_record_id: string; p_approve: boolean; p_note: string | null }>('decide_overtime')
  const rows = (list.data ?? []).filter((r) => !status || r.status === status)
  const pol = config.data?.policy
  const totals = rows.reduce(
    (acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + r.minutes }),
    {} as Record<string, number>,
  )

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="Overtime"
        description="Calculated from punches: time after the shift on workdays, all worked time on weekends and holidays. Applies to every grade."
        actions={canAdd && <Button onClick={() => setAdding(true)}><Plus className="size-4" />Add overtime</Button>}
      />
      {pol && (
        <Card className="flex flex-wrap gap-x-6 gap-y-2 p-4 text-sm text-slate-600">
          <span>Weekday ×{pol.weekday_multiplier}</span><span>Weekend ×{pol.weekend_multiplier}</span><span>Holiday ×{pol.holiday_multiplier}</span>
          <span>Minimum {pol.minimum_minutes} min</span><span>Rounded to {pol.rounding_minutes} min</span>
          <span>Daily cap {minutesToHm(pol.daily_cap_minutes)} (workdays)</span>
          {pol.monthly_cap_minutes && <span>Monthly cap {minutesToHm(pol.monthly_cap_minutes)}</span>}
        </Card>
      )}
      <div className="flex flex-wrap items-center gap-3">
        <MonthPicker value={month} onChange={setMonth} />
        <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)} placeholder="All"
          options={[{ value: 'pending', label: 'Pending' }, { value: 'approved', label: 'Approved' }, { value: 'rejected', label: 'Rejected' }]} />
        <span className="text-sm text-slate-500">Approved {minutesToHm(totals.approved)} · Pending {minutesToHm(totals.pending)}</span>
      </div>
      {decide.isError && <Alert>{errorMessage(decide.error)}</Alert>}
      {list.isPending ? <Spinner /> : list.isError ? <Alert>{errorMessage(list.error)}</Alert> : rows.length === 0 ? (
        <EmptyState title="No overtime this month" />
      ) : (
        <Table minWidth={760} head={
          <tr><th className={th}>Employee</th><th className={th}>Date</th><th className={th}>Day</th><th className={th}>Time</th>
            <th className={th}>Rate</th><th className={th}>Source</th><th className={th}>Status</th><th className={th} /></tr>
        }>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className={td}><p className="font-medium text-slate-900">{r.full_name}</p><p className="text-xs text-slate-400">{r.department_name ?? ''}</p></td>
              <td className={td}>{formatDate(r.work_date)}</td>
              <td className={`${td} capitalize`}>{r.day_type}</td>
              <td className={td}>{minutesToHm(r.minutes)}</td>
              <td className={td}>×{r.multiplier}</td>
              <td className={td}>{r.source}{r.reason && <p className="max-w-40 truncate text-xs italic text-slate-400" title={r.reason}>{r.reason}</p>}</td>
              <td className={td}><Badge tone={TONE[r.status]}>{r.status}</Badge>{r.locked && <Badge>Locked</Badge>}</td>
              <td className="px-4 py-3 text-right">
                {canApprove && !r.is_self && r.status === 'pending' && !r.locked && (
                  <div className="flex justify-end gap-2">
                    <Button onClick={() => decide.mutate({ p_record_id: r.id, p_approve: true, p_note: null })}>Approve</Button>
                    <Button variant="secondary" onClick={() => decide.mutate({ p_record_id: r.id, p_approve: false, p_note: null })}>Reject</Button>
                  </div>
                )}
              </td>
            </tr>
          ))}
        </Table>
      )}
      <AddOvertimeDialog open={adding} onClose={() => setAdding(false)} />
    </div>
  )
}

function AddOvertimeDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const people = useEmployeeOptions(open)
  const add = useTimeAction<{ p_employee_id: string; p_date: string; p_minutes: number; p_reason: string }>('add_manual_overtime')
  const [emp, setEmp] = useState('')
  const [date, setDate] = useState(localDateString())
  const [minutes, setMinutes] = useState('60')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const submit = async () => {
    setError(null)
    try {
      await add.mutateAsync({ p_employee_id: emp, p_date: date, p_minutes: Number(minutes), p_reason: reason })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }
  return (
    <Modal open={open} onClose={onClose} size="sm" title="Add overtime" description="For work the punches could not show. It still needs approval."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!emp || !reason.trim()} loading={add.isPending} onClick={submit}>Add</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Employee" value={emp} onChange={(e) => setEmp(e.target.value)} placeholder="Select…"
          options={(people.data ?? []).map((p) => ({ value: p.id, label: `${p.full_name} (${p.card_id})` }))} />
        <Input label="Date" type="date" name="ot_date" value={date} onChange={(e) => setDate(e.target.value)} />
        <Input label="Minutes" type="number" name="ot_minutes" min={1} max={1440} value={minutes} onChange={(e) => setMinutes(e.target.value)} />
        <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}
