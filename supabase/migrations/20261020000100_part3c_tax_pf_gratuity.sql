-- =============================================================================
-- Part 3C: income tax (TDS), provident fund, gratuity, and the law / policy
-- reference library (Part 3 architecture, sections 2.2 "3C", 2.5, 2.6).
--
-- Rules:
--   * Every statutory number lives in a table with a reference row that names
--     the law, section, source and verification date. Admin and HR can always
--     see where a calculation comes from (law, company policy or a setting).
--   * Tax tables are versioned per fiscal year (1 July - 30 June) and global;
--     FY 2026-27 is seeded from the Finance Act 2026 figures verified on
--     2026-10-17 (PwC tax summary reviewed 31 July 2026, Daily Star report of
--     the passed Finance Bill). A month outside any seeded year gets no TDS.
--   * TDS uses the annual projection method (doc 2.5): income paid this fiscal
--     year + this month + the regular monthly pay for the remaining months.
--     Auto-TDS off (default) = preview only; on = a "TDS" deduction line.
--   * PF and gratuity are switches per organization. Their rates and bands
--     are company settings that must be confirmed before they are switched on.
--   * The engine of Part 3B is extended, not rewritten: calculate_slip and
--     lock_payroll_run are wrapped, so every 3B golden number stays the same.
--   * Ledgers (TDS, PF, gratuity provision) are posted when a run is locked and
--     are append-only.
-- =============================================================================

do $guard$
begin
  if to_regclass('public.payroll_slips') is null then
    raise exception 'Apply 20261019000100_part3b_payroll_engine.sql first, then run this file again';
  end if;
end;
$guard$;

-- -----------------------------------------------------------------------------
-- 1. Permissions
-- -----------------------------------------------------------------------------
insert into public.permissions (key, module, description, admin_only) values
  ('tax.view_profiles', 'payroll', 'See tax profiles, TDS ledger and tax previews',            false),
  ('tax.manage',        'payroll', 'Edit tax profiles and record TDS challans',                  false),
  ('pf.manage',         'payroll', 'Enrol provident fund members, see ledgers, preview payouts', false),
  ('gratuity.manage',   'payroll', 'See gratuity liability and provisions, preview payouts',     false)
on conflict (key) do nothing;

-- -----------------------------------------------------------------------------
-- 2. Law and policy reference library (global, read-only for users)
-- -----------------------------------------------------------------------------
create table public.statutory_references (
  key          text primary key check (key ~ '^[a-z][a-z0-9_.]{2,60}$'),
  category     text not null check (category in ('law', 'company_policy', 'company_setting')),
  area         text not null check (area in ('tax', 'pf', 'gratuity', 'overtime', 'attendance', 'salary', 'performance')),
  title        text not null,
  title_bn     text,
  law_name     text,
  section      text,
  summary      text not null,
  summary_bn   text,
  source_url   text,
  verified_on  date,
  -- verified: figures checked against the named sources; needs_confirmation:
  -- the company (or its tax / legal adviser) must confirm before relying on it.
  status       text not null default 'needs_confirmation' check (status in ('verified', 'needs_confirmation')),
  sort_order   smallint not null default 100
);

insert into public.statutory_references
  (key, category, area, title, title_bn, law_name, section, summary, summary_bn, source_url, verified_on, status, sort_order)
