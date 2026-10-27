# Part 4 — Olympus AI Assistant — Architecture

**Product:** Olympus HRIS · **Part:** 4 (AI assistant) · **Status:** design, discussion only (no code yet)
**Requirements from the user (2026-10-27):**
1. A **floating AI assistant** on every signed-in page of the app.
2. A sidebar item **"AI assistant"** (setup) that only **Admin** and **HR Manager** can open and change.
3. The setup works like **Roles & access**: a checkbox matrix that decides, **role by role**, which kinds of messages
   and answers the assistant may show.
4. The AI has **no right to read the database**. It may only show:
   - the **dashboard updates** the user would see anyway, and
   - **rules, regulations, law and company policy**, also **role based**.

**Follow-up (2026-10-27, second round):**
5. Each company gives only **two things**: (1) an **API key** and (2) **uploadable resources: JSON, PDF, DOCX**.
   It sets the **hyperparameters**, and then the assistant is ready. All processing happens in the backend.
6. All module code lives in **one folder, `src/AIassistant/`** (see its README for the file map).
7. Build the **UI first**, as a real module on preview data (browser storage); backend later.
8. Answers: D1 yes · D2 control stays with Admin, who may hand the setup over to HR Manager · D3 platform
   embedding key · providers Claude, OpenAI and Gemini · hyperparameters: model, temperature, answer length,
   retrieval (top-k, minimum match), chunking (size, overlap).

This document replaces the earlier generic RAG design (Python worker, Excel/JSON indexing). That design let the AI
read any indexed data; the new requirement forbids it, so the scope is narrower and the security model is stricter.

---

## 1. What the assistant is, and what it is not

| The assistant **does** | The assistant **does not** |
|---|---|
| Answer questions from the **Knowledge library** (company policies, HR rules, circulars, SOPs, labour law, tax/PF/gratuity references), with citations (document, page, section). | Read any business table (employees, attendance, leave, salary, payroll, applicants, audit logs). |
| Show the user's **Updates**: the same dashboard numbers and pending items they already see, filtered by the setup. | Run SQL, call arbitrary RPCs, or "look something up" about a person. |
| Answer in **Bangla or English** (the language of the question). | Make decisions, approve, edit or send anything. |
| Point to the right page ("Open Leave → My requests") when a question needs real data. | Answer from general internet knowledge when the library has nothing ("I don't know" instead). |
| Refuse politely when a topic is not allowed for the user's role. | Show a topic to a role that the role's permissions do not already allow. |

**Core rule:** the AI model never holds a database credential. It only receives two prepared, already-filtered
packages from the database: **knowledge passages** and the **update digest** (section 4). Everything else is closed.

---

## 2. Requirements

### Functional
- **F1 Floating widget** on every signed-in page (not on landing, login, careers, test or offer pages).
- **F2 Two tabs** in the widget: **Updates** (no AI needed, instant) and **Ask** (chat with the AI).
- **F3 Setup page** `/settings/assistant` in the sidebar **Setup** section, visible to Admin and HR Manager only.
- **F4 Role matrix**: per role, tick which **update topics** and **knowledge topics** the assistant may use.
- **F5 Per-role messages**: greeting, suggested questions, a pinned notice, the "not allowed" message, daily question limit.
- **F6 Resources**: upload PDF, DOCX and JSON; set topic and readers (topic roles, or only some roles), new version,
  archive / restore; live processing status. JSON files that look like employee data (salary, NID, phone, bank
  fields) ask for confirmation.
- **F6b API key**: provider (Claude, OpenAI, Gemini) + key, saved encrypted and tested by the backend; the browser
  keeps only the last 4 characters.
- **F6c Model settings (hyperparameters)**: model, temperature, answer style and maximum length, top-k, minimum match,
  chunk size and overlap (changing chunking re-processes the documents).
- **F6d Readiness**: an Overview checklist (key tested, ≥ 1 resource ready, valid settings, ≥ 1 role on) says when
  the assistant is ready.
