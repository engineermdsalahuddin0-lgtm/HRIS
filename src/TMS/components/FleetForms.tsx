import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'
import { FUEL, LICENCE_CLASS, VEHICLE_STATUS, VEHICLE_TYPE, classCovers, normRegNo } from '../core/tms'
import type { Driver, Fleet, Vehicle, VehicleType } from '../core/types'
import { useSaveDriver, useSaveVehicle } from '../data/api'

const opts = <K extends string>(r: Record<K, string | { label: string }>) =>
  (Object.keys(r) as K[]).map((k) => ({ value: k, label: typeof r[k] === 'string' ? (r[k] as string) : (r[k] as { label: string }).label }))

type Form = Record<string, string>
const str = (v: unknown) => (v == null ? '' : String(v))

export function VehicleForm({ fleet, vehicle, onClose }: { fleet: Fleet; vehicle: Vehicle | null; onClose: () => void }) {
  const save = useSaveVehicle()
  const [f, setF] = useState<Form>(() => ({
    reg_no: str(vehicle?.reg_no), vtype: vehicle?.vtype ?? 'car', make: str(vehicle?.make), model: str(vehicle?.model), year: str(vehicle?.year),
    color: str(vehicle?.color), fuel: vehicle?.fuel ?? 'octane', fuel2: str(vehicle?.fuel2), tank_l: str(vehicle?.tank_l), cng_m3: str(vehicle?.cng_m3),
    seats: str(vehicle?.seats), payload_kg: str(vehicle?.payload_kg), ownership: vehicle?.ownership ?? 'owned', branch_id: str(vehicle?.branch_id),
    department_id: str(vehicle?.department_id), chassis_no: str(vehicle?.chassis_no), engine_no: str(vehicle?.engine_no),
    purchase_date: str(vehicle?.purchase_date), purchase_cost: str(vehicle?.purchase_cost), odometer_km: str(vehicle?.odometer_km ?? 0),
    normal_km_per_unit: str(vehicle?.normal_km_per_unit), status: vehicle?.status ?? 'active', driver_id: str(vehicle?.driver?.id), notes: str(vehicle?.notes),
  }))
  const set = (k: string) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  const drivers = fleet.drivers.filter((d) => d.status !== 'inactive' && (!d.vehicle || d.vehicle.id === vehicle?.id))
  const chosen = fleet.drivers.find((d) => d.id === f.driver_id)
  const classProblem = chosen && !classCovers(chosen.licence_class, f.vtype as VehicleType)
    ? `${chosen.name}'s ${LICENCE_CLASS[chosen.licence_class].toLowerCase()} licence does not cover a ${VEHICLE_TYPE[f.vtype as VehicleType].toLowerCase()}.` : null

  return (
    <Modal open onClose={onClose} size="xl" title={vehicle ? `Edit ${vehicle.reg_no}` : 'Add vehicle'}>
      <form className="space-y-4" onSubmit={(e) => {
        e.preventDefault()
        save.mutate({ id: vehicle?.id ?? null, p: { ...f, reg_no: normRegNo(f.reg_no) } }, { onSuccess: onClose })
      }}>
        <div className="grid gap-3 sm:grid-cols-3">
          <Input label="Registration number *" value={f.reg_no} onChange={set('reg_no')} placeholder="DHAKA METRO-GA 12-3456" required className="sm:col-span-2" />
          <Select label="Type" value={f.vtype} onChange={set('vtype')} options={opts(VEHICLE_TYPE)} />
          <Input label="Make" value={f.make} onChange={set('make')} placeholder="Toyota" />
          <Input label="Model" value={f.model} onChange={set('model')} placeholder="Hiace" />
          <Input label="Year" type="number" value={f.year} onChange={set('year')} />
          <Select label="Fuel" value={f.fuel} onChange={set('fuel')} options={opts(FUEL)} />
          <Select label="Second fuel (dual fuel)" value={f.fuel2} onChange={set('fuel2')} placeholder="None"
            options={opts(FUEL).filter((o) => o.value !== 'electric' && o.value !== f.fuel)} />
          <Input label="Tank (litres)" type="number" step="0.1" value={f.tank_l} onChange={set('tank_l')} />
          {(f.fuel === 'cng' || f.fuel2 === 'cng') && <Input label="CNG cylinder (m³)" type="number" step="0.1" value={f.cng_m3} onChange={set('cng_m3')} />}
          <Input label="Seats" type="number" value={f.seats} onChange={set('seats')} />
          <Input label="Payload (kg)" type="number" value={f.payload_kg} onChange={set('payload_kg')} />
          <Select label="Ownership" value={f.ownership} onChange={set('ownership')} options={[{ value: 'owned', label: 'Owned' }, { value: 'leased', label: 'Leased' }, { value: 'rented', label: 'Rented' }]} />
          <Select label="Branch" value={f.branch_id} onChange={set('branch_id')} placeholder="—" options={fleet.branches.map((b) => ({ value: b.id, label: b.name }))} />
          <Select label="Department" value={f.department_id} onChange={set('department_id')} placeholder="—" options={fleet.departments.map((d) => ({ value: d.id, label: d.name }))} />
          <Select label="Default driver" value={f.driver_id} onChange={set('driver_id')} placeholder="None"
            options={drivers.map((d) => ({ value: d.id, label: `${d.name} (${LICENCE_CLASS[d.licence_class]})` }))} />
          <Input label="Odometer (km)" type="number" step="0.1" value={f.odometer_km} onChange={set('odometer_km')}
            hint={vehicle ? 'Can only go up' : undefined} />
          <Input label="Normal km per unit" type="number" step="0.01" value={f.normal_km_per_unit} onChange={set('normal_km_per_unit')}
            hint="Used to flag unusual fuel use" />
          {vehicle && <Select label="Status" value={f.status} onChange={set('status')} options={opts(VEHICLE_STATUS)} />}
          <Input label="Chassis no." value={f.chassis_no} onChange={set('chassis_no')} />
          <Input label="Engine no." value={f.engine_no} onChange={set('engine_no')} />
          <Input label="Purchase date" type="date" value={f.purchase_date} onChange={set('purchase_date')} />
          <Input label="Purchase cost (৳)" type="number" value={f.purchase_cost} onChange={set('purchase_cost')} />
        </div>
        <Textarea label="Notes" value={f.notes} onChange={set('notes')} />
        {classProblem && <Alert>{classProblem}</Alert>}
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={save.isPending} disabled={!!classProblem}>Save</Button>
        </div>
      </form>
    </Modal>
  )
}

