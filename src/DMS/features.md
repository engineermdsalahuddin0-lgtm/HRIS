# DMS: Features, dashboard and permissions

Architecture: `architecture.md`. Schema: `schema.md`. Security: `security.md`.
The step (D1–D6) that delivers each feature is shown in brackets.

---

## 1. Permissions (Roles & access, module `dms`)

| Key | Default roles | Meaning |
|---|---|---|
| `dms.manage` | Admin (implicit), HR Manager | Setup: ISO profiles, base folders on/off, any folder, document types, approvers, AI switch per type (D1) |
| `dms.upload` | HR Manager, Manager | Upload documents and new versions for their departments; edit drafts they own; create subfolders and move their own documents between folders (D1) |
| `dms.upload_all` | HR Manager | Upload for any department (D1) |
| `dms.approve` | HR Manager | Review and approve versions they are named on; never their own (D2) |
| `dms.view_confidential` | HR Manager, Manager | Read Confidential documents of their department (all departments with `dms.upload_all`) (D2) |
| `dms.records` | none (Admin gives it) | Retention rules, legal hold, disposal approval (D4) |
| `dms.audit` | none (Admin gives it) | Read-only: every document, approvals, audit and access logs; for internal and external auditors (D6) |

Every employee with portal access reads the **Published** Public and Internal documents meant for them without
any permission. Restricted documents are read only by the people and roles listed on the document.

Mapping to the DMS.md roles: System admin = Admin; Records manager = `dms.records`; Document owner = `dms.upload`;
Reviewer / Approver = `dms.approve`; Employee = no permission; Auditor = `dms.audit`.

---

## 2. Dashboard (sidebar: Documents)

The sample dashboard the user shared is the target layout. Tabs:

| Tab | Who sees it | Contents |
|---|---|---|
| **Overview** | any `dms.*` | Setup steps (1 ISO standard, 2 departments and owners, 3 documents, 4 index for AI); counts: documents, expiring in 60 days, awaiting approval, indexed for AI; licences by expiry date with a date range; Upload card; Folders card; Fixed naming standard card (D1, D2) |
| **Library** | everyone | Folder tree from the file plan (with counts), list with code, title, version, status, owner, dates; filters (department, type, status, classification, ISO); search by code / title / text; document page with versions, approvals, related ISO clauses, download (D1) |
| **My documents** | everyone | Documents waiting for my review / approval, my drafts, my documents due for review (D2) |
| **Expiry & renewals** | `dms.upload`, `dms.manage` | 30 / 60 / 90 day windows, expired, active, date range, colour status, "Upload renewal" (creates the next version) (D2) |
| **ISO compliance** | `dms.manage`, `dms.audit` | Per selected profile: clauses with evidence (green), without evidence (gap, red), evidence past review (amber); export (D3) |
| **Retention** | `dms.records` | Rules per type, due-for-disposal list, legal holds, disposal proof log (D4) |
| **Access** | `dms.manage` | Who can see what: per classification and department; quarterly access review sign-off (D6) |
| **Audit log** | `dms.manage`, `dms.audit` | Uploads, changes, approvals, downloads, holds, disposals; filter and CSV export (D6) |
| **Setup** | `dms.manage` | ISO profiles, file plan, document types and fields, approvers, reminders, AI on/off per type (D1–D5) |

UI rules: loading / empty / error state everywhere, mobile-first, actions hidden when the role lacks the permission
(the database still checks), a SpotlightTour target on Upload (`data-tour="dms-upload"`).

---

## 2a. Guiding rule: the user only uploads (user, 2026-10-27)

The user opens a folder and drops a file. The system decides everything else. No duplicates, no mismatches.

**Upload in one step**
- Upload starts from where the user is: inside a folder, the folder is known and the type list shows only that
  folder's types (one type → chosen automatically).
- Department = the uploader's department (changeable only with `dms.upload_all`); owner = the uploader.
- Classification, review date, reminder days, approver, AI indexing: **defaults from the document type**, shown
  folded under "More", never required.
- The form shows only the type's required fields (e.g. licence number + expiry date). With an AI key, auto-fill
  proposes them from the file.
- Live preview before saving: "Will be saved as `HR-POL-0013_v1` in HR Policy".
- If the type needs approval, the document goes to the approver by itself; the uploader does nothing more.
- Several files at once: each gets its own code; the shared fields are asked once.

**No duplication**
| Case | What the system does |
|---|---|
| The exact same file again (same SHA-256) | Refused: "This file is already saved as `HR-POL-0012 v3` in HR Policy" with a link |
| A changed file for a document that exists (same type, department, similar title) | Asks: "Is this a new version of `HR-POL-0012 Leave Policy`?" Yes → v4 of the same code, not a new document |
| Licence renewal | "Upload renewal" on the expiry row → next version of the same licence; the old one is superseded |
| One document needed by several ISOs / folders | Stored once, tagged many times; never copied |

