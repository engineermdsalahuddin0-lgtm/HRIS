import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { expiryBadge } from '@/DMS/core/dms'
import { LICENCE_CLASS, VEHICLE_STATUS, VEHICLE_TYPE, formatKm } from '../core/tms'
import type { Driver, Fleet, Vehicle } from '../core/types'
import { useFleet, useTmsOverview } from '../data/api'
import { DriverForm, VehicleForm } from '../components/FleetForms'
import { VehicleModal } from '../components/VehicleModal'

type Tab = 'overview' | 'vehicles' | 'drivers'

/** /transport: the Transport Management System. Tabs by permission; the database checks every action. */
export default function TmsPage() {
  const fleet = useFleet()
  const [params, setParams] = useSearchParams()
  const tab = (params.get('tab') as Tab | null) ?? 'overview'
  const go = (t: Tab) => setParams({ tab: t }, { replace: true })
  if (fleet.isPending) return <PageLoader />
  if (fleet.isError) {
    return (
      <div className="mx-auto max-w-3xl space-y-4">
        <PageHeader title="Transport" />
        <Alert>{errorMessage(fleet.error)}</Alert>
      </div>
    )
  }
  const f = fleet.data
  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Transport" description="Vehicles, drivers, papers, trips, fuel and costs in one place." />
      <Tabs<Tab> value={tab} onChange={go} tabs={[
        { key: 'overview', label: 'Overview' },
        { key: 'vehicles', label: 'Vehicles', count: f.vehicles.filter((v) => v.status !== 'disposed').length },
        { key: 'drivers', label: 'Drivers', count: f.drivers.filter((d) => d.status !== 'inactive').length },
      ]} />
      {tab === 'overview' && <OverviewTab onGo={go} />}
      {tab === 'vehicles' && <VehiclesTab fleet={f} />}
      {tab === 'drivers' && <DriversTab fleet={f} />}
    </div>
  )
}

function OverviewTab({ onGo }: { onGo: (t: Tab) => void }) {
  const o = useTmsOverview(true)
  if (o.isPending) return <PageLoader />
  if (o.isError) return <Alert>{errorMessage(o.error)}</Alert>
  const d = o.data
  const stats: [string, number, Tab, boolean][] = [
    ['Vehicles', d.vehicles.total, 'vehicles', false],
    ['Active', d.vehicles.active, 'vehicles', false],
    ['In maintenance', d.vehicles.in_maintenance, 'vehicles', d.vehicles.in_maintenance > 0],
    ['Off road', d.vehicles.off_road, 'vehicles', d.vehicles.off_road > 0],
    ['Active drivers', d.drivers.active, 'drivers', false],
    ['Licence expired', d.drivers.licence_expired, 'drivers', d.drivers.licence_expired > 0],
  ]
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-6">
        {stats.map(([label, value, target, warn]) => (
          <button key={label} type="button" onClick={() => onGo(target)} className="rounded-2xl bg-white p-4 text-left shadow-sm ring-1 ring-slate-200 hover:ring-primary-300">
            <p className="text-xs text-slate-500">{label}</p>
            <p className={cx('mt-1 text-2xl font-semibold', warn ? 'text-red-600' : 'text-slate-900')}>{value}</p>
          </button>
        ))}
      </div>
      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">Papers and licences expiring in 60 days</h3>
        {d.expiring.length === 0 ? <EmptyState title="Nothing expires in the next 60 days" /> : (
          <Table minWidth={640} head={<tr><th className={th}>What</th><th className={th}>Vehicle / driver</th><th className={th}>Expiry</th><th className={th}>Status</th></tr>}>
            {d.expiring.map((x, i) => {
              const b = expiryBadge(x.expiry_status, x.days_left)
              return (
                <tr key={i}>
                  <td className={td}>{x.what}{x.doc_code && <span className="ml-2 font-mono text-xs text-slate-500">{x.doc_code}</span>}</td>
                  <td className={td}>{[x.vehicle, x.driver].filter(Boolean).join(' · ') || '—'}</td>
                  <td className={cx(td, 'whitespace-nowrap')}>{formatDate(x.expiry_date)}</td>
                  <td className={td}><Badge tone={b.tone}>{b.label}</Badge></td>
                </tr>
              )
            })}
          </Table>
        )}
      </Card>
    </div>
  )
}