- **F7 Law references**: the verified `statutory_references` rows (Part 3C) appear automatically as the **Law** category.
- **F8 Citations**: each answer cites `[1] Leave Policy 2026 · p.4 · Maternity leave`; clicking opens the document at that page.
- **F9 Test as role**: the setup page can preview the assistant as any role before the change goes live.
- **F10 Usage and logs**: questions per day, unanswered questions (gaps in the library), token use — Admin only.

### Non-functional
- **N1 No database access for the AI** (see section 5).
- **N2 Tenant isolation**: `org_id` on every row, composite FKs, RLS closed tables, RPC-only access (same as all parts).
- **N3 Never more than the role already has**: a ticked topic still needs the role's existing permission.
- **N4 No secrets in the browser**: the Claude key stays in `org_integrations` (R3), read only by the Edge Function.
- **N5 Auditable**: every question logged (user, role, topics used, cited passages), setup changes audited.
- **N6 Bangla + English** in documents, questions and answers.
- **N7 Mobile first**: the widget is full screen at 375 px; no horizontal scroll.
- **N8 Cost control**: per-role daily limit and an org monthly cap.

---

## 3. High-level architecture

```
 Browser (React SPA)
 ┌───────────────────────────────────────────────────────────────────────────┐
 │  AppLayout                                                                │
 │   ├─ Sidebar › Setup › "AI assistant"  (assistant.manage only)            │
 │   │     └─ /settings/assistant : General · Role access · Knowledge ·      │
 │   │                              Messages · Test as role · Usage          │
 │   └─ Floating button ● ─▶ panel:  [Updates] [Ask]                         │
 └──────────┬───────────────────────────────┬────────────────────────────────┘
            │ RPC (user JWT)                │ POST /functions/v1/assistant (user JWT, streaming)
            ▼                               ▼
 ┌─────────────────────────┐     ┌─────────────────────────────────────────────┐
 │ Postgres (public RPCs)  │     │ Edge Function "assistant"                   │
 │  assistant_my_config    │◀────│  1 assistant_prepare(question)  ← as USER   │
 │  assistant_updates      │     │     returns: allowed passages + digest      │
 │  assistant_* setup RPCs │     │  2 Claude (key via service function)        │
 │  knowledge_* RPCs       │     │  3 stream answer + citations                │
 │                         │◀────│  4 assistant_record_answer(...) ← as USER   │
 │  closed tables, RLS     │     └─────────────────────────────────────────────┘
 └─────────────────────────┘                    ▲
            ▲                                   │ document text, embeddings
            │                       ┌───────────┴──────────────────────┐
            └───────────────────────│ Edge Function "knowledge-ingest" │
                                    │  PDF → pages → chunks → embed    │
                                    └──────────────────────────────────┘
```

### Components

| Component | Responsibility |
|---|---|
| **Floating widget** (`AssistantWidget`) | Button + panel in `AppLayout`. Loads `assistant_my_config` once per session; hidden when the org or the role has the assistant switched off. |
| **Setup page** (`/settings/assistant`) | The six tabs in section 7. Guarded by `assistant.manage`. |
| **Postgres** | All rules: who may see which topic, the digest, knowledge search, limits, logs. Same patterns as every other part (closed tables, `require_permission`, audit). |
| **Edge Function `assistant`** | Orchestrator. Calls the DB **as the user** for the prepared package, calls Claude, streams the answer, records it. It has no table access of its own. |
| **Edge Function `knowledge-ingest`** | Turns an uploaded document into page-numbered passages and embeddings. Writes only knowledge tables, through one service-only RPC. |
| **LLM** | The company's own key: Claude, OpenAI or Gemini (stored encrypted, like the R3 key in `org_integrations`). |
| **Embeddings** | A multilingual embedding model for Bangla + English (decision D3). |

### Why no Python worker any more
The machine and the project have no Python, and the stack rule is "Postgres functions + Edge Functions". Claude reads
PDFs directly (including scanned pages and Bangla text) and returns text per page, so OCR and PDF libraries are not
needed. DOCX is converted to PDF in the backend for true page numbers. **JSON** (user requirement) is indexed one
passage per record, flattened to `key.path: value` lines and cited by JSON path; files that look like employee data
get a warning before upload. Excel stays out.

