// Shapes returned by the TMS RPCs (supabase/migrations/20261105000*_tms_*.sql).

export type VehicleType = 'car' | 'microbus' | 'pickup' | 'covered_van' | 'truck' | 'bus' | 'motorcycle' | 'other'
export type Fuel = 'octane' | 'petrol' | 'diesel' | 'cng' | 'lpg' | 'electric'
export type LicenceClass = 'motorcycle' | 'light' | 'medium' | 'heavy'
export type VehicleStatus = 'active' | 'in_maintenance' | 'off_road' | 'disposed'
export type ExpiryStatus = 'expired' | 'due' | 'active'

export interface Paper {
  document_id: string; doc_code: string; title: string; type_code: string; type_name: string
  expiry_date: string | null; expiry_status: ExpiryStatus | null; days_left: number | null; lifecycle: string
}

export interface Vehicle {
  id: string
  reg_no: string
  vtype: VehicleType
  make: string | null
  model: string | null
  year: number | null
  color: string | null
  fuel: Fuel
  fuel2: Fuel | null
  tank_l: number | null
  cng_m3: number | null
  seats: number | null
  payload_kg: number | null
  ownership: 'owned' | 'leased' | 'rented'
  branch_id: string | null
  branch: string | null
  department_id: string | null
  department: string | null
  chassis_no: string | null
  engine_no: string | null
  purchase_date: string | null
  purchase_cost: number | null
  odometer_km: number
  normal_km_per_unit: number | null
  status: VehicleStatus
  notes: string | null
  class_needed: LicenceClass
  driver: { id: string; name: string } | null
  next_expiry: string | null
  papers_count: number
}

export interface VehicleDetail extends Vehicle { papers: Paper[]; driver_papers: Paper[] }

export interface Driver {
  id: string
  employee_id: string | null
  name: string
  outside: boolean
  phone: string | null
  nid: string | null
  has_login: boolean
  licence_no: string
  licence_class: LicenceClass
  licence_kind: 'professional' | 'non_professional'
  licence_expiry: string
  licence_status: ExpiryStatus
  licence_days_left: number
  status: 'active' | 'off_duty' | 'inactive'
  notes: string | null
  vehicle: { id: string; reg_no: string } | null
  department: string | null
}

export interface Fleet {
  can: { manage: boolean; approve: boolean; inventory: boolean; view_costs: boolean }
  vehicles: Vehicle[]
  drivers: Driver[]
  branches: { id: string; name: string }[]
  departments: { id: string; name: string }[]
  employees: { id: string; name: string; department: string | null }[]
}

export interface ExpiringItem {
  kind: 'paper' | 'licence'
  what: string
  doc_code?: string
  document_id?: string
  vehicle?: string | null
  driver?: string | null
  driver_id?: string
  expiry_date: string
  days_left: number
  expiry_status: ExpiryStatus
}

export interface TmsOverview {
  vehicles: { total: number; active: number; in_maintenance: number; off_road: number }
  drivers: { active: number; licence_expired: number }
  expiring: ExpiringItem[]
}
