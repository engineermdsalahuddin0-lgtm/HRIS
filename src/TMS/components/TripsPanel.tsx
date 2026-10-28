import { useState } from 'react'
import { MapPin, Play, Plus, Receipt, Square } from 'lucide-react'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, cx } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'
import { EXPENSE_KIND, TRIP_KIND, TRIP_STATUS, formatKm, formatTaka, mapsLink } from '../core/tms'
import type { TmsMe, Trip } from '../core/types'
import { currentPosition, openTmsFile, useAddExpense, useAssignOptions, useTrip, useTripAction, useTrips } from '../data/api'

type Scope = 'mine' | 'approve' | 'all'

/** Trips: everyone requests; managers approve their department; the desk assigns and sees all. */
export function TripsPanel({ me }: { me: TmsMe }) {
  const scopes: [Scope, string][] = [['mine', 'My requests'],
    ...((me.can.approve || me.can.manage) ? [['approve', `To approve${me.to_approve ? ` (${me.to_approve})` : ''}`] as [Scope, string]] : []),
    ...((me.can.manage || me.can.view_costs) ? [['all', `All trips${me.to_assign ? ` · ${me.to_assign} to assign` : ''}`] as [Scope, string]] : [])]
  const [scope, setScope] = useState<Scope>(me.can.manage ? 'all' : 'mine')
  const trips = useTrips(scope)
  const [creating, setCreating] = useState(false)
  const [open, setOpen] = useState<string | null>(null)
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        {scopes.map(([k, label]) => (
          <button key={k} type="button" onClick={() => setScope(k)}
            className={cx('rounded-full px-3 py-1.5 text-sm ring-1', scope === k ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-700 ring-slate-300')}>
            {label}
          </button>
        ))}
        <Button className="ml-auto" onClick={() => setCreating(true)}><Plus className="size-4" />{me.can.manage ? 'New trip' : 'Request a vehicle'}</Button>
      </div>
      {trips.isPending ? <PageLoader /> : trips.isError ? <Alert>{errorMessage(trips.error)}</Alert>
        : trips.data.length === 0 ? <EmptyState title="No trips here" /> : (
          <ul className="space-y-2">{trips.data.map((t) => <TripRow key={t.id} trip={t} onOpen={() => setOpen(t.id)} />)}</ul>
        )}
      {creating && <TripForm desk={me.can.manage} onClose={() => setCreating(false)} />}
      {open && <TripModal id={open} me={me} onClose={() => setOpen(null)} />}
    </div>
  )
}

function TripRow({ trip: t, onOpen }: { trip: Trip; onOpen: () => void }) {
  const s = TRIP_STATUS[t.status]
  return (
    <li>
      <button type="button" onClick={onOpen} className="flex w-full flex-wrap items-center gap-3 rounded-xl bg-white p-3 text-left text-sm shadow-sm ring-1 ring-slate-200 hover:ring-primary-300">
        <div className="min-w-0 flex-1">
          <p className="font-medium text-slate-900">{t.from_place} → {t.to_place} <span className="font-normal text-slate-500">· {t.purpose}</span></p>
          <p className="text-xs text-slate-500">
            {formatDateTime(t.planned_start)} · {TRIP_KIND[t.kind]}{t.department ? ` · ${t.department}` : ''} · by {t.requested_by ?? '—'}
            {t.vehicle ? ` · ${t.vehicle.reg_no}` : ''}{t.driver ? ` · ${t.driver.name}` : ''}{t.distance_km != null ? ` · ${formatKm(t.distance_km)}` : ''}
          </p>
        </div>
        <Badge tone={s.tone}>{s.label}</Badge>
      </button>
    </li>
  )
}

const local = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16)