values
  ('tax.slabs', 'law', 'tax', 'Income tax rates for individuals (FY 2026-27)', 'ব্যক্তি করদাতার আয়কর হার (২০২৬-২৭)',
   'Income Tax Act 2023, as amended by the Finance Act 2026', 'Rates of tax for individuals',
   'After the tax-free threshold: 10% on the next Tk 300,000, 15% on the next Tk 400,000, 20% on the next Tk 500,000, 25% on the next Tk 2,000,000 and 30% on the rest.',
   'করমুক্ত সীমার পর: পরবর্তী ৩,০০,০০০ টাকায় ১০%, পরবর্তী ৪,০০,০০০ টাকায় ১৫%, পরবর্তী ৫,০০,০০০ টাকায় ২০%, পরবর্তী ২০,০০,০০০ টাকায় ২৫% এবং বাকি আয়ে ৩০%।',
   'https://taxsummaries.pwc.com/bangladesh/individual/taxes-on-personal-income', '2026-10-17', 'verified', 10),
  ('tax.thresholds', 'law', 'tax', 'Tax-free income threshold (FY 2026-27)', 'করমুক্ত আয়ের সীমা (২০২৬-২৭)',
   'Income Tax Act 2023, as amended by the Finance Act 2026', 'Tax-free threshold',
   'General Tk 400,000; women and taxpayers aged 65+ Tk 450,000; persons with disability and third-gender Tk 525,000; gazetted war-wounded freedom fighters Tk 550,000; parent or guardian of a person with disability gets Tk 50,000 more.',
   'সাধারণ ৪,০০,০০০ টাকা; নারী ও ৬৫+ বয়সী ৪,৫০,০০০; প্রতিবন্ধী ও তৃতীয় লিঙ্গ ৫,২৫,০০০; গেজেটভুক্ত যুদ্ধাহত মুক্তিযোদ্ধা ৫,৫০,০০০; প্রতিবন্ধী ব্যক্তির পিতা-মাতা/অভিভাবক অতিরিক্ত ৫০,০০০।',
   'https://www.thedailystar.net/business/bangladesh-budget-2025-26/news/finance-bill-passed-tax-free-income-threshold-set-tk-4-lakh-fy2026-27-4211511',
   '2026-10-17', 'verified', 20),
  ('tax.salary_exemption', 'law', 'tax', 'Exempt part of employment income', 'চাকরির আয়ের করমুক্ত অংশ',
   'Income Tax Act 2023', 'Employment income exemption',
   'One-third of employment income or Tk 500,000, whichever is lower, is exempt. Separate allowance exemptions were replaced by this single rule, so components should be taxable unless a specific exemption applies.',
   'চাকরির আয়ের এক-তৃতীয়াংশ অথবা ৫,০০,০০০ টাকা, যেটি কম, করমুক্ত।',
   'https://taxsummaries.pwc.com/bangladesh/individual/deductions', '2026-10-17', 'verified', 30),
  ('tax.investment_rebate', 'law', 'tax', 'Investment tax rebate', 'বিনিয়োগ কর রেয়াত',
   'Income Tax Act 2023, as amended by the Finance Act 2026', 'Tax rebate for investment',
   'Rebate = the lowest of 3% of taxable income, 10% of eligible investment, and Tk 750,000.',
   'রেয়াত = করযোগ্য আয়ের ৩%, যোগ্য বিনিয়োগের ১০% এবং ৭,৫০,০০০ টাকা — এই তিনটির মধ্যে যেটি কম।',
   'https://taxsummaries.pwc.com/bangladesh/individual/deductions', '2026-10-17', 'verified', 40),
  ('tax.minimum_tax', 'law', 'tax', 'Minimum tax', 'ন্যূনতম কর',
   'Income Tax Act 2023, as amended by the Finance Act 2026', 'Minimum tax for individuals',
   'If income is above the tax-free threshold, tax is at least Tk 5,000 (Tk 1,000 for a new taxpayer).',
   'আয় করমুক্ত সীমার বেশি হলে ন্যূনতম কর ৫,০০০ টাকা (নতুন করদাতার জন্য ১,০০০ টাকা)।',
   'https://taxsummaries.pwc.com/bangladesh/individual/taxes-on-personal-income', '2026-10-17', 'verified', 50),
  ('tax.tds_salary', 'law', 'tax', 'Tax deducted at source from salary', 'বেতন থেকে উৎসে কর কর্তন',
   'Income Tax Act 2023', 'Section 86',
   'The employer deducts tax from salary every month at the average rate on the estimated annual income and deposits it to the government. Olympus re-estimates every month (projection method), so a bonus or increment adjusts the later months.',
   'নিয়োগকর্তা প্রতি মাসে আনুমানিক বার্ষিক আয়ের গড় হারে বেতন থেকে কর কেটে সরকারি কোষাগারে জমা দেন।',
   'https://nbr.gov.bd/', '2026-10-17', 'needs_confirmation', 60),
  ('tax.recognised_pf', 'law', 'tax', 'Provident fund contributions as investment', 'ভবিষ্য তহবিলে অবদান বিনিয়োগ হিসেবে',
   'Income Tax Act 2023', 'Allowable investment (recognised provident fund)',
   'Employee and employer contributions to a recognised provident fund count towards the investment used for the rebate.',
   'স্বীকৃত ভবিষ্য তহবিলে কর্মী ও নিয়োগকর্তার অবদান রেয়াতের বিনিয়োগ হিসেবে গণ্য হয়।',
   'https://taxsummaries.pwc.com/bangladesh/individual/deductions', '2026-10-17', 'needs_confirmation', 70),
  ('labour.provident_fund', 'law', 'pf', 'Provident fund for workers', 'শ্রমিকদের ভবিষ্য তহবিল',
   'Bangladesh Labour Act 2006 (as amended) and the Provident Funds Act 1925', 'Section 264',
   'Rates, eligibility and vesting come from the fund rules; a matching 7-10% of basic is common. The 2025-2026 amendments make a fund mandatory for larger employers on the workers'' demand - confirm the current text before use.',
   'হার, যোগ্যতা ও প্রাপ্যতার নিয়ম তহবিলের বিধিমালা থেকে আসে; সাধারণত মূল বেতনের ৭-১০% সমান অবদান।',
   'http://bdlaws.minlaw.gov.bd/act-952.html', '2026-10-17', 'needs_confirmation', 110),
  ('labour.gratuity', 'law', 'gratuity', 'Gratuity', 'গ্র্যাচুইটি',
   'Bangladesh Labour Act 2006 (as amended)', 'Section 2(10)',
   'At least 30 days'' wages for every completed year of service, or 45 days'' wages per year when service is more than 10 years. Service of more than six months in a year counts as a full year. Amendments discussed in 2025-2026 may change the bands - confirm before use.',
   'প্রতি পূর্ণ চাকরি বছরের জন্য অন্তত ৩০ দিনের মজুরি; চাকরি ১০ বছরের বেশি হলে প্রতি বছরে ৪৫ দিনের মজুরি।',
   'http://bdlaws.minlaw.gov.bd/act-952.html', '2026-10-17', 'needs_confirmation', 120),
  ('labour.overtime', 'law', 'overtime', 'Overtime rate', 'ওভারটাইম হার',
   'Bangladesh Labour Act 2006 (as amended)', 'Section 108',
   'Overtime is paid at twice the ordinary hourly rate of basic wage. The hourly divisor and multipliers are company settings that must match the law.',
   'ওভারটাইম মূল মজুরির সাধারণ ঘণ্টা-হারের দ্বিগুণ হারে প্রদেয়।',
   'http://bdlaws.minlaw.gov.bd/act-952.html', '2026-10-17', 'needs_confirmation', 130),
  ('labour.absence_deduction', 'law', 'attendance', 'Deduction for absence', 'অনুপস্থিতির জন্য কর্তন',
   'Bangladesh Labour Act 2006 (as amended)', 'Section 125',
   'A deduction for absence from duty must be in proportion to the period of absence.',
   'অনুপস্থিতির কর্তন অনুপস্থিত সময়ের অনুপাতে হতে হবে।',
   'http://bdlaws.minlaw.gov.bd/act-952.html', '2026-10-17', 'needs_confirmation', 140),
  ('labour.epz', 'law', 'salary', 'EPZ companies', 'ইপিজেড প্রতিষ্ঠান',
   'Bangladesh EPZ Labour Act 2019 and EPZ Labour Rules 2022', null,
   'Companies inside an EPZ follow the EPZ Labour Act instead of the Labour Act 2006; confirm overtime, PF and gratuity values against it.',
   'ইপিজেড-এর প্রতিষ্ঠান শ্রম আইন ২০০৬-এর বদলে ইপিজেড শ্রম আইন ২০১৯ অনুসরণ করে।',
   'https://cdn2.ogrlegal.com/files/labour/act/The-Bangladesh-EPZ-Labour-Act,-2019-English-Version.pdf', '2026-10-17',
   'needs_confirmation', 150),
  ('policy.month_30_days', 'company_policy', 'salary', 'Month = 30 days', 'মাস = ৩০ দিন',
   null, null, 'Daily rate = monthly amount / 30 in every month; February and 31-day months pay the same.',
   'প্রতি মাসে দৈনিক হার = মাসিক অঙ্ক / ৩০।', null, null, 'verified', 200),
  ('policy.salary_structure', 'company_policy', 'salary', 'Salary structure', 'বেতন কাঠামো',
   null, null, 'Components and amounts come from the company''s salary template and the employee''s pay record.',
   'অংশ ও পরিমাণ প্রতিষ্ঠানের বেতন টেমপ্লেট ও কর্মীর বেতন রেকর্ড থেকে আসে।', null, null, 'verified', 210),
  ('policy.late_deduction', 'company_policy', 'attendance', 'Late attendance deduction', 'দেরিতে আসার কর্তন',
   null, null, 'Set by the company in Time setup: so many lates = so many days, or a fixed amount per late.',
   'প্রতিষ্ঠানের নিয়ম অনুযায়ী: নির্দিষ্ট সংখ্যক দেরি = নির্দিষ্ট দিনের কর্তন, অথবা প্রতি দেরিতে নির্দিষ্ট টাকা।', null, null, 'verified', 220),
  ('policy.deduction_base', 'company_setting', 'attendance', 'Deduction base', 'কর্তনের ভিত্তি',
   null, null, 'Absence, half-day and unpaid-leave deductions use basic or gross per payroll settings.',
   'অনুপস্থিতি, অর্ধদিবস ও বিনা বেতনের ছুটির কর্তন বেতন সেটিংস অনুযায়ী মূল বা মোট বেতনের উপর।', null, null, 'verified', 230),
  ('policy.loans', 'company_policy', 'salary', 'Loans and advances', 'ঋণ ও অগ্রিম',
   null, null, 'Installments agreed with the employee; never more than the amount left.',
   'কর্মীর সাথে সম্মত কিস্তি; বাকি অঙ্কের বেশি কখনো নয়।', null, null, 'verified', 240),
  ('policy.bonus', 'company_policy', 'salary', 'Bonuses', 'বোনাস',
   null, null, 'Bonus amount, month, minimum service and eligibility are set by the company.',
   'বোনাসের পরিমাণ, মাস, ন্যূনতম চাকরিকাল ও যোগ্যতা প্রতিষ্ঠান নির্ধারণ করে।', null, null, 'verified', 250),
  ('policy.net_rules', 'company_setting', 'salary', 'Net rounding and negative net', 'নিট রাউন্ডিং ও ঋণাত্মক নিট',
   null, null, 'Net is rounded by the payroll setting; a negative net becomes zero and the rest carries to next month (or blocks the run).',
   'নিট বেতন সেটিংস অনুযায়ী রাউন্ড হয়; ঋণাত্মক হলে শূন্য এবং বাকি পরের মাসে যায়।', null, null, 'verified', 260),
  ('policy.pf_rules', 'company_setting', 'pf', 'Company provident fund rules', 'প্রতিষ্ঠানের ভবিষ্য তহবিল নিয়ম',
   null, null, 'Employee and employer rates, basis, minimum service, interest and vesting are the company''s fund rules (PF settings).',
   'কর্মী ও নিয়োগকর্তার হার, ভিত্তি, ন্যূনতম চাকরিকাল, সুদ ও প্রাপ্যতা প্রতিষ্ঠানের তহবিল বিধি।', null, null, 'verified', 270),
  ('policy.gratuity_rules', 'company_setting', 'gratuity', 'Company gratuity rules', 'প্রতিষ্ঠানের গ্র্যাচুইটি নিয়ম',
   null, null, 'Basis, day bands and minimum service as set in gratuity settings; they must not be below the law.',
   'ভিত্তি, দিনের ধাপ ও ন্যূনতম চাকরিকাল গ্র্যাচুইটি সেটিংস অনুযায়ী; আইনের চেয়ে কম হতে পারবে না।', null, null, 'verified', 280),
  ('policy.performance', 'company_policy', 'performance', 'Performance scoring', 'পারফরম্যান্স স্কোরিং',
   null, null, 'Criteria, weights and the 1-5 scale are set by the company for each review cycle (manual scoring demo).',
   'প্রতিটি মূল্যায়ন চক্রের মানদণ্ড, ওজন ও ১-৫ স্কেল প্রতিষ্ঠান নির্ধারণ করে।', null, null, 'verified', 300);

-- -----------------------------------------------------------------------------
-- 3. Tax tables (global, versioned per fiscal year)
-- -----------------------------------------------------------------------------
create table public.tax_fiscal_years (
  id                        uuid primary key default gen_random_uuid(),
  code                      text not null unique check (code ~ '^\d{4}-\d{2}$'),
  from_date                 date not null,
  to_date                   date not null,
  salary_exempt_divisor     numeric(6, 2) not null,   -- 3 = one-third of employment income
  salary_exempt_cap         numeric(14, 2) not null,
  rebate_income_percent     numeric(5, 2) not null,
  rebate_investment_percent numeric(5, 2) not null,
  rebate_cap                numeric(14, 2) not null,
  minimum_tax               numeric(12, 2) not null,
  minimum_tax_new           numeric(12, 2) not null,
  parent_disabled_extra     numeric(12, 2) not null,
  status                    text not null default 'active' check (status in ('active', 'archived')),
  constraint tax_fiscal_years_range check (to_date > from_date)
);

create table public.tax_thresholds (
  fiscal_year_id uuid not null references public.tax_fiscal_years (id),
  taxpayer_type  text not null check (taxpayer_type in ('general', 'woman_senior', 'disabled', 'third_gender', 'freedom_fighter')),
  threshold      numeric(14, 2) not null check (threshold >= 0),
  primary key (fiscal_year_id, taxpayer_type)
);

-- Bands after the tax-free threshold, in order; width null = the rest.
create table public.tax_slabs (
  fiscal_year_id uuid not null references public.tax_fiscal_years (id),
  band_order     smallint not null,
  width          numeric(14, 2) check (width is null or width > 0),
  rate           numeric(5, 2) not null check (rate between 0 and 100),
  primary key (fiscal_year_id, band_order)
);

