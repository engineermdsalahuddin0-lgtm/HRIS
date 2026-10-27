# Communication module (Part 5): Notices, Helpdesk, Password requests

Design, rules, tables and RPCs: [architecture.md](architecture.md). Source spec: `docs/Part05Architecture.md`
Module 15 (features and fields only). Status: **C1–C3 built (backend + UI), migrations not yet applied on Supabase.**

## Files

| Path | What it holds |
|---|---|
| `architecture.md` | Design + backend of all three steps (permissions, rules, tables, RPCs, UI). |
| `shared/markup.ts` | Safe markdown parser (bold, italic, lists, headings, http/mailto links), plain text, toolbar edits. |
| `shared/RichText.tsx` | `RichText` renderer (elements, never HTML) and `RichTextEditor` (textarea + toolbar). |
| `shared/FilePicker.tsx` | Multi-file picker (PDF / images) with removable chips. |
| `shared/api.ts` | `rpc`, `can` (UI permission check), app address for email links, safe file names, attachment check, `pushEmails` (asks `recruit-notify` to send the queue). |
| `notices/core/notices.ts` | Categories, shown status, reach %, form checks, datetime-local helpers. |
| `notices/data/api.ts` | Hooks for every notice RPC; save + upload + publish in one mutation. |
| `notices/components/` | `NoticeForm`, `NoticeReader` (EN / বাংলা, acknowledge), `ReceiptsModal` (reminder), `NoticeBanner` (dashboard). |
| `notices/pages/NoticesPage.tsx` | `/notices`: tabs For me / Manage. `?open=<id>` opens a notice (links in emails). |
| `helpdesk/core/helpdesk.ts` | Priorities, statuses, ticket numbers, SLA labels, setup and form checks. |
| `helpdesk/data/api.ts` | Hooks for every helpdesk RPC; file upload into `helpdesk-files`. |
| `helpdesk/components/` | `TicketForm`, `HelpdeskSetup` (categories + handlers, SLA, auto-close). |
| `helpdesk/pages/` | `HelpdeskPage` (`/helpdesk`: my / assigned / all / setup), `TicketPage` (`/helpdesk/:id`). |
| `password-requests/core/password.ts` | Temporary password suggestion (passes the login rule, no look-alike characters). |
| `password-requests/data/api.ts` | List / resolve / dismiss hooks; `askForPasswordHelp` for the login page. |
| `password-requests/components/ForgotPasswordDialog.tsx` | Login page dialog (loaded on demand). |
| `password-requests/pages/PasswordRequestsPage.tsx` | `/password-requests` (users.reset_password). |
| `*/__tests__/` | Unit tests for the pure helpers. |

## Backend files
| Step | Migration | SQL test |
|---|---|---|
| C1 Notices | `supabase/migrations/20261102000100_comm_c1_notices.sql` | `supabase/tests/comm_c1_notices_test.sql` |
| C2 Helpdesk | `supabase/migrations/20261102000200_comm_c2_helpdesk.sql` | `supabase/tests/comm_c2_helpdesk_test.sql` |
| C3 Password requests | `supabase/migrations/20261102000300_comm_c3_password_requests.sql` | `supabase/tests/comm_c3_password_requests_test.sql` |

Apply in that order in the Supabase SQL Editor, each followed by its test (expects the `ALL … PASSED` row).
No Edge Function change: emails go through the existing `recruit-notify`.

## Wired into the app
- `src/router.tsx`: `/notices`, `/helpdesk`, `/helpdesk/:id`, `/password-requests`.
- `src/components/AppLayout.tsx`: sidebar section **Communication** (Notices, Helpdesk, Password requests).
- `src/pages/DashboardPage.tsx`: lazy `NoticeBanner`. `src/pages/LoginPage.tsx`: "Forgot password? Ask HR".
- `src/pages/settings/RolesPage.tsx`: module label "Communication" for the new permissions.
