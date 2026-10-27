# DMS: Database schema

## As built: D1 (`20261104000100_dms_d1_foundation.sql`, test `dms_d1_foundation_test.sql`, 9 checks)
Where D1 differs from the plan below, D1 is the truth:
- Catalog: `dms_iso_profiles` (8 standards), `dms_catalog_folders` (6 base + 9 ISO; `profile_code` null = base),
  `dms_catalog_doc_types` (52 types, **codes unique across the catalog**; `expiry_default` `fiscal_year_end` = 30 June
  for Trade Licence and IRC/ERC). Clause tables come in D3.
- `dms_settings` holds `profiles text[]` and `no_iso` (no separate `dms_org_profiles`).
- The folder tree is `dms_folders` (`origin` base / iso / custom, `enabled`), not `dms_categories`. A document has a
  `folder_id` (where it is shown) and a `doc_type_id` (what names it) — independent.
- `dms_doc_types` per company (copied from the catalog; custom types have no extra fields). Type code unique per company.
- `dms_documents.lifecycle`: pending / published / archived / cancelled (approval states arrive in D2).
  `owner_user_id` (a login), not an employee.
- `dms_versions.status`: uploading / current / superseded / cancelled; each version keeps its own `expiry_date` and
  `fields` (licence history). Unique hash per company among non-cancelled versions.
- `dms_access_log` (downloads). Seeding runs once per company (`seed_dms_defaults`), so removed permissions or
  folders are never brought back.
- RPCs: `get_dms_setup`, `set_dms_profiles(codes, no_iso)`, `save_dms_folder`, `save_dms_doc_type`, `get_dms_library`,
  `list_dms_documents(p)`, `get_dms_document`, `dms_next_code`, `dms_register_upload`, `dms_confirm_upload`,
  `dms_cancel_upload`, `update_dms_document`, `archive_dms_document`, `dms_file_path`, `get_dms_overview(from, to)`.
- Not in D1: the `dms` Edge Function (magic-byte re-check, auto-fill) moves to D5; until then the bucket MIME list,
  the size limit and the kind/MIME match in `dms_register_upload` guard uploads, and files are only served as downloads.

## As built: D2 (`20261104000200_dms_d2_governance.sql`, test `dms_d2_governance_test.sql`, 8 checks)
- Permission `dms.approve` (HR Manager, Manager). Settings `require_review` (on), `review_days` (3 working days),
  `reminder_days` ({60,30,7,0}).
- `dms_versions` + statuses `in_review`, `rejected`; `submitted_at`, `review_due_date`, `reviewed_by/at`,
  `review_comment`, `published_without_review`, `request_id`. A rejected file may be sent again (hash index skips it).
- `dms_custodians` (folder, user, active), `dms_requests` (upload | renewal; open → submitted → done | cancelled),
  `dms_reminders` (one row per document, kind, due date, step). Outbox `notifications.source` gains `dms`.
- RPCs: `dms_decide`, `list_dms_tasks`, `list_dms_people`, `create_dms_request`, `cancel_dms_request`,
  `save_dms_custodian`, `save_dms_settings`; redefined `dms_register_upload` (request_id, custodian),
  `dms_confirm_upload` (Admin → published, others → in_review), `get_dms_document`, `get_dms_setup`,
  `get_dms_overview`, `get_dms_library` (types for everyone), `dms_file_path`, `private.dms_file_access`.
- Reminders run when DMS lists open (`private.run_dms_reminders`): current step only, never repeated; the first
  expiry step creates one renewal request for the owner.

## As built: D3 (`20261104000300_dms_d3_compliance.sql`, test `dms_d3_compliance_test.sql`)
- Permission `dms.audit` (read-only auditor: every document, checklist; given by the Admin).
- `dms_iso_clauses` (our own topic wording + clause number), `dms_catalog_type_clauses` (type → clauses),
  `dms_document_clauses` (manual tags, replaced as a set). New policy types ISP, EPL, OHP, ENP.
- Evidence = published documents by type mapping + manual tags (`private.dms_evidence`); clause status ok / stale
  (only expired or past-review evidence) / gap.
- RPCs: `get_dms_compliance(profile)`, `get_dms_document_clauses`, `set_dms_document_clauses`; `dms_can_read`
  now also lets `dms.audit` read everything.

---

