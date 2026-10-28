# Olympus HRIS — Feature tracker

What is done and what is left, by module. Updated after every task (rule in `memory.md` A0).
Details of each item: `memory.md` A9 (status board) and each module's architecture file.

**Last updated: 2026-10-28**

| Mark | Meaning |
|---|---|
| ✅ | Built, applied on Supabase, test passed |
| 🟢 | Built and applied; something small still to confirm (see note) |
| 🟡 | Built in code, not applied / not live-tested |
| 📝 | Designed (decisions taken), no code yet |
| ⬜ | Not started |

## Summary

| Area | Done | Left |
|---|---|---|
| Part 1 Core HR + platform | 11 / 11 | Account lockout, phone login (settings, not code) |
| Part 2 Time & attendance | 9 / 12 | Biometric devices, live tracking, scheduled jobs |
| Part 3 Payroll & compliance | 5 / 8 | Hours compliance, grievances & committees, employer cost report |
| Hiring (R1–R7) + organogram | 9 / 9 | Confirm R3–R5 test runs on Supabase |
| Part 4 AI assistant | 6 / 8 | Live test with a real API key; apply the DMS link (D5) |
| Part 5 Communication | 3 / 3 | — |
| DMS | 6 / 6 steps live | XLSX / auto-fill / OCR; policy acknowledgement; transport folder (with TMS) |
| Part 5 other modules | 0 / 8 | Assets, Fleet (TMS), Travel & expense, Reports, Integrations, Settings, Security sessions, System |

---

## Part 1 — Core HR and platform
| Feature | Status | Note |
|---|---|---|
| Foundation (tenancy, roles, audit, soft delete) | ✅ | |
| Login (email or mobile), forced password change | ✅ | |
| Organization: branches, offices, departments, designations, grades, operations | ✅ | |
| Roles & access: permissions + field-level ticks | ✅ | |
| Employees: add, edit, profile, KPIs, search | ✅ | |
| History (transfer / promote), reporting lines | ✅ | |
| Portal access (give, change role, reset password, revoke) | ✅ | |
| Deactivate / reactivate with impact preview | ✅ | |
| Audit log viewer, dashboard on real data | ✅ | |
| Platform SaaS: landing, register, applications, subscriptions, payments | ✅ | |
| Files: photo, signature, NID, company logo, ID card | ✅ | |
| Account lockout after wrong passwords | ⬜ | Needs Supabase Password Verification Hook (may need a paid plan) |
| Phone-only login | ⬜ | Supabase Phone provider is off; needs an SMS provider |

## Part 2 — Time and attendance
| Feature | Status | Note |
|---|---|---|
| Shifts (incl. night), roster, holidays, work rules | ✅ | |
| Check-in / out: web, GPS, QR; breaks | ✅ | |
| Attendance engine, reconciliation, manual fix with audit | ✅ | |
| Leave: types, balances, request, approval, rollover | ✅ | |
| Overtime: policy, automatic + manual, approval | ✅ | |
| Shift swaps | ✅ | |
| Geofences, rotating QR display | ✅ | |
| Period lock for payroll | ✅ | |
| Calendar, monthly summary | ✅ | |
| Biometric devices (registry, push endpoint, PIN mapping) | ⬜ | Deferred (Part 2D) |
| Live tracking | ⬜ | Needs the mobile app |
| Scheduled jobs: daily close, leave rollover, audit purge | ⬜ | pg_cron not scheduled; HR uses "Close / rebuild day" |

## Part 3 — Payroll and compliance
| Feature | Status | Note |
|---|---|---|
| 3A Salary structure, increments + arrears, bonuses, loans, payment accounts | ✅ | |
| 3B Payroll runs, payslips EN/বাংলা, payment sheets, lock | ✅ | |
| 3C Tax / TDS, provident fund, gratuity, law references | 🟢 | Applied; its own test run not confirmed |
| Performance: manual scoring demo, cycles, my reviews | 🟢 | Applied; test not confirmed; full PMS scope still to agree |
| Statutory values (leave, overtime divisor 208, half-day %) | 🟢 | Placeholders until the company confirms |
| 3D Hours compliance flags | ⬜ | |
| 3D Grievances (anonymous), committees, meetings | ⬜ | |
| Employer cost report | ⬜ | |

