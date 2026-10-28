# TMS: Features and permissions

## Permissions (Roles & access, module `tms`)
| Key | Default roles | Meaning |
|---|---|---|
| `tms.manage` | HR Manager (Admin implicit) | Transport desk: vehicles, drivers, assignments, direct trips, fuel verification, maintenance, setup |
| `tms.request` | every role | Ask for a vehicle |
| `tms.approve` | Manager | Approve vehicle requests of their own department (`tms.manage` approves all) |
| `tms.inventory` | HR Manager | Spare parts and tyre stock: receive, issue, adjust |
| `tms.view_costs` | nobody (Admin implicit) | Cost dashboard: cost per vehicle and per km, fuel spend |

**Drivers need no permission:** a driver record linked to a login sees "My trips" (start / end, fuel, expenses).
Outside drivers without a login are handled by the desk.

## Tabs (`/transport`)
| Tab | Who | Contents |
|---|---|---|
| Overview | any `tms.*`, drivers | Vehicles by status, on trip now (last point), requests waiting, documents expiring, services due, flagged fuel |
| Vehicles | `tms.manage` (read: approvers) | Register, odometer, status, assigned driver, papers from the DMS with expiry, service plans |
| Drivers | `tms.manage` | Employee or outside driver, licence (class, type, expiry), status, assigned vehicle, licence copy in the DMS |
| Trips | requesters see theirs; approvers their department; desk all | Request, approve / reject, assign vehicle + driver (clash check), trip log, expenses, distance |
| My trips | drivers | Today's and upcoming trips, Start / End with odometer and GPS, add fuel and expenses |
| Fuel | `tms.manage` | Fuel log, km per unit, flags (over tank, odometer back, price off, low efficiency), verify / dispute |
| Maintenance | `tms.manage` | Service plans (km / months), due list, job cards (workshop, labour, parts) |
| Inventory | `tms.inventory` | Parts and tyres: stock, receive, issue to vehicle / job card, low-stock list |
| Costs | `tms.view_costs` | Per vehicle and period: fuel, maintenance, trip expenses, distance, cost per km, km per unit; CSV |
| Setup | `tms.manage` | Fuel prices, fraud tolerance, vehicle types in use |

## Feature list by step
**T1 Fleet** — vehicle register (BRTA no., type, make / model / year, fuel incl. dual fuel, tank and CNG capacity,
seats, payload, ownership owned / leased / rented, branch, department, chassis / engine no., purchase date and
cost, odometer, status active / in maintenance / off road / disposed); drivers (employee or outside, licence no.,
class, professional / non-professional, expiry, phone, NID masked, status, default vehicle); DMS base folder
"Transport & Vehicles" with Registration Certificate, Fitness Certificate, Tax Token, Route Permit, Insurance,
Driving Licence (all with expiry; tax token and route permit default to 30 June); documents linked to the vehicle or
driver; next expiry per vehicle; no hard delete.

**T2 Trips** — kinds staff / delivery / field; request with purpose, places, time, passengers or cargo, customer;
approval by department manager; assignment with clash check (vehicle and driver busy, vehicle off road, licence
expired, licence class too low for the vehicle); start / end with odometer (never below the last reading) and GPS;
trip expenses (toll, parking, fine, food, other) with receipt; distance; cancel with reason; emails to the requester
and the driver.

**T3 Fuel** — log a fill (fuel, quantity, unit price, amount, odometer, full tank, station, paid by, receipt, GPS);
units: litres (octane, petrol, diesel, LPG), m³ (CNG), kWh (electric); company price list; km per unit between full
fills; flags: over tank, odometer back, price off by more than the tolerance, efficiency below the vehicle's normal;
verify / dispute by the desk.

**T4 Maintenance & inventory** — service plans per vehicle (every N km and / or N months) with due status; job cards
(service, repair, accident; workshop; labour; parts from stock or bought outside); closing a card updates the plan
and returns the vehicle to active; parts and tyres with stock, average cost, minimum level; receive, issue, adjust
moves (history kept).

**T5 Costs** — per vehicle and period: distance, fuel quantity and cost, km per unit, maintenance cost, trip
expenses, total, cost per km; fleet totals; CSV; owner overview (on trip now, idle, off road, expiring papers).

## Later (Phase 2)
GPS device integration and live map, geofence alerts, continuous tracking in the mobile app, staff bus routes and
seat booking, conveyance bills (Part 5 Module 18), driver overtime from trips into payroll, tyre serial tracking,
fuel card statement import.
