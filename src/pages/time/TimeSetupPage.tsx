import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Crosshair, Lock, QrCode, Unlock } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, today as todayIso } from '@/lib/options'
import type { Geofence, Holiday, LeaveType, Shift } from '@/lib/time'
import {
  WEEKDAYS, getBrowserLocation, hhmm, useRosters, useSaveRow, useTimeAction, useTimeConfig,
} from '@/lib/time'
import { useEmployeeOptions, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, Spinner } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'
import { StructureTab } from '../organization/StructureTab'

type Tab = 'shifts' | 'roster' | 'holidays' | 'leave' | 'overtime' | 'rules' | 'geo'

export default function TimeSetupPage() {
  const ctx = useMyContext()
  const can = (p: string) => ctx.permissions.includes(p)
  const config = useTimeConfig()
  const tabs = ([
    { key: 'shifts', label: 'Shifts', show: true },
    { key: 'roster', label: 'Roster', show: can('roster.manage') },
    { key: 'holidays', label: 'Holidays', show: true },
    { key: 'leave', label: 'Leave types', show: true },
    { key: 'overtime', label: 'Overtime policy', show: true },
    { key: 'rules', label: 'Work rules', show: can('attendance.settings') || can('attendance.lock_period') },
    { key: 'geo', label: 'Geofences & QR', show: can('geofences.manage') || can('attendance.qr_display') },
  ] as { key: Tab; label: string; show: boolean }[]).filter((t) => t.show)
  const [tab, setTab] = useState<Tab>('shifts')

  if (config.isPending) return <PageLoader />
  if (config.isError) return <Alert>{errorMessage(config.error)}</Alert>
  const c = config.data

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Time setup" description="Shifts, rosters, holidays, leave, overtime and attendance rules for your organization." />
      <Tabs tabs={tabs} value={tab} onChange={setTab} />

      {tab === 'shifts' && (
        <StructureTab<Shift>
          table="shifts" noun="Shift" rows={c.shifts} canManage={can('shifts.manage')} searchText={(r) => `${r.name} ${r.code}`}
          columns={[
            { header: 'Shift', cell: (r) => <><span className="font-medium text-slate-900">{r.name}</span> <span className="font-mono text-xs text-slate-400">{r.code}</span></> },
            { header: 'Time', cell: (r) => <>{hhmm(r.start_time)}–{hhmm(r.end_time)} {r.crosses_midnight && <Badge tone="orange">Night</Badge>}</> },
            { header: 'Late after', cell: (r) => `${r.late_grace_minutes} min` },
            { header: 'Absent after', cell: (r) => `${r.checkin_latest_minutes} min` },
            { header: 'Break', cell: (r) => `${r.break_minutes} min` },
            { header: 'Half day <', cell: (r) => `${r.half_day_threshold_minutes} min` },
            { header: 'Default', cell: (r) => (c.settings?.default_shift_id === r.id ? <Badge tone="green">Default</Badge> : '') },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            { name: 'code', label: 'Code', required: true, createOnly: true, placeholder: 'e.g. GEN, NIGHT' },
            { name: 'start_time', label: 'Start', type: 'time', required: true },
            { name: 'end_time', label: 'End', type: 'time', required: true, hint: 'Earlier than start = night shift (ends next day)' },
            { name: 'break_minutes', label: 'Break (minutes)', type: 'number', required: true },
            { name: 'late_grace_minutes', label: 'Late grace (minutes)', type: 'number', required: true },
            { name: 'checkin_earliest_minutes', label: 'Check-in opens (minutes before start)', type: 'number', required: true },
            { name: 'checkin_latest_minutes', label: 'Absent cut-off (minutes after start)', type: 'number', required: true },
            { name: 'early_out_grace_minutes', label: 'Early-out grace (minutes)', type: 'number', required: true },
            { name: 'checkout_latest_minutes', label: 'Check-out window (minutes after end)', type: 'number', required: true },
            { name: 'half_day_threshold_minutes', label: 'Half day below (worked minutes)', type: 'number', required: true },
            { name: 'auto_checkout', label: 'Auto check-out at shift end', type: 'checkbox' },
          ]}
        />
      )}

      {tab === 'roster' && <RosterTab />}

      {tab === 'holidays' && (
        <StructureTab<Holiday>
          table="holidays" noun="Holiday" rows={c.holidays} canManage={can('holidays.manage')} searchText={(r) => `${r.name} ${r.date}`}
          columns={[
            { header: 'Date', cell: (r) => <span className="whitespace-nowrap">{formatDate(r.date)} <span className="text-xs text-slate-400">{WEEKDAYS[new Date(`${r.date}T00:00:00`).getDay()]}</span></span> },
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Type', cell: (r) => <span className="capitalize">{r.type}</span> },
            { header: 'Branches', cell: (r) => (r.branch_ids.length ? `${r.branch_ids.length} branch(es)` : 'All') },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true, placeholder: 'e.g. Eid-ul-Fitr' },
            { name: 'date', label: 'Date', type: 'date', required: true },
            { name: 'type', label: 'Type', type: 'select', required: true, options: [
              { value: 'public', label: 'Public' }, { value: 'company', label: 'Company' }, { value: 'optional', label: 'Optional' }] },
          ]}
          toolbar={<span className="hidden self-center text-xs text-slate-500 md:inline">Fixed-date public holidays are seeded; add Eid, Puja and other lunar dates each year.</span>}
        />
      )}

      {tab === 'leave' && (
        <StructureTab<LeaveType>
          table="leave_types" noun="Leave type" rows={c.leaveTypes} canManage={can('leave.manage_types')} searchText={(r) => `${r.name} ${r.code}`}
          columns={[
            { header: 'Type', cell: (r) => <><span className="font-medium text-slate-900">{r.name}</span> <span className="font-mono text-xs text-slate-400">{r.code}</span></> },
            { header: 'Days / year', cell: (r) => r.days_per_year ?? 'No limit' },
            { header: 'Paid', cell: (r) => (r.paid ? 'Yes' : 'No') },
            { header: 'Carry forward', cell: (r) => (r.carry_forward ? `Yes${r.carry_forward_cap ? ` (max ${r.carry_forward_cap})` : ''}` : 'No') },
            { header: 'Accrual', cell: (r) => <span className="capitalize">{r.accrual}</span> },
            { header: 'Rules', cell: (r) => [r.allows_half_day && 'half day', r.document_required && 'document', r.counts_off_days && 'counts off days'].filter(Boolean).join(', ') || '—' },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            { name: 'code', label: 'Code', required: true, createOnly: true, placeholder: 'e.g. CL' },
            { name: 'days_per_year', label: 'Days per year', type: 'number', hint: 'Empty = no limit' },
            { name: 'accrual', label: 'Accrual', type: 'select', required: true, options: [{ value: 'yearly', label: 'Yearly' }, { value: 'monthly', label: 'Monthly' }] },
            { name: 'carry_forward_cap', label: 'Carry-forward cap (days)', type: 'number' },
            { name: 'paid', label: 'Paid', type: 'checkbox' },
            { name: 'carry_forward', label: 'Carry forward unused days', type: 'checkbox' },
            { name: 'allows_half_day', label: 'Half day allowed', type: 'checkbox' },
            { name: 'document_required', label: 'Reason / document required', type: 'checkbox' },
            { name: 'counts_off_days', label: 'Count weekly offs and holidays', type: 'checkbox' },
          ]}
          toolbar={can('leave.manage_types') ? <RolloverButton /> : undefined}
        />
      )}

      {tab === 'overtime' && <OvertimePolicyTab canEdit={can('overtime.manage_policy')} />}
      {tab === 'rules' && <RulesTab />}
      {tab === 'geo' && <GeoTab geofences={c.geofences} canManage={can('geofences.manage')} canQr={can('attendance.qr_display')} />}
    </div>
  )
}

