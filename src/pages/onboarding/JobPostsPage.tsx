import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ExternalLink, FilePlus2, Pencil } from 'lucide-react'
import type { JobPostStatus, JobProfileRow, ReadyVacancy } from '@/onboarding-process/core/types'
import { POST_STATUS_LABEL, careersPath, deadlineText } from '@/onboarding-process/core/jobPost'
import { useJobPosts, useJobProfiles, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, PageLoader } from '@/components/ui'
import { PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { REASON_LABEL } from './dialogs/VacancyDialog'
import { JobProfileDialog } from './dialogs/JobProfileDialog'

type Tab = 'ready' | 'posts' | 'profiles'

export const postStatusTone = (status: JobPostStatus) =>
  status === 'published' ? 'green' : status === 'draft' ? 'orange' : status === 'cancelled' ? 'red' : 'slate'

const localToday = () => new Date().toLocaleDateString('en-CA')

/** Approved vacancies become job posts filled from the designation's job profile. */
export default function JobPostsPage() {
  const posts = useJobPosts()
  const profiles = useJobProfiles()
  const navigate = useNavigate()
  const create = useRecruitAction<{ p_vacancy_id: string }, string>('create_job_post_from_vacancy')
  const [tab, setTab] = useState<Tab>('ready')
  const [editing, setEditing] = useState<{ row: JobProfileRow; then?: ReadyVacancy } | null>(null)

  const createPost = (vacancy: ReadyVacancy) =>
    create.mutate({ p_vacancy_id: vacancy.vacancy_id }, { onSuccess: (id) => navigate(`/job-posts/${id}`) })

  const startPost = (vacancy: ReadyVacancy) => {
    if (vacancy.has_profile) return createPost(vacancy)
    const row = profiles.data?.find((r) => r.designation_id === vacancy.designation_id)
    if (row) setEditing({ row, then: vacancy })
  }

  if (posts.isPending || profiles.isPending) return <PageLoader />
  if (posts.isError) return <Alert>{errorMessage(posts.error)}</Alert>
  if (profiles.isError) return <Alert>{errorMessage(profiles.error)}</Alert>
  const data = posts.data
  const today = localToday()

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Job posts"
        description="Every approved vacancy becomes a post filled from the job profile. Published posts appear on your careers page."
        actions={<a href={careersPath(data.org_code)} target="_blank" rel="noreferrer"
          className="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-medium text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50">
          <ExternalLink className="size-4" />Careers page</a>} />
      {create.isError && <Alert>{errorMessage(create.error)}</Alert>}
      <Tabs value={tab} onChange={setTab} tabs={[
        { key: 'ready', label: 'Ready to post', count: data.ready.length },
        { key: 'posts', label: 'Posts', count: data.posts.length },
        { key: 'profiles', label: 'Job profiles', count: profiles.data.filter((r) => r.profile).length },
      ]} />

      {tab === 'ready' && (data.ready.length === 0 ? (
        <EmptyState title="No approved vacancy is waiting">
          Approve a vacancy on the <Link to="/vacancies" className="text-primary-700 underline">Vacancies</Link> page and it appears here.
        </EmptyState>
      ) : (
        <Table minWidth={680} head={(
          <tr><th className={th}>Position</th><th className={th}>Seats</th><th className={th}>Reason</th>
            <th className={th}>Approved</th><th className={th}>Job profile</th><th className={th} /></tr>
        )}>
          {data.ready.map((v) => (
            <tr key={v.vacancy_id}>
              <td className={td}><p className="font-medium text-slate-900">{v.designation_name}</p>
                <p className="text-xs text-slate-400">{v.department_name} · {v.grade_code}</p></td>
              <td className={`${td} tabular-nums`}>{v.seats}</td>
              <td className={td}>{REASON_LABEL[v.reason]}</td>
              <td className={td}>{formatDate(v.decided_at)}</td>
              <td className={td}>{v.has_profile ? <Badge tone="green">Ready</Badge> : <Badge tone="orange">Missing</Badge>}</td>
              <td className={`${td} text-right`}>
                <Button loading={create.isPending && create.variables?.p_vacancy_id === v.vacancy_id} onClick={() => startPost(v)}>
                  <FilePlus2 className="size-4" />{v.has_profile ? 'Create post' : 'Set profile & post'}
                </Button>
              </td>
            </tr>
          ))}
        </Table>
      ))}

      {tab === 'posts' && (data.posts.length === 0 ? (
        <EmptyState title="No job posts yet">Create one from the Ready to post tab.</EmptyState>
      ) : (
        <Table minWidth={760} head={(
          <tr><th className={th}>Post</th><th className={th}>Status</th><th className={th}>Deadline</th>
            <th className={th}>Applicants</th><th className={th}>Created</th></tr>
        )}>
          {data.posts.map((p) => (
            <tr key={p.id} className="cursor-pointer hover:bg-slate-50" onClick={() => navigate(`/job-posts/${p.id}`)}>
              <td className={td}>
                <Link to={`/job-posts/${p.id}`} className="font-medium text-slate-900 hover:text-primary-700" onClick={(e) => e.stopPropagation()}>{p.title}</Link>
                <p className="text-xs text-slate-400">{p.department_name} · {p.seats} seat(s)</p>
              </td>
              <td className={td}><Badge tone={postStatusTone(p.status)}>{POST_STATUS_LABEL[p.status]}</Badge></td>
              <td className={td}>{formatDate(p.deadline)}
                {p.status === 'published' && <p className="text-xs text-slate-400">{deadlineText(p.deadline, today)}</p>}</td>
              <td className={`${td} tabular-nums`}>{p.applicants}<span className="text-xs text-slate-400"> · {p.with_cv} with CV</span></td>
              <td className={td}>{formatDate(p.created_at)}</td>
            </tr>
          ))}
        </Table>
      ))}

      {tab === 'profiles' && (profiles.data.length === 0 ? (
        <EmptyState title="No designations yet">Add designations on the Organization page first.</EmptyState>
      ) : (
        <Table minWidth={640} head={(
          <tr><th className={th}>Designation</th><th className={th}>Profile</th><th className={th}>Last change</th><th className={th} /></tr>
        )}>
          {profiles.data.map((row) => (
            <tr key={row.designation_id}>
              <td className={td}><p className="font-medium text-slate-900">{row.designation_name}</p>
                <p className="text-xs text-slate-400">{row.department_name} · {row.grade_code}</p></td>
              <td className={td}>{row.profile ? <Badge tone="green">Version {row.profile.version}</Badge> : <Badge>Not set</Badge>}</td>
              <td className={td}>{row.profile ? formatDate(row.profile.updated_at) : '—'}</td>
              <td className={`${td} text-right`}>
                <Button variant="secondary" onClick={() => setEditing({ row })}><Pencil className="size-4" />{row.profile ? 'Edit' : 'Set up'}</Button>
              </td>
            </tr>
          ))}
        </Table>
      ))}

      {editing && (
        <JobProfileDialog key={editing.row.designation_id} row={editing.row} onClose={() => setEditing(null)}
          onSaved={editing.then ? () => createPost(editing.then!) : undefined} />
      )}
    </div>
  )
}