---

## 4. The two things the AI may see

### 4.1 Knowledge (rules, regulations, law, policy)

**Topics** (rows in the role matrix, "Knowledge" group). Seeded per org, HR can add custom topics:

| Topic key | Label | Typical documents | Default roles |
|---|---|---|---|
| `kb.company_policy` | Company policies | Leave, attendance, code of conduct, dress code | Everyone |
| `kb.hr_rules` | HR rules & procedures | Joining, transfer, resignation, final settlement SOP | Everyone |
| `kb.circulars` | Notices & circulars | Office closure, Eid holiday notice | Everyone |
| `kb.labour_law` | Labour law | Bangladesh Labour Act / EPZ Act summaries (from `statutory_references`) | HR, Admin, Manager |
| `kb.tax_pf_gratuity` | Tax, PF & gratuity | 3C references, PF trust rules | HR, Admin (+ Employee: own-rights summaries only, if ticked) |
| `kb.pay_policy` | Pay & benefits policy | Salary structure policy, bonus policy, allowances | HR, Admin |
| `kb.manager_guide` | Manager guide | Approving leave/OT, performance review guide | Manager, HR, Admin |
| `kb.confidential` | Confidential HR | Disciplinary procedure, investigation SOP | Admin only |

**Each document** belongs to one topic and **follows the topic's roles** by default. A document may narrow its own
audience further (for example, a circular only for the Chattogram branch roles), but **never widen** it beyond the
topic. So the effective audience of a passage = topic roles ∩ document roles.

**Law category:** verified rows of `statutory_references` (status `verified`) are mirrored into the library as
passages of `kb.labour_law` / `kb.tax_pf_gratuity`, with their `source_url`, section and `verified_on` shown in the
citation. Rows marked `needs_confirmation` are **not** used; the assistant says "this value is not confirmed yet, ask HR".

### 4.2 Updates (the dashboard digest)

**Topics** ("Updates" group in the matrix). Each topic is tied to an **existing permission**, so ticking it can never
give a role more than it has:

| Topic key | What the user sees | Needs permission | Default roles |
|---|---|---|---|
| `up.my_day` | My check-in today, shift, late or not | `attendance.view_own` | Everyone |
| `up.my_leave` | My leave balance, my pending requests | `leave.request` | Everyone |
| `up.my_payslip` | "Your October payslip is ready" (no amounts) | `payroll.view_own` | Everyone |
| `up.my_reviews` | Performance review waiting for acknowledgement | (own record) | Everyone |
| `up.team_today` | Team present / late / absent counts | `attendance.view_team` | Manager |
| `up.approvals` | Leave, OT, swap requests waiting for me | `leave.approve` / `overtime.approve` / `swaps.approve` | Manager, HR |
| `up.headcount` | Total, active, new this month (same as dashboard KPIs) | `employees.view` | HR, Admin |
| `up.attendance_org` | Today's org attendance summary | `attendance.view_all` | HR, Admin |
| `up.payroll_status` | Current payroll run status (draft → locked), no amounts | `payroll.prepare` or `payroll.approve` | HR, Admin |
| `up.hiring` | Open vacancies, posts, applicants waiting | `vacancies` / job post permissions | HR, Admin |
| `up.new_policies` | "New policy published: Leave Policy 2026" | (allowed knowledge topic) | Everyone |

**How the digest is made:** a database function builds a short list of items (title, one line, number, link to the
page) for the current user from the **same sources the dashboard uses**, and keeps only items that pass both checks:
the topic is ticked for the user's role **and** the user has the permission. Money amounts, names of other people,
NID, phone numbers and account numbers are **never** part of the digest. Counts and statuses only.

The **Updates tab** shows this list directly (no AI call, instant, free). The **Ask tab** may receive the same list
as text, so "what's waiting for me today?" can be answered. The AI never receives anything that is not on the user's
own Updates tab.

---

## 5. Security model — why the AI cannot read the database