function TripForm({ desk, onClose }: { desk: boolean; onClose: () => void }) {
  const act = useTripAction()
  const start = new Date(Date.now() + 3600_000)
  const [f, setF] = useState({
    kind: 'staff', purpose: '', from_place: '', to_place: '', stops: '', planned_start: local(start),
    planned_end: local(new Date(start.getTime() + 3 * 3600_000)), passengers: '', cargo: '', customer: '',
  })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} size="lg" title={desk ? 'New trip' : 'Request a vehicle'}
      description={desk ? 'Trips you create are approved at once; assign a vehicle next.' : 'Your department manager approves it, then the transport desk assigns a vehicle and a driver.'}>
      <form className="space-y-3" onSubmit={(e) => {
        e.preventDefault()
        act.mutate({ fn: 'create_tms_trip', args: { p: { ...f, planned_start: new Date(f.planned_start).toISOString(), planned_end: new Date(f.planned_end).toISOString() } } },
          { onSuccess: onClose })
      }}>
        <div className="grid gap-3 sm:grid-cols-2">
          <Select label="Kind" value={f.kind} onChange={set('kind')} options={Object.entries(TRIP_KIND).map(([value, label]) => ({ value, label }))} />
          <Input label="Purpose *" value={f.purpose} onChange={set('purpose')} required placeholder="Client meeting, delivery…" />
          <Input label="From *" value={f.from_place} onChange={set('from_place')} required />
          <Input label="To *" value={f.to_place} onChange={set('to_place')} required />
          <Input label="Start *" type="datetime-local" value={f.planned_start} onChange={set('planned_start')} required />
          <Input label="Back by *" type="datetime-local" value={f.planned_end} onChange={set('planned_end')} required />
          {f.kind === 'delivery' ? (
            <>
              <Input label="Cargo" value={f.cargo} onChange={set('cargo')} placeholder="3 cartons, 500 kg" />
              <Input label="Customer" value={f.customer} onChange={set('customer')} />
            </>
          ) : <Input label="Passengers" type="number" min={1} value={f.passengers} onChange={set('passengers')} />}
        </div>
        <Textarea label="Stops on the way" value={f.stops} onChange={set('stops')} />
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={act.isPending}>{desk ? 'Create trip' : 'Send request'}</Button>
        </div>
      </form>
    </Modal>
  )
}

function TripModal({ id, me, onClose }: { id: string; me: TmsMe; onClose: () => void }) {
  const trip = useTrip(id)
  const act = useTripAction()
  const [assigning, setAssigning] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)
  const t = trip.data
  const run = (fn: string, args: Record<string, unknown>) => act.mutate({ fn, args })
  return (
    <Modal open onClose={onClose} size="lg" title={t ? `${t.from_place} → ${t.to_place}` : 'Trip'} description={t?.purpose}>
      {trip.isPending ? <PageLoader /> : trip.isError ? <Alert>{errorMessage(trip.error)}</Alert> : t && (
        assigning ? <AssignForm tripId={t.id} onDone={() => setAssigning(false)} /> : (
          <div className="space-y-4">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone={TRIP_STATUS[t.status].tone}>{TRIP_STATUS[t.status].label}</Badge>
              <span className="text-sm text-slate-600">{TRIP_KIND[t.kind]} · {formatDateTime(t.planned_start)} – {formatDateTime(t.planned_end)}</span>
            </div>
            <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
              {([
                ['Requested by', `${t.requested_by ?? '—'}${t.department ? ` · ${t.department}` : ''}`],
                ['Decision', t.decided_by ? `${t.decided_by}${t.decision_note ? `: ${t.decision_note}` : ''}` : '—'],
                ['Vehicle', t.vehicle?.reg_no ?? '—'],
                ['Driver', t.driver ? `${t.driver.name}${t.driver.phone ? ` · ${t.driver.phone}` : ''}` : '—'],
                ...(t.passengers ? [['Passengers', String(t.passengers)]] : []),
                ...(t.cargo || t.customer ? [['Cargo / customer', [t.cargo, t.customer].filter(Boolean).join(' · ')]] : []),
                ...(t.stops ? [['Stops', t.stops]] : []),
                ['Odometer', t.start_odometer != null ? `${formatKm(t.start_odometer)} → ${t.end_odometer != null ? formatKm(t.end_odometer) : '…'}` : '—'],
                ['Distance', t.distance_km != null ? formatKm(t.distance_km) : '—'],
                ['Expenses', formatTaka(t.expenses_total)],
              ] as [string, string][]).map(([k, v]) => <div key={k}><dt className="text-xs text-slate-500">{k}</dt><dd className="text-slate-900">{v}</dd></div>)}
            </dl>
            {t.points.length > 0 && (
              <div className="flex flex-wrap gap-2 text-xs">
                {t.points.map((p, i) => (
                  <a key={i} href={mapsLink(p)} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-slate-700 hover:bg-slate-200">
                    <MapPin className="size-3.5" aria-hidden />{p.event.replace('_', ' ')} · {formatDateTime(p.at)}
                  </a>
                ))}
              </div>
            )}
            {t.expenses.length > 0 && (
              <ul className="divide-y divide-slate-100 rounded-xl text-sm ring-1 ring-slate-200">
                {t.expenses.map((x) => (
                  <li key={x.id} className="flex flex-wrap items-center gap-3 px-3 py-2">
                    <span className="font-medium">{EXPENSE_KIND[x.kind as keyof typeof EXPENSE_KIND] ?? x.kind}</span>
                    <span>{formatTaka(x.amount)}</span>
                    <span className="text-xs text-slate-500">{x.note}</span>
                    {x.receipt_path && <button type="button" className="ml-auto text-xs text-primary-700 hover:underline"
                      onClick={() => openTmsFile(x.receipt_path!).catch((e) => setFileError(errorMessage(e)))}>Receipt</button>}
                  </li>
                ))}
              </ul>
            )}
            {(act.error || fileError) && <Alert>{fileError ?? errorMessage(act.error)}</Alert>}
            <div className="flex flex-wrap gap-2">
              {t.can_approve && <>
                <Button loading={act.isPending} onClick={() => run('decide_tms_trip', { p_id: t.id, p_approve: true, p_note: null })}>Approve</Button>
                <Button variant="secondary" onClick={() => { const n = window.prompt('Why is it refused?'); if (n) run('decide_tms_trip', { p_id: t.id, p_approve: false, p_note: n }) }}>Refuse</Button>
              </>}
              {me.can.manage && (t.status === 'approved' || t.status === 'assigned') && (
                <Button variant={t.status === 'approved' ? 'primary' : 'secondary'} onClick={() => setAssigning(true)}>{t.status === 'approved' ? 'Assign vehicle' : 'Change vehicle'}</Button>
              )}
              {(t.requested_by_me || me.can.manage) && ['requested', 'approved', 'assigned'].includes(t.status) && (
                <Button variant="ghost" onClick={() => { const n = window.prompt('Why is the trip cancelled?'); if (n) run('cancel_tms_trip', { p_id: t.id, p_reason: n }) }}>Cancel trip</Button>
              )}
            </div>
          </div>
        )
      )}
    </Modal>
  )
}

