# Olympus HRIS — Project memory

Running log of decisions and progress. Read this first when resuming work.
Architecture source: [docs/Part01Architecture.md](docs/Part01Architecture.md) (titled "AIHR BD"; project name is **Olympus HRIS**).

## Stack (decided)
- Frontend: **Vite + React + TypeScript**, Tailwind v4 (orange primary), React Router, React Query (server data),
  Zustand (session/org state), react-hook-form + zod, **lucide-react** icons, **recharts** charts.
- Backend: **Supabase** (Postgres, Auth). The doc says Next.js; we are **not** using Next.js.
  - Transactional server operations = **Postgres functions (RPC)**, `security definer`, in `public` (API) or `private` (internal).
  - Edge Functions only where the service-role key is needed (create/ban auth users, password reset) — Step 7+.
  - Service-role key never in `.env` / any `VITE_` variable.
- Supabase project ref: `tlvhybyattbxthoacixg`. `.env` holds URL + anon key (git-ignored).

## Environment constraints
- **No Docker**, so no local Supabase. Terminal DB connections (`supabase db push`, port 5432/6543) are **blocked by firewall**.
- Migrations are applied by the user **manually in the Supabase SQL Editor**, in filename order.
- HTTPS to Supabase works, so the anon REST API can be probed from the terminal.
- Local SQL verification: PGlite (in-process Postgres) with a stub `auth` schema, kept in the session scratchpad
  (not in the repo). It runs all migrations + `supabase/tests/*.sql`.
- Supabase SQL Editor shows only the **last** result set; tests end with a `select '... PASSED'` row.
- User's dev server runs on `http://localhost:5173` (`npm run dev`).

## Key design decisions
- **Org/role comes from tables, not JWT claims**: `org_members` (user_id, org_id, role_id, status), one active row per user.
  RLS helpers in `private`: `active_membership()`, `current_org_id()`, `current_role_id()`, `is_org_admin()`,
  `has_permission(key)`, `is_platform_admin()`. Role changes/revocation apply on the next request.
- **Admin** role (`system_key='admin'`) implicitly has every permission; its `role_permissions` are locked.
  Admin-only permissions (`roles.manage`, `settings.manage`, `audit.view`) can't be granted to other roles.
- Admin can't remove own admin access; an org always keeps ≥1 active Admin.
- **Composite FKs `(org_id, id)`** stop cross-company links (e.g. assigning another org's role).
- **Org sign-up**: applicant creates a login → `submit_org_signup_request` → **platform admin** approves
  (`approve_org_signup_request`) → org (random 6-digit immutable code) + 4 default roles (Admin, HR Manager,
  Manager, Employee) + applicant becomes Admin. Platform admins live in `platform_admins` (seeded by SQL).
- `audit_logs` append-only (trigger blocks update/delete/truncate, even for owner). `private.purge_expired_audit_logs()`
  deletes only rows > 3 years (schedule with pg_cron — not yet scheduled).
- Soft delete only (`prevent_delete` trigger) on business tables.
- Phones stored as `+8801XXXXXXXXX` (`private.normalize_bd_phone`), unique across formats.
- Field-level visibility (`role_field_access`) will be enforced via views/RPCs + edit triggers in Step 4/5 (RLS is row-level only).
- Login error is always "ID or password is wrong".

## Open decisions / pending from user
- **Lockout**: currently relying on Supabase's built-in IP rate limit (option 3). Options: Supabase Password
  Verification Hook (may need paid plan) or Edge Function (bypassable).
- **Phone login**: Supabase Phone provider is **disabled** (`phone_provider_disabled`). Needs enabling + SMS provider
  choice before Step 7 (phone-only employees).
- **Office deactivation** (Step 8): move employees to target office or target branch? Not answered.
- §9 assumptions of the architecture doc: treated as accepted unless user says otherwise.
- Email confirmation is ON in Supabase (sign-up sends a confirm link; default SMTP is rate-limited).

## Progress
### Step 1 — Foundation ✅ (committed `d319403`, `2f9b026`)
- Migrations `20261013000100_foundation_core`, `…0200_tenancy_roles`, `…0300_org_signup` — **applied** on Supabase.
- `supabase/tests/step1_foundation_test.sql` — 17 checks, **passed on Supabase** (and in PGlite; sabotage run fails as expected).

### Step 2 — Login + UI shell (in progress, not committed yet)
- Migration `20261013000400_login.sql` (`record_login`, `complete_password_change`, audit ignores `last_login_at`)
  — **applied** on Supabase (2026-10-13; first attempt failed with 42P13 from a partial paste, rerun in a fresh tab worked).
- Screens: Login (email/mobile), Sign up, Onboarding (org request / pending / rejected), Change password (forced first login),
  Platform sign-up requests (approve/reject), Dashboard.
- App shell: **left icon rail that expands on mouse hover** (and keyboard focus), lucide icons, header with org code,
  role badge, sign out; mobile drawer.
- Dashboard: 4 KPI tiles + Headcount area chart, Employment-type donut, Employees-by-department bars,
  Joiners/leavers grouped bars (each with "view as table"), Recent activity, Quick actions.
  Uses **sample data** (`src/pages/dashboard/sampleData.ts`) until Step 5 provides real employee data.
- Chart palette (validated with the dataviz validator): `#2a78d6` blue, `#eb6834` orange, `#1baf7a` aqua, fixed order.
- Dev-only route **`/preview`** shows the app shell + dashboard with a mock Admin, no login needed.
- Verified in browser: `/` → `/login` redirect, validation, generic login error, preview dashboard + hover sidebar.

### Next steps
- User: apply `…0400_login.sql`, sign up, seed self in `platform_admins`, submit + approve org, test full flow → then commit Step 2.
- Step 3: Organization structure (grades, departments, designations, branches, offices, operations) — tabs UI.
- Steps 4–9 per architecture doc §8.

## File map
- `supabase/migrations/` — schema, RLS, functions (apply in order)
- `supabase/tests/` — SQL acceptance checks (transaction + rollback)
- `src/stores/session.ts` — Zustand session + `get_my_context()`; `useCan(permission)`
- `src/lib/appContext.tsx` — `useMyContext()` (real or `/preview` mock)
- `src/components/AppLayout.tsx` — hover rail sidebar + header; `NAV` list with permissions & "Soon" steps
- `src/components/guards.tsx` — PublicOnly / RequireSession / RequireAppAccess / RequirePlatformAdmin
- `src/pages/dashboard/` — charts + sample data
