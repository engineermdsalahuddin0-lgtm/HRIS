# Document Management System (DMS): Architecture

Source idea: `docs/DMS.md` (the user's draft, written for FastAPI + S3 + Celery). This file rewrites it for this
project's stack and rules. **Status: planned, no code yet** (2026-10-27).

Other files in this folder:
| File | Holds |
|---|---|
| `features.md` | Feature list, dashboard tabs, permissions, the ISO guide for clients |
| `schema.md` | Tables, RPCs, storage, indexes, tests per step |
| `security.md` | Security model and the coding rules every DMS step must follow |
| `README.md` | Folder map and build order |

User decisions (2026-10-27):
1. **Stack: Supabase**, same as the rest of the app. No FastAPI, S3, Celery, RabbitMQ or Redis.
2. **Roles: permissions in Roles & access** (`dms.*`), ticked on any role by the Admin. No separate DMS roles.
3. **AI: only Public and Internal documents are indexed.** Confidential and Restricted text never leaves for an
   external API.
4. **ISO profiles at launch: 9001, 27001, 14001, 45001**, plus the agent's suggestions (features.md §6).
5. The DMS is the **only** resource source of the AI assistant (decided in Part 4 revision 2). The assistant's own
   upload adapter is retired once DMS step D5 is live.
6. **Folders are flexible, names are not** (2026-10-27):
   - **Base folders** (License & Compliance with BD statutory licences, Buyer Compliance, HR Policy, Contracts,
     Records & Audits) come with every company, need no selection, and each can be switched off in Setup.
   - **ISO folders** are optional and only add folders and checklist ticks. A company can start with no ISO at all.
   - **Users create their own folders and subfolders** and put files in them.
   - **Every file still follows the naming rule.** Whatever folder it sits in, the system names it
     `{DEPT}-{TYPE}-{SEQ}_v{n}`; nobody types a file name. Moving a file to another folder changes neither its name
     nor its storage path.

---

## 1. Design principles (kept from DMS.md)

1. **One locked core under a replaceable ISO layer.** Naming, IDs, storage path and metadata never change; ISO
   profiles only add categories, document types and clause tags. Changing ISO never moves a file or re-indexes.
2. **Folders are views.** The folder tree is built from category metadata. Storage paths hold only UUIDs.
3. **The system names things.** Document code, version name and storage path are generated. The original file name
   is kept as metadata only.
4. **Files are immutable.** A new file is always a new version; old versions stay until disposed.
5. **Every chunk is traceable** to document, version, page or sheet, and section.
6. **Access is checked before retrieval,** in the database, never after generation.
7. **Processing is resumable and idempotent,** keyed on the version id.

Added for this project:
8. **Multi-company.** Every table has `org_id`, composite FKs `(org_id, id)`, closed RLS, RPC-only access.
9. **No delete.** Rows are archived; only the disposal workflow removes a file, and it keeps proof.
10. **Company credentials only.** AI auto-fill and indexing use the company's own keys from Setup → AI assistant.

---

## 2. Layers

```
[ ISO profile layer ]  platform catalog: ISO 9001 | 27001 | 14001 | 45001 | BD statutory | ... | Custom
                       categories, document types, clause list, default review period
--------------------------------------------------------------------------------------------------
[ Governance layer ]   per company: lifecycle, approval, review dates, expiry, retention, legal hold, audit
--------------------------------------------------------------------------------------------------
[ Core layer (locked)] doc code, version name, storage path, mandatory metadata, classification, access
--------------------------------------------------------------------------------------------------
[ Storage + AI ]       Supabase Storage (private bucket) | Postgres | pgvector + tsvector (assistant store)
```

| Layer | Lives in | Changed by |
|---|---|---|
| ISO profile | Global catalog tables, seeded by migration (platform-owned) | Platform team, by migration |
| Company file plan | Org tables copied from the selected profiles + company custom branch | `dms.manage` |
| Governance | Org tables (doc types, approvals, retention, holds) | `dms.manage`, `dms.records` |
| Core | Database functions and constraints | Dev team, by migration only |
| Storage + AI | Bucket `dms-documents`, `assistant_resources` / `assistant_chunks` | System only |

**The folder tree has three kinds of folder**, all stored in one table (`dms_categories.origin`):

| Kind | Comes from | Company may |
|---|---|---|
| `base` | Created for every company on DMS setup | Rename the label, switch off (hidden while empty), add subfolders. Code locked |
| `iso` | Copied when an ISO profile is selected | Same as base. Deselecting the profile hides its empty folders; folders holding documents stay |
| `custom` | Created by a user | Create, rename, nest (up to 3 levels), move, switch off when empty. Never deleted while it holds documents |

**Folder ≠ name.** A document's code comes from its department and document type, never from its folder. A custom
folder offers every active document type, plus a generic "General document" (`DOC`) type, so a file put anywhere is
still named `{DEPT}-{TYPE}-{SEQ}_v{n}`. Moving a document between folders is a metadata change only (audited).

---

## 3. Runtime flows

### 3.1 Upload (new document or new version)
```
UI: category -> document type -> department -> type fields (expiry etc.) -> drop file
 |
 |-- browser: detect type by extension + MIME, size limit, SHA-256 of the bytes
 v
RPC dms_register_upload            permission + department check, validate fields,
 |                                 reject duplicate hash in this org, reserve version row (status 'uploading'),
 |                                 return storage path {org}/{document}/v{n}.{ext}
 v
Storage upload (signed upload URL, private bucket, RLS on the path)
 v
RPC dms_confirm_upload             object exists, size matches -> status 'uploaded'
 |                                 doc code assigned on the first version: {DEPT}-{TYPE}-{SEQ}
 v
Edge Function dms  action 'inspect' magic-byte type check, recompute SHA-256, page/sheet count,
                                   text-layer check for PDF; mismatch -> status 'rejected' + reason
                   action 'autofill' (optional, company chat key) suggests title, dates, licence number;
                                   the user confirms in the form, nothing is saved without them
```

### 3.2 Lifecycle and approval
```
draft --submit--> in_review --approve--> approved --publish--> published --new version published--> superseded
  ^                   |                                            |
  +------reject-------+                                            +--archive--> archived --dispose--> disposed
```
- The document type decides the reviewer (role or person) and approver; the uploader can never approve their own
  version (checked in the database).
- Publishing a new version marks the previous one `superseded` in the same transaction.
- Only `published` versions are visible to general readers and to the AI.

### 3.3 AI indexing (adapter into the existing assistant store)
```
version published  AND classification in (public, internal)  AND document type ai_enabled
 |
 v  private.dms_sync_assistant (same transaction)
assistant_resources row: source 'dms', dms_document_id, dms_version_id, file_path in dms-documents,
                         topic from the category mapping, audience from the document's access
 v
Edge Function assistant  action 'ingest' (already deployed: batches of 48, resumable)
 v
assistant_chunks (vector(1024) + tsvector), each chunk keeps doc code, version, page / sheet, section
```
- A superseded, archived, disposed or reclassified (to Confidential / Restricted) version removes its resource and
  chunks in the same transaction.
- The assistant's own upload tab becomes a read-only list "Documents from the DMS" after D5.
- New in the assistant ingest: an XLSX parser (one unit per sheet, rows as `header: value`).
- No LangChain, no reranker, no OCR at launch (see §5).

### 3.4 Expiry, review and reminders
- Documents with an expiry date (licences, certificates) and every document's `next_review_date` feed the
  "Expiry & renewals" tab. Status: expired, due within the reminder window (default 60 days), active.
- Reminders go to the owner and the department head through the existing outbox (`notifications`) and the existing
  Edge Function `recruit-notify`. One reminder per document per window step (60 / 30 / 7 days / expired).
- Scheduling: if `pg_cron` is enabled on the project, a daily job calls `run_dms_reminders()`. Without it, the same
  idempotent function runs when anyone with DMS access opens the dashboard (the notices pattern).

### 3.5 Retention and disposal
- Each document type has a retention rule: start event (published, superseded, expiry, archived), years, action
  (review / dispose). Values are set by the company (legal / records owner), never defaulted by us.
- Disposal is never automatic: the Records tab lists due items, a `dms.records` holder approves, a second person
  confirms. Legal hold blocks it. Disposal removes the storage object and AI chunks, blanks the text fields, and
  keeps a proof row (code, version, hash, who, when, method). The document row itself stays as a tombstone.

### 3.6 Reading and download
- Library and search show only what the reader may see (§security.md 2).
- Download: RPC `dms_file_url` checks access, writes an access-log row, returns a signed URL valid 60 seconds.

---

## 4. How the DMS fits the existing app

| Need | Existing piece reused |
|---|---|
| Departments and their codes | `departments.code` (Overview step 2 makes the code mandatory for departments used by DMS) |
| Owners, reviewers | `employees` + `org_members`; department heads from `departments.head_employee_id` |
| Permissions | `permissions` / `role_permissions`, `private.has_permission` |
| Audit of changes | `attach_standard_triggers` + `private.write_audit` |
| Emails | `notifications` outbox + `recruit-notify` |
| AI keys, vectors, ingest | `org_integrations` (`assistant_chat`, `assistant_embed`), `assistant_resources`, `assistant_chunks`, Edge Function `assistant` |
| Plan gating | Same plan check as the assistant (TRIAL / PRO / ENTERPRISE) |
| UI kit | `components/ui.tsx`, `components/kit.tsx`, Tabs, Modal, StatusBadge, SpotlightTour `data-tour` |
| Notices | A published policy can be announced with one click ("Notify readers" creates a notice linking to it) |

The R7 `onboarding_documents` (an employee's personal papers) stay where they are: they are personal data, not
company documents, and the AI must never read them.

---

## 5. What DMS.md had that is changed or postponed

| DMS.md | Here | Why |
|---|---|---|
| FastAPI + JWT | Postgres RPCs + Supabase Auth | One backend, one permission system |
| S3 `docs/{uuid}/v{n}/original.ext` | Bucket `dms-documents`, `{org}/{doc}/v{n}.{ext}` | Org prefix lets storage RLS isolate companies |
| Celery + RabbitMQ + DLQ | Version status + resumable Edge Function batches + "Retry" button | Same guarantees without servers |
| `vector(1536)` own chunk table | Assistant store `vector(1024)` | One vector store per company, already deployed |
| Cross-encoder reranker | Hybrid search (cosine + `ts_rank_cd` + boosts) | Can be added later with a company rerank key |
| Tesseract OCR | Postponed. Scanned PDF -> "No text found, upload a text PDF or the Word file" | Not runnable on Edge Functions |
| ClamAV | Magic-byte check, size limit, extension allow-list, never served inline | No virus scanner on Supabase |
| `audit_log` with queries | Standard audit + `dms_access_log`; AI queries already in `assistant_query_log` | Avoid duplicates |

---

## 6. Build steps

| Step | Contents | Migration (planned) | Test |
|---|---|---|---|
| D1 Foundation | Permissions, ISO catalog seed, company file plan, doc types, naming, bucket, upload + versions, Library tab | `20261104000100_dms_d1_foundation.sql` | `dms_d1_foundation_test.sql` |
| D2 Governance | Lifecycle, review / approval, access rules, Expiry & renewals, reminders | `20261104000200_dms_d2_governance.sql` | `dms_d2_governance_test.sql` |
| D3 ISO compliance | Clause tags, compliance view, gap list, ISO guide page | `20261104000300_dms_d3_compliance.sql` | `dms_d3_compliance_test.sql` |
| D4 Records | Retention rules, legal hold, two-person disposal, proof log | `20261104000400_dms_d4_records.sql` | `dms_d4_records_test.sql` |
| D5 AI adapter | Sync into the assistant store, XLSX parser, assistant upload tab retired, autofill | `20261104000500_dms_d5_ai.sql` + Edge Functions `dms`, `assistant` | `dms_d5_ai_test.sql` |
| D6 Audit & access review | Audit log tab, export, quarterly access review | `20261104000600_dms_d6_audit.sql` | `dms_d6_audit_test.sql` |

Each step: migration -> SQL test (PGlite locally) -> UI -> unit tests -> typecheck/build -> handbook update -> commit.
The user applies each migration and its test in the Supabase SQL Editor in order.

---

## 7. Open questions (ask before the step that needs them)
- D2: Is one approver enough for every type, or do some types (policy, procedure) need two?
- D2: Should employees be asked to acknowledge a newly published policy (reuse the notice acknowledgement)?
- D4: Who in the client company sets retention years? The UI will refuse to dispose until a rule exists.
- D5: Which category maps to which assistant topic (proposed defaults in features.md §5)?
- Later: OCR for scanned PDFs through the company's chat model (vision) — cost per page must be shown first.