function RolloverButton() {
  const roll = useTimeAction<{ p_from_year: number }, number>('run_leave_rollover')
  const year = new Date().getFullYear() - 1
  return (
    <Button variant="secondary" loading={roll.isPending} title={`Carry unused ${year} days into ${year + 1}`}
      onClick={() => confirm(`Carry unused ${year} leave (up to each cap) into ${year + 1}?`) && roll.mutate({ p_from_year: year })}>
      {roll.isSuccess ? `Rolled over ${roll.data}` : `Year rollover ${year}→${year + 1}`}
    </Button>
  )
}

function RosterTab() {
  const config = useTimeConfig()
  const rosters = useRosters()
  const people = useEmployeeOptions()
  const save = useSaveRow('shift_rosters')
  const [open, setOpen] = useState(false)
  const [v, setV] = useState({ employee_id: '', shift_id: '', date_from: todayIso(), date_to: todayIso(), note: '' })
  const [error, setError] = useState<string | null>(null)
  const shifts = (config.data?.shifts ?? []).filter((s) => s.status === 'active')
  const name = (id: string) => people.data?.find((p) => p.id === id)?.full_name ?? '—'
  const shiftName = (id: string) => config.data?.shifts.find((s) => s.id === id)?.name ?? '—'

  const submit = async () => {
    setError(null)
    try {
      await save.mutateAsync({ values: { ...v, note: v.note || null } })
      setOpen(false)
    } catch (e) {
      setError(errorMessage(e))
    }
  }
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-slate-500">Without a roster, people work the default shift. One shift per person per date; overlaps are refused.</p>
        <Button onClick={() => setOpen(true)}>Assign shift</Button>
      </div>
      {save.isError && !open && <Alert>{errorMessage(save.error)}</Alert>}
      {rosters.isPending ? <Spinner /> : !rosters.data?.length ? <EmptyState title="No rosters yet" /> : (
        <Table head={<tr><th className={th}>Employee</th><th className={th}>Shift</th><th className={th}>From</th><th className={th}>To</th><th className={th}>Note</th><th className={th} /></tr>}>
          {rosters.data.map((r) => (
            <tr key={r.id}>
              <td className={td}>{name(r.employee_id)}</td>
              <td className={td}>{shiftName(r.shift_id)} {r.is_override && <Badge tone="orange">Swap / override</Badge>}</td>
              <td className={td}>{formatDate(r.date_from)}</td>
              <td className={td}>{formatDate(r.date_to)}</td>
              <td className={td}>{r.note ?? '—'}</td>
              <td className="px-4 py-3 text-right">
                {!r.is_override && <Button variant="ghost" onClick={() => confirm('Remove this roster?') && save.mutate({ id: r.id, values: { status: 'inactive' } })}>Remove</Button>}
              </td>
            </tr>
          ))}
        </Table>
      )}
      <Modal open={open} onClose={() => setOpen(false)} size="sm" title="Assign shift"
        footer={<><Button variant="secondary" onClick={() => setOpen(false)}>Cancel</Button><Button loading={save.isPending} disabled={!v.employee_id || !v.shift_id} onClick={submit}>Save</Button></>}>
        <div className="space-y-4">
          {error && <Alert>{error}</Alert>}
          <Select label="Employee" value={v.employee_id} onChange={(e) => setV({ ...v, employee_id: e.target.value })} placeholder="Select…"
            options={(people.data ?? []).map((p) => ({ value: p.id, label: `${p.full_name} (${p.card_id})` }))} />
          <Select label="Shift" value={v.shift_id} onChange={(e) => setV({ ...v, shift_id: e.target.value })} placeholder="Select…"
            options={shifts.map((s) => ({ value: s.id, label: `${s.name} (${hhmm(s.start_time)}–${hhmm(s.end_time)})` }))} />
          <div className="grid grid-cols-2 gap-3">
            <Input label="From" type="date" name="r_from" value={v.date_from} onChange={(e) => setV({ ...v, date_from: e.target.value })} />
            <Input label="To" type="date" name="r_to" value={v.date_to} onChange={(e) => setV({ ...v, date_to: e.target.value })} />
          </div>
          <Textarea label="Note" value={v.note} onChange={(e) => setV({ ...v, note: e.target.value })} />
        </div>
      </Modal>
    </div>
  )
}