**No mismatch**
- Names are generated, never typed; department, type and authority lists are chosen, not free text.
- One stored value per fact (expiry date, review date, status); every screen, reminder and AI answer reads the same
  column.
- Moving between folders never renames or moves the file.
- Publishing a new version, superseding the old one and updating the AI index happen in one transaction.
- File type is detected from the file itself, never asked.

---

## 3. Feature list

### Core (D1)
- Document code `{DEPT}-{TYPE}-{SEQ}` (e.g. `HR-POL-0012`), assigned once, never reused, sequence per company,
  department and type. Version name `{code}_v{n}`. Display name `{code} v{n} - {title}`.
- Storage path `{org}/{document}/v{n}.{ext}`; original file name kept only as metadata.
- File types: PDF, DOCX, XLSX, JSON (images allowed only for licence scans, not indexed). Max 25 MB.
- Type detected by the system (extension + MIME in the browser, magic bytes in the Edge Function).
- Duplicate content rejected by SHA-256 within the company.
- Mandatory metadata: title, category, type, department, owner, classification, language (EN / BN / both),
  effective date, review date (from the type's review period); type-specific fields (licence number, authority,
  issue / expiry date, reminder days) defined by the type's field list.
- Folders: **base** folders for every company (switch off any), **ISO** folders when a standard is selected
  (optional), **custom** folders and subfolders created by users (up to 3 levels). Labels editable; base and ISO
  codes locked.
- Naming is independent of the folder: every file, in any folder, is named by the system from department + type.
  Custom folders offer all active types plus "General document" (`DOC`). Moving between folders never renames.
- Library, folders as views, versions list, download with a 60-second link.

### Governance (D2)
- Lifecycle Draft → In review → Approved → Published → Superseded / Archived → Disposed.
- Reviewer and approver from the document type (a role, the department head, or a named person); the uploader
  never approves their own version.
- Comments on reject; full approval history per version.
- Classification Public / Internal / Confidential / Restricted; Restricted lists named roles or people.
- Department scope: whole company, or listed departments.
- Expiry and review dates, reminders at 60 / 30 / 7 days and on expiry, by email and in-app.
- "Notify readers": publish a notice that links to the document (Communication module).

### ISO compliance (D3)
- Each document type carries clause tags from the selected profiles; one document can serve several standards
  (stored once, tagged many times).
- Compliance view per standard: clause, topic, evidence documents, status; gap list for the auditor.
- ISO guide page in plain language for clients (§6), also shown in Setup when picking profiles.

### Records (D4)
- Retention rule per type: start event, years, action (review / dispose). No rule = never offered for disposal.
- Legal hold on a document (reason, who, when); blocks archive-to-dispose; release is audited.
- Two-person disposal with proof log (code, version, hash, approvers, time, method).

### AI (D5)
- Published Public / Internal versions of AI-enabled types are indexed into the company's assistant store.
- Citations show doc code, version and page / sheet; clicking opens the Library document page.
- Auto-fill on upload with the company's chat key: suggests title, document type, licence number, dates.
- Questions about dates and lists ("which licences expire this month") are answered from SQL by the
  assistant's Updates digest, not from vectors.
- Assistant setup → Resources becomes "Documents from the DMS" (read-only list with index status and Retry).

### Audit and access review (D6)
- Audit log tab (changes from the standard audit trigger; views and downloads from `dms_access_log`).
- Quarterly access review: `dms.manage` confirms the list of who holds `dms.*` permissions; the sign-off is stored
  as evidence for ISO 27001.
- CSV export of audit, approvals and compliance.

---

## 4. Document types shipped with the profiles (first set)

Base folders (every company): License & Compliance, Buyer Compliance, HR Policy, Contracts, Records & Audits,
General. ISO folders: Quality Manual & Policy and Procedures (9001), Information security (27001), Environment
(14001), Health & Safety (45001).

