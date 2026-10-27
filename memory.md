Admin ID: nabidbhuia313@gmail.com 
Password: 1234Nabidbhuia
# Olympus HRIS — Project memory (handbook + decision log)

> **Every new session: read Part A fully before doing anything.** It is the single source of truth for how the
> project is built, what exists, what is applied on Supabase and what comes next. Part B explains *why*.
> After finishing any task: update the **Status board (A9)**, the relevant schema/RPC/UI sections, and add the
> decisions to Part B. Keep this file in sync with the code — it is the project's memory.

---------------------------------------------------------------------------------------------------------------------
# Part A — Handbook
---------------------------------------------------------------------------------------------------------------------

## A0. Quick start for a new session
1. Read this file (Part A, then the Part B section of the area you will touch).
2. Read the architecture doc of the part you work on: `docs/Part01Architecture.md`, `Part02Architecture.md`,
   `Part03Architecture.md` (titled "AIHR BD"; the product name is **Olympus HRIS**). User answers to the docs'
   "assumptions to confirm" are recorded in Part B and **override** the docs.
3. `git log --oneline | head -20` and `git status` to see where work stopped; read **A9a Handoff** for open items.
4. Before coding, run `npm run test:all` (unit + database tests) to confirm a green baseline.
5. **Feature tracker**: `docs/FeatureTracker.md` lists every feature as done / left. Update it after every task,
   together with A9.
6. Language: the user writes Bangla/Banglish → answer in Bangla, technical terms in English. The user wants visible
   UI early, a commit per step, and this file updated after every step.

## A1. Project at a glance
- **What**: multi-tenant SaaS HRIS for Bangladeshi companies: organization & employees, attendance (web/GPS/QR),
  leave, overtime, salary structure, payroll, platform administration (applications, subscriptions, payments).
- **Repo**: `E:\Project 04 Olympus` (git, branch `main`). `E:\Olympus` is an unrelated old prototype — ignore it.
- **Stack**: Vite + React 19 + TypeScript, Tailwind v4 (orange `primary-*`), React Router 7, TanStack React Query 5
  (server state), Zustand (session), react-hook-form + zod, lucide-react icons, recharts, `qrcode`.
  Backend = **Supabase** (Postgres + Auth + Storage). **No Next.js, no Edge Functions, no service-role key**:
  all server logic is Postgres functions.
- **Supabase project ref**: `tlvhybyattbxthoacixg`. `.env` (git-ignored) holds `VITE_SUPABASE_URL` + anon key only.
- **Super admins** (platform): `sarwar@gmail.com`, `nabidbhuia313@gmail.com` (allow-list, promoted on email confirm).

## A2. Environment and workflow rules (important)
- **No Docker; terminal DB ports are firewall-blocked.** Never `supabase db push`. The user applies each migration
  **manually in the Supabase SQL Editor** (new empty tab, nothing selected, whole file), in filename order, then runs
  the matching `supabase/tests/*.sql` (expects a final `ALL … CHECKS PASSED` row; only the last result set shows).
- HTTPS to Supabase works: probe objects with the anon key (`401 42501` = exists but closed, `404 PGRST20x` = missing).
- **Local verification**: `npm run test:db` = PGlite (in-process Postgres + pgcrypto) + `scripts/db-test/supabase-stub.sql`
  (fake `auth`, `storage`, roles) → runs **every migration and every SQL test**. `npm test` = vitest unit tests.
  `npm run test:all` = both. `npm run typecheck`, `npm run build`.
- Dev server: `npm run dev` → `http://localhost:5173` (`.claude/launch.json` name `web`). `/preview` (dev only) renders the
  app shell + dashboard with a mock Admin without login.
- **Never** create accounts or type passwords on the live Supabase from the agent; the user tests logins by hand.
- Commits: one per step, message body lists what/why, ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- The machine has **no Python** — use Node one-liners for scripted edits (watch `$$` in JS `replace()` strings).

## A3. Architecture and request flow
```
Browser (React SPA)
  ├─ supabase-js (anon key + user JWT)
  │    ├─ auth: signInWithPassword / signUp / updateUser
  │    ├─ RPC  supabase.rpc('fn', {p_...})      → public.* SECURITY DEFINER functions (all writes, most reads)
  │    ├─ views  from('xxx_v').select()          → security-barrier views with built-in row/field filtering
  │    ├─ tables from('config table')            → RLS + column grants (config/structure tables only)
  │    └─ storage buckets (signed URLs)          → storage policies call private.*_access()
Postgres
  ├─ public  : tables, views, API functions (RPC)
  ├─ private : helpers, triggers, secrets (never exposed to the API)
  └─ auth    : Supabase users (we insert logins directly for portal access)
```
- **Tenant isolation**: every business table has `org_id`; **composite FKs `(org_id, id)`** stop cross-org links; RLS
  filters by `private.current_org_id()`; protected tables are closed to API roles entirely (views/RPCs only).
- **Identity → org/role** comes from tables on every request (`org_members`), never from JWT claims, so role changes,
  revocation and org suspension apply on the next request.
- **Every RPC pattern**: `perform private.require_permission('x')` → load row with `org_id = private.current_org_id()`
  (else `P0002 'X not found'`) → validate inputs explicitly (`22023` with a user-readable message) → write → audit.
- **Audit**: generic trigger `private.audit_row_change()` on business tables + explicit `private.write_audit(...)` for
  named events. `audit_logs` is append-only (even for the DB owner); NID and payment numbers are masked/stripped.
- **Soft delete only**: `private.prevent_delete()`; status columns instead of deletes.
- **Locks / flags**: "transaction-local flag" pattern (`set_config('olympus.x','on',true)` then off) lets one RPC do a
  guarded change (structure deactivation, audit purge, payroll payment marking).
- **Errors**: SQLSTATE `22023` invalid input, `23502` missing value, `23505` duplicate, `23514` rule broken,
  `23P01` overlap, `42501` not allowed, `P0002` not found. Frontend `errorMessage()` (`src/lib/identity.ts`) shows our
  RAISE messages and turns Postgres internals into plain sentences — never leak schema names.

## A4. Main flows (business)
1. **Company onboarding**: visitor → landing `/` → `/register` (company + admin account in one form; company data sent as
   sign-up metadata) → trigger creates a pending `org_signup_requests` row → applicant confirms email → super admin
   accepts (`approve_org_signup_request`: creates org with random immutable 6-digit `org_code`, default roles, grades,
   field access, time/leave/overtime/payroll defaults, TRIAL subscription, applicant = Admin with an employee row) or
   rejects with remarks → applicant logs in → `/onboarding` shows status until approved.
2. **Login**: one field (email or BD mobile) + password; generic error "ID or password is wrong"; first login with a
   company-issued password forces `/change-password`.
3. **Org setup** (Admin/HR): Organization → branches/offices/departments/designations(+grade)/operations; Time setup →
   shifts, roster, holidays, leave types, overtime policy, work rules (law, weekly off, late policy), geofences/QR;
   Salary structure → components/templates; Payroll settings; Roles & access → permissions + field ticks.
4. **Employee lifecycle**: Add employee (2 steps) → card ID auto/custom → set starting pay → give portal access (login
   created in SQL, forced password change) → transfer/promote (history) → reporting lines → deactivate (revokes login,
   closes lines) / reactivate.
5. **Daily attendance**: employee checks in/out on `/attendance/me` (browser GPS or office QR) → raw punch (immutable) →
   engine rebuilds the day (present/late/absent/half day/early out, night shifts, overtime record) → HR fixes with
   reason (override punches) → daily close (pg_cron later; now "Close / rebuild day").
6. **Requests**: leave (balance reserved → manager/HR approves → attendance on_leave), overtime approval, shift swaps
   (colleague accepts → manager approves → override roster), breaks.
7. **Pay changes**: increment request (HR) → approval by someone else (Admin) → new pay version; back-dated → arrears.
   Bonuses, loans/advances, payment accounts (encrypted).
