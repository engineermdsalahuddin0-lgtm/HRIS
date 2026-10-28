# ISO-aligned Document Management System (DMS) with RAG: Architecture

Status: draft v1.0 · Stack: React, FastAPI, S3, Celery + RabbitMQ, PostgreSQL (pgvector), Redis

## 1. Purpose and scope

A DMS that (a) stores, versions, approves and retires company documents under a selected ISO framework, and (b) prepares every approved document for retrieval-augmented generation (RAG) with full source traceability.

In scope: upload, classification, metadata, versioning, approval, retention, access control, audit, ingestion, hybrid retrieval, citations, dashboard.
Out of scope: ISO certification itself. Certification applies to the organisation's management system; the DMS supplies the controls and evidence.

## 2. Design principles

1. **Two fixed layers under one variable layer.** A locked Core (naming, IDs, storage, metadata) sits under Governance and a replaceable ISO Profile. Changing ISO never moves files or forces re-indexing.
2. **Folders are views, not storage.** Folder trees are generated from metadata; S3 paths never contain business names.
3. **The system names things, users do not.** Document codes, version names and S3 keys are generated.
4. **Raw files are immutable.** Original files stay in S3 so any parser, chunker or embedding model can be re-run.
5. **Every chunk is traceable.** Each chunk carries document, version, page, section, classification and ISO tags.
6. **Access control happens before retrieval,** never after generation.
7. **Ingestion is async, idempotent and retryable.**

## 3. Architecture overview

### 3.1 Layers

```
[ ISO Profile layer ]   ISO 9001 | ISO 27001 | ISO 14001 | Custom
   category tree, DocTypes, mandatory fields, retention, clause map
------------------------------------------------------------------
[ Governance layer ]    lifecycle, approval, retention, legal hold, audit
------------------------------------------------------------------
[ Core layer (locked) ] doc code, naming, S3 key, metadata schema,
                        versioning, chunk metadata, access model
------------------------------------------------------------------
[ Storage + RAG ]       S3 | PostgreSQL | pgvector | tsvector | Redis
```

| Layer | Decides | Changed by |
|---|---|---|
| ISO Profile | Categories, DocTypes, clause mapping, default retention | Profile admin (versioned config) |
| Governance | Who approves, how long to keep, when to dispose | Records manager |
| Core | Naming, IDs, S3 path, metadata schema, chunk metadata | Dev team via release only |
| Storage + RAG | Files, relational data, vectors, keyword index | DevOps |

### 3.2 Runtime flow

```
[ React UI: upload + category + DocType + department + fields ]
        |
        v
[ FastAPI: JWT/RBAC -> validation -> SHA-256 dedupe ]
        |
        +--> S3        docs/{doc_uuid}/v{n}/original.{ext}
        +--> Postgres  documents, document_versions (status=uploaded)
        +--> RabbitMQ  ingest task
        |
        v
[ Celery worker ]
   1. Parser Router   (PDF / DOCX / XLSX / JSON, OCR fallback)
   2. Cleaner         (headers, footers, noise, language detect)
   3. Chunker         (section-aware, title/heading prefix)
   4. Embedder        (batch, retry, model version stored)
   5. Indexer         (pgvector + tsvector, one transaction)
   6. Status update   (embedded | failed, retry, DLQ)
        |
        v
[ Query API ]
   user -> access filter -> metadata filter -> hybrid search (RRF)
        -> reranker -> LLM -> answer + citations -> audit log
```

## 4. Core standard (identical for every ISO option)

| Item | Rule | Example |
|---|---|---|
| Document code | `{DEPT}-{TYPE}-{SEQ}`, assigned once, never reused | `HR-POL-0012` |
| Version name | `{code}_v{n}` | `HR-POL-0012_v3` |
| S3 key | `docs/{doc_uuid}/v{n}/original.{ext}` | `docs/7c1e.../v3/original.pdf` |
| Display name | `{code} v{n} - {title}` | `HR-POL-0012 v3 - Leave Policy` |
| Original file name | Metadata only (`original_file_name`) | `leave policy final2.pdf` |
| Mandatory metadata | owner, reviewer, classification, effective date, review date, status, language | |
| Controlled vocabulary | Department, DocType, Classification chosen from lists | |
| Integrity | SHA-256 per file, unique per version | |
| Chunk metadata | `doc_id, version, page, section, category, iso_tags, classification, is_latest, embedding_model` | |

