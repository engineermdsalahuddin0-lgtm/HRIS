# Olympus HRIS — Project memory

Running log of **what was done and why**. Read this first when resuming work.
Architecture source: [docs/Part01Architecture.md](docs/Part01Architecture.md) (titled "AIHR BD"; project name is **Olympus HRIS**).

## Stack (decided)
- Frontend: **Vite + React + TypeScript**, Tailwind v4 (orange primary), React Router, React Query (server data),
  Zustand (session/org state), react-hook-form + zod, **lucide-react** icons, **recharts** charts.
- Backend: **Supabase** (Postgres, Auth). The doc says Next.js; we are **not** using Next.js (user chose Vite).
  - All server logic = **Postgres functions (RPC)**, `security definer`, in `public` (callable API) or `private` (internal).
  - **No Edge Functions and no service-role key** are used at all (see Step 7 decision). Service key never in `.env`.
- Supabase project ref: `tlvhybyattbxthoacixg`. `.env` holds URL + anon key (git-ignored).

## Environment constraints
- **No Docker** → no local Supabase. Terminal DB connections (`supabase db push`, ports 5432/6543) are **blocked by firewall**.
- Migrations are applied by the user **manually in the Supabase SQL Editor**, in filename order, each in a fresh
  "New query" tab with nothing selected (a partial paste gave `42P13 no language specified` once).
- HTTPS to Supabase works → the anon REST API can be probed from the terminal to confirm objects exist.
- Local SQL verification: **PGlite** (in-process Postgres + pgcrypto) with a stub `auth` schema
  (users, identities, sessions, refresh_tokens), kept in the session scratchpad (not in the repo).
  Runs all migrations + every `supabase/tests/*.sql`.
- SQL Editor shows only the **last** result set → every test ends with `select '... PASSED' as result`.
- User runs the dev server on `http://localhost:5173` (`npm run dev`).

## Key design decisions (and why)
- **Org/role from tables, not JWT claims** — `org_members(user_id, org_id, role_id, employee_id, status)`, one active row
  per user. *Why:* JWT claims stay valid ~1h, so revoke/role change would not be immediate. Helpers in `private`:
  `active_membership()`, `current_org_id()`, `current_role_id()`, `is_org_admin()`, `has_permission(key)`,
  `is_platform_admin()`, `current_employee_id()`, `viewer()`.
- **Admin** (`system_key='admin'`) implicitly has every permission; its permissions are locked. `roles.manage`,
  `settings.manage`, `audit.view` are admin-only. *Why:* doc says roles are created/assigned only by Admin/Owner.
- Admin cannot remove own admin access; an org always keeps ≥1 active Admin (trigger on `org_members`).
- **Composite FKs `(org_id, …)`** everywhere. *Why:* RLS alone can't stop a row in company A pointing at company B's data.
  Also `(org_id, department_id, designation_id)` → designation always belongs to the department, and
  `(org_id, branch_id, office_id)` → office always belongs to the branch — enforced by the database, not the UI.
- **Org sign-up**: applicant login → `submit_org_signup_request` → **platform admin** approves → org (random 6-digit
  immutable code) + 4 default roles + default grades + default field access + applicant becomes Admin **with an
  employee row** (owner gets a card ID).
- `audit_logs` append-only (blocked even for the DB owner). `private.purge_expired_audit_logs()` deletes only rows
  > 3 years (pg_cron schedule **not yet set**). NID values are masked in the audit log (`***123`).
- Soft delete only (`prevent_delete` trigger); deactivate = `status`.
- Phones stored as `+8801XXXXXXXXX` (`private.normalize_bd_phone`); Supabase Auth stores them without `+`.
- Login error is always "ID or password is wrong".
- **Platform (super) admins**: `sarwar@gmail.com`, `nabidbhuia313@gmail.com` (migration `20261015000100_platform_admins.sql`).
  Kept in `private.platform_admin_allowlist`; promoted only once the email is **confirmed** (trigger on `auth.users`),
  so nobody can claim the role by signing up with that address first. To add one: insert the email into the allowlist.