function OvertimePolicyTab({ canEdit }: { canEdit: boolean }) {
  const config = useTimeConfig()
  const save = useSaveRow('overtime_policy')
  const pol = config.data?.policy
  const [v, setV] = useState<Record<string, string | boolean>>({})
  useEffect(() => {
    if (pol) setV({ ...Object.fromEntries(Object.entries(pol).map(([k, x]) => [k, typeof x === 'boolean' ? x : x === null ? '' : String(x)])) })
  }, [pol])
  if (!pol) return <EmptyState title="No overtime policy" />
  const num = (k: string, label: string, hint?: string) => (
    <Input key={k} label={label} type="number" step="0.25" name={k} hint={hint} disabled={!canEdit} value={String(v[k] ?? '')}
      onChange={(e) => setV({ ...v, [k]: e.target.value })} />
  )
  return (
    <Card className="space-y-5">
      <Alert tone="info">
        Bangladesh law pays overtime at twice the ordinary rate. Values here are company policy — confirm them with your legal adviser.
        Overtime is counted for everyone, including management and owners.
      </Alert>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {num('weekday_multiplier', 'Weekday rate (×)')}
        {num('weekend_multiplier', 'Weekend rate (×)')}
        {num('holiday_multiplier', 'Holiday rate (×)')}
        {num('minimum_minutes', 'Minimum minutes', 'Less than this is not overtime')}
        {num('rounding_minutes', 'Round down to (minutes)')}
        {num('daily_cap_minutes', 'Daily cap on workdays (minutes)')}
        {num('monthly_cap_minutes', 'Monthly cap (minutes)', 'Empty = no cap')}
      </div>
      <div className="flex flex-wrap gap-6">
        <Checkbox label="Capture overtime automatically from punches" checked={!!v.auto_capture} disabled={!canEdit} onChange={(x) => setV({ ...v, auto_capture: x })} />
        <Checkbox label="Overtime needs approval" checked={!!v.requires_approval} disabled={!canEdit} onChange={(x) => setV({ ...v, requires_approval: x })} />
      </div>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {canEdit && (
        <div className="flex justify-end">
          <Button loading={save.isPending} onClick={() => save.mutate({
            id: pol.org_id, key: 'org_id',
            values: {
              weekday_multiplier: Number(v.weekday_multiplier), weekend_multiplier: Number(v.weekend_multiplier),
              holiday_multiplier: Number(v.holiday_multiplier), minimum_minutes: Number(v.minimum_minutes),
              rounding_minutes: Number(v.rounding_minutes), daily_cap_minutes: Number(v.daily_cap_minutes),
              monthly_cap_minutes: v.monthly_cap_minutes === '' ? null : Number(v.monthly_cap_minutes),
              auto_capture: !!v.auto_capture, requires_approval: !!v.requires_approval,
            },
          })}>Save policy</Button>
        </div>
      )}
    </Card>
  )
}