8. **Monthly payroll**: HR creates run (month, scope) → calculate → review → Admin approves (preparer cannot) → payment
   sheets (CSV per method, export audited) → mark batches paid → lock (also locks the month's attendance/leave/OT).
   Fix after approval = reopen (reason) or adjustment in an open month. Employees see payslips (EN/বাংলা, print to PDF).
9. **Platform admin**: `/platform` status dashboard → applications (accept / reject with remarks) → organization details
   (employee volume, subscription, payments; activate/deactivate with reason; record invoices/payments manually).

## A5. Data schema (by module) — `public` unless noted
Conventions: `id uuid pk`, `org_id`, `created_at/updated_at/created_by/updated_by`, `status`; money `numeric(12,2)`.

**Foundation & identity** (Step 1–2)
- `organizations` (org_code 6-digit immutable, name, status active|suspended|inactive, timezone, card_id_mode/length)
- `user_profiles` (id = auth user, email, phone +880…, full_name, status, must_change_password, last_login_at)
- `org_members` (user_id, org_id, role_id, employee_id, status) — one active membership per user
- `roles` (system_key admin|hr_manager|manager|employee|null, name, status), `permissions` (catalog),
  `role_permissions`, `role_field_access` (role, resource, field_key, can_view, can_edit), `field_catalog`
- `platform_admins`, `private.platform_admin_allowlist`, `org_signup_requests` (applicant, org details, status,
  review_note, organization_id), `audit_logs` (append-only)

**Organization & employees** (Steps 3–9)
- `grades` (code EM0–4 / MS0–2 / OWNER01–02, category, level = seniority), `departments`, `designations`
  (department_id + grade_id), `branches`, `offices` (branch_id), `operations`, `office_operations`
- `employees` (card_id, personal fields, join_date, exit_date, employment_type, status active|inactive|terminated,
  department/designation/branch/office/operation, user_id) — **closed table**, read via `employees_v` (field masking)
- `employee_sensitive` (nid_number), `employee_nominees`, `employment_history` (append-only events with from/to json),
  `reporting_lines` (manager per line type, start/end dates)

**Time & attendance** (Part 2)
- `org_work_settings` (labor_regime bd_labour_act|bd_epz_labour_act, weekly_off_days, default_shift_id, month_days=30,
  late_deduction_mode/lates_per_deduction/late_deduction_days/late_amount_per_late, qr_rotation_seconds, require_location)
- `shifts` (times, grace/windows, half-day threshold, auto_checkout), `shift_rosters` (date range, is_override),
  `holidays`, `leave_types`, `leave_balances`, `leave_requests`, `overtime_policy`, `period_locks`
- `geofences`, `qr_checkin_codes` (hash only), `qr_code_uses`, `attendance_punches` (immutable raw),
  `attendance_records` (derived per employee/day), `break_records`, `overtime_records` (minutes, day_type, multiplier,
  status pending|approved|rejected, locked), `shift_swaps`
- Views: `attendance_v`, `attendance_punches_v`, `overtime_v`, `leave_requests_v`, `shift_swaps_v`, `break_records_v`
- Storage buckets: `employee-files/{org}/{employee}/{photo|signature|nid}`, `org-assets/{org}/logo`

**Salary structure** (Part 3A) — closed tables, views + RPCs
- `payroll_settings` (deduct_base, ot_rate_basis, ot_hourly_divisor 208*, pay_weekly_off, pay_holidays,
  half_day_deduction_percent, unpaid_leave_base, net_rounding, negative_net_rule, payslip_release, large_change_percent,
  statutory_confirmed_at, auto_tds/pf_enabled/gratuity_enabled for 3C)
- `salary_components` (kind earning|deduction, calc fixed|percent_of_basic|percent_of_gross, is_basic),
  `salary_templates` + `salary_template_lines`
- `employee_compensation` (versioned: effective_from/to, basic, gross, change_type) + `employee_compensation_lines`
  (snapshot), `salary_increments` (maker-checker, arrears_slip_id), `bonuses` + `bonus_eligibility`,
  `employee_deductions` (loan/advance/other: total, installment, start_month, remaining, status),
  `employee_payment_accounts` (bank/mobile_wallet/cash; numbers encrypted, last4 for masking),
  `private.app_secrets` (encryption key)
- Views: `employee_pay_v`, `salary_increments_v`, `employee_deductions_v`, `payment_accounts_v`

**Payroll engine** (Part 3B) — closed tables, RPCs only
- `payroll_runs` (period_month, scope all|branch|department, status draft|calculated|reviewed|approved|paid|locked|
  cancelled, inputs_fingerprint, prepared/reviewed/approved/locked by+at, totals, run_warnings)
- `payroll_slips` (one per employee per month: compensation_id, monthly gross, employed/payable days, absent/half/
  unpaid-leave days, late_count, OT minutes, gross_earnings, total_deductions, net, carry_forward_out, payment account,
  payment_status, warnings, has_blocker)
- `payroll_slip_lines` (direction earning|deduction, line_type, code, label, base, rate, quantity, amount, source)
- `payroll_adjustments` (apply_month, direction, amount, reason, status pending|approved|rejected|applied|cancelled)
- `payment_batches` (per run & method, total, status generated|exported|paid, reference)

**Tax, PF, gratuity (Part 3C)** — closed tables, RPCs only
- `statutory_references` (global: key, category law|company_policy|company_setting, area, title(+bn), law_name, section,
  summary(+bn), source_url, verified_on, status verified|needs_confirmation) — every explained number links here by key
- `tax_fiscal_years` (global: code '2026-27', exempt divisor/cap, rebate %/cap, minimum tax), `tax_thresholds`, `tax_slabs`
- `tax_profiles` (TIN 12 digits, taxpayer_type, is_new_taxpayer, parent_of_disabled, declared_investment), `tds_ledger`
  (posted at lock; challan_reference/date, status posted|deposited)
- `pf_settings` (rates, basis, min service, interest, vesting jsonb, is_recognised, confirmed_at), `pf_members`, `pf_ledger` (append-only)
- `gratuity_settings` (basis, min service, partial_year_months, bands jsonb, provision_enabled), `gratuity_provisions` (append-only)
- payroll_slips + taxable_earnings, tds_preview, employer_pf, tax_detail jsonb; slip line types + 'pf' (PF_EE), 'tax' (TDS)
- payroll_settings + tds_apply_minimum_tax, tds_confirmed_at/by (switches auto_tds/pf_enabled/gratuity_enabled from 3A)

**Onboarding R1 — workforce** (schema in `src/onboarding-process/architecture.md` §5)
- `workforce_settings`, `department_workforce`, `headcount_plans`, `workload_inputs`, `workload_snapshots`,
  `vacancies`, `vacancy_events`; trigger on `employees` drafts a replacement when a planned position holder leaves

**Onboarding R2 — job posts** (schema in `src/onboarding-process/architecture.md` §5)
- `job_profiles` (one per designation, versioned), `job_posts` (one per approved vacancy, keeps a profile copy),
  `applicants` (own audit trigger: ids/status/changed field names only, no personal data), `applicant_events`,
  `private.apply_log` (rate limit hashes); private bucket `recruit-cvs/{org}/{post}/{applicant}.pdf|docx`;
  schema `policy_checks` holds only `recruit_cv_pending` (anon storage policy) — anon never gets `private`

**Onboarding R3 — screening** (schema in architecture.md §5)
- `recruit_settings` (cv_mode basic|ai), `job_posts.cv_mode`, `org_integrations` (AI key encrypted, last4, model),
  `applicant_profiles` (CV markdown, facts + sources, ATS figures, gate; no row audit), `applicant_decisions`
  (append-only), `question_bank` (per designation), `question_papers` + `paper_questions` (per post, lockable)

**Onboarding R4 — tests & interviews** (schema in architecture.md §5)
- `assessment_invites` (token sha-256, shuffled order, server deadline), `assessment_answers`, `assessment_results`
  (by section), `written_marks`, `interview_schedules` (panel 1–4, due_by, prev_status)

**Onboarding R5 — messages & interviews** (schema in architecture.md §5)
- `org_messaging` (email Resend / SMS gateway, keys encrypted), `message_templates`, `notifications` (outbox, no
  audit), `preinterview_forms` (token), `interview_scores` (5 × 1–5, recommendation)

**Onboarding R6 + R7 — offers & joining** (schema in architecture.md §5)
- `candidate_decisions`, `offers` (maker-checker), `prehire_records` (NID / account encrypted, photo in
  `prehire-files`), `onboarding_cases` / `onboarding_tasks` / `onboarding_documents` (scans in `onboarding-docs`),
  `joining_feedback` (named); `applicants.employee_id_joined`

**Performance (manual scoring demo)**
- `performance_cycles` (draft|open|closed), `performance_criteria` (weight, sum 100), `performance_reviews` (one per
  cycle+employee; draft|submitted|acknowledged, overall_score, rating), `performance_scores` (1-5 + comment)

**Communication C1–C3** (Part 5, design in `src/communication/architecture.md`)
- `notices` (category, title(+bn), body(+bn) safe markdown, audience all|department|branch|employees + id arrays, pinned,
  requires_ack, email_copy, status draft|published|archived, publish_at, expires_at, attachment, email_queued_at,
  last_reminded_at), `notice_reads` (first_read_at, acknowledged_at set once); bucket `notice-files/{org}/{notice}/…`
- `notifications` (R5 outbox) widened: applicant_id / job_post_id nullable, `source` recruit|notice|helpdesk,
  `employee_id`, `ref_id`
- `helpdesk_settings` (sla jsonb minutes per priority, auto_close_days, next_ticket_no), `helpdesk_categories`
  (confidential, handler_employee_id), `helpdesk_tickets` (ticket_no, status open|in_progress|waiting|resolved|closed,
  due times, first_response_at, waiting_since, paused_minutes, rating, reopen_count), `helpdesk_messages`
  (reply|note|event, append-only); bucket `helpdesk-files`
- `password_requests` (pending|resolved|dismissed, masked login_hint), `private.password_request_log` (hashes, 1 day)

**AI assistant (Part 4, AI1–AI6)** — design `docs/Part04Architecture.md` §12, code `src/AIassistant/`
- `assistant_settings` (enabled, name, language_mode, hyper jsonb, monthly_token_cap, retention_days), `assistant_topics`
  (global, incl. `kb.app_guide`), `assistant_role_settings` (per role: enabled, daily_limit, greeting, suggestions, notice,
  not_allowed_message), `assistant_role_topics` (the matrix), `assistant_resources` (source upload|dms, hash, topic,
  audience_role_ids, version, status uploading|processing|ready|failed|archived, processed_through, embedding_model),
  `assistant_guide_articles` (global help per route: needs_any_of, tour_targets), `assistant_chunks` (per-company vector
  store: vector(1024) HNSW + tsvector, embedding_model), `assistant_conversations`, `assistant_messages`, `assistant_query_log`
- `org_integrations` new kinds `assistant_chat` (anthropic|openai|google) and `assistant_embed` (openai|google|voyage);
  bucket `assistant-resources/{org}/{resource}/v{n}.{ext}`; extension `vector` (PGlite: `@electric-sql/pglite-pgvector`)

**DMS (D1, `src/DMS/schema.md` "As built")**
- Catalog (global): `dms_iso_profiles`, `dms_catalog_folders` (base when `profile_code` null), `dms_catalog_doc_types`
  (codes unique; `expiry_default` fiscal_year_end = 30 June). Company: `dms_settings` (profiles[], no_iso),
  `dms_folders` (base|iso|custom, enabled), `dms_doc_types`, `dms_code_sequences` (org, dept code, type code),
  `dms_documents` (doc_code, folder_id ≠ naming, classification, scope, restricted_role_ids, fields, expiry,
  lifecycle pending|published|archived|cancelled), `dms_versions` (uploading|current|superseded|cancelled, hash unique,
  own expiry/fields), `dms_access_log`; bucket `dms-documents/{org}/{doc}/v{n}.{ext}`; read rule `private.dms_can_read`

**Platform / SaaS**
- `platform_plans` (TRIAL/BASIC/PRO/ENTERPRISE, price_per_employee null = contact sales, max_employees, features)
- `org_subscriptions` (one per org: plan, status trial|active|past_due|suspended|cancelled|expired, seats, price,
  period end, trial end), `org_payments` (period, amount, due_date, status due|paid|overdue|waived|refunded, method, ref)

## A6. RPC catalog (public functions the UI calls)
- **Session/login**: `get_my_context`, `record_login`, `complete_password_change`
- **Applications/platform**: `submit_org_signup_request`, `cancel_org_signup_request`, `approve_org_signup_request`,
  `reject_org_signup_request`, `get_public_plans` (anon), `platform_overview`, `platform_list_applications`,
  `platform_organization_details`, `platform_set_organization_status`, `platform_update_subscription`,
  `platform_record_payment`, `platform_update_payment`
- **Roles**: `set_role_permissions`, `set_role_field_access`
- **Employees**: `create_employee`, `update_employee`, `get_employee_stats`, `get_employee_profile`, `transfer_employee`,
  `set_reporting_line`, `grant_portal_access`, `revoke_portal_access`, `change_portal_role`, `reset_user_password`,
  `deactivate_employee`, `reactivate_employee`
- **Structure**: `get_deactivation_impact`, `deactivate_branch|office|department|designation`
- **Audit/dashboard**: `list_audit_logs`, `get_audit_filter_options`, `get_dashboard_stats`
- **Time config**: `apply_labor_regime_defaults`, `set_period_lock`
- **Attendance**: `punch`, `manual_punch`, `adjust_attendance`, `issue_qr_code`, `run_daily_close`, `rebuild_attendance`,
  `get_reconciliation`, `get_attendance_summary`, `get_my_today`, `list_colleagues`
- **Requests**: `get_leave_balances`, `request_leave`, `decide_leave`, `cancel_leave`, `run_leave_rollover`,
  `decide_overtime`, `add_manual_overtime`, `start_break`, `end_break`, `request_shift_swap`, `respond_shift_swap`,
  `decide_shift_swap`, `cancel_shift_swap`
- **Salary (3A)**: `save_salary_template`, `preview_salary`, `set_initial_compensation`, `request_increment`,
  `decide_increment`, `cancel_increment`, `get_increment_arrears`, `get_employee_compensation`, `save_bonus`,
  `get_bonus_preview`, `create_deduction`, `cancel_deduction`, `save_payment_account`, `reveal_payment_account`,
  `confirm_payroll_statutory_values`, `get_compensation_stats`
- **Payroll (3B)**: `create_payroll_run`, `calculate_payroll_run`, `review_payroll_run`, `approve_payroll_run`,
  `reopen_payroll_run`, `cancel_payroll_run`, `mark_payment_batch_paid`, `lock_payroll_run`,
  `create_payroll_adjustment`, `decide_payroll_adjustment`, `cancel_payroll_adjustment`, `list_payroll_runs`,
  `get_payroll_run`, `get_payslip`, `list_my_payslips`, `list_payroll_adjustments`, `get_payment_sheet`
- **Tax/PF/gratuity (3C)**: `list_statutory_references`, `get_tax_tables`, `preview_tax`, `get_statutory_settings`,
  `save_statutory_settings` (needs confirm=true to switch on), `list_tax_profiles`, `save_tax_profile`, `list_tds_ledger`,
  `set_tds_challan`, `get_run_statutory_summary`, `list_pf_members`, `set_pf_membership`, `get_pf_statement`,
  `preview_pf_withdrawal`, `post_pf_interest`, `preview_gratuity`, `list_gratuity_liability`; `lock_payroll_run` now wraps
  `private.lock_payroll_run_core` and posts the TDS / PF / gratuity ledgers
- **Onboarding R1 (workforce)**: `save_workforce_settings`, `save_department_workforce`, `save_headcount_plan`,
  `save_workload_inputs`, `build_workload_snapshots`, `get_workforce_dashboard`, `list_vacancies`, `draft_vacancy`,
  `review_vacancy`, `decide_vacancy`, `cancel_vacancy` — details in `src/onboarding-process/architecture.md` §7
- **Onboarding R2 (job posts)**: `list_job_profiles`, `save_job_profile`, `list_job_posts`, `create_job_post_from_vacancy`,
  `get_job_post`, `update_job_post`, `publish_job_post`, `close_job_post`, `add_applicants`, `attach_applicant_cv`,
  `list_applicants`; anon: `get_public_careers`, `get_public_job_post`, `submit_job_application`, `confirm_cv_upload`
- **Onboarding R3 (screening)**: `get/save_recruit_settings`, `save/remove_ai_integration`, `ai_test_context`,
  `record_ai_test`, `service_ai_key` (service_role only), `set_post_cv_mode`, `claim_cv_reads`, `save_cv_read`,
  `save_applicant_profile`, `move_applicants`, `get_question_papers`, `save_question_paper`, `delete_question_paper`,
  `question_ai_context`; R2 `list_job_posts` / `get_job_post` / `list_applicants` redefined for Managers.
  Edge Function `supabase/functions/recruit-ai` (read_cvs, draft_questions, test_key)
- **Onboarding R4 (tests & interviews)**: `get_assessment_board`, `invite_to_test`, `cancel_test_invite`,
  `save_written_marks`, `list_interviewer_options`, `propose_interview_slot`, `save_interview`, `cancel_interview`,
  `move_applicants` (redefined); anon by token: `get_test`, `start_test`, `save_test_answer`, `submit_test`
- **Onboarding R5 (messages & interviews)**: `get_messaging_settings`, `save/remove_messaging_channel`,
  `save_message_template`, `messaging_test_context`, `record_messaging_test`, `service_messaging_config` (service_role),
  `list_notifications`, `claim_notifications`, `mark_notification`, `retry_notification`, `invite_to_test` (5 args now),
  `send_interview_invite`, anon `get/submit_preinterview_form`, `list_my_interviews`, `get_interviewer_kit`,
  `submit_interview_score`, `get_candidate_results`, `get_assessment_board` (re-created). Edge Function `recruit-notify`
- **Onboarding R6 + R7**: `decide_candidate`, `get_offer_context`, `prepare_offer`, `decide_offer` (offer.approve),
  `send_offer`, `withdraw_offer`, `list_offers`, `get_prehire`, `verify_prehire`, anon `get_offer` / `respond_offer` /
  `start_prejoining_photo` / `submit_prejoining`; `convert_to_employee`, `get_onboarding_case`, `list_onboarding_cases`,
  `set_onboarding_task`, `mark_document_printed`, `attach_signed_document`, `complete_onboarding`, `get_purge_plan`,
  `purge_post_applicants`, anon `get/submit_joining_feedback`
- **Communication (C1–C3)**: notices `save_notice`, `publish_notice`, `set_notice_pin`, `archive_notice`,
  `list_notices_manage`, `notice_receipts`, `remind_notice_ack`, `my_notices`, `open_notice`, `acknowledge_notice`,
  `my_notice_alerts`; outbox `claim_notifications` / `mark_notification` now also for notice publishers
  (`private.can_send_messages`); helpdesk `list_helpdesk_categories`, `create_ticket`, `list_tickets(scope)`, `get_ticket`,
  `reply_ticket`, `set_ticket_status`, `assign_ticket`, `rate_ticket`, `reopen_ticket`, `get_helpdesk_setup`,
  `save_helpdesk_settings`, `save_helpdesk_category`; office time `private.add_office_minutes`,
  `office_minutes_between`, `office_days_between`; password `request_password_help` (anon), `list_password_requests`,
  `resolve_password_request`, `dismiss_password_request`
- **AI assistant**: setup `get_assistant_setup`, `save_assistant_settings`, `set_assistant_delegation` (Admin),
  `save_assistant_key`, `record_assistant_key_test`, `remove_assistant_key`, `save_assistant_hyper`,
  `save_assistant_role_matrix`, `save_assistant_role_messages`; resources `register_assistant_resource`,
  `confirm_assistant_upload`, `update_assistant_resource`, `list_assistant_resources`; widget `assistant_my_config`,
  `assistant_updates`, `assistant_prepare`, `assistant_record_answer`, `assistant_feedback`, `assistant_history`,
  `assistant_resource_path`, `assistant_preview_as_role`; usage `get_assistant_usage`, `run_assistant_purge`;
  service_role only `service_assistant_keys`, `service_assistant_resource`, `service_save_assistant_chunks`,
  `service_fail_assistant_resource`, `service_guide_articles`, `service_save_guide_chunks`.
  Edge Function `supabase/functions/assistant` (test_key, ingest, index_guide, ask)
- **DMS (D1)**: `get_dms_setup`, `set_dms_profiles`, `save_dms_folder`, `save_dms_doc_type`, `get_dms_library`,
  `list_dms_documents`, `get_dms_document`, `dms_next_code`, `dms_register_upload`, `dms_confirm_upload`,
  `dms_cancel_upload`, `update_dms_document`, `archive_dms_document`, `dms_file_path`, `get_dms_overview`
- **Performance**: `save_performance_cycle`, `set_performance_cycle_status`, `list_performance_cycles`, `get_performance_cycle`,
  `get_performance_review`, `save_performance_review`, `list_my_performance_reviews`, `acknowledge_performance_review`
- 3C engine hook: `private.calculate_slip` = `calculate_slip_core` (3B) + `apply_statutory_lines` (PF, TDS) + `finalize_slip_totals`;
  `payroll_inputs_fingerprint` = core + tax profiles, PF members/settings, earlier FY slips; `compute_annual_tax` returns the working json.
- Key private helpers: `current_org_id`, `current_employee_id`, `current_role_id`, `has_permission`, `is_org_admin`,
  `is_platform_admin`, `require_permission`, `viewer`, `time_viewer`, `money_viewer`, `team_employee_ids`,
  `can_see_time`, `write_audit`, `attach_standard_triggers`, `rebuild_attendance_day`, `record_punch`,
  `resolve_salary`, `create_compensation`, `compensation_on`, `calculate_slip`, `payroll_inputs_fingerprint`,
  `seed_org_defaults` (calls the per-part seed functions for new orgs).

## A7. Permissions and default roles
- **Admin** (`system_key = admin`) implicitly has every permission; its set cannot be edited. **Admin-only** (never
  grantable): `roles.manage`, `settings.manage`, `audit.view`, `attendance.lock_period`.
- Catalog by module:
  - organization: `org.view`, `org.manage`
  - employees: `employees.view|create|edit|deactivate|transfer|reporting|portal_access`
  - security: `users.reset_password`, `roles.view`, `roles.manage`, `audit.view`; settings: `settings.manage`
  - attendance: `attendance.view_own|view_team|view_all|adjust|qr_display|settings|lock_period`, `shifts.manage`,
    `roster.manage`, `holidays.manage`, `swaps.approve`, `geofences.manage`
  - leave: `leave.request|approve|manage_types|view_all`; overtime: `overtime.view|approve|manage_policy`
  - payroll: `compensation.view|edit`, `increments.approve`, `bonuses.manage`, `deductions.manage`,
    `payroll_settings.manage`, `payment_accounts.view|edit`, `payroll.view_own|prepare|review|approve|reopen|lock`,
    `payment.export`
  - 3C: `tax.view_profiles`, `tax.manage`, `pf.manage`, `gratuity.manage` (HR default all four)
  - performance: `performance.manage` (HR), `performance.review` (HR + Manager, own team only)
  - assistant: `assistant.manage` (Admin; HR Manager only via the Admin hand-over, a trigger refuses other roles),
    `assistant.view_usage` (Admin only)
  - communication: `notices.manage` (HR), `notices.department` (Manager: own department only), `helpdesk.manage` (HR),
    `helpdesk.handle` (HR; give to IT etc.); password requests use the existing `users.reset_password`
  - dms: `dms.manage` (HR), `dms.upload` (HR, Manager: own department), `dms.upload_all` (HR),
    `dms.view_confidential` (HR, Manager); readers need no permission (read rule in the database)
- **HR Manager** default: org view/manage, all employees.*, users.reset_password, roles.view, all attendance except
  lock_period, shifts/roster/holidays/swaps/geofences, all leave, all overtime, compensation view/edit, bonuses,
  deductions, payment accounts view/edit, payroll.view_own/prepare/review. **Not**: increments.approve,
  payroll_settings.manage, payroll.approve/reopen/lock, payment.export (Admin until ticked).
- **Manager** default: org.view, employees.view, attendance.view_own/view_team, swaps.approve, leave.request/approve,
  overtime.view/approve, payroll.view_own. Sees **no salary**.
- **Employee** default: attendance.view_own, leave.request, payroll.view_own (+ own profile always).
- Field-level access: `role_field_access` ticks per role (HR all; Manager phone/email/join date/type/gender view;
  Employee = which own fields they may edit). People always see their whole own record.
- Maker-checker everywhere money/approval is involved: increments, payroll runs, payroll adjustments; nobody approves
  their own leave/overtime/swap/attendance fix/pay.

## A8. UI map (routes → pages)
- Shell: `src/components/AppLayout.tsx` (hover-expand icon rail with company logo, sections Team/Payroll/Setup/Platform,
  mobile drawer, top bar with `UserMenu` dropdown), guards in `src/components/guards.tsx`, routes in `src/router.tsx`
  (lazy-loaded pages; `guarded(permission|any-of, path, page)`), session in `src/stores/session.ts`.
- Public: `/` landing (signed out) · `/register` · `/login` · `/change-password` · `/onboarding`
- Everyone: `/` dashboard (real stats; personal home without employees.view) · `/me` → own profile ·
  `/attendance/me` · `/attendance/qr?c=` · `/leave` · `/payslips`
- Team/HR: `/attendance` (daily, monthly summary, calendar, reconciliation, swaps) · `/overtime` · `/employees`,
  `/employees/new`, `/employees/:id` (tabs Personal, History, Reporting, Financial; dialogs edit, transfer, reporting,
  status, portal, ID card; files photo/signature/NID)
- Payroll: `/payroll` (runs + adjustments) · `/payroll/runs/:id` · `/compensation` (pay, increments, bonuses, loans) ·
  `/salary` (templates, components) · `/settings/payroll`
- Setup: `/organization` (6 tabs) · `/time` (shifts, roster, holidays, leave types, OT policy, work rules, geofences/QR) ·
  `/attendance/qr-display/:officeId` · `/settings/roles` · `/audit` · `/settings` (org, logo, card ID policy)
- 3C: `/tax` (calculator / tax tables / profiles / TDS ledger) · `/pf` · `/gratuity` · `/settings/statutory` · `/references`;
  payslip dialog has a "How it was calculated" view (pages/payroll/CalculationExplainer.tsx); run page shows TDS / PF columns
- Performance: `/performance` (cycles, criteria weights, scoring dialog) · `/my-reviews` (everyone; acknowledge)
- Hiring (onboarding process): `/workforce` (overview, output data, plan & methods, settings, demo cases) ·
  `/vacancies` (review → approve) · `/job-posts` (ready / posts / job profiles) · `/job-posts/:id` (editor, text +
  poster PNG with QR, applicants table → profile modal) · public `/careers/:orgCode[/:slug]` (apply form) · dev
  `/preview/workforce`, `/preview/job-post`; R3: post page tabs Applicants (score, read CVs, shortlist) / Question
  papers, `/settings/recruitment` (CV mode, Claude key); R4: post tab Tests & interviews (links, scores, written
  marks, interview dialog with "Propose a time"), public `/t/:token` test page; R5: post tabs Results / Messages,
  `/my-interviews` + kit (every employee), public `/f/:token` form, email/SMS/templates on Recruitment settings;
  R6/R7: Results decisions, post tab Offers & joining (offer, form check, make employee, joining checklist + documents,
  close hiring), public `/offer/:token` and `/joining-feedback/:token`; core logic in `src/onboarding-process/`
- Visual helpers: `lib/calculationGuide.ts` (explainLine, taxSteps, weightedScore…), `components/references.tsx`
  (SourceBadge, ReferenceChips, ReferenceCard), `components/calcVisuals.tsx` (TaxBreakdown, SlabBar, NetFlow) — plain HTML bars
- AI assistant (Part 4, real data, `src/AIassistant/`): floating `AssistantWidget` in AppLayout (Updates / Ask with
  citations, page links, Show me spotlight; error alerts in `components/ui.tsx` offer "Ask the assistant" via
  `bridge.ts`) · `/settings/assistant` (assistant.manage) tabs Overview / API keys / Resources / Model settings /
  Role access / Messages / Test as role / Usage (Admin)
- DMS (`src/DMS/`): `/documents` tabs Overview (steps, counts, licences by expiry, upload, folders, naming card) /
  Library (folder tree, search, upload, new folder) / Expiry & renewals / Setup (dms.manage); `?tab= ?folder= ?doc=`
- Communication (`src/communication/`, sidebar section Communication): `/notices` (For me / Manage, `?open=<id>`) ·
  `/helpdesk` (my / assigned / all / setup) · `/helpdesk/:id` · `/password-requests` · dashboard `NoticeBanner` ·
  login page "Forgot password? Ask HR"
- Platform: `/platform` · `/platform/applications` · `/platform/organizations/:id`
- Data hooks: `src/lib/hr.ts` (Part 1), `time.ts` (Part 2), `files.ts` (storage), `payroll.ts` (3A + money helpers),
  `payrollRuns.ts` (3B + CSV), `payslipText.ts` (EN/BN), `platform.ts`, `identity.ts` (phone/login/errors),
  `options.ts` (labels/dates), `appContext.tsx` (`useMyContext` real or preview mock)
- UI kit: `components/ui.tsx` (Button, Input, Card, Alert, Badge, Spinner, PageLoader, EmptyState, AuthShell),
  `components/kit.tsx` (Select, Textarea, Modal on `<dialog>`, Tabs, Switch, Checkbox, Table th/td, StatusBadge,
  PageHeader); generic `pages/organization/StructureTab.tsx` (config-driven CRUD table + form).
- Design rules: orange primary, rounded-2xl cards, every page has loading/empty/error states, actions hidden when the
  role lacks the permission (the DB still enforces), mobile-first (no horizontal scroll at 375 px), Bangla where
  user-facing documents need it (payslip).

## A9. Status board (keep this current)
| Part / step | Migration(s) | On Supabase | Test file (checks) |
|---|---|---|---|
| Step 1 foundation | `20261013000100…0300` | ✅ applied, passed | `step1_foundation_test.sql` (17) |
| Step 2 login | `20261013000400_login` | ✅ applied | — |
| Steps 3–9 org/employees | `20261014000100…0700` | ✅ applied, passed | `step3_9_acceptance_test.sql` (19) |
| Platform admins allow-list | `20261015000100_platform_admins` | ✅ applied | (in platform test) |
| Part 2 time & attendance + files | `20261016000100…0400` | ✅ applied, passed | `part2_attendance_test.sql` (21) |
| Part 3A salary structure | `20261017000100_part3a_salary_structure` | ✅ applied 2026-10-17 | `part3a_salary_structure_test.sql` (11) |
| Platform SaaS / landing | `20261018000100_platform_saas` | ✅ applied, passed | `platform_saas_test.sql` (7) |
| **Part 3C tax/PF/gratuity + refs** | `20261020000100_part3c_tax_pf_gratuity` | ✅ applied (R1 ran on top of it; own test run not confirmed) | `part3c_tax_pf_gratuity_pms_test.sql` (14, covers PMS too) |
| **PMS manual scoring demo** | `20261020000200_pms_manual_scoring` | ✅ applied (R1 guard needs it; test not confirmed) | (same test) |
| **Part 3B payroll engine** | `20261019000100_part3b_payroll_engine` | ✅ applied, passed 2026-10-17 | `part3b_payroll_engine_test.sql` (12) |
| **Onboarding R1 workforce** | `20261025000100_recruit_r1_workforce` | ✅ applied, passed 2026-10-25 | `recruit_r1_workforce_test.sql` (9) |
| **Onboarding R2 job posts** | `20261026000100_recruit_r2_job_posts` | ✅ applied, passed 2026-10-25 | `recruit_r2_job_posts_test.sql` (12) |
| **Onboarding R3 screening** | `20261027000100_recruit_r3_screening` | ✅ applied (anon probe 2026-10-25: `claim_cv_reads` exists; test run not confirmed); Edge Function `recruit-ai` ✅ deployed, boots (probe: "Unknown action") | `recruit_r3_screening_test.sql` (10) |
| **Onboarding R4 tests & interviews** | `20261028000100_recruit_r4_tests_interviews` | ✅ applied (anon probe 2026-10-25: `get_test` answers "This test link is not valid"; test run not confirmed) | `recruit_r4_tests_interviews_test.sql` (9) |
| **Onboarding R5 messages & interviews** | `20261029000100_recruit_r5_messages_interviews` | ✅ applied (probe 2026-10-25: `get_preinterview_form` answers; test run not confirmed); Edge Function `recruit-notify` ✅ deployed (probe: "Unknown action") | `recruit_r5_messages_interviews_test.sql` (8) |
| **Onboarding R6 offers** | `20261030000100_recruit_r6_offers` | ⏳ not applied (needs R5) | `recruit_r6_r7_offer_joining_test.sql` (9, needs R7 too) |
| **Onboarding R7 joining** | `20261031000100_recruit_r7_joining` | ⏳ not applied (needs R6) | (same test) |
| **Onboarding R6 + R7 (live)** | — | ✅ applied, `recruit_r6_r7_offer_joining_test.sql` passed on Supabase 2026-10-25 | |
| **Department organogram** | `20261101000100_organogram` | ✅ applied, `organogram_test.sql` passed on Supabase 2026-10-25 | `organogram_test.sql` (9) |
| **Organogram fix** | `20261101000200_organogram_fix_volatile` | ✅ applied (implied: test check 9 passed on Supabase 2026-10-25); `list_organogram_grades` was STABLE but seeds grades → HTTP 405 | (organogram test check 9: no STABLE public function writes) |
| **Comm C1 notices** | `20261102000100_comm_c1_notices` | ✅ applied, passed (user, 2026-10-27) | `comm_c1_notices_test.sql` (8) |
| **Comm C2 helpdesk** | `20261102000200_comm_c2_helpdesk` | ✅ applied, passed (user, 2026-10-27) | `comm_c2_helpdesk_test.sql` (6) |
| **Comm C3 password requests** | `20261102000300_comm_c3_password_requests` | ✅ applied, passed (user, 2026-10-27) | `comm_c3_password_requests_test.sql` (3) |
| **AI1 assistant foundation** | `20261103000100_assistant_ai1_foundation` | ✅ applied, passed (user, 2026-10-27) | `assistant_ai1_foundation_test.sql` (5) |
| **AI3 assistant updates** | `20261103000200_assistant_ai3_updates` | ✅ applied, passed (user, 2026-10-27) | `assistant_ai3_updates_test.sql` (3) |
| **AI4 assistant resources + guide** | `20261103000300_assistant_ai4_resources` | ✅ applied, passed (user, 2026-10-27) | `assistant_ai4_resources_test.sql` (4) |
| **AI5 assistant ask** | `20261103000400_assistant_ai5_ask` | ✅ applied, passed (user, 2026-10-27) | `assistant_ai5_ask_test.sql` (3) |
| **AI6 assistant usage** | `20261103000500_assistant_ai6_usage` | ✅ applied, passed (user, 2026-10-27) | `assistant_ai6_usage_test.sql` (3) |
| **Edge Function assistant** | `supabase/functions/assistant` | ✅ deployed (user, 2026-10-27) | ⚠️ **INCOMPLETE**: never run against a real provider (company has no API key yet); see A9a |
| **DMS D1 foundation** | `20261104000100_dms_d1_foundation` | ✅ applied, passed on Supabase (user, 2026-10-27) | `dms_d1_foundation_test.sql` (9; since D2 it switches review off for itself) |
| **DMS D2 governance** | `20261104000200_dms_d2_governance` | ⏳ not applied | `dms_d2_governance_test.sql` (8) |
| **DMS D3 ISO checklist** | `20261104000300_dms_d3_compliance` | ⏳ not applied | `dms_d3_compliance_test.sql` (3) |
- Local (2026-10-27): all 22 SQL suites pass in PGlite (with pgvector); vitest 183 tests; typecheck + build pass
  (main chunk 505 kB: chunk-boundary effect of the bundler, first-load size ~unchanged).
- **Pitfall**: PostgREST runs STABLE/IMMUTABLE functions in a read-only transaction; one that writes fails with HTTP 405
  on Supabase but passes in PGlite. A function that seeds or logs must stay VOLATILE (the organogram test lints this).
- R6 → R7 → organogram + fix are all applied.

### A9a. Handoff — where work stopped (2026-10-25, last commit `ec84577`, tree clean)
- **Finished**: recruitment/onboarding R1–R7 (full hiring cycle) + Department Organogram + interactive organogram demo.
  Handbook for all of it: `src/onboarding-process/architecture.md` (§1 status, §2 decisions 1–25, §10b organogram).
- **Latest (2026-10-27, evening): DMS D1 built** (`src/DMS/`, route `/documents`, sidebar Communication → Documents).
  Folders (base / ISO / custom), system naming `{DEPT}-{TYPE}-{SEQ}_v{n}`, duplicate refusal (hash; same type +
  department + title), versions / renewals, read rule (classification, department scope, restricted roles),
  licences by expiry with 30 June default, Setup tab. Local: 23 SQL suites, 192 unit tests, build pass; not
  browser-checked (no browser tool). Applied on Supabase and `dms_d1_foundation_test.sql` passed (user, 2026-10-27).
  **User still:** give departments a Code in Organization → Departments; try a real upload in the browser.
  Next: D2 (approval, reminders) — ask the D2 questions in `src/DMS/architecture.md` §7 first.
- **⚠️ INCOMPLETE — AI assistant live test (open item, ask the user about it each session):** C1–C3, AI1–AI6 applied
  and their tests passed on Supabase, Edge Function `assistant` deployed (all confirmed by the user 2026-10-27). Not
  done: the company must buy an API key first; then in the app: API keys → Test key → index the app guide → upload a
  policy → Test as role → ask from the widget. Provider request shapes in `supabase/functions/assistant/index.ts`
  (Anthropic / OpenAI / Gemini chat, OpenAI / Gemini / Voyage embeddings) were never run by the agent; fix whatever
  the first real test reports.
- **Earlier (2026-10-27, later)**: AI assistant backend AI1–AI6 built (commits `bc82b2f`…), revision 2 of the design
  (company keys only, app guide, page-aware, Show me, error help).
  Commit `3b5350c`: the UI shows before the backend exists. A missing RPC (PGRST202 / 404, `isBackendMissing` in
  `src/AIassistant/data/api.ts`) → widget uses `FALLBACK_CONFIG` (Updates empty, Ask says "not installed"); setup page
  uses `data/fallback.ts` with an install banner; Admin reaches it via `roles.manage`. Switches to real data by itself
  once installed. User's screenshot showed the old preview build → told to hard-refresh / restart `npm run dev`.
- **Earlier (2026-10-27)**: Part 5 Communication C1 notices, C2 helpdesk, C3 password requests built (backend + UI,
  commits `64a686e`…`84fb7c6`), local tests green. **User must apply on Supabase, in order:**
  `20261102000100_comm_c1_notices.sql` → `comm_c1_notices_test.sql`, `20261102000200_comm_c2_helpdesk.sql` →
  `comm_c2_helpdesk_test.sql`, `20261102000300_comm_c3_password_requests.sql` → `comm_c3_password_requests_test.sql`.
  Then hand test: notice with email copy (needs the email channel), a ticket through a custom "IT" role with
  helpdesk.handle, "Forgot password?" on the login page. Not browser-checked by the agent (no browser tool).
  `docs/DevelopersManual.md` is an untracked user file: not read, not committed.
- **Waiting on the user** (ask at the start of the next session, do not redo):
  1. Done 2026-10-25: `organogram_test.sql` passed on Supabase (so the fix is applied). Still to confirm in the UI that
     Organogram → Budget & slots / Grades & designations open (they gave HTTP 405 before the fix).
  2. Done 2026-10-25: `recruit_r6_r7_offer_joining_test.sql` passed on Supabase. (R3–R5 tests never run there, only probed.)
  3. Hand test with real keys: AI CV reading / question drafting (`recruit-ai`), email/SMS (`recruit-notify`).
- **Demo folder (temporary, user 2026-10-25: "pore remove kore dibo")**: `src/demo/` — browser-only demos the user will
  delete later; removal steps in `src/demo/README.md` (lines marked `DEMO` in router.tsx and AppLayout.tsx). Now holds the
  **Hiring flow demo** (`/demo/hiring-flow`, dev `/preview/hiring-flow`): R1 → R7 as one clickable story using the real core
  calculations (`flow.ts` + `flow.test.ts`). Put any new demo in this folder, not next to the real pages.
- **Known, not investigated**: `set_pf_membership` returns HTTP 400 in the browser console (Part 3C PF page).
- **Part 4 AI assistant (2026-10-27)**: design `docs/Part04Architecture.md`; **UI done on preview data** in
  `src/AIassistant/` (widget on every page, Setup → AI assistant). All decisions D1–D8 settled. Backend AI1–AI6
  (doc §11) only when the user says so ("do AI1"). `docs/Part05Architecture.md` = user's next module, untouched until
  asked. Other candidates already noted: Part 3D (hours compliance,
  grievance box, committees), final settlement module, pg_cron jobs (monthly snapshot, auto-convert on joining date,
  reminders, forgotten-post purge, daily close, audit purge), hiring funnel dashboard, PMS score for internal candidates.
- **Organogram (2026-10-25, user spec)**: separate organogram grade table (user chose it over extending pay grades);
  department budget + grade slots = the single source of sanctioned headcount (user choice), R1 re-reads it; positions
  table kept in step by triggers; offers refused when filled + offers in process would pass the budget. Details:
  architecture.md §10b and decisions 24–25.
- Probing from the terminal works over HTTPS with the anon key from `.env`: `POST {url}/rest/v1/rpc/<fn>` (missing
  function → PGRST202) and `POST {url}/functions/v1/<name>` with `{"action":"ping"}` (deployed → "Unknown action",
  missing → 404). PostgREST returns HTTP 500 for P0002 raises; the JSON message is still right.
  The R2 test's manager check was changed in R3 (managers may now read their department's posts).
