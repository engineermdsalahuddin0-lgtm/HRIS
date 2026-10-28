import { useState } from 'react'
import { Plus, Wrench } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, Select, Table, Textarea, td, th } from '@/components/kit'
import { formatKm, formatTaka } from '../core/tms'
import type { Fleet, JobCard, Part, ServicePlan } from '../core/types'
import { useInventory, useMaintenance, useTripAction } from '../data/api'

const PLAN_STATUS: Record<ServicePlan['status'], { label: string; tone: 'red' | 'orange' | 'green' }> = {
  overdue: { label: 'Overdue', tone: 'red' }, due_soon: { label: 'Due soon', tone: 'orange' }, ok: { label: 'OK', tone: 'green' },
}
const KIND = { service: 'Service', repair: 'Repair', accident: 'Accident' } as const

/** Service plans (km / months), open job cards with parts from stock, closed history. */
export function MaintenancePanel({ fleet }: { fleet: Fleet }) {
  const data = useMaintenance()
  const act = useTripAction()
  const [planning, setPlanning] = useState(false)
  const [opening, setOpening] = useState<{ vehicleId?: string; planId?: string } | null>(null)
  const [closing, setClosing] = useState<JobCard | null>(null)
  if (data.isPending) return <PageLoader />
  if (data.isError) return <Alert>{errorMessage(data.error)}</Alert>
  const d = data.data
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap justify-end gap-2">
        <Button variant="secondary" onClick={() => setPlanning(true)}><Plus className="size-4" /> Service plan</Button>
        <Button onClick={() => setOpening({})}><Wrench className="size-4" /> Open job card</Button>
      </div>
      {act.isError && <Alert>{errorMessage(act.error)}</Alert>}

      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">Service plans</h3>
        {d.plans.length === 0 ? <EmptyState title="No service plans">Add one per vehicle: engine oil every 5,000 km, tyres, battery…</EmptyState> : (
          <Table minWidth={760} head={<tr><th className={th}>Vehicle</th><th className={th}>Service</th><th className={th}>Every</th><th className={th}>Next</th><th className={th}>Status</th><th className={th} aria-label="Actions" /></tr>}>
            {d.plans.map((p) => (
              <tr key={p.id}>
                <td className={td}>{p.reg_no}</td>
                <td className={td}>{p.name}</td>
                <td className={td}>{[p.every_km ? formatKm(p.every_km) : null, p.every_months ? `${p.every_months} months` : null].filter(Boolean).join(' / ')}</td>
                <td className={td}>{[p.next_km != null ? `${formatKm(p.next_km)}${p.km_left != null ? ` (${p.km_left > 0 ? `${Math.round(p.km_left)} km left` : 'passed'})` : ''}` : null,
                  p.next_date ? formatDate(p.next_date) : null].filter(Boolean).join(' · ')}</td>
                <td className={td}><Badge tone={PLAN_STATUS[p.status].tone}>{PLAN_STATUS[p.status].label}</Badge></td>
                <td className={`${td} text-right`}>
                  {p.status !== 'ok' && <Button variant="ghost" onClick={() => setOpening({ vehicleId: p.vehicle_id, planId: p.id })}>Open job card</Button>}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">Open job cards ({d.open.length})</h3>
        {d.open.length === 0 ? <EmptyState title="No vehicle in the workshop" /> : d.open.map((j) => (
          <JobRow key={j.id} job={j} onClose={() => setClosing(j)} />
        ))}
      </Card>

      {d.closed.length > 0 && (
        <Card className="space-y-3">
          <h3 className="text-base font-semibold text-slate-900">Recent work</h3>
          <Table minWidth={760} head={<tr><th className={th}>Closed</th><th className={th}>Vehicle</th><th className={th}>Work</th><th className={th}>Workshop</th><th className={th}>Cost</th></tr>}>
            {d.closed.map((j) => (
              <tr key={j.id}>
                <td className={td}>{formatDate(j.closed_at)}</td>
                <td className={td}>{j.reg_no}</td>
                <td className={td}>{KIND[j.kind]}: {j.description}</td>
                <td className={td}>{j.workshop ?? '—'}</td>
                <td className={td}>{formatTaka(j.total_cost)}</td>
              </tr>
            ))}
          </Table>
        </Card>
      )}

      {planning && <PlanForm fleet={fleet} onClose={() => setPlanning(false)} />}
      {opening && <JobForm fleet={fleet} plans={d.plans} initial={opening} onClose={() => setOpening(null)} />}
      {closing && <CloseJobForm job={closing} onClose={() => setClosing(null)} />}
    </div>
  )
}

function JobRow({ job: j, onClose }: { job: JobCard; onClose: () => void }) {
  const [issuing, setIssuing] = useState(false)
  return (
    <div className="space-y-2 rounded-xl p-3 text-sm ring-1 ring-slate-200">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-medium text-slate-900">{j.reg_no}</span>
        <Badge tone="orange">{KIND[j.kind]}</Badge>
        <span className="text-slate-600">{j.description}{j.plan ? ` (${j.plan})` : ''}</span>
        <span className="ml-auto text-xs text-slate-500">{j.workshop ?? 'Workshop not set'} · opened {formatDateTime(j.opened_at)}</span>
      </div>
      {j.parts.length > 0 && <p className="text-xs text-slate-600">Parts: {j.parts.map((p) => `${p.part} × ${p.qty} ${p.unit}`).join(', ')} · {formatTaka(j.stock_parts_cost)}</p>}
      <div className="flex gap-2">
        <Button variant="secondary" onClick={() => setIssuing(true)}>Issue parts</Button>
        <Button onClick={onClose}>Close job</Button>
      </div>
      {issuing && <IssueForm jobId={j.id} onClose={() => setIssuing(false)} />}
    </div>
  )
}

function PlanForm({ fleet, onClose }: { fleet: Fleet; onClose: () => void }) {
  const act = useTripAction()
  const [f, setF] = useState({ vehicle_id: '', name: 'Engine oil', every_km: '5000', every_months: '6', last_km: '', last_date: '' })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} title="Service plan" description="When was it last done? The next service is counted from there.">
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'save_tms_service_plan', args: { p_id: null, p: f } }, { onSuccess: onClose }) }}>
        <Select label="Vehicle" value={f.vehicle_id} onChange={set('vehicle_id')} placeholder="Choose…" required
          options={fleet.vehicles.filter((v) => v.status !== 'disposed').map((v) => ({ value: v.id, label: `${v.reg_no} · ${formatKm(v.odometer_km)}` }))} />
        <Input label="Service" value={f.name} onChange={set('name')} required />
        <div className="grid grid-cols-2 gap-3">
          <Input label="Every (km)" type="number" value={f.every_km} onChange={set('every_km')} />
          <Input label="Or every (months)" type="number" value={f.every_months} onChange={set('every_months')} />
          <Input label="Last done at (km)" type="number" value={f.last_km} onChange={set('last_km')} hint="Empty = now" />
          <Input label="Last done on" type="date" value={f.last_date} onChange={set('last_date')} hint="Empty = today" />
        </div>
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <Button type="submit" className="w-full" loading={act.isPending}>Save</Button>
      </form>
    </Modal>
  )
}

