# TMS (Transport Management System)

**Status (2026-10-28): architecture written; building T1–T5.** Read in this order: `architecture.md` (decisions,
flows, steps), `features.md` (permissions, tabs, features per step), `schema.md`, `security.md`.

## Step tracker
| Step | What | Migration | Test | State |
|---|---|---|---|---|
| T1 | Vehicles, drivers, papers in the DMS | `20261105000100_tms_t1_fleet.sql` | `tms_t1_fleet_test.sql` | building |
| T2 | Trips, approval, assignment, start / end, GPS, expenses | `20261105000200_tms_t2_trips.sql` | `tms_t2_trips_test.sql` | planned |
| T3 | Fuel log, prices, efficiency, fraud flags | `20261105000300_tms_t3_fuel.sql` | `tms_t3_fuel_test.sql` | planned |
| T4 | Maintenance, job cards, parts / tyre stock | `20261105000400_tms_t4_maintenance.sql` | `tms_t4_maintenance_test.sql` | planned |
| T5 | Cost dashboard, owner overview | `20261105000500_tms_t5_costs.sql` | `tms_t5_costs_test.sql` | planned |

## Code layout (same shape as `src/DMS/`)
```
src/TMS/
  core/        types, pure helpers (units, BD reg no., efficiency, flags, due status)
  data/api.ts  React Query hooks over the RPCs
  components/  one panel per tab, forms, the driver view
  pages/TmsPage.tsx   /transport (tabs by permission)
  __tests__/
```
