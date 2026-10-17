# Olympus— Part 3 Architecture

*Payroll · Compensation · Tax, PF and Gratuity · Compliance — Version 1.0 — October 2026 — builds on Parts 1 and 2*

## 0. How to use this document

Give Claude this document, the Part 1 and Part 2 documents, and **one build step at a time** (Section 8). Payroll is money, so every step ends with hand-calculated golden tests (Section 6). Part 3 starts only after Part 2 is tested and tagged. Development runs on a **local Supabase** with **fake seed data**. Performance management is not part of Part 3.

**Rule for numbers:** statutory values (tax slabs, PF rates, gratuity multipliers, overtime hourly divisor, overtime and leave rules) are never typed from memory. They are seeded from verified current sources and confirmed by the company. The figures in the original spec (tax year 2024-25, 26 working days) are placeholders only.

## 1. Scope and final decisions

**In Part 3:** salary components and templates, employee compensation history, increments, bonuses, loans and deductions, payment accounts, payroll runs and payslips, payment sheets, tax and TDS, provident fund, gratuity, hours compliance, grievance box, committees.

**Not in Part 3:** performance reviews, goals, kudos, 1-on-1s, training (a separate part). Direct bank and mobile-wallet integrations (later). Meal scanner devices (later).

| Topic | Decision |
| --- | --- |
| Foundation | Reuse Parts 1 and 2: org\_id on every table, UUID keys, roles and permissions, field visibility, row-level security, soft delete, audit log, legal regime (EPZ or Labour Act). |
| Salary data | Lives in protected tables, readable only by roles the Admin ticked. A Manager does not see salary. An Employee sees only their own payslips. |
| Month | 30-day basis, decided in Part 2. Per-day amount is the monthly amount divided by 30. |
| Overtime | Every grade (EM, MS, OWNER) earns overtime, from the approved overtime records of Part 2. |
| Late penalty | The amount is computed in Part 2 from the company's own policy. Payroll applies it as one deduction line. |
| Legal values | Come from regime rules: EPZ first, Labour Act where EPZ does not cover. A company may set values above the legal rule, not below. |
| Run control | Maker-checker: the person who prepares a run cannot approve it. Approved and locked runs are immutable. Fixes go through adjustments in the next period. |
| Tax, PF, Gratuity | Each is a switch per organization. Payroll works without them. |
| Payment | Payroll produces payment sheets (CSV or XLSX) per payment method. Direct bank and wallet integration comes later. |
| Explainability | Every number on a payslip can be traced to a base, a rate and a source. |

## 2. Backend

### 2.1 Principles

- Same stack and rules as Parts 1 and 2. Every table: UUID key, org\_id, created\_at, updated\_at, created\_by, updated\_by, soft delete or status.
- Money is stored as exact decimals in taka with 2 decimal places, never floating point. Rounding is an explicit setting.
- Compensation, rules and tax tables are versioned with effective dates. Payroll uses the version effective for the period.
- Salary, tax, PF and bank data sit in protected tables with field-level access. Every change and every export writes an audit row.
- Every calculation is repeatable: the same inputs always produce the same slips.

### 2.2 Tables

**3A. Salary structure**

| Table | Key columns | Notes |
| --- | --- | --- |
| salary\_components | id, org\_id, name, code, kind (earning, deduction), calc (percent of basic, percent of gross, fixed), default value, taxable, pf\_applicable, status | Catalog: Basic, House Rent, Medical, Conveyance and more. |
| salary\_templates | id, org\_id, name, description, basic\_amount, status | Reusable structure for a role or grade. |
| salary\_template\_lines | template\_id, component\_id, calc, value |  |
| employee\_compensation | id, org\_id, employee\_id, template\_id, basic, gross, effective\_from, effective\_to, reason, created\_by | Protected. Pay history. The current row has no end date. Never edited: a change closes the old row and opens a new one. |
| employee\_compensation\_lines | compensation\_id, component\_id, amount | Snapshot of resolved amounts. |
| salary\_increments | id, org\_id, employee\_id, type (increment, promotion, correction), old gross, new gross, effective\_date, reason, status (pending, approved, rejected), approved\_by | Approval creates a new compensation row. A back-dated date creates arrears. |
| bonuses | id, org\_id, name, type (festival, performance, incentive, annual, ad hoc), basis (fixed or percent), amount or percent, percent base (basic or gross), payment\_month, minimum service months, eligibility scope (all, department, employees), status |  |
| bonus\_eligibility | bonus\_id, department\_id or employee\_id | Used when scope is not all. |
| employee\_deductions | id, org\_id, employee\_id, type (loan, advance, other), total, installment, start\_month, remaining, status | Installments flow into payroll automatically. |
| meal\_settings | org\_id, meal price, deduction mode (monthly fixed, per meal entered, none) | Optional. |
| meal\_entries | id, org\_id, employee\_id, date, meal\_type, amount, source (manual now, scanner later) | Optional. |
| employee\_payment\_accounts | id, org\_id, employee\_id, method (bank, mobile wallet, cash), bank name, branch, account number, routing number, wallet number, status | Protected, encrypted, shown masked. |
| payroll\_settings | org\_id, deduct\_base (basic or gross), ot\_rate\_basis (basic or gross), pay\_weekly\_off, pay\_holidays, half\_day\_deduction\_percent, unpaid\_leave\_base, rounding rule, negative\_net\_rule, auto\_tds, pf\_enabled, gratuity\_enabled | The month basis (30) is read from the Part 2 work settings. |