function VehiclesTab({ fleet }: { fleet: Fleet }) {
  const [editing, setEditing] = useState<Vehicle | 'new' | null>(null)
  const [open, setOpen] = useState<string | null>(null)
  const [showDisposed, setShowDisposed] = useState(false)
  const rows = fleet.vehicles.filter((v) => showDisposed || v.status !== 'disposed')
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={showDisposed} onChange={(e) => setShowDisposed(e.target.checked)} className="size-4 accent-primary-600" /> Show disposed
        </label>
        {fleet.can.manage && <Button onClick={() => setEditing('new')}><Plus className="size-4" /> Add vehicle</Button>}
      </div>
      {rows.length === 0 ? <EmptyState title="No vehicles yet">{fleet.can.manage ? 'Add the first vehicle.' : null}</EmptyState> : (
        <Table minWidth={860} head={
          <tr><th className={th}>Registration</th><th className={th}>Type</th><th className={th}>Driver</th><th className={th}>Odometer</th><th className={th}>Next paper expiry</th><th className={th}>Status</th></tr>
        }>
          {rows.map((v) => {
            const days = v.next_expiry ? Math.round((new Date(`${v.next_expiry}T00:00:00`).getTime() - new Date().setHours(0, 0, 0, 0)) / 86_400_000) : null
            const b = expiryBadge(days == null ? null : days < 0 ? 'expired' : days <= 60 ? 'due' : 'active', days)
            return (
              <tr key={v.id} className="cursor-pointer hover:bg-slate-50" onClick={() => setOpen(v.id)}>
                <td className={td}>
                  <span className="font-medium text-slate-900">{v.reg_no}</span>
                  <p className="text-xs text-slate-500">{[v.make, v.model, v.year].filter(Boolean).join(' ') || '—'}</p>
                </td>
                <td className={td}>{VEHICLE_TYPE[v.vtype]}</td>
                <td className={td}>{v.driver?.name ?? '—'}</td>
                <td className={cx(td, 'whitespace-nowrap')}>{formatKm(v.odometer_km)}</td>
                <td className={td}>{v.next_expiry ? <span className="inline-flex items-center gap-2 whitespace-nowrap">{formatDate(v.next_expiry)} <Badge tone={b.tone}>{b.label}</Badge></span>
                  : <span className="text-xs text-slate-400">{v.papers_count ? 'No expiry' : 'No papers'}</span>}</td>
                <td className={td}><Badge tone={VEHICLE_STATUS[v.status].tone}>{VEHICLE_STATUS[v.status].label}</Badge></td>
              </tr>
            )
          })}
        </Table>
      )}
      {editing && <VehicleForm fleet={fleet} vehicle={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
      {open && <VehicleModal id={open} canManage={fleet.can.manage} onClose={() => setOpen(null)}
        onEdit={() => { const v = fleet.vehicles.find((x) => x.id === open) ?? null; setOpen(null); setEditing(v) }} />}
    </div>
  )
}

function DriversTab({ fleet }: { fleet: Fleet }) {
  const [editing, setEditing] = useState<Driver | 'new' | null>(null)
  return (
    <div className="space-y-4">
      <div className="flex justify-end">{fleet.can.manage && <Button onClick={() => setEditing('new')}><Plus className="size-4" /> Add driver</Button>}</div>
      {fleet.drivers.length === 0 ? <EmptyState title="No drivers yet" /> : (
        <Table minWidth={860} head={
          <tr><th className={th}>Driver</th><th className={th}>Licence</th><th className={th}>Expiry</th><th className={th}>Vehicle</th><th className={th}>Status</th></tr>
        }>
          {fleet.drivers.map((d) => {
            const b = expiryBadge(d.licence_status, d.licence_days_left)
            return (
              <tr key={d.id} className={cx(fleet.can.manage && 'cursor-pointer hover:bg-slate-50', d.status === 'inactive' && 'opacity-60')}
                onClick={() => fleet.can.manage && setEditing(d)}>
                <td className={td}>
                  <span className="font-medium text-slate-900">{d.name}</span>
                  <p className="text-xs text-slate-500">{d.outside ? 'Outside driver' : d.department ?? 'Employee'}{d.phone ? ` · ${d.phone}` : ''}{d.has_login ? ' · uses the app' : ''}</p>
                </td>
                <td className={td}>
                  <span className="font-mono text-xs">{d.licence_no}</span>
                  <p className="text-xs text-slate-500">{LICENCE_CLASS[d.licence_class]} · {d.licence_kind === 'professional' ? 'Professional' : 'Non-professional'}</p>
                </td>
                <td className={td}><span className="inline-flex items-center gap-2 whitespace-nowrap">{formatDate(d.licence_expiry)} <Badge tone={b.tone}>{b.label}</Badge></span></td>
                <td className={td}>{d.vehicle?.reg_no ?? '—'}</td>
                <td className={td}><Badge tone={d.status === 'active' ? 'green' : d.status === 'off_duty' ? 'orange' : 'slate'}>{d.status.replace('_', ' ')}</Badge></td>
              </tr>
            )
          })}
        </Table>
      )}
      {editing && <DriverForm fleet={fleet} driver={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
    </div>
  )
}
