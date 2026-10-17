import { Link } from 'react-router-dom'
import type { LucideIcon } from 'lucide-react'
import {
  ArrowRight, BadgeCheck, Banknote, Building2, CalendarClock, CalendarDays, Check, ChevronDown, Clock, Fingerprint,
  IdCard, KeyRound, Landmark, Lock, MapPin, QrCode, ScrollText, ShieldCheck, Timer, UserPlus, Users, Wallet,
} from 'lucide-react'
import type { PublicPlan } from '@/lib/platform'
import { usePublicPlans } from '@/lib/platform'
import { cx } from '@/components/ui'
import { PublicShell } from './PublicShell'

/** Shown if the plan catalogue cannot be loaded; mirrors the seeded plans. */
const FALLBACK_PLANS: PublicPlan[] = [
  { code: 'TRIAL', name: 'Free trial', tagline: 'Try everything with your own team', price_per_employee: 0, max_employees: 25, trial_days: 30,
    features: ['Up to 25 employees', 'Employees, attendance and leave', 'Web, GPS and QR check-in', 'Email support'] },
  { code: 'BASIC', name: 'Basic', tagline: 'Core HR for growing companies', price_per_employee: null, max_employees: 100, trial_days: null,
    features: ['Up to 100 employees', 'Everything in the trial', 'Shifts, rosters and overtime', 'Roles and field-level access'] },
  { code: 'PRO', name: 'Professional', tagline: 'HR, attendance and payroll in one place', price_per_employee: null, max_employees: 1000, trial_days: null,
    features: ['Up to 1,000 employees', 'Everything in Basic', 'Salary structure and payroll', 'Audit log and approvals'] },
  { code: 'ENTERPRISE', name: 'Enterprise', tagline: 'For groups and large factories', price_per_employee: null, max_employees: null, trial_days: null,
    features: ['Unlimited employees', 'Everything in Professional', 'Multiple branches and factories', 'Priority support and onboarding'] },
]

const MODULES: { icon: LucideIcon; title: string; text: string }[] = [
  { icon: Users, title: 'Employee records', text: 'Profiles, documents, nominees, history and reporting lines — with a printable ID card for every employee.' },
  { icon: Building2, title: 'Organization structure', text: 'Branches, factories, offices, departments, designations and grades, kept consistent by the system.' },
  { icon: Fingerprint, title: 'Attendance', text: 'Web, GPS and rotating-QR check-in. Late, absent, half day and night shifts calculated automatically.' },
  { icon: CalendarClock, title: 'Shifts and rosters', text: 'Day and night shifts, rosters without overlaps, and shift swaps with colleague and manager approval.' },
  { icon: CalendarDays, title: 'Leave', text: 'Casual, sick, earned and maternity leave with balances, approvals through the reporting chain and carry-forward.' },
  { icon: Timer, title: 'Overtime', text: 'Weekday, weekend and holiday overtime for every grade, with caps, rounding and approval.' },
  { icon: Wallet, title: 'Salary and payroll', text: 'Salary templates, versioned pay, increments with arrears, bonuses, loans and encrypted bank details.' },
  { icon: ScrollText, title: 'Roles and audit', text: 'Role-based access down to individual fields, maker-checker approvals and a tamper-proof audit log.' },
]

const BANGLADESH_POINTS = [
  'Choose Bangladesh Labour Act 2006 or the EPZ Labour Act 2019 per company',
  'Salary month on a fixed 30-day basis, amounts in taka',
  'Friday weekly off by default, Bangladesh public holidays pre-loaded',
  'Mobile numbers in +880 format; email or mobile sign-in',
  'Your own late-deduction policy: N lates = X days, or taka per late',
  'Overtime for every grade, management and owners included',
]

const SECURITY_POINTS: { icon: LucideIcon; title: string; text: string }[] = [
  { icon: Lock, title: 'Your data stays yours', text: 'Every company is isolated in the database itself, not just on screen.' },
  { icon: KeyRound, title: 'Field-level access', text: 'Decide which roles see salary, NID or contact details — down to each field.' },
  { icon: ShieldCheck, title: 'Encrypted bank details', text: 'Account and wallet numbers are encrypted at rest and shown masked.' },
  { icon: ScrollText, title: 'Full audit trail', text: 'Who changed what and when is recorded and can never be edited or deleted.' },
]

const STEPS: { icon: LucideIcon; title: string; text: string }[] = [
  { icon: UserPlus, title: 'Apply', text: 'Register your company and your admin account in one short form.' },
  { icon: BadgeCheck, title: 'Get approved', text: 'Our team reviews the application. You get access to a free trial as soon as it is accepted.' },
  { icon: Building2, title: 'Set up and invite', text: 'Add branches, departments and employees, then give your team their logins.' },
]