with fy as (
  insert into public.tax_fiscal_years (code, from_date, to_date, salary_exempt_divisor, salary_exempt_cap,
                                       rebate_income_percent, rebate_investment_percent, rebate_cap,
                                       minimum_tax, minimum_tax_new, parent_disabled_extra)
  values ('2026-27', '2026-07-01', '2027-06-30', 3, 500000, 3, 10, 750000, 5000, 1000, 50000)
  returning id
), thresholds as (
  insert into public.tax_thresholds (fiscal_year_id, taxpayer_type, threshold)
  select fy.id, t.taxpayer_type, t.threshold from fy,
    (values ('general', 400000), ('woman_senior', 450000), ('disabled', 525000), ('third_gender', 525000),
            ('freedom_fighter', 550000)) as t (taxpayer_type, threshold)
  returning 1
)
insert into public.tax_slabs (fiscal_year_id, band_order, width, rate)
select fy.id, s.band_order, s.width, s.rate from fy,
  (values (1, 300000::numeric, 10::numeric), (2, 400000, 15), (3, 500000, 20), (4, 2000000, 25), (5, null, 30))
    as s (band_order, width, rate);

-- -----------------------------------------------------------------------------
-- 4. Organization tables: tax profiles, TDS ledger, PF, gratuity
-- -----------------------------------------------------------------------------
alter table public.payroll_settings add column tds_apply_minimum_tax boolean not null default true;
alter table public.payroll_settings add column tds_confirmed_at timestamptz;
alter table public.payroll_settings add column tds_confirmed_by uuid references public.user_profiles (id);

create table public.tax_profiles (
  id                  uuid primary key default gen_random_uuid(),
  org_id              uuid not null,
  employee_id         uuid not null,
  tin                 text check (tin is null or tin ~ '^\d{12}$'),
  taxpayer_type       text not null default 'general'
                      check (taxpayer_type in ('general', 'woman_senior', 'disabled', 'third_gender', 'freedom_fighter')),
  is_new_taxpayer     boolean not null default false,
  parent_of_disabled  boolean not null default false,
  declared_investment numeric(14, 2) not null default 0 check (declared_investment between 0 and 999999999),
  note                text check (note is null or char_length(note) <= 300),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id),
  updated_by          uuid references public.user_profiles (id),
  constraint tax_profiles_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint tax_profiles_employee_uq unique (employee_id)
);
select private.attach_standard_triggers('public.tax_profiles');