- No Deno / Supabase CLI on this machine: the Edge Function is not type-checked or run locally.
- PowerShell 5.1 `Get-Content`/`Set-Content` on UTF-8 files without BOM corrupts non-ASCII (– — •): edit with the
  Edit tool or Node, never a PowerShell read-replace-write.
- PGlite stub now grants anon on `storage.objects` (as Supabase does) so the anon CV-upload policy is tested.
- Supabase blocks `delete from storage.objects` in SQL (`storage.protect_delete`, 42501), even as postgres; the
  stub now does the same. Tests that need "file removed" move the row (`update … set name = 'purge-test/…'`) instead.
- 2026-10-17: running 3B failed (23503, `compensation.view` missing) because 3A was never applied; 3B now starts
  with a guard that names the missing prerequisite. Always probe with the anon key before trusting "applied".
- **3C/PMS status (2026-10-17)**: backend done + golden-tested (commit 2154d41). FY 2026-27 tax values verified from PwC (reviewed 31 Jul 2026) + Daily Star (Finance Act 2026): threshold 400k (woman/65+ 450k, disabled/third gender 525k, freedom fighter 550k), slabs 10/15/20/25/30 on 300k/400k/500k/2M/rest, exempt min(1/3, 500k), rebate min(3% taxable, 10% investment, 750k), min tax 5,000 (new 1,000). PF/gratuity defaults are placeholders marked needs_confirmation (Labour Act 2025-26 amendments uncertain).
  UI done: src/lib/statutory.ts (hooks), src/lib/calculationGuide.ts (+tests), components/references.tsx (law/policy chips), components/calcVisuals.tsx (TaxBreakdown, SlabBar, NetFlow), payslip dialog "How it was calculated" view (pages/payroll/CalculationExplainer.tsx), run page TDS/PF columns.
  UI pages done (2026-10-17): /tax (calculator, tax tables, profiles, TDS ledger + challan), /pf, /gratuity, /settings/statutory, /references, /performance, /my-reviews. Browser-checked nav only; data pages need the migrations applied.
