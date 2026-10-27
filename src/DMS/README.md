# DMS (Document Management System)

**Status: planned, no code yet.** Read in this order:

1. `architecture.md` — decisions, layers, flows, how it plugs into the app and the AI assistant, build steps D1–D6
2. `features.md` — permissions, dashboard tabs, feature list per step, ISO guide for clients
3. `schema.md` — tables, RPCs, storage, indexes, tests
4. `security.md` — threats, read-access rule, coding rules, release checklist

Source draft: `docs/DMS.md` (the user's, generic stack). Target dashboard: the user's sample (Overview with setup
steps, counts, licences by expiry, Upload card, Folders card, Fixed naming standard card).

## Planned code layout (same shape as `src/communication/`)

```
src/DMS/
  core/        types, naming (doc code / version name), access helpers, field-schema validation, iso catalog labels
  data/        api.ts (React Query hooks over the RPCs), upload.ts (hash, signed upload, confirm)
  components/  UploadCard, FolderTree, DocumentTable, VersionList, ApprovalPanel, ExpiryTable, FieldForm
  pages/       DmsPage (tabs), DocumentPage (/documents/:id), DmsSetupPage
  __tests__/   unit tests for core
supabase/migrations/20261104000x00_dms_d*.sql   (Supabase needs migrations there)
supabase/tests/dms_d*_test.sql
supabase/functions/dms/                         (inspect, autofill, dispose)
```

Routes (planned): `/documents` (tabs), `/documents/:id`, `/settings/documents` (setup). Sidebar: "Documents",
shown to everyone (readers see the Library only).
