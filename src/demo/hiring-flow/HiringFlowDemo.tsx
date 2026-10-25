// Hiring flow demo: the whole onboarding process (R1 → R7) as one clickable story.
// Every number comes from the real core calculations (see flow.ts); nothing is stored.
import type { ReactNode } from 'react'
import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, ArrowRight, Check, CheckCircle2, Circle, ExternalLink, Mail, RotateCcw, Star } from 'lucide-react'
import { GATE_LABEL, REASON_TEXT } from '@/onboarding-process/core/ats'
import { COMPONENT_LABEL } from '@/onboarding-process/core/composite'
import { BAND_LABEL, suggestionText } from '@/onboarding-process/core/workload'
import { DOCUMENT_LABEL, FEEDBACK_QUESTIONS, TASK_LABEL } from '@/onboarding-process/core/joining'
import type { DocumentKind, TaskKey } from '@/onboarding-process/core/joining'
import { budgetSentence } from '@/onboarding-process/core/organogram'
import { joinOffer, sendOffer, simCounts } from '@/onboarding-process/core/organogramSim'
import { demoChart } from '@/onboarding-process/demo/organogramDemo'
import { formatTaka } from '@/lib/payroll'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, cx } from '@/components/ui'
import { PageHeader, Table, td, th } from '@/components/kit'
import { Chart } from '@/pages/onboarding/OrganogramPage'
import {
  CANDIDATES, COMPANY, INTERVIEWERS, OBJECTIVE, OFFER, OFFER_STEPS, POST, STEPS, accountsOrganogram, defaultShortlist, last4, results, screen, workload,
} from './flow'

const REAL_PAGE: Record<(typeof STEPS)[number]['key'], { to: string; label: string }> = {
  workforce: { to: '/workforce', label: 'Workforce & Vacancies' },
  post: { to: '/job-posts', label: 'Job posts' },
  screening: { to: '/job-posts', label: 'Job post → Applicants' },
  tests: { to: '/job-posts', label: 'Job post → Tests' },
  interview: { to: '/my-interviews', label: 'My interviews / Results' },
  offer: { to: '/job-posts', label: 'Job post → Offers' },
  joining: { to: '/organogram', label: 'Organogram' },
}

const VACANCY_STEPS = [
  { label: 'Manager drafts the vacancy (replacement, 1 seat)', who: 'Accounts Manager' },
  { label: 'HR reviews and forwards', who: 'HR Manager' },
  { label: 'Admin approves', who: 'Admin' },
]

function Tile({ label, value, hint }: { label: string; value: ReactNode; hint?: string }) {
  return (
    <div className="rounded-xl bg-slate-50 px-3 py-2.5">
      <p className="text-xs text-slate-500">{label}</p>
      <p className="text-lg font-semibold tabular-nums text-slate-900">{value}</p>
      {hint && <p className="text-[11px] text-slate-500">{hint}</p>}
    </div>
  )
}

/** A vertical list of steps; the next one gets the button. */
function Timeline({ steps, done, onNext, nextLabel }: { steps: { label: string; who: string }[]; done: number; onNext: () => void; nextLabel?: string }) {
  return (
    <ol className="space-y-2">
      {steps.map((s, i) => (
        <li key={s.label} className="flex items-center gap-3 text-sm">
          {i < done ? <CheckCircle2 className="size-5 shrink-0 text-green-600" /> : <Circle className={cx('size-5 shrink-0', i === done ? 'text-primary-500' : 'text-slate-300')} />}
          <span className={cx(i < done ? 'text-slate-900' : 'text-slate-500')}>{s.label} <span className="text-xs text-slate-400">· {s.who}</span></span>
          {i === done && <Button className="ml-auto px-3 py-1.5 text-xs" onClick={onNext}>{nextLabel ?? 'Do it'}</Button>}
        </li>
      ))}
    </ol>
  )
}

const NID = '1995261234567'
const ACCOUNT = '1234567890123'