- **Next** (in order): hand test a payroll run (HR prepares, Admin approves) →
  **Part 3C** (tax/TDS, PF, gratuity — statutory values must come from verified sources, never memory) →
  **Part 3D** (hours compliance, grievance box with true anonymity, committees) → PMS demo (manual scoring; scope TBD).
- **Deferred**: Part 2D biometric devices, live location tracking (mobile app), meals, bank/wallet integrations,
  payment gateway for subscriptions, Supabase Vault for the encryption key.
- **Open user decisions**: see "Open decisions" at the end of Part B.

## A10. Recipe: building the next part
1. Read the part's doc section + any user answers; ask only real decisions (AskUserQuestion), record answers in Part B.
2. **Migration** `supabase/migrations/YYYYMMDDHHMMSS_partXX_name.sql`: header comment (what + rules), permissions
   insert + `seed_*` update (and run it for existing orgs), tables (org_id + composite FKs, checks, unique indexes),
   guards/triggers (`attach_standard_triggers`, append-only where history), helpers in `private`, RPCs in `public`
   (permission check → org-scoped load → explicit validation → write → audit), views with `security_barrier`,
   then privileges: `enable row level security`, `revoke all … from anon, authenticated`, grant only what is needed,
   `revoke all on function … from public, anon` + `grant execute … to authenticated`, private functions revoked.