Planned (original plan, kept for the later steps). Conventions (handbook A3, A10): every org table has `org_id uuid not null`,
`unique (org_id, id)`, composite FKs `(org_id, x_id)`, RLS on with **no policies** (closed; RPC only), standard meta
columns (`created_at/by`, `updated_at/by`), `attach_standard_triggers` (audit + no delete). Global catalog tables
are read-only to clients and written only by migrations. Every RPC is `security definer`,
`set search_path = ''`, and starts with a permission check.

---

## 1. Global catalog (platform-owned, seeded by migration) — D1 / D3

| Table | Key columns |
|---|---|
| `dms_iso_profiles` | `code` PK (`ISO_9001`, `ISO_27001`, `ISO_14001`, `ISO_45001`, `BD_STATUTORY`, `BUYER_SOCIAL`, …), `name`, `edition` (e.g. `2015`), `summary` (plain-language line), `who_needs_it`, `default_on`, `sort_order`, `status` |
| `dms_iso_clauses` | PK (`profile_code`, `clause`), `topic` (our own short wording, never the ISO text), `evidence_expected` (bool), `sort_order` |
| `dms_catalog_categories` | `code` PK (`LIC`, `QMS`, `PRC`, `HRP`, `CON`, `REC`, `ISM`, `ENV`, `OHS`), `name`, `parent_code`, `sort_order` |
| `dms_catalog_categories_profiles` | (`category_code`, `profile_code`): which profiles bring a category |
| `dms_catalog_doc_types` | PK (`category_code`, `code`), `name`, `field_schema` jsonb, `has_expiry`, `review_months`, `reminder_days`, `ai_default`, `default_classification` |
| `dms_catalog_doc_type_clauses` | (`category_code`, `type_code`, `profile_code`, `clause`): default clause tags |

`field_schema` is a small declarative list, validated by `private.dms_validate_fields`:
```json
[{"key":"licence_no","label":"Licence number","type":"text","required":true,"max":60},
 {"key":"authority","label":"Issuing authority","type":"text","required":true},
 {"key":"issue_date","label":"Issue date","type":"date"},
 {"key":"expiry_date","label":"Expiry date","type":"date","required":true,"maps_to":"expiry_date"}]
```
Allowed types: `text`, `number`, `date`, `select` (with `options`), `boolean`. No free-form code.

---

## 2. Company file plan and settings — D1

| Table | Key columns |
|---|---|
| `dms_settings` | `org_id` PK, `enabled`, `max_file_mb` (≤ 25), `reminder_steps` int[] (default `{60,30,7,0}`), `require_second_disposal_approver` (default true), `setup_completed_at` |
| `dms_org_profiles` | (`org_id`, `profile_code`), `selected_at`, `selected_by`, `status` (active / inactive) |
| `dms_categories` (the folder tree) | `id`, `org_id`, `code` (`^[A-Z0-9]{2,6}$`; generated for custom folders), `name`, `parent_id` (same org; depth ≤ 3 for custom), `origin` (`base` / `iso` / `custom`), `catalog_code`, `locked` (true for base / iso), `enabled` (switch off; refused while it holds documents unless they are moved), `sort_order`, `status`; unique (`org_id`, `code`), unique (`org_id`, `parent_id`, lower(`name`)) |
| `dms_doc_types` | `id`, `org_id`, `category_id`, `code` (`^[A-Z]{2,4}$`), `name`, `origin`, `locked`, `field_schema`, `has_expiry`, `review_months`, `reminder_days`, `default_classification`, `ai_enabled`, `assistant_topic` (FK `assistant_topics.key`), `reviewer_mode` (none / role / dept_head / person), `reviewer_role_id`, `reviewer_employee_id`, `approver_mode` (role / dept_head / person), `approver_role_id`, `approver_employee_id`, `status`; unique (`org_id`, `category_id`, `code`) |
| `dms_doc_type_clauses` | (`org_id`, `doc_type_id`, `profile_code`, `clause`) |
| `dms_code_sequences` | (`org_id`, `dept_code`, `type_code`) PK, `last_seq`. Taken with `select … for update`; a number is never reused, even if the upload is cancelled |

Departments used by the DMS must have `departments.code` (`^[A-Za-z0-9-]{1,20}$`, upper-cased for the code). The
code is frozen in documents already created; renaming a department code later does not rename documents.