create table public.tds_ledger (
  id                uuid primary key default gen_random_uuid(),
  org_id            uuid not null,
  employee_id       uuid not null,
  fiscal_year_id    uuid not null references public.tax_fiscal_years (id),
  period_month      date not null,
  run_id            uuid not null,
  slip_id           uuid not null,
  tds_amount        numeric(12, 2) not null check (tds_amount > 0),
  challan_reference text check (challan_reference is null or char_length(challan_reference) <= 60),
  challan_date      date,
  status            text not null default 'posted' check (status in ('posted', 'deposited')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint tds_ledger_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint tds_ledger_run_fk foreign key (org_id, run_id) references public.payroll_runs (org_id, id),
  constraint tds_ledger_slip_uq unique (slip_id)
);

create table public.pf_settings (
  org_id              uuid primary key references public.organizations (id),
  employee_rate       numeric(5, 2) not null default 8 check (employee_rate between 0 and 30),
  employer_rate       numeric(5, 2) not null default 8 check (employer_rate between 0 and 30),
  basis               text not null default 'basic' check (basis in ('basic', 'gross')),
  min_service_months  smallint not null default 0 check (min_service_months between 0 and 120),
  interest_rate       numeric(5, 2) not null default 0 check (interest_rate between 0 and 30),
  -- Employer portion paid out on leaving, by completed years of service.
  vesting             jsonb not null default
                      '[{"min_years":0,"percent":0},{"min_years":3,"percent":50},{"min_years":5,"percent":100}]',
  is_recognised       boolean not null default true,
  confirmed_at        timestamptz,
  confirmed_by        uuid references public.user_profiles (id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  created_by          uuid references public.user_profiles (id),
  updated_by          uuid references public.user_profiles (id)
);

create table public.pf_members (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  employee_id   uuid not null,
  enrolled_from date not null,
  status        text not null default 'active' check (status in ('active', 'left')),
  left_on       date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references public.user_profiles (id),
  updated_by    uuid references public.user_profiles (id),
  constraint pf_members_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint pf_members_employee_uq unique (employee_id)
);
select private.attach_standard_triggers('public.pf_members');

create table public.pf_ledger (
  id              uuid primary key default gen_random_uuid(),
  org_id          uuid not null,
  employee_id     uuid not null,
  period_month    date not null,
  entry_type      text not null check (entry_type in ('contribution', 'interest')),
  employee_amount numeric(12, 2) not null default 0,
  employer_amount numeric(12, 2) not null default 0,
  interest_amount numeric(12, 2) not null default 0,
  run_id          uuid,
  slip_id         uuid,
  note            text,
  created_at      timestamptz not null default now(),
  created_by      uuid references public.user_profiles (id),
  constraint pf_ledger_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint pf_ledger_one_per_month unique (employee_id, period_month, entry_type)
);
create trigger append_only before update or delete on public.pf_ledger
  for each row execute function private.append_only_row();

create table public.gratuity_settings (
  org_id               uuid primary key references public.organizations (id),
  basis                text not null default 'last_basic' check (basis in ('last_basic', 'average_last_3_basic')),
  min_service_months   smallint not null default 12 check (min_service_months between 0 and 120),
  -- Months beyond whole years that count as one more year (law: more than six).
  partial_year_months  smallint not null default 6 check (partial_year_months between 0 and 11),
  -- Days of basic per counted year; the highest band reached applies to all years.
  bands                jsonb not null default '[{"min_years":1,"days":30},{"min_years":11,"days":45}]',
  provision_enabled    boolean not null default false,
  confirmed_at         timestamptz,
  confirmed_by         uuid references public.user_profiles (id),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  created_by           uuid references public.user_profiles (id),
  updated_by           uuid references public.user_profiles (id)
);

create table public.gratuity_provisions (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null,
  employee_id   uuid not null,
  period_month  date not null,
  run_id        uuid not null,
  basic         numeric(12, 2) not null,
  days_per_year numeric(6, 2) not null,
  amount        numeric(12, 2) not null check (amount >= 0),
  created_at    timestamptz not null default now(),
  constraint gratuity_provisions_employee_fk foreign key (org_id, employee_id) references public.employees (org_id, id),
  constraint gratuity_provisions_month_uq unique (employee_id, period_month)
);
create trigger append_only before update or delete on public.gratuity_provisions
  for each row execute function private.append_only_row();

create trigger set_row_meta before insert or update on public.pf_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.pf_settings
  for each row execute function private.audit_row_change();
create trigger set_row_meta before insert or update on public.gratuity_settings
  for each row execute function private.set_row_meta();
create trigger audit after insert or update or delete on public.gratuity_settings
  for each row execute function private.audit_row_change();
create trigger touch before update on public.tds_ledger
  for each row execute function private.touch_updated_at();
create trigger audit after insert or update or delete on public.tds_ledger
  for each row execute function private.audit_row_change();

-- Slip extensions: the tax working (shown step by step), the TDS preview when
-- auto-TDS is off, the employer PF cost and the taxable part of the earnings.
alter table public.payroll_slips add column taxable_earnings numeric(12, 2) not null default 0;
alter table public.payroll_slips add column tds_preview      numeric(12, 2) not null default 0;
alter table public.payroll_slips add column employer_pf      numeric(12, 2) not null default 0;
alter table public.payroll_slips add column tax_detail       jsonb;

alter table public.payroll_slip_lines drop constraint payroll_slip_lines_line_type_check;
alter table public.payroll_slip_lines add constraint payroll_slip_lines_line_type_check check (line_type in (
  'earning', 'proration', 'overtime', 'bonus', 'arrear', 'adjustment',
  'component_deduction', 'absence', 'half_day', 'unpaid_leave', 'unpaid_off_day', 'late',
  'loan', 'carry_forward', 'pf', 'tax'));

-- -----------------------------------------------------------------------------
-- 5. Defaults for organizations
-- -----------------------------------------------------------------------------
create or replace function private.seed_statutory_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.role_permissions (org_id, role_id, permission_key)
  select r.org_id, r.id, permission_key
  from public.roles r
  cross join lateral unnest(case r.system_key
    when 'hr_manager' then array['tax.view_profiles', 'tax.manage', 'pf.manage', 'gratuity.manage']
    else array[]::text[]
  end) as permission_key
  where r.org_id = p_org_id
  on conflict do nothing;

  insert into public.pf_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
  insert into public.gratuity_settings (org_id) values (p_org_id) on conflict (org_id) do nothing;
end;
$$;

create or replace function private.seed_org_defaults(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.grades (org_id, code, category, level, description) values
    (p_org_id, 'EM0',     'EM',    0,  'Employee level 0'),
    (p_org_id, 'EM1',     'EM',    1,  'Employee level 1'),
    (p_org_id, 'EM2',     'EM',    2,  'Employee level 2'),
    (p_org_id, 'EM3',     'EM',    3,  'Employee level 3'),
    (p_org_id, 'EM4',     'EM',    4,  'Employee level 4'),
    (p_org_id, 'MS0',     'MS',    10, 'Management level 0'),
    (p_org_id, 'MS1',     'MS',    11, 'Management level 1'),
    (p_org_id, 'MS2',     'MS',    12, 'Management level 2'),
    (p_org_id, 'OWNER01', 'OWNER', 20, 'Owner level 1'),
    (p_org_id, 'OWNER02', 'OWNER', 21, 'Owner level 2')
  on conflict (org_id, code) do nothing;
  perform private.seed_default_field_access(p_org_id);
  perform private.seed_time_defaults(p_org_id);
  perform private.seed_payroll_defaults(p_org_id);
  perform private.seed_statutory_defaults(p_org_id);
end;
$$;

select private.seed_statutory_defaults(id) from public.organizations;

-- -----------------------------------------------------------------------------
-- 6. Calculation helpers
-- -----------------------------------------------------------------------------
create or replace function private.fiscal_year_for(p_date date)
returns public.tax_fiscal_years
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.tax_fiscal_years
  where p_date between from_date and to_date and status = 'active'
  limit 1
$$;

-- Annual tax for one person, with every step kept for the "how was this
-- calculated" view. Pure function of the inputs and the fiscal-year tables.
create or replace function private.compute_annual_tax(
  p_fiscal_year_id  uuid,
  p_taxpayer_type   text,
  p_parent_disabled boolean,
  p_new_taxpayer    boolean,
  p_annual_income   numeric,
  p_investment      numeric,
  p_apply_minimum   boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_year          public.tax_fiscal_years;
  v_threshold     numeric;
  v_income        numeric := greatest(coalesce(p_annual_income, 0), 0);
  v_exempt        numeric;
  v_taxable       numeric;
  v_remaining     numeric;
  v_band_from     numeric;
  v_in_band       numeric;
  v_band_tax      numeric;
  v_gross_tax     numeric := 0;
  v_bands         jsonb;
  v_band          record;
  v_rebate_income numeric;
  v_rebate_invest numeric;
  v_rebate        numeric;
  v_after_rebate  numeric;
  v_minimum       numeric := 0;
  v_annual_tax    numeric;
begin
  select * into v_year from public.tax_fiscal_years where id = p_fiscal_year_id;
  select threshold into v_threshold from public.tax_thresholds
   where fiscal_year_id = v_year.id and taxpayer_type = coalesce(p_taxpayer_type, 'general');
  if v_threshold is null then
    select threshold into v_threshold from public.tax_thresholds
     where fiscal_year_id = v_year.id and taxpayer_type = 'general';
  end if;
  v_threshold := v_threshold + case when p_parent_disabled then v_year.parent_disabled_extra else 0 end;

  -- Exempt part of employment income: one-third, capped.
  v_exempt  := least(private.round_money(v_income / v_year.salary_exempt_divisor), v_year.salary_exempt_cap);
  v_taxable := v_income - v_exempt;

  -- Bands: the tax-free threshold first, then the slabs in order.
  v_in_band := least(v_taxable, v_threshold);
  v_bands := jsonb_build_array(jsonb_build_object('from', 0, 'to', v_threshold, 'rate', 0,
                                                  'amount_in_band', v_in_band, 'tax', 0));
  v_remaining := v_taxable - v_in_band;
  v_band_from := v_threshold;
  for v_band in select width, rate from public.tax_slabs where fiscal_year_id = v_year.id order by band_order loop
    v_in_band := case when v_band.width is null then v_remaining else least(v_remaining, v_band.width) end;
    v_band_tax := private.round_money(v_in_band * v_band.rate / 100);
    v_bands := v_bands || jsonb_build_object('from', v_band_from,
                                             'to', case when v_band.width is null then null else v_band_from + v_band.width end,
                                             'rate', v_band.rate, 'amount_in_band', v_in_band, 'tax', v_band_tax);
    v_gross_tax := v_gross_tax + v_band_tax;
    v_remaining := v_remaining - v_in_band;
    v_band_from := v_band_from + coalesce(v_band.width, 0);
  end loop;

  -- Investment rebate: the lowest of three limits, never more than the tax.
  v_rebate_income := private.round_money(v_taxable * v_year.rebate_income_percent / 100);
  v_rebate_invest := private.round_money(greatest(coalesce(p_investment, 0), 0) * v_year.rebate_investment_percent / 100);
  v_rebate := least(v_rebate_income, v_rebate_invest, v_year.rebate_cap, v_gross_tax);
  v_after_rebate := v_gross_tax - v_rebate;

  if p_apply_minimum and v_taxable > v_threshold then
    v_minimum := case when p_new_taxpayer then v_year.minimum_tax_new else v_year.minimum_tax end;
  end if;
  v_annual_tax := greatest(v_after_rebate, v_minimum);

  return jsonb_build_object(
    'fiscal_year', v_year.code, 'taxpayer_type', coalesce(p_taxpayer_type, 'general'),
    'annual_income', v_income,
    'exempt', v_exempt, 'exempt_rule', jsonb_build_object('divisor', v_year.salary_exempt_divisor,
                                                           'cap', v_year.salary_exempt_cap),
    'taxable_income', v_taxable, 'threshold', v_threshold, 'bands', v_bands, 'gross_tax', v_gross_tax,
    'investment', greatest(coalesce(p_investment, 0), 0),
    'rebate', jsonb_build_object('by_income', v_rebate_income, 'income_percent', v_year.rebate_income_percent,
                                 'by_investment', v_rebate_invest, 'investment_percent', v_year.rebate_investment_percent,
                                 'cap', v_year.rebate_cap, 'applied', v_rebate),
    'tax_after_rebate', v_after_rebate, 'minimum_tax', v_minimum, 'annual_tax', v_annual_tax,
    'references', jsonb_build_array('tax.salary_exemption', 'tax.thresholds', 'tax.slabs',
                                    'tax.investment_rebate', 'tax.minimum_tax'));
end;
$$;

-- Recomputes a slip's totals and net after statutory lines were added. Same
-- rules as the 3B engine (rounding, negative net, large-change warning).
create or replace function private.finalize_slip_totals(p_slip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slip         public.payroll_slips;
  v_settings     public.payroll_settings;
  v_gross        numeric;
  v_deductions   numeric;
  v_net_raw      numeric;
  v_net          numeric;
  v_carry_out    numeric := 0;
  v_warnings     jsonb;
  v_previous_net numeric;
begin
  select * into v_slip from public.payroll_slips where id = p_slip_id;
  select * into v_settings from public.payroll_settings where org_id = v_slip.org_id;

  select coalesce(sum(amount) filter (where direction = 'earning'), 0),
         coalesce(sum(amount) filter (where direction = 'deduction'), 0)
    into v_gross, v_deductions
  from public.payroll_slip_lines where slip_id = p_slip_id;

  select coalesce(jsonb_agg(w), '[]'::jsonb) into v_warnings
  from jsonb_array_elements(v_slip.warnings) w
  where w ->> 'code' not in ('negative_net', 'large_change');

  v_net_raw := v_gross - v_deductions;
  if v_net_raw < 0 then
    v_net := 0;
    if v_settings.negative_net_rule = 'zero_and_carry' then
      v_carry_out := -v_net_raw;
      v_warnings := v_warnings || jsonb_build_object('code', 'negative_net', 'severity', 'warning',
        'message', 'Deductions exceed earnings; ' || v_carry_out || ' carried to next month');
    else
      v_warnings := v_warnings || jsonb_build_object('code', 'negative_net', 'severity', 'blocker',
        'message', 'Deductions exceed earnings by ' || (-v_net_raw));
    end if;
  else
    v_net := private.round_net(v_net_raw, v_settings.net_rounding);
  end if;

  select s.net into v_previous_net
  from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id and r.status in ('approved', 'paid', 'locked')
  where s.employee_id = v_slip.employee_id and s.period_month = (v_slip.period_month - interval '1 month')::date;
  if v_previous_net is not null and v_previous_net > 0
     and abs(v_net - v_previous_net) / v_previous_net * 100 > v_settings.large_change_percent then
    v_warnings := v_warnings || jsonb_build_object('code', 'large_change', 'severity', 'warning',
      'message', 'Net changed by ' || round(abs(v_net - v_previous_net) / v_previous_net * 100) || '% from last month');
  end if;

  update public.payroll_slips
     set gross_earnings = v_gross, total_deductions = v_deductions,
         net_before_rounding = case when v_net_raw < 0 then v_net_raw else private.round_money(v_net_raw) end,
         rounding_adjustment = case when v_net_raw < 0 then 0 else v_net - private.round_money(v_net_raw) end,
         net = v_net, carry_forward_out = v_carry_out, warnings = v_warnings,
         has_blocker = exists (select 1 from jsonb_array_elements(v_warnings) w where w ->> 'severity' = 'blocker')
   where id = p_slip_id;
end;
$$;

-- Adds provident fund and TDS to a calculated slip.
create or replace function private.apply_statutory_lines(p_slip_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slip             public.payroll_slips;
  v_employee         public.employees;
  v_settings         public.payroll_settings;
  v_pf               public.pf_settings;
  v_profile          public.tax_profiles;
  v_year             public.tax_fiscal_years;
  v_month_end        date;
  v_changed          boolean := false;
  v_pf_basis         numeric;
  v_pf_employee      numeric := 0;
  v_pf_employer      numeric := 0;
  v_taxable_now      numeric;
  v_regular_taxable  numeric;
  v_remaining_months integer;
  v_future_months    integer;
  v_ytd_income       numeric;
  v_ytd_tds          numeric;
  v_ytd_pf           numeric;
  v_projected        numeric;
  v_investment       numeric;
  v_detail           jsonb;
  v_annual_tax       numeric;
  v_tds              numeric;
  v_warnings         jsonb;
begin
  select * into v_slip from public.payroll_slips where id = p_slip_id;
  if v_slip.compensation_id is null then
    return;
  end if;
  select * into v_employee from public.employees where id = v_slip.employee_id;
  select * into v_settings from public.payroll_settings where org_id = v_slip.org_id;
  v_month_end := private.month_end(v_slip.period_month);
  v_warnings := v_slip.warnings;

  -- Provident fund: enrolled members with enough service; employer part is a cost.
  if v_settings.pf_enabled then
    select * into v_pf from public.pf_settings where org_id = v_slip.org_id;
    if exists (select 1 from public.pf_members m
               where m.employee_id = v_slip.employee_id and m.status = 'active' and m.enrolled_from <= v_month_end)
       and private.service_months(v_employee.join_date, v_month_end) >= v_pf.min_service_months then
      v_pf_basis := private.round_money(
        case v_pf.basis when 'gross' then v_slip.monthly_gross else v_slip.monthly_basic end * v_slip.employed_days / 30.0);
      v_pf_employee := private.round_money(v_pf_basis * v_pf.employee_rate / 100);
      v_pf_employer := private.round_money(v_pf_basis * v_pf.employer_rate / 100);
      if v_pf_employee > 0 then
        insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                               amount, sort_order)
        values (v_slip.org_id, p_slip_id, 'deduction', 'pf', 'PF_EE', 'Provident fund (employee)', v_pf_basis,
                v_pf.employee_rate, 1, v_pf_employee, 1500);
        v_changed := true;
      end if;
      update public.payroll_slips set employer_pf = v_pf_employer where id = p_slip_id;
    end if;
  end if;

  -- Taxable earnings: every earning except components marked non-taxable.
  select coalesce(sum(l.amount) filter (where l.direction = 'earning'), 0)
         - coalesce(sum(l.amount) filter (where l.direction = 'earning' and ecl.taxable is false), 0)
    into v_taxable_now
  from public.payroll_slip_lines l
  left join public.employee_compensation_lines ecl
    on l.source_table = 'employee_compensation_lines' and ecl.id = l.source_id
  where l.slip_id = p_slip_id;

  v_year := private.fiscal_year_for(v_slip.period_month);
  if v_year.id is null then
    if v_settings.auto_tds then
      v_warnings := v_warnings || jsonb_build_object('code', 'no_tax_year', 'severity', 'warning',
        'message', 'No tax table for this month; TDS not calculated');
    end if;
    update public.payroll_slips set taxable_earnings = v_taxable_now, warnings = v_warnings where id = p_slip_id;
    if v_changed then
      perform private.finalize_slip_totals(p_slip_id);
    end if;
    return;
  end if;

  select * into v_profile from public.tax_profiles where employee_id = v_slip.employee_id;

  -- Months left in the fiscal year, this one included; fewer if the person leaves.
  v_remaining_months := ((6 - extract(month from v_slip.period_month)::int + 12) % 12) + 1;
  v_future_months := v_remaining_months - 1;
  if v_employee.exit_date is not null and v_employee.exit_date < v_year.to_date then
    v_future_months := greatest(0, least(v_future_months,
      (extract(year from v_employee.exit_date)::int * 12 + extract(month from v_employee.exit_date)::int)
      - (extract(year from v_slip.period_month)::int * 12 + extract(month from v_slip.period_month)::int)));
  end if;

  select coalesce(sum(l.amount), 0) into v_regular_taxable
  from public.employee_compensation_lines l
  where l.compensation_id = v_slip.compensation_id and l.kind = 'earning' and l.taxable;

  -- Already paid this fiscal year (approved, paid or locked runs only).
  select coalesce(sum(s.taxable_earnings), 0),
         coalesce(sum((select coalesce(sum(l.amount), 0) from public.payroll_slip_lines l
                       where l.slip_id = s.id and l.code = 'TDS')), 0),
         coalesce(sum(s.employer_pf + (select coalesce(sum(l.amount), 0) from public.payroll_slip_lines l
                                       where l.slip_id = s.id and l.code = 'PF_EE')), 0)
    into v_ytd_income, v_ytd_tds, v_ytd_pf
  from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id and r.status in ('approved', 'paid', 'locked')
  where s.employee_id = v_slip.employee_id and s.period_month >= v_year.from_date and s.period_month < v_slip.period_month;

  v_projected := v_ytd_income + v_taxable_now + v_regular_taxable * v_future_months;
  v_investment := coalesce(v_profile.declared_investment, 0);
  if v_settings.pf_enabled and v_pf.is_recognised then
    v_investment := v_investment + v_ytd_pf + (v_pf_employee + v_pf_employer) * (1 + v_future_months);
  end if;

  v_detail := private.compute_annual_tax(v_year.id, v_profile.taxpayer_type, coalesce(v_profile.parent_of_disabled, false),
                                         coalesce(v_profile.is_new_taxpayer, false), v_projected, v_investment,
                                         v_settings.tds_apply_minimum_tax);
  v_annual_tax := (v_detail ->> 'annual_tax')::numeric;
  v_tds := greatest(private.round_money((v_annual_tax - v_ytd_tds) / (1 + v_future_months)), 0);

  v_detail := v_detail || jsonb_build_object(
    'projection', jsonb_build_object(
      'ytd_income', v_ytd_income, 'this_month', v_taxable_now, 'regular_monthly', v_regular_taxable,
      'future_months', v_future_months, 'months_remaining', 1 + v_future_months, 'projected_income', v_projected,
      'declared_investment', coalesce(v_profile.declared_investment, 0),
      'pf_investment', v_investment - coalesce(v_profile.declared_investment, 0)),
    'ytd_tds', v_ytd_tds, 'monthly_tds', v_tds, 'auto_tds', v_settings.auto_tds,
    'has_profile', v_profile.id is not null, 'has_tin', v_profile.tin is not null,
    'references', (v_detail -> 'references') || '["tax.tds_salary", "tax.recognised_pf"]'::jsonb);

  if v_settings.auto_tds and v_tds > 0 then
    insert into public.payroll_slip_lines (org_id, slip_id, direction, line_type, code, label, base, rate, quantity,
                                           amount, sort_order)
    values (v_slip.org_id, p_slip_id, 'deduction', 'tax', 'TDS', 'Income tax (TDS)', v_annual_tax - v_ytd_tds, null,
            1 + v_future_months, v_tds, 1600);
    v_changed := true;
  end if;
  if v_annual_tax > 0 and v_profile.tin is null then
    v_warnings := v_warnings || jsonb_build_object('code', 'missing_tin', 'severity', 'warning',
      'message', 'Tax is due but no TIN is on record');
  end if;

  update public.payroll_slips
     set taxable_earnings = v_taxable_now, tds_preview = v_tds, tax_detail = v_detail, warnings = v_warnings
   where id = p_slip_id;
  if v_changed then
    perform private.finalize_slip_totals(p_slip_id);
  end if;
end;
$$;

-- Wrap the 3B engine: the original becomes calculate_slip_core.
alter function private.calculate_slip(uuid, uuid) rename to calculate_slip_core;

create or replace function private.calculate_slip(p_run_id uuid, p_employee_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slip_id uuid;
begin
  perform private.calculate_slip_core(p_run_id, p_employee_id);
  select id into v_slip_id from public.payroll_slips where run_id = p_run_id and employee_id = p_employee_id;
  perform private.apply_statutory_lines(v_slip_id);
end;
$$;

-- The inputs fingerprint also covers tax, PF and earlier months of the fiscal year.
alter function private.payroll_inputs_fingerprint(uuid, date) rename to payroll_inputs_fingerprint_core;

create or replace function private.payroll_inputs_fingerprint(p_org_id uuid, p_month date)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select md5(concat_ws('|',
    private.payroll_inputs_fingerprint_core(p_org_id, p_month),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.tax_profiles where org_id = p_org_id),
    (select count(*) || ':' || coalesce(max(updated_at)::text, '') from public.pf_members where org_id = p_org_id),
    (select coalesce(max(updated_at)::text, '') from public.pf_settings where org_id = p_org_id),
    (select count(*) || ':' || coalesce(sum(s.taxable_earnings), 0)
       from public.payroll_slips s join public.payroll_runs r on r.id = s.run_id
      where s.org_id = p_org_id and s.period_month < p_month and s.period_month >= (p_month - interval '12 months')::date
        and r.status in ('approved', 'paid', 'locked'))))
$$;

-- Locking also posts the TDS, PF and gratuity ledgers.
alter function public.lock_payroll_run(uuid) set schema private;
alter function private.lock_payroll_run(uuid) rename to lock_payroll_run_core;

create or replace function public.lock_payroll_run(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run      public.payroll_runs;
  v_gratuity public.gratuity_settings;
  v_year     public.tax_fiscal_years;
begin
  perform private.lock_payroll_run_core(p_run_id);
  select * into v_run from public.payroll_runs where id = p_run_id;
  v_year := private.fiscal_year_for(v_run.period_month);

  if v_year.id is not null then
    insert into public.tds_ledger (org_id, employee_id, fiscal_year_id, period_month, run_id, slip_id, tds_amount)
    select s.org_id, s.employee_id, v_year.id, s.period_month, p_run_id, s.id, l.amount
    from public.payroll_slips s join public.payroll_slip_lines l on l.slip_id = s.id and l.code = 'TDS'
    where s.run_id = p_run_id and l.amount > 0
    on conflict (slip_id) do nothing;
  end if;

  insert into public.pf_ledger (org_id, employee_id, period_month, entry_type, employee_amount, employer_amount,
                                run_id, slip_id, created_by)
  select s.org_id, s.employee_id, s.period_month, 'contribution', coalesce(l.amount, 0), s.employer_pf, p_run_id, s.id,
         auth.uid()
  from public.payroll_slips s
  left join public.payroll_slip_lines l on l.slip_id = s.id and l.code = 'PF_EE'
  where s.run_id = p_run_id and (coalesce(l.amount, 0) > 0 or s.employer_pf > 0)
  on conflict (employee_id, period_month, entry_type) do nothing;

  select * into v_gratuity from public.gratuity_settings where org_id = v_run.org_id;
  if v_gratuity.provision_enabled
     and exists (select 1 from public.payroll_settings where org_id = v_run.org_id and gratuity_enabled) then
    insert into public.gratuity_provisions (org_id, employee_id, period_month, run_id, basic, days_per_year, amount)
    select s.org_id, s.employee_id, s.period_month, p_run_id, s.monthly_basic, g.days,
           private.round_money(s.monthly_basic / 30 * g.days / 12)
    from public.payroll_slips s
    join public.employees e on e.id = s.employee_id
    cross join lateral (select private.gratuity_days_per_year(v_gratuity,
                          private.gratuity_counted_years(v_gratuity, e.join_date, private.month_end(s.period_month))) as days) g
    where s.run_id = p_run_id and s.monthly_basic > 0 and g.days > 0
    on conflict (employee_id, period_month) do nothing;
  end if;
end;
$$;

-- Gratuity: counted years (a part year beyond the setting counts as a year).
create or replace function private.gratuity_counted_years(p_settings public.gratuity_settings, p_join date, p_until date)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_age   interval;
  v_years integer;
begin
  if p_until < p_join then
    return 0;
  end if;
  v_age := age(p_until + 1, p_join);
  v_years := extract(year from v_age)::int;
  if v_age - make_interval(years => v_years) > make_interval(months => p_settings.partial_year_months) then
    v_years := v_years + 1;
  end if;
  return v_years;
end;
$$;

-- Days of basic per year for the band reached (the highest band applies to all years).
create or replace function private.gratuity_days_per_year(p_settings public.gratuity_settings, p_years integer)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce((select (b ->> 'days')::numeric
                   from jsonb_array_elements(p_settings.bands) b
                   where (b ->> 'min_years')::int <= p_years
                   order by (b ->> 'min_years')::int desc limit 1), 0)
$$;

-- -----------------------------------------------------------------------------
-- 7. API: references, tax tables, calculator, settings
-- -----------------------------------------------------------------------------
create or replace function public.list_statutory_references()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.sort_order, r.key), '[]'::jsonb)
  from public.statutory_references r
$$;

create or replace function public.get_tax_tables()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(y) || jsonb_build_object(
           'thresholds', (select jsonb_object_agg(t.taxpayer_type, t.threshold) from public.tax_thresholds t
                          where t.fiscal_year_id = y.id),
           'slabs', (select jsonb_agg(jsonb_build_object('band_order', s.band_order, 'width', s.width, 'rate', s.rate)
                                      order by s.band_order)
                     from public.tax_slabs s where s.fiscal_year_id = y.id))
         order by y.from_date desc), '[]'::jsonb)
  from public.tax_fiscal_years y
$$;

-- Tax calculator: annual (or monthly x 12) income -> step-by-step annual tax.
create or replace function public.preview_tax(p jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_year   public.tax_fiscal_years;
  v_income numeric;
  v_detail jsonb;
begin
  if private.current_org_id() is null then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  select * into v_year from public.tax_fiscal_years
   where code = coalesce(nullif(p ->> 'fiscal_year', ''), (private.fiscal_year_for(current_date)).code);
  if v_year.id is null then
    select * into v_year from public.tax_fiscal_years order by from_date desc limit 1;
  end if;
  v_income := coalesce(nullif(p ->> 'annual_income', '')::numeric, nullif(p ->> 'monthly_income', '')::numeric * 12, 0);
  if v_income < 0 or v_income > 9999999999 then
    raise exception 'Enter a valid income' using errcode = '22023';
  end if;
  if coalesce(p ->> 'taxpayer_type', 'general') not in ('general', 'woman_senior', 'disabled', 'third_gender', 'freedom_fighter') then
    raise exception 'Unknown taxpayer type' using errcode = '22023';
  end if;
  v_detail := private.compute_annual_tax(v_year.id, coalesce(p ->> 'taxpayer_type', 'general'),
                                         coalesce((p ->> 'parent_of_disabled')::boolean, false),
                                         coalesce((p ->> 'is_new_taxpayer')::boolean, false), v_income,
                                         coalesce(nullif(p ->> 'investment', '')::numeric, 0), true);
  return v_detail || jsonb_build_object('monthly_tds', private.round_money((v_detail ->> 'annual_tax')::numeric / 12));
end;
$$;

create or replace function public.get_statutory_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
begin
  if not (private.has_permission('payroll_settings.manage') or private.has_permission('pf.manage')
          or private.has_permission('gratuity.manage') or private.has_permission('tax.view_profiles')) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'switches', (select jsonb_build_object('auto_tds', auto_tds, 'tds_apply_minimum_tax', tds_apply_minimum_tax,
                                           'tds_confirmed_at', tds_confirmed_at, 'pf_enabled', pf_enabled,
                                           'gratuity_enabled', gratuity_enabled)
                 from public.payroll_settings where org_id = v_org_id),
    'pf', (select to_jsonb(p) - array['org_id', 'created_by', 'updated_by'] from public.pf_settings p where org_id = v_org_id),
    'gratuity', (select to_jsonb(g) - array['org_id', 'created_by', 'updated_by']
                 from public.gratuity_settings g where org_id = v_org_id),
    'can_edit', private.has_permission('payroll_settings.manage'));
end;
$$;

-- Saves tax / PF / gratuity settings. Switching any of them on needs the
-- explicit confirmation that the values were checked against the law.
create or replace function public.save_statutory_settings(p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id  uuid := private.current_org_id();
  v_confirm boolean := coalesce((p ->> 'confirm')::boolean, false);
  v_band    jsonb;
begin
  perform private.require_permission('payroll_settings.manage');
  if (coalesce((p ->> 'auto_tds')::boolean, false) or coalesce((p ->> 'pf_enabled')::boolean, false)
      or coalesce((p ->> 'gratuity_enabled')::boolean, false)) and not v_confirm then
    raise exception 'Confirm that the tax, PF and gratuity values were checked against the current law before switching them on'
      using errcode = '23514';
  end if;

  if p ? 'pf' then
    if jsonb_typeof(p -> 'pf' -> 'vesting') is distinct from 'array' then
      raise exception 'PF vesting must be a list of bands' using errcode = '22023';
    end if;
    for v_band in select * from jsonb_array_elements(p -> 'pf' -> 'vesting') loop
      if (v_band ->> 'min_years')::numeric < 0 or (v_band ->> 'percent')::numeric not between 0 and 100 then
        raise exception 'Each vesting band needs years >= 0 and a percent from 0 to 100' using errcode = '22023';
      end if;
    end loop;
    update public.pf_settings
       set employee_rate = (p -> 'pf' ->> 'employee_rate')::numeric,
           employer_rate = (p -> 'pf' ->> 'employer_rate')::numeric,
           basis = p -> 'pf' ->> 'basis',
           min_service_months = (p -> 'pf' ->> 'min_service_months')::smallint,
           interest_rate = (p -> 'pf' ->> 'interest_rate')::numeric,
           vesting = p -> 'pf' -> 'vesting',
           is_recognised = coalesce((p -> 'pf' ->> 'is_recognised')::boolean, true),
           confirmed_at = case when v_confirm then now() else null end,
           confirmed_by = case when v_confirm then auth.uid() else null end
     where org_id = v_org_id;
  end if;

  if p ? 'gratuity' then
    if jsonb_typeof(p -> 'gratuity' -> 'bands') is distinct from 'array'
       or jsonb_array_length(p -> 'gratuity' -> 'bands') = 0 then
      raise exception 'Gratuity needs at least one band' using errcode = '22023';
    end if;
    for v_band in select * from jsonb_array_elements(p -> 'gratuity' -> 'bands') loop
      if (v_band ->> 'min_years')::numeric < 0 or (v_band ->> 'days')::numeric not between 0 and 365 then
        raise exception 'Each gratuity band needs years >= 0 and days from 0 to 365' using errcode = '22023';
      end if;
    end loop;
    update public.gratuity_settings
       set basis = p -> 'gratuity' ->> 'basis',
           min_service_months = (p -> 'gratuity' ->> 'min_service_months')::smallint,
           partial_year_months = (p -> 'gratuity' ->> 'partial_year_months')::smallint,
           bands = p -> 'gratuity' -> 'bands',
           provision_enabled = coalesce((p -> 'gratuity' ->> 'provision_enabled')::boolean, false),
           confirmed_at = case when v_confirm then now() else null end,
           confirmed_by = case when v_confirm then auth.uid() else null end
     where org_id = v_org_id;
  end if;

  update public.payroll_settings
     set auto_tds = coalesce((p ->> 'auto_tds')::boolean, auto_tds),
         tds_apply_minimum_tax = coalesce((p ->> 'tds_apply_minimum_tax')::boolean, tds_apply_minimum_tax),
         pf_enabled = coalesce((p ->> 'pf_enabled')::boolean, pf_enabled),
         gratuity_enabled = coalesce((p ->> 'gratuity_enabled')::boolean, gratuity_enabled),
         tds_confirmed_at = case when v_confirm then now() else tds_confirmed_at end,
         tds_confirmed_by = case when v_confirm then auth.uid() else tds_confirmed_by end
   where org_id = v_org_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. API: tax profiles and TDS ledger
-- -----------------------------------------------------------------------------
create or replace function public.list_tax_profiles()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_year   public.tax_fiscal_years := private.fiscal_year_for(current_date);
begin
  perform private.require_permission('tax.view_profiles');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id, 'department_name', d.name,
      'profile_id', tp.id, 'tin', tp.tin, 'taxpayer_type', coalesce(tp.taxpayer_type, 'general'),
      'is_new_taxpayer', coalesce(tp.is_new_taxpayer, false), 'parent_of_disabled', coalesce(tp.parent_of_disabled, false),
      'declared_investment', coalesce(tp.declared_investment, 0), 'note', tp.note,
      'ytd_tds', (select coalesce(sum(l.tds_amount), 0) from public.tds_ledger l
                  where l.employee_id = e.id and l.fiscal_year_id = v_year.id))
      order by e.full_name)
    from public.employees e
    left join public.departments d on d.id = e.department_id
    left join public.tax_profiles tp on tp.employee_id = e.id
    where e.org_id = v_org_id and e.status = 'active'), '[]'::jsonb);