**3B. Payroll**

| Table | Key columns | Notes |
| --- | --- | --- |
| payroll\_runs | id, org\_id, period\_month, period\_year, scope (all, branch, department), status (draft, calculated, reviewed, approved, paid, locked), prepared\_by, reviewed\_by, approved\_by, timestamps, totals | One per organization, period and scope. |
| payroll\_slips | id, run\_id, org\_id, employee\_id, compensation\_id, payable\_days, gross, total\_deductions, net, payment\_method, payment\_status, warnings | One per employee per run. |
| payroll\_slip\_lines | id, slip\_id, line\_type (earning, overtime, bonus, arrear, deduction, tax, pf, loan, meal), code, label, base, rate, quantity, amount, source reference | Makes every number traceable. |
| payroll\_adjustments | id, org\_id, employee\_id, apply\_period, type (arrear, correction, manual), amount, reason, status, approved\_by | The only way to fix a locked period. |
| payment\_batches | id, run\_id, method, row count, total, file reference, status | One payment sheet per method. |

**3C. Tax, provident fund, gratuity**

| Table | Key columns | Notes |
| --- | --- | --- |
| tax\_fiscal\_years | id, code, from\_date, to\_date, status | One row per tax year. |
| tax\_slabs | id, fiscal\_year\_id, taxpayer\_type, from\_amount, to\_amount, rate | Seeded from the current NBR rules and verified. |
| tax\_thresholds | fiscal\_year\_id, taxpayer\_type, free threshold |  |
| tax\_minimums | fiscal\_year\_id, zone, minimum tax |  |
| tax\_settings | org\_id, fiscal\_year\_id, auto\_tds, investment rebate rate and caps |  |
| tax\_profiles | id, org\_id, employee\_id, tin, zone, taxpayer\_type, declared investment | Protected. A missing TIN raises a warning. |
| tds\_ledger | id, org\_id, employee\_id, fiscal\_year\_id, month, tds\_amount, challan reference, status | One row per deduction. |
| pf\_settings | org\_id, employee rate, employer rate, basis (basic or gross), minimum service months, vesting schedule |  |
| pf\_members | employee\_id, enrolled\_from, status |  |
| pf\_ledger | id, org\_id, employee\_id, month, employee\_contribution, employer\_contribution, interest, balance |  |
| pf\_withdrawals | id, org\_id, employee\_id, reason, leaving\_date, employee\_portion, employer\_vested\_percent, total, status |  |
| gratuity\_settings | org\_id, basis (last basic or average of last 3 basic), multiplier bands by service years, minimum service months, provision toggle |  |
| gratuity\_provisions | id, org\_id, employee\_id, month, amount |  |
| gratuity\_payouts | id, org\_id, employee\_id, leaving\_date, service\_years, amount, status |  |

**3D. Compliance**

| Table | Key columns | Notes |
| --- | --- | --- |
| compliance\_flags | id, org\_id, employee\_id, period, rule\_key, observed value, limit, status (open, reviewed, accepted), note | Built from Part 2 attendance and overtime. |
| grievances | id, org\_id, anonymous, submitter\_employee\_id (empty when anonymous), tracking\_code, category, description, status (new, in review, resolved, closed), assigned\_to, resolution\_note |  |
| grievance\_events | id, grievance\_id, event, note, actor, created\_at |  |
| committees | id, org\_id, name, purpose, status |  |
| committee\_members | committee\_id, employee\_id, role, from\_date, to\_date |  |
| committee\_meetings | id, org\_id, committee\_id, meeting\_date, agenda, minutes |  |

### 2.3 Payroll calculation (per employee, per month)

**Inputs:** the compensation effective in the period, the Part 2 month summary, regime rules, payroll settings, tax profile, PF and gratuity settings, bonuses, deductions and adjustments. **Steps, in this order:**

