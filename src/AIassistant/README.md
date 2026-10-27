# AI assistant module (Part 4)

Design: [docs/Part04Architecture.md](../../docs/Part04Architecture.md). Status: **UI only, preview data**:
the setup is saved in the browser (`localStorage` key `olympus.ai-assistant.v1`). Processing and answers
are simulated until the backend exists.

**Concept:** a company gives two things, an **API key** (Claude, OpenAI or Gemini) and **resources**
(PDF, DOCX, JSON), then sets the **hyperparameters** and the **role access**. After that the assistant is ready.
The backend does the parsing, chunking, embedding and answering. The AI never reads the database: it only gets
passages from the resources the role may read, plus the role's update digest (counts and statuses only).

## Files

| Path | What it holds |
|---|---|
| `core/types.ts` | Shared types (setup, resource, topic, answer). |
| `core/catalog.ts` | Providers and models, roles, topics (matrix rows), file types, hyperparameter ranges, default setup. |
| `core/access.ts` | Who manages (Admin, or HR Manager when handed over), tick ∩ permission, resource audience, readiness checklist. |
| `core/resources.ts` | Upload checks, JSON → passages, chunk estimates, personal-data warning. |
| `core/digest.ts` | The Updates list built from dashboard numbers. |
| `core/answer.ts` | Preview answer engine (keyword retrieval, citations, refusals). The backend replaces it. |
| `data/store.ts` | Preview data layer (zustand + localStorage). Swap for RPC hooks when the backend exists. |
| `data/useAssistant.ts` | Everything the widget needs for one role. |
| `data/sampleData.ts` | Sample resources and dashboard numbers ("Load sample resources"). |
| `nav.ts` | Light sidebar check, so the module stays out of the first download. |
| `widget/` | Floating button and panel: `AssistantWidget`, `UpdatesView`, `ChatView`, `SourceViewer`. |
| `setup/` | `/settings/assistant` page and its tabs: Overview, API key, Resources, Model settings, Role access, Messages, Test as role. |
| `__tests__/` | Unit tests for the core rules. |

## Where it is wired into the app
- `src/components/AppLayout.tsx`: the sidebar item **Setup → AI assistant** (`showIf`) and the lazy `<AssistantWidget />`.
- `src/router.tsx`: `/settings/assistant` and dev `/preview/assistant`.

## When the backend comes (AI1–AI6 in the design doc)
Replace `data/store.ts` with React Query hooks over the RPCs, `core/answer.ts` with the `assistant` Edge Function
call (streaming), and `nav.ts` with the `assistant.manage` permission. The UI components keep their props.
