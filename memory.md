# Olympus HRIS — Project memory

Running log of **what was done and why**. Read this first when resuming work.
Architecture source: [docs/Part01Architecture.md](docs/Part01Architecture.md), [Part02](docs/Part02Architecture.md),
[Part03](docs/Part03Architecture.md) (titled "AIHR BD"; project name is **Olympus HRIS**).

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

### Part 3A decisions (Salary structure) — 2026-10-17
User answers in the Part 3 doc §9: #14 retention period confirmed by the company **and every payment must be traceable
in the audit log**; #15 wants a **visible manual performance-scoring demo** now (PMS later) — not built yet, see Open.
Other §9 assumptions treated as accepted (30-day basis, base per org, maker-checker, negative net → 0 + carry, lines
2 decimals / net nearest taka).
- **Salary tables closed to API roles** (`employee_compensation`, lines, increments, deductions, payment accounts);
  reads via security-barrier views (`employee_pay_v`, `salary_increments_v`, `employee_deductions_v`,
  `payment_accounts_v`) filtered by `private.money_viewer()`; writes only via RPCs. *Why:* doc "salary readable only by
  roles the Admin ticked"; Manager/Employee get no money permission.
- **Permissions** (3A): `compensation.view/edit`, `increments.approve`, `bonuses.manage`, `deductions.manage`,
  `payroll_settings.manage`, `payment_accounts.view/edit`. HR default: view/edit, bonuses, deductions, accounts view/edit.
  **Not** HR by default: `increments.approve`, `payroll_settings.manage` (Admin ticks them). Employee sees own payment
  accounts (masked) and own loans only — not the pay table (payslips come in 3B).
- **Pay is versioned, never edited**: a change closes the current row (`effective_to` = new date − 1) and opens a new one;
  lines are a **snapshot** (code, name, calc, rate, amount), so template edits never change past or current pay.
  Guard trigger allows only closing a row; lines are append-only; no overlap per employee.
- **Starting pay** (`set_initial_compensation`) only once per employee; every later change = **increment request →
  approval** (maker-checker: requester ≠ approver, nobody decides their own pay). One pending increment per employee.
- **Resolution** `private.resolve_salary(template, basic | target gross)`: gross = basic + fixed + basic·Σ%basic +
  gross·Σ%gross (Σ%gross < 100). With a target gross, basic is solved and the rounding paisa goes on the Basic line so the
  gross matches exactly. Lines rounded half away from zero to 2 decimals. Client mirror `previewTemplate()` (integer paisa
  + BigInt) gives the same numbers for the unsaved template builder; the server stays the authority.
- **Arrears** preview `get_increment_arrears`: gross difference per month on the 30-day basis from the effective month up to
  (not incl.) the current month; first month pays `30 − (day − 1)` days. 3B pays it.
- **Bonus eligibility**: in scope (all / departments / employees), employed in the payment month, pay on record, completed
  service months at the payment month end ≥ minimum. Percent of basic or gross from the pay effective that month.
- **Loans/advances**: `remaining` starts = total, installment ≤ total; 3B posts installments and stops at zero.
- **Payment accounts**: numbers encrypted with pgcrypto `pgp_sym_encrypt` (AES-256); only the last 4 digits kept clear
  for masking; stored numbers are never sent back to the form (empty = keep). Reveal = `reveal_payment_account` (needs
  `payment_accounts.view`, audited, the UI hides it again after 30 s). The audit trigger strips the encrypted columns and
  only records `number_changed`. Nobody (except Admin) edits their own payment data. *Trade-off:* the key lives in
  `private.app_secrets` (not readable by API roles) because Vault is not available in PGlite; could move to Supabase Vault.
- **Payroll settings**: deduction base, OT base + **OT hourly divisor (placeholder 208 — must be confirmed)**, pay weekly
  off/holidays, half-day %, unpaid-leave base, net rounding, negative-net rule, payslip release, large-change warning.
  Changing a statutory value clears `statutory_confirmed_at`; `confirm_payroll_statutory_values()` re-confirms.
  Tax/PF/gratuity switches exist in the table but are edited in 3C.
- **Seeded components** (examples, not statutory): BASIC (the one Basic), HOUSE_RENT 50% basic, MEDICAL 750,
  CONVEYANCE 450, FOOD 1250. Basic cannot be changed or switched off; a component used by an active template cannot be off.