export function HiringFlowDemo() {
  const [step, setStep] = useState(0)
  const [vacancy, setVacancy] = useState(0)
  const [published, setPublished] = useState(false)
  const [shortlist, setShortlist] = useState<string[]>(defaultShortlist)
  const [testsSent, setTestsSent] = useState(false)
  const [interview, setInterview] = useState<Record<string, [number, number]>>({})
  const [offerStep, setOfferStep] = useState(0)
  const [joined, setJoined] = useState(false)
  const [tasks, setTasks] = useState<TaskKey[]>([])
  const [rating, setRating] = useState(0)
  const [closed, setClosed] = useState(false)

  const f = workload()
  const rows = useMemo(() => results(shortlist, interview), [shortlist, interview])
  const ranked = rows.filter((r) => r.passed)
  const selected = ranked[0]?.c ?? null
  const waitlisted = ranked[1]?.c ?? null
  const before = accountsOrganogram()
  // The organogram follows the story: offer in process from "sent", the joiner fills the recruited slot.
  const offerSent = offerStep >= 3
  const offered = selected ? sendOffer(before, 'f-sr').state : before
  const withName = { ...offered, offers: offered.offers.map((o) => ({ ...o, name: selected?.name ?? o.name })) }
  const orgNow = joined && selected ? joinOffer(withName, withName.offers[0].id).state : offerSent ? withName : before

  const ready: boolean[] = [vacancy === 3, published, shortlist.length > 0, testsSent && ranked.length > 0, !!selected, offerStep === OFFER_STEPS.length, closed]
  const reset = () => {
    setStep(0); setVacancy(0); setPublished(false); setShortlist(defaultShortlist()); setTestsSent(false); setInterview({})
    setOfferStep(0); setJoined(false); setTasks([]); setRating(0); setClosed(false)
  }
  const current = STEPS[step]

  return (
    <div className="space-y-4">
      <Alert tone="info">Demo of the whole hiring cycle at {COMPANY}: one Senior Executive for Accounts. Click the buttons in each step; scores and the
        organogram are calculated by the same rules as the real system. Nothing is saved.</Alert>

      <ol className="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
        {STEPS.map((s, i) => (
          <li key={s.key}>
            <button type="button" onClick={() => setStep(i)}
              className={cx('w-full rounded-xl border px-3 py-2 text-left text-xs transition',
                i === step ? 'border-primary-500 bg-primary-50' : ready[i] ? 'border-green-200 bg-green-50' : 'border-slate-200 bg-white hover:bg-slate-50')}>
              <span className="flex items-center gap-1 font-semibold text-slate-500">{ready[i] && <Check className="size-3.5 text-green-600" />}{s.step}</span>
              <span className="block font-medium text-slate-900">{s.title}</span>
            </button>
          </li>
        ))}
      </ol>

      <Card className="space-y-4">
        <div className="flex flex-wrap items-start gap-3">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-primary-600">{current.step} · {current.who}</p>
            <h2 className="text-lg font-semibold text-slate-900">{current.title}</h2>
          </div>
          <Link to={REAL_PAGE[current.key].to} className="ml-auto inline-flex items-center gap-1 text-sm text-primary-700 hover:underline">
            Real page: {REAL_PAGE[current.key].label}<ExternalLink className="size-3.5" /></Link>
        </div>

        {current.key === 'workforce' && (
          <div className="space-y-4">
            <p className="text-sm text-slate-600">Each month the Accounts manager enters the work (hours). The system compares it with what the team can do.</p>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              <Tile label="Work this month" value={`${f.demand_hours.toLocaleString()} h`} />
              <Tile label="Team capacity" value={`${f.capacity_hours.toLocaleString()} h`} hint={`${f.active} people × ${f.capacity_per_fte} h`} />
              <Tile label="Workload index" value={f.index} hint={BAND_LABEL[f.band]} />
              <Tile label="Sanctioned / active" value={`${f.sanctioned} / ${f.active}`} hint={`needs ${f.required_fte} people`} />
            </div>
            <Alert tone="success">Suggestion: {suggestionText(f)}. The empty sanctioned seat is filled first; no new position is needed.</Alert>
            <Timeline steps={VACANCY_STEPS} done={vacancy} onNext={() => setVacancy((v) => v + 1)} />
          </div>
        )}

        {current.key === 'post' && (
          <div className="space-y-4">
            {vacancy < 3 && <Alert>Approve the vacancy in step R1 first.</Alert>}
            <div className="grid gap-4 lg:grid-cols-2">
              <div className="rounded-2xl bg-gradient-to-br from-primary-600 to-primary-800 p-5 text-white">
                <p className="text-xs uppercase tracking-wide text-primary-100">{COMPANY} is hiring</p>
                <p className="mt-1 text-xl font-bold">{POST.title}</p>
                <p className="mt-1 text-sm">{formatTaka(POST.salary_min)} – {formatTaka(POST.salary_max)} · apply by {formatDate(POST.deadline)}</p>
                <p className="mt-3 text-xs font-semibold uppercase text-primary-100">Must have</p>
                <ul className="list-inside list-disc text-sm">{POST.must_have.map((m) => <li key={m}>{m}</li>)}</ul>
                <p className="mt-2 text-xs text-primary-100">Bachelor's degree · {POST.min_years}+ years · nice to have: {POST.nice_to_have.join(', ')}</p>
              </div>
              <div className="space-y-2 text-sm">
                <p className="font-medium text-slate-900">Result weights (total 100)</p>
                {(Object.keys(POST.weights) as (keyof typeof POST.weights)[]).map((k) => (
                  <div key={k} className="flex items-center gap-2"><span className="w-24 text-slate-600">{COMPONENT_LABEL[k]}</span>
                    <div className="h-2 flex-1 rounded-full bg-slate-100"><div className="h-2 rounded-full bg-primary-500" style={{ width: `${POST.weights[k]}%` }} /></div>
                    <span className="w-8 text-right tabular-nums">{POST.weights[k]}</span></div>
                ))}
                {!published ? <Button disabled={vacancy < 3} onClick={() => setPublished(true)}>Publish post &amp; share link</Button> : (
                  <p className="rounded-lg bg-green-50 px-3 py-2 text-green-800">Published: /careers/alpha/senior-executive-accounts — poster shared on Facebook / LinkedIn.</p>)}
              </div>
            </div>
            {published && (
              <Table minWidth={480} head={<tr><th className={th}>Applicant</th><th className={th}>Source</th><th className={th}>CV</th></tr>}>
                {CANDIDATES.map((c) => <tr key={c.id}><td className={td}>{c.name} <span className="text-xs text-slate-400">{c.email}</span></td>
                  <td className={td}>{c.source}</td><td className={td}>PDF uploaded</td></tr>)}
              </Table>
            )}
          </div>
        )}

        {current.key === 'screening' && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Each CV is read (AI mode, or basic mode that turns the PDF into text) and scored against the post: skills 40, experience 25,
              education 20 → out of 85. Missing a must-have (experience or education) fails the gate. Tick who goes to the test.</p>
            <Table minWidth={720} head={<tr><th className={th}>Shortlist</th><th className={th}>Applicant</th><th className={th}>Experience</th><th className={th}>Education</th>
              <th className={th}>Skills</th><th className={th}>ATS score</th><th className={th}>Gate</th></tr>}>
              {CANDIDATES.map((c) => {
                const a = screen(c)
                return (
                  <tr key={c.id}>
                    <td className={td}><input type="checkbox" aria-label={`Shortlist ${c.name}`} checked={shortlist.includes(c.id)}
                      onChange={(e) => setShortlist((s) => (e.target.checked ? [...s, c.id] : s.filter((x) => x !== c.id)))} /></td>
                    <td className={td}>{c.name}</td>
                    <td className={td}>{c.years == null ? 'not found' : `${c.years} yrs`}</td>
                    <td className={td}>{c.level ?? '—'}</td>
                    <td className={td}>{c.matched}/{POST.must_have.length} (+{c.nice} nice)</td>
                    <td className={`${td} font-semibold tabular-nums`}>{a.score}</td>
                    <td className={td}><Badge tone={a.gate === 'pass' ? 'green' : a.gate === 'fail' ? 'red' : 'orange'}>{GATE_LABEL[a.gate]}</Badge>
                      {a.reasons.length > 0 && <p className="mt-0.5 text-[11px] text-slate-500">{a.reasons.map((r) => REASON_TEXT[r]).join('; ')}</p>}</td>
                  </tr>
                )
              })}
            </Table>
          </div>
        )}

        {current.key === 'tests' && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Shortlisted applicants get a one-time test link ({OBJECTIVE.length} questions, {OBJECTIVE.length * 2} marks, pass {POST.pass_percent} %).
              Those who pass sit a written paper ({POST.written_total} marks) that HR marks by hand.</p>
            {!testsSent ? <Button disabled={shortlist.length === 0} onClick={() => setTestsSent(true)}><Mail className="size-4" />Send test links to {shortlist.length}</Button> : (
              <Table minWidth={560} head={<tr><th className={th}>Applicant</th><th className={th}>Online test</th><th className={th}>Result</th><th className={th}>Written</th></tr>}>
                {rows.map((r) => (
                  <tr key={r.c.id}>
                    <td className={td}>{r.c.name}</td>
                    <td className={`${td} tabular-nums`}>{r.c.correct}/{OBJECTIVE.length} right · {r.objective ?? '—'} %</td>
                    <td className={td}><Badge tone={r.passed ? 'green' : 'red'}>{r.passed ? 'Passed' : 'Below pass mark'}</Badge></td>
                    <td className={`${td} tabular-nums`}>{r.written == null ? '—' : `${r.c.written.join(' + ')} of ${POST.written_total} · ${r.written} %`}</td>
                  </tr>
                ))}
              </Table>
            )}
          </div>
        )}

        {current.key === 'interview' && (
          <div className="space-y-3">
            <p className="text-sm text-slate-600">Each interviewer scores 5 areas from 1 to 5 in their kit. Move the sliders (each interviewer's average) and watch the
              ranking change. Interview % = (average − 1) ÷ 4; result = weighted CV + tests + interview.</p>
            {ranked.length === 0 ? <Alert>Send the tests in step R4 first.</Alert> : ranked.map((r, i) => {
              const means = interview[r.c.id] ?? r.c.interview
              return (
                <div key={r.c.id} className={cx('rounded-xl border p-3', i === 0 ? 'border-green-300 bg-green-50' : 'border-slate-200')}>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="font-medium text-slate-900">{i + 1}. {r.c.name}</span>
                    {i === 0 && <Badge tone="green">Top</Badge>}
                    {r.figures.spread_flag && <Badge tone="orange">Interviewers disagree</Badge>}
                    <span className="ml-auto text-lg font-semibold tabular-nums">{r.figures.composite} %</span>
                  </div>
                  <div className="mt-2 grid gap-2 sm:grid-cols-2">
                    {INTERVIEWERS.map((who, k) => (
                      <label key={who} className="flex items-center gap-2 text-xs text-slate-600">
                        <span className="w-28 shrink-0">{who}</span>
                        <input type="range" min={1} max={5} step={0.1} value={means[k]} className="flex-1"
                          onChange={(e) => setInterview((x) => {
                            const m: [number, number] = [...means]
                            m[k] = Number(e.target.value)
                            return { ...x, [r.c.id]: m }
                          })} />
                        <span className="w-8 tabular-nums">{means[k].toFixed(1)}</span>
                      </label>
                    ))}
                  </div>
                  <p className="mt-1 text-[11px] text-slate-500">{r.figures.components.map((c) => `${COMPONENT_LABEL[c.key]} ${c.percent} % × ${c.weight}`).join(' · ')}</p>
                </div>
              )
            })}
          </div>
        )}

        {current.key === 'offer' && (
          <div className="space-y-4">
            {!selected ? <Alert>Finish the interviews in step R5 first.</Alert> : (
              <>
                <div className="grid gap-2 sm:grid-cols-3">
                  <Tile label="Selected" value={selected.name} hint="1 seat" />
                  <Tile label="Waitlist" value={waitlisted?.name ?? '—'} hint="if the offer is declined" />
                  <Tile label="Not selected" value={`${CANDIDATES.length - (waitlisted ? 2 : 1)}`} hint="polite email queued" />
                </div>
                <Alert tone="info">Budget check before the offer: {budgetSentence(simCounts(before))}. An offer is refused when the department's headcount budget is full.</Alert>
                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="space-y-1 rounded-xl bg-slate-50 p-3 text-sm">
                    <p className="font-medium text-slate-900">Offer for {selected.name}</p>
                    <p>Gross {formatTaka(OFFER.gross)} / month · joins {formatDate(OFFER.joining_date)}</p>
                    <p>Reply by {formatDate(OFFER.expires_on)} · probation {OFFER.probation_months} months</p>
                    {offerStep >= 5 && <div className="mt-2 border-t border-slate-200 pt-2 text-xs text-slate-600">
                      Pre-joining form: photo ✓ · NID {last4(NID)} · bank account {last4(ACCOUNT)} · nominee: mother. Stored encrypted; HR sees the last 4 digits only.</div>}
                  </div>
                  <Timeline steps={OFFER_STEPS.map((s) => ({ label: s.label, who: s.who }))} done={offerStep} onNext={() => setOfferStep((v) => v + 1)} />
                </div>
              </>
            )}
          </div>
        )}

        {current.key === 'joining' && (
          <div className="space-y-4">
            {offerStep < OFFER_STEPS.length || !selected ? <Alert>Verify the pre-joining form in step R6 first.</Alert> : !joined ? (
              <div className="flex flex-wrap items-center gap-3">
                <p className="text-sm text-slate-600">On the joining day HR converts {selected.name} into an employee: card ID, pay from the offer, salary account, NID and nominee
                  copy over; the vacancy closes and the organogram updates.</p>
                <Button onClick={() => setJoined(true)}>Convert to employee</Button>
              </div>
            ) : (
              <>
                <Alert tone="success">{selected.name} is now employee EMP0007, Senior Executive, Accounts, gross {formatTaka(OFFER.gross)}. Vacancy filled.</Alert>
                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="space-y-2">
                    <p className="font-medium text-slate-900">Joining checklist</p>
                    {(Object.keys(TASK_LABEL) as TaskKey[]).map((k) => (
                      <label key={k} className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={tasks.includes(k)} onChange={(e) => setTasks((t) => (e.target.checked ? [...t, k] : t.filter((x) => x !== k)))} />
                        {TASK_LABEL[k]}
                      </label>
                    ))}
                    <p className="pt-1 text-xs text-slate-500">Documents printed and signed: {(Object.keys(DOCUMENT_LABEL) as DocumentKind[]).map((d) => DOCUMENT_LABEL[d]).join(' · ')}</p>
                  </div>
                  <div className="space-y-2">
                    <p className="font-medium text-slate-900">Named feedback (link to {selected.name})</p>
                    <p className="text-sm text-slate-600">{FEEDBACK_QUESTIONS[0].label}</p>
                    <div className="flex gap-1">{[1, 2, 3, 4, 5].map((n) => (
                      <button key={n} type="button" aria-label={`${n} stars`} onClick={() => setRating(n)}>
                        <Star className={cx('size-6', n <= rating ? 'fill-amber-400 text-amber-400' : 'text-slate-300')} /></button>))}</div>
                    {!closed ? (
                      <Button variant="secondary" disabled={tasks.length < Object.keys(TASK_LABEL).length}
                        onClick={() => setClosed(true)}>Complete onboarding &amp; close hiring</Button>
                    ) : <Alert tone="success">Case completed. Hiring closed: CVs and the other {CANDIDATES.length - 1} applicants' personal data are deleted;
                      {' '}{selected.name}'s data lives on in the employee record.</Alert>}
                  </div>
                </div>
              </>
            )}
            <div className="space-y-2">
              <p className="font-medium text-slate-900">Accounts organogram {joined ? '(after joining)' : offerSent ? '(offer in process)' : '(now)'}</p>
              <p className="text-sm text-slate-600">{budgetSentence(simCounts(orgNow))}</p>
              <Chart chart={demoChart(orgNow)} onPosition={() => undefined} />
            </div>
          </div>
        )}

        <div className="flex items-center gap-2 border-t border-slate-100 pt-3">
          <Button variant="ghost" disabled={step === 0} onClick={() => setStep((s) => s - 1)}><ArrowLeft className="size-4" />Previous</Button>
          <Button variant="ghost" onClick={reset}><RotateCcw className="size-4" />Start over</Button>
          {step < STEPS.length - 1 && (
            <Button className="ml-auto" disabled={!ready[step]} onClick={() => setStep((s) => s + 1)}>Next: {STEPS[step + 1].title}<ArrowRight className="size-4" /></Button>)}
        </div>
      </Card>
    </div>
  )
}

export default function HiringFlowDemoPage() {
  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Hiring flow demo" description="The whole onboarding process, from workload to joining, with sample data." />
      <HiringFlowDemo />
    </div>
  )
}
