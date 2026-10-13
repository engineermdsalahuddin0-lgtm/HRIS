# AIHR BD — Part 2 Architecture

*Time and Attendance: Shifts · Attendance · Leave · Overtime · Geofence · Devices — Version 1.0 — October 2026 — builds on Part 1*

## 0. How to use this document

Give Claude this document, the Part 1 architecture document, and **one build step at a time** (Section 8). Part 2 starts only after Part 1 passes its acceptance tests and is tagged. Development and testing run on a **local Supabase** with **fake seed data** and a **device simulator**. Real hardware is touched only in the last step. Items marked as assumptions are listed in Section 9.

## 1. Scope and final decisions

**In Part 2:** shifts, roster, shift swaps, holidays, leave (types, balances, requests, approval), attendance records and daily engine, reconciliation, manual/web/QR/geofence check-in, overtime, breaks, biometric device integration, live tracking.

**Not in Part 2:** salary, payroll runs, tax, provident fund, performance, training, recruitment, onboarding, offboarding. Payroll (Part 3) will read from Part 2.

| Topic | Decision |
| --- | --- |
| Foundation | Reuse Part 1: org\_id on every table, UUID keys, roles and permissions, soft delete, audit log, row-level security. |
| Where attendance happens | An employee may punch at any branch or office of their own organization. Each record stores the office where the punch happened. The employee's home office is separate. |
| Device identity | A device belongs to one office and one organization. A device PIN is resolved only inside that organization. The PIN is mapped to the employee through its own mapping table, not through the card ID. |
| Card ID | Still for ID cards and display only. Never the only key for a security decision. |
| Raw data | Every punch from every source is stored first and never edited. Attendance records are derived from it. |
| Time | Stored in UTC, shown in Asia/Dhaka. A night shift belongs to the date it starts. |
| Biometric data | Only punch events are stored. Fingerprint or face templates never enter our database. |
| Geofence | Outside the radius is flagged, not blocked. |
| Approvals | Leave, overtime, swaps and attendance fixes follow the reporting chain from Part 1. Nobody approves their own request. |
| Payroll lock | After a payroll period is closed (Part 3), its attendance, leave and overtime become read-only. The lock flag is built now. |

## 2. Backend

### 2.1 Principles

- Same stack and rules as Part 1. Every table: UUID key, org\_id, created\_at, updated\_at, created\_by, updated\_by, soft delete or status.
- Raw punches are immutable. Derived rows can be rebuilt from raw punches at any time.
- Every job and every device endpoint is idempotent: running or receiving the same data twice changes nothing.
- All adjustments (manual punch, leave override, overtime edit) write an audit row.

### 2.2 Tables

**Time configuration**

| Table | Key columns | Notes |
| --- | --- | --- |
| shifts | id, org\_id, name, code, start\_time, end\_time, crosses\_midnight, break\_minutes, check-in earliest / grace / latest (minutes), check-out earliest / early-out grace / latest (minutes), auto\_checkout, half\_day\_threshold\_minutes, status | Covers day and night shifts. |
| shift\_rosters | id, org\_id, employee\_id, shift\_id, date\_from, date\_to | One active shift per employee per date, no overlap allowed. |
| shift\_swaps | id, org\_id, requester\_employee\_id, target\_employee\_id, work\_date, both shift ids, status (pending, peer accepted, approved, rejected, cancelled), approved\_by | A swap changes the roster only after final approval. |
| holidays | id, org\_id, name, date, type (public, company, optional), branch scope (empty means all), status | Seeded with Bangladesh public holidays. Variable-date ones are entered each year. |
| org\_work\_settings | org\_id, weekly off days, default working hours, time zone | Used when an employee has no shift. |

**Attendance**

