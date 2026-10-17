# Olympus HRIS

A multi-tenant HR and payroll system for Bangladeshi companies. A company applies on the landing page, a platform admin approves it, and the company runs its people, attendance, leave, overtime, payroll, income tax, provident fund, gratuity and performance reviews in one workspace.

- **Frontend:** Vite + React 19 + TypeScript single-page app.
- **Backend:** Supabase (PostgreSQL, Auth, Storage). All server logic is in PostgreSQL functions; there are no Edge Functions and no service-role key.
- **Bangladesh rules built in:** Labour Act 2006 or EPZ Labour Act 2019 per company, 30-day month, FY 2026-27 income-tax tables (Finance Act 2026), Bangla payslips.

> **Before going live, read [Statutory values](#statutory-values-read-before-go-live).** Tax tables were checked against public sources. Provident-fund and gratuity defaults are placeholders the company must confirm.

---

## Contents

1. [Features](#features)
2. [Tech stack](#tech-stack)
3. [Architecture](#architecture)
4. [Repository layout](#repository-layout)
5. [Getting started (local)](#getting-started-local)
6. [Database setup](#database-setup)
7. [Deployment](#deployment)
8. [Roles and permissions](#roles-and-permissions)
9. [Developer guide](#developer-guide)
10. [Spotlight guide (onboarding tours)](#spotlight-guide-onboarding-tours)
11. [Testing](#testing)
12. [Statutory values (read before go-live)](#statutory-values-read-before-go-live)
13. [Troubleshooting](#troubleshooting)
14. [Further documentation](#further-documentation)

---

## Features

| Area | What it does |
|---|---|
| **Platform (SaaS)** | Landing page, company application (company + admin account in one form), two allow-listed super admins accept or reject with remarks, organization status, subscriptions (Trial / Basic / Pro / Enterprise), manual payment entry |
| **Organization** | Branches, offices, departments, designations with grades (EM / MS / OWNER), operations, company logo, card-ID policy |
| **Employees** | Two-step onboarding, transfers and promotions with history, reporting lines, nominees, portal logins, deactivation, photo / signature / NID upload, printable ID card with QR |
| **Time & attendance** | Shifts, rosters, holidays, web / GPS / QR check-in, attendance engine (late, half day, absent, night shift), daily close, reconciliation, period locks |
| **Requests** | Leave (balances, approval, rollover), overtime approval, breaks, shift swaps |
| **Salary structure** | Components and templates, versioned pay, increments (maker-checker, arrears), bonuses with eligibility, loans and advances, encrypted bank / mobile-wallet accounts |
| **Payroll** | Monthly runs (calculate, review, approve, pay, lock), slip lines with every number traceable, adjustments, payment sheets (CSV), payslips in English and Bangla (print to PDF) |
| **Tax, PF, gratuity** | TDS by the annual projection method, tax calculator, TIN profiles, TDS ledger with challans, provident fund members / ledger / interest / withdrawal preview, gratuity payout and liability |
| **Explainability** | Every payslip line shows its formula with real numbers and links to the law or company policy it follows (law & policy library, English + Bangla) |
| **Performance (demo)** | Review cycles with weighted criteria, 1–5 manual scoring, manager team scope, employee acknowledgement |
| **Audit & security** | Append-only audit log, field-level access per role, masked sensitive data, every export audited |
| **UX** | Hover-expand sidebar, mobile drawer, dashboard charts, spotlight onboarding tour, responsive down to 375 px |

## Tech stack

| Layer | Choice |
|---|---|
| UI | React 19, TypeScript, Tailwind CSS v4 (orange `primary-*` palette), lucide-react icons, recharts |
| Routing | React Router 7 with lazy-loaded pages |
| Server state | TanStack React Query 5 |
| Session state | Zustand (`src/stores/session.ts`) |
| Forms | react-hook-form + zod (validation for UX only; the database is the authority) |
| Backend | Supabase: PostgreSQL 15+, Auth, Storage, Row Level Security |
| Tests | vitest (unit), PGlite (in-process PostgreSQL for every migration and SQL test) |
| Build | Vite 8, Node.js 22 LTS or newer |

## Architecture

```
Browser (React SPA)
  └─ supabase-js (anon key + user JWT)
       ├─ auth            sign in / sign up / password change
       ├─ rpc('fn', …)    public.* SECURITY DEFINER functions: all writes, most reads
       ├─ from('*_v')     security-barrier views with row and field filtering
       ├─ from('table')   configuration tables only, guarded by RLS and column grants
       └─ storage         employee-files / org-assets buckets, signed URLs
PostgreSQL
  ├─ public    tables, views, API functions
  ├─ private   helpers, triggers, secrets (never exposed through the API)
  └─ auth      Supabase users (portal logins are created in SQL)
```

**Security model:**

- **Tenant isolation.** Every business table has `org_id`. Composite foreign keys `(org_id, id)` make cross-company links impossible. RLS filters by `private.current_org_id()`. Sensitive tables are closed to API roles and are reached only through functions.
- **Identity comes from tables, not the JWT.** The organization and role are read from `org_members` on every request, so a role change, a revoked login or a suspended company takes effect immediately.
- **Function pattern.** Each function does the same steps in order: permission check, then an org-scoped row load, then explicit validation, then the write, then the audit entry.
- **Maker-checker.** Increments, payroll approval and payroll adjustments need a second person. Nobody approves their own leave, overtime or pay.
- **Sensitive data:**
  - NID and account numbers are masked in views.
  - Account numbers are encrypted at rest (pgcrypto).
  - Sensitive values are stripped from the audit log.
  - Reveals and exports are audited.
- **Records are never deleted.** Business rows use `status` instead (soft delete). Ledgers and history tables are append-only.
- **Safe errors.**
  - Functions raise clear messages with standard SQLSTATE codes (`22023`, `23502`, `23505`, `23514`, `42501`, `P0002`).
  - The UI shows them through `errorMessage()` in `src/lib/identity.ts`.
  - Internal database details are never shown to users.

## Repository layout

```
src/
  components/          AppLayout (sidebar, top bar), guards, ui.tsx + kit.tsx (design system),
                       references.tsx (law chips), calcVisuals.tsx (tax / net charts), spotlight/ (tour)
  lib/                 data hooks per area: hr, time, payroll, payrollRuns, statutory, platform, files;
                       pure helpers: identity, options, payslipText, calculationGuide (all unit-tested)
  pages/               one folder per area (employees, attendance, payroll, statutory, performance, platform, …)
  router.tsx           routes; guarded(permission, path, page) hides pages the role cannot use
  stores/session.ts    signed-in user and organization context (get_my_context)
supabase/
  migrations/          schema, RLS, functions — apply in filename order
  tests/               SQL acceptance tests with hand-calculated golden numbers (always rolled back)
scripts/db-test/       PGlite runner + Supabase stub used by `npm run test:db`
docs/                  architecture documents (Part 1–3)
memory.md              project handbook and decision log (read this before changing anything)
```

## Getting started (local)

**Prerequisites:** Node.js 22+, npm, and a Supabase project (the free tier is enough). Docker is not required.

```bash
npm install
```

1. Apply the database, as described in [Database setup](#database-setup).
2. Create `.env.local` from the example and fill in your project URL and **anon** key (Supabase Dashboard → Project Settings → API):

   ```bash
   cp .env.example .env.local
   ```

3. Start the dev server:

   ```bash
   npm run dev
   ```

4. Open `http://localhost:5173`.

`http://localhost:5173/preview` (development builds only) shows the app shell and dashboard with sample data and no sign-in. It is useful for UI work.

### Environment variables

| Name | Where to find it | Notes |
|---|---|---|
| `VITE_SUPABASE_URL` | Project Settings → API → Project URL | public |
| `VITE_SUPABASE_ANON_KEY` | Project Settings → API → `anon` `public` key | public, protected by RLS |

> **Never** put the `service_role` key in any file or `VITE_` variable. Everything prefixed `VITE_` ends up in the browser bundle.

### npm scripts

| Script | What it does |
|---|---|
| `npm run dev` | Vite dev server with hot reload |
| `npm run build` | Type-check, then production build into `dist/` |
| `npm run preview` | Serve the production build locally |
| `npm run typecheck` | TypeScript project build check |
| `npm test` | Unit tests (vitest) |
| `npm run test:db` | Every migration + every SQL test in PGlite (in-process PostgreSQL) |
| `npm run test:all` | Both of the above |

## Database setup

Apply every file in `supabase/migrations/` **in filename order**. Two ways:

- **SQL Editor (recommended).** Supabase Dashboard → SQL Editor → **New query**. Paste the **whole** file with nothing selected and press Run. Use a fresh tab for each file.
- **CLI.** Where the database port is reachable:

  ```bash
  npx supabase link --project-ref <ref>
  ```

  then:

  ```bash
  npx supabase db push
  ```

| # | Migration | Adds |
|---|---|---|
| 1 | `20261013000100_foundation_core` | audit log, row metadata triggers |
| 2 | `20261013000200_tenancy_roles` | organizations, user profiles, roles, permissions, memberships |
| 3 | `20261013000300_org_signup` | company applications and approval |
| 4 | `20261013000400_login` | email-or-phone login, first-login password change |
| 5–11 | `20261014000100` … `0700` | organization structure, field access, employees, history, portal access, deactivation, audit viewer, dashboard |
| 12 | `20261015000100_platform_admins` | super-admin allow-list (edit the emails for your deployment) |
| 13–16 | `20261016000100` … `0400` | Part 2: time config, attendance engine, requests, file storage buckets |
| 17 | `20261017000100_part3a_salary_structure` | salary components, pay history, increments, bonuses, loans, payment accounts |
| 18 | `20261018000100_platform_saas` | plans, subscriptions, payments, landing-page applications |
| 19 | `20261019000100_part3b_payroll_engine` | payroll runs, slips, adjustments, payment batches |
| 20 | `20261020000100_part3c_tax_pf_gratuity` | tax tables, TDS, provident fund, gratuity, law & policy references |
| 21 | `20261020000200_pms_manual_scoring` | performance review cycles and scores |

Several migrations check their prerequisite and stop with a clear message if an earlier file is missing.

### Verify with the SQL tests

Run each file in `supabase/tests/` the same way. Each one runs inside a transaction that is rolled back, so it leaves no data behind. The last result row must read `==== ALL … CHECKS PASSED ====`. A failed check shows up as an error instead.

| Test | Covers |
|---|---|
| `step1_foundation_test.sql` | tenancy, roles, applications, audit |
| `step3_9_acceptance_test.sql` | organization, employees, history, portal access, deactivation |
| `part2_attendance_test.sql` | attendance engine, leave, overtime, swaps, locks |
| `part3a_salary_structure_test.sql` | templates, increments, arrears, bonuses, loans |
| `platform_saas_test.sql` | plans, subscriptions, payments |
| `part3b_payroll_engine_test.sql` | payroll golden numbers (joiners, leavers, overtime, arrears, negative net …) |
| `part3c_tax_pf_gratuity_pms_test.sql` | TDS projection, PF, gratuity, tax calculator, performance scoring |

### Platform (super) admins

Migration 12 holds an allow-list of emails. To create the super-admin accounts:

1. Supabase Dashboard → Authentication → Users → **Add user**, with **Auto confirm** ticked.
2. As soon as the email is confirmed, the account becomes a platform admin.

Edit the list in that migration before applying it to another deployment. To add an admin to a database that is already running, use the SQL Editor:

```sql
insert into private.platform_admin_allowlist (email) values ('admin@example.com');
-- then create or confirm the user; existing confirmed users can be promoted directly:
insert into public.platform_admins (user_id) select id from auth.users where email = 'admin@example.com';
```

## Deployment

The frontend is a static SPA, so any static host works (Vercel, Netlify, Cloudflare Pages, S3 + CloudFront, Nginx).

1. **Build:**

   ```bash
   npm ci
   ```

   then:

   ```bash
   npm run build
   ```

   This produces `dist/`. On a CI host, use build command `npm run build` and output directory `dist`.
2. **Environment.** Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the host's build settings. They are read at build time.
3. **SPA fallback.** Every unknown path must serve `index.html`, so deep links like `/payroll/runs/…` work.
   - Netlify: add a `public/_redirects` file containing `/*  /index.html  200`.
   - Vercel: add `vercel.json` with `{ "rewrites": [{ "source": "/(.*)", "destination": "/" }] }`.
   - Nginx: `try_files $uri /index.html;`.
4. **Supabase Auth** (Dashboard → Authentication → URL Configuration):
   - Set **Site URL** to the production domain.
   - Add the domain to **Redirect URLs**, which email confirmation links use.
   - Keep email confirmation on. Platform-admin promotion and company applications depend on it.
5. **Database.** Apply all migrations and run the SQL tests on the production project.
6. **Storage.** Migration 16 creates the `employee-files` and `org-assets` buckets with their policies. No manual setup is needed.
7. **Optional scheduled job.** `private.purge_expired_audit_logs()` deletes audit rows past the retention period and can be scheduled with pg_cron. Daily attendance close and leave rollover are run from the app for now (Attendance → "Close / rebuild day", Time setup → leave types → "Year rollover"), because they check the user's permission.

**Go-live checklist:**

- [ ] All 21 migrations applied, and all 7 SQL tests pass on the production database.
- [ ] Super-admin accounts created and confirmed.
- [ ] Site URL and redirect URLs set.
- [ ] The Admin of each company has confirmed payroll statutory values (Payroll settings) and tax / PF / gratuity values (Statutory settings).
- [ ] `service_role` key appears nowhere in the frontend or its environment.

## Roles and permissions

Every company starts with four roles. The Admin can edit the other three, tick permissions and choose which fields each role sees.

| Role | Default access |
|---|---|
| **Admin** | Everything, implicitly. Only the Admin can manage roles, company settings, the audit log and attendance period locks. |
| **HR Manager** | Organization, employees, attendance, leave, overtime, compensation, bonuses, loans, payment accounts, payroll prepare / review, tax profiles, PF, gratuity, performance. **Not by default:** approving pay changes or payroll, payment exports. |
| **Manager** | Own team's attendance, leave, overtime and swaps, plus performance scoring for the own team. Sees no salary. |
| **Employee** | Own attendance, leave requests, payslips and reviews. |

The UI hides what a role cannot use; the database enforces every permission regardless. The full permission catalog is in [memory.md](memory.md) (section A7).

## Developer guide

**Read [memory.md](memory.md) first.** Part A is the handbook (flows, schema, function catalog, UI map, status). Part B explains why things are built the way they are.

### Adding a feature

1. **Migration.** Create `supabase/migrations/YYYYMMDDHHMMSS_area_name.sql` with:
   - a header comment stating purpose and rules;
   - permissions and a seed function for new and existing companies;
   - tables with `org_id`, composite foreign keys, checks and `attach_standard_triggers`;
   - helpers in `private` and API functions in `public`;
   - privileges: enable RLS, `revoke all … from anon, authenticated`, then grant only what is needed.
2. **SQL test.** Create `supabase/tests/<area>_test.sql`:
   - Wrap it in `begin` … `rollback`.
   - Build fixtures through the real sign-up and approval functions.
   - Write the expected numbers in comments first.
   - Do **not** create tables mid-script (the Supabase SQL Editor cannot see them). Pass values between statements with `set_config('t.x', …, true)`.
3. **Data hooks.** Add React Query hooks to `src/lib/<area>.ts` and invalidate the affected query keys after mutations.
4. **Page.** Add a page in `src/pages/<area>/`, a lazy route with `guarded(permission, path, page)` in `src/router.tsx`, and a sidebar item (`anyOf` permissions) plus a title in `src/components/AppLayout.tsx`.
5. **Verify.** Run `npm run test:all`, `npm run typecheck` and `npm run build`. Check the page at desktop width and at 375 px.

### Conventions

- **Calling the database.** Use `supabase.rpc('function_name', { p_argument: … })`. Function arguments start with `p_`.
- **Money** is `numeric`, rounded half away from zero to 2 decimals (`private.round_money`). The month is always 30 days.
- **Every page** has loading, empty and error states. Show errors only through `errorMessage(error)`.
- **Components.** Reuse `components/ui.tsx` (Button, Input, Card, Alert, Badge, …) and `components/kit.tsx` (Select, Modal, Tabs, Table, Switch, PageHeader, …).
- **Comments** explain *why*, not *what*. Names say what a value is (`v_deduct_daily`, `payableDays`).
- **CSV exports** go through `toCsv` / `csvCell` (`src/lib/payrollRuns.ts`), which neutralise spreadsheet formulas.

### Explaining a calculation

To show where a number comes from:

- Add a row to `statutory_references` (in a migration) with the law, section, source URL and verification date.
- Show it with `<ReferenceChips keys={['labour.overtime']} />` from `src/components/references.tsx`.
- For payslip lines, `explainLine()` in `src/lib/calculationGuide.ts` maps each line type to its formula and references.

## Spotlight guide (onboarding tours)

`src/components/spotlight/` is a reusable onboarding guide. It shows a dark mask (70% overlay) with a hole punched around one element per step, and a step card beside it.

- **Responsive.** It follows the element on scroll and resize, and keeps the card inside the screen.
- **Keyboard.** `→` / `Enter` goes to the next step, `←` goes back, `Esc` closes. Focus stays inside the card and returns to where it was when the guide closes.
- **Motion.** It respects `prefers-reduced-motion`.
- **Robust.** The page behind cannot be clicked. Steps whose target is hidden or missing (for example a desktop-only element on a phone) are skipped.
- **Remembers.** It opens automatically once per browser and can be replayed with the **?** button in the top bar.

### Usage

**1. Mark the elements** with `data-tour`:

```tsx
<div data-tour="kpis" className="grid …">…</div>
```

**2. Describe the steps:**

```tsx
import type { SpotlightStep } from '@/components/spotlight/SpotlightTour'

const STEPS: SpotlightStep[] = [
  { title: 'Welcome', body: 'A quick tour of this page.' },                        // no target: centred card
  { target: '[data-tour="kpis"]', title: 'Key numbers', body: 'Headcount at a glance.' },
  { target: ['[data-tour="sidebar"]', '[data-tour="menu-button"]'],                 // first visible one wins
    title: 'Menu', body: 'Everything lives here.', placement: 'right', padding: 4 },
]
```

**3. Render it.** Bump the key (`-v2`) when the steps change, so everyone sees the new guide:

```tsx
import { SpotlightTour } from '@/components/spotlight/SpotlightTour'
import { useSpotlightTour } from '@/components/spotlight/useSpotlightTour'

const tour = useSpotlightTour('payroll-v1')          // auto-opens once per browser
<button onClick={tour.start}>Show guide</button>
<SpotlightTour steps={STEPS} open={tour.open} onClose={tour.close} />
```

| `SpotlightStep` field | Default | Meaning |
|---|---|---|
| `target` | none | CSS selector, or a list of selectors (the first visible one is used). Omit for a centred step. |
| `title`, `body` | required | Card text; `body` accepts JSX |
| `placement` | `'auto'` | `top`, `bottom`, `left`, `right`, or `auto` (the side with room) |
| `padding` | `8` | Space between the element and the hole edge (px) |
| `radius` | `14` | Corner radius of the hole (px) |
| `optional` | `true` | Skip the step when its target is not on the page |

| `SpotlightTour` prop | Meaning |
|---|---|
| `steps`, `open` | Steps to show, and whether the guide is visible |
| `onClose(completed)` | `true` when the user pressed **Finish** on the last step |
| `startAt` | First step index (default `0`) |
| `waitForTargetMs` | How long to wait for a target that is still loading (default `1500`) |

The dashboard tour is defined in `src/components/spotlight/dashboardTour.tsx`. The placement math lives in `geometry.ts` and is unit-tested.

## Testing

```bash
npm run test:all
```

- **Unit tests** (`src/lib/__tests__/`) cover pure helpers: phone and login parsing, money and CSV, payslip Bangla text, calculation explanations, spotlight geometry.
- **Database tests** (`npm run test:db`) apply every migration to an in-process PostgreSQL (PGlite with a Supabase stub) and run every SQL test. The payroll and tax tests use golden numbers worked out by hand.

On Supabase itself, run the same SQL test files in the SQL Editor after applying migrations.

## Statutory values (read before go-live)

| Value | Source in the app | Status |
|---|---|---|
| Income-tax thresholds and slabs, salary exemption, investment rebate, minimum tax (FY 2026-27) | `tax_fiscal_years`, `tax_thresholds`, `tax_slabs` | Seeded from the Finance Act 2026 figures as published by PwC tax summaries and the press, verified 17 Oct 2026. Add a new fiscal year each July. |
| Overtime hourly divisor and multipliers, half-day deduction | Payroll settings, Time setup | The company confirms these (Labour Act s.108 / EPZ Act). |
| Provident-fund rates, vesting, interest | Statutory settings | **Placeholders.** These follow the company's fund rules; check them against the Labour Act s.264 and its 2025–2026 amendments. |
| Gratuity bands (30 days per year, 45 days after 10 years), minimum service | Statutory settings | **Placeholders** based on Labour Act s.2(10). Confirm them against the current text. |

Tax, PF and gratuity cannot be switched on without an explicit confirmation by the Admin, which is recorded with a timestamp. The **Law & policy** page (`/references`) lists every rule with its source and whether it still needs confirmation. This software does not give legal or tax advice. Have values checked by a qualified adviser.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `42P13 … no language specified` in the SQL Editor | Only part of the file was run. Paste the whole file into a fresh tab with nothing selected. |
| `Apply … first, then run this file again` | Migrations were applied out of order. Apply the named file first. |
| `23503 … permission_key … not present` | An earlier migration (for example Part 3A) was never applied. Check with the status table in memory.md. |
| `42P01 relation … does not exist` while running a test | Pull the latest test file. Tests no longer create tables mid-script. |
| API returns `PGRST205` for a table | The migration that creates it has not been applied (or the API schema cache is still refreshing). |
| `Missing VITE_SUPABASE_URL …` on start | `.env.local` is missing. Copy it from `.env.example`. |
| A deep link returns 404 after deploy | Add the SPA fallback described in [Deployment](#deployment). |
| Sign-up confirmation link opens localhost | Set Site URL and Redirect URLs in Supabase Auth. |

## Further documentation

- [memory.md](memory.md): project handbook (flows, schema, function catalog, permissions, UI map, status) and the decision log.
- [docs/Part01Architecture.md](docs/Part01Architecture.md): foundation, organization, employees.
- [docs/Part02Architecture.md](docs/Part02Architecture.md): time and attendance.
- [docs/Part03Architecture.md](docs/Part03Architecture.md): payroll, tax, provident fund, gratuity, compliance.

---

Private project. All rights reserved.