Rules: a new file for an existing `doc_code` is always a new version. Duplicate content is rejected by hash. File type is detected by the system, never asked from the user.

## 5. ISO Profile layer

A profile is data (versioned JSON in the database), not code. Adding an ISO means adding a profile.

```json
{
  "profile": "ISO_9001", "version": "2015",
  "categories": [
    { "code": "QMS", "name": "Quality Manual and Policy",
      "doc_types": [
        { "code": "POL", "name": "Quality Policy", "clause": "5.2",
          "mandatory": true, "review_months": 12, "retention_years": null }
      ]},
    { "code": "REC", "name": "Records",
      "doc_types": [
        { "code": "IAR", "name": "Internal Audit Report", "clause": "9.2" }
      ]}
  ]
}
```

- **Multi-select:** an organisation may select several profiles. Profiles are merged into one category tree.
- **One document, many standards:** a document needed by two ISOs is stored once and tagged `iso_tags = [9001:9.2, 27001:9.2]`. No copies.
- **Compliance view:** per ISO, list tagged documents and show clauses with no evidence.
- **Changing ISO later** adds categories and tags only. Files, names and embeddings are untouched.
- **Locked vs custom:** profile categories are locked; admins add their own under a Custom branch, and Core naming still applies.
- `retention_years` values are placeholders to be set by legal and records owners, not defaults from this document.

## 6. Category, DocType and expiry

- On upload the admin selects Category, Document type and Department. The DocType defines the extra fields.
- Example DocType `Licence`: licence number, issuing authority, issue date, expiry date, reminder days.
- **AI auto-fill:** an LLM extracts category, DocType, numbers and dates from the file; the admin confirms.
- **Expiry dashboard:** 30/60/90-day windows, expired, active, date-range filter, saved views, automatic reminders.
- Date, list and status questions ("which licences expire this month") are answered by SQL, not by vector search.

## 7. Data model (PostgreSQL)

```sql
create extension if not exists vector;

create table categories (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references categories(id),
  code text not null, name text not null, sort_order int default 0
);

create table document_types (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references categories(id),
  code text not null, name text not null,
  field_schema jsonb not null,
  has_expiry boolean default false, reminder_days int default 60
);

create table documents (
  id uuid primary key default gen_random_uuid(),
  doc_code text unique not null, seq int not null,
  title text not null,
  category_id uuid references categories(id),
  doc_type_id uuid references document_types(id),
  department text not null,
  classification text not null default 'internal',
  fields jsonb default '{}',
  owner_id uuid not null, reviewer_id uuid,
  lifecycle_state text not null default 'draft',
  current_version int not null default 1,
  expiry_date date, next_review_date date,
  created_at timestamptz default now()
);

create table document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid references documents(id),
  version int not null,
  original_file_name text, file_type text,
  storage_path text not null, file_hash text not null,
  status text not null default 'uploaded',
  -- uploaded|parsing|chunking|embedding|embedded|failed
  error_message text, retry_count int default 0,
  is_latest boolean default true,
  effective_date date, language text,
  uploaded_at timestamptz default now(),
  unique (document_id, version), unique (file_hash)
);

create table document_chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid references documents(id),
  version_id uuid references document_versions(id),
  chunk_index int not null, content text not null,
  page_number int, sheet_name text, section_heading text,
  department text, category_id uuid, classification text,
  iso_tags text[], is_latest boolean default true,
  chunk_hash text, embedding vector(1536), embedding_model text,
  tsv tsvector generated always as (to_tsvector('simple', content)) stored
);
create index on document_chunks using hnsw (embedding vector_cosine_ops);
create index on document_chunks using gin (tsv);
create index on document_chunks (department, classification, is_latest);
create index on documents (doc_type_id, expiry_date);

create table iso_profiles (
  id uuid primary key default gen_random_uuid(),
  code text not null, version text not null,
  config jsonb not null, is_active boolean default true,
  unique (code, version)
);
create table org_profiles (
  org_id uuid, profile_id uuid references iso_profiles(id),
  selected_at timestamptz default now(), primary key (org_id, profile_id)
);
create table doc_iso_tags (
  document_id uuid references documents(id),
  profile_id uuid references iso_profiles(id),
  clause text, primary key (document_id, profile_id, clause)
);

create table approvals (
  id bigserial primary key, version_id uuid references document_versions(id),
  step text, actor_id uuid, decision text, comment text,
  decided_at timestamptz default now()
);
create table retention_rules (
  doc_type_id uuid references document_types(id) primary key,
  start_event text, retain_years int, action_after text
);
create table legal_holds (
  id uuid primary key default gen_random_uuid(),
  document_id uuid references documents(id),
  reason text, placed_by uuid,
  placed_at timestamptz default now(), released_at timestamptz
);
create table disposition_log (
  id bigserial primary key, document_id uuid, approved_by uuid,
  disposed_at timestamptz default now(), method text
);
create table audit_log (
  id bigserial primary key, user_id uuid, action text,
  document_id uuid, query text, chunk_ids uuid[],
  created_at timestamptz default now()
);
```