end;
$$;

create or replace function public.save_tax_profile(p_employee_id uuid, p jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_tin    text := nullif(regexp_replace(coalesce(p ->> 'tin', ''), '\s', '', 'g'), '');
begin
  perform private.require_permission('tax.manage');
  if not exists (select 1 from public.employees where id = p_employee_id and org_id = v_org_id) then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if v_tin is not null and v_tin !~ '^\d{12}$' then
    raise exception 'A TIN has 12 digits' using errcode = '22023';
  end if;
  if coalesce(p ->> 'taxpayer_type', 'general') not in ('general', 'woman_senior', 'disabled', 'third_gender', 'freedom_fighter') then
    raise exception 'Unknown taxpayer type' using errcode = '22023';
  end if;
  if coalesce(nullif(p ->> 'declared_investment', '')::numeric, 0) not between 0 and 999999999 then
    raise exception 'Enter a valid investment amount' using errcode = '22023';
  end if;

  insert into public.tax_profiles (org_id, employee_id, tin, taxpayer_type, is_new_taxpayer, parent_of_disabled,
                                   declared_investment, note)
  values (v_org_id, p_employee_id, v_tin, coalesce(p ->> 'taxpayer_type', 'general'),
          coalesce((p ->> 'is_new_taxpayer')::boolean, false), coalesce((p ->> 'parent_of_disabled')::boolean, false),
          coalesce(nullif(p ->> 'declared_investment', '')::numeric, 0), nullif(left(btrim(p ->> 'note'), 300), ''))
  on conflict (employee_id) do update
     set tin = excluded.tin, taxpayer_type = excluded.taxpayer_type, is_new_taxpayer = excluded.is_new_taxpayer,
         parent_of_disabled = excluded.parent_of_disabled, declared_investment = excluded.declared_investment,
         note = excluded.note;
end;
$$;

create or replace function public.list_tds_ledger(p_fiscal_year text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('tax.view_profiles');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', l.id, 'employee_id', l.employee_id, 'full_name', e.full_name, 'card_id', e.card_id, 'tin', tp.tin,
      'fiscal_year', y.code, 'period_month', l.period_month, 'tds_amount', l.tds_amount,
      'challan_reference', l.challan_reference, 'challan_date', l.challan_date, 'status', l.status)
      order by l.period_month desc, e.full_name)
    from public.tds_ledger l
    join public.employees e on e.id = l.employee_id
    join public.tax_fiscal_years y on y.id = l.fiscal_year_id
    left join public.tax_profiles tp on tp.employee_id = l.employee_id
    where l.org_id = private.current_org_id() and (p_fiscal_year is null or y.code = p_fiscal_year)), '[]'::jsonb);
