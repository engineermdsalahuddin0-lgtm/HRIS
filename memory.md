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

## Open decisions / pending from user
- **Lockout**: relying on Supabase's built-in IP rate limit. Options: Password Verification Hook (may need paid plan).
- **Phone login**: Supabase Phone provider is **disabled** (`phone_provider_disabled`). Phone-only logins created in Step 7
  can't sign in until the user enables Authentication → Providers → Phone (needs an SMS provider choice).
- **pg_cron** for the 3-year audit purge not scheduled yet.
- §9 assumptions of the architecture doc: treated as accepted.
- Email confirmation is ON in Supabase for self sign-up (portal logins created by HR are pre-confirmed).
- Bundle is > 500 kB (one chunk); route-level code splitting can be added later.

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

### Next steps
1. User applies the 7 Step 3–9 migrations in order in the SQL Editor, then runs `step3_9_acceptance_test.sql`
   (expects `ALL STEP 3-9 CHECKS PASSED`).
2. Hand test in the app (doc §6), then tag the Part 1 release.
3. Then Part 2 (shift, attendance, salary, …) per the doc.

## File map
- `supabase/migrations/` — schema, RLS, functions (apply in order)
- `supabase/tests/` — SQL acceptance checks (one transaction, rolled back)
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