---

## 3. Documents and versions — D1 / D2

| Table | Key columns |
|---|---|
| `dms_documents` | `id`, `org_id`, `doc_code` (unique per org), `seq`, `title`, `category_id`, `doc_type_id`, `department_id`, `owner_employee_id`, `classification` (public / internal / confidential / restricted), `scope` (company / departments), `scope_department_ids` uuid[], `restricted_role_ids` uuid[], `restricted_employee_ids` uuid[], `language` (en / bn / both), `fields` jsonb, `expiry_date`, `next_review_date`, `lifecycle` (draft / in_review / approved / published / archived / disposed), `current_version`, `published_version`, `legal_hold` (bool, maintained by D4), standard meta |
| `dms_versions` | `id`, `org_id`, `document_id`, `version`, `original_file_name`, `file_kind` (pdf / docx / xlsx / json / image), `mime`, `size_bytes`, `file_hash` (`^[0-9a-f]{64}$`), `file_path`, `status` (uploading / uploaded / inspecting / ready / rejected / superseded / disposed), `reject_reason`, `page_count`, `has_text`, `change_note`, `effective_date`, `submitted_at`, `approved_at`, `published_at`, `ai_status` (not_indexed / queued / indexed / failed / excluded); unique (`org_id`, `document_id`, `version`); unique (`org_id`, `file_hash`) where status not in (rejected, disposed) |
| `dms_approvals` — D2 | `id`, `org_id`, `version_id`, `step` (review / approve), `actor_employee_id`, `decision` (approved / rejected / returned), `comment`, `decided_at`. Insert-only |
| `dms_reminders` — D2 | (`org_id`, `document_id`, `kind` (expiry / review), `due_date`, `step_days`) PK, `notification_id`, `sent_at`. Makes reminders idempotent |
| `dms_access_log` — D2 | `id`, `org_id`, `document_id`, `version_id`, `user_id`, `action` (view / download), `at`. Insert-only, purged after the audit retention period |

Check constraints carry the rules: `restricted` needs at least one role or employee; `scope = departments` needs
department ids; `expiry_date` required when the type `has_expiry`.

---

## 4. ISO evidence — D3

| Table | Key columns |
|---|---|
| `dms_document_clauses` | (`org_id`, `document_id`, `profile_code`, `clause`), `source` (type_default / manual), `added_by`. Seeded from the type on create; editable by `dms.manage` |
| `dms_compliance_snapshots` | `id`, `org_id`, `profile_code`, `taken_at`, `taken_by`, `summary` jsonb (clauses with / without evidence). Kept as audit evidence when exported |

---

## 5. Records — D4

| Table | Key columns |
|---|---|
| `dms_retention_rules` | (`org_id`, `doc_type_id`) PK, `start_event` (published / superseded / expiry / archived), `retain_years` (1–100), `action` (review / dispose), `set_by`, `note` |
| `dms_legal_holds` | `id`, `org_id`, `document_id`, `reason`, `placed_by`, `placed_at`, `released_by`, `released_at` |
| `dms_disposals` | `id`, `org_id`, `document_id`, `version_ids` uuid[], `doc_code`, `hashes` text[], `requested_by`, `requested_at`, `approved_by` (≠ requested_by), `approved_at`, `method` (storage_delete), `status` (requested / approved / done / cancelled) |

---

## 6. AI link — D5 (existing assistant tables, widened)

- `assistant_resources` already has `source ('upload','dms')`, `dms_document_id`, `dms_version_id`. D5 adds the
  composite FK to `dms_versions`, widens `kind` to include `xlsx`, and lets `file_path` point into
  `dms-documents`.
- `private.dms_sync_assistant(version_id)` creates / removes the resource in the same transaction as publish,
  supersede, archive, dispose or reclassify.
- `assistant_chunks.location` keeps `p. 4` / `Sheet: Fees`; the answer citation adds `doc_code v{n}`.

---

## 7. RPCs (planned)