3. **SQL test** `supabase/tests/partXX_….sql`: one transaction, fixtures via auth.users + signup + platform approval,
   switch users with `set local role authenticated` + `set_config('request.jwt.claims', …)`, read closed tables only via
   RPCs when in the authenticated role, **hand-calculated expected numbers written in comments first**, `raise notice
   'PASS …'`, final `select '==== ALL … PASSED ====' as result; rollback;`. Run `npm run test:db`.
4. **Frontend**: types + hooks in `src/lib/<area>.ts` (React Query, `invalidateQueries` after mutations), pages in
   `src/pages/<area>/`, lazy route via `guarded(...)` in `router.tsx`, nav item (`anyOf` permissions) + title in
   `AppLayout.tsx`, unit tests for pure helpers in `src/lib/__tests__/`.
5. Verify: `npm run test:all`, `npm run typecheck`, `npm run build` (no chunk > 500 kB), browser check (desktop + 375 px).
6. Commit (backend and UI separately), update **this file** (A5/A6/A8/A9 + Part B), tell the user which SQL files to
   run in the SQL Editor and what to hand test.

- **SQL test gotcha**: SQL tests must **not create tables** (temp or normal) mid-script — the Supabase SQL Editor then
  reports 42P01 "relation does not exist" on later statements (PGlite is fine). Read source tables directly, and carry
  ids/snapshots between statements as text/JSON in `set_config('t.x', …, true)` (`jsonb_to_recordset` to read back).

