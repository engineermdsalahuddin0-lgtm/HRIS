import { useMemo, useState } from 'react'
import { AlertTriangle, CalendarCheck, Clock, PenLine, RefreshCw, UserCheck, UserX, Plane } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { AttendanceRow } from '@/lib/time'
import {
  localDateString, minutesToHm, monthBounds, timeOf, useAttendanceDay, useAttendanceRange, useReconciliation, useSummary,
  useSwaps, useTimeAction,
} from '@/lib/time'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Input, Spinner } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'
import { AttendanceBadge, DateInput, MonthCalendar, MonthPicker, SourceIcon } from './shared'

type Tab = 'daily' | 'monthly' | 'calendar' | 'reconcile' | 'swaps'

function Kpi({ label, value, icon: Icon, tone }: { label: string; value: number; icon: LucideIcon; tone: string }) {
  return (
    <Card className="flex items-center gap-3 p-4">
      <div className={`flex size-10 items-center justify-center rounded-xl ${tone}`}><Icon className="size-5" aria-hidden /></div>
      <div>
        <p className="text-xs text-slate-500">{label}</p>
        <p className="text-xl font-semibold tabular-nums text-slate-900">{value}</p>
      </div>
    </Card>
  )
}

export default function AttendancePage() {
  const ctx = useMyContext()
  const can = (p: string) => ctx.permissions.includes(p)
  const canAdjust = can('attendance.adjust')
  const tabs: { key: Tab; label: string }[] = [
    { key: 'daily', label: 'Daily' },
    { key: 'monthly', label: 'Monthly summary' },
    { key: 'calendar', label: 'Calendar' },
    ...(canAdjust ? [{ key: 'reconcile' as Tab, label: 'Reconciliation' }] : []),
    ...(can('swaps.approve') ? [{ key: 'swaps' as Tab, label: 'Shift swaps' }] : []),
  ]
  const [tab, setTab] = useState<Tab>('daily')

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader
        title="Attendance"
        description={can('attendance.view_all') ? 'Everyone in the organization.' : 'Your reporting team.'}
      />
      <Tabs tabs={tabs} value={tab} onChange={setTab} />
      {tab === 'daily' && <DailyTab canAdjust={canAdjust} />}
      {tab === 'monthly' && <MonthlyTab />}
      {tab === 'calendar' && <CalendarTab />}
      {tab === 'reconcile' && <ReconcileTab />}
      {tab === 'swaps' && <SwapsTab />}
    </div>
  )
}