end;
$$;

create or replace function public.set_tds_challan(p_ledger_ids uuid[], p_reference text, p_challan_date date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  perform private.require_permission('tax.manage');
  if char_length(btrim(coalesce(p_reference, ''))) < 3 then
    raise exception 'Enter the challan reference' using errcode = '23502';
  end if;
  if p_challan_date is null or p_challan_date > current_date then
    raise exception 'Enter a challan date that is not in the future' using errcode = '22023';
  end if;
  update public.tds_ledger
     set challan_reference = left(btrim(p_reference), 60), challan_date = p_challan_date, status = 'deposited'
   where id = any (p_ledger_ids) and org_id = private.current_org_id();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Per-slip statutory amounts for the run page.
create or replace function public.get_run_statutory_summary(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_payroll_staff();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'slip_id', s.id, 'employee_id', s.employee_id, 'taxable_earnings', s.taxable_earnings,
      'tds', (select coalesce(sum(l.amount), 0) from public.payroll_slip_lines l where l.slip_id = s.id and l.code = 'TDS'),
      'tds_preview', s.tds_preview, 'annual_tax', (s.tax_detail ->> 'annual_tax')::numeric,
      'pf_employee', (select coalesce(sum(l.amount), 0) from public.payroll_slip_lines l where l.slip_id = s.id and l.code = 'PF_EE'),
      'pf_employer', s.employer_pf))
    from public.payroll_slips s
    where s.run_id = p_run_id and s.org_id = private.current_org_id()), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. API: provident fund