1. **Payable days.** Start from 30. Subtract unpaid days: absent days not covered by leave, unpaid leave, days before joining and after leaving. Weekly offs and holidays inside the month stay paid (a setting can change this). February and 31-day months pay the same as any other month.
2. **Earnings.** Every component of the compensation snapshot at its full monthly value. A joiner or leaver gets a proration line equal to the monthly amount times the days not employed divided by 30, taken off.
3. **Daily rate.** Deduction base (basic or gross, by setting, never including overtime or bonus) divided by 30.
4. **Absence deduction.** Daily rate times unpaid days. A half day deducts the configured percent of the daily rate.
5. **Overtime.** Hourly rate is the overtime base divided by the overtime hourly divisor, which is a legal rule value the company confirms. Amount is approved overtime hours by day type times the hourly rate times the multiplier of that day type from the overtime policy. Every grade is included.
6. **Late penalty.** Taken from the Part 2 month summary, which already excludes waived lates. Shown as one deduction line.
7. **Bonuses** due this month: check eligibility and minimum service, then fixed amount or percent of basic or gross.
8. **Arrears and adjustments:** back-dated increments, approved corrections, fixes from earlier periods.
9. **Gross** is all earnings plus overtime, bonuses and arrears, minus any proration.
10. **Provident fund.** Employee contribution is the rate times the PF basis for enrolled and eligible members. The employer contribution is posted to the PF ledger and the employer cost report, not deducted.
11. **TDS** as in Section 2.5.
12. **Other deductions:** loan and advance installments, meal deduction, other approved deductions.
13. **Net** is gross minus all deductions, rounded by the rounding setting. If net would be negative, the negative-net rule applies.
14. **Checks** raise warnings or blockers: attendance not locked, missing compensation, missing bank or wallet account, missing TIN, negative net, a large change from last month.

The employer cost view adds employer PF and the gratuity provision to gross.

The original spec used gross including overtime for the daily rate, a single overtime multiplier, a fixed monthly TDS and 26 working days. This document replaces all four.

### 2.4 Run lifecycle and controls

- States: draft, calculated, reviewed, approved, paid, locked.
- The preparer calculates. A reviewer checks warnings. An approver approves. The preparer cannot approve their own run, and the system enforces it.
- Recalculation is allowed until approval. Changing any input after calculation marks the run stale.
- Approval freezes the slips. Reopening needs a permission and a reason and is audited.
- Payment is marked per payment batch. Locking happens after payment and locks the slips and the month's attendance, leave and overtime (the Part 2 lock flag).
- Fixes after lock are adjustments in the next open period, never edits.
- An employee sees a payslip only after approval (an organization setting can delay it until paid).

### 2.5 Tax and TDS

- Tax tables are versioned per fiscal year. Payroll uses the fiscal year that contains the month. The 2024-25 figures in the spec are not used. Current values are seeded from NBR and verified before real use.
- Taxpayer type, zone and TIN sit in the tax profile. A missing TIN is a warning.
- Projection method: projected annual taxable income is the taxable earnings already paid this fiscal year plus this month's taxable earnings times the remaining months plus known bonuses. Annual tax comes from the slabs, minus the investment rebate, and not below the zone minimum where it applies. Monthly TDS is the annual tax minus the TDS already deducted, divided by the remaining months. It is recomputed every month, so a bonus or increment adjusts it.
- Auto-TDS is off by default: payroll shows a preview and the approver confirms it before it enters the slip.
- The TDS ledger records each deduction and the challan reference. Reports: TDS summary, per-employee certificate, annual statement, TIN coverage.
- Zero tax must work correctly for employees below the threshold.

### 2.6 Provident fund and gratuity

- **PF (switch).** Employee and employer rates, basis, minimum service and the vesting schedule of the employer portion are settings. The spec defaults (10 percent each, basis basic, vesting by service years) are placeholders. The company checks the legal minimum before use.
- Payroll posts the monthly ledger rows. A yearly job posts interest at the rate the company sets.
- Withdrawal at separation is the full employee portion plus the vested employer percent. The calculation and an HR screen are built now. Offboarding will call it later.
- **Gratuity (switch).** Basis, multiplier bands by service years and minimum service are settings, with the same placeholder warning. A monthly provision row is posted when provision is on. The payout calculation is built now.

### 2.7 Compliance rules