1. **No credential.** The Edge Function creates its Supabase client with the **user's** JWT. It never uses the
   service-role key for reading. The only service-role call is the existing pattern of fetching the decrypted Claude key
   (`service_ai_key`, R3) and the ingest writer.
2. **Two doors only.** For the user's role, the API exposes exactly two read functions to the assistant:
   `assistant_prepare` (knowledge passages + digest) and nothing else. There is no generic "query" function, and the
   model has **no tools** that touch data (no function calling into the DB).
3. **Filtering before the prompt.** Topic ticks, permissions, document roles and org are checked **inside** the SQL
   that picks passages. Content a role may not see never reaches the prompt, so the model cannot leak it.
4. **Questions about people or numbers.** A question like "What is Rahim's salary?" or "How many days was I absent?"
   gets a fixed answer: "I can't see employee records. You can check this on *Attendance → My attendance*." The
   system prompt and an allow-list of page links make this consistent.
5. **Documents are untrusted.** Passages go into a delimited block; the model is told they are data, not instructions
   ("ignore previous instructions" inside a PDF does nothing).
6. **Storage.** Knowledge files live in a private bucket `knowledge-docs/{org}/{document}/v{n}.pdf`. The storage
   policy checks org **and** the same topic/document roles (fixes the gap in the old design, where any org member could
   open a restricted file by path). Files open only through short signed URLs.
7. **Setup cannot escalate.** Only `assistant.manage` changes the matrix. Ticks for a topic whose permission the role
   lacks are shown greyed out ("This role has no `attendance.view_team`; change it in Roles & access first").
8. **Audit.** Setup changes go through the standard audit trigger; every question writes an append-only log row.

---

## 6. Floating assistant — UI

### 6.1 Button
- Round orange button, bottom-right, above page content; badge with the number of new Updates.
- Hidden for public pages, for roles where the assistant is off, and while printing.
- Keyboard: opens with the button or `Alt + A`; `Esc` closes; focus returns to the button.

### 6.2 Panel (desktop 380 × 600 px, mobile full screen)

```
 ┌──────────────────────────────────────┐
 │ ✦ Olympus Assistant          ─   ✕   │
 │ [ Updates (3) ]  [ Ask ]             │
 ├──────────────────────────────────────┤
 │ Today                                │
 │ ● You checked in 09:02 (on time)  →  │
 │ ● 2 leave requests wait for you   →  │
 │ ● New policy: Leave Policy 2026   →  │
 │                                      │
 │ 📌 Office closed on 16 Dec (notice)  │
 └──────────────────────────────────────┘

 ┌──────────────────────────────────────┐
 │ ✦ Olympus Assistant          ─   ✕   │
 │ [ Updates ]  [ Ask ]                 │
 ├──────────────────────────────────────┤
 │ Hi Karim! Ask me about company       │
 │ policies, rules and your updates.    │
 │                                      │
 │ (How many casual leaves do I get?)   │
 │ (মাতৃত্বকালীন ছুটির নিয়ম কী?)        │
 │                                      │
 │ You: How many casual leaves...       │
 │ AI : You get 10 days of casual       │
 │      leave per year [1]...           │
 │      [1] Leave Policy 2026 · p.4     │
 ├──────────────────────────────────────┤
 │ Type a question…              [ ➤ ]  │
 │ Answers come only from company       │
 │ documents. Check important details   │
 │ with HR.                             │
 └──────────────────────────────────────┘
```

- **Updates tab**: digest items grouped *Today / This week*, each with a link to the real page; pinned notice of the role.
- **Ask tab**: greeting and suggested questions of the role; streaming answer; citation chips; "Not helpful" button
  (feeds the Usage tab); remaining questions today ("12 of 20 left").
- **Citation click**: opens a viewer modal at the cited page (PDF), or the reference card for a law item
  (title, section, summary, source link, verified date — the existing `ReferenceCard`).
- **States**: loading, empty library ("HR has not published any documents yet"), limit reached, assistant switched
  off mid-session, network error, "I don't know" answers shown with a suggestion to ask HR.
