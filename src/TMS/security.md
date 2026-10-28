# TMS: Security and privacy

| Risk | Control |
|---|---|
| Another company sees our fleet | `org_id` everywhere, composite FKs, closed RLS, RPCs filter by `private.current_org_id()`; storage paths start with the org |
| Drivers or staff see costs | Costs only through `get_tms_costs` (`tms.view_costs` / Admin); trip lists show cost only to the desk |
| Location as surveillance | GPS is recorded **only** at trip start / end and fuel fills in Phase 1, never in the background; the driver view says so; points are kept with the trip, readable by the desk and the driver |
| Outside driver NID exposed | NID returned masked (last 4) except to `tms.manage` |
| Fuel fraud | Odometer may never go back; quantity above tank capacity, price off the company list, low km per unit are flagged for verification; every change is audited |
| Trips assigned to unsafe drivers / vehicles | Assignment refuses an expired licence, a licence class too low for the vehicle, an off-road / in-maintenance vehicle, and time clashes |
| Self-approval | A requester cannot approve their own trip |
| Stock manipulation | Stock changes only through moves (insert-only history); stock may not go below zero; adjustments need a reason |
| Receipts with personal data | Private bucket, signed URLs, read by the desk and the uploader only |

Coding rules: the same as `src/DMS/security.md` §4–5 (security definer + empty search_path, permission first,
org-scoped load, explicit validation, audit, VOLATILE for writers, SQL test proves isolation and refusals).