| Table | Key columns | Notes |
| --- | --- | --- |
| biometric\_raw\_logs | id, org\_id, device\_id, device\_pin, verify\_time, in\_out\_mode, verify\_mode, raw\_payload, processing\_status (processed, unmapped, duplicate, error), employee\_id (empty if unmapped) | Immutable. Unknown PINs are kept as unmapped, never dropped. |
| attendance\_devices | id, org\_id, office\_id, name, brand, protocol, serial\_number, host, port, secret (stored hashed), last\_seen\_at, clock\_offset, status | Brands from the spec: ZKTeco, Hikvision, Dahua, Tipsoi. |
| employee\_device\_pins | id, org\_id, employee\_id, device\_pin, status | PIN unique inside the organization. Keep it 9 digits or fewer because some device models limit the length. |
| attendance\_records | id, org\_id, employee\_id, work\_date, shift\_id, office\_id (where punched), check\_in\_at, check\_out\_at, source\_in, source\_out (biometric, qr, gps, manual, web), status, is\_late, late\_minutes, early\_out\_minutes, worked\_minutes, outside\_geofence, note, adjusted\_by, adjusted\_at, locked | One row per employee per date. Statuses: present, late, absent, half\_day, early\_out, on\_leave, weekend, holiday. |
| geofences | id, org\_id, branch\_id (optional), office\_id (optional), name, latitude, longitude, radius\_meters, status |  |
| qr\_checkin\_codes | id, org\_id, office\_id, code (stored hashed), valid\_from, valid\_until, status | Short-lived rotating codes. |
| location\_pings | id, org\_id, employee\_id, latitude, longitude, accuracy\_meters, battery, recorded\_at | Live Tracking only. Auto-deleted after the retention period. |
| break\_records | id, org\_id, employee\_id, attendance\_record\_id, break\_start, break\_end, type |  |

**Overtime**

| Table | Key columns | Notes |
| --- | --- | --- |
| overtime\_policy | org\_id, weekday / weekend / holiday multiplier, minimum minutes, daily and monthly caps, auto\_capture, requires\_approval, rounding | Spec defaults are 2.0, 2.0 and 3.0 and must be confirmed against labour law and company policy. |
| overtime\_records | id, org\_id, employee\_id, work\_date, minutes, day\_type, multiplier, status (pending, approved, rejected), source (auto, manual), approved\_by, locked |  |

**Leave**

| Table | Key columns | Notes |
| --- | --- | --- |
| leave\_types | id, org\_id, name, code, days\_per\_year, paid, carry\_forward and cap, accrual (yearly or monthly), allows\_half\_day, document\_required, status | Fully configurable per organization. |
| leave\_balances | id, org\_id, employee\_id, leave\_type\_id, year, entitled, used, pending, carried\_forward |  |
| leave\_requests | id, org\_id, employee\_id, leave\_type\_id, from\_date, to\_date, half\_day, days, reason, status, approver\_id, decided\_at, decision\_note |  |

### 2.3 Attendance engine rules

1. Every punch from any source becomes a normalized punch with employee, time, office, source.
2. The punch is assigned to a work date through the employee's shift. A night shift belongs to its start date.
3. The first valid punch inside the check-in window is the check-in. The last valid punch inside the check-out window is the check-out. Other punches stay in raw data.
4. Late means after the grace period. Absent means no valid punch by the cut-off. Early out means leaving before the early-out grace. Half day means worked time below the half-day threshold.
5. Approved leave sets on\_leave. A holiday or weekly off sets holiday or weekend. A punch on those days is overtime eligible.
6. A daily closing job creates absent rows, applies auto-checkout, and refreshes derived rows. It can be re-run safely.
7. A manual fix needs the permission, a reason, and writes audit. It sets the source to manual. It is refused on locked rows.
8. Overtime is calculated from worked time beyond the shift end (and from the full worked time on weekends and holidays), using the overtime policy and the day type.

### 2.4 Devices

- Devices **push** punches to a server endpoint over HTTP. The spec's ZKTeco ADMS push is the main path. Direct TCP pull from a cloud function is not planned and must be verified in Step 2D.
- Each device has its own secret. Requests without a valid serial and secret are rejected. The endpoint is rate limited.
- A push is stored in raw logs first, then processed. Duplicates are marked duplicate. Unknown PINs are marked unmapped and shown to HR for mapping.
- Devices can send old punches after being offline. The engine must handle late arrival of old punches and rebuild that day.
- Device clocks drift. The device stores a clock offset that is applied during processing.
- A **device simulator** sends test punches in the same format, including duplicates, unknown PINs, late batches and night shifts.

