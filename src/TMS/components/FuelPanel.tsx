import { useState } from 'react'
import { Fuel as FuelIcon, MapPin } from 'lucide-react'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, Select, Table, td, th } from '@/components/kit'
import { FUEL, UNIT_LABEL, formatKm, formatTaka, mapsLink } from '../core/tms'
import type { Fuel, FuelFlag, FuelLog, TmsSettings } from '../core/types'
import { openTmsFile, useFuel, useFuelVehicles, useLogFuel, useTmsSettings, useTripAction } from '../data/api'

export const FLAG_LABEL: Record<FuelFlag, string> = {
  over_tank: 'More than the tank holds',
  odometer_back: 'Odometer went back',
  price_off: 'Price off the company rate',
  low_efficiency: 'Low km per unit',
}

/** The desk: every fill, flagged ones first to verify or dispute; company fuel prices. */
export function FuelPanel({ canManage }: { canManage: boolean }) {
  const [onlyFlagged, setOnlyFlagged] = useState(true)
  const list = useFuel({ scope: 'all', flagged: onlyFlagged })
  const review = useTripAction()
  const [logging, setLogging] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)
  return (
    <div className="space-y-6">
      {canManage && <PricesCard />}
      <div className="flex flex-wrap items-center gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={onlyFlagged} onChange={(e) => setOnlyFlagged(e.target.checked)} className="size-4 accent-primary-600" /> Only fills to check
        </label>
        {canManage && <Button className="ml-auto" onClick={() => setLogging(true)}><FuelIcon className="size-4" /> Log fuel</Button>}
      </div>
      {(review.error || fileError) && <Alert>{fileError ?? errorMessage(review.error)}</Alert>}
      {list.isPending ? <PageLoader /> : list.isError ? <Alert>{errorMessage(list.error)}</Alert>
        : list.data.length === 0 ? <EmptyState title={onlyFlagged ? 'Nothing to check' : 'No fuel logged in the last 90 days'} /> : (
          <Table minWidth={980} head={
            <tr><th className={th}>When / vehicle</th><th className={th}>Fuel</th><th className={th}>Amount</th><th className={th}>Odometer</th>
              <th className={th}>km per unit</th><th className={th}>Check</th><th className={th} aria-label="Actions" /></tr>
          }>
            {list.data.map((f) => (
              <tr key={f.id}>
                <td className={td}>
                  <span className="font-medium text-slate-900">{f.reg_no}</span>
                  <p className="text-xs text-slate-500">{formatDateTime(f.filled_at)} · {f.driver ?? f.logged_by ?? '—'}{f.station ? ` · ${f.station}` : ''}</p>
                </td>
                <td className={td}>{f.quantity} {UNIT_LABEL[f.unit]} {FUEL[f.fuel].label}{f.full_tank ? '' : ' (part)'}</td>
                <td className={td}>{formatTaka(f.amount)}<p className="text-xs text-slate-500">৳{f.unit_price}/{UNIT_LABEL[f.unit]} · {f.paid_by.replace('_', ' ')}</p></td>
                <td className={td}>{formatKm(f.odometer_km)}</td>
                <td className={td}>{f.km_per_unit ?? '—'}</td>
                <td className={td}>
                  {f.flags.length > 0 && <div className="flex flex-wrap gap-1">{f.flags.map((x) => <Badge key={x} tone="red">{FLAG_LABEL[x]}</Badge>)}</div>}
                  <span className="text-xs text-slate-500">{f.status}{f.review_note ? `: ${f.review_note}` : ''}</span>
                </td>
                <td className={`${td} whitespace-nowrap text-right`}>
                  {f.point && <a href={mapsLink(f.point)} target="_blank" rel="noopener noreferrer" className="mr-2 inline-flex text-slate-500 hover:text-primary-700" title="Where">
                    <MapPin className="size-4" /></a>}
                  {f.receipt_path && <button type="button" className="mr-2 text-xs text-primary-700 hover:underline"
                    onClick={() => openTmsFile(f.receipt_path!).catch((e) => setFileError(errorMessage(e)))}>Receipt</button>}
                  {canManage && f.status === 'flagged' && <>
                    <Button variant="ghost" onClick={() => review.mutate({ fn: 'review_tms_fuel', args: { p_id: f.id, p_ok: true, p_note: null } })}>Verify</Button>
                    <Button variant="ghost" onClick={() => { const n = window.prompt('Why is this fill disputed?'); if (n) review.mutate({ fn: 'review_tms_fuel', args: { p_id: f.id, p_ok: false, p_note: n } }) }}>Dispute</Button>
                  </>}
                </td>
              </tr>
            ))}
          </Table>
        )}
      {logging && <FuelForm onClose={() => setLogging(false)} />}
    </div>
  )
}

function PricesCard() {
  const settings = useTmsSettings(true)
  const save = useTripAction()
  const [draft, setDraft] = useState<TmsSettings | null>(null)
  if (!settings.data) return null
  const s = draft ?? settings.data
  const fuels = Object.keys(FUEL) as Fuel[]
  return (
    <Card className="space-y-3">
      <div>
        <h3 className="text-base font-semibold text-slate-900">Company fuel prices</h3>
        <p className="text-sm text-slate-500">A fill priced further from these than the tolerance is flagged. Update them when the government price changes.</p>
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-8">
        {fuels.map((k) => (
          <Input key={k} label={`${FUEL[k].label} ৳/${UNIT_LABEL[FUEL[k].unit]}`} type="number" step="0.01" value={s.fuel_prices[k] ?? ''}
            onChange={(e) => setDraft({ ...s, fuel_prices: { ...s.fuel_prices, [k]: e.target.value === '' ? undefined : Number(e.target.value) } })} />
        ))}
        <Input label="Price tolerance %" type="number" value={s.price_tolerance_pct} onChange={(e) => setDraft({ ...s, price_tolerance_pct: Number(e.target.value) })} />
        <Input label="km/unit tolerance %" type="number" value={s.efficiency_tolerance_pct} onChange={(e) => setDraft({ ...s, efficiency_tolerance_pct: Number(e.target.value) })} />
      </div>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <Button disabled={!draft} loading={save.isPending} onClick={() => save.mutate({ fn: 'save_tms_settings', args: { p: s } }, { onSuccess: () => setDraft(null) })}>Save prices</Button>
    </Card>
  )
}