const FAQS = [
  { q: 'Who can use Olympus HRIS?', a: 'Any company in Bangladesh — offices, factories and groups with several branches. Employees can use it from a phone browser.' },
  { q: 'How does registration work?', a: 'Fill in the registration form with your company details and create your admin account. After you confirm your email and our team accepts the application, you can sign in and start setting up.' },
  { q: 'Is there a free trial?', a: 'Yes. Every new company starts on a free trial for up to 25 employees. Plans for larger teams are priced to fit your company — contact us.' },
  { q: 'Does it follow Bangladesh labour law?', a: 'Each company chooses the Labour Act 2006 or the EPZ Labour Act 2019. Leave, overtime and holiday defaults come from that choice and your HR team confirms the values.' },
  { q: 'Can employees check in from their phone?', a: 'Yes — from the phone browser using GPS or by scanning a QR code that changes every minute at the office. A mobile app is planned.' },
  { q: 'Is our salary data safe?', a: 'Salary tables are closed to everyone except roles you allow. Bank and wallet numbers are encrypted, and every view of an unmasked number is logged.' },
]

/** Illustrative product preview (drawn with markup, not a screenshot of real data). */
function ProductPreview() {
  const bars = [62, 74, 58, 81, 69, 88, 76]
  return (
    <div className="relative mx-auto w-full max-w-lg" aria-hidden>
      <div className="absolute -inset-6 rounded-[2rem] bg-gradient-to-br from-primary-200/60 via-primary-100/40 to-transparent blur-2xl" />
      <div className="relative rounded-2xl bg-white p-4 shadow-2xl ring-1 ring-slate-200 sm:p-5">
        <div className="flex items-center gap-2 border-b border-slate-100 pb-3">
          <span className="size-2.5 rounded-full bg-red-300" /><span className="size-2.5 rounded-full bg-amber-300" /><span className="size-2.5 rounded-full bg-green-300" />
          <span className="ml-3 text-xs font-medium text-slate-400">Today · Attendance</span>
        </div>
        <div className="mt-4 grid grid-cols-3 gap-3">
          {[['Present', 'bg-green-50 text-green-700'], ['Late', 'bg-amber-50 text-amber-700'], ['On leave', 'bg-blue-50 text-blue-700']].map(([label, tone]) => (
            <div key={label} className={cx('rounded-xl p-3', tone)}>
              <p className="text-[11px] font-medium opacity-80">{label}</p>
              <div className="mt-2 h-4 w-10 rounded bg-current opacity-30" />
            </div>
          ))}
        </div>
        <div className="mt-4 rounded-xl bg-slate-50 p-3">
          <p className="text-[11px] font-medium text-slate-500">Weekly attendance</p>
          <div className="mt-3 flex h-24 items-end gap-2">
            {bars.map((height, index) => (
              <div key={index} className="flex-1 rounded-t-md bg-primary-500/80" style={{ height: `${height}%` }} />
            ))}
          </div>
        </div>
        <div className="mt-4 space-y-2">
          {[['Check-in', MapPin, 'GPS · inside office area'], ['Check-in', QrCode, 'Office QR · rotating code'], ['Payslip', Banknote, 'Ready for approval']].map(([title, Icon, note], index) => {
            const RowIcon = Icon as LucideIcon
            return (
              <div key={index} className="flex items-center gap-3 rounded-xl border border-slate-100 p-2.5">
                <span className="flex size-8 items-center justify-center rounded-lg bg-primary-50 text-primary-600"><RowIcon className="size-4" /></span>
                <div className="flex-1">
                  <p className="text-xs font-medium text-slate-800">{title as string}</p>
                  <p className="text-[11px] text-slate-400">{note as string}</p>
                </div>
                <Check className="size-4 text-green-600" />
              </div>
            )
          })}
        </div>
      </div>
      <div className="absolute -bottom-5 -left-4 hidden rounded-2xl bg-white p-3 shadow-xl ring-1 ring-slate-200 sm:block">
        <div className="flex items-center gap-2">
          <IdCard className="size-5 text-primary-600" />
          <p className="text-xs font-medium text-slate-700">ID cards in one click</p>
        </div>
      </div>
    </div>
  )
}

function SectionHeading({ eyebrow, title, text }: { eyebrow: string; title: string; text?: string }) {
  return (
    <div className="mx-auto max-w-2xl text-center">
      <p className="text-sm font-semibold uppercase tracking-wider text-primary-600">{eyebrow}</p>
      <h2 className="mt-2 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">{title}</h2>
      {text && <p className="mt-4 text-base leading-relaxed text-slate-600">{text}</p>}
    </div>
  )
}

