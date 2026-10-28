# TMS: Database schema

**As built (2026-10-28): T1–T5 match this plan**, with these differences: no `tms.request` permission (anyone may
request); `tms_fuel_logs.status` has `flagged`; `tms_stock_moves` has a frozen-history trigger; GPS points only
from trip start / end and fuel fills; costs through `get_tms_costs` (`tms.view_costs`). RPCs: T1 `get_tms_fleet`,
`get_tms_vehicle`, `save_tms_vehicle`, `save_tms_driver`, `tms_link_document`, `my_tms_driver`,
`get_tms_overview`; T2 `get_tms_me`, `create_tms_trip`, `decide_tms_trip`, `tms_assign_options`,
`assign_tms_trip`, `cancel_tms_trip`, `start_tms_trip`, `end_tms_trip`, `add_tms_trip_expense`,
`list_tms_trips`, `get_tms_trip`; T3 `log_tms_fuel`, `review_tms_fuel`, `list_tms_fuel`, `tms_fuel_vehicles`,
`get_tms_settings`, `save_tms_settings`; T4 `save_tms_service_plan`, `open_tms_job_card`,
`close_tms_job_card`, `get_tms_maintenance`, `save_tms_part`, `tms_stock_move`, `get_tms_inventory`;
T5 `get_tms_costs`. Every access rule returns false, never NULL.

Conventions as everywhere (handbook A3): `org_id` on every row, `unique (org_id, id)`, composite FKs, closed RLS
(RPC only), standard meta columns and triggers (audit, no delete), statuses instead of deletes, SQLSTATE errors with
plain messages.

## T1 Fleet
| Table | Key columns |
|---|---|
| `tms_settings` | `org_id` PK, `enabled`, `fuel_prices` jsonb (`{"octane":…, "diesel":…, "cng":…}` per unit), `price_tolerance_pct` (10), `efficiency_tolerance_pct` (25) |
| `tms_vehicles` | `reg_no` (unique per org, normalised), `vtype` (car / microbus / pickup / covered_van / truck / bus / motorcycle / other), `make`, `model`, `year`, `color`, `fuel` (octane / petrol / diesel / cng / lpg / electric), `fuel2` (dual fuel), `tank_l`, `cng_m3`, `seats`, `payload_kg`, `ownership` (owned / leased / rented), `branch_id`, `department_id`, `chassis_no`, `engine_no`, `purchase_date`, `purchase_cost`, `odometer_km`, `normal_km_per_unit`, `status` (active / in_maintenance / off_road / disposed), `driver_id`, `notes` |
| `tms_drivers` | `employee_id` (or) `name` + `phone` + `nid` (outside driver), `user_id` (login for My trips), `licence_no`, `licence_class` (motorcycle / light / medium / heavy), `licence_kind` (professional / non_professional), `licence_expiry`, `status` (active / off_duty / inactive), `vehicle_id` |
| DMS | base folder `TRP` "Transport & Vehicles"; types `VRC`, `FIT`, `TTK`, `RPM`, `INS`, `DLC`; `dms_documents.vehicle_id`, `driver_id` |

## T2 Trips
| Table | Key columns |
|---|---|
| `tms_trips` | `kind` (staff / delivery / field), `requested_by`, `department_id`, `purpose`, `from_place`, `to_place`, `stops`, `planned_start`, `planned_end`, `passengers`, `cargo`, `customer`, `status` (requested / approved / rejected / assigned / in_progress / completed / cancelled), `approved_by/at`, `decision_note`, `vehicle_id`, `driver_id`, `start_odometer`, `end_odometer`, `started_at`, `ended_at`, `start_lat/lng`, `end_lat/lng` |
| `tms_trip_expenses` | `trip_id`, `kind` (toll / parking / fine / food / other), `amount`, `note`, `receipt_path` |
| `tms_locations` | `vehicle_id`, `driver_id`, `trip_id`, `source` (phone / device), `event` (trip_start / trip_end / fuel / point), `lat`, `lng`, `accuracy_m`, `recorded_at` |

## T3 Fuel
| Table | Key columns |
|---|---|
| `tms_fuel_logs` | `vehicle_id`, `driver_id`, `trip_id`, `fuel`, `quantity`, `unit` (l / m3 / kwh), `unit_price`, `amount`, `odometer_km`, `full_tank`, `station`, `paid_by` (company / driver_cash / card), `receipt_path`, `lat/lng`, `filled_at`, `km_per_unit`, `flags` text[], `status` (recorded / verified / disputed), `review_note` |

## T4 Maintenance and inventory
| Table | Key columns |
|---|---|
| `tms_service_plans` | `vehicle_id`, `name`, `every_km`, `every_months`, `last_km`, `last_date`, `active` |
| `tms_job_cards` | `vehicle_id`, `plan_id`, `kind` (service / repair / accident), `workshop`, `opened_at`, `closed_at`, `odometer_km`, `description`, `labour_cost`, `outside_parts_cost`, `status` (open / closed / cancelled) |
| `tms_parts` | `code`, `name`, `category` (part / tyre / lubricant / battery / other), `unit`, `on_hand`, `avg_cost`, `min_stock`, `active` |
| `tms_stock_moves` | `part_id`, `kind` (receive / issue / adjust), `qty`, `unit_cost`, `vehicle_id`, `job_card_id`, `supplier`, `ref`, `moved_at` (insert-only) |

## T5 Costs
No new tables: `get_tms_costs(from, to)` sums fuel, job cards (labour + parts issued + outside parts) and trip
expenses per vehicle; distance from odometer readings (trips and fuel fills) in the period.

## Storage
`tms-files/{org}/{kind}/{id}/{file}`: receipts and photos (JPG / PNG / PDF, 10 MB); read by the desk and the person
who uploaded; vehicle papers are DMS files, not here.