- Conversation history stays in the panel for the session; saved history (decision D6) is per user only.

---

## 7. Setup page — `/settings/assistant`

Sidebar **Setup → AI assistant** (icon: sparkles). Visible to Admin, and to HR Manager after an Admin hands it over
(`assistant.manage` once the backend exists).

**As built (UI preview, `src/AIassistant/setup/`):** tabs are **Overview** (readiness checklist + General below),
**API key**, **Resources** (= Knowledge library), **Model settings** (hyperparameters), **Role access**,
**Messages**, **Test as role**. Usage (Tab 6) waits for the backend logs.

### Tab 1 — General
- Assistant **on/off** for the organization.
- Name (default "Olympus Assistant") and short description.
- Answer language: *follow the question* (default) / always Bangla / always English.
- Answer style: short / detailed; always show citations (on, cannot be switched off).
- Out-of-scope message (EN + BN).
- AI key status: uses the Claude key from **Recruitment settings** (link there); shows "not set" if missing.
- Monthly limit for the organization (questions or tokens); what happens when reached (stop / Admin-only).

### Tab 2 — Role access (the checkbox matrix, same look as Roles & access)

```
                                Admin   HR Manager   Manager   Employee   Accounts*
 Assistant enabled               ☑ 🔒      ☑            ☑          ☑          ☐
 ─ Updates ─────────────────────────────────────────────────────────────────────
 My day                          ☑ 🔒      ☑            ☑          ☑          ☐
 My leave                        ☑ 🔒      ☑            ☑          ☑          ☐
 Approvals waiting               ☑ 🔒      ☑            ☑          ▢ (no perm)
 Headcount                       ☑ 🔒      ☑            ▢ (no perm) ▢ (no perm)
 Payroll status                  ☑ 🔒      ☑            ▢ (no perm) ▢ (no perm)
 ─ Knowledge ───────────────────────────────────────────────────────────────────
 Company policies                ☑ 🔒      ☑            ☑          ☑          ☑
 Labour law                      ☑ 🔒      ☑            ☑          ☐          ☐
 Pay & benefits policy           ☑ 🔒      ☑            ☐          ☐          ☐
 Confidential HR                 ☑ 🔒      ☐            ☐          ☐          ☐
 ─ Limits ──────────────────────────────────────────────────────────────────────
 Questions per day               ∞         50           30         20         20
                                                      * custom roles appear as extra columns
```

- Admin column is locked (always everything), like Roles & access.
- `▢ (no perm)` = greyed, with a tooltip naming the missing permission.
- **HR Manager cannot tick `kb.confidential` for HR Manager** unless Admin allows it (decision D2), so HR cannot widen
  its own access.
- Save shows a summary ("Manager: + Labour law, − Headcount") before applying.

### Tab 3 — Knowledge library
- Table: title, topic, language, version, effective from, status (*processing / ready / failed / archived*), pages,
  uploaded by, last updated.
- **Upload**: PDF (or DOCX after conversion), title, topic, audience (follow topic / narrow to roles), effective date,
  language. Duplicate files (same hash) are refused **before** the upload starts.
- **New version** of a document: the old version is archived (kept for audit, no longer answered from).
- Live status while processing; a failed document shows the reason and a **Retry** button.
- **Law references** sub-list: read-only view of the mirrored `statutory_references` rows with a link to `/references`.

### Tab 4 — Messages (per role)
For each role: greeting (EN + BN), up to 6 suggested questions, a pinned notice with an end date, the "not allowed
for your role" message.

### Tab 5 — Test as role
Pick a role → the panel on the right behaves exactly as for that role (same digest topics, same knowledge topics),
using sample digest values, not real people's data. Each answer shows "used topics" and the cited passages, so HR can
see why the assistant answered as it did.

### Tab 6 — Usage (Admin only, `audit.view`)
- Questions per day / per role, tokens used vs. monthly limit.
- **Unanswered questions** (the AI said "I don't know") → tells HR which policy is missing.
- "Not helpful" answers.
- Question log (user, role, time, topics, cited documents). Question text is kept for the retention period
  (decision D7), then removed by the purge job.