- **Hours compliance:** weekly hours and overtime caps come from regime rules and are checked against Part 2 data weekly and monthly. Breaches create flags. HR marks each flag reviewed or accepted with a note.
- **Grievance box:** any employee can submit. An anonymous submission stores no submitter identity at all, not hidden, absent, and gives the person a tracking code to see the status. Handlers see only cases assigned to them or covered by their permission. Every event is logged.
- **Committees:** committees, members with role and term, meetings with agenda and minutes.

### 2.8 Permissions and row-level security

All isolation rules from Parts 1 and 2 apply. New permissions:

- payroll.view\_own, payroll.prepare, payroll.review, payroll.approve, payroll.reopen, payroll.lock
- compensation.view, compensation.edit, increments.approve, bonuses.manage, deductions.manage, payroll\_settings.manage
- payment\_accounts.view (masked by default), payment\_accounts.edit, payment.export
- tax.manage, tax.view\_profiles, pf.manage, gratuity.manage
- compliance.view, compliance.review, grievance.submit, grievance.handle, committees.manage

The Manager role has none of the money permissions by default. An Employee sees only their own payslips. Bank and wallet numbers are masked unless the role has the permission, and every unmasking and export is audited.

### 2.9 Server operations and jobs

1. Calculate or recalculate a run (repeatable, same inputs give the same slips).
2. Review, approve, reopen, mark paid, lock and unlock.
3. Generate payment sheets per method.
4. Generate payslip PDFs in Bangla and English.
5. Apply an approved increment: new compensation row and arrears.
6. Reduce loan and advance balances after approval.
7. Evaluate bonus eligibility.
8. Compute the TDS projection and post the TDS ledger.
9. Post PF ledger rows and run the yearly interest job.
10. Post gratuity provisions.
11. Run the weekly and monthly hours compliance checks.
12. Generate anonymous grievance tracking codes.

## 3. UI

Same style as Parts 1 and 2. Every page has loading, empty and error states, and hides actions the role cannot use.

| Area | Screens |
| --- | --- |
| Payroll | Run list by month. Create run (period, scope). Run page with employee table, warnings, totals and a status stepper. Actions shown by role. Slip detail with every line. Payment sheet downloads. |
| My payslips | Employee's own payslips, detail view, PDF download. |
| Salary templates | KPI tiles, template list, builder with component rows and a gross preview. |
| Components | Component catalog list and form. |
| Employee Financial tab | Current compensation, pay history, add increment, payment accounts (masked), deductions. Only with permission. |
| Increments | Request, approve, history, arrears preview. |
| Bonuses | List and form with eligibility. |
| Deductions | Loans and advances with the installment schedule. |
| Meals (optional) | Settings and monthly entries. |
| Settings: Payroll | All payroll settings with plain-language hints. |
| Tax and TDS | Settings (fiscal year, slabs view), Profiles (TIN, zone, type), Calculator, Reports. |
| Provident Fund | Settings, members, ledger, statement, withdrawal calculator. |
| Gratuity | Settings, provisions, payout calculator. |
| Hours compliance | Flag list, review with note, report. |
| Grievance | Submit form (named or anonymous), my cases, handler inbox, tracking-code lookup. |
| Committees | Committee list, members, meetings and minutes. |
| Employer cost report | Gross, employer PF and gratuity provision by month and branch. |

## 4. Policies

- **Isolation:** no payroll, tax, PF or grievance data crosses organizations.
- **Salary confidentiality:** salary is visible only to roles with the permission and to the employee for their own slip. A Manager does not see it.
- **Maker-checker:** the preparer cannot approve. The system enforces it.
- **Immutability:** approved slips are frozen and locked periods cannot change. Corrections are dated adjustments with a reason.
- **Explainable numbers:** every slip line stores its base, rate, quantity and source.
- **Versioned rules:** compensation, regime rules and tax tables carry effective dates, and history is kept.
- **Statutory values:** never typed from memory. Seeded from verified sources, confirmed by the company, and every change is audited.
- **Money handling:** exact decimals, explicit rounding rule, no floating point.
- **Bank and wallet data:** encrypted at rest, masked by default, never written to logs. Unmasking and exports are audited.
- **Exports:** payment sheets and reports need a permission and are audited.
- **Anonymous grievances:** no identity is stored and the system never tries to trace the submitter.
- **Retention:** payroll records are kept for the period the law and the company require. The company confirms the period. The 3-year audit minimum from Part 2 still applies.

## 5. Total feature list for Part 3

**Backend**

- Salary components, templates and employee compensation history
- Increments with approval and arrears
- Bonuses with eligibility, loans and deductions, optional meals
- Payment accounts (protected) and payroll settings
- Payroll runs, slips, slip lines, adjustments and the run lifecycle
- Payroll calculation for all steps in Section 2.3, with checks
- Payment sheets and payslip PDFs in Bangla and English
- Tax tables, tax profiles, TDS projection and ledger
- Provident fund ledger, interest job, withdrawal calculation
- Gratuity provisions and payout calculation
- Hours compliance flags
- Grievances with anonymity, committees and meetings

