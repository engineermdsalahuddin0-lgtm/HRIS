# Demo folder (temporary)

Browser-only demos with sample data. Nothing here touches the database, and nothing in the
real app imports from this folder, so it can be deleted in one go.

| Demo | Route | Files |
|---|---|---|
| Hiring flow (R1 → R7 as one story) | `/demo/hiring-flow` (signed in), `/preview/hiring-flow` (dev, no login) | `hiring-flow/` |

The numbers come from the real calculations in `src/onboarding-process/core` (workload, ATS,
tests, composite, organogram simulator), so the demo shows what the system really computes.

## Removing it

1. Delete `src/demo/`.
2. `src/router.tsx`: remove the two lines marked `DEMO` (`/demo/hiring-flow` and the
   `hiring-flow` preview child).
3. `src/components/AppLayout.tsx`: remove the `Hiring flow demo` nav item (marked `DEMO`), its two
   page-title rows, and `PlayCircle` from the icon import.
4. `npm run typecheck` and `npm run build`.

The older demos (Workforce, Job post, Organogram demo tabs) live with their pages in
`src/pages/onboarding/` and `src/onboarding-process/demo/`; they are not part of this folder.