function JobForm({ fleet, plans, initial, onClose }: { fleet: Fleet; plans: ServicePlan[]; initial: { vehicleId?: string; planId?: string }; onClose: () => void }) {
  const act = useTripAction()
  const plan = plans.find((p) => p.id === initial.planId)
  const [f, setF] = useState({ vehicle_id: initial.vehicleId ?? '', plan_id: initial.planId ?? '', kind: plan ? 'service' : 'repair',
    workshop: '', description: plan?.name ?? '', odometer_km: '' })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} title="Open job card" description="The vehicle is marked In maintenance until the job is closed.">
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'open_tms_job_card', args: { p: f } }, { onSuccess: onClose }) }}>
        <Select label="Vehicle" value={f.vehicle_id} onChange={set('vehicle_id')} placeholder="Choose…" required
          options={fleet.vehicles.filter((v) => v.status !== 'disposed').map((v) => ({ value: v.id, label: v.reg_no }))} />
        <div className="grid grid-cols-2 gap-3">
          <Select label="Kind" value={f.kind} onChange={set('kind')} options={Object.entries(KIND).map(([value, label]) => ({ value, label }))} />
          <Select label="Service plan" value={f.plan_id} onChange={set('plan_id')} placeholder="None"
            options={plans.filter((p) => p.vehicle_id === f.vehicle_id).map((p) => ({ value: p.id, label: p.name }))} />
        </div>
        <Input label="Workshop" value={f.workshop} onChange={set('workshop')} placeholder="In-house or garage name" />
        <Textarea label="Work to do" value={f.description} onChange={set('description')} required />
        <Input label="Odometer (km)" type="number" value={f.odometer_km} onChange={set('odometer_km')} hint="Empty = the vehicle's last reading" />
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <Button type="submit" className="w-full" loading={act.isPending}>Open</Button>
      </form>
    </Modal>
  )
}