**UI**

- Payroll run screens and my payslips
- Templates, components, Financial tab, increments, bonuses, deductions
- Payroll, tax, PF and gratuity settings and screens
- Compliance, grievance and committee screens
- Employer cost report

**Policy**

- Every rule in Section 4 enforced and tested

## 6. Test data and golden tests

**Seed data (fake, local only):** two companies (one on EPZ, one on Labour Act), salary templates for EM, MS and OWNER grades, 3 to 6 months of attendance with month summaries, bonuses, loans, TIN profiles, PF members.

Every payroll test has a hand-calculated expected result written before the code runs.

1. Company A can never see Company B's payroll, tax, PF or grievance data.
2. A Manager sees no salary. An Employee sees only their own slips. HR sees what the Admin ticked.
3. A full month with no events gives gross minus PF and TDS exactly.
4. Absent days and unpaid leave on the 30-day basis. A 28-day February and a 31-day month pay the same.
5. A mid-month joiner and a mid-month leaver are prorated correctly.
6. Two companies with different late penalty rules get the correct deduction each. A waived late is excluded.
7. Overtime for weekday, weekend and holiday, for EM, MS and OWNER grade employees alike.
8. Deduction base of basic and of gross give different daily rates, and neither includes overtime.
9. A back-dated increment creates the right arrears.
10. A festival bonus respects minimum service and eligibility.
11. TDS projection: a bonus month recomputes the later months. A zero-tax employee gets zero. A missing TIN warns.
12. PF contributions, vesting at each service band, and withdrawal at separation.
13. Gratuity payout for each multiplier band.
14. Loan installments reduce the balance to zero and stop.
15. The negative-net rule works as set.
16. The rounding rule gives the expected taka values.
17. Maker-checker blocks the same person from preparing and approving.
18. Recalculating twice gives identical slips.
19. An approved run cannot be edited. A reopen needs a reason and is audited.
20. Locking a run locks that month's attendance, leave and overtime in Part 2.
21. Payment sheet totals equal the slip net totals. Account numbers show masked.
22. The EPZ company and the Labour Act company get their own rule values.
23. A hours-compliance breach creates a flag that HR can review.
24. An anonymous grievance contains no submitter data anywhere.
25. The Bangla payslip PDF renders correctly.

## 7. What done means

All Section 6 tests pass on local Supabase, the feature list in Section 5 is complete, and the work is committed and tagged as the Part 3 release. The statutory values have been confirmed by the company.

## 8. Build order inside Part 3

Each step: build, run its golden tests, commit, then continue.

- **3A, salary structure:** components, templates, compensation history, increments, bonuses, deductions, payment accounts, payroll settings. Test visibility and history first.
- **3B, payroll engine without tax and PF:** run lifecycle, calculation, slips and lines, adjustments, payment sheets, payslip view and PDF, lock integration with Part 2. This is the largest and riskiest step, so most golden tests live here.
- **3C, tax, PF, gratuity:** plug into the engine through the organization switches.
- **3D, compliance:** hours compliance, grievance box, committees. Independent of 3B and 3C and can be built any time after Part 2.
- **Later, not in this release:** performance management, direct bank and wallet integrations, meal scanner.

## 9. Assumptions to confirm

1. Payable days are 30 minus unpaid days. February and 31-day months pay the same.
2. The deduction base and the overtime base are each chosen per organization, basic or gross.
3. Weekly offs and holidays are paid inside the 30 days. No rule that removes pay for days next to an absence unless the company asks.
4. The overtime hourly divisor and all multipliers are legal rule values the company confirms.
5. TDS uses the annual projection method. Auto-TDS is off by default with preview and approval.
6. The 2024-25 tax figures in the spec are stale. Current figures are seeded and verified.
7. PF and gratuity are optional per company. Spec defaults are placeholders that must be checked.
8. Payroll produces payment sheets only. Bank and wallet integration comes later.
9. Maker-checker is mandatory for approval.
10. If net would be negative, net is set to zero and the rest carries to the next month as a deduction.
11. Each slip line is rounded to 2 decimals and the net is rounded to the nearest taka.
12. Meals use a monthly fixed deduction or manual entries now. The scanner comes later.
13. Anonymous grievances store no submitter identity.
14. The payroll record retention period is confirmed by the company. yes..and payment must be traceable by audit log.
15. Performance management is a separate later part.