function RulesTab() {
  const ctx = useMyContext()
  const canEdit = ctx.permissions.includes('attendance.settings')
  const canLock = ctx.permissions.includes('attendance.lock_period')
  const config = useTimeConfig()
  const save = useSaveRow('org_work_settings')
  const regime = useTimeAction<{ p_regime: string }>('apply_labor_regime_defaults')
  const lock = useTimeAction<{ p_start: string; p_end: string; p_locked: boolean; p_note: string | null }>('set_period_lock')
  const ws = config.data?.settings
  const [v, setV] = useState(ws)
  const [lockFrom, setLockFrom] = useState('')
  const [lockTo, setLockTo] = useState('')
  useEffect(() => setV(ws), [ws])
  if (!ws || !v) return <EmptyState title="No work settings" />
  const shifts = (config.data?.shifts ?? []).filter((s) => s.status === 'active')

  return (
    <div className="space-y-6">
      <Card className="space-y-4">
        <h3 className="font-semibold text-slate-900">Labour law</h3>
        <p className="text-sm text-slate-500">
          Enterprises inside an Export Processing Zone follow the <strong>EPZ Labour Act 2019</strong>; everyone else follows the
          <strong> Bangladesh Labour Act 2006</strong>. Applying a law resets leave types and overtime rates to that law's defaults.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          {(['bd_labour_act', 'bd_epz_labour_act'] as const).map((r) => (
            <button key={r} disabled={!canEdit} onClick={() => confirm('Apply this law and reset leave types and overtime rates to its defaults?') && regime.mutate({ p_regime: r })}
              className={`rounded-xl border p-4 text-left transition disabled:cursor-not-allowed ${ws.labor_regime === r ? 'border-primary-500 bg-primary-50 ring-2 ring-primary-100' : 'border-slate-200 hover:bg-slate-50'}`}>
              <p className="font-medium text-slate-900">{r === 'bd_labour_act' ? 'Bangladesh Labour Act 2006' : 'EPZ Labour Act 2019'}</p>
              <p className="text-sm text-slate-500">{r === 'bd_labour_act' ? 'Default for companies outside an EPZ' : 'For enterprises inside an EPZ'}</p>
              {ws.labor_regime === r && <Badge tone="orange">Current</Badge>}
            </button>
          ))}
        </div>
        {regime.isError && <Alert>{errorMessage(regime.error)}</Alert>}
      </Card>

      <Card className="space-y-5">
        <h3 className="font-semibold text-slate-900">Week, shift and late policy</h3>
        <div>
          <p className="mb-2 text-sm font-medium text-slate-700">Weekly off days</p>
          <div className="flex flex-wrap gap-3">
            {WEEKDAYS.map((d, i) => (
              <Checkbox key={d} label={d} disabled={!canEdit} checked={v.weekly_off_days.includes(i)}
                onChange={(x) => setV({ ...v, weekly_off_days: x ? [...v.weekly_off_days, i].sort() : v.weekly_off_days.filter((y) => y !== i) })} />
            ))}
          </div>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <Select label="Default shift" value={v.default_shift_id ?? ''} disabled={!canEdit} onChange={(e) => setV({ ...v, default_shift_id: e.target.value || null })}
            options={shifts.map((s) => ({ value: s.id, label: `${s.name} (${hhmm(s.start_time)}–${hhmm(s.end_time)})` }))} placeholder="None" />
          <Input label="Salary month" name="month_days" value="30 days (fixed)" disabled hint="Daily rate = monthly salary ÷ 30" />
          <Select label="Late deduction" value={v.late_deduction_mode} disabled={!canEdit}
            onChange={(e) => setV({ ...v, late_deduction_mode: e.target.value as typeof v.late_deduction_mode })}
            options={[{ value: 'none', label: 'No deduction' }, { value: 'days_per_lates', label: "N lates = X day's pay" }, { value: 'amount_per_late', label: 'Fixed taka per late' }]} />
          {v.late_deduction_mode === 'days_per_lates' && (
            <>
              <Input label="Number of lates (N)" type="number" name="lates_n" min={1} disabled={!canEdit} value={String(v.lates_per_deduction)}
                onChange={(e) => setV({ ...v, lates_per_deduction: Number(e.target.value) })} />
              <Input label="Days deducted (X)" type="number" step="0.5" name="lates_x" disabled={!canEdit} value={String(v.late_deduction_days)}
                onChange={(e) => setV({ ...v, late_deduction_days: Number(e.target.value) })} />
            </>
          )}
          {v.late_deduction_mode === 'amount_per_late' && (
            <Input label="Taka per late" type="number" name="late_amount" disabled={!canEdit} value={String(v.late_amount_per_late)}
              onChange={(e) => setV({ ...v, late_amount_per_late: Number(e.target.value) })} />
          )}
          <Input label="QR code rotates every (seconds)" type="number" name="qr_secs" disabled={!canEdit} value={String(v.qr_rotation_seconds)}
            onChange={(e) => setV({ ...v, qr_rotation_seconds: Number(e.target.value) })} />
        </div>
        <Checkbox label="Web check-in must send the browser location" disabled={!canEdit} checked={v.require_location}
          onChange={(x) => setV({ ...v, require_location: x })} />
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        {canEdit && (
          <div className="flex justify-end">
            <Button loading={save.isPending} onClick={() => save.mutate({
              id: ws.org_id, key: 'org_id',
              values: {
                weekly_off_days: v.weekly_off_days, default_shift_id: v.default_shift_id, late_deduction_mode: v.late_deduction_mode,
                lates_per_deduction: v.lates_per_deduction, late_deduction_days: v.late_deduction_days,
                late_amount_per_late: v.late_amount_per_late, qr_rotation_seconds: v.qr_rotation_seconds, require_location: v.require_location,
              },
            })}>Save rules</Button>
          </div>
        )}
      </Card>

      {canLock && (
        <Card className="space-y-4">
          <h3 className="flex items-center gap-2 font-semibold text-slate-900"><Lock className="size-4" />Payroll period lock</h3>
          <p className="text-sm text-slate-500">Locked dates are read-only: no punches, fixes, leave or overtime changes.</p>
          <div className="flex flex-wrap items-end gap-3">
            <Input label="From" type="date" name="lock_from" value={lockFrom} onChange={(e) => setLockFrom(e.target.value)} />
            <Input label="To" type="date" name="lock_to" value={lockTo} onChange={(e) => setLockTo(e.target.value)} />
            <Button disabled={!lockFrom || !lockTo} loading={lock.isPending}
              onClick={() => lock.mutate({ p_start: lockFrom, p_end: lockTo, p_locked: true, p_note: null })}>Lock period</Button>
          </div>
          {lock.isError && <Alert>{errorMessage(lock.error)}</Alert>}
          <ul className="divide-y divide-slate-100 text-sm">
            {(config.data?.locks ?? []).filter((l) => l.status === 'locked').map((l) => (
              <li key={l.id} className="flex items-center justify-between py-2">
                <span>{formatDate(l.period_start)} → {formatDate(l.period_end)}</span>
                <Button variant="ghost" onClick={() => confirm('Unlock this period?') && lock.mutate({ p_start: l.period_start, p_end: l.period_end, p_locked: false, p_note: null })}>
                  <Unlock className="size-4" />Unlock
                </Button>
              </li>
            ))}
          </ul>
        </Card>
      )}
    </div>
  )
}