Chunk rows copy `department`, `classification`, `is_latest` and `iso_tags` so filters run without joins. Publishing a new version must update `is_latest` in the same transaction.

## 8. Components

### 8.1 Ingestion API (FastAPI)
JWT auth and RBAC; type, size and optional virus (ClamAV) validation; SHA-256 dedupe; generate `doc_code`, UUID and S3 key; write DB row (`status=uploaded`); enqueue task; return `202` with `document_id`.

### 8.2 Parser Router
All parsers return the same shape: `{text, page, sheet, section, is_table}`.

| Type | Parser | Notes |
|---|---|---|
| PDF (text) | PyMuPDF or LlamaParse | Keeps page numbers and layout |
| PDF (scanned) | Tesseract (`ben+eng`) or cloud OCR | Used when no text layer is found |
| DOCX | python-docx or mammoth | Keeps heading structure |
| XLSX | openpyxl or pandas | One unit per sheet; rows as `header: value` text |
| JSON | custom flattener | Key paths kept as context |

### 8.3 Chunker
Split by section first, then by token limit (about 500-800 tokens, 10-15% overlap). Never split a table; repeat the header row when a table must be divided. Prefix each chunk with `Document title > Section heading`. Store `chunk_hash` so unchanged chunks are not re-embedded.

### 8.4 Embedder
Multilingual model (for Bangla and English), for example OpenAI `text-embedding-3-large` or Cohere `embed-multilingual-v3`. Batch calls, backoff on rate limits, store model name and version per chunk to allow a controlled switch and re-index.

### 8.5 Storage
S3 for raw files; PostgreSQL for metadata; pgvector (HNSW) for vectors; `tsvector` (GIN) for keyword search; Redis for Celery results, rate limits and caching. Move vectors to a dedicated engine (Qdrant, Weaviate) only when volume requires it.

### 8.6 Retrieval
1. Build access filter from role, department and classification.
2. Apply metadata filter (`is_latest`, lifecycle `Published`, department, doc type, dates).
3. Vector top 30 plus keyword top 30, merged with Reciprocal Rank Fusion.
4. Rerank to top 5-8 with a cross-encoder reranker.
5. Prompt the LLM with the chunks; require citations (doc code, version, page, passage).
6. If evidence is missing, answer that the documents do not contain it.
7. Log query and chunk IDs.

## 9. Lifecycle, approval, retention, legal hold

**Lifecycle:** Draft -> In Review -> Approved -> Published -> Archived -> Disposed. Only Published documents are visible to general users and RAG. Publishing a new version archives the previous one and marks it obsolete.

**Approval:** each DocType defines reviewer and approver. Every step is stored in `approvals`. An owner cannot approve their own document.

**Retention:** each DocType has a retention rule (start event, years, action after). Values must be set by legal and records owners according to local law and company policy.

**Legal hold:** a hold blocks deletion and disposition. Placing and releasing a hold are audited.

**Disposition:** never automatic. The system lists expired items; the Records manager approves; deletion removes the S3 object, DB rows, chunks and embeddings together; `disposition_log` keeps the proof.

## 10. Security and access control

- RBAC plus department and classification (Public, Internal, Confidential, Restricted).
- Access filters applied in the query itself, before any content reaches the LLM.
- S3 private; pre-signed URLs with short expiry for downloads.
- Encryption at rest (S3 SSE, database) and in transit (TLS).
- Restricted and personal data: masking and a separate access path; decide whether such text may leave the network (external embedding or LLM APIs) or requires a self-hosted model.
- Prompt-injection defence: document text is passed as data, never as instructions.
- Immutable audit log of views, downloads, changes, approvals, holds, disposals and RAG queries.
- Backups with periodic restore tests.

## 11. Mapping ISO needs to DMS features