/** Log a fill: the driver (their vehicle) or the desk (any vehicle). One GPS reading is taken. */
export function FuelForm({ onClose }: { onClose: () => void }) {
  const ctx = useMyContext()
  const vehicles = useFuelVehicles()
  const log = useLogFuel()
  const [vehicleId, setVehicleId] = useState('')
  const [fuel, setFuel] = useState<Fuel | ''>('')
  const [qty, setQty] = useState('')
  const [price, setPrice] = useState('')
  const [amount, setAmount] = useState('')
  const [odo, setOdo] = useState('')
  const [full, setFull] = useState(true)
  const [station, setStation] = useState('')
  const [paidBy, setPaidBy] = useState('company')
  const [file, setFile] = useState<File | null>(null)
  const [result, setResult] = useState<FuelLog | null>(null)
  const v = vehicles.data?.find((x) => x.id === vehicleId)
  const fuels = v ? [v.fuel, ...(v.fuel2 ? [v.fuel2] : [])] : []
  const pick = (id: string) => {
    const nv = vehicles.data?.find((x) => x.id === id)
    setVehicleId(id)
    setFuel(nv?.fuel ?? '')
    setPrice(nv?.price?.[nv.fuel] != null ? String(nv.price[nv.fuel]) : '')
  }
  const unit = fuel ? UNIT_LABEL[FUEL[fuel].unit] : ''
  return (
    <Modal open onClose={onClose} size="md" title="Log fuel" description="Your location is taken once when you save.">
      {result ? (
        <div className="space-y-3">
          <Alert tone={result.flags.length ? 'info' : 'success'}>
            Saved: {result.quantity} {UNIT_LABEL[result.unit]} for {formatTaka(result.amount)}{result.km_per_unit ? ` · ${result.km_per_unit} km per ${UNIT_LABEL[result.unit]}` : ''}.
            {result.flags.length > 0 && <> The desk will check it: {result.flags.map((x) => FLAG_LABEL[x]).join(', ')}.</>}
          </Alert>
          <Button className="w-full" onClick={onClose}>Done</Button>
        </div>
      ) : vehicles.isPending ? <PageLoader /> : (vehicles.data ?? []).length === 0 ? (
        <Alert tone="info">No vehicle to log fuel for: you are not the driver of a vehicle right now.</Alert>
      ) : (
        <form className="space-y-3" onSubmit={(e) => {
          e.preventDefault()
          log.mutate({ orgId: ctx.organization!.id, file, p: {
            vehicle_id: vehicleId, fuel, quantity: qty, unit_price: price || null, amount: amount || null, odometer_km: odo, full_tank: full,
            station, paid_by: paidBy, trip_id: v?.trip_id ?? null,
          } }, { onSuccess: setResult })
        }}>
          <Select label="Vehicle" value={vehicleId} onChange={(e) => pick(e.target.value)} placeholder="Choose…" required
            options={(vehicles.data ?? []).map((x) => ({ value: x.id, label: `${x.reg_no} · ${formatKm(x.odometer_km)}` }))} />
          {fuels.length > 1 && <Select label="Fuel" value={fuel} onChange={(e) => { const f = e.target.value as Fuel; setFuel(f); setPrice(v?.price?.[f] != null ? String(v.price[f]) : '') }}
            options={fuels.map((f) => ({ value: f, label: FUEL[f].label }))} />}
          <div className="grid grid-cols-2 gap-3">
            <Input label={`Quantity (${unit || '…'})`} type="number" step="0.01" inputMode="decimal" value={qty} onChange={(e) => setQty(e.target.value)} required />
            <Input label={`Price (৳/${unit || '…'})`} type="number" step="0.01" inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} />
            <Input label="Or total amount (৳)" type="number" step="0.01" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} />
            <Input label="Odometer (km)" type="number" step="0.1" inputMode="decimal" value={odo} onChange={(e) => setOdo(e.target.value)} required
              hint={v ? `Last: ${formatKm(v.odometer_km)}` : undefined} />
          </div>
          <label className="inline-flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" checked={full} onChange={(e) => setFull(e.target.checked)} className="size-4 accent-primary-600" /> Filled to full (used for km per unit)
          </label>
          <div className="grid grid-cols-2 gap-3">
            <Input label="Station" value={station} onChange={(e) => setStation(e.target.value)} />
            <Select label="Paid by" value={paidBy} onChange={(e) => setPaidBy(e.target.value)}
              options={[{ value: 'company', label: 'Company' }, { value: 'driver_cash', label: 'Driver (cash)' }, { value: 'card', label: 'Fuel card' }]} />
          </div>
          <label className="block text-sm text-slate-700">Receipt photo (optional)
            <input type="file" accept="image/*,application/pdf" capture="environment" className="mt-1 block w-full text-sm" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </label>
          {log.isError && <Alert>{errorMessage(log.error)}</Alert>}
          <Button type="submit" className="w-full" loading={log.isPending} disabled={!vehicleId || !fuel}>Save</Button>
        </form>
      )}
    </Modal>
  )
}
