# Communication module (Part 5): Notices, Helpdesk, Password requests

Source spec: `docs/Part05Architecture.md` Module 15 (old "AIHR BD" design; only its features and fields are used,
not its Next.js / REST stack). User decisions: memory.md Part B "Part 5 Communication" (2026-10-27).
Code: this folder (file map in `README.md`). Backend: one migration per step in `supabase/migrations/`
(Supabase needs them there), one SQL test per step in `supabase/tests/`.

| Step | Migration | Test | Status |
|---|---|---|---|
| C1 Notices | `20261102000100_comm_c1_notices.sql` | `comm_c1_notices_test.sql` | built, not applied |
| C2 Helpdesk | `20261102000200_comm_c2_helpdesk.sql` | `comm_c2_helpdesk_test.sql` | built, not applied |
| C3 Password requests | `20261102000300_comm_c3_password_requests.sql` | `comm_c3_password_requests_test.sql` | built, not applied |

Same rules as every part (handbook A3, A10): closed tables, RPC only, `org_id` + composite FKs, permission check →
org-scoped load → explicit validation → write → audit, soft delete only, errors as SQLSTATE with plain messages.

---

## 1. Permissions

| Key | Module | Default roles | Meaning |
|---|---|---|---|
| `notices.manage` | communication | HR Manager (Admin implicit) | Publish to anyone; see, edit, pin, archive every notice; read receipts. |
| `notices.department` | communication | Manager | Publish only to **their own department**; edit their own notices. |
| `helpdesk.manage` | communication | HR Manager | Helpdesk setup (categories, handlers, SLA); see every ticket; assign; close. |
| `helpdesk.handle` | communication | HR Manager | May be a category handler; sees and works the tickets assigned to them. Give it to an IT role etc. |
| `users.reset_password` (exists) | security | HR Manager | Sees and resolves password requests. |

Everyone with portal access reads the notices meant for them and raises / follows their own tickets: no permission.

---

## 2. Notices (C1)

### Rules
- **Who publishes:** `notices.manage` → audience *all / departments / branches / employees*; `notices.department`
  → audience is exactly their own department (the database fills it). Managers edit only their own notices;
  `notices.manage` edits all.
- **Content:** title + body (safe markdown: `**bold**`, `*italic*`, `- list`, `## heading`, `[text](https://…)`),
  optional **Bangla** title + body; the reader switches EN / বাংলা. Optional attachment (PDF / image ≤ 10 MB).
- **Category:** general, policy_update, event, urgent, hr_notice, safety.
- **Life cycle (stored status):** draft → published → archived (no delete). **Shown status** is computed:
  draft · scheduled (publish_at in the future) · active · expired (expires_at passed) · archived.
- **Pin:** pinned active notices come first and show on the dashboard.
- **Read receipt:** the first open is recorded per employee. Managers of the notice see read / not read, %.
- **Acknowledge:** when `requires_ack` (default on for policy_update and safety) the reader presses
  "I have read and agree"; it cannot be undone. Pending acknowledgements show as a dashboard banner.
  "Send reminder" (once per 24 h) emails those who have not acknowledged.
- **Email copy:** when on, publishing queues one email per audience employee with an email address into the
  existing R5 outbox (`notifications`); the existing Edge Function `recruit-notify` sends it (no redeploy).
  If the company has no working email channel, the notice is still published and the result says so.
- **Scheduled notices** need no job: they become active when `publish_at` passes, and their email copy is queued
  the first time anyone lists notices after that (`private.release_due_notices`).
- **Audience** = active employees matching the target at read time (a new joiner of the department sees it).

### Tables
| Table | Key columns |
|---|---|
| `notices` | `org_id`, `category`, `title`, `title_bn`, `body`, `body_bn`, `audience` (all / department / branch / employees), `department_ids`, `branch_ids`, `employee_ids` (uuid[]), `pinned`, `requires_ack`, `email_copy`, `status` (draft / published / archived), `publish_at`, `expires_at`, `attachment_path`, `attachment_name`, `attachment_type`, `email_queued_at`, `last_reminded_at`, `author_employee_id`, standard meta. Standard triggers (audit, no delete). |
| `notice_reads` | `org_id`, `notice_id`, `employee_id`, `first_read_at`, `acknowledged_at` (set once). Unique (notice, employee). |
| `notifications` (R5, widened) | `applicant_id`, `job_post_id` now nullable; new `source` (recruit / notice / helpdesk), `employee_id`, `ref_id`. |

Bucket `notice-files/{org}/{notice}/{file}`: write = may edit the notice; read = may see the notice.

### RPCs
`list_notices_manage()`, `save_notice(p_id, p)`, `publish_notice(p_id, p_base_url)`, `set_notice_pin(p_id, p_pinned)`,
`archive_notice(p_id)`, `notice_receipts(p_id)`, `remind_notice_ack(p_id, p_base_url)`, `my_notices()`,
`open_notice(p_id)` (records the read), `acknowledge_notice(p_id)`, `my_notice_alerts()` (dashboard: pinned, unread,
pending acknowledgements). `claim_notifications` / `mark_notification` / `retry_notification` now also accept the
notice and helpdesk permissions.

---

## 3. Helpdesk (C2)

### Rules
- **Ticket:** subject, category, priority (low / medium / high / critical), description, attachments. Number per
  company (`#0001`). Any portal user may raise one (max 20 per day).