| RPC | Permission | Step |
|---|---|---|
| `get_dms_setup()`, `save_dms_settings(...)` | `dms.manage` | D1 |
| `list_dms_profiles()`, `set_dms_profiles(codes text[])` | read: any `dms.*`; write: `dms.manage` | D1 |
| `save_dms_category(...)`, `save_dms_doc_type(...)` | `dms.manage` (locked codes cannot change) | D1 |
| `create_dms_folder(parent_id, name)`, `rename_dms_folder`, `move_dms_document(document_id, folder_id)` | `dms.manage`, or `dms.upload` for subfolders and their own documents; moving never changes code or path | D1 |
| `dms_register_upload(document_id?, doc_type_id, department_id, title, fields, classification, …, file meta)` | `dms.upload` (+ own department or `dms.upload_all`) | D1 |
| `dms_confirm_upload(version_id)`, `dms_cancel_upload(version_id)` | uploader | D1 |
| `list_dms_documents(filters)`, `get_dms_document(id)`, `get_dms_folders()` | reader access rules | D1 |
| `dms_file_url(version_id)` → path for a 60 s signed URL, logs access | reader access rules | D1 |
| `get_dms_overview()` (counts, steps, expiring list) | any `dms.*` | D1 |
| `dms_submit(version_id)`, `dms_decide(version_id, decision, comment)`, `dms_publish(version_id)`, `dms_archive(document_id)` | owner / named reviewer / approver | D2 |
| `list_dms_expiring(from, to)`, `run_dms_reminders()` | `dms.upload` / system | D2 |
| `list_dms_my_tasks()` | any employee | D2 |
| `get_dms_compliance(profile_code)`, `set_dms_document_clauses(...)`, `snapshot_dms_compliance(...)` | `dms.manage`, `dms.audit` | D3 |
| `save_dms_retention_rule`, `place_dms_hold`, `release_dms_hold`, `request_dms_disposal`, `approve_dms_disposal` | `dms.records` | D4 |
| `service_dms_inspect(...)`, `service_dms_dispose_done(...)` | service role only (Edge Function) | D1 / D4 |
| `list_dms_audit(filters)`, `sign_dms_access_review()` | `dms.audit` / `dms.manage` | D6 |

Errors: `42501` not permitted, `P0002` not found, `22023` invalid input, `23514` rule broken (e.g. self-approval,
hold blocks disposal), `23505` duplicate file. Messages are plain English for the UI.

---

## 8. Storage

| Bucket | Public | Limit | Types | Path |
|---|---|---|---|---|
| `dms-documents` | no | 25 MB | application/pdf, …wordprocessingml.document, …spreadsheetml.sheet, application/json, image/jpeg, image/png | `{org_id}/{document_id}/v{n}.{ext}` |

Storage RLS: insert allowed only to a path reserved by `dms_register_upload` for the calling user and still
`uploading`; no select / update / delete policies for clients (downloads only through signed URLs created by the
RPC path check, deletes only by the disposal Edge Function with the service role).

---

## 9. Indexes

- `dms_documents (org_id, category_id, lifecycle)`, `(org_id, department_id)`, `(org_id, expiry_date) where expiry_date is not null`, `(org_id, next_review_date)`
- `dms_documents` trigram or `to_tsvector('simple', doc_code || ' ' || title)` GIN for Library search
- `dms_versions (org_id, document_id, version desc)`, `(org_id, status)`
- `dms_approvals (org_id, version_id)`, `dms_access_log (org_id, document_id, at desc)`

---

## 10. Tests (one SQL file per step, PGlite locally, Supabase by the user)

| Test | Checks (planned) |
|---|---|
| `dms_d1_foundation_test.sql` | org isolation; base folders created without any ISO; custom folder upload still gets `{DEPT}-{TYPE}-{SEQ}`; move keeps code and path; code format and no reuse after cancel; duplicate hash rejected; locked codes immutable; upload refused for another department without `upload_all`; reader cannot see drafts; no delete trigger |
| `dms_d2_governance_test.sql` | self-approval refused; publish supersedes previous version atomically; Confidential hidden from a plain employee; Restricted only for listed roles; reminders idempotent |
| `dms_d3_compliance_test.sql` | multi-profile tags on one document; gap list correct; deselecting a profile keeps used categories |
| `dms_d4_records_test.sql` | no rule → no disposal; hold blocks disposal; same person cannot request and approve; proof row written |
| `dms_d5_ai_test.sql` | only Published Public / Internal AI-enabled versions create resources; supersede / reclassify removes chunks; another org's chunks never returned |
| `dms_d6_audit_test.sql` | access log written on download; audit visible to `dms.audit` only; access review stored |