ISO text is copyrighted; only topics and clause numbers are listed. Verify clause and control numbers against the current standard editions and the organisation's Statement of Applicability.

| Requirement | ISO | DMS feature |
|---|---|---|
| Identification, approval, version control | 9001 cl. 7.5 | doc code, approval log, versions, obsolete control |
| Periodic review | 9001 cl. 7.5 | `next_review_date` and reminders |
| Classification and retention of records | 15489 | category tree (file plan), retention rules |
| Records metadata | 23081 | mandatory metadata in Core |
| Classification and labelling | 27001 | classification field, carried to every chunk |
| Access control | 27001 | RBAC, department and classification filters |
| Logging | 27001 | immutable audit log |
| Encryption and backup | 27001 | SSE, TLS, backup and restore tests |
| Secure deletion | 27001 | disposition workflow and log |
| Personal data protection | 27001 / local law | restricted level, masking |

Outside the software, auditors also expect: a Document Control Procedure, an approved retention schedule, defined roles, periodic access reviews, backup/restore test records, internal audits, and training records.

## 12. RAG governance

- Answer only from Published, latest, permitted chunks.
- Archived or disposed documents leave the index immediately (disposed: fully deleted).
- Every answer cites doc code, version and page.
- Every query and the chunks used are logged.
- Embedding model and chunking version are recorded for reproducible re-index.
- A fixed evaluation set measures hit rate and MRR after any change.

## 13. Dashboard modules and roles

| Module | Purpose |
|---|---|
| Overview | Setup steps, counts, expiry summary |
| Library | Virtual folder tree, file list, filters, search |
| Expiry and renewals | Date ranges, colour status, reminders |
| ISO compliance | Per-ISO view of evidence and gaps by clause |
| Retention | Rules, disposition approvals, legal holds |
| Access | Roles, department permissions, access reviews |
| Audit log | Filterable, exportable activity trail |
| AI assistant | RAG Q&A with citations |

| Role | Capabilities |
|---|---|
| System admin | Select ISO profiles, users and roles, system settings |
| Records manager | File plan, retention, disposition approval, legal hold |
| Document owner | Upload, new versions, own document details |
| Reviewer / Approver | Review and approve (never own documents) |
| Employee | View permitted Published documents, ask questions |
| Auditor (read-only) | View documents, approvals and audit log |

## 14. Observability and evaluation

- Metrics: ingestion time, failure rate, queue depth, query latency, embedding cost.
- Structured logs with trace IDs; error tracking; dashboards (Prometheus/Grafana or equivalent).
- Evaluation set of 20-50 real questions with expected sources; track hit rate and MRR per change to chunk size, model or reranker.
- User feedback on answers feeds the evaluation set.

## 15. Deployment

- Start with Docker Compose: `api`, `worker`, `rabbitmq`, `redis`, `postgres`.
- Scale workers independently (separate queues for CPU-heavy parsing/OCR and for embedding).
- Dev, staging and production environments; secrets in a secret manager; Alembic migrations in CI.
- Ingestion tasks use `acks_late`, at most 3 retries and a dead-letter queue. Each task is idempotent on `version_id`.

## 16. Failure handling

| Step | On failure |
|---|---|
| Upload and hash check | Return error; no DB row created |
| Parse (incl. OCR fallback) | `status=failed`, store error, retry |
| Chunk | Same as parse |
| Embed | Backoff and retry, then dead-letter queue |
| Index | All chunks written in one transaction; no partial data |
| Version switch | Old chunks `is_latest=false` in the same transaction |

The UI shows status and error per file and offers Retry.

## 17. Implementation phases

1. **Foundation:** Core standard, doc code and naming, categories/DocTypes, upload, S3, Celery pipeline, PDF and DOCX, basic vector search.
2. **ISO profiles:** profile tables, merged category tree, ISO tags, compliance view, XLSX/JSON/OCR.
3. **Governance:** lifecycle, approval, versioning, RBAC, expiry dashboard and reminders, audit log.
4. **Retention:** retention rules, disposition, legal hold, backup and restore tests.
5. **RAG and quality:** hybrid search, reranker, RAG controls, evaluation set, monitoring.

## 18. Open decisions

- [ ] Which ISO standards will be selected first (9001, 27001, others)?
- [ ] Who sets retention periods (legal, records manager)?
- [ ] May Restricted content use external embedding or LLM APIs?
- [ ] Who validates the ISO profile content?
- [ ] Final stack: Supabase (Storage + Postgres) or separate S3 + Postgres?