function PlanCard({ plan, highlighted }: { plan: PublicPlan; highlighted: boolean }) {
  const isTrial = plan.price_per_employee === 0
  return (
    <div className={cx('relative flex flex-col rounded-2xl p-6 ring-1',
      highlighted ? 'bg-slate-900 text-white shadow-2xl ring-slate-900' : 'bg-white text-slate-900 ring-slate-200')}>
      {highlighted && <span className="absolute -top-3 left-6 rounded-full bg-primary-600 px-3 py-1 text-xs font-semibold text-white">Most popular</span>}
      <h3 className="text-lg font-semibold">{plan.name}</h3>
      <p className={cx('mt-1 text-sm', highlighted ? 'text-slate-300' : 'text-slate-500')}>{plan.tagline}</p>
      <p className={cx('mt-6 whitespace-nowrap font-bold tracking-tight', plan.price_per_employee === null ? 'text-2xl' : 'text-3xl')}>
        {isTrial ? 'Free' : plan.price_per_employee === null ? 'Contact sales' : `৳${plan.price_per_employee}`}
      </p>
      <p className={cx('text-sm', highlighted ? 'text-slate-400' : 'text-slate-500')}>
        {isTrial ? `${plan.trial_days ?? 30} days, no card needed` : plan.price_per_employee === null ? 'Priced for your team size' : 'per employee / month'}
      </p>
      <ul className="mt-6 flex-1 space-y-3 text-sm">
        {plan.features.map((feature) => (
          <li key={feature} className="flex gap-2">
            <Check className={cx('mt-0.5 size-4 shrink-0', highlighted ? 'text-primary-400' : 'text-primary-600')} />
            <span>{feature}</span>
          </li>
        ))}
      </ul>
      <Link to={`/register?plan=${plan.code}`}
        className={cx('mt-8 rounded-xl px-4 py-2.5 text-center text-sm font-semibold transition',
          highlighted ? 'bg-primary-600 text-white hover:bg-primary-500' : 'bg-slate-100 text-slate-900 hover:bg-slate-200')}>
        {isTrial ? 'Start free trial' : 'Apply now'}
      </Link>
    </div>
  )
}

