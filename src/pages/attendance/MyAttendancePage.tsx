import { useState } from 'react'
import { Coffee, LogIn, LogOut, MapPin, Repeat } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import {
  getBrowserLocation, hhmm, localDateString, minutesToHm, monthBounds, timeOf, useAttendanceRange, useMyToday,
  useColleagues, useSummary, useSwaps, useTimeAction,
} from '@/lib/time'
import { Alert, Badge, Button, Card, PageLoader } from '@/components/ui'
import { Modal, PageHeader, Select, Textarea } from '@/components/kit'
import { AttendanceBadge, MonthCalendar, MonthPicker, SourceIcon } from './shared'

export default function MyAttendancePage() {
  const today = useMyToday()
  const [month, setMonth] = useState(localDateString().slice(0, 7))
  const { from, to } = monthBounds(month)
  const history = useAttendanceRange(from, to)
  const summary = useSummary(`${month}-01`)
  const punch = useTimeAction<{ p_source: string; p_lat: number | null; p_lng: number | null; p_accuracy: number | null }, {
    outside_geofence: boolean; distance_meters: number | null }>('punch')
  const startBreak = useTimeAction<{ p_type: string }>('start_break')
  const endBreak = useTimeAction<Record<string, never>>('end_break')
  const [message, setMessage] = useState<{ tone: 'success' | 'error' | 'info'; text: string } | null>(null)
  const [locating, setLocating] = useState(false)
  const [swapOpen, setSwapOpen] = useState(false)

  if (today.isPending) return <PageLoader />
  if (today.isError) return <Alert>{errorMessage(today.error)}</Alert>
  const t = today.data
  if (!t) return <Alert tone="info">Your login is not linked to an employee record.</Alert>

  const rec = t.record
  const checkedIn = !!rec?.check_in_at && !rec?.check_out_at
  const mine = history.data?.filter((r) => r.is_self) ?? []
  const me = summary.data?.rows.find((r) => r.employee_id === t.employee_id)

  const doPunch = async () => {
    setMessage(null)
    setLocating(true)
    const loc = await getBrowserLocation()
    setLocating(false)
    try {
      const res = await punch.mutateAsync({
        p_source: loc ? 'gps' : 'web', p_lat: loc?.lat ?? null, p_lng: loc?.lng ?? null, p_accuracy: loc?.accuracy ?? null,
      })
      setMessage(
        res.outside_geofence
          ? { tone: 'info', text: `Punch saved, but you are outside the office area${res.distance_meters ? ` (${res.distance_meters} m away)` : ''}. HR will review it.` }
          : { tone: 'success', text: `Punch saved at ${new Date().toLocaleTimeString()}.` },
      )
    } catch (e) {
      setMessage({ tone: 'error', text: errorMessage(e) })
    }
  }

  const run = async (fn: () => Promise<unknown>, ok: string) => {
    setMessage(null)
    try {
      await fn()
      setMessage({ tone: 'success', text: ok })
    } catch (e) {
      setMessage({ tone: 'error', text: errorMessage(e) })
    }
  }

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader
        title="My attendance"
        description="Check in and out from here. Your location is used only to confirm you are at the office."
        actions={<Button variant="secondary" onClick={() => setSwapOpen(true)}><Repeat className="size-4" />Shift swap</Button>}
      />

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-sm text-slate-500">{formatDate(t.date)} · {t.day_type === 'workday' ? 'Working day' : t.day_type === 'weekend' ? 'Weekly off' : 'Holiday'}</p>
              <p className="mt-1 text-lg font-semibold text-slate-900">
                {t.shift ? `${t.shift.name} shift · ${hhmm(t.shift.start_time)}–${hhmm(t.shift.end_time)}` : 'No shift assigned'}
              </p>
              {t.shift && <p className="text-xs text-slate-500">Late after {t.shift.late_grace_minutes} min grace{t.shift.crosses_midnight ? ' · night shift' : ''}</p>}
            </div>
            {rec && <AttendanceBadge status={rec.status} />}
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-3">
            <div className="rounded-xl bg-slate-50 p-3">
              <p className="text-xs text-slate-500">Check-in</p>
              <p className="mt-1 flex items-center gap-1.5 text-lg font-semibold">{timeOf(rec?.check_in_at)} <SourceIcon source={rec?.source_in ?? null} /></p>
            </div>
            <div className="rounded-xl bg-slate-50 p-3">
              <p className="text-xs text-slate-500">Check-out</p>
              <p className="mt-1 flex items-center gap-1.5 text-lg font-semibold">{timeOf(rec?.check_out_at)} <SourceIcon source={rec?.source_out ?? null} /></p>
            </div>
            <div className="rounded-xl bg-slate-50 p-3">
              <p className="text-xs text-slate-500">Worked</p>
              <p className="mt-1 text-lg font-semibold">{minutesToHm(rec?.worked_minutes)}</p>
            </div>
          </div>

          {message && <div className="mt-4"><Alert tone={message.tone}>{message.text}</Alert></div>}

          <div className="mt-5 flex flex-wrap gap-3">
            <Button className="min-w-40 flex-1 py-3 text-base sm:flex-none" loading={locating || punch.isPending} onClick={doPunch}>
              {checkedIn ? <LogOut className="size-5" /> : <LogIn className="size-5" />}
              {locating ? 'Getting location…' : checkedIn ? 'Check out' : 'Check in'}
            </Button>
            {checkedIn && (
              t.open_break ? (
                <Button variant="secondary" loading={endBreak.isPending} onClick={() => run(() => endBreak.mutateAsync({}), 'Break ended.')}>
                  <Coffee className="size-4" />End break (since {timeOf(t.open_break.break_start)})
                </Button>
              ) : (
                <Button variant="secondary" loading={startBreak.isPending} onClick={() => run(() => startBreak.mutateAsync({ p_type: 'break' }), 'Break started.')}>
                  <Coffee className="size-4" />Start break
                </Button>
              )
            )}
          </div>
          {t.has_geofences && (
            <p className="mt-3 flex items-center gap-1.5 text-xs text-slate-500">
              <MapPin className="size-3.5" /> Allow location access when asked. Punches outside the office area are saved and flagged for review.
            </p>
          )}
          {t.punches.length > 0 && (
            <p className="mt-3 text-xs text-slate-500">
              Today's punches: {t.punches.map((p) => timeOf(p.punched_at) + (p.outside_geofence ? ' (outside)' : '')).join(', ')}
            </p>
          )}
        </Card>

        <Card>
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-slate-900">This month</h3>
            <Badge>{summary.data?.month_days ?? 30}-day month</Badge>
          </div>
          {me ? (
            <dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div><dt className="text-slate-500">Present</dt><dd className="text-xl font-semibold">{me.present_days}</dd></div>
              <div><dt className="text-slate-500">Late</dt><dd className="text-xl font-semibold text-amber-700">{me.late_count}</dd></div>
              <div><dt className="text-slate-500">Absent</dt><dd className="text-xl font-semibold text-red-700">{me.absent_days}</dd></div>
              <div><dt className="text-slate-500">Leave</dt><dd className="text-xl font-semibold">{me.leave_days}</dd></div>
              <div><dt className="text-slate-500">Worked</dt><dd className="font-semibold">{minutesToHm(me.worked_minutes)}</dd></div>
              <div><dt className="text-slate-500">Overtime (approved)</dt><dd className="font-semibold">{minutesToHm(me.approved_overtime_minutes)}</dd></div>
              <div className="col-span-2 rounded-xl bg-amber-50 p-3 text-amber-900">
                <dt className="text-xs">Late deduction</dt>
                <dd className="font-semibold">
                  {summary.data?.policy.mode === 'amount_per_late'
                    ? `৳ ${me.late_deduction_amount}`
                    : summary.data?.policy.mode === 'days_per_lates'
                      ? `${me.late_deduction_days} day(s)`
                      : 'No deduction policy'}
                </dd>
              </div>
            </dl>
          ) : (
            <p className="mt-3 text-sm text-slate-500">No records yet.</p>
          )}
        </Card>
      </div>

      <Card>
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <h3 className="font-semibold text-slate-900">History</h3>
          <MonthPicker value={month} onChange={setMonth} />
        </div>
        <div className="grid gap-6 lg:grid-cols-[minmax(0,320px)_1fr]">
          <MonthCalendar month={month} rows={mine} />
          <div className="overflow-x-auto">
            <table className="w-full min-w-[520px] text-sm">
              <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
                <tr><th className="py-2">Date</th><th>Status</th><th>In</th><th>Out</th><th>Worked</th><th>OT</th></tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {mine.length === 0 && <tr><td colSpan={6} className="py-6 text-center text-slate-400">No records this month</td></tr>}
                {[...mine].reverse().map((r) => (
                  <tr key={r.id}>
                    <td className="py-2">{formatDate(r.work_date)}</td>
                    <td><AttendanceBadge status={r.status} /> {r.is_late && <span className="text-xs text-amber-700">+{r.late_minutes}m</span>}</td>
                    <td>{timeOf(r.check_in_at)}</td>
                    <td>{timeOf(r.check_out_at)}</td>
                    <td>{minutesToHm(r.worked_minutes)}</td>
                    <td>{r.overtime_minutes ? minutesToHm(r.overtime_minutes) : '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </Card>

      <MySwaps />
      <SwapRequestDialog open={swapOpen} onClose={() => setSwapOpen(false)} />
    </div>
  )
}

function MySwaps() {
  const swaps = useSwaps()
  const respond = useTimeAction<{ p_swap_id: string; p_accept: boolean }>('respond_shift_swap')
  const cancel = useTimeAction<{ p_swap_id: string }>('cancel_shift_swap')
  const mine = (swaps.data ?? []).filter((s) => s.is_requester || s.is_target)
  if (!mine.length) return null
  return (
    <Card>
      <h3 className="mb-3 font-semibold text-slate-900">My shift swaps</h3>
      {(respond.isError || cancel.isError) && <Alert>{errorMessage(respond.error ?? cancel.error)}</Alert>}
      <ul className="divide-y divide-slate-100 text-sm">
        {mine.map((s) => (
          <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5">
            <span>
              {formatDate(s.work_date)} · <strong>{s.requester_name}</strong> ({s.requester_shift_name}) ⇄ <strong>{s.target_name}</strong> ({s.target_shift_name})
            </span>
            <span className="flex items-center gap-2">
              <Badge tone={s.status === 'approved' ? 'green' : s.status === 'rejected' || s.status === 'cancelled' ? 'red' : 'orange'}>
                {s.status.replace('_', ' ')}
              </Badge>
              {s.is_target && s.status === 'pending' && (
                <>
                  <Button variant="secondary" onClick={() => respond.mutate({ p_swap_id: s.id, p_accept: true })}>Accept</Button>
                  <Button variant="ghost" onClick={() => respond.mutate({ p_swap_id: s.id, p_accept: false })}>Decline</Button>
                </>
              )}
              {s.is_requester && (s.status === 'pending' || s.status === 'peer_accepted') && (
                <Button variant="ghost" onClick={() => cancel.mutate({ p_swap_id: s.id })}>Cancel</Button>
              )}
            </span>
          </li>
        ))}
      </ul>
    </Card>
  )
}

function SwapRequestDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const people = useColleagues(open)
  const request = useTimeAction<{ p_target_employee_id: string; p_date: string; p_reason: string }>('request_shift_swap')
  const [target, setTarget] = useState('')
  const [date, setDate] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const submit = async () => {
    setError(null)
    try {
      await request.mutateAsync({ p_target_employee_id: target, p_date: date, p_reason: reason })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }
  return (
    <Modal open={open} onClose={onClose} size="sm" title="Request a shift swap"
      description="Your colleague accepts first, then your manager approves."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button disabled={!target || !date} loading={request.isPending} onClick={submit}>Send request</Button></>}
    >
      <div className="space-y-4">
        {error && <Alert>{error}</Alert>}
        <Select label="Colleague" value={target} onChange={(e) => setTarget(e.target.value)}
          options={(people.data ?? []).map((p) => ({ value: p.id, label: `${p.full_name} (${p.card_id})${p.department_name ? ` · ${p.department_name}` : ''}` }))} placeholder="Select…" />
        <label className="block text-sm font-medium text-slate-700">
          Date
          <input type="date" value={date} min={localDateString()} onChange={(e) => setDate(e.target.value)}
            className="mt-1.5 block w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm" />
        </label>
        <Textarea label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} />
      </div>
    </Modal>
  )
}
