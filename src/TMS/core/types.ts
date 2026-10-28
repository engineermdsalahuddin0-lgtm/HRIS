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

export type TripStatus = 'requested' | 'approved' | 'rejected' | 'assigned' | 'in_progress' | 'completed' | 'cancelled'
export type TripKind = 'staff' | 'delivery' | 'field'

export interface Trip {
  id: string
  kind: TripKind
  status: TripStatus
  purpose: string
  from_place: string
  to_place: string
  stops: string | null
  planned_start: string
  planned_end: string
  passengers: number | null
  cargo: string | null
  customer: string | null
  decision_note: string | null
  decided_at: string | null
  requested_by: string | null
  requested_by_me: boolean
  decided_by: string | null
  department_id: string | null
  department: string | null
  vehicle: { id: string; reg_no: string; vtype: VehicleType } | null
  driver: { id: string; name: string; phone: string | null } | null
  i_drive: boolean
  can_approve: boolean
  start_odometer: number | null
  end_odometer: number | null
  distance_km: number | null
  started_at: string | null
  ended_at: string | null
  start_point: { lat: number; lng: number } | null
  end_point: { lat: number; lng: number } | null
  expenses_total: number
  created_at: string
}

export interface TripDetail extends Trip {
  expenses: { id: string; kind: string; amount: number; note: string | null; receipt_path: string | null; created_at: string; by: string | null }[]
  points: { event: string; lat: number; lng: number; accuracy_m: number | null; at: string }[]
}

export interface AssignOptions {
  vehicles: { id: string; reg_no: string; vtype: VehicleType; seats: number | null; default_driver_id: string | null; problems: string[] }[]
  drivers: { id: string; name: string; licence_class: LicenceClass; problems: string[] }[]
}

export interface TmsMe {
  can: { manage: boolean; approve: boolean; inventory: boolean; view_costs: boolean; see_fleet: boolean }
  driver: Driver | null
  to_approve: number
  to_assign: number
  my_open_trips: number
}

export type FuelFlag = 'over_tank' | 'odometer_back' | 'price_off' | 'low_efficiency'

export interface FuelLog {
  id: string; vehicle_id: string; reg_no: string; driver: string | null; trip_id: string | null
  fuel: Fuel; unit: 'l' | 'm3' | 'kwh'; quantity: number; unit_price: number; amount: number; odometer_km: number
  full_tank: boolean; station: string | null; paid_by: 'company' | 'driver_cash' | 'card'; receipt_path: string | null
  point: { lat: number; lng: number } | null; filled_at: string; km_per_unit: number | null; flags: FuelFlag[]
  status: 'recorded' | 'flagged' | 'verified' | 'disputed'; review_note: string | null; reviewed_by: string | null
  reviewed_at: string | null; logged_by: string | null
}

export interface FuelVehicle {
  id: string; reg_no: string; fuel: Fuel; fuel2: Fuel | null; odometer_km: number; tank_l: number | null; cng_m3: number | null
  price: Partial<Record<Fuel, number>> | null; trip_id: string | null
}

export interface TmsSettings { fuel_prices: Partial<Record<Fuel, number>>; price_tolerance_pct: number; efficiency_tolerance_pct: number }

export interface ServicePlan {
  id: string; vehicle_id: string; reg_no: string; name: string; every_km: number | null; every_months: number | null
  last_km: number | null; last_date: string | null; active: boolean; odometer_km: number; next_km: number | null
  next_date: string | null; km_left: number | null; status: 'overdue' | 'due_soon' | 'ok'
}

export interface JobCard {
  id: string; vehicle_id: string; reg_no: string; plan_id: string | null; plan: string | null; kind: 'service' | 'repair' | 'accident'
  workshop: string | null; description: string; odometer_km: number | null; opened_at: string; closed_at: string | null
  labour_cost: number; outside_parts_cost: number; stock_parts_cost: number; total_cost: number
  parts: { part: string; code: string; qty: number; unit: string; unit_cost: number }[]
  status: 'open' | 'closed' | 'cancelled'; close_note: string | null; opened_by: string | null
}

export interface Maintenance { plans: ServicePlan[]; open: JobCard[]; closed: JobCard[] }

export interface Part {
  id: string; code: string; name: string; category: 'part' | 'tyre' | 'lubricant' | 'battery' | 'other'; unit: string
  on_hand: number; avg_cost: number; min_stock: number; active: boolean; value: number; low: boolean
}

export interface Inventory {
  parts: Part[]
  moves: { id: string; part: string; code: string; kind: 'receive' | 'issue' | 'adjust'; qty: number; unit: string; unit_cost: number
           reg_no: string | null; job_card_id: string | null; supplier: string | null; ref: string | null; note: string | null; moved_at: string; by: string | null }[]
  can_manage_stock: boolean
}

export interface VehicleCost {
  id: string; reg_no: string; vtype: VehicleType; status: VehicleStatus; distance_km: number; fuel_cost: number
  fuel_qty: Partial<Record<'l' | 'm3' | 'kwh', number>>; km_per_unit: number | null; repair_cost: number; trip_cost: number
  total_cost: number; trips: number; flagged_fills: number; cost_per_km: number | null
}

export interface Costs {
  from: string; to: string
  vehicles: VehicleCost[]
  totals: { distance_km: number; fuel_cost: number; repair_cost: number; trip_cost: number; total_cost: number; trips: number; cost_per_km: number | null }
  live: { trip_id: string; reg_no: string; driver: string; from_place: string; to_place: string; started_at: string
          last_point: { lat: number; lng: number; at: string; event: string } | null }[]
}

export interface TmsOverview {
  vehicles: { total: number; active: number; in_maintenance: number; off_road: number }
  drivers: { active: number; licence_expired: number }
  expiring: ExpiringItem[]
}
