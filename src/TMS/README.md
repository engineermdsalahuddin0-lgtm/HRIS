# TMS (Transport Management System)

**Status (2026-10-28): T1–T5 built and tested locally, not applied.** Apply in order: the DMS fix
`20261104000700_dms_null_safe_access.sql`, then T1 → T5, each followed by its test. Route `/transport` (sidebar Operations →
Transport, shown to everyone: Trips for all, My trips for drivers, fleet tabs for `tms.*` holders). Anyone may request a vehicle (no `tms.request` permission). Read in this order: `architecture.md` (decisions,
flows, steps), `features.md` (permissions, tabs, features per step), `schema.md`, `security.md`.

## Step tracker
| Step | What | Migration | Test | State |
|---|---|---|---|---|
| T1 | Vehicles, drivers, papers in the DMS | `20261105000100_tms_t1_fleet.sql` | `tms_t1_fleet_test.sql` (5) | built, not applied |
| T2 | Trips, approval, assignment, start / end, GPS, expenses | `20261105000200_tms_t2_trips.sql` | `tms_t2_trips_test.sql` (4) | built, not applied |
| T3 | Fuel log, prices, efficiency, fraud flags | `20261105000300_tms_t3_fuel.sql` | `tms_t3_fuel_test.sql` (3) | built, not applied |
| T4 | Maintenance, job cards, parts / tyre stock | `20261105000400_tms_t4_maintenance.sql` | `tms_t4_maintenance_test.sql` (4) | built, not applied |
| T5 | Cost dashboard, owner overview | `20261105000500_tms_t5_costs.sql` | `tms_t5_costs_test.sql` (1) | built, not applied |

## Code layout (same shape as `src/DMS/`)
```
src/TMS/
  core/        types, pure helpers (units, BD reg no., efficiency, flags, due status)
  data/api.ts  React Query hooks over the RPCs
  components/  FleetForms (vehicle, driver), VehicleModal (papers via the DMS upload), TripsPanel (trips, assignment,
               My trips for drivers), FuelPanel (log, flags, prices), MaintenancePanel (plans, job cards, inventory), CostsPanel
  pages/TmsPage.tsx   /transport (tabs by permission)
  __tests__/
```