function DailyTab({ canAdjust }: { canAdjust: boolean }) {
  const [date, setDate] = useState(localDateString())
  const [status, setStatus] = useState('')
  const [fix, setFix] = useState<AttendanceRow | null>(null)
  const day = useAttendanceDay(date)
  const close = useTimeAction<{ p_date: string }, number>('run_daily_close')
  const all = day.data ?? []
  const rows = status ? all.filter((r) => r.status === status) : all
  const count = (s: string[]) => all.filter((r) => s.includes(r.status)).length

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <DateInput label="Date" value={date} onChange={setDate} />
        <Select aria-label="Status" value={status} onChange={(e) => setStatus(e.target.value)} placeholder="All statuses"
          options={['present', 'late', 'absent', 'half_day', 'early_out', 'on_leave', 'weekend', 'holiday'].map((s) => ({ value: s, label: s.replace('_', ' ') }))} />
        {canAdjust && (
          <Button variant="secondary" className="ml-auto" loading={close.isPending} onClick={() => close.mutate({ p_date: date })}
            title="Creates absent rows and applies auto check-out for this date. Safe to run again.">
            <RefreshCw className="size-4" /> Close / rebuild day
          </Button>
        )}
      </div>
      {close.isError && <Alert>{errorMessage(close.error)}</Alert>}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi label="Present" value={count(['present', 'early_out', 'half_day'])} icon={UserCheck} tone="bg-green-50 text-green-700" />
        <Kpi label="Late" value={count(['late'])} icon={Clock} tone="bg-amber-50 text-amber-700" />
        <Kpi label="Absent" value={count(['absent'])} icon={UserX} tone="bg-red-50 text-red-700" />
        <Kpi label="On leave" value={count(['on_leave'])} icon={Plane} tone="bg-blue-50 text-blue-700" />
      </div>

      {day.isPending ? (
        <div className="flex justify-center py-12 text-primary-600"><Spinner /></div>
      ) : day.isError ? (
        <Alert>{errorMessage(day.error)}</Alert>
      ) : rows.length === 0 ? (
        <EmptyState title="No attendance for this date">Absent rows appear after the check-in cut-off or the daily close.</EmptyState>
      ) : (
        <Table minWidth={860} head={
          <tr>
            <th className={th}>Employee</th><th className={th}>Department</th><th className={th}>Shift</th>
            <th className={th}>In</th><th className={th}>Out</th><th className={th}>Worked</th><th className={th}>Status</th><th className={th} />
          </tr>
        }>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className={td}><p className="font-medium text-slate-900">{r.full_name}</p><p className="font-mono text-xs text-slate-400">{r.card_id}</p></td>
              <td className={td}>{r.department_name ?? '—'}</td>
              <td className={td}>{r.shift_code ?? '—'}</td>
              <td className={td}><span className="inline-flex items-center gap-1">{timeOf(r.check_in_at)} <SourceIcon source={r.source_in} /></span></td>
              <td className={td}><span className="inline-flex items-center gap-1">{timeOf(r.check_out_at)} <SourceIcon source={r.source_out} /></span></td>
              <td className={td}>{minutesToHm(r.worked_minutes)}{r.overtime_minutes > 0 && <span className="ml-1 text-xs text-primary-700">+{minutesToHm(r.overtime_minutes)} OT</span>}</td>
              <td className={td}>
                <div className="flex flex-wrap items-center gap-1">
                  <AttendanceBadge status={r.status} />
                  {r.is_late && <span className="text-xs text-amber-700">+{r.late_minutes}m</span>}
                  {r.outside_geofence && <span title="Outside geofence"><AlertTriangle className="size-4 text-red-500" /></span>}
                  {r.note && <span title={r.note}><PenLine className="size-3.5 text-slate-400" /></span>}
                </div>
              </td>
              <td className="px-4 py-3 text-right">
                {canAdjust && !r.is_self && !r.locked && <Button variant="ghost" onClick={() => setFix(r)}>Fix</Button>}
                {r.locked && <Badge>Locked</Badge>}
              </td>
            </tr>
          ))}
        </Table>
      )}
      <FixDialog row={fix} onClose={() => setFix(null)} />
    </div>
  )
}

function toLocalInput(iso: string | null) {
  if (!iso) return ''
  const d = new Date(iso)
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)
}