-- -----------------------------------------------------------------------------
create or replace function public.list_pf_members()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('pf.manage');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id, 'join_date', e.join_date,
      'member_status', m.status, 'enrolled_from', m.enrolled_from, 'left_on', m.left_on,
      'employee_total', b.employee_total, 'employer_total', b.employer_total, 'interest_total', b.interest_total)
      order by e.full_name)
    from public.employees e
    left join public.pf_members m on m.employee_id = e.id
    cross join lateral (select coalesce(sum(employee_amount), 0) as employee_total,
                               coalesce(sum(employer_amount), 0) as employer_total,
                               coalesce(sum(interest_amount), 0) as interest_total
                        from public.pf_ledger l where l.employee_id = e.id) b
    where e.org_id = private.current_org_id() and (e.status = 'active' or m.id is not null)), '[]'::jsonb);
end;
$$;

create or replace function public.set_pf_membership(p_employee_id uuid, p_enrolled_from date, p_status text default 'active')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_join   date;
begin
  perform private.require_permission('pf.manage');
  select join_date into v_join from public.employees where id = p_employee_id and org_id = v_org_id;
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_status not in ('active', 'left') then
    raise exception 'Unknown membership status' using errcode = '22023';
  end if;
  if p_enrolled_from is null or p_enrolled_from < v_join then
    raise exception 'Enrolment cannot be before the joining date' using errcode = '22023';
  end if;
  insert into public.pf_members (org_id, employee_id, enrolled_from, status, left_on)
  values (v_org_id, p_employee_id, p_enrolled_from, p_status, case when p_status = 'left' then current_date end)
  on conflict (employee_id) do update
     set enrolled_from = excluded.enrolled_from, status = excluded.status,
         left_on = case when excluded.status = 'left' then coalesce(public.pf_members.left_on, current_date) end;
end;
$$;

create or replace function public.get_pf_statement(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (private.has_permission('pf.manage') or p_employee_id = private.current_employee_id()) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'rows', coalesce((select jsonb_agg(to_jsonb(x) order by x.period_month, x.entry_type)
                      from (select l.period_month, l.entry_type, l.employee_amount, l.employer_amount, l.interest_amount,
                                   l.note,
                                   sum(l.employee_amount + l.employer_amount + l.interest_amount)
                                     over (order by l.period_month, l.entry_type) as balance
                            from public.pf_ledger l
                            where l.employee_id = p_employee_id and l.org_id = private.current_org_id()) x), '[]'::jsonb));
end;
$$;