function CloseJobForm({ job, onClose }: { job: JobCard; onClose: () => void }) {
  const act = useTripAction()
  const [f, setF] = useState({ labour_cost: '', outside_parts_cost: '', odometer_km: String(job.odometer_km ?? ''), close_note: '' })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} title={`Close job: ${job.reg_no}`} description="Parts issued from stock are already counted.">
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'close_tms_job_card', args: { p_id: job.id, p: f } }, { onSuccess: onClose }) }}>
        <div className="grid grid-cols-2 gap-3">
          <Input label="Labour (৳)" type="number" step="0.01" value={f.labour_cost} onChange={set('labour_cost')} />
          <Input label="Parts bought outside (৳)" type="number" step="0.01" value={f.outside_parts_cost} onChange={set('outside_parts_cost')} />
        </div>
        <Input label="Odometer at handover (km)" type="number" value={f.odometer_km} onChange={set('odometer_km')} />
        <Textarea label="Note" value={f.close_note} onChange={set('close_note')} />
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <div className="flex justify-between gap-2">
          <Button type="button" variant="ghost" onClick={() => act.mutate({ fn: 'close_tms_job_card', args: { p_id: job.id, p: { cancel: true, close_note: f.close_note || 'Cancelled' } } }, { onSuccess: onClose })}>
            Cancel job</Button>
          <Button type="submit" loading={act.isPending}>Close and return the vehicle</Button>
        </div>
      </form>
    </Modal>
  )
}

function IssueForm({ jobId, onClose }: { jobId: string; onClose: () => void }) {
  const inv = useInventory()
  const act = useTripAction()
  const [partId, setPartId] = useState('')
  const [qty, setQty] = useState('')
  const part = inv.data?.parts.find((p) => p.id === partId)
  return (
    <form className="flex flex-wrap items-end gap-2 rounded-lg bg-slate-50 p-2" onSubmit={(e) => {
      e.preventDefault()
      act.mutate({ fn: 'tms_stock_move', args: { p: { part_id: partId, kind: 'issue', qty, job_card_id: jobId } } }, { onSuccess: onClose })
    }}>
      <Select label="Part" value={partId} onChange={(e) => setPartId(e.target.value)} placeholder="Choose…" className="min-w-56 flex-1"
        options={(inv.data?.parts ?? []).filter((p) => p.active && p.on_hand > 0).map((p) => ({ value: p.id, label: `${p.name} (${p.on_hand} ${p.unit})` }))} />
      <Input label={`Qty${part ? ` (${part.unit})` : ''}`} type="number" step="0.01" value={qty} onChange={(e) => setQty(e.target.value)} className="w-28" />
      <Button type="submit" loading={act.isPending} disabled={!partId || !qty}>Issue</Button>
      <Button type="button" variant="ghost" onClick={onClose}>Back</Button>
      {act.isError && <p className="w-full text-xs text-red-600">{errorMessage(act.error)}</p>}
    </form>
  )
}

// ----------------------------------------------------------------------------- inventory
const CATEGORY = { part: 'Part', tyre: 'Tyre', lubricant: 'Lubricant', battery: 'Battery', other: 'Other' } as const

