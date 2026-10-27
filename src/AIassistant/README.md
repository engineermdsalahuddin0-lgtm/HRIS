# AI assistant module (Part 4)

Design and backend plan: [docs/Part04Architecture.md](../../docs/Part04Architecture.md).

**Status (2026-10-27): UI done on preview data. Backend designed, not built.**
The setup is saved in this browser (`localStorage` key `olympus.ai-assistant.v1`); resource processing and answers
are simulated. The backend is built later in steps **AI1–AI6** (design doc §11): say "do AI1" and follow that step.

**Concept:** a company gives two things, an **API key** (Claude, OpenAI or Gemini) and **resources** (PDF, DOCX,
JSON), then sets the **hyperparameters** and the **role access**. The Overview checklist then says "ready". The
backend does the parsing, chunking, embedding and answering. The AI never reads the database: it only gets passages
from resources the role may read, plus the role's update digest (counts and statuses only).

**Who manages:** Admin always. HR Manager only after an Admin switches on "HR Manager may manage the assistant"
(Overview); sensitive ticks for HR Manager stay Admin-only.

## Files

| Path | What it holds | After the backend |
|---|---|---|
| `core/types.ts` | Shared types (setup, resource, topic, answer). | Stays. |
| `core/catalog.ts` | Providers and models, roles, topics (matrix rows), file types, hyperparameter ranges, `DEFAULT_SETUP` (= the database seed). | Stays; keep in step with the seed. |
| `core/access.ts` | Who manages, tick ∩ permission, resource readers, readiness checklist, matrix change summary. | Stays (UI checks); the database enforces the same rules. |
| `core/resources.ts` | Upload checks, JSON → passages, chunk estimates, personal-data warning. | Stays for checks before upload. |
| `core/digest.ts` | Updates list from dashboard numbers. | Replaced by `assistant_updates` (AI3); kept for preview/tests. |
| `core/answer.ts` | Preview answer engine (keyword match, citations, refusals). | Replaced by the Edge Function `ask` (AI5); kept for preview/tests. |
| `data/store.ts` | Preview data layer (zustand + localStorage). | Replaced by `data/api.ts` React Query hooks (AI2–AI5), then deleted (AI6). |
| `data/useAssistant.ts` | Everything the widget needs for one role. | Reads the RPCs instead of the store (AI3). |
| `data/sampleData.ts` | Sample resources and dashboard numbers. | Preview and tests only. |
| `nav.ts` | Light sidebar check (keeps the module out of the first download). | Replaced by the `assistant.manage` permission (AI2). |
| `widget/` | `AssistantWidget`, `UpdatesView`, `ChatView`, `SourceViewer`. | Same components; `ChatView` streams from the Edge Function (AI5). |
| `setup/` | `/settings/assistant`: Overview, API key, Resources, Model settings, Role access, Messages, Test as role. | Same tabs on real data; Usage tab added (AI6). |
| `__tests__/` | Unit tests for the core rules (29). | Stay. |

## Wired into the app
- `src/components/AppLayout.tsx`: sidebar item **Setup → AI assistant** (`showIf` + `nav.ts`) and the lazy
  `<AssistantWidget />` on every signed-in page.
- `src/router.tsx`: `/settings/assistant` (the page checks who may open it) and dev `/preview/assistant`.

## Backend files to come (design doc §11)
| Step | Creates | Switches in this folder |
|---|---|---|
| AI1 | `supabase/migrations/20261102000100_assistant_ai1_foundation.sql`, `supabase/tests/assistant_ai1_foundation_test.sql`, pgvector in `scripts/db-test/` | — |
| AI2 | `data/api.ts`, Edge Function `supabase/functions/assistant/` (`test_key`) | Overview, API key, Model settings, Role access, Messages tabs; `nav.ts` → permission |
| AI3 | `…_assistant_ai3_updates.sql` + test | `useAssistant.ts` (digest + config) |
| AI4 | `…_assistant_ai4_resources.sql` + test, Edge `ingest` | Resources tab (upload → ingest loop) |
| AI5 | `…_assistant_ai5_ask.sql` + test, Edge `ask` (SSE) | `ChatView`, `SourceViewer`, Test as role |
| AI6 | Usage RPCs, purge | Usage tab, monthly cap; delete `store.ts` |

## Decisions in force
D1 Updates without a key · D2 Admin controls, may hand over to HR Manager · D3 platform embedding key · providers
Claude / OpenAI / Gemini · D4 DOCX cited by section (approx. page) · D5 Ask on PRO + ENTERPRISE, Updates on all ·
D6 chat history own only, 90 days · D7 question text kept 90 days · D8 limits Employee 20, Manager 30, HR 50, Admin none.