function GeoTab({ geofences, canManage, canQr }: { geofences: Geofence[]; canManage: boolean; canQr: boolean }) {
  const structure = useOrgStructure()
  const save = useSaveRow('geofences')
  const [open, setOpen] = useState(false)
  const [v, setV] = useState({ name: '', office_id: '', latitude: '', longitude: '', radius_meters: '150' })
  const [error, setError] = useState<string | null>(null)
  const [locating, setLocating] = useState(false)
  const offices = (structure.data?.offices ?? []).filter((o) => o.status === 'active')
  const officeName = (id: string | null) => offices.find((o) => o.id === id)?.name ?? '—'

  const useMyLocation = async () => {
    setLocating(true)
    const loc = await getBrowserLocation()
    setLocating(false)
    if (!loc) return setError('Could not read your location. Allow location access in the browser.')
    setV({ ...v, latitude: loc.lat.toFixed(6), longitude: loc.lng.toFixed(6) })
  }
  const submit = async () => {
    setError(null)
    try {
      await save.mutateAsync({ values: {
        name: v.name, office_id: v.office_id || null, latitude: Number(v.latitude), longitude: Number(v.longitude), radius_meters: Number(v.radius_meters),
      } })
      setOpen(false)
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <div className="space-y-6">
      <Card className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h3 className="font-semibold text-slate-900">Geofences</h3>
            <p className="text-sm text-slate-500">Punches outside every area are saved and flagged for review — never blocked.</p>
          </div>
          {canManage && <Button onClick={() => { setError(null); setOpen(true) }}>Add geofence</Button>}
        </div>
        {!geofences.length ? <EmptyState title="No geofences yet" /> : (
          <Table head={<tr><th className={th}>Name</th><th className={th}>Office</th><th className={th}>Location</th><th className={th}>Radius</th><th className={th}>Status</th><th className={th} /></tr>}>
            {geofences.map((g) => (
              <tr key={g.id}>
                <td className={td}>{g.name}</td>
                <td className={td}>{officeName(g.office_id)}</td>
                <td className={td}>
                  <a className="text-primary-700 hover:underline" target="_blank" rel="noreferrer" href={`https://www.google.com/maps?q=${g.latitude},${g.longitude}`}>
                    {Number(g.latitude).toFixed(5)}, {Number(g.longitude).toFixed(5)}
                  </a>
                </td>
                <td className={td}>{g.radius_meters} m</td>
                <td className={td}><Badge tone={g.status === 'active' ? 'green' : 'slate'}>{g.status}</Badge></td>
                <td className="px-4 py-3 text-right">
                  {canManage && <Button variant="ghost" onClick={() => save.mutate({ id: g.id, values: { status: g.status === 'active' ? 'inactive' : 'active' } })}>
                    {g.status === 'active' ? 'Turn off' : 'Turn on'}
                  </Button>}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      {canQr && (
        <Card className="space-y-3">
          <h3 className="flex items-center gap-2 font-semibold text-slate-900"><QrCode className="size-4" />Office QR check-in</h3>
          <p className="text-sm text-slate-500">Open the QR screen on a tablet or monitor at the office. The code rotates, so a photo of it stops working.</p>
          <div className="flex flex-wrap gap-2">
            {offices.map((o) => (
              <Link key={o.id} to={`/attendance/qr-display/${o.id}`} target="_blank"
                className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-700 hover:border-primary-200 hover:bg-primary-50">
                {o.name}
              </Link>
            ))}
          </div>
        </Card>
      )}

      <Modal open={open} onClose={() => setOpen(false)} size="sm" title="Add geofence"
        footer={<><Button variant="secondary" onClick={() => setOpen(false)}>Cancel</Button><Button loading={save.isPending} disabled={!v.name || !v.latitude || !v.longitude} onClick={submit}>Save</Button></>}>
        <div className="space-y-4">
          {error && <Alert>{error}</Alert>}
          <Input label="Name" name="g_name" value={v.name} onChange={(e) => setV({ ...v, name: e.target.value })} placeholder="e.g. Factory gate" />
          <Select label="Office" value={v.office_id} onChange={(e) => setV({ ...v, office_id: e.target.value })} placeholder="None"
            options={offices.map((o) => ({ value: o.id, label: o.name }))} hint="Punches inside are recorded at this office" />
          <div className="grid grid-cols-2 gap-3">
            <Input label="Latitude" name="g_lat" value={v.latitude} onChange={(e) => setV({ ...v, latitude: e.target.value })} />
            <Input label="Longitude" name="g_lng" value={v.longitude} onChange={(e) => setV({ ...v, longitude: e.target.value })} />
          </div>
          <Button variant="secondary" loading={locating} onClick={useMyLocation}><Crosshair className="size-4" />Use my location</Button>
          <Input label="Radius (metres)" type="number" name="g_radius" min={10} max={5000} value={v.radius_meters} onChange={(e) => setV({ ...v, radius_meters: e.target.value })} />
        </div>
      </Modal>
    </div>
  )
}
