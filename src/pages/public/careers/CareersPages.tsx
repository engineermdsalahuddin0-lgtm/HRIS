// Public careers page of one company (/careers/:orgCode) and one job with the
// apply form (/careers/:orgCode/:slug). No login. The database checks every rule
// again (open post, consent, file type and size, duplicates, rate limit).
import type { ReactNode } from 'react'
import { useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Briefcase, CalendarClock, CheckCircle2, MapPin, Wallet } from 'lucide-react'
import type { PublicJobPost } from '@/onboarding-process/core/types'
import { CV_ACCEPT, EMPLOYMENT_LABEL, careersPath, cvError, deadlineText, salaryText } from '@/onboarding-process/core/jobPost'
import type { ApplicationForm } from '@/lib/recruit'
import { usePublicCareers, usePublicJobPost, useSubmitApplication } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Button, Card, Input, PageLoader } from '@/components/ui'
import { Textarea } from '@/components/kit'
import { Markdown } from '@/components/Markdown'

const localToday = () => new Date().toLocaleDateString('en-CA')

function CareersShell({ orgName, orgCode, children }: { orgName?: string; orgCode?: string; children: ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex h-16 max-w-4xl items-center gap-3 px-4">
          <span className="flex size-9 items-center justify-center rounded-xl bg-primary-600 font-bold text-white">
            {(orgName ?? 'C').slice(0, 1).toUpperCase()}</span>
          {orgCode ? <Link to={careersPath(orgCode)} className="font-semibold">{orgName ?? 'Careers'}</Link> : <span className="font-semibold">Careers</span>}
          <span className="ml-auto text-sm text-slate-500">Careers</span>
        </div>
      </header>
      <main className="mx-auto max-w-4xl px-4 py-8">{children}</main>
      <footer className="py-8 text-center text-xs text-slate-400">Powered by Olympus HRIS</footer>
    </div>
  )
}

function Facts({ post, today }: { post: PublicJobPost; today: string }) {
  const item = (icon: ReactNode, text: string) => <span className="inline-flex items-center gap-1.5">{icon}{text}</span>
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-slate-600">
      {item(<Briefcase className="size-4 text-slate-400" />, `${post.department_name} · ${EMPLOYMENT_LABEL[post.employment_type]}`)}
      {post.location && item(<MapPin className="size-4 text-slate-400" />, post.location)}
      {item(<Wallet className="size-4 text-slate-400" />, salaryText(post))}
      {item(<CalendarClock className="size-4 text-slate-400" />, post.is_open ? `${formatDate(post.deadline)} · ${deadlineText(post.deadline, today)}` : 'Closed')}
    </div>
  )
}

export function CareersPage() {
  const { orgCode } = useParams()
  const careers = usePublicCareers(orgCode)
  const today = localToday()
  if (careers.isPending) return <CareersShell><PageLoader /></CareersShell>
  if (careers.isError) return <CareersShell><Alert>This careers page was not found.</Alert></CareersShell>
  const { organization, posts } = careers.data
  return (
    <CareersShell orgName={organization.name} orgCode={organization.org_code}>
      <h1 className="text-2xl font-semibold">Work with {organization.name}</h1>
      <p className="mt-1 text-sm text-slate-500">{posts.length === 0 ? 'No open positions right now. Please check again later.' : `${posts.length} open position${posts.length === 1 ? '' : 's'}`}</p>
      <div className="mt-6 space-y-3">
        {posts.map((post) => (
          <Link key={post.slug} to={careersPath(organization.org_code, post.slug)}
            className="block rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-200 transition hover:ring-primary-300">
            <h2 className="text-lg font-semibold text-slate-900">{post.title}</h2>
            <div className="mt-2"><Facts post={post} today={today} /></div>
          </Link>
        ))}
      </div>
    </CareersShell>
  )
}

const EMPTY: ApplicationForm = { full_name: '', email: '', phone: '', cover_note: '', consent: false, website: '' }

