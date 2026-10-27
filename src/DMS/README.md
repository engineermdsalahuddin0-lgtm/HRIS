# DMS (Document Management System)

**Status (2026-10-27): D1 applied on Supabase and passed; D2–D6 built and tested locally, not applied yet**
(order and the Edge Function redeploy: `memory.md` A9a). Read in this order:

1. `architecture.md` — decisions, layers, flows, how it plugs into the app and the AI assistant, build steps D1–D6
2. `features.md` — permissions, dashboard tabs, feature list per step, ISO guide for clients
3. `schema.md` — "As built: D1" first, then the plan for later steps
4. `security.md` — threats, read-access rule, coding rules, release checklist

Source draft: `docs/DMS.md` (the user's, generic stack). Target dashboard: the user's sample.

## Code layout

```
src/DMS/
  core/types.ts        RPC shapes
  core/dms.ts          file type detection, 30 June default, expiry badge, folder tree, types per folder
  data/api.ts          React Query hooks; upload = hash → register → storage → confirm (cancel on failure); openFile
  components/          UploadForm, NewVersionForm, FileDrop, FieldInputs (type fields, access), DocumentModal (versions,
                       review, ISO tags, AI status, legal hold), DocumentTable, FolderTree, SetupPanel (ISO, review &
                       reminders, folders + custodians, types + AI switch, department codes), TasksPanel (My tasks,
                       Review queue), ReviewDecision, RequestForm, CompliancePanel, ClauseTags, RecordsPanel, AuditPanel
  pages/DmsPage.tsx    /documents with tabs Overview · Library · My tasks · Review · Expiry & renewals ·
                       ISO compliance · Retention · Audit log · Setup (each shown by permission)
  __tests__/dms.test.ts
supabase/migrations/20261104000100…0600_dms_d1…d6_*.sql   (foundation, governance, compliance, records, ai, audit)
supabase/tests/dms_d1…d6_*_test.sql
supabase/functions/assistant/index.ts                     (D5: downloads DMS files from dms-documents)
```

Route: `/documents` (`?tab=`, `?folder=`, `?doc=`). Sidebar: Communication → Documents, shown to everyone (readers
see only what the read rule allows; Upload and Setup appear with the permission). Setup is a tab, not a separate
route. Department codes are set in Organization → Departments (the "Code" field).