## Hiring (onboarding process) — `src/onboarding-process/`
| Feature | Status | Note |
|---|---|---|
| R1 Workforce planning, vacancies | ✅ | |
| R2 Job posts, careers page, applications | ✅ | |
| R3 CV screening with AI (`recruit-ai`) | 🟢 | Applied; test run not confirmed |
| R4 Written tests, interviews | 🟢 | Applied; test run not confirmed |
| R5 Email / SMS messages, interview kit (`recruit-notify`) | 🟢 | Applied; test run not confirmed |
| R6 Offers | ✅ | |
| R7 Joining, onboarding checklist, documents | ✅ | |
| Department organogram (+ fix) | ✅ | |
| Hiring flow demo | ✅ | |

## Part 4 — AI assistant — `src/AIassistant/`
| Feature | Status | Note |
|---|---|---|
| AI1 Setup: keys, model, role access matrix, messages | ✅ | |
| AI3 Updates digest (role-based, no database reading by the AI) | ✅ | |
| AI4 Resources upload, app guide (26 articles) | ✅ | |
| AI5 Ask: page-aware, links, "Show me", error help, citations | ✅ | |
| AI6 Usage, log retention, monthly cap | ✅ | |
| Edge Function `assistant` deployed | ✅ | |
| **Live test with a real provider key** | ⚠️ | **Incomplete**: buy an API key, then test; fix whatever the first run reports |
| Documents from the DMS as the only source | 🟢 | DMS D5 applied; Edge Function redeploy to confirm |

## Part 5 — Communication — `src/communication/`
| Feature | Status | Note |
|---|---|---|
| Notices: Bangla version, email copy, read receipts, acknowledge, pin, schedule | ✅ | |
| Helpdesk: categories, auto-routing, office-hours SLA, rating, auto-close | ✅ | |
| Password requests ("Forgot password? Ask HR") | ✅ | |

## DMS (Document Management System) — `src/DMS/`
| Step | Status | Note |
|---|---|---|
| D1 Folders (base / ISO / custom), system naming, upload, versions, duplicate refusal, read access, licences by expiry, 30 June default | ✅ | Next: give departments a code, try a real upload |
| D2 Custodians, document requests, central review (never auto-approved), overdue lists, reminders + renewal tasks | ✅ | |
| D3 ISO checklist (clauses, evidence, gaps, CSV), read-only auditor | ✅ | |
| D4 Retention rules, legal hold, two-person disposal with proof | ✅ | |
| D5 DMS feeds the AI assistant (AI switch per type, citations open the document) | 🟢 | Applied; confirm the Edge Function `assistant` was redeployed |
| D6 Audit log tab, CSV export, quarterly access review | ✅ | |
| XLSX indexing, AI auto-fill on upload, server-side file content check, OCR | ⬜ | Need Edge Function work that could not be run here |
| "Porechi" acknowledgement of new policies | ⬜ | Postponed (can reuse the notice acknowledgement) |
| "Transport & Vehicles" folder | ⬜ | Add when TMS is built |

## Part 5 — Other modules (`docs/Part05Architecture.md`)
| Module | Status | Note |
|---|---|---|
| 16 Assets: registry, asset requests | ⬜ | |
| 17 Fleet: vehicles, drivers → Transport Management System (TMS) | ⬜ | Brings the DMS transport folder |
| 18 Travel & expense: conveyance bills, visits | ⬜ | |
| 19 Reports & insights | ⬜ | |
| 20 Integrations: API keys, webhooks, accounting | ⬜ | |
| 21 Settings (complete): account, preferences, layout, daily email, email templates | ⬜ | Parts exist elsewhere (work schedule = Time setup, leave quotas = Leave types, payroll = Payroll settings); to review |
| 22 Security: access control ✅ (Roles & access), audit log ✅, **sessions** ⬜ | 🟡 | Only sessions left |
| 23 System settings | ⬜ | |

## Cross-cutting, open
- pg_cron jobs (daily close, leave rollover, audit purge, DMS reminders later)
- OCR for scanned PDFs (AI assistant and DMS): postponed
- Browser check of new screens by the agent: not possible in these sessions (no browser tool); the user tests by hand