/** Parts and tyres: stock, value, low-stock list, receive / issue / adjust, history. */
export function InventoryPanel({ fleet }: { fleet: Fleet }) {
  const inv = useInventory()
  const [adding, setAdding] = useState(false)
  const [moving, setMoving] = useState<Part | null>(null)
  if (inv.isPending) return <PageLoader />
  if (inv.isError) return <Alert>{errorMessage(inv.error)}</Alert>
  const d = inv.data
  const low = d.parts.filter((p) => p.low && p.active)
  return (
    <div className="space-y-6">
      {low.length > 0 && <Alert tone="info">Low stock: {low.map((p) => `${p.name} (${p.on_hand} ${p.unit})`).join(', ')}</Alert>}
      {d.can_manage_stock && <div className="flex justify-end"><Button onClick={() => setAdding(true)}><Plus className="size-4" /> New part</Button></div>}
      {d.parts.length === 0 ? <EmptyState title="No parts yet" /> : (
        <Table minWidth={760} head={<tr><th className={th}>Part</th><th className={th}>Category</th><th className={th}>In stock</th><th className={th}>Avg cost</th><th className={th}>Value</th><th className={th} aria-label="Actions" /></tr>}>
          {d.parts.map((p) => (
            <tr key={p.id} className={p.active ? '' : 'opacity-60'}>
              <td className={td}><span className="font-medium text-slate-900">{p.name}</span> <span className="font-mono text-xs text-slate-500">{p.code}</span></td>
              <td className={td}>{CATEGORY[p.category]}</td>
              <td className={td}>{p.on_hand} {p.unit}{p.low && <> <Badge tone="red">Low</Badge></>}</td>
              <td className={td}>{formatTaka(p.avg_cost)}</td>
              <td className={td}>{formatTaka(p.value)}</td>
              <td className={`${td} text-right`}>{d.can_manage_stock && <Button variant="ghost" onClick={() => setMoving(p)}>Receive / issue</Button>}</td>
            </tr>
          ))}
        </Table>
      )}
      {d.moves.length > 0 && (
        <Card className="space-y-2">
          <h3 className="text-base font-semibold text-slate-900">Recent moves</h3>
          <ul className="divide-y divide-slate-100 text-sm">
            {d.moves.map((m) => (
              <li key={m.id} className="flex flex-wrap gap-x-3 py-1.5">
                <span className="text-xs text-slate-500">{formatDateTime(m.moved_at)}</span>
                <span className="font-medium">{m.kind}</span>
                <span>{m.part} × {m.qty} {m.unit}</span>
                <span className="text-xs text-slate-500">{[m.reg_no, m.supplier, m.ref, m.note, m.by].filter(Boolean).join(' · ')}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}
      {adding && <PartForm onClose={() => setAdding(false)} />}
      {moving && <MoveForm part={moving} fleet={fleet} onClose={() => setMoving(null)} />}
    </div>
  )
}

function PartForm({ onClose }: { onClose: () => void }) {
  const act = useTripAction()
  const [f, setF] = useState({ code: '', name: '', category: 'part', unit: 'pcs', min_stock: '' })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} title="New part">
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'save_tms_part', args: { p_id: null, p: f } }, { onSuccess: onClose }) }}>
        <div className="grid grid-cols-2 gap-3">
          <Input label="Code" value={f.code} onChange={set('code')} required placeholder="TYRE-195-65R15" />
          <Select label="Category" value={f.category} onChange={set('category')} options={Object.entries(CATEGORY).map(([value, label]) => ({ value, label }))} />
        </div>
        <Input label="Name" value={f.name} onChange={set('name')} required />
        <div className="grid grid-cols-2 gap-3">
          <Input label="Unit" value={f.unit} onChange={set('unit')} placeholder="pcs, litre, set" />
          <Input label="Minimum stock" type="number" value={f.min_stock} onChange={set('min_stock')} />
        </div>
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <Button type="submit" className="w-full" loading={act.isPending}>Save</Button>
      </form>
    </Modal>
  )
}

function MoveForm({ part, fleet, onClose }: { part: Part; fleet: Fleet; onClose: () => void }) {
  const act = useTripAction()
  const [f, setF] = useState({ kind: 'receive', qty: '', unit_cost: '', vehicle_id: '', supplier: '', ref: '', note: '' })
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} title={part.name} description={`In stock: ${part.on_hand} ${part.unit} · average ${formatTaka(part.avg_cost)}`}>
      <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); act.mutate({ fn: 'tms_stock_move', args: { p: { ...f, part_id: part.id } } }, { onSuccess: onClose }) }}>
        <Select label="Move" value={f.kind} onChange={set('kind')}
          options={[{ value: 'receive', label: 'Receive (bought)' }, { value: 'issue', label: 'Issue to a vehicle' }, { value: 'adjust', label: 'Adjust (count, damage)' }]} />
        <Input label={`Quantity (${part.unit})${f.kind === 'adjust' ? ', minus to reduce' : ''}`} type="number" step="0.01" value={f.qty} onChange={set('qty')} required />
        {f.kind === 'receive' && <>
          <Input label="Unit cost (৳)" type="number" step="0.01" value={f.unit_cost} onChange={set('unit_cost')} required />
          <div className="grid grid-cols-2 gap-3">
            <Input label="Supplier" value={f.supplier} onChange={set('supplier')} />
            <Input label="Bill / challan no." value={f.ref} onChange={set('ref')} />
          </div>
        </>}
        {f.kind === 'issue' && <Select label="Vehicle" value={f.vehicle_id} onChange={set('vehicle_id')} placeholder="Choose…" required
          options={fleet.vehicles.filter((v) => v.status !== 'disposed').map((v) => ({ value: v.id, label: v.reg_no }))} />}
        <Input label={f.kind === 'adjust' ? 'Reason *' : 'Note'} value={f.note} onChange={set('note')} required={f.kind === 'adjust'} />
        {act.isError && <Alert>{errorMessage(act.error)}</Alert>}
        <Button type="submit" className="w-full" loading={act.isPending}>Save</Button>
      </form>
    </Modal>
  )
}