---

## 8. Data model (closed tables, RPCs only — same rules as every part)

| Table | Purpose | Key columns |
|---|---|---|
| `assistant_settings` | One row per org | enabled, name, language_mode, style, out_of_scope_message (+bn), monthly_limit, limit_action, retention_days |
| `assistant_topics` | Global catalog of topics | key, group (update / knowledge), label (+bn), required_permissions[], is_sensitive, sort |
| `assistant_org_topics` | Org's custom knowledge topics | org_id, key, label (+bn), status |
| `assistant_role_settings` | One row per role | org_id, role_id, enabled, daily_limit, greeting (+bn), suggestions[], pinned_notice, notice_until, not_allowed_message |
| `assistant_role_topics` | **The checkbox matrix** | org_id, role_id, topic_key, allowed |
| `knowledge_documents` | Library | org_id, topic_key, title, language, file_path, file_hash (unique per org), version, effective_from, audience_roles[] (empty = follow topic), status, error, page_count, published_by/at, archived_at |
| `knowledge_chunks` | Passages | org_id, document_id, topic_key, page_number, section_title, passage, token_count, embedding, embedding_model, keyword index |
| `assistant_conversations` | Saved chats (if D6 = yes) | org_id, user_id, title, last_at |
| `assistant_messages` | Chat lines | conversation_id, role (user / assistant), content, cited_chunk_ids[], used_topics[] |
| `assistant_query_log` | **Append-only** log | org_id, user_id, role_id, asked_at, question (removed after retention), topics_used[], chunk_ids[], digest_keys[], answered, helpful, tokens_in/out |

Rules:
- Composite FKs `(org_id, id)`; `attach_standard_triggers` (audit, updated_at, no hard delete) on setup and library tables.
- The audience of a chunk is **not copied** onto the chunk; it is computed from the document and topic at query time
  (fixes the old "visibility copied, never re-synced" gap). A change in the matrix applies on the next question.
- Embedding dimension is fixed by the chosen model; `embedding_model` is stored so a later model change can re-embed.
- Law passages from `statutory_references` are kept in step by a trigger (verified → indexed; changed → re-indexed;
  needs_confirmation → removed).

### Permissions (added to the catalog)
| Permission | Who | Notes |
|---|---|---|
| `assistant.manage` | Admin (implicit), HR Manager (default) | Opens the setup page. **Grantable only to roles with `system_key` admin or hr_manager** (user rule: only Admin and HR Manager). |
| `assistant.view_usage` | Admin only | Usage tab and question log (same idea as `audit.view`). |
| (none) | Everyone | Using the widget is controlled by the role matrix, not a permission. |

### Functions (RPCs) — names only
- Widget: `assistant_my_config` (enabled? greeting, suggestions, notice, limit left), `assistant_updates` (the digest).
- Chat (called by the Edge Function as the user): `assistant_prepare(question, query_embedding)` → checks enabled,
  limit, returns allowed passages (hybrid search: meaning + keywords, topic/role filter inside) + digest text;
  `assistant_record_answer(...)` → log + saved message; `assistant_feedback(message, helpful)`.
- Setup: `get_assistant_setup`, `save_assistant_settings`, `save_assistant_role_matrix`,
  `save_assistant_role_messages`, `assistant_preview_as_role`.
- Library: `list_knowledge_documents`, `register_knowledge_document`, `archive_knowledge_document`,
  `retry_knowledge_document`, `knowledge_document_url` (signed URL, role checked); service only:
  `service_save_knowledge_chunks`, `service_set_document_status`.
- Usage: `get_assistant_usage`, `list_assistant_queries`.

---

## 9. Flows

### 9.1 Ask a question
1. User types in the Ask tab → browser calls the `assistant` Edge Function with the user JWT.
2. Edge Function embeds the question (same model as the library).
3. Calls `assistant_prepare` **as the user** → the DB checks: org on, role on, daily and monthly limits; picks the top
   passages only from allowed topics and documents; adds the digest text. If nothing is allowed or found, it says so.