/** Vehicles and drivers with the reasons they cannot take the trip (clash, maintenance, licence). */
function AssignForm({ tripId, onDone }: { tripId: string; onDone: () => void }) {
  const opts = useAssignOptions(tripId)
  const act = useTripAction()
  const [vehicle, setVehicle] = useState('')
  const [driver, setDriver] = useState('')
  if (opts.isPending) return <PageLoader />
  if (opts.isError) return <Alert>{errorMessage(opts.error)}</Alert>
  const label = (name: string, problems: string[]) => (problems.length ? `${name} — ${problems.join('; ')}` : name)
  return (
    <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'assign_tms_trip', args: { p_id: tripId, p_vehicle_id: vehicle, p_driver_id: driver } }, { onSuccess: onDone }) }}>
      <Select label="Vehicle" value={vehicle} placeholder="Choose…" required
        onChange={(e) => {
          setVehicle(e.target.value)
          const def = opts.data.vehicles.find((v) => v.id === e.target.value)?.default_driver_id
          if (def && !driver) setDriver(def)
        }}
        options={opts.data.vehicles.map((v) => ({ value: v.id, label: label(`${v.reg_no}${v.seats ? ` (${v.seats} seats)` : ''}`, v.problems) }))} />
      <Select label="Driver" value={driver} onChange={(e) => setDriver(e.target.value)} placeholder="Choose…" required
        options={opts.data.drivers.map((d) => ({ value: d.id, label: label(d.name, d.problems) }))} />
      <p className="text-xs text-slate-500">Reasons after a name mean it cannot take this trip; the final check also covers the licence class for the chosen vehicle.</p>
      {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onDone}>Back</Button>
        <Button type="submit" loading={act.isPending} disabled={!vehicle || !driver}>Assign</Button>
      </div>
    </form>
  )
}