### Step 3–9 decisions
- **Field-level security via a view, not RLS** — base tables `employees`, `employee_sensitive`, `employee_nominees`,
  `employment_history`, `reporting_lines` are **closed to API roles**. Reads go through `employees_v`
  (security-definer view: row filter = self OR `employees.view`; each optional field shown only if the role ticked it;
  Admin and the person themself see everything). Writes go through RPCs that check `private.editable_fields()`.
  *Why:* RLS is row-level only; a Manager would otherwise get every column (doc test 3).
- `private.viewer()` computes the caller's rights **once per query** (used by the view) instead of per row/field. *Why:* speed.
- **Field catalog** (`field_catalog`) + `role_field_access` ticks. Core fields (name, card ID, department, designation,
  grade, branch, office, operation, status) are always visible to anyone who can see the employee.
  Defaults: HR Manager = all view+edit; Manager = phone, email, join date, employment type, gender (view only);
  Employee role = what they may **edit on their own profile** (phone, addresses, marital status, blood group, nominees).
- **Card ID**: auto = 2-digit join year + random digits, length 8–10 from org settings; custom = 6–15 letters/digits/hyphen.
  Unique per org case-insensitively. Generation takes a per-org **advisory lock** → two people added at the same moment
  never collide (doc test 5).
- **Placement guard trigger**: a new placement (create, transfer, reactivation) must use active department, designation,
  branch, office, operation; an operation must run in the chosen office (`office_operations`).
- **History**: `employment_history` append-only. `transfer_employee` classifies the event by grade level:
  higher = `promotion`, lower = `demotion`, else `transfer` (dept/branch/office) / `designation` / `operation`.
  Grade `level` = seniority number (EM0–4 → 0–4, MS0–2 → 10–12, OWNER01–02 → 20–21).
- **Reporting lines**: changing a manager closes the old row (end_date) and opens a new one; one current line per type;
  reporting-manager **loops are rejected**. Deactivating an employee closes their lines and clears head roles.
- **Step 7 — portal access without Edge Functions**: logins are created in SQL (`private.create_auth_user` inserts
  `auth.users` + `auth.identities`, password hashed with bcrypt via pgcrypto `extensions.crypt`, confirmed, empty-string
  token columns). Revoke = membership inactive + `banned_until` + delete sessions/refresh tokens.
  *Why:* firewall blocks deploying Edge Functions from the terminal; everything stays applyable from the SQL Editor and
  is one transaction with the audit row. *Trade-off:* depends on Supabase Auth's internal table layout — if Supabase
  changes `auth.users`, `create_auth_user` may need an update.
- HR may give only the **Employee** role; any other role needs an Admin (doc: roles assigned only by Admin).
  Admin-level logins can only be revoked/reset by an Admin; nobody can revoke/reset/deactivate themselves.
- Re-joining: an existing login with **no active employment** can be linked to a new employment (company transfer);
  an identity with an active employment anywhere → "This email or mobile number is already in use".
