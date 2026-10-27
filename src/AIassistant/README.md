# AI assistant module (Part 4)

Design: [docs/Part04Architecture.md](../../docs/Part04Architecture.md) (section 12 = revision 2: company keys only,
app guide, DMS later). **Status (2026-10-27): AI1–AI6 built (backend + UI), not yet applied on Supabase.**

**What it does.** A floating assistant on every signed-in page:
- **Updates**: counts and statuses the dashboard already shows, filtered by the role matrix (no key needed).
- **Ask**: answers from the **app guide** (how to use each Olympus page) and the company's **resources** (PDF, DOCX,
  JSON), with citations; page-aware (the current page's guide ranks first), page links, **Show me** (opens the page and
  highlights the control), **error help** (error alerts offer "Ask the assistant"). It never reads business tables.
- A feature the role may not use → "Your role is not permitted for that feature."; a document the role may not read →
  the role's "not allowed" message; personal records → which page to open.

**What a company does (all in the UI, no backend code):** Setup → AI assistant → API keys (chat key; plus an embedding
key when chat is Claude, Voyage recommended) → Resources (index the app guide, upload files) → Model settings → Role
access → Messages → Test as role. Indexing is not training: chunks are embedded with the company's key into its own
rows of the vector store (1024 dimensions, pgvector).

## Files

| Path | What it holds |
|---|---|
| `core/types.ts`, `core/catalog.ts` | Types; topics, hyperparameter ranges, file types, defaults (= the database seed). |
| `core/access.ts` | UI rules (who manages, tick ∩ permission) and the readiness checklist (`serverReadiness`). |
| `core/resources.ts` | Upload checks, JSON parsing / personal-data warning, chunk estimates. |
| `data/api.ts` | Every RPC and the Edge Function calls (setup, keys, resources + indexing, config, updates, ask, history, usage). |
| `data/sampleData.ts` | Sample resources for the unit tests. |
| `bridge.ts` | Tiny link used by error alerts (`Alert` in `components/ui.tsx`) to open the assistant with the error text. |
| `widget/AssistantWidget.tsx` | Floating button + panel (Updates / Ask), error-help listener, Show me spotlight. |
| `widget/LiveChat.tsx` | Ask tab: history, answer reveal, citations (open the document at the page), links, Show me, not helpful. |
| `widget/UpdatesView.tsx` | Updates list + pinned notice. |
| `setup/` | `/settings/assistant`: Overview (checklist, general, monthly cap, HR hand-over), API keys, Resources (app guide + uploads + indexing runner), Model settings, Role access, Messages, Test as role, Usage (Admin). |
| `__tests__/` | Unit tests for the core rules. |

## Backend
| Step | Migration | SQL test |
|---|---|---|
| AI1 foundation | `20261103000100_assistant_ai1_foundation.sql` | `assistant_ai1_foundation_test.sql` |
| AI3 updates | `20261103000200_assistant_ai3_updates.sql` | `assistant_ai3_updates_test.sql` |
| AI4 resources + guide | `20261103000300_assistant_ai4_resources.sql` | `assistant_ai4_resources_test.sql` |
| AI5 ask | `20261103000400_assistant_ai5_ask.sql` | `assistant_ai5_ask_test.sql` |
| AI6 usage + purge | `20261103000500_assistant_ai6_usage.sql` | `assistant_ai6_usage_test.sql` |

(AI2 was UI + Edge Function only.) Edge Function **`supabase/functions/assistant/index.ts`**: actions `test_key`,
`ingest`, `index_guide`, `ask`. Deploy once: `supabase functions deploy assistant` or paste it in Dashboard → Edge
Functions → New function "assistant". It needs no extra secrets (company keys come from the database).

## Known limits (now)
- Answers are returned whole and revealed word by word (no token streaming yet).
- Scanned PDFs (no text layer) are refused with a clear message; upload a text PDF or the DOCX.
- DOCX citations use the section and an approximate page (D4).
- Indexing runs while someone keeps the Resources tab open (resumes where it stopped).
- The purge runs from the Usage tab until pg_cron jobs exist.
- DMS source (`assistant_resources.source = 'dms'`) is prepared in the table; the adapter comes with the DMS.