4. Edge Function builds the prompt: rules (answer only from sources, cite `[n]`, user's language, no personal data,
   send people to the right page for records), the sources block, the digest block, the last few turns.
5. Claude answers; tokens stream to the browser; a final event carries the citations.
6. `assistant_record_answer` writes the log and (optionally) the saved message.

### 9.2 Publish a policy
1. HR uploads in the Knowledge tab → hash checked first → document row `processing` → file to `knowledge-docs`.
2. `knowledge-ingest` reads the PDF with Claude page by page → passages split on headings/paragraphs (300–500 tokens,
   small overlap, header line "Document · Page · Section" for meaning search) → embeddings → saved; status `ready`.
3. Status change appears live in the table; a `up.new_policies` item appears in Updates for the allowed roles.

### 9.3 Change the matrix
HR ticks → summary → save → audit row → applies on everyone's next question / next Updates refresh.

---

## 10. Decisions

| # | Question | Answer |
|---|---|---|
| D1 | Should Updates work even when the AI key is missing? | **Yes (user, 2026-10-27).** Updates need no AI; only the Ask tab needs the key. |
| D2 | Who controls the setup? | **Admin (user, 2026-10-27).** HR Manager opens the setup only after an Admin switches on "HR Manager may manage the assistant"; even then sensitive topics (`kb.confidential`, `up.payroll_status`) for HR Manager are Admin-only ticks. |
| D3 | Embedding provider | **Platform-level key (user, 2026-10-27)** held by Olympus, multilingual (Bangla + English); companies give only their LLM key. |
| D3b | LLM providers | **Claude, OpenAI, Gemini (user, 2026-10-27)**; the model list per provider comes from the backend. |
| D4 | DOCX | Converted to PDF in the backend (no "Save as PDF" step for HR). |

Still recommendations, not yet confirmed:

| # | Question | Recommendation |
|---|---|---|
| D5 | Plans | Assistant available on PRO and ENTERPRISE; Updates tab on all plans. |
| D6 | Save chat history? | Yes, own history only, kept for 90 days. |
| D7 | Question text retention in the log | 90 days, then removed by the purge job; counts stay. |
| D8 | Default daily limits | Employee 20, Manager 30, HR 50, Admin unlimited. |

---

## 11. Build order (steps AI1–AI6, a commit per step, like R1–R7)

**Done first (2026-10-27): the whole UI on preview data** in `src/AIassistant/` (widget, setup tabs, core rules with
unit tests). The steps below now replace its data layer piece by piece.

1. **AI1 Foundation**: migration for settings, topics, role matrix, role messages, permissions, seeds for existing
   orgs; SQL test (two orgs, four roles, "tick without permission does nothing").
2. **AI2 Setup UI**: sidebar item, `/settings/assistant` with General, Role access, Messages tabs.
3. **AI3 Floating widget + Updates**: `assistant_my_config`, `assistant_updates` digest, the panel with Updates tab.
   (Works without any AI key.)
4. **AI4 Knowledge library**: bucket + storage policy with role check, documents table, `knowledge-ingest` Edge
   Function, law mirror from `statutory_references`, Knowledge tab.
5. **AI5 Ask**: `assistant` Edge Function, `assistant_prepare` hybrid search, streaming chat, citations, viewer, limits.
6. **AI6 Test as role + Usage**: preview, usage stats, unanswered questions, purge job; evaluation with ~50 real HR
   questions (does the right page come back? does a role ever see a topic it should not?).

---

## 12. Pitfalls to avoid
- Giving the model any tool or RPC that reads business tables "just for one feature".
- Filtering by role **after** retrieval instead of inside the SQL.
- Letting the matrix grant something the role's permissions do not allow.
- Using different embedding models for the library and the questions.
- Indexing spreadsheets or exports with employee data.
- Answering from `needs_confirmation` law values as if they were verified.
- Showing amounts or other people's names in the digest.
- A STABLE function that logs or counts the limit (fails with HTTP 405 on Supabase; must be VOLATILE).
