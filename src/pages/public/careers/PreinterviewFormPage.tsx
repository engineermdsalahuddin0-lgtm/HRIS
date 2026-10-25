// The pre-interview form (/f/:token), no login. The link comes in the interview email;
// answers can be changed until the interview starts.
import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import { CheckCircle2 } from 'lucide-react'
import type { PreinterviewForm } from '@/onboarding-process/core/types'
import { formApi } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, Input, PageLoader } from '@/components/ui'
import { Textarea } from '@/components/kit'

export function PreinterviewFormPage() {
  const { token = '' } = useParams()
  const [form, setForm] = useState<PreinterviewForm | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState(false)
  const [a, setA] = useState({ can_attend: '' as '' | 'yes' | 'no', current_employer: '', current_designation: '', notice_period_days: '',
    current_salary: '', expected_salary: '', questions: '' })
  const set = (k: keyof typeof a, v: string) => setA((x) => ({ ...x, [k]: v }))

  useEffect(() => {
    formApi.get(token).then((f) => {
      setForm(f)
      const x = f.answers
      if (x) setA({ can_attend: x.can_attend ? 'yes' : 'no', current_employer: x.current_employer ?? '', current_designation: x.current_designation ?? '',
        notice_period_days: x.notice_period_days?.toString() ?? '', current_salary: x.current_salary?.toString() ?? '',
        expected_salary: x.expected_salary?.toString() ?? '', questions: x.questions ?? '' })
    }).catch((e) => setError(errorMessage(e)))
  }, [token])

  const shell = (children: React.ReactNode) => (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white"><div className="mx-auto flex h-14 max-w-2xl items-center px-4 font-semibold">{form ? `${form.organization} · ${form.job_title}` : 'Interview form'}</div></header>
      <main className="mx-auto max-w-2xl px-4 py-6">{children}</main>
      <footer className="py-6 text-center text-xs text-slate-400">Powered by Olympus HRIS</footer>
    </div>
  )
  if (error && !form) return shell(<Alert>{error.includes('not valid') ? 'This form link is not valid. Please check the link in your email.' : error}</Alert>)
  if (!form) return shell(<PageLoader />)
  if (form.status === 'cancelled') return shell(<Alert>This interview was cancelled. {form.organization} will contact you.</Alert>)
  if (form.status === 'closed') return shell(<Alert tone="info">The interview has started, so this form is closed.</Alert>)

  const submit = async () => {
    setBusy(true)
    setError(null)
    try {
      await formApi.submit(token, {
        can_attend: a.can_attend === 'yes', current_employer: a.current_employer, current_designation: a.current_designation,
        notice_period_days: a.notice_period_days === '' ? null : Number(a.notice_period_days),
        current_salary: a.current_salary === '' ? null : Number(a.current_salary),
        expected_salary: a.expected_salary === '' ? null : Number(a.expected_salary), questions: a.questions,
      })
      setSaved(true)
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return shell(
    <Card className="space-y-4">
      <div>
        <h1 className="text-xl font-semibold">Hello {form.first_name}</h1>
        <p className="mt-1 text-sm text-slate-600">Your interview: <span className="font-medium">{form.interview_time}</span>, {form.interview_place}
          {form.online_link && <> — <a className="text-primary-700 underline" href={form.online_link} target="_blank" rel="noreferrer">meeting link</a></>}.</p>
        <p className="mt-1 text-sm text-slate-600">Please answer a few questions before the interview. You can change them until it starts.</p>
      </div>
      {saved && <Alert tone="success"><CheckCircle2 className="mr-1 inline size-4" />Thank you, your answers are saved.</Alert>}
      {error && <Alert>{error}</Alert>}
      <fieldset>
        <legend className="mb-1.5 text-sm font-medium text-slate-700">Can you attend at this time? *</legend>
        <div className="flex gap-4 text-sm">
          {(['yes', 'no'] as const).map((v) => (
            <label key={v} className="flex items-center gap-2"><input type="radio" name="attend" className="size-4 accent-primary-600" checked={a.can_attend === v} onChange={() => set('can_attend', v)} />
              {v === 'yes' ? 'Yes' : 'No, I need another time'}</label>
          ))}
        </div>
      </fieldset>
      <div className="grid gap-3 sm:grid-cols-2">
        <Input label="Current / last employer" value={a.current_employer} maxLength={120} onChange={(e) => set('current_employer', e.target.value)} />
        <Input label="Current / last designation" value={a.current_designation} maxLength={120} onChange={(e) => set('current_designation', e.target.value)} />
        <Input label="Notice period (days)" inputMode="numeric" value={a.notice_period_days} onChange={(e) => set('notice_period_days', e.target.value.replace(/\D/g, ''))} />
        <Input label="Expected salary (Tk / month)" inputMode="numeric" value={a.expected_salary} onChange={(e) => set('expected_salary', e.target.value.replace(/\D/g, ''))} />
        <Input label="Current salary (Tk / month, optional)" inputMode="numeric" value={a.current_salary} onChange={(e) => set('current_salary', e.target.value.replace(/\D/g, ''))} />
      </div>
      <Textarea label="Anything you want to ask us? (optional)" value={a.questions} maxLength={1000} onChange={(e) => set('questions', e.target.value)} />
      <Button className="w-full sm:w-auto" loading={busy} disabled={!a.can_attend} onClick={submit}>{saved || form.status === 'submitted' ? 'Update answers' : 'Submit'}</Button>
    </Card>,
  )
}
