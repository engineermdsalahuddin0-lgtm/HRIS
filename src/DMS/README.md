# DMS (Document Management System)

**Status: D1 built and applied on Supabase, test passed (2026-10-27).** D2–D6 planned. Read in this order:

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
  components/          UploadForm, NewVersionForm, FileDrop, FieldInputs (type fields, access), DocumentModal,
                       DocumentTable, FolderTree, SetupPanel (ISO, folders, types, department codes)
  pages/DmsPage.tsx    /documents with tabs Overview · Library · Expiry & renewals · Setup (dms.manage)
  __tests__/dms.test.ts
supabase/migrations/20261104000100_dms_d1_foundation.sql
supabase/tests/dms_d1_foundation_test.sql
```

Route: `/documents` (`?tab=`, `?folder=`, `?doc=`). Sidebar: Communication → Documents, shown to everyone (readers
see only what the read rule allows; Upload and Setup appear with the permission). Setup is a tab, not a separate
route. Department codes are set in Organization → Departments (the "Code" field).