export function FixDialog({ row, onClose }: { row: AttendanceRow | null; onClose: () => void }) {
  const adjust = useTimeAction<{ p_employee_id: string; p_date: string; p_check_in: string | null; p_check_out: string | null; p_reason: string }>('adjust_attendance')
  const [inAt, setIn] = useState('')
  const [outAt, setOut] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [loadedFor, setLoadedFor] = useState<string | null>(null)
  if (row && loadedFor !== row.id) {
    setLoadedFor(row.id)
    setIn(toLocalInput(row.check_in_at) || `${row.work_date}T09:00`)
    setOut(toLocalInput(row.check_out_at))
    setReason('')
    setError(null)
  }
  const submit = async () => {
    if (!row) return
    setError(null)
    try {
      await adjust.mutateAsync({
        p_employee_id: row.employee_id, p_date: row.work_date,
        p_check_in: inAt ? new Date(inAt).toISOString() : null,
        p_check_out: outAt ? new Date(outAt).toISOString() : null,
        p_reason: reason,
      })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }
  return (
    <Modal open={!!row} onClose={onClose} size="sm" title="Fix attendance"
      description={row ? `${row.full_name} · ${formatDate(row.work_date)}` : undefined}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={adjust.isPending} disabled={!reason.trim()} onClick={submit}>Save fix</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Alert tone="info">The original punches stay as evidence. The fix is recorded as a manual entry with your reason in the audit log.</Alert>
        <Input label="Check-in" type="datetime-local" name="fix_in" value={inAt} onChange={(e) => setIn(e.target.value)} />
        <Input label="Check-out" type="datetime-local" name="fix_out" value={outAt} onChange={(e) => setOut(e.target.value)} />
        <Textarea label="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}

function MonthlyTab() {
  const [month, setMonth] = useState(localDateString().slice(0, 7))
  const summary = useSummary(`${month}-01`)
  const d = summary.data
  const policyText = !d ? '' : d.policy.mode === 'days_per_lates'
    ? `Every ${d.policy.lates_per_deduction} lates = ${d.policy.deduction_days} day's pay deducted`
    : d.policy.mode === 'amount_per_late' ? `৳ ${d.policy.amount_per_late} per late` : 'No late deduction'
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <MonthPicker value={month} onChange={setMonth} />
        {d && <Badge>{d.month_days}-day month</Badge>}
        {d && <Badge tone="orange">{policyText}</Badge>}
      </div>
      {summary.isPending ? <div className="flex justify-center py-12 text-primary-600"><Spinner /></div>
        : summary.isError ? <Alert>{errorMessage(summary.error)}</Alert>
        : !d?.rows.length ? <EmptyState title="Nobody to show for this month" />
        : (
          <Table minWidth={980} head={
            <tr>
              <th className={th}>Employee</th><th className={th}>Present</th><th className={th}>Late</th><th className={th}>Absent</th>
              <th className={th}>Half</th><th className={th}>Early</th><th className={th}>Leave</th><th className={th}>Off</th>
              <th className={th}>Worked</th><th className={th}>OT (approved)</th><th className={th}>Late deduction</th>
            </tr>
          }>
            {d.rows.map((r) => (
              <tr key={r.employee_id}>
                <td className={td}><p className="font-medium text-slate-900">{r.full_name}</p><p className="font-mono text-xs text-slate-400">{r.card_id}</p></td>
                <td className={td}>{r.present_days}</td>
                <td className={`${td} text-amber-700`}>{r.late_count}</td>
                <td className={`${td} text-red-700`}>{r.absent_days}</td>
                <td className={td}>{r.half_days}</td>
                <td className={td}>{r.early_out_days}</td>
                <td className={td}>{r.leave_days}</td>
                <td className={td}>{r.off_days}</td>
                <td className={td}>{minutesToHm(r.worked_minutes)}</td>
                <td className={td}>{minutesToHm(r.approved_overtime_minutes)}</td>
                <td className={td}>
                  {d.policy.mode === 'amount_per_late' ? `৳ ${r.late_deduction_amount}` : d.policy.mode === 'days_per_lates' ? `${r.late_deduction_days} day(s)` : '—'}
                </td>
              </tr>
            ))}
          </Table>
        )}
    </div>
  )
}

function CalendarTab() {
  const [month, setMonth] = useState(localDateString().slice(0, 7))
  const { from, to } = monthBounds(month)
  const range = useAttendanceRange(from, to)
  const people = useMemo(() => {
    const m = new Map<string, string>()
    for (const r of range.data ?? []) m.set(r.employee_id, r.full_name)
    return [...m.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [range.data])
  const [who, setWho] = useState('')
  const selected = who || people[0]?.[0] || ''
  return (
    <Card>
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <MonthPicker value={month} onChange={setMonth} />
        <Select aria-label="Employee" value={selected} onChange={(e) => setWho(e.target.value)} options={people.map(([id, n]) => ({ value: id, label: n }))} />
      </div>
      {range.isPending ? <Spinner /> : !selected ? <EmptyState title="No records this month" /> : (
        <div className="max-w-md"><MonthCalendar month={month} rows={(range.data ?? []).filter((r) => r.employee_id === selected)} /></div>
      )}
    </Card>
  )
}

function ReconcileTab() {
  const today = localDateString()
  const [from, setFrom] = useState(`${today.slice(0, 7)}-01`)
  const [to, setTo] = useState(today)
  const items = useReconciliation(from, to, true)
  const range = useAttendanceRange(from, to)
  const [fix, setFix] = useState<AttendanceRow | null>(null)
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2 text-sm text-slate-600">
        <DateInput label="From" value={from} onChange={setFrom} /> to <DateInput label="To" value={to} onChange={setTo} />
      </div>
      {items.isPending ? <Spinner /> : items.isError ? <Alert>{errorMessage(items.error)}</Alert>
        : !items.data.length ? <EmptyState title="Nothing needs attention"><CalendarCheck className="mx-auto mt-2 size-6 text-green-600" /></EmptyState>
        : (
          <Table head={<tr><th className={th}>Date</th><th className={th}>Employee</th><th className={th}>Issue</th><th className={th}>In</th><th className={th}>Out</th><th className={th} /></tr>}>
            {items.data.map((x) => (
              <tr key={x.record_id}>
                <td className={td}>{formatDate(x.work_date)}</td>
                <td className={td}>{x.full_name} <span className="font-mono text-xs text-slate-400">{x.card_id}</span></td>
                <td className={td}><Badge tone="red">{x.issue === 'missing_checkout' ? 'Missing check-out' : 'Outside geofence'}</Badge></td>
                <td className={td}>{timeOf(x.check_in_at)}</td>
                <td className={td}>{timeOf(x.check_out_at)}</td>
                <td className="px-4 py-3 text-right">
                  {!x.locked && <Button variant="ghost" onClick={() => setFix(range.data?.find((r) => r.id === x.record_id) ?? null)}>Fix</Button>}
                </td>
              </tr>
            ))}
          </Table>
        )}
      <FixDialog row={fix} onClose={() => setFix(null)} />
    </div>
  )
}

function SwapsTab() {
  const swaps = useSwaps()
  const decide = useTimeAction<{ p_swap_id: string; p_approve: boolean; p_note: string | null }>('decide_shift_swap')
  const list = (swaps.data ?? []).filter((s) => !s.is_requester && !s.is_target)
  return (
    <div className="space-y-3">
      {decide.isError && <Alert>{errorMessage(decide.error)}</Alert>}
      {!list.length ? <EmptyState title="No swap requests" /> : (
        <Table head={<tr><th className={th}>Date</th><th className={th}>Swap</th><th className={th}>Status</th><th className={th} /></tr>}>
          {list.map((s) => (
            <tr key={s.id}>
              <td className={td}>{formatDate(s.work_date)}</td>
              <td className={td}>{s.requester_name} ({s.requester_shift_name}) ⇄ {s.target_name} ({s.target_shift_name}){s.reason && <p className="text-xs italic text-slate-400">{s.reason}</p>}</td>
              <td className={td}><Badge tone={s.status === 'approved' ? 'green' : s.status === 'peer_accepted' ? 'orange' : 'slate'}>{s.status.replace('_', ' ')}</Badge></td>
              <td className="px-4 py-3 text-right">
                {s.status === 'peer_accepted' && (
                  <div className="flex justify-end gap-2">
                    <Button onClick={() => decide.mutate({ p_swap_id: s.id, p_approve: true, p_note: null })}>Approve</Button>
                    <Button variant="secondary" onClick={() => decide.mutate({ p_swap_id: s.id, p_approve: false, p_note: null })}>Reject</Button>
                  </div>
                )}
              </td>
            </tr>
          ))}
        </Table>
      )}
    </div>
  )
}