## A10b. Spotlight guide (onboarding tours)
- `src/components/spotlight/`: SpotlightTour (dark mask 70%, box-shadow hole, step card, keyboard, focus trap), geometry.ts (pure,
  tested), useSpotlightTour(key) (auto-open once per browser via localStorage `olympus.tour.<key>`), dashboardTour.tsx.
- Mark targets with `data-tour="…"`; bump the key version when steps change. Usage documented in README.

## A11. Code conventions
- Professional comments: a header block per migration/file explaining purpose and rules; comments explain *why*, not
  what. Meaningful names (`v_employee`, `v_deduct_daily`, `p_period_month`); no abbreviations like `x`, `tmp`.
- SQL: `set search_path = ''`, fully qualified names, `security definer` only where needed, every function's privileges
  set explicitly, money via `private.round_money` (2 decimals, half away from zero), dates in org timezone
  (`private.org_today`).
- Never trust the client: permissions, org scope, maker-checker, locks and validation all live in the database.
  Sensitive data (NID, account numbers) masked in views, encrypted at rest, stripped from audit, reveals/exports audited.
- Frontend: never show raw DB errors (use `errorMessage`), validate forms with zod for UX only, keep secrets out of
  `VITE_*`, CSV exports through `csvCell` (formula-injection safe).