- **Safe error messages** (`errorMessage` in `src/lib/identity.ts`): our own RAISE messages pass through; Postgres
  internals (constraint/table names, RLS text, PGRST codes) become plain sentences. RPCs validate inputs explicitly so
  users get a clear message instead of a constraint error.
- Meals (optional) **deferred**.

### Part 3B decisions (Payroll engine) — 2026-10-19
- **Lifecycle** draft → calculated → reviewed → approved → paid → locked (+ cancelled). The **preparer = whoever last
  calculated**; that person can never approve (maker-checker enforced in `approve_payroll_run`). Review is blocked while
  the run is stale or has blockers.
- **Stale detection**: `private.payroll_inputs_fingerprint(org, month)` (md5 of counts / max(updated_at) / sums of
  attendance, approved overtime, pay versions, increments, bonuses, loans, adjustments, employees, payment accounts,
  settings, previous month's approved slips). Stored at calculation; review/approve refuse a different fingerprint.
- **Engine** `private.calculate_slip` (30-day basis, every line rounded to paisa half away from zero):
  pay = the version in force on the 1st of the month (or the joining day); a mid-month change is paid as arrears next
  month. Earnings = every snapshot line at full value. **Proration** = −gross × days not employed / 30
  (`private.employed_days`: joining day N → N−1 days off; leaving on day N → 30−N off; leaving on/after month end = full).
  **Overtime** = approved minutes grouped by (day type, multiplier stored on the record) × (OT base ÷ divisor) — every grade.
  **Bonuses**: active, payment month, scope, completed service ≥ minimum. **Arrears** (`private.increment_arrears_due`):
  for approved back-dated increments, every already-approved month slip with a different pay version →
  (new gross − slip gross) × (first month: days from the effective date, else 30) / 30; paid once (`arrears_slip_id`).
  **Adjustments**: approved, apply month. **Absence** = deduct base ÷ 30 × absent days; **half day** × the set %;
  **unpaid leave** = unpaid-leave base ÷ 30 × days on a leave type with `paid = false`; unpaid weekly off / holidays only
  if the settings say so. **Late** = Part 2 policy (floor(lates ÷ N) × X days × daily, or taka × lates).
  **Loans** = least(installment, remaining) from the start month. **Carry** = last month's `carry_forward_out`.
  Net = gross − deductions → negative: `zero_and_carry` (net 0, carry) or `block` (blocker); else net-rounding rule.
- **Warnings / blockers** per slip: missing_compensation (blocker), negative_net, missing_payment_account, large_change
  (vs last month's approved net, `large_change_percent`), no_attendance. Run warnings: attendance_not_locked,
  statutory_unconfirmed.
- **Approval posts** (one transaction): loans `remaining −= installment` (0 → completed), increment `arrears_slip_id`,
  adjustments `applied`, payment batches per method (`unassigned` when no account; net 0 slips excluded).
  **Reopen** (`payroll.reopen`, reason ≥ 5 chars, audited) reverses exactly these and returns to calculated.
- **Frozen slips**: a trigger blocks changing slips/lines of approved+ runs; only marking payments sets a
  transaction-local flag. Corrections after approval = `payroll_adjustments` (maker-checker) in an open month.
- **Paid / lock**: `mark_payment_batch_paid` per batch; all paid → run paid. `lock_payroll_run` → locked and, for a
  whole-organization run, inserts a Part 2 period lock for the month (attendance, leave, overtime read-only).
- **One run per employee per month** (unique slip key); a branch/department run skips people already in another run.
- **Visibility**: payroll staff = any of prepare/review/approve/reopen/lock. Employees see their own slip via
  `get_payslip` / `list_my_payslips` only once released (`payslip_release`: approved or paid). Managers see nothing.
- **Payment sheets**: `get_payment_sheet(batch)` decrypts numbers, needs `payment.export`, audited
  (`payment_sheet.exported`); the UI builds a CSV with **formula-injection protection** (`csvCell`) and a UTF-8 BOM.
- **Payslip PDF**: printable `PayslipDocument` in **English or Bangla** (labels + Bangla digits; component names as
  entered) printed through the browser (Save as PDF). Every line shows base × rate × quantity.
- **Permissions** added: `payroll.view_own` (Employee, Manager, HR), `payroll.prepare` + `payroll.review` (HR),
  `payroll.approve`, `payroll.reopen`, `payroll.lock`, `payment.export` (Admin until ticked for another role).

### Platform / SaaS decisions — user answers 2026-10-17
- **Order agreed**: landing page + super-admin platform first, then Part 3B.
- **Registration = one form (company + admin account)** on `/register`. The company details are sent as sign-up metadata
  (`org_application`); trigger `on_auth_user_signup_application` validates them and creates a **pending application**.
  Bad values are dropped and a bad application never blocks the account (the onboarding screen still lets them apply).
  *Why:* email confirmation is on, so the applicant has no session right after sign-up and cannot call an RPC.
- **Super admins** (`sarwar@gmail.com`, `nabidbhuia313@gmail.com`) accept or reject applications; **reject needs remarks**
  (shown to the applicant). Accepting works before the applicant confirms their email; they can sign in after confirming.
- **Platform dashboard** (`/platform`) shows only statuses: applications pending / accepted / rejected and organizations
  active / non-active; clicking an organization row opens `/platform/organizations/:id` with employee volume,
  subscription and payment status (+ admins, application details, payment history).
- **Subscriptions = plan + manual payment entry** (no gateway yet): `platform_plans` (TRIAL 30 days ≤ 25 employees, BASIC,
  PRO, ENTERPRISE; prices null = "Contact sales"), one `org_subscriptions` row per org (every new org starts on TRIAL via a
  trigger on `organizations`), `org_payments` recorded by super admins (due / paid / overdue / waived / refunded; a due
  invoice past its due date reads as overdue). Payment status per org = overdue > due > paid > none.
- **Deactivate organization** = `suspended` or `inactive` with a required reason; its users lose access on the next request
  (active_membership requires an active org). Reactivation restores access.
- Billing tables closed to API roles; only platform RPCs (`private.require_platform_admin()`) reach them. Every platform
  action is audited on the organization concerned.
- **Landing page** (`/` when signed out): hero, modules, "made for Bangladesh", security, how it works, pricing from
  `get_public_plans()` (anon-callable; falls back to built-in plans), FAQ, CTA. No invented testimonials or customer counts.
  Ideas taken from ibos.io (hero + CTA, solutions grid, 3-step process, FAQ).
- Old `SignupPage` and `SignupRequestsPage` removed; `/signup` → `/register`, `/platform/requests` → `/platform/applications`.

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
- Super-admin accounts: create them in Supabase Dashboard → Authentication → Users → Add user (auto-confirm); the
  allow-list trigger promotes them. Passwords are never stored or shared by the project (bcrypt hashes only).
- **PMS demo** (user note on §9 #15): a visible manual performance-scoring screen is wanted as a demo before the real
  PMS part — scope (who scores, scale, link to performance bonus?) to be agreed.
- Overtime hourly divisor (208) and half-day % are placeholders until the company confirms them.

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

### Part 3A ✅ (2026-10-17) — **applied on Supabase; `part3a_salary_structure_test.sql` passed (2026-10-17)**
| Area | Migration | UI |
|---|---|---|
| 3A salary structure | `20261017000100_part3a_salary_structure.sql` | `/salary` (KPI tiles, Templates builder with live gross preview, Components), `/compensation` (Employee pay + set pay / request change, Increments review with arrears, Bonuses + eligibility preview, Loans & advances with schedule), `/settings/payroll`, Employee profile **Financial** tab (`?tab=financial`) |
- Tests: `part3a_salary_structure_test.sql` 11 checks (Part 3 tests 1, 2, 9, 10, 14 set-up, 16, 17, 21 masking +
  immutability, statutory confirmation), hand-calculated: 17,450.00; 15,033.33 / 7,516.67 / 25,000.00; 34,166.67;
  arrears 3,910.00; bonus 7,516.67. vitest 35 tests (`payroll.test.ts` mirrors the same golden numbers;
  `identity.test.ts` covers safe errors). Typecheck + build pass. UI not yet checked against live data.
- Fixed in passing: profile initials regex `/s+/` → `/\s+/`.

### Platform / landing ✅ (2026-10-17) — **applied on Supabase; `platform_saas_test.sql` passed**
| Area | Migration | UI |
|---|---|---|
| SaaS platform | `20261018000100_platform_saas.sql` | `/` landing (signed out), `/register` (2-step), `/platform` dashboard, `/platform/applications` (accept / reject with remarks), `/platform/organizations/:id` (volume, subscription, payments, activate/deactivate) |
- Tests: `platform_saas_test.sql` 7 checks (applications from sign-up metadata incl. invalid data, anon can read plans only,
  non-admins blocked, reject needs remarks, trial on approval, overdue → paid, plan change, suspend → no access →
  reactivate, audit). All 5 SQL suites pass (75 checks); vitest 35; typecheck + build pass.
- Verified in the browser: landing desktop + mobile (no horizontal scroll), register step-1 validation, `?plan=` preselect.

### Part 3B ✅ code complete (2026-10-19) — **not yet applied on Supabase**
| Area | Migration | UI |
|---|---|---|
| 3B payroll engine | `20261019000100_part3b_payroll_engine.sql` | `/payroll` (runs, new run = create + calculate, adjustments with approve/reject), `/payroll/runs/:id` (status stepper, checks, role-based actions, slips, payment sheets CSV, mark paid, reopen, lock), `/payslips` (own payslips), payslip dialog EN/বাংলা + print |
- Tests: `part3b_payroll_engine_test.sql` 12 golden checks (Part 3 tests 1–10, 14–21): Feb 17,450 / 16,783 / total
  156,383; Mar 21,450 (bonus − loan), 16,783 (31-day = Feb), 8,725 joiner, 11,633 leaver, 18,700 MS OT
  (192.31 + 480.77 + 576.92), 17,642 OWNER-grade OT, 16,950 late + half day, 21,275 arrears (2,550 × 15/30),
  0 + carry 2,550; Apr 16,950 (last 500), 14,900 carry recovered, 20,000 no second arrears; Beta gross-base absence
  1,163.33, 200/late = 600, down-rounding 15,878.98 → 15,878; recalc identical; stale input blocks review; preparer cannot
  approve; reopen reverses loans/adjustments; lock blocks March attendance fix. vitest 42 (csv safety, Bangla money).
- Note: in tests the org owner joins on the approval day, so owners are not in back-dated payroll months.

### Next steps
1. Done: Part 2 migrations applied and acceptance test passed on Supabase.
0. Apply `20261019000100_part3b_payroll_engine.sql`, run `part3b_payroll_engine_test.sql`; hand test a run with two
   people (HR prepares, Admin approves). Then Part 3C (tax/TDS, PF, gratuity) and 3D (compliance, grievance, committees).
0. Apply `20261017000100_part3a_salary_structure.sql` and `20261018000100_platform_saas.sql`, then run
   `part3a_salary_structure_test.sql` and `platform_saas_test.sql`.
2. Hand test: shifts → roster → check-in on a phone → leave → overtime → lock.
3. Optional: schedule pg_cron jobs; enable the Phone provider.
4. Apply Part 3A on Supabase and run its test; hand test templates → set pay → increment (two people) → bonus preview.
5. Part 3B (payroll engine): runs, slips + lines, adjustments, payment sheets, payslip view/PDF, lock integration.
   Reads the attendance summary, approved overtime, leave, period locks, pay versions, bonuses, loans, arrears.
6. Agree the PMS demo scope (manual scoring).

## File map
- `supabase/migrations/` — schema, RLS, functions (apply in order)
- `supabase/tests/` — SQL acceptance checks (one transaction, rolled back)
- `scripts/db-test/` — PGlite runner + Supabase stand-in (`npm run test:db`); `src/lib/__tests__/` — vitest unit tests
- `src/lib/payroll.ts` — Part 3 types + hooks + money helpers (`formatTaka`, `parseMoney`, `previewTemplate`,
  `installmentSchedule`); `src/pages/salary/` — SalaryStructurePage, CompensationPage, PayrollSettingsPage, dialogs
  (SetPay, Increment, Deduction, PaymentAccount, MaskedNumber); `src/pages/employees/FinancialTab.tsx`
- `src/lib/time.ts` — Part 2 types + hooks; `src/lib/files.ts` — storage hooks (photo/signature/NID/logo, QR payload)
- `src/components/UserMenu.tsx` — top-bar profile dropdown + `PersonAvatar`
- `src/lib/payrollRuns.ts` — Part 3B types, hooks, CSV helpers; `src/lib/payslipText.ts` — EN/BN payslip labels;
  `src/pages/payroll/` — PayrollRunsPage (runs + adjustments), PayrollRunPage, PayslipView (dialog + printable), MyPayslipsPage
- `src/lib/platform.ts` — platform/SaaS types + hooks; `src/pages/public/` — PublicShell, LandingPage, RegisterPage;
  `src/pages/platform/` — PlatformDashboardPage, ApplicationsPage, OrganizationDetailsPage
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