export function JobApplyPage() {
  const { orgCode = '', slug = '' } = useParams()
  const post = usePublicJobPost(orgCode, slug)
  const submit = useSubmitApplication(orgCode, slug)
  const fileInput = useRef<HTMLInputElement>(null)
  const [form, setForm] = useState<ApplicationForm>(EMPTY)
  const [file, setFile] = useState<File | null>(null)
  const [fileProblem, setFileProblem] = useState<string | null>(null)
  const set = <K extends keyof ApplicationForm>(key: K, value: ApplicationForm[K]) => setForm((f) => ({ ...f, [key]: value }))
  const today = localToday()

  if (post.isPending) return <CareersShell><PageLoader /></CareersShell>
  if (post.isError) return <CareersShell><Alert>This job post was not found.</Alert></CareersShell>
  const p = post.data
  const org = p.organization

  if (submit.isSuccess) {
    return (
      <CareersShell orgName={org?.name} orgCode={org?.org_code}>
        <Card className="text-center">
          <CheckCircle2 className="mx-auto size-12 text-green-600" />
          <h1 className="mt-3 text-xl font-semibold">Application received</h1>
          <p className="mt-2 text-sm text-slate-600">Thank you, {form.full_name}. {org?.name} will contact you by email or phone if you are shortlisted.</p>
          <Link to={careersPath(orgCode)} className="mt-4 inline-block text-sm text-primary-700 hover:underline">See other positions</Link>
        </Card>
      </CareersShell>
    )
  }

  const ready = form.full_name.trim().length >= 2 && form.email.includes('@') && form.phone.trim() !== '' && form.consent && !!file && !fileProblem

  return (
    <CareersShell orgName={org?.name} orgCode={org?.org_code}>
      <Link to={careersPath(orgCode)} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" />All positions</Link>
      <h1 className="mt-2 text-2xl font-semibold">{p.title}</h1>
      <div className="mt-2"><Facts post={p} today={today} /></div>
      <div className="mt-6 grid gap-6 lg:grid-cols-[1.3fr_1fr]">
        <Card><Markdown source={p.description_md ?? ''} /></Card>
        <Card className="h-fit">
          {!p.is_open ? (
            <Alert tone="info">This position is no longer taking applications.</Alert>
          ) : (
            <form className="space-y-4" noValidate onSubmit={(e) => {
              e.preventDefault()
              if (ready && file) submit.mutate({ form, file })
            }}>
              <h2 className="text-lg font-semibold">Apply now</h2>
              {submit.isError && <Alert>{errorMessage(submit.error)}</Alert>}
              <Input label="Full name" name="full_name" autoComplete="name" required value={form.full_name} maxLength={120}
                onChange={(e) => set('full_name', e.target.value)} />
              <Input label="Email" name="email" type="email" autoComplete="email" required value={form.email} maxLength={254}
                onChange={(e) => set('email', e.target.value)} />
              <Input label="Mobile number" name="phone" type="tel" autoComplete="tel" required placeholder="01XXXXXXXXX" value={form.phone}
                onChange={(e) => set('phone', e.target.value)} />
              <div>
                <span className="mb-1.5 block text-sm font-medium text-slate-700">CV (PDF or DOCX, up to 5 MB)</span>
                <input ref={fileInput} type="file" accept={CV_ACCEPT} className="hidden" onChange={(e) => {
                  const picked = e.target.files?.[0] ?? null
                  setFile(picked)
                  setFileProblem(picked ? cvError(picked) : null)
                }} />
                <Button type="button" variant="secondary" className="w-full" onClick={() => fileInput.current?.click()}>
                  {file ? file.name : 'Choose file'}
                </Button>
                {fileProblem && <p className="mt-1 text-xs text-red-600">{fileProblem}</p>}
              </div>
              <Textarea label="Anything you want to add? (optional)" name="cover_note" value={form.cover_note} maxLength={1000}
                onChange={(e) => set('cover_note', e.target.value)} />
              {/* Left empty by people; bots that fill every field are refused. */}
              <div className="hidden" aria-hidden="true">
                <label>Website <input tabIndex={-1} autoComplete="off" value={form.website} onChange={(e) => set('website', e.target.value)} /></label>
              </div>
              <label className="flex items-start gap-2 text-sm text-slate-700">
                <input type="checkbox" className="mt-0.5 size-4 accent-primary-600" checked={form.consent} onChange={(e) => set('consent', e.target.checked)} />
                <span>I agree that {org?.name ?? 'the company'} may use my details and CV for this recruitment only. They are deleted when the
                  position is filled, unless I join.</span>
              </label>
              <Button type="submit" className="w-full" disabled={!ready} loading={submit.isPending}>Submit application</Button>
            </form>
          )}
        </Card>
      </div>
    </CareersShell>
  )
}