// ----------------------------------------------------------------------------- driver view
/** My trips (drivers): start and end with the odometer and one GPS reading; add tolls and other costs. */
export function MyTripsPanel() {
  const trips = useTrips('driver')
  const [acting, setActing] = useState<{ trip: Trip; mode: 'start' | 'end' | 'expense' } | null>(null)
  if (trips.isPending) return <PageLoader />
  if (trips.isError) return <Alert>{errorMessage(trips.error)}</Alert>
  const open = trips.data.filter((t) => t.status === 'assigned' || t.status === 'in_progress')
  const done = trips.data.filter((t) => t.status === 'completed').slice(0, 10)
  return (
    <div className="space-y-4">
      <p className="text-sm text-slate-500">Your location is taken only when you press Start, End or log fuel; never in the background.</p>
      {open.length === 0 ? <EmptyState title="No trip assigned to you" /> : open.map((t) => (
        <Card key={t.id} className="space-y-3 p-4">
          <div className="flex flex-wrap items-center gap-2">
            <p className="font-medium text-slate-900">{t.from_place} → {t.to_place}</p>
            <Badge tone={TRIP_STATUS[t.status].tone}>{TRIP_STATUS[t.status].label}</Badge>
          </div>
          <p className="text-sm text-slate-600">{t.purpose} · {formatDateTime(t.planned_start)} · {t.vehicle?.reg_no}</p>
          <div className="flex flex-wrap gap-2">
            {t.status === 'assigned' && <Button onClick={() => setActing({ trip: t, mode: 'start' })}><Play className="size-4" /> Start trip</Button>}
            {t.status === 'in_progress' && <>
              <Button onClick={() => setActing({ trip: t, mode: 'end' })}><Square className="size-4" /> End trip</Button>
              <Button variant="secondary" onClick={() => setActing({ trip: t, mode: 'expense' })}><Receipt className="size-4" /> Add cost</Button>
            </>}
          </div>
        </Card>
      ))}
      {done.length > 0 && (
        <div>
          <h3 className="mb-2 text-sm font-semibold text-slate-900">Recent trips</h3>
          <ul className="space-y-2">{done.map((t) => (
            <li key={t.id} className="rounded-xl bg-white p-3 text-sm ring-1 ring-slate-200">
              {t.from_place} → {t.to_place} · {formatDateTime(t.started_at)} · {formatKm(t.distance_km)}
              {t.status === 'completed' && <button type="button" className="ml-3 text-xs text-primary-700 hover:underline" onClick={() => setActing({ trip: t, mode: 'expense' })}>Add cost</button>}
            </li>
          ))}</ul>
        </div>
      )}
      {acting && (acting.mode === 'expense'
        ? <ExpenseForm trip={acting.trip} onClose={() => setActing(null)} />
        : <OdometerForm trip={acting.trip} mode={acting.mode} onClose={() => setActing(null)} />)}
    </div>
  )
}

function OdometerForm({ trip, mode, onClose }: { trip: Trip; mode: 'start' | 'end'; onClose: () => void }) {
  const act = useTripAction()
  const [odo, setOdo] = useState('')
  const [locating, setLocating] = useState(false)
  const submit = async () => {
    setLocating(true)
    const pos = await currentPosition()
    setLocating(false)
    act.mutate({ fn: mode === 'start' ? 'start_tms_trip' : 'end_tms_trip', args: { p_id: trip.id, p: { odometer_km: odo, ...(pos ?? {}) } } }, { onSuccess: onClose })
  }
  return (
    <Modal open onClose={onClose} size="sm" title={mode === 'start' ? 'Start trip' : 'End trip'}
      description={`${trip.vehicle?.reg_no ?? ''} · ${trip.from_place} → ${trip.to_place}`}>
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); void submit() }}>
        <Input label="Odometer now (km)" type="number" step="0.1" inputMode="decimal" value={odo} onChange={(e) => setOdo(e.target.value)} required autoFocus
          hint={mode === 'end' && trip.start_odometer != null ? `Started at ${formatKm(trip.start_odometer)}` : 'Read it from the dashboard'} />
        <p className="text-xs text-slate-500">Your phone's location is recorded once now (allow it when asked). Without it the trip still starts.</p>
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <Button type="submit" className="w-full" loading={locating || act.isPending}>{mode === 'start' ? 'Start' : 'End'}</Button>
      </form>
    </Modal>
  )
}

function ExpenseForm({ trip, onClose }: { trip: Trip; onClose: () => void }) {
  const ctx = useMyContext()
  const add = useAddExpense()
  const [kind, setKind] = useState('toll')
  const [amount, setAmount] = useState('')
  const [note, setNote] = useState('')
  const [file, setFile] = useState<File | null>(null)
  return (
    <Modal open onClose={onClose} size="sm" title="Add a trip cost">
      <form className="space-y-3" onSubmit={(e) => {
        e.preventDefault()
        add.mutate({ orgId: ctx.organization!.id, tripId: trip.id, p: { kind, amount, note }, file }, { onSuccess: onClose })
      }}>
        <Select label="Kind" value={kind} onChange={(e) => setKind(e.target.value)} options={Object.entries(EXPENSE_KIND).map(([value, label]) => ({ value, label }))} />
        <Input label="Amount (৳)" type="number" step="0.01" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} required />
        <Input label="Note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Padma Bridge toll" />
        <label className="block text-sm text-slate-700">Receipt photo (optional)
          <input type="file" accept="image/*,application/pdf" capture="environment" className="mt-1 block w-full text-sm"
            onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
        </label>
        {add.isError && <Alert>{errorMessage(add.error)}</Alert>}
        <Button type="submit" className="w-full" loading={add.isPending}>Save</Button>
      </form>
    </Modal>
  )
}