| Category | Types (code) | Expiry fields |
|---|---|---|
| General (base) | General document (DOC) — usable in any custom folder | — |
| Buyer Compliance (base) | Social Audit Report (SAR), Corrective Action Plan (CAP), Buyer Certificate (BCT), Code of Conduct Acknowledgement (BCA) | certificate expiry |
| License & Compliance (base, BD statutory) | Trade Licence (TRD), Factory Licence (FCT), Fire Licence (FIR), Boiler Certificate (CRT), Environmental Clearance (ENV), BIDA / Import-Export Registration (REG), TIN / VAT / BIN Certificate (TAX) | number, authority, issue date, expiry date, reminder days |
| Quality Manual & Policy | Quality Manual (QMN), Policy (POL), Objectives (OBJ) | review date |
| Procedures & Work instructions | Procedure (PRC), Work Instruction (WIN), Form / Template (FRM) | review date |
| HR Policy | HR Policy (POL), Code of Conduct (COC), Handbook (HBK) | review date |
| Contracts | Supplier Contract (SUP), Customer Contract (CUS), Lease (LSE), NDA (NDA) | start, end date, renewal notice days |
| Records & Audits | Internal Audit Report (IAR), Management Review (MRV), Corrective Action (CAR), Training Record (TRN) | — |
| Information security (27001) | ISMS Scope (SCP), Risk Assessment (RSK), Statement of Applicability (SOA), Asset Inventory (AST), Incident Report (INC), Backup / Restore Test (BKP) | review date |
| Environment (14001) | Aspect & Impact Register (ASP), Legal Register (LEG), Waste Record (WST), Emergency Drill (DRL) | review date |
| Health & Safety (45001) | Hazard / Risk Register (HAZ), Incident & Near-miss (NMS), Safety Committee Minutes (SCM), PPE Register (PPE), Fire Drill (DRL) | review date |

The final list is seeded in D1 and reviewed with the user before the migration is written.

## 5. Default category → assistant topic (D5)

| DMS category | Assistant topic |
|---|---|
| Quality Manual & Policy, Procedures | `kb.company_policy` |
| HR Policy | `kb.hr_rules` |
| Notices / circulars archive | `kb.circulars` |
| Labour law and legal registers | `kb.labour_law` |
| Pay, tax, PF policies | `kb.pay_policy` / `kb.tax_pf_gratuity` |
| Manager guides | `kb.manager_guide` |
| Licences, contracts, audit records, ISMS records | not indexed by default (switch per type in Setup) |

Confidential and Restricted are never indexed, whatever the topic (`kb.confidential` stays for uploads that
existed before D5).

---

## 6. ISO guide for clients (shown in Setup; plain language)

ISO standards are international "good management" rulebooks. A company does not need all of them. Certification is
done by an outside auditor, not by this software; the DMS keeps the documents and the evidence the auditor asks
for. Clause numbers below follow the shared ISO structure (4 context, 5 leadership, 6 planning, 7 support,
8 operation, 9 checking, 10 improvement) and must be checked against the edition the client uses.

| Standard | In one line | Who needs it | Typical documents the auditor asks for |
|---|---|---|---|
| **ISO 9001** Quality | "We do the work the same correct way every time and fix what goes wrong." | Almost every company; most buyers ask for it first | Quality policy (5.2), objectives (6.2), procedures, training records (7.2), document control (7.5), supplier evaluation (8.4), internal audit (9.2), management review (9.3), corrective actions (10.2) |
| **ISO 27001** Information security | "Our data and systems are protected and we can prove it." | IT / software firms, banks, any company holding customer or employee data, buyers asking for data safety | ISMS scope (4.3), security policy (5.2), risk assessment and treatment (6.1.2, 6.1.3), Statement of Applicability, asset list, access reviews, incident log, backup tests |
| **ISO 14001** Environment | "We know how we affect the environment and we control it." | Factories, garments and textiles (buyer and DoE pressure), chemicals | Environmental aspects register (6.1.2), legal register (6.1.3), waste and effluent records, emergency drills (8.2), compliance evaluation (9.1.2) |
| **ISO 45001** Health & safety | "Workers are safe and they have a voice." | Factories, construction, any site with physical risk; strongly expected by buyers in Bangladesh | Hazard and risk register (6.1.2), legal requirements (6.1.3), worker consultation / safety committee (5.4), fire and emergency drills (8.2), incident and near-miss records (10.2) |

Suggested extras (catalog only, switched on when a client needs them):

| Profile | Why it can matter here |
|---|---|
Not ISO, and **not an option to select**: BD statutory licences (License & Compliance) and buyer social compliance
(BSCI / amfori, WRAP, SA8000, Sedex SMETA) are **base folders** that every company gets. A company that does not
need one (e.g. an IT firm without buyers) switches it off in Setup.
| **ISO 50001** Energy | Large factories cutting energy cost; buyers with carbon targets. |
| **ISO 22000** Food safety | Food and beverage companies only. |
| **ISO 22301** Business continuity | Banks, IT and service companies that must keep running after a disaster. |
| **ISO 37001** Anti-bribery | Companies selling to government or large multinationals. |

Advice for a client who is unsure: the base folders already cover licences; start with **ISO 9001**. Add **45001 and 14001** for a
factory, **27001** for a company that handles data. The same document (for example an internal audit report) is
stored once and counts for every standard that needs it.
