// The interviewer kit: who the applicant is, how they did so far, what to ask, and the
// scoring form (1-5 in five categories, a recommendation, a comment). Others' scores show
// only after you have scored (HR always sees them).
import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, ExternalLink, Lightbulb } from 'lucide-react'
import type { InterviewerKit } from '@/onboarding-process/core/types'
import { isoToZoned } from '@/onboarding-process/core/assessment'
import type { Category, Recommendation } from '@/onboarding-process/core/interview'
import {
  CATEGORIES, CATEGORY_LABEL, RECOMMENDATION_LABEL, SCALE_LABEL, meanOf, suggestedQuestions,
} from '@/onboarding-process/core/interview'
import { EDUCATION_LABEL } from '@/onboarding-process/core/jobPost'
import { useInterviewerKit, useSubmitInterviewScore } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { formatTaka } from '@/lib/payroll'
import { Alert, Badge, Button, Card, PageLoader, cx } from '@/components/ui'
import { Select, Textarea } from '@/components/kit'

function ScoreForm({ kit }: { kit: InterviewerKit }) {
  const submit = useSubmitInterviewScore(kit.interview.id)
  const [scores, setScores] = useState<Partial<Record<Category, number>>>(kit.my_score?.scores ?? {})
  const [rec, setRec] = useState<Recommendation | ''>(kit.my_score?.recommendation ?? '')
  const [comment, setComment] = useState(kit.my_score?.comment ?? '')
  const mean = meanOf(scores)
  const early = new Date(kit.interview.starts_at).getTime() - Date.now() > 3600_000
  return (
    <Card className="space-y-4">
      <div className="flex items-center justify-between"><h3 className="font-semibold text-slate-900">Your scores</h3>
        {kit.my_score && <span className="text-xs text-slate-500">Saved {formatDateTime(kit.my_score.submitted_at)}</span>}</div>
      {early && <Alert tone="info">You can score from one hour before the interview.</Alert>}
      {submit.isError && <Alert>{errorMessage(submit.error)}</Alert>}
      {submit.isSuccess && <Alert tone="success">{submit.data.panel_complete ? 'Saved. The whole panel has scored.' : 'Saved. You can change it until HR decides.'}</Alert>}
      {CATEGORIES.map((c) => (
        <div key={c} role="radiogroup" aria-label={CATEGORY_LABEL[c].label}>
          <p className="text-sm font-medium text-slate-800">{CATEGORY_LABEL[c].label} <span className="font-normal text-slate-400">· {CATEGORY_LABEL[c].hint}</span></p>
          <div className="mt-1 grid grid-cols-5 gap-1.5">
            {[1, 2, 3, 4, 5].map((v) => (
              <button key={v} type="button" role="radio" aria-checked={scores[c] === v} disabled={early}
                onClick={() => setScores((s) => ({ ...s, [c]: v }))}
                className={cx('rounded-lg px-1 py-2 text-xs font-medium ring-1 transition disabled:opacity-50',
                  scores[c] === v ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-600 ring-slate-300 hover:ring-slate-400')}>
                {v}<span className="block text-[10px] font-normal">{SCALE_LABEL[v]}</span>
              </button>
            ))}
          </div>
        </div>
      ))}
      <Select label="Recommendation" value={rec} placeholder="Choose" disabled={early} onChange={(e) => setRec(e.target.value as Recommendation)}
        options={(Object.keys(RECOMMENDATION_LABEL) as Recommendation[]).map((r) => ({ value: r, label: RECOMMENDATION_LABEL[r] }))} />
      <Textarea label="Comment (why)" rows={3} value={comment} maxLength={2000} disabled={early} onChange={(e) => setComment(e.target.value)} />
      <div className="flex items-center justify-between">
        <span className="text-sm text-slate-600">{mean != null ? `Your mean: ${mean} / 5` : 'Score all five'}</span>
        <Button loading={submit.isPending} disabled={early || mean == null || !rec} onClick={() => submit.mutate({ scores, recommendation: rec, comment })}>
          {kit.my_score ? 'Update scores' : 'Submit scores'}</Button>
      </div>
    </Card>
  )
}

export default function InterviewKitPage() {
  const { id } = useParams()
  const kit = useInterviewerKit(id)
  if (kit.isPending) return <PageLoader />
  if (kit.isError) return <Alert>{errorMessage(kit.error)}</Alert>
  const k = kit.data
  const z = isoToZoned(k.interview.starts_at, k.timezone)
  const questions = suggestedQuestions({ job: k.job, screening: k.screening, objective: k.objective })
  const form = k.form?.answers
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <Link to="/my-interviews" className="mb-1 inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" />My interviews</Link>
        <h2 className="text-2xl font-semibold text-slate-900">{k.applicant.full_name}</h2>
        <p className="mt-1 text-sm text-slate-500">{k.job.title} · {k.job.department_name} · {formatDate(z.date)} {z.time} · {k.interview.mode === 'online'
          ? <a className="text-primary-700 hover:underline" href={k.interview.online_link ?? '#'} target="_blank" rel="noreferrer">Online <ExternalLink className="inline size-3" /></a> : k.interview.location}</p>
        <p className="mt-1 text-xs text-slate-500">Panel: {k.interview.panel.map((p) => `${p.full_name}${p.scored ? ' ✓' : ''}`).join(', ')}</p>
      </div>
      {k.interview.note && <Alert tone="info">{k.interview.note}</Alert>}

      <div className="grid gap-6 lg:grid-cols-[1.1fr_1fr]">
        <div className="space-y-4">
          <Card className="space-y-3">
            <h3 className="font-semibold text-slate-900">So far</h3>
            <dl className="grid gap-3 text-sm sm:grid-cols-3">
              <div><dt className="text-xs text-slate-500">CV score (ATS)</dt><dd className="text-lg font-semibold">{k.screening?.ats_score ?? '—'}</dd></div>
              <div><dt className="text-xs text-slate-500">Online test</dt><dd className="text-lg font-semibold">{k.objective ? `${k.objective.percent}%` : '—'}</dd></div>
              <div><dt className="text-xs text-slate-500">Written test</dt><dd className="text-lg font-semibold">{k.written ? `${k.written.percent}%` : '—'}</dd></div>
            </dl>
            {k.objective && <p className="text-xs text-slate-500">By section: {Object.entries(k.objective.sections).map(([s, v]) => `${s.replace('_', ' ')} ${v.percent ?? '—'}%`).join(' · ')}</p>}
            {k.screening && (
              <p className="text-sm text-slate-700">{k.screening.years != null ? `${k.screening.years} years of experience` : 'Experience unknown'} ·{' '}
                {k.screening.education_level ? EDUCATION_LABEL[k.screening.education_level as keyof typeof EDUCATION_LABEL] : 'education unknown'}
                {k.screening.matched_required?.length ? ` · has ${k.screening.matched_required.join(', ')}` : ''}</p>
            )}
            {k.screening?.summary && <p className="rounded-xl bg-slate-50 p-3 text-sm text-slate-700">{k.screening.summary}</p>}
          </Card>
          <Card className="space-y-2">
            <h3 className="font-semibold text-slate-900">Pre-interview form</h3>
            {!form ? <p className="text-sm text-slate-500">Not filled in yet.</p> : (
              <dl className="grid gap-2 text-sm sm:grid-cols-2">
                <div><dt className="text-xs text-slate-500">Can attend</dt><dd>{form.can_attend ? 'Yes' : 'No — check with HR'}</dd></div>
                <div><dt className="text-xs text-slate-500">Now at</dt><dd>{[form.current_designation, form.current_employer].filter(Boolean).join(', ') || '—'}</dd></div>
                <div><dt className="text-xs text-slate-500">Notice period</dt><dd>{form.notice_period_days != null ? `${form.notice_period_days} days` : '—'}</dd></div>
                <div><dt className="text-xs text-slate-500">Expected salary</dt><dd>{form.expected_salary != null ? formatTaka(form.expected_salary) : '—'}</dd></div>
                {form.questions && <div className="sm:col-span-2"><dt className="text-xs text-slate-500">Their questions</dt><dd>{form.questions}</dd></div>}
              </dl>
            )}
          </Card>
          <Card className="space-y-2">
            <h3 className="flex items-center gap-2 font-semibold text-slate-900"><Lightbulb className="size-4 text-amber-500" />Questions to ask</h3>
            <ol className="list-decimal space-y-1.5 pl-5 text-sm text-slate-700">
              {questions.map((q, i) => <li key={i}>{q.text} <span className="text-xs text-slate-400">({CATEGORY_LABEL[q.category].label})</span></li>)}
            </ol>
          </Card>
        </div>

        <div className="space-y-4">
          {k.access === 'panel' ? <ScoreForm kit={k} /> : <Alert tone="info">You are viewing as HR / manager. Only panel members score.</Alert>}
          <Card className="space-y-2">
            <h3 className="font-semibold text-slate-900">Panel scores</h3>
            {k.all_scores == null ? <p className="text-sm text-slate-500">Shown after you submit your own scores, so they do not influence you.</p>
              : k.all_scores.length === 0 ? <p className="text-sm text-slate-500">No scores yet.</p> : (
                <ul className="space-y-2 text-sm">{k.all_scores.map((s) => (
                  <li key={s.full_name} className="rounded-xl border border-slate-200 p-3">
                    <p className="flex items-center justify-between"><span className="font-medium text-slate-900">{s.full_name}</span>
                      <span>{s.mean} · <Badge tone={s.recommendation.endsWith('yes') ? 'green' : 'red'}>{RECOMMENDATION_LABEL[s.recommendation]}</Badge></span></p>
                    <p className="text-xs text-slate-500">{CATEGORIES.map((c) => `${CATEGORY_LABEL[c].label} ${s.scores[c]}`).join(' · ')}</p>
                    {s.comment && <p className="mt-1 text-xs text-slate-700">{s.comment}</p>}
                  </li>
                ))}</ul>
              )}
          </Card>
        </div>
      </div>
    </div>
  )
}
