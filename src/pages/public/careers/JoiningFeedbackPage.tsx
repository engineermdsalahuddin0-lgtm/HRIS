// Named joining feedback (/joining-feedback/:token): the link comes with the welcome email.
import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { CheckCircle2 } from 'lucide-react'
import type { FeedbackKey } from '@/onboarding-process/core/joining'
import { FEEDBACK_QUESTIONS } from '@/onboarding-process/core/joining'
import { feedbackApi } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, PageLoader, cx } from '@/components/ui'
import { Textarea } from '@/components/kit'

export function JoiningFeedbackPage() {
  const { token = '' } = useParams()
  const [info, setInfo] = useState<Awaited<ReturnType<typeof feedbackApi.get>> | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [ratings, setRatings] = useState<Partial<Record<FeedbackKey, number>>>({})
  const [comment, setComment] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  useEffect(() => { feedbackApi.get(token).then(setInfo).catch((e) => setError(errorMessage(e))) }, [token])

  const shell = (children: React.ReactNode) => (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white"><div className="mx-auto flex h-14 max-w-2xl items-center px-4 font-semibold">{info ? `${info.organization} · Welcome` : 'Joining feedback'}</div></header>
      <main className="mx-auto max-w-2xl px-4 py-6">{children}</main>
    </div>
  )
  if (error && !info) return shell(<Alert>{error.includes('not valid') ? 'This feedback link is not valid.' : error}</Alert>)
  if (!info) return shell(<PageLoader />)
  if (!info.open) return shell(<Alert tone="info">This feedback form is closed.</Alert>)
  if (done) return shell(<Card className="text-center"><CheckCircle2 className="mx-auto size-12 text-green-600" /><p className="mt-3 font-semibold">Thank you, {info.full_name}!</p></Card>)
  const ready = FEEDBACK_QUESTIONS.every((q) => ratings[q.key])

  return shell(
    <Card className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Welcome, {info.full_name}</h1>
        <p className="mt-1 text-sm text-slate-600">How did your recruitment and first day go? Your answers carry your name so HR can follow up.{info.submitted ? ' You can change your earlier answers.' : ''}</p>
      </div>
      {error && <Alert>{error}</Alert>}
      {FEEDBACK_QUESTIONS.map((q) => (
        <div key={q.key} role="radiogroup" aria-label={q.label}>
          <p className="text-sm font-medium text-slate-800">{q.label}</p>
          <div className="mt-1 grid grid-cols-5 gap-1.5">
            {[1, 2, 3, 4, 5].map((v) => (
              <button key={v} type="button" role="radio" aria-checked={ratings[q.key] === v} onClick={() => setRatings((r) => ({ ...r, [q.key]: v }))}
                className={cx('rounded-lg py-2 text-sm font-medium ring-1', ratings[q.key] === v ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-600 ring-slate-300')}>{v}</button>
            ))}
          </div>
        </div>
      ))}
      <Textarea label="Anything else? (optional)" value={comment} maxLength={2000} onChange={(e) => setComment(e.target.value)} />
      <Button loading={busy} disabled={!ready} onClick={async () => {
        setBusy(true)
        try { await feedbackApi.submit(token, { ratings, comment }); setDone(true) } catch (e) { setError(errorMessage(e)) } finally { setBusy(false) }
      }}>Send</Button>
    </Card>,
  )
}