- **Routing:** each category has a handler (an employee whose role has `helpdesk.handle` or `helpdesk.manage`).
  A new ticket goes to that handler; without one it waits in the HR queue (unassigned, seen by `helpdesk.manage`).
  `helpdesk.manage` can reassign.
- **Visibility:** the requester (public replies only), the assignee and `helpdesk.manage` (also internal notes).
  **Confidential** categories (default: HR Query, Payroll Issue) can only be handled by someone with
  `helpdesk.manage`, so a Manager or IT handler never sees them.
- **Status:** open → in_progress → waiting (for the employee) → in_progress → resolved → closed.
  Requester on a resolved ticket: **rate 1–5** (→ closed) or **reopen** with a reason (→ in_progress).
  No action for **3 working days** → closed automatically. Closed tickets never reopen (raise a new one).
- **SLA on office hours:** office time = the company's default shift (fallback 09:00–18:00), excluding weekly off
  days and company-wide holidays, in the company time zone. Default targets (configurable):

  | Priority | First response | Resolution |
  |---|---|---|
  | Critical | 1 h | 4 h |
  | High | 4 h | 24 h |
  | Medium | 24 h | 72 h |
  | Low | 72 h | 7 days (168 h) |

  Hours mean office hours. While a ticket is **waiting** for the employee the clock stops; the paused office
  minutes are added to both due times. First response = the first public reply or status change by the handler.
  Breach is computed when read (no job needed); auto-close also runs when tickets are listed.

### Tables
| Table | Key columns |
|---|---|
| `helpdesk_settings` (1 per org) | `sla` jsonb (minutes per priority), `auto_close_days`, `next_ticket_no` |
| `helpdesk_categories` | `name`, `confidential`, `handler_employee_id`, `status`, `sort` (standard triggers) |
| `helpdesk_tickets` | `ticket_no`, `subject`, `description`, `category_id`, `priority`, `requester_employee_id`, `assignee_employee_id`, `status`, `response_due_at`, `resolution_due_at`, `first_response_at`, `waiting_since`, `paused_minutes`, `resolved_at`, `closed_at`, `closed_reason`, `rating`, `rating_comment`, `reopen_count` (audit trigger, no delete) |
| `helpdesk_messages` (append-only) | `ticket_id`, `kind` (reply / note / event), `author_employee_id`, `body`, `attachments` jsonb |

Bucket `helpdesk-files/{org}/{ticket}/{file}`: read and write = may see the ticket.

### RPCs
`create_ticket(p)`, `list_tickets(p_scope)` (mine / assigned / all; KPIs), `get_ticket(p_id)`,
`reply_ticket(p_id, p)`, `set_ticket_status(p_id, p_status, p_note)`, `assign_ticket(p_id, p_employee_id)`,
`rate_ticket(p_id, p_rating, p_comment)`, `reopen_ticket(p_id, p_reason)`, `get_helpdesk_setup()`,
`save_helpdesk_settings(p)`, `save_helpdesk_category(p_id, p)`.
Helpers: `private.office_window`, `private.add_office_minutes`, `private.office_minutes_between`,
`private.ticket_sla`, `private.auto_close_tickets`.

---

## 4. Password requests (C3)

- Login page: "Forgot password?" → enter email or mobile → `request_password_help(p_login)` (anon). The answer is
  always the same ("If this ID has an account, your HR has been told"), so it never reveals who has an account.
- Limits: 3 requests per ID per day, 10 per IP per hour (hashes only, kept 1 day). One pending request per user.
- HR (`users.reset_password`): `/password-requests` list (pending / resolved), **Reset** (sets a temporary password
  through the existing reset; the user must change it at next login) or **Dismiss** with a note.

Tables: `password_requests` (`org_id`, `user_id`, `employee_id`, `status` pending / resolved / dismissed,
`requested_at`, `resolved_at`, `resolved_by`, `note`), `private.password_request_log`.
RPCs: `request_password_help(p_login)` (anon), `list_password_requests()`, `resolve_password_request(p_id, p_password)`,
`dismiss_password_request(p_id, p_note)`.

---

## 5. UI

| Route | Who | Contents |
|---|---|---|
| `/notices` | everyone | Tab **For me** (pinned first, unread dot, EN/বাংলা, acknowledge); tab **Manage** (notices.manage / department): KPIs TOTAL · PINNED · ACTIVE · THIS MONTH, table, New notice form, receipts, reminder. |
| `/helpdesk` | everyone | Tabs **My tickets**, **Assigned to me** (handlers), **All tickets** (manage), **Setup** (manage). KPIs OPEN · IN PROGRESS · SLA BREACH · MY TICKETS · RESOLVED TODAY. New ticket form. |
| `/helpdesk/:id` | requester / assignee / manage | Thread (replies, internal notes, events), SLA bars, actions (status, assign, rate, reopen). |
| `/password-requests` | users.reset_password | KPIs PENDING · RESOLVED, table, Reset / Dismiss. |
| Login page | visitors | "Forgot password?" dialog. |
| Dashboard | everyone | Notice banner: pinned notices, unread count, acknowledgements waiting. |

Sidebar: new section **Communication** (Notices, Helpdesk, Password requests).

---

## 6. Later (not in C1–C3)
- Email to the requester when a ticket is resolved / answered, SLA breach alerts (need pg_cron or a send job).
- AI assistant: notices as Updates ("New notice") and as `kb.circulars` passages; "My tickets" as an Updates topic
  (with Part 4 AI3 / AI4).