### 2.5 Geofence, QR and live tracking

- GPS check-in compares the position and accuracy against active geofences of the employee's organization. Outside the radius, or poor accuracy, sets outside\_geofence and flags the record for review.
- QR check-in uses a short-lived code shown at the office. The code rotates so a photo of it is useless later.
- Live Tracking sends pings only during an active shift and only for employees covered by the policy. Pings are deleted after the retention period.

### 2.6 Leave rules

- The balance is checked at request time. Pending requests reserve days.
- Approval goes to the Reporting Manager from the reporting chain, or to HR if none exists.
- An approved leave sets attendance to on\_leave for those dates and reduces the balance. A cancelled leave restores both.
- Weekly offs and holidays inside a leave range are not counted unless the leave type says so.
- Year start and monthly accrual run as a scheduled job.

### 2.7 Row-level security and permissions

All Part 1 isolation rules apply: nothing crosses organizations. New permissions in the catalog:

- attendance.view\_own, attendance.view\_team, attendance.view\_all, attendance.adjust
- shifts.manage, roster.manage, holidays.manage, swaps.approve
- leave.request, leave.approve, leave.manage\_types, leave.view\_all
- overtime.view, overtime.approve, overtime.manage\_policy
- devices.manage, geofences.manage, tracking.view

An Employee sees and requests only for themselves. A Manager sees the team on their reporting chain (assumption). HR Manager and Admin see the whole company if the role has the permission. Device endpoints use the device secret, never a user login.

### 2.8 Server operations and jobs

1. Process a device push or a manual, web, QR or GPS punch into raw data and the engine.
2. Daily close job and auto-checkout job.
3. Leave accrual job and year-start rollover.
4. Create, approve and reject leave, overtime and swaps.
5. Rebuild a day or a date range for one employee or everyone.
6. Map an unmapped PIN to an employee and reprocess the held punches.
7. Purge location pings after the retention period.
8. Lock and unlock a period (called by Part 3).

## 3. UI

Same style as Part 1. Every page has loading, empty and error states and hides actions the role cannot use.

| Area | Screens |
| --- | --- |
| Attendance | Date picker, KPI tiles (Present, Late, Absent, On Leave), table with employee, department, check-in, check-out, duration, source icon, status badge, actions (manual punch, fix, note). Monthly calendar view with color legend. |
| Reconciliation | List of days needing attention: missing check-out, outside geofence, unmapped PIN, device errors. Fix with reason. |
| My Attendance | Employee's own check-in or out (web, QR scan, GPS), today's status, history. |
| Shifts | Shift list and form with check-in and check-out rules sections. |
| Roster | Assign shifts to employees by date range, calendar or table view. Overlap warning. |
| Shift swaps | Request, peer accept, manager approve. |
| Holidays | Yearly list, add, edit, branch scope. |
| Leave | Leave types settings, my balances, request form, approval inbox, team calendar. |
| Overtime | Policy settings, list of records, approve or reject, filters by month. |
| Breaks | Break records per day. |
| Devices | Device list with last seen, status, PIN mapping, unmapped punch inbox. |
| Geofences | List and form with a map showing the radius circle, use my location button. |
| QR codes | Display screen for an office with the rotating code. |
| Live Tracking | Map and list of active employees. Visible only with the tracking permission. |

## 4. Policies

- **Isolation:** no attendance, leave or device data crosses organizations.
- **Raw data is evidence:** raw punches are never edited or deleted by users. Corrections are new records with a reason.
- **No self-approval:** a person cannot approve their own leave, overtime, swap or attendance fix.
- **Location privacy:** employees are told that location is used for check-in and tracking. Tracking runs only during shifts, only for covered employees, and only roles with the tracking permission can see it. Pings are deleted after the retention period.
- **Biometric data:** the system never stores fingerprint or face templates, only punch events.
- **Payroll lock:** locked attendance, leave and overtime cannot be changed.
- **Device security:** per-device secret, rate limiting, unknown devices rejected and logged.
- **Retention:** raw punches and audit rows are kept at least 3 years. Location pings follow the shorter tracking retention.
- **Audit:** manual punches, fixes, leave and overtime decisions, device changes, mapping changes and period locks all write audit rows.
- **Statutory values** (overtime multipliers, leave entitlements, holiday list) are configurable seeds. Confirm them with the labour law and company policy before real use.