export function DriverForm({ fleet, driver, onClose }: { fleet: Fleet; driver: Driver | null; onClose: () => void }) {
  const save = useSaveDriver()
  const [outside, setOutside] = useState(driver ? driver.outside : false)
  const [f, setF] = useState<Form>(() => ({
    employee_id: str(driver?.employee_id), name: driver?.outside ? driver.name : '', phone: driver?.outside ? str(driver.phone) : '', nid: '',
    licence_no: str(driver?.licence_no), licence_class: driver?.licence_class ?? 'light', licence_kind: driver?.licence_kind ?? 'professional',
    licence_expiry: str(driver?.licence_expiry), status: driver?.status ?? 'active', notes: str(driver?.notes),
  }))
  const set = (k: string) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value })
  return (
    <Modal open onClose={onClose} size="lg" title={driver ? `Edit ${driver.name}` : 'Add driver'}>
      <form className="space-y-4" onSubmit={(e) => {
        e.preventDefault()
        const p: Record<string, unknown> = { ...f }
        if (outside) delete p.employee_id
        else { delete p.name; delete p.phone; delete p.nid }
        if (!p.nid) delete p.nid
        save.mutate({ id: driver?.id ?? null, p }, { onSuccess: onClose })
      }}>
        {!driver && (
          <div className="flex gap-4 text-sm">
            <label className="inline-flex items-center gap-2"><input type="radio" checked={!outside} onChange={() => setOutside(false)} className="accent-primary-600" /> Employee</label>
            <label className="inline-flex items-center gap-2"><input type="radio" checked={outside} onChange={() => setOutside(true)} className="accent-primary-600" /> Outside / rented driver</label>
          </div>
        )}
        <div className="grid gap-3 sm:grid-cols-2">
          {!outside ? (
            driver ? <p className="text-sm text-slate-700 sm:col-span-2">Employee: <b>{driver.name}</b></p> : (
              <Select label="Employee" value={f.employee_id} onChange={set('employee_id')} placeholder="Choose…" required className="sm:col-span-2"
                options={fleet.employees.map((e) => ({ value: e.id, label: e.department ? `${e.name} · ${e.department}` : e.name }))} />
            )
          ) : (
            <>
              <Input label="Name *" value={f.name} onChange={set('name')} required />
              <Input label="Phone *" value={f.phone} onChange={set('phone')} placeholder="+8801…" required />
              <Input label="NID" value={f.nid} onChange={set('nid')} hint={driver?.nid ? `On file: ${driver.nid}` : '10, 13 or 17 digits'} />
            </>
          )}
          <Input label="Licence number *" value={f.licence_no} onChange={set('licence_no')} required />
          <Select label="Licence class" value={f.licence_class} onChange={set('licence_class')} options={opts(LICENCE_CLASS)} />
          <Select label="Licence kind" value={f.licence_kind} onChange={set('licence_kind')}
            options={[{ value: 'professional', label: 'Professional' }, { value: 'non_professional', label: 'Non-professional' }]} />
          <Input label="Licence expiry *" type="date" value={f.licence_expiry} onChange={set('licence_expiry')} required />
          {driver && <Select label="Status" value={f.status} onChange={set('status')}
            options={[{ value: 'active', label: 'Active' }, { value: 'off_duty', label: 'Off duty' }, { value: 'inactive', label: 'Inactive' }]} />}
        </div>
        <Textarea label="Notes" value={f.notes} onChange={set('notes')} />
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={save.isPending}>Save</Button>
        </div>
      </form>
    </Modal>
  )
}
