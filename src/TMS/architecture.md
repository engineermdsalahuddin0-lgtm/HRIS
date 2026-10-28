# Transport Management System (TMS): Architecture

Source: `docs/Part05Architecture.md` Module 17 (Fleet: vehicles, drivers; only its fields are used, not its REST
stack), widened with what international TMS / fleet products do and what Bangladeshi fleets need.
Decisions: user, 2026-10-28 (below). Other files: `features.md`, `schema.md`, `security.md`, `README.md`.

## 1. User decisions (2026-10-28)
1. **Location: the driver's phone now, a GPS device later.** Phase 1 records a GPS point at trip start, trip end and
   every fuel fill (with the odometer). Phase 2 adds a GPS tracker vendor (its server posts to us) and a live map.
2. **All three uses:** staff / official vehicles (requests, approval, pool cars, staff buses), goods delivery /
   logistics (cargo, customer, tolls, per-trip cost), field sales and service (motorcycles, daily routes).
3. **Drivers: HR employees and outside drivers** (contract / rented; kept in TMS with licence, NID, phone).
4. **First build: everything** — vehicles + documents + drivers, trips + fuel + location, maintenance + inventory,
   cost dashboard.
5. Vehicle papers live in the **DMS** (the "Transport & Vehicles" folder promised for TMS), linked to the vehicle,
   so expiry reminders, review and audit are the DMS's.

## 2. What international TMS products do, and what Bangladesh adds
| Area | Usual in fleet / TMS products | Bangladesh specifics we build in |
|---|---|---|
| Vehicles | Register, status, assignment, odometer | BRTA registration no. (e.g. *Dhaka Metro-GA 12-3456*), chassis / engine no., dual fuel (petrol + CNG) |
| Documents | Expiry tracking | BRTA registration, fitness, tax token, route permit, insurance; driving licence (professional / non-professional; light, medium, heavy, motorcycle) |
| Drivers | Profile, licence, assignment | Outside / rented drivers without an HR record; NID kept masked |
| Trips | Requests, dispatch, trip log | Requisition → approval → assign vehicle and driver (common practice); cargo and customer for deliveries |
| Location | Live GPS, geofences | Phase 1 phone points (no device cost); Phase 2 local GPS tracker vendors |
| Fuel | Fuel log, km per litre, fraud flags | Octane / petrol / diesel in litres, **CNG in m³**, LPG in litres; company price list; tank-overfill and odometer-rollback flags (fuel theft is a known problem) |
| Costs | Cost per km, total cost of ownership | Bridge / road tolls, traffic case fines, parking, driver allowance |
| Maintenance | Service plans by km / date, job cards | Outside workshops (most fleets), tyres and batteries as stock |
| Inventory | Spare parts stock | Store issue to a vehicle or a job card |

## 3. Layers and flows
```
UI /transport (tabs by permission) and the driver view (phone-first)
  │  RPC only (security definer, org-scoped)       storage: tms-files/{org}/... (receipts, photos)
  ▼
tms_* tables ──► DMS (vehicle and licence papers: dms_documents.vehicle_id / driver_id)
             ──► HR (employees, departments, branches; drivers may be employees)
             ──► notifications outbox (approvals, assignments, due services)
Phase 2: GPS vendor → Edge Function tms-gps (per-company secret) → tms_locations (source 'device')
```

**Trip flow:** request (anyone with `tms.request`) → approve (Manager of the department, or transport manager)
→ assign vehicle + driver (transport desk; clash check on time) → driver **Start** (odometer + GPS) → expenses and
fuel on the way → **End** (odometer + GPS) → distance and cost on the trip. Direct trips (no request) for deliveries
and field routes are created by the transport desk.

**Fuel flow:** driver or desk logs a fill (fuel, quantity, price, odometer, receipt photo, GPS) → the system checks
it (tank capacity, odometer going back, price far from the company price, km per unit far below the vehicle's
normal) → flagged fills wait for the transport manager to verify or dispute.

**Maintenance flow:** service plans per vehicle (every N km or N months) → due list → job card (workshop, labour,
parts issued from stock) → closing updates the plan's last-done km / date and the vehicle's status.

**Cost:** fuel + maintenance (labour + parts) + trip expenses per vehicle and period; ÷ distance = cost per km.

## 4. Fits the existing app
| Need | Reused |
|---|---|
| People, departments, branches | `employees`, `departments`, `branches`, `org_members` |
| Permissions | Roles & access (`tms.*`), `private.has_permission` |
| Vehicle / licence papers | DMS (new base folder "Transport & Vehicles", 6 types) + links |
| Audit | `attach_standard_triggers`, `private.write_audit` |
| Emails | `notifications` outbox + `recruit-notify` |
| Working days | `private.is_office_day` for due dates |

## 5. Build steps
| Step | Contents | Migration | Test |
|---|---|---|---|
| T1 | Permissions, settings, vehicles, drivers, DMS folder + links, Vehicles / Drivers tabs | `20261105000100_tms_t1_fleet.sql` | `tms_t1_fleet_test.sql` |
| T2 | Trip requests, approval, assignment with clash check, start / end with odometer + GPS, trip expenses, driver view | `20261105000200_tms_t2_trips.sql` | `tms_t2_trips_test.sql` |
| T3 | Fuel log, company fuel prices, efficiency, fraud flags, verification | `20261105000300_tms_t3_fuel.sql` | `tms_t3_fuel_test.sql` |
| T4 | Service plans, job cards, parts / tyres stock, issue to vehicle | `20261105000400_tms_t4_maintenance.sql` | `tms_t4_maintenance_test.sql` |
| T5 | Cost dashboard (per vehicle, per km, efficiency), owner overview | `20261105000500_tms_t5_costs.sql` | `tms_t5_costs_test.sql` |
| Later | GPS device webhook + live map, geofences, mobile app tracking, staff bus seats, conveyance bills, driver overtime to payroll | — | — |

Each step: migration → SQL test (PGlite) → UI → typecheck / unit tests / build → handbook + tracker → commit.