- **Step 8 — deactivation** (user didn't answer the office question; chose the precise option):
  - Branch → Admin picks **target branch + target office**; employees move, the branch's offices close too.
  - Office → Admin picks a **target office** (any active branch); event is `office` (same branch) or `branch`.
  - Department / designation → **blocked** while active employees remain; closing a department closes its designations.
  - Grades/operations can be switched off directly, but not while in use.
  - Direct `status = inactive` updates on department/designation/branch/office are blocked; the RPC sets a
    transaction-local flag and **switches it off again** right after (a test found the flag leaking within a transaction).
- **Dashboard** reads `get_dashboard_stats()` (real data). Sample data only on the dev-only `/preview` route.
- **Audit viewer** uses `list_audit_logs()` / `get_audit_filter_options()` (admin-only) and shows a per-field diff.

### Part 2 decisions (Time & Attendance) — user answers 2026-10-13
User clarifications that override the Part 2 doc:
1. **Web browser now; a mobile app later** will send exact location. Now: browser Geolocation for GPS check-in.
   *Live Tracking (location pings) is deferred to the mobile app* — not built.
2. **No biometric device yet** → Step 2D (device registry, ADMS push endpoint, PIN mapping, unmapped inbox) **deferred**.
   Raw punches already have `source = biometric` and `device_id`, so devices plug into `private.record_punch` later.
3. **Management and owners get overtime too** → overtime is calculated for every grade; no grade exclusion anywhere.
4. **Company chooses the law**: `org_work_settings.labor_regime` = `bd_labour_act` (default, Labour Act 2006) or
   `bd_epz_labour_act` (EPZ Labour Act 2019, for EPZ enterprises). If not EPZ → Labour Act. `apply_labor_regime_defaults()`
   resets leave types and overtime rates to that law. Today both seeds are the same (CL 10, SL 14, EL 18/yr monthly accrual
   carry ≤ 40, ML 112, LWP unlimited; OT ×2.0 everywhere, workday cap 2 h) — *values must be confirmed by HR/legal*.
5. **Month = 30 days** (`month_days` fixed at 30; daily rate = monthly ÷ 30 in Part 3). **Late deduction policy** per company:
   `none` | `days_per_lates` (N lates = X days of pay, default 3 → 1) | `amount_per_late` (fixed taka per late).
   Applied in `get_attendance_summary()`; taka for day-based deductions is computed in Part 3 (needs salary).
6. **Manager sees their team** = everyone below them on the current reporting chain (recursive, any line type) via
   `private.team_employee_ids()`. HR/Admin see everyone with `attendance.view_all`.

Other Part 2 decisions (why):
- **Raw punches are immutable evidence** (`attendance_punches`, append-only trigger, idempotent unique key). Derived
  `attendance_records` are rebuilt by `private.rebuild_attendance_day(emp, date)` — idempotent (no update when equal).
- **Engine**: check-in = first punch in [start − earliest, start + cut-off]; check-out = last punch after check-in up to
  end + window. Late = beyond grace (workdays only). Absent only after the cut-off. Half day = worked < threshold.
  Early out = before end − grace. Recorded breaks are deducted; otherwise the shift break when raw time ≥ 6 h.
  A night shift belongs to its start date; every punch rebuilds its local date and the day before.
- **Overtime**: workday = after shift end (daily cap); weekend/holiday = all worked time (no daily cap); minimum minutes,
  rounding, optional monthly cap (applied in the summary). Manual, decided or locked records are never overwritten.
- **Manual fixes** add override punches (`kind = override_in/out` + `work_date`), so originals stay; they need
  `attendance.adjust`, a reason, not on yourself, not in a locked period; audited.
- **Geofence**: nearest active fence; outside the radius or accuracy worse than max(100 m, radius) → `outside_geofence`
  (flag, never block). No location while fences exist → flagged; `require_location` makes location mandatory.
- **QR**: `issue_qr_code(office)` returns a random code once and stores only its SHA-256; valid for `qr_rotation_seconds`
  (+15 s grace); one use per employee per code. The QR is a link `/attendance/qr?c=…`, so a phone camera opens the app.
- **Leave**: balance checked at request; pending reserves days; approval → used + attendance `on_leave`; cancel restores
  both. Weekly offs/holidays are not counted unless the type says so. One calendar year per request. Approver = the
  reporting manager (team) or HR (`leave.view_all`). Nobody decides their own request. Monthly accrual is computed on read
  (`ensure_leave_balance`), so no monthly job; year rollover via `run_leave_rollover(year)`.
- **Shift swap**: request → colleague accepts → manager/HR approves → one-day override rosters for both.
  `list_colleagues()` gives employees a minimal name/card/department list to pick a partner (no contact data).
- **Period lock** (`set_period_lock`, admin-only `attendance.lock_period`): locked dates refuse punches, fixes, leave,
  overtime and rebuilds. Built now for Part 3 payroll.
- **Files**: private buckets `employee-files/{org}/{employee}/{photo|signature|nid}` and `org-assets/{org}/logo`;
  storage policies call `private.employee_file_access()` / `private.org_asset_access()` (same rules as the profile; the NID
  scan only for roles ticked for NID). The app uses 1-hour signed URLs.
- **ID card**: CR80 front/back generated in the browser from the profile (logo, photo, name, designation, card ID, blood
  group, QR `OLYMPUS:{org_code}:{card_id}`, holder signature); printed via the `.print-area` print CSS.
- **Holidays seeded**: fixed-date BD public holidays for this and next year (21 Feb, 26 Mar, 14 Apr, 1 May, 16 Dec,
  25 Dec). Eid, Puja and other lunar dates are added by HR each year.
- **No map library**: the geofence form uses "Use my location" + coordinates, with a Google Maps link to check.
- **Profile dropdown** in the top bar (photo/initials, role, org code, My profile, Change password, Sign out).
- **Lazy-loaded routes** keep every JS chunk under 500 kB.

## Open decisions / pending from user
- **Lockout**: relying on Supabase's built-in IP rate limit. Options: Password Verification Hook (may need paid plan).
- **Phone login**: Supabase Phone provider is **disabled** (`phone_provider_disabled`). Phone-only logins can't sign in
  until Authentication → Providers → Phone is enabled (needs an SMS provider).
- **pg_cron** not scheduled yet for the audit purge (`private.purge_expired_audit_logs()`) and the daily attendance close
  (`private.run_daily_close_all()`, closes "yesterday" per org timezone). Until then HR uses "Close / rebuild day".
- Statutory leave/overtime values must be confirmed against the chosen law.
- Part 2 deferred: devices (2D) and live tracking (mobile app).
- §9 assumptions of both docs: treated as accepted (Part 2 #2 confirmed by the user: manager sees their team).
- Email confirmation is ON in Supabase for self sign-up (portal logins created by HR are pre-confirmed).

## Progress
### Step 1 — Foundation ✅ (`d319403`) — applied + tested on Supabase
### Step 2 — Login + UI shell ✅ (`c655e29`) — `…0400_login.sql` applied on Supabase
### Steps 3–9 ✅ code complete — backend `204b697`, UI in the next commit. **Not yet applied on Supabase.**
| Step | Migration | UI |
|---|---|---|
| 3 Org structure | `20261014000100_step3_org_structure.sql` | `/organization` — 6 tabs, add/edit/toggle, office ↔ operations |
| 4 Roles & fields | `20261014000200_step4_roles_fields.sql` | `/settings/roles` (permissions + field view/edit ticks, new role), `/settings` (card ID policy) |
| 5 Employees | `20261014000300_step5_employees.sql` | `/employees` (KPIs, search, filters, paging), `/employees/new` (2-step), `/employees/:id`, `/me` |
| 6 History/reporting | `20261014000400_step6_history_reporting.sql` | Profile tabs: History timeline, Reporting chain; Transfer/promote, Change reporting dialogs |
| 7 Portal access | `20261014000500_step7_portal_access.sql` | Portal dialog: give access, change role, reset password, revoke; Deactivate/Reactivate |
| 8 Deactivation | `20261014000600_step8_deactivation.sql` | Deactivate dialog with impact count + target branch/office |
| 9 Audit + dashboard | `20261014000700_step9_audit_dashboard.sql` | `/audit` viewer with filters + diff; dashboard on real data |
- Tests: `supabase/tests/step3_9_acceptance_test.sql` covers architecture §6 tests 1–12 (Admin, HR, Manager, Employee,
  two companies). **Passes in PGlite** together with the Step 1 test. Typecheck + production build pass.

- Steps 3–9 applied on Supabase by the user (2026-10-13). Platform admins allow-list ✅ (`eabc2f8`,
  `20261015000100_platform_admins.sql`: sarwar@gmail.com, nabidbhuia313@gmail.com).

### Part 2 ✅ (backend `de9041d`, UI `875fe9b`) — **applied on Supabase and `part2_attendance_test.sql` passed (2026-10-14)**
- First run failed at the leave section because `…0300_part2c_requests.sql` had not been applied; rerun after applying it passed.
| Area | Migration | UI |
|---|---|---|
| 2A config | `20261016000100_part2a_time_config.sql` | `/time`: Shifts, Roster, Holidays, Leave types, Overtime policy, Work rules (law, weekly off, late policy, period lock), Geofences & QR |
| 2B attendance | `20261016000200_part2b_attendance.sql` | `/attendance/me` (check in/out with location, break, calendar, month summary, swaps), `/attendance` (daily KPIs + table + fix, monthly summary, calendar, reconciliation, swap approvals), `/attendance/qr`, `/attendance/qr-display/:officeId` |
| 2C requests | `20261016000300_part2c_requests.sql` | `/leave` (balances, request, my requests, approvals, all), `/overtime` (approve/reject, manual) |
| Files | `20261016000400_files_storage.sql` | Profile: photo/signature/NID upload + **ID card**; Settings: **company logo**; top-bar **profile dropdown** |
- Tests: `npm run test:db` (PGlite: all migrations + 3 SQL suites, 17 + 19 + 21 checks) and `npm test` (vitest, 23 unit
  tests); `npm run test:all` runs both. Typecheck + build pass.
- Verified in the browser (`/preview`): profile dropdown, mobile layout (no horizontal scroll), mobile drawer.

### Next steps
1. Done: Part 2 migrations applied and acceptance test passed on Supabase.
2. Hand test: shifts → roster → check-in on a phone → leave → overtime → lock.
3. Optional: schedule pg_cron jobs; enable the Phone provider.
4. Part 3 (payroll) reads the attendance summary, approved overtime, leave and period locks.

## File map
- `supabase/migrations/` — schema, RLS, functions (apply in order)
- `supabase/tests/` — SQL acceptance checks (one transaction, rolled back)
- `scripts/db-test/` — PGlite runner + Supabase stand-in (`npm run test:db`); `src/lib/__tests__/` — vitest unit tests
- `src/lib/time.ts` — Part 2 types + hooks; `src/lib/files.ts` — storage hooks (photo/signature/NID/logo, QR payload)
- `src/components/UserMenu.tsx` — top-bar profile dropdown + `PersonAvatar`
- `src/pages/attendance/`, `src/pages/leave/`, `src/pages/overtime/`, `src/pages/time/` — Part 2 screens
- `src/pages/employees/EmployeeFiles.tsx`, `IdCardDialog.tsx` — uploads and ID card
- `src/stores/session.ts` — Zustand session + `get_my_context()`
- `src/lib/appContext.tsx` — `useMyContext()` (real or `/preview` mock)
- `src/lib/hr.ts` — HR types + React Query hooks (structure, employees, roles, dashboard, audit)
- `src/lib/options.ts` — select options, labels, date formatting
- `src/components/ui.tsx`, `src/components/kit.tsx` — UI kit (Button, Input, Card, Modal on `<dialog>`, Select, Tabs, Table…)
- `src/components/AppLayout.tsx` — hover rail sidebar + header; `NAV` with permissions
- `src/components/guards.tsx` — PublicOnly / RequireSession / RequireAppAccess / RequirePermission / RequirePlatformAdmin
- `src/pages/organization/` — StructureTab (generic), DeactivateDialog, OrganizationPage
- `src/pages/settings/` — RolesPage, SettingsPage
- `src/pages/employees/` — EmployeesPage, AddEmployeePage, EmployeeProfilePage, profileDialogs
- `src/pages/audit/AuditLogPage.tsx`, `src/pages/DashboardPage.tsx`, `src/pages/dashboard/` (charts, preview sample data)
