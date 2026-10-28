// Pure TMS helpers: labels, Bangladeshi registration numbers, licence classes, fuel units.
import type { Fuel, LicenceClass, VehicleStatus, VehicleType } from './types'

export const VEHICLE_TYPE: Record<VehicleType, string> = {
  car: 'Car', microbus: 'Microbus', pickup: 'Pickup', covered_van: 'Covered van', truck: 'Truck', bus: 'Bus',
  motorcycle: 'Motorcycle', other: 'Other',
}

export const FUEL: Record<Fuel, { label: string; unit: 'l' | 'm3' | 'kwh' }> = {
  octane: { label: 'Octane', unit: 'l' },
  petrol: { label: 'Petrol', unit: 'l' },
  diesel: { label: 'Diesel', unit: 'l' },
  cng: { label: 'CNG', unit: 'm3' },
  lpg: { label: 'LPG', unit: 'l' },
  electric: { label: 'Electric', unit: 'kwh' },
}

export const UNIT_LABEL = { l: 'litre', m3: 'm³', kwh: 'kWh' } as const

export const LICENCE_CLASS: Record<LicenceClass, string> = { motorcycle: 'Motorcycle', light: 'Light', medium: 'Medium', heavy: 'Heavy' }

export const VEHICLE_STATUS: Record<VehicleStatus, { label: string; tone: 'green' | 'orange' | 'red' | 'slate' }> = {
  active: { label: 'Active', tone: 'green' },
  in_maintenance: { label: 'In maintenance', tone: 'orange' },
  off_road: { label: 'Off road', tone: 'red' },
  disposed: { label: 'Disposed', tone: 'slate' },
}

/** "dhaka metro-ga   12-3456" → "DHAKA METRO-GA 12-3456" (same rule as the database). */
export const normRegNo = (s: string) => s.trim().replace(/\s+/g, ' ').toUpperCase()

/** The licence class a vehicle type needs (same rule as the database). */
export function classNeeded(t: VehicleType): LicenceClass {
  if (t === 'motorcycle') return 'motorcycle'
  if (t === 'covered_van') return 'medium'
  if (t === 'truck' || t === 'bus') return 'heavy'
  return 'light'
}

/** Heavy covers medium and light; medium covers light; motorcycle only itself. */
export function classCovers(have: LicenceClass, t: VehicleType): boolean {
  const need = classNeeded(t)
  if (need === 'motorcycle') return have === 'motorcycle'
  const rank = { motorcycle: -1, light: 0, medium: 1, heavy: 2 }
  return rank[have] >= rank[need]
}

export const formatKm = (km: number | null | undefined) => (km == null ? '—' : `${Math.round(km).toLocaleString('en-IN')} km`)
export const formatTaka = (n: number | null | undefined) =>
  n == null ? '—' : `৳ ${Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`