---------------------------------------------------------------------------------------------------------------------
# Part B — Decision log (why things are the way they are)
---------------------------------------------------------------------------------------------------------------------

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

### Recruitment & onboarding (planned, discussion only) — user answers 2026-10-25
- **Order**: onboarding/recruitment first; **final settlement is a separate module, later**.
- Scope = full recruitment flow: workload + vacancy (Part 01) → job post from designation profile + apply channels + CV
  storage + ATS/markdown profile/report (Part 02) → objective/written tests, interview scheduling ≤ 15 days, editable
  (Part 03) → SMS with pre-interview form, interviewer kit, 1–4 panel scoring, offer/reject email + pre-joining form
  (NID, photo, nominee, bank) (Part 04) → joining-day feedback form, auto-filled documents printed and signed (Part 05).
- **Sanctioned headcount**: companies set it in the system (new headcount plan per department/designation/office + budget).
- **Vacancy**: auto-drafted (separation or overload), a person approves.
- **Workload**: link output data, not only attendance/OT; methods per department (hours / output×SMV / volume×standard
  time / staffing ratio); every formula and source shown on a (?) hover; sources verified, never from memory.
- **Module handbook: `src/onboarding-process/architecture.md`** (core code folder; SQL stays in supabase/migrations,
  Edge Functions in supabase/functions). Read it before any recruitment work; it holds schema, formulas, flow graph,
  security, the 10 demo cases and the build steps R1–R7.
- Second round of answers (2026-10-25): Claude API now + per-company API key input (Settings → Integrations);
  email now, SMS adapter coded but off; own recruitment test page (no Google Form); aptitude section, "confidence" is
  an interviewer-scored category; no CV retention after close (rejected purged, selected → employee); applicant row →
  profile modal; salary toggle per post (off = "Negotiable"); joining feedback named. Edge Functions accepted for
  AI/email/apply only; service-role key only inside Edge Functions. Approval chain still a default (HR → Admin).
- **R1 built 2026-10-25** (backend + UI; applied on Supabase and its test passed the same day). Choices made while building:
  plan per designation (no office level, no versioning — snapshots keep history); method + budget in
  `department_workforce`; capacity = one company figure × availability (roster-based later); vacancies drafted only
  from the current/previous month; demo cases are browser-only (never stored); budget/cost hidden without
  `compensation.view`; `statutory_references` gains `industry_practice` / `workforce`.
- **R2 built 2026-10-25** (applied on Supabase, test passed the same day). Choices: apply form = anon RPC + direct upload to the private bucket
  (policy allows only the returned path, 1 hour, once) + token confirm — no Edge Function yet; honeypot field and rate
  limit (10 per network / 5 per email per hour) instead of captcha for now; file checked by extension + declared type +
  size (content/magic-byte check comes with CV parsing in R3); one post per vacancy; deadline default +14 days (max 90);
  job profile = one education level + subjects (not a list of alternatives); post text written by SQL
  (`private.job_post_markdown`), rendered by a safe Markdown subset (`core/markdown.ts`, no raw HTML); poster drawn on
  canvas in the browser (4 colour themes, QR to the apply page). If the CV upload fails the application stays without
  a CV (HR can upload it). Found: 30+ older `private` functions are executable by PUBLIC — harmless while `private`
  is closed to anon and not exposed by the API, but never grant anon usage on `private`.
- **R3 decisions (2026-10-25, discussion)**: CV reading per company/post = AI mode (Claude) or Basic mode (no AI,
  PDF/DOCX → markdown via JS libraries in the Edge Function — user chose this over a Python MarkItDown server);
  AI falls back to Basic. Question bank per designation, per-post papers (objective / written / both), editable,
  "this post only" or "update bank"; typed in the system or Excel paste (AI draft only in AI mode). Recruitment only for
  Admin, HR Manager, Manager (own department); employees nothing. R5: a Manager may assign any employee as interviewer,
  who only scores assigned applicants. Manager actions default (not answered): view + set papers; publish/shortlist =
  HR/Admin. Details: architecture.md §2 #17–19.
- **R3 built 2026-10-25** (not applied, function not deployed). Choices: no `ai_jobs` queue — the Edge Function claims
  applicants as the user and saves each result (only `service_ai_key` uses the service role); default model
  `claude-opus-5-5` (company can pick Sonnet 5.5 / Haiku 5.5), effort low, JSON schema output, server-side refusal
  fallback; ATS out of 85 when relevance is not set; gate never moves anyone; HR corrections (`mode_used = manual`)
  survive re-reads; no platform test key (owner pastes own key into the test company); token usage not stored yet.
- **R4 built 2026-10-25** (not applied). Choices: papers from R3 (no `assessments` table), no negative marking;
  links shown once to HR (copy / mailto) until email arrives in R5; first link locks the objective paper, first marks
  lock the written paper (no unlock yet); server clock + 30 s grace, lazy auto-submit; question order shuffled, options
  not; scores never move anyone; interview window fixed 10:00–16:30 (shifts not used), notice 2 days, due = last result
  + 15 days, later needs a reason; HR or department Manager schedules; test links / marks are HR only; screening out
  after tests cancels open links and the interview. JS `String.replace` with `$$` in the replacement writes `$` — use
  a function replacement when editing SQL with Node.
- **R5 built 2026-10-25** (not applied, `recruit-notify` not deployed). Choices: email provider Resend (user did not
  answer), SMS generic gateway adapter off by default; English default templates editable (Bangla allowed); links
  carry `window.location.origin` as base URL; messages wait in the outbox until email is set up; the app sends right
  after queuing (no pg_cron yet); interview scoring 5 categories incl. confidence, from 1 h before the start, others'
  scores hidden until one scores; suggested questions without AI; composite computed live (no table), PMS for
  internal candidates not built; selection decision moved to R6. plpgsql: wrap `CASE … THEN` inside an `IF`
  condition in parentheses (bit us twice).
