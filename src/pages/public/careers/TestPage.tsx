// The online objective test (/t/:token), no login. The server keeps the clock and the
// answer key; each answer is saved the moment it is chosen, so a reload loses nothing.
import { useCallback, useEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { AlertTriangle, CheckCircle2, ChevronLeft, ChevronRight, Clock } from 'lucide-react'
import type { TestState } from '@/onboarding-process/core/types'
import { clock } from '@/onboarding-process/core/assessment'
import { testApi } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, PageLoader, cx } from '@/components/ui'

function Shell({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex h-14 max-w-3xl items-center px-4 font-semibold">{title ?? 'Online test'}</div>
      </header>
      <main className="mx-auto max-w-3xl px-4 py-6">{children}</main>
      <footer className="py-6 text-center text-xs text-slate-400">Powered by Olympus HRIS</footer>
    </div>
  )
}

export function TestPage() {
  const { token = '' } = useParams()
  const [state, setState] = useState<TestState | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [answers, setAnswers] = useState<Record<string, number>>({})
  const [saving, setSaving] = useState<Record<string, 'saving' | 'error'>>({})
  const [index, setIndex] = useState(0)
  const [left, setLeft] = useState<number | null>(null)
  const endsAt = useRef<number | null>(null)
  const submitted = useRef(false)

  const load = useCallback((s: TestState) => {
    setState(s)
    setAnswers(s.answers ?? {})
    endsAt.current = s.seconds_left != null ? Date.now() + s.seconds_left * 1000 : null
    setLeft(s.seconds_left)
  }, [])

  useEffect(() => {
    testApi.get(token).then(load).catch((e) => setError(errorMessage(e)))
  }, [token, load])

  const submit = useCallback(async () => {
    if (submitted.current) return
    submitted.current = true
    setBusy(true)
    try {
      await testApi.submit(token)
      load(await testApi.get(token))
    } catch (e) {
      submitted.current = false
      setError(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }, [token, load])

  useEffect(() => {
    if (state?.status !== 'started') return
    const timer = setInterval(() => {
      const remaining = endsAt.current == null ? null : Math.max(0, Math.round((endsAt.current - Date.now()) / 1000))
      setLeft(remaining)
      if (remaining === 0) void submit()
    }, 1000)
    return () => clearInterval(timer)
  }, [state?.status, submit])

  const choose = async (position: number, choice: number) => {
    const key = String(position)
    setAnswers((a) => ({ ...a, [key]: choice }))
    setSaving((s) => ({ ...s, [key]: 'saving' }))
    try {
      await testApi.answer(token, position, choice)
      setSaving((s) => { const n = { ...s }; delete n[key]; return n })
    } catch {
      setSaving((s) => ({ ...s, [key]: 'error' }))
    }
  }

  if (error && !state) return <Shell><Alert>{error.includes('not valid') ? 'This test link is not valid. Please check the link in your email.' : error}</Alert></Shell>
  if (!state) return <Shell><PageLoader /></Shell>
  const title = `${state.organization} · ${state.job_title}`

  if (state.status === 'submitted') {
    return (
      <Shell title={title}>
        <Card className="text-center">
          <CheckCircle2 className="mx-auto size-12 text-green-600" />
          <h1 className="mt-3 text-xl font-semibold">Your test is submitted</h1>
          <p className="mt-2 text-sm text-slate-600">
            {state.auto_submitted ? 'The time ran out, so your saved answers were submitted. ' : ''}Thank you, {state.first_name}. {state.organization} will contact you about the next step.
          </p>
        </Card>
      </Shell>
    )
  }
  if (state.status === 'expired' || state.status === 'cancelled') {
    return <Shell title={title}><Alert>This test link has expired. Please contact {state.organization} for a new one.</Alert></Shell>
  }
  if (state.status === 'invited') {
    return (
      <Shell title={title}>
        <Card className="space-y-4">
          <h1 className="text-xl font-semibold">Hello {state.first_name}</h1>
          <p className="text-sm text-slate-600">This is the online test for <span className="font-medium">{state.job_title}</span> at {state.organization}.</p>
          <ul className="list-disc space-y-1 pl-5 text-sm text-slate-700">
            <li>{state.question_count} multiple-choice questions, {state.total_marks} marks.</li>
            <li>You have <span className="font-medium">{state.duration_minutes} minutes</span>. The clock starts when you press Start and does not stop.</li>
            <li>You can take the test only once. Each answer is saved as soon as you choose it.</li>
            <li>When the time is up, your saved answers are submitted automatically.</li>
            <li>Use a stable internet connection. If the page reloads, open the same link again — your answers are kept.</li>
          </ul>
          {error && <Alert>{error}</Alert>}
          <Button className="w-full sm:w-auto" loading={busy} onClick={async () => {
            setBusy(true)
            try { load(await testApi.start(token)) } catch (e) { setError(errorMessage(e)) } finally { setBusy(false) }
          }}>Start the test</Button>
        </Card>
      </Shell>
    )
  }

  const questions = state.questions ?? []
  const q = questions[Math.min(index, questions.length - 1)]
  const answered = questions.filter((x) => answers[String(x.position)] !== undefined).length
  const low = left != null && left <= 60

  return (
    <Shell title={title}>
      <div className="sticky top-0 z-10 -mx-4 mb-4 flex items-center gap-3 border-b border-slate-200 bg-slate-50/95 px-4 py-2 backdrop-blur">
        <span className={cx('inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-mono text-sm font-semibold', low ? 'bg-red-100 text-red-700' : 'bg-white text-slate-800 ring-1 ring-slate-200')}
          role="timer" aria-live={low ? 'assertive' : 'off'}><Clock className="size-4" />{left == null ? '—' : clock(left)}</span>
        <span className="text-sm text-slate-600">{answered} of {questions.length} answered</span>
        <Button className="ml-auto" loading={busy} onClick={() => {
          const missing = questions.length - answered
          if (confirm(missing > 0 ? `${missing} question(s) are not answered. Submit anyway?` : 'Submit your test now? You cannot change answers afterwards.')) void submit()
        }}>Submit</Button>
      </div>
      {error && <div className="mb-3"><Alert>{error}</Alert></div>}

      <nav className="mb-4 flex flex-wrap gap-1.5" aria-label="Questions">
        {questions.map((x, i) => (
          <button key={x.position} type="button" onClick={() => setIndex(i)} aria-current={i === index ? 'step' : undefined}
            aria-label={`Question ${i + 1}${answers[String(x.position)] !== undefined ? ', answered' : ''}`}
            className={cx('size-9 rounded-lg text-sm font-medium ring-1',
              i === index ? 'bg-primary-600 text-white ring-primary-600'
                : answers[String(x.position)] !== undefined ? 'bg-green-50 text-green-800 ring-green-300' : 'bg-white text-slate-600 ring-slate-300')}>
            {i + 1}
          </button>
        ))}
      </nav>

      {q && (
        <Card className="space-y-4">
          <p className="text-xs text-slate-500">Question {index + 1} of {questions.length} · {q.marks} mark{q.marks === 1 ? '' : 's'}</p>
          <h2 className="whitespace-pre-wrap text-base font-medium text-slate-900">{q.stem}</h2>
          <fieldset className="space-y-2">
            <legend className="sr-only">Choose one answer</legend>
            {q.options.map((option, i) => {
              const chosen = answers[String(q.position)] === i
              return (
                <label key={i} className={cx('flex cursor-pointer items-start gap-3 rounded-xl p-3 text-sm ring-1 transition',
                  chosen ? 'bg-primary-50 ring-2 ring-primary-500' : 'bg-white ring-slate-200 hover:ring-slate-300')}>
                  <input type="radio" name={`q-${q.position}`} className="mt-0.5 size-4 accent-primary-600" checked={chosen}
                    onChange={() => void choose(q.position, i)} />
                  <span><span className="mr-1 font-medium text-slate-500">{'ABCDEF'[i]}.</span>{option}</span>
                </label>
              )
            })}
          </fieldset>
          {saving[String(q.position)] === 'error' && (
            <p className="flex items-center gap-1 text-sm text-red-600"><AlertTriangle className="size-4" />Not saved — check your connection and choose again.</p>
          )}
          <div className="flex justify-between">
            <Button variant="secondary" disabled={index === 0} onClick={() => setIndex(index - 1)}><ChevronLeft className="size-4" />Previous</Button>
            <Button variant="secondary" disabled={index >= questions.length - 1} onClick={() => setIndex(index + 1)}>Next<ChevronRight className="size-4" /></Button>
          </div>
        </Card>
      )}
    </Shell>
  )
}