-- What a member would take on leaving: own portion + vested employer portion + interest.
create or replace function public.preview_pf_withdrawal(p_employee_id uuid, p_leaving_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee public.employees;
  v_pf       public.pf_settings;
  v_own      numeric;
  v_employer numeric;
  v_interest numeric;
  v_years    integer;
  v_percent  numeric;
  v_vested   numeric;
begin
  perform private.require_permission('pf.manage');
  select * into v_employee from public.employees where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_leaving_date is null or p_leaving_date < v_employee.join_date then
    raise exception 'Enter a leaving date after the joining date' using errcode = '22023';
  end if;
  select * into v_pf from public.pf_settings where org_id = v_employee.org_id;
  select coalesce(sum(employee_amount), 0), coalesce(sum(employer_amount), 0), coalesce(sum(interest_amount), 0)
    into v_own, v_employer, v_interest
  from public.pf_ledger where employee_id = p_employee_id;

  v_years := private.service_months(v_employee.join_date, p_leaving_date) / 12;
  select coalesce((select (b ->> 'percent')::numeric from jsonb_array_elements(v_pf.vesting) b
                   where (b ->> 'min_years')::numeric <= v_years
                   order by (b ->> 'min_years')::numeric desc limit 1), 0) into v_percent;
  v_vested := private.round_money(v_employer * v_percent / 100);

  return jsonb_build_object(
    'join_date', v_employee.join_date, 'leaving_date', p_leaving_date, 'service_years', v_years,
    'employee_portion', v_own, 'employer_portion', v_employer, 'vested_percent', v_percent,
    'employer_vested', v_vested, 'interest', v_interest, 'total', v_own + v_vested + v_interest,
    'vesting', v_pf.vesting, 'references', jsonb_build_array('labour.provident_fund', 'policy.pf_rules'));
end;
$$;

-- Yearly interest on each member's balance at the given date (once per date).
create or replace function public.post_pf_interest(p_as_of date)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_id uuid := private.current_org_id();
  v_rate   numeric;
  v_count  integer;
begin
  perform private.require_permission('pf.manage');
  select interest_rate into v_rate from public.pf_settings where org_id = v_org_id;
  if coalesce(v_rate, 0) <= 0 then
    raise exception 'Set an interest rate in PF settings first' using errcode = '22023';
  end if;
  if p_as_of is null or p_as_of > current_date then
    raise exception 'Enter a date that is not in the future' using errcode = '22023';
  end if;
  insert into public.pf_ledger (org_id, employee_id, period_month, entry_type, interest_amount, note, created_by)
  select v_org_id, l.employee_id, private.month_start(p_as_of), 'interest',
         private.round_money(sum(l.employee_amount + l.employer_amount + l.interest_amount) * v_rate / 100),
         'Interest ' || v_rate || '% on balance at ' || p_as_of, auth.uid()
  from public.pf_ledger l
  where l.org_id = v_org_id and l.period_month <= p_as_of
  group by l.employee_id
  having sum(l.employee_amount + l.employer_amount + l.interest_amount) > 0
  on conflict (employee_id, period_month, entry_type) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. API: gratuity
-- -----------------------------------------------------------------------------
create or replace function private.gratuity_breakdown(p_employee public.employees, p_until date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings   public.gratuity_settings;
  v_months     integer;
  v_years      integer;
  v_days       numeric;
  v_basic      numeric;
  v_amount     numeric;
  v_reason     text;
  v_age        interval;
begin
  select * into v_settings from public.gratuity_settings where org_id = p_employee.org_id;
  v_months := private.service_months(p_employee.join_date, p_until);
  v_years  := private.gratuity_counted_years(v_settings, p_employee.join_date, p_until);
  v_days   := private.gratuity_days_per_year(v_settings, v_years);
  v_age    := age(p_until + 1, p_employee.join_date);

  if v_settings.basis = 'average_last_3_basic' then
    select avg(monthly_basic) into v_basic
    from (select s.monthly_basic from public.payroll_slips s
          join public.payroll_runs r on r.id = s.run_id and r.status in ('approved', 'paid', 'locked')
          where s.employee_id = p_employee.id and s.period_month <= p_until
          order by s.period_month desc limit 3) last3;
  end if;
  if v_basic is null then
    v_basic := coalesce((private.compensation_on(p_employee.id, least(p_until, current_date))).basic, 0);
  end if;
  v_basic := private.round_money(v_basic);

  if v_months < v_settings.min_service_months then
    v_amount := 0;
    v_reason := 'Service is shorter than the minimum of ' || v_settings.min_service_months || ' months';
  else
    v_amount := private.round_money(v_basic / 30 * v_days * v_years);
  end if;

  return jsonb_build_object(
    'join_date', p_employee.join_date, 'until', p_until,
    'service', jsonb_build_object('years', extract(year from v_age)::int, 'months', extract(month from v_age)::int,
                                  'days', extract(day from v_age)::int, 'total_months', v_months),
    'counted_years', v_years, 'partial_year_months', v_settings.partial_year_months,
    'days_per_year', v_days, 'bands', v_settings.bands, 'basis', v_settings.basis, 'basic', v_basic,
    'daily_basic', private.round_money(v_basic / 30), 'min_service_months', v_settings.min_service_months,
    'amount', v_amount, 'not_eligible_reason', v_reason,
    'references', jsonb_build_array('labour.gratuity', 'policy.gratuity_rules', 'policy.month_30_days'));
end;
$$;

create or replace function public.preview_gratuity(p_employee_id uuid, p_leaving_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_employee public.employees;
begin
  perform private.require_permission('gratuity.manage');
  select * into v_employee from public.employees where id = p_employee_id and org_id = private.current_org_id();
  if not found then
    raise exception 'Employee not found' using errcode = 'P0002';
  end if;
  if p_leaving_date is null or p_leaving_date < v_employee.join_date then
    raise exception 'Enter a leaving date after the joining date' using errcode = '22023';
  end if;
  return private.gratuity_breakdown(v_employee, p_leaving_date);
end;
$$;

-- Liability of every active employee if they left today, plus provisions posted.
create or replace function public.list_gratuity_liability()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.require_permission('gratuity.manage');
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'full_name', e.full_name, 'card_id', e.card_id, 'join_date', e.join_date,
      'counted_years', (b ->> 'counted_years')::int, 'days_per_year', (b ->> 'days_per_year')::numeric,
      'basic', (b ->> 'basic')::numeric, 'liability', (b ->> 'amount')::numeric,
      'provisioned', (select coalesce(sum(gp.amount), 0) from public.gratuity_provisions gp where gp.employee_id = e.id))
      order by e.full_name)
    from public.employees e
    cross join lateral private.gratuity_breakdown(e, current_date) b
    where e.org_id = private.current_org_id() and e.status = 'active'), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. Privileges
-- -----------------------------------------------------------------------------
alter table public.statutory_references enable row level security;
alter table public.tax_fiscal_years     enable row level security;
alter table public.tax_thresholds       enable row level security;
alter table public.tax_slabs            enable row level security;
alter table public.tax_profiles         enable row level security;
alter table public.tds_ledger           enable row level security;
alter table public.pf_settings          enable row level security;
alter table public.pf_members           enable row level security;
alter table public.pf_ledger            enable row level security;
alter table public.gratuity_settings    enable row level security;
alter table public.gratuity_provisions  enable row level security;
-- Everything goes through the functions above.
revoke all on table public.statutory_references, public.tax_fiscal_years, public.tax_thresholds, public.tax_slabs,
                    public.tax_profiles, public.tds_ledger, public.pf_settings, public.pf_members, public.pf_ledger,
                    public.gratuity_settings, public.gratuity_provisions
from anon, authenticated;

revoke all on function
  public.list_statutory_references(), public.get_tax_tables(), public.preview_tax(jsonb),
  public.get_statutory_settings(), public.save_statutory_settings(jsonb), public.list_tax_profiles(),
  public.save_tax_profile(uuid, jsonb), public.list_tds_ledger(text), public.set_tds_challan(uuid[], text, date),
  public.get_run_statutory_summary(uuid), public.list_pf_members(), public.set_pf_membership(uuid, date, text),
  public.get_pf_statement(uuid), public.preview_pf_withdrawal(uuid, date), public.post_pf_interest(date),
  public.preview_gratuity(uuid, date), public.list_gratuity_liability(), public.lock_payroll_run(uuid)
from public, anon;
grant execute on function
  public.list_statutory_references(), public.get_tax_tables(), public.preview_tax(jsonb),
  public.get_statutory_settings(), public.save_statutory_settings(jsonb), public.list_tax_profiles(),
  public.save_tax_profile(uuid, jsonb), public.list_tds_ledger(text), public.set_tds_challan(uuid[], text, date),
  public.get_run_statutory_summary(uuid), public.list_pf_members(), public.set_pf_membership(uuid, date, text),
  public.get_pf_statement(uuid), public.preview_pf_withdrawal(uuid, date), public.post_pf_interest(date),
  public.preview_gratuity(uuid, date), public.list_gratuity_liability(), public.lock_payroll_run(uuid)
to authenticated;

revoke all on function
  private.seed_statutory_defaults(uuid), private.seed_org_defaults(uuid), private.fiscal_year_for(date),
  private.compute_annual_tax(uuid, text, boolean, boolean, numeric, numeric, boolean),
  private.finalize_slip_totals(uuid), private.apply_statutory_lines(uuid), private.calculate_slip(uuid, uuid),
  private.calculate_slip_core(uuid, uuid), private.payroll_inputs_fingerprint(uuid, date),
  private.payroll_inputs_fingerprint_core(uuid, date), private.lock_payroll_run_core(uuid),
  private.gratuity_counted_years(public.gratuity_settings, date, date),
  private.gratuity_days_per_year(public.gratuity_settings, integer),
  private.gratuity_breakdown(public.employees, date)
from public, anon, authenticated;