## 5. Total feature list for Part 2

**Backend**

- Shifts including night shifts, rosters, shift swaps, holidays, work settings
- Raw punch intake from web, QR, GPS, manual and devices
- Attendance engine and daily close job with auto-checkout
- Reconciliation and manual adjustment with audit
- Leave types, balances, requests, approval, accrual job
- Overtime policy and automatic or manual overtime records
- Break records
- Device registry, secret-based push endpoint, PIN mapping, unmapped inbox
- Geofences, rotating QR codes, location pings with retention purge
- Period lock flag for payroll

**UI**

- Attendance page, calendar view, reconciliation
- My Attendance check-in screen
- Shifts, roster, swaps, holidays
- Leave types, balances, request and approval screens
- Overtime and breaks screens
- Devices, geofences, QR display, Live Tracking

**Policy**

- Every rule in Section 4 enforced and tested

## 6. Test data and acceptance tests

**Seed data (fake, local only):** two companies, branches and offices from Part 1, 50 to 100 employees, a day shift, a night shift and a rotating roster, Bangladesh holidays, leave types with balances, and 30 to 90 days of attendance with late, absent, weekend, half-day and overtime cases. A device simulator sends punches.

1. Company A can never see Company B's attendance, leave, devices or tracking data.
2. Each role sees only what its permissions allow. An Employee sees only their own records.
3. A day shift employee punching late becomes late; punching after the cut-off becomes absent; leaving early becomes early\_out.
4. A night shift punch after midnight is counted on the shift's start date.
5. Two punches from different offices of the same company are both accepted and the office is recorded.
6. A duplicate device push creates no second record.
7. An unknown PIN lands in the unmapped inbox; mapping it reprocesses the held punches.
8. A late-arriving old batch of device punches rebuilds the correct day.
9. A GPS punch outside the radius is flagged, not blocked. A reused or expired QR code is rejected.
10. Leave request reserves balance, manager approval changes attendance to on\_leave, cancellation restores both.
11. Leave approval is refused when the requester is the approver.
12. Overtime is calculated correctly for weekday, weekend and holiday.
13. A manual fix needs a reason, shows in the audit log, and is refused on a locked period.
14. Raw punches cannot be edited or deleted by any user.
15. Location pings older than the retention period are purged, and a user without the tracking permission sees nothing.
16. The daily close job run twice produces the same result.

## 7. What done means

All Section 6 tests pass on local Supabase with seed data, the real-device check in Step 2D is complete or explicitly deferred, the feature list in Section 5 is complete, and the work is committed and tagged as the Part 2 release.

## 8. Build order inside Part 2

Each step: build, test by hand with seed data, commit, then continue.

- **2A, rules and configuration:** shifts, org work settings, holidays, leave types, overtime policy, roster. No hardware needed.
- **2B, attendance core:** raw punch intake, attendance engine, manual and web punch, QR, geofence, daily close job, reconciliation, attendance and My Attendance screens.
- **2C, requests:** leave balances, requests and approvals, overtime records and approval, breaks, shift swaps.
- **2D, devices and tracking:** device simulator first, then the device registry, push endpoint, PIN mapping and unmapped inbox, then one real device model, then Live Tracking.

## 9. Assumptions to confirm

1. Approvals follow the Reporting Manager; HR approves when none exists.
2. A Manager sees the team on their reporting chain, not the whole company, unless the role is given that permission.
3. A night shift belongs to its start date.
4. ZKTeco and similar devices push over HTTP (ADMS). Direct TCP pull is not planned.
5. Location pings are kept 90 days, and tracking runs only during shifts.
6. Overtime multipliers start from the spec defaults and are confirmed against labour law.
7. Leave types and the holiday list are seed examples that HR confirms.
8. A geofence violation is a flag for review, not a block.
9. QR codes rotate every few minutes.
10. Half-day threshold is configurable per shift.
11. A device PIN is 9 digits or fewer and is mapped separately from the card ID.
12. Only punch events are stored from devices, never biometric templates.