- **R6 + R7 built 2026-10-25** (not applied) — the hiring cycle is complete. Choices: decision on Results (seats
  enforced); offer maker-checker with `offer.approve` (Admin default; preparer never approves); the offer link also
  opens the pre-joining form; no email OTP (numbers are write-only instead); HR converts manually after verifying
  (no pg_cron); pay written from the approved offer via `private.create_compensation`; encrypted account copied as is;
  documents printed from the browser (`core/joining.ts`); photo copied to the employee by the app; portal login and
  reporting manager are checklist items done on the profile; close hiring = app deletes Storage files (Supabase blocks
  SQL deletes of storage rows), then `purge_post_applicants`. Known gap: notes in append-only decision histories and
  old interview comments in the audit log are kept. `of` is a reserved word — never use it as a SQL alias.

### Part 4 AI assistant (planned, discussion only) — user requirements 2026-10-27
- Design doc: `docs/Part04Architecture.md` (rewritten; the earlier generic RAG draft with a Python worker is replaced).
- User rules: floating AI widget on every signed-in page; sidebar Setup → "AI assistant" that **only Admin and HR
  Manager** may change; role-by-role checkbox matrix (like Roles & access) deciding which messages/topics each role
  gets; **the AI has no right to read the database** — it only shows dashboard updates and rules/regulation/law/policy,
  both role based.
- Design answer: the AI gets only two pre-filtered packages from the DB (knowledge passages + an update digest of
  counts/statuses), no tools, no service-role reads; a ticked topic still needs the role's existing permission;
  law = verified `statutory_references` rows; Claude key reused from R3 `org_integrations`; no Excel/JSON indexing.
- Second round (2026-10-27): each company gives only **an API key + resources (JSON, PDF, DOCX)** and sets the
  hyperparameters; the backend does the rest. All code in **`src/AIassistant/`** (README = file map). UI first on
  preview data. D1 yes; D2 Admin controls, may hand the setup over to HR Manager (switch on Overview, Admin-only);
  D3 platform embedding key; providers Claude + OpenAI + Gemini; hyperparameters model, temperature, answer
  length/style, top-k, minimum match, chunk size/overlap. JSON now indexed (one passage per record) with a
  personal-data warning. D5–D8 kept as my recommendations (user, 2026-10-27): Ask on PRO + ENTERPRISE / Updates
  on all plans; chat history own only 90 days; question text 90 days; limits Employee 20, Manager 30, HR 50, Admin
  none. D4 changed: DOCX cited by section with approx. page (no converter in Edge Functions).
- **Backend written as an execution plan** (design doc §8 + §11, README "Backend files to come"): steps AI1–AI6 each
  list files, UI parts to switch from `data/store.ts`, tests, SQL files for the user. User: "UI only now, backend
  later — when I say, execute it". `docs/Part05Architecture.md` is the user's next module (read 2026-10-27 on request,
  discussion only: Modules 15–23 + REST/Next.js spec from the old "AIHR BD" design; stack parts conflict with ours).
- **UI built 2026-10-27** (preview, no backend): floating widget (Updates + Ask, Alt+A), `/settings/assistant` with
  7 tabs, state in localStorage `olympus.ai-assistant.v1` (only key last 4 kept). `nav.ts` keeps the module out of the
  first download. Build: main chunk now 509 kB (was 497) — only ~1 kB is new code; react-query moved from the `ui-`
  chunk into `index` (bundler chunking), total JS +71 kB all in lazy chunks.

### Part 5 Communication: Notices + Helpdesk (planned, discussion only) — user answers 2026-10-27
- Source spec: `docs/Part05Architecture.md` (old "AIHR BD" Modules 15–23; take features/fields only, not its
  Next.js / REST stack). User chose to start with **Notices + Helpdesk, full backend + UI**, in a tidy module folder
  (like `src/AIassistant/`).
- Notices: publish by **Admin, HR Manager, and Manager for own department only**. Features: **Bangla version, email
  copy, acknowledge, read receipt**. Editor: **simple toolbar → safe markdown** (no rich-text library).
- Helpdesk: **auto-routing by category** to a handler set in setup (Admin/HR can reassign); **SLA on office hours**
  (weekly off, holidays, office time excluded; paused while waiting for the employee). Visibility: **own + handler +
  HR/Admin**; internal notes hidden from the employee; confidential categories never shown to Managers. Closing:
  **rating 1–5 or reopen; auto-close after 3 working days**; closed tickets do not reopen.
- **Password requests (15.3) included, small**: "Forgot password? Ask HR" on login → request list → existing
  `reset_user_password`; rate limited.
- **Built 2026-10-27** (C1–C3, not applied). Choices made while building: emails reuse the R5 outbox (`notifications`
  widened with `source` / `employee_id` / `ref_id`) and the unchanged `recruit-notify` function; scheduled notices and
  ticket auto-close / SLA breach are computed when lists are read (no pg_cron); SLA counts only the resolution clock
  as paused while waiting; first response = first public reply or status change by staff; confidential tickets can
  only be assigned to holders of helpdesk.manage; managers' notices always target their own department (DB fills it);
  ticket files are added as a first message right after creation (storage needs the ticket id).

### Part 4 AI assistant revision 2 — user answers 2026-10-27 (built the same day)
- The AI should **guide users in the app** (where to go, how a feature works) besides answering policy questions.
- **No platform key**: each company enters every credential in the UI; vectors per company with its own key.
  Claude has no embeddings → a second embedding key (Voyage recommended; OpenAI / Gemini possible); OpenAI / Gemini chat
  keys embed by themselves. Always 1024 dimensions. "Pretraining" = indexing (explained to the user).
- Guide: answer + page link, Show me highlight, page-aware, error help (all four chosen). Role lacks the feature →
  exactly "Your role is not permitted for that feature."
- App guide indexed with the company's key. When the DMS is built it becomes the **only** resource source
  (`assistant_resources.source = 'dms'` prepared). No LangChain.
- Choices while building: answers not streamed (revealed in the UI); Ask allowed on TRIAL too ("try everything");
  indexing runs from the browser in resumable batches of 48 chunks; scanned PDFs refused; usage + purge Admin only.

### DMS (Document Management System) — planned, user answers 2026-10-27 (architecture only, no code)
- Docs: `src/DMS/` (README, architecture, features, schema, security). Source draft `docs/DMS.md` (user's file,
  FastAPI/S3/Celery stack) rewritten for Supabase. Target UI: the user's sample dashboard (Overview setup steps,
  counts, licences by expiry, Upload / Folders / Fixed naming cards; tabs Library, Expiry & renewals, ISO compliance,
  Retention, Access, Audit log).
- Decisions: **Supabase stack**; roles as **`dms.*` permissions in Roles & access**; AI indexes **only Public +
  Internal**; profiles **ISO 9001, 27001, 14001, 45001** + agent suggestions (BD statutory licences on by default,
  buyer social compliance, 50001, 22000, 22301, 37001 as catalog extras). User's clients do not know ISO → a plain
  ISO guide is part of the product (features.md §6).
- Folders (user, 2026-10-27): **flexible**. Base folders (licences, buyer compliance, HR policy, contracts, records,
  general) for every company, each can be switched off; ISO folders optional; users create their own folders /
  subfolders. **Naming rule always enforced**: code from department + type, never from the folder; moving never renames.
- Guiding rule (user, 2026-10-27): **the user only opens a folder and uploads**; the system names, defaults, routes for
  approval and prevents duplicates / mismatches (features.md §2a). Keep every form minimal.
- D2 decisions (user, 2026-10-27; full list `src/DMS/architecture.md` §6a): requests by Admin / HR Manager (anyone)
  and Manager (own department); **custodians** per folder (the person who handles the work, e.g. transport → Karim;
  department Manager by default) upload and get reminders; every upload goes to central review (Admin, plus
  `dms.approve` holders); **never auto-approve** — "Review overdue" / "Upload overdue" stay until acted on;
  **Admin's own uploads publish directly** (audited); D1 documents stay published. Open: review period (3 working
  days proposed), two approvers?, policy acknowledgement?
- **Later, with TMS (Transport Management System)**: add base folder "Transport & Vehicles" (registration, fitness,
  tax token, route permit, insurance + vehicle number). Not now — user, 2026-10-27.
- Build steps D1–D6 (migrations `20261104000100…0600`); open questions per step in architecture.md §7. Ask before
  starting D1; seed document-type list to be reviewed with the user first.

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
(Single source: see **A9 Status board** and **A9a Handoff** — the list below is the 2026-10-17 history.) In order:
1. Done 2026-10-17: 3A + 3B applied, tests passed on Supabase. Hand test a run
   with two people (HR prepares, Admin approves), payslip EN/বাংলা, payment sheet CSV, lock.
2. Part 3C: tax/TDS, PF, gratuity (statutory values from verified sources, confirmed by the user).
3. Part 3D: hours compliance, grievance box, committees.
4. PMS demo (manual performance scoring) — agree scope first (user note #15 in Part03 §9).
5. Optional: pg_cron jobs (daily close, leave rollover, audit purge); enable the Phone provider; account lockout.

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
