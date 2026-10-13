# Olympus HRIS

Multi-tenant HRIS. Frontend: Vite + React + TypeScript. Backend: Supabase (PostgreSQL, Auth, Edge Functions).
Architecture: [docs/Part01Architecture.md](docs/Part01Architecture.md).

## Layout

```
src/                    React app (React Query for server data, Zustand for session state)
supabase/migrations/    Database schema, RLS policies, server functions (run in filename order)
supabase/tests/         SQL acceptance checks (run in one transaction, always rolled back)
docs/                   Architecture documents
```

## Setup

1. Create a Supabase project.
2. Apply the migrations, in filename order, using either:
   - the Supabase SQL editor (paste each file in `supabase/migrations/`), or
   - the CLI: `npx supabase login`, `npx supabase link --project-ref <ref>`, `npx supabase db push`.
3. Run each file in `supabase/tests/` in the SQL editor. The Results tab must show
   `ALL STEP 1 CHECKS PASSED`; any failed check shows as an error instead. It leaves no data behind.
4. Copy `.env.example` to `.env.local` and fill in the project URL and **anon** key.
5. `npm install` then `npm run dev`.

The `service_role` key never goes in `.env.local` or any `VITE_` variable.

## Creating the first platform admin

Platform admins approve organization sign-ups. Sign up a user, then in the SQL editor:

```sql
insert into public.platform_admins (user_id)
select id from auth.users where email = 'you@example.com';
```

## Organization sign-up flow

1. Applicant creates a login (email + password).
2. Applicant calls `submit_org_signup_request(org_name, contact_name, contact_phone)`.
3. A platform admin calls `approve_org_signup_request(id)` (or `reject_org_signup_request(id, note)`).
   This creates the organization with a random 6-digit code, the default roles
   (Admin, HR Manager, Manager, Employee), and makes the applicant its Admin.

## Security model (Step 1)

- Every request's organization and role come from `org_members`, not from JWT claims,
  so role changes and revocations apply on the next request.
- Admin holds every permission implicitly. `roles.manage`, `settings.manage` and
  `audit.view` can never be granted to another role.
- An Admin cannot remove their own admin access; an organization always keeps one active Admin.
- `audit_logs` is append-only, even for the database owner. Only
  `private.purge_expired_audit_logs()` may delete rows older than 3 years (schedule with pg_cron).
- Business rows are never physically deleted; set `status` instead.

## Build progress (Part 1)

- [x] Step 1: Foundation: organizations, user profiles, roles and permissions, RLS, audit log, org sign-up
- [x] Step 2: Login: email/phone, first-login password change (lockout: Supabase rate limit for now)
- [x] Step 3: Organization structure
- [x] Step 4: Roles screen and field visibility, card ID policy
- [x] Step 5: Employees
- [x] Step 6: History, reporting chain, nominees
- [x] Step 7: Portal access
- [x] Step 8: Deactivation flows
- [x] Step 9: Audit log viewer and acceptance tests (`supabase/tests/step3_9_acceptance_test.sql`)

## Part 2 — Time & Attendance

- [x] 2A: shifts, rosters, holidays, leave types, overtime policy, work rules (Labour Act / EPZ, 30-day month, late deduction)
- [x] 2B: punches (web, GPS, QR, manual), attendance engine, daily close, reconciliation, monthly summary
- [x] 2C: leave requests and approvals, overtime approval, breaks, shift swaps
- [ ] 2D: biometric devices and live tracking (deferred: no devices yet; tracking comes with the mobile app)
- [x] Files: employee photo / signature / NID, company logo, printable ID card

## Tests

```bash
npm run test:all
```

`npm test` runs the unit tests (vitest); `npm run test:db` runs every migration and every SQL test in an in-process
Postgres (PGlite), no Docker needed.

See [memory.md](memory.md) for decisions and the reasons behind them.