/** Public marketing page shown at "/" to visitors who are not signed in. */
export default function LandingPage() {
  const plans = usePublicPlans()
  const planList = plans.data?.length ? plans.data : FALLBACK_PLANS

  return (
    <PublicShell>
      {/* Hero */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 -z-10 bg-[radial-gradient(ellipse_at_top_left,var(--color-primary-100),transparent_55%)]" />
        <div className="mx-auto grid max-w-7xl items-center gap-14 px-4 pb-20 pt-14 sm:px-6 lg:grid-cols-2 lg:pt-20">
          <div>
            <span className="inline-flex items-center gap-2 rounded-full bg-primary-50 px-3 py-1 text-xs font-semibold text-primary-700 ring-1 ring-primary-100">
              <Landmark className="size-3.5" /> Built for Bangladesh · Labour Act and EPZ ready
            </span>
            <h1 className="mt-5 text-4xl font-bold leading-tight tracking-tight text-slate-900 sm:text-5xl lg:text-6xl">
              HR, attendance and payroll —{' '}
              <span className="bg-gradient-to-r from-primary-600 to-amber-500 bg-clip-text text-transparent">in one place.</span>
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-relaxed text-slate-600">
              Olympus HRIS runs your people operations end to end: employee records, phone check-in with GPS and QR,
              leave, overtime and salary — secure, audited and made for how companies work in Bangladesh.
            </p>
            <div className="mt-8 flex flex-wrap gap-3">
              <Link to="/register" className="inline-flex items-center gap-2 rounded-xl bg-primary-600 px-6 py-3 text-base font-semibold text-white shadow-lg shadow-primary-600/20 hover:bg-primary-700">
                Register your company <ArrowRight className="size-4" />
              </Link>
              <a href="#features" className="inline-flex items-center gap-2 rounded-xl bg-white px-6 py-3 text-base font-semibold text-slate-800 ring-1 ring-slate-300 hover:bg-slate-50">
                See features
              </a>
            </div>
            <ul className="mt-8 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate-500">
              {['30-day free trial', 'No card needed', 'Works on any phone browser'].map((item) => (
                <li key={item} className="flex items-center gap-1.5"><Check className="size-4 text-green-600" />{item}</li>
              ))}
            </ul>
          </div>
          <ProductPreview />
        </div>
      </section>

      {/* Modules */}
      <section id="features" className="scroll-mt-20 bg-slate-50 py-20">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <SectionHeading eyebrow="Everything in one system" title="One platform for your whole HR cycle"
            text="Stop juggling spreadsheets, attendance registers and separate payroll files. Every module shares the same employee data." />
          <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-4">
            {MODULES.map(({ icon: Icon, title, text }) => (
              <div key={title} className="group rounded-2xl bg-white p-6 ring-1 ring-slate-200 transition hover:-translate-y-0.5 hover:shadow-lg">
                <span className="flex size-11 items-center justify-center rounded-xl bg-primary-50 text-primary-600 transition group-hover:bg-primary-600 group-hover:text-white">
                  <Icon className="size-5" />
                </span>
                <h3 className="mt-5 font-semibold text-slate-900">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-slate-600">{text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Bangladesh */}
      <section id="bangladesh" className="scroll-mt-20 py-20">
        <div className="mx-auto grid max-w-7xl items-center gap-12 px-4 sm:px-6 lg:grid-cols-2">
          <div>
            <p className="text-sm font-semibold uppercase tracking-wider text-primary-600">Made for Bangladesh</p>
            <h2 className="mt-2 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">Local rules built in, not bolted on</h2>
            <p className="mt-4 text-base leading-relaxed text-slate-600">
              Olympus follows the way Bangladeshi companies actually run payroll and attendance, so your HR team spends less time on
              workarounds. Statutory values start from the law you choose and your team confirms them.
            </p>
            <ul className="mt-8 grid gap-3 sm:grid-cols-2">
              {BANGLADESH_POINTS.map((point) => (
                <li key={point} className="flex gap-3 rounded-xl bg-slate-50 p-3 text-sm text-slate-700">
                  <Check className="mt-0.5 size-4 shrink-0 text-primary-600" />{point}
                </li>
              ))}
            </ul>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {SECURITY_POINTS.map(({ icon: Icon, title, text }) => (
              <div key={title} className="rounded-2xl bg-slate-900 p-6 text-white">
                <Icon className="size-6 text-primary-400" />
                <h3 className="mt-4 font-semibold">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-slate-300">{text}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* How it works */}
      <section id="how-it-works" className="scroll-mt-20 bg-slate-50 py-20">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <SectionHeading eyebrow="How it works" title="From application to first payroll" />
          <ol className="mt-14 grid gap-6 md:grid-cols-3">
            {STEPS.map(({ icon: Icon, title, text }, index) => (
              <li key={title} className="relative rounded-2xl bg-white p-7 ring-1 ring-slate-200">
                <span className="absolute right-6 top-6 text-5xl font-bold text-slate-100">{index + 1}</span>
                <span className="flex size-12 items-center justify-center rounded-xl bg-primary-600 text-white"><Icon className="size-5" /></span>
                <h3 className="mt-5 text-lg font-semibold text-slate-900">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-slate-600">{text}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Pricing */}
      <section id="pricing" className="scroll-mt-20 py-20">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <SectionHeading eyebrow="Pricing" title="Start free, grow when you are ready"
            text="Every company starts with a free trial. Plans for larger teams are priced to your employee count — talk to us." />
          <div className="mt-14 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
            {planList.map((plan) => <PlanCard key={plan.code} plan={plan} highlighted={plan.code === 'PRO'} />)}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="scroll-mt-20 bg-slate-50 py-20">
        <div className="mx-auto max-w-3xl px-4 sm:px-6">
          <SectionHeading eyebrow="FAQ" title="Questions, answered" />
          <div className="mt-12 space-y-3">
            {FAQS.map(({ q, a }) => (
              <details key={q} className="group rounded-2xl bg-white p-5 ring-1 ring-slate-200 open:shadow-sm">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-medium text-slate-900">
                  {q}
                  <ChevronDown className="size-5 shrink-0 text-slate-400 transition group-open:rotate-180" />
                </summary>
                <p className="mt-3 text-sm leading-relaxed text-slate-600">{a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      {/* Call to action */}
      <section className="py-20">
        <div className="mx-auto max-w-7xl px-4 sm:px-6">
          <div className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-primary-600 to-amber-500 px-6 py-14 text-center text-white sm:px-12">
            <Clock className="absolute -right-6 -top-6 size-40 text-white/10" aria-hidden />
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">Ready to bring your HR into one place?</h2>
            <p className="mx-auto mt-4 max-w-xl text-white/90">Register your company today. Once approved, your free trial starts immediately.</p>
            <Link to="/register" className="mt-8 inline-flex items-center gap-2 rounded-xl bg-white px-6 py-3 font-semibold text-primary-700 shadow-lg hover:bg-primary-50">
              Register your company <ArrowRight className="size-4" />
            </Link>
          </div>
        </div>
      </section>
    </PublicShell>
  )
}
