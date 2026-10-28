import { useState } from 'react'
import { Download, MapPin } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { downloadText, toCsv } from '@/lib/payrollRuns'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Table, td, th } from '@/components/kit'
import { UNIT_LABEL, VEHICLE_TYPE, formatKm, formatTaka, mapsLink } from '../core/tms'
import type { Costs } from '../core/types'
import { useCosts } from '../data/api'

const iso = (d: Date) => d.toISOString().slice(0, 10)

/** tms.view_costs: what each vehicle costs (fuel, repairs, trip costs), per km, and what is on the road now. */
export function CostsPanel() {
  const now = new Date()
  const [from, setFrom] = useState(iso(new Date(now.getFullYear(), now.getMonth(), 1)))
  const [to, setTo] = useState(iso(now))
  const costs = useCosts(from, to)
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end gap-3">
        <Input label="From" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
        <Input label="To" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        <Button variant="secondary" className="ml-auto" disabled={!costs.data?.vehicles.length} onClick={() => costs.data && exportCsv(costs.data)}>
          <Download className="size-4" /> Export CSV
        </Button>
      </div>
      {costs.isPending ? <PageLoader /> : costs.isError ? <Alert>{errorMessage(costs.error)}</Alert> : <Body c={costs.data} />}
    </div>
  )
}

function Body({ c }: { c: Costs }) {
  const t = c.totals
  const tiles: [string, string][] = [
    ['Total cost', formatTaka(t.total_cost)], ['Cost per km', t.cost_per_km != null ? formatTaka(t.cost_per_km) : '—'],
    ['Distance', formatKm(t.distance_km)], ['Fuel', formatTaka(t.fuel_cost)], ['Repairs', formatTaka(t.repair_cost)], ['Trip costs', formatTaka(t.trip_cost)],
  ]
  return (
    <>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-6">
        {tiles.map(([k, v]) => (
          <Card key={k} className="p-4"><p className="text-xs text-slate-500">{k}</p><p className="mt-1 text-xl font-semibold text-slate-900">{v}</p></Card>
        ))}
      </div>

      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">On the road now ({c.live.length})</h3>
        {c.live.length === 0 ? <p className="text-sm text-slate-500">No vehicle is on a trip.</p> : (
          <ul className="space-y-2 text-sm">
            {c.live.map((l) => (
              <li key={l.trip_id} className="flex flex-wrap items-center gap-3">
                <span className="font-medium text-slate-900">{l.reg_no}</span>
                <span>{l.driver} · {l.from_place} → {l.to_place} · since {formatDateTime(l.started_at)}</span>
                {l.last_point && (
                  <a href={mapsLink(l.last_point)} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 text-xs text-primary-700 hover:underline">
                    <MapPin className="size-3.5" aria-hidden /> Last seen {formatDateTime(l.last_point.at)} ({l.last_point.event.replace('_', ' ')})
                  </a>
                )}
              </li>
            ))}
          </ul>
        )}
        <p className="text-xs text-slate-500">Phase 1 shows the last trip start, end or fuel point. A GPS device (Phase 2) will give a live map.</p>
      </Card>

      {c.vehicles.length === 0 ? <EmptyState title="No vehicles" /> : (
        <Table minWidth={980} head={
          <tr><th className={th}>Vehicle</th><th className={th}>Distance</th><th className={th}>Fuel</th><th className={th}>km / unit</th>
            <th className={th}>Repairs</th><th className={th}>Trip costs</th><th className={th}>Total</th><th className={th}>Per km</th></tr>
        }>
          {c.vehicles.map((v) => (
            <tr key={v.id}>
              <td className={td}>
                <span className="font-medium text-slate-900">{v.reg_no}</span>
                <p className="text-xs text-slate-500">{VEHICLE_TYPE[v.vtype]} · {v.trips} trips</p>
                {v.flagged_fills > 0 && <Badge tone="red">{v.flagged_fills} fuel to check</Badge>}
              </td>
              <td className={td}>{formatKm(v.distance_km)}</td>
              <td className={td}>{formatTaka(v.fuel_cost)}
                <p className="text-xs text-slate-500">{Object.entries(v.fuel_qty).map(([u, q]) => `${q} ${UNIT_LABEL[u as keyof typeof UNIT_LABEL]}`).join(' · ')}</p></td>
              <td className={td}>{v.km_per_unit ?? '—'}</td>
              <td className={td}>{formatTaka(v.repair_cost)}</td>
              <td className={td}>{formatTaka(v.trip_cost)}</td>
              <td className={`${td} font-medium`}>{formatTaka(v.total_cost)}</td>
              <td className={td}>{v.cost_per_km != null ? formatTaka(v.cost_per_km) : '—'}</td>
            </tr>
          ))}
        </Table>
      )}
    </>
  )
}

function exportCsv(c: Costs) {
  downloadText(`transport-costs-${c.from}-to-${c.to}.csv`, toCsv(
    ['Vehicle', 'Type', 'Distance km', 'Fuel cost', 'Fuel litres', 'Fuel m3', 'km per unit', 'Repairs', 'Trip costs', 'Total', 'Cost per km', 'Trips'],
    c.vehicles.map((v) => [v.reg_no, VEHICLE_TYPE[v.vtype], v.distance_km, v.fuel_cost, v.fuel_qty.l ?? '', v.fuel_qty.m3 ?? '', v.km_per_unit ?? '',
      v.repair_cost, v.trip_cost, v.total_cost, v.cost_per_km ?? '', v.trips])))
}
