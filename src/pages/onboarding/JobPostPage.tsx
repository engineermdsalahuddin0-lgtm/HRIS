import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Check, Copy, ExternalLink, Send, XCircle } from 'lucide-react'
import type { JobPost, PosterTheme, Weights } from '@/onboarding-process/core/types'
import {
  POSTER_THEMES, POST_STATUS_LABEL, WEIGHT_LABEL, addDays, careersPath, deadlineText, salaryError, salaryText,
  SLUG_PATTERN, weightsError, weightsTotal,
} from '@/onboarding-process/core/jobPost'
import { DEMO_JOB_POST } from '@/onboarding-process/demo/jobPostDemo'
import { useJobPost, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { Switch, Tabs, Textarea } from '@/components/kit'
import { Markdown } from '@/components/Markdown'
import { JobPoster } from './JobPoster'
import { ApplicantsPanel } from './ApplicantsPanel'
import { QuestionPapersPanel } from './QuestionPapersPanel'
import { TestsPanel } from './TestsPanel'
import { postStatusTone } from './JobPostsPage'

type Draft = Pick<JobPost, 'title' | 'description_md' | 'location' | 'show_salary' | 'deadline' | 'has_written_test' | 'public_slug'> & {
  salary_min: string; salary_max: string; theme: PosterTheme; weights: Weights
}

const toDraft = (post: JobPost): Draft => ({
  title: post.title, description_md: post.description_md, location: post.location, show_salary: post.show_salary,
  salary_min: post.salary_min == null ? '' : String(post.salary_min), salary_max: post.salary_max == null ? '' : String(post.salary_max),
  deadline: post.deadline, has_written_test: post.has_written_test, public_slug: post.public_slug,
  theme: post.poster?.theme ?? 'orange', weights: post.weights,
})

/** /preview/job-post (dev only, no login): the editor, text and poster with a sample post. */
export function JobPostDemoPage() {
  return <JobPostEditor post={DEMO_JOB_POST} demo />
}

export default function JobPostPage() {
  const { id } = useParams()
  const post = useJobPost(id)
  if (post.isPending) return <PageLoader />
  if (post.isError) return <Alert>{errorMessage(post.error)}</Alert>
  return <JobPostEditor key={`${post.data.id}-${post.data.status}`} post={post.data} />
}

/** Edit, preview (text / poster), publish and share one job post; applicants below. */
export function JobPostEditor({ post, demo = false }: { post: JobPost; demo?: boolean }) {
  const update = useRecruitAction<{ p_id: string; p: Record<string, unknown> }>('update_job_post')
  const publish = useRecruitAction<{ p_id: string }>('publish_job_post')
  const close = useRecruitAction<{ p_id: string; p_note: string | null }>('close_job_post')
  const [draft, setDraft] = useState<Draft>(() => toDraft(post))
  const [view, setView] = useState<'text' | 'poster'>('text')
  const [copied, setCopied] = useState(false)
  const set = <K extends keyof Draft>(key: K, value: Draft[K]) => setDraft((d) => ({ ...d, [key]: value }))

  // Managers (recruit.department) see the post but do not change it.
  const editable = (post.status === 'draft' || post.status === 'published') && (post.can?.manage ?? true)
  const salary = { show_salary: draft.show_salary, salary_min: draft.salary_min === '' ? null : Number(draft.salary_min),
    salary_max: draft.salary_max === '' ? null : Number(draft.salary_max) }
  const problems = [
    salaryError(salary), weightsError(draft.weights),
    draft.title.trim().length < 3 ? 'The title needs at least 3 characters' : null,
    !draft.description_md.trim() ? 'Write a description' : null,
    draft.deadline < post.today ? 'The deadline is in the past' : null,
    !SLUG_PATTERN.test(draft.public_slug) ? 'The link may use a-z, 0-9 and single dashes' : null,
  ].filter(Boolean) as string[]
  const dirty = JSON.stringify(draft) !== JSON.stringify(toDraft(post))
  const url = `${window.location.origin}${careersPath(post.org_code, post.status === 'draft' ? draft.public_slug : post.public_slug)}`
  const busy = update.isPending || publish.isPending || close.isPending
  const error = update.error ?? publish.error ?? close.error
  const preview = { ...post, ...salary, title: draft.title, description_md: draft.description_md, location: draft.location,
    deadline: draft.deadline, public_slug: draft.public_slug }

  const payload = () => ({
    title: draft.title, description_md: draft.description_md, location: draft.location ?? '', show_salary: draft.show_salary,
    salary_min: salary.salary_min, salary_max: salary.salary_max, deadline: draft.deadline, has_written_test: draft.has_written_test,
    weights: draft.weights, poster: { theme: draft.theme }, ...(post.status === 'draft' ? { public_slug: draft.public_slug } : {}),
  })
  const save = (then?: () => void) => update.mutate({ p_id: post.id, p: payload() }, { onSuccess: then })
  const doPublish = () => (dirty ? save(() => publish.mutate({ p_id: post.id })) : publish.mutate({ p_id: post.id }))
  const doClose = () => {
    const note = prompt(post.status === 'draft' ? 'Cancel this draft? Optional reason:' : 'Close this post? It stops taking applications. Optional reason:')
    if (note !== null) close.mutate({ p_id: post.id, p_note: note || null })
  }
  const copy = async () => {
    await navigator.clipboard.writeText(url)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          {!demo && <Link to="/job-posts" className="mb-1 inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" />Job posts</Link>}
          <h2 className="text-2xl font-semibold text-slate-900">{post.title}</h2>
          <p className="mt-1 flex flex-wrap items-center gap-2 text-sm text-slate-500">
            <Badge tone={postStatusTone(post.status)}>{POST_STATUS_LABEL[post.status]}</Badge>
            {post.department_name} · {post.seats} seat(s) · {post.status === 'published' ? deadlineText(post.deadline, post.today) : `deadline ${formatDate(post.deadline)}`}
          </p>
        </div>
        {editable && !demo && (
          <div className="flex flex-wrap gap-2">
            <Button variant="ghost" disabled={busy} onClick={doClose}><XCircle className="size-4" />{post.status === 'draft' ? 'Cancel draft' : 'Close post'}</Button>
            <Button variant="secondary" disabled={!dirty || problems.length > 0} loading={update.isPending && !publish.isPending} onClick={() => save()}>Save</Button>
            {post.status === 'draft' && (
              <Button disabled={problems.length > 0 || post.vacancy_status !== 'approved'} loading={publish.isPending} onClick={doPublish}>
                <Send className="size-4" />Publish
              </Button>
            )}
          </div>
        )}
      </div>

      {error && <Alert>{errorMessage(error)}</Alert>}
      {post.vacancy_status !== 'approved' && post.status === 'draft' && <Alert>The vacancy is {post.vacancy_status.replace('_', ' ')}; it must be approved to publish.</Alert>}
      {post.profile_current_version != null && post.profile_current_version > post.profile_version && (
        <Alert tone="info">The job profile changed after this post was created (version {post.profile_version} → {post.profile_current_version}). The post keeps its own text; edit it here if needed.</Alert>
      )}
      {(post.status === 'published' || post.status === 'closed') && (
        <Card className="flex flex-wrap items-center gap-3 p-4">
          <span className="text-sm font-medium text-slate-700">Apply link</span>
          <code className="min-w-0 flex-1 truncate rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-700">{url}</code>
          <Button variant="secondary" onClick={copy}>{copied ? <Check className="size-4" /> : <Copy className="size-4" />}{copied ? 'Copied' : 'Copy'}</Button>
          <a href={url} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-sm text-primary-700 hover:underline">
            Open <ExternalLink className="size-3.5" /></a>
        </Card>
      )}

      <div className="grid gap-6 lg:grid-cols-[1fr_1fr]">
        <Card className="space-y-4">
          <h3 className="font-semibold text-slate-900">Details</h3>
          <fieldset disabled={!editable || demo} className="space-y-4">
            <Input label="Title" value={draft.title} maxLength={120} onChange={(e) => set('title', e.target.value)} />
            <div className="grid gap-4 sm:grid-cols-2">
              <Input label="Location" value={draft.location ?? ''} maxLength={120} onChange={(e) => set('location', e.target.value)} />
              <Input label="Deadline" type="date" value={draft.deadline} min={post.today} max={addDays(post.today, 90)}
                onChange={(e) => set('deadline', e.target.value)} hint="Up to 90 days ahead" />
            </div>
            <div className="rounded-xl border border-slate-200 p-4">
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className="text-sm font-medium text-slate-800">Show salary</p>
                  <p className="text-xs text-slate-500">Off shows “Negotiable”. Now: <span className="font-medium text-slate-700">{salaryText(salary)}</span></p>
                </div>
                <Switch label="Show salary" checked={draft.show_salary} onChange={(v) => set('show_salary', v)} disabled={!editable || demo} />
              </div>
              {draft.show_salary && (
                <div className="mt-3 grid gap-3 sm:grid-cols-2">
                  <Input label="Minimum (Tk / month)" inputMode="numeric" value={draft.salary_min} onChange={(e) => set('salary_min', e.target.value)} />
                  <Input label="Maximum (Tk / month)" inputMode="numeric" value={draft.salary_max} onChange={(e) => set('salary_max', e.target.value)}
                    error={salaryError(salary) ?? undefined} />
                </div>
              )}
            </div>
            <Input label="Link" value={draft.public_slug} disabled={post.status !== 'draft' || demo} onChange={(e) => set('public_slug', e.target.value.toLowerCase())}
              hint={post.status === 'draft' ? `${careersPath(post.org_code, draft.public_slug)} · fixed once published` : 'Fixed after publishing'} />
            <Textarea label="Description" rows={14} value={draft.description_md} maxLength={10000}
              onChange={(e) => set('description_md', e.target.value)}
              hint="“## ” starts a heading, “- ” a bullet, **text** is bold. Filled from the job profile; edit freely." />
            <div className="rounded-xl border border-slate-200 p-4">
              <div className="flex items-center justify-between gap-3">
                <p className="text-sm font-medium text-slate-800">Selection weights</p>
                <span className={cx('text-xs font-medium', weightsTotal(draft.weights) === 100 ? 'text-green-700' : 'text-red-600')}>
                  Total {weightsTotal(draft.weights)} / 100</span>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-4">
                {(Object.keys(WEIGHT_LABEL) as (keyof Weights)[]).map((k) => (
                  <Input key={k} label={WEIGHT_LABEL[k]} inputMode="numeric" value={String(draft.weights[k])}
                    onChange={(e) => set('weights', { ...draft.weights, [k]: Number(e.target.value.replace(/\D/g, '') || 0) })} />
                ))}
              </div>
              <label className="mt-3 flex items-center gap-2 text-sm text-slate-700">
                <input type="checkbox" className="size-4 accent-primary-600" checked={draft.has_written_test}
                  onChange={(e) => set('has_written_test', e.target.checked)} />
                This post has a written test (on paper)
              </label>
              <p className="mt-1 text-xs text-slate-500">Used for the final score in a later step. Without a written test its weight is shared out over the others.</p>
            </div>
          </fieldset>
          {problems.length > 0 && editable && <Alert>{problems[0]}</Alert>}
        </Card>

        <div className="space-y-3">
          <Tabs value={view} onChange={setView} tabs={[{ key: 'text', label: 'Text' }, { key: 'poster', label: 'Poster' }]} />
          {view === 'text' ? (
            <Card className="space-y-4">
              <div>
                <p className="text-sm text-slate-500">{post.org_name}</p>
                <h3 className="text-xl font-semibold text-slate-900">{draft.title || '—'}</h3>
                <p className="mt-1 text-sm text-slate-600">
                  {post.department_name}{draft.location ? ` · ${draft.location}` : ''} · {salaryText(salary)} · Apply by {formatDate(draft.deadline)}
                </p>
              </div>
              <Markdown source={draft.description_md} />
            </Card>
          ) : (
            <Card className="space-y-3">
              <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Poster colour">
                {(Object.keys(POSTER_THEMES) as PosterTheme[]).map((t) => (
                  <button key={t} type="button" role="radio" aria-checked={draft.theme === t} disabled={!editable && !demo}
                    onClick={() => set('theme', t)}
                    className={cx('flex items-center gap-2 rounded-full px-3 py-1.5 text-xs font-medium ring-1',
                      draft.theme === t ? 'ring-2 ring-slate-900' : 'ring-slate-300')}>
                    <span className="size-3.5 rounded-full" style={{ background: POSTER_THEMES[t].background }} />{POSTER_THEMES[t].label}
                  </button>
                ))}
              </div>
              <JobPoster post={preview} theme={draft.theme} url={url} />
              {post.status === 'draft' && <p className="text-xs text-slate-500">The QR code works once the post is published.</p>}
            </Card>
          )}
        </div>
      </div>

      {!demo && post.status !== 'cancelled' && <PostWork post={post} />}
    </div>
  )
}

/** Below the post: applicants (once published) and the question papers. */
function PostWork({ post }: { post: JobPost }) {
  const live = post.status === 'published' || post.status === 'closed'
  const [tab, setTab] = useState<'applicants' | 'tests' | 'papers'>(live ? 'applicants' : 'papers')
  return (
    <section className="space-y-4">
      <Tabs value={tab} onChange={setTab} tabs={[
        ...(live ? [{ key: 'applicants' as const, label: 'Applicants' }, { key: 'tests' as const, label: 'Tests & interviews' }] : []),
        { key: 'papers' as const, label: 'Question papers' },
      ]} />
      {tab === 'applicants' && live ? <ApplicantsPanel post={post} />
        : tab === 'tests' && live ? <TestsPanel post={post} /> : <QuestionPapersPanel post={post} />}
    </section>
  )
}
