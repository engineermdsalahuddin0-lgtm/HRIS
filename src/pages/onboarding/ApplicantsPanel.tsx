// Applicants of one job post: report table (sort, filter by source), row click
// opens the full profile in a modal, and HR can add people who applied elsewhere.
import { useMemo, useState } from 'react'
import { ArrowDownUp, FileText, UserPlus } from 'lucide-react'
import type { Applicant, ApplicantSource, JobPost } from '@/onboarding-process/core/types'
import { APPLICANT_STATUS_LABEL, SOURCE_LABEL } from '@/onboarding-process/core/jobPost'
import { useApplicants } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, Spinner } from '@/components/ui'
import { Select, Table, td, th } from '@/components/kit'
import { ApplicantDialog } from './dialogs/ApplicantDialog'
import { AddApplicantsDialog } from './dialogs/AddApplicantsDialog'

type SortKey = 'created_at' | 'full_name' | 'source'

export function ApplicantsPanel({ post }: { post: JobPost }) {
  const applicants = useApplicants(post.id)
  const [source, setSource] = useState<ApplicantSource | ''>('')
  const [sort, setSort] = useState<{ key: SortKey; desc: boolean }>({ key: 'created_at', desc: true })
  const [openId, setOpenId] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)

  const rows = useMemo(() => {
    const list = (applicants.data ?? []).filter((a) => !source || a.source === source)
    const dir = sort.desc ? -1 : 1
    return [...list].sort((a, b) => (a[sort.key] < b[sort.key] ? -dir : a[sort.key] > b[sort.key] ? dir : 0))
  }, [applicants.data, source, sort])
  const open = applicants.data?.find((a) => a.id === openId)
  const header = (key: SortKey, label: string) => (
    <th className={th}>
      <button type="button" className="inline-flex items-center gap-1 uppercase hover:text-slate-800"
        onClick={() => setSort((s) => ({ key, desc: s.key === key ? !s.desc : key === 'created_at' }))}>
        {label}<ArrowDownUp className="size-3" />
      </button>
    </th>
  )

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h3 className="text-lg font-semibold text-slate-900">Applicants</h3>
          <p className="text-sm text-slate-500">CVs are kept only until the vacancy closes. Screening and scores come in the next step.</p>
        </div>
        <div className="flex flex-wrap items-end gap-2">
          <Select aria-label="Filter by source" value={source} onChange={(e) => setSource(e.target.value as ApplicantSource | '')}
            options={[{ value: '', label: 'All sources' }, ...Object.entries(SOURCE_LABEL).map(([value, label]) => ({ value, label }))]} />
          <Button variant="secondary" onClick={() => setAdding(true)}><UserPlus className="size-4" />Add applicants</Button>
        </div>
      </div>
      {applicants.isPending ? <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
        : applicants.isError ? <Alert>{errorMessage(applicants.error)}</Alert>
          : rows.length === 0 ? (
            <EmptyState title={source ? 'No applicants from this source' : 'No applicants yet'}>
              Share the apply link or the poster, or add people who sent their CV by email, LinkedIn or Bdjobs.
            </EmptyState>
          ) : (
            <Table minWidth={760} head={(
              <tr>{header('full_name', 'Name')}<th className={th}>Contact</th>{header('source', 'Source')}
                <th className={th}>CV</th><th className={th}>Status</th>{header('created_at', 'Applied')}</tr>
            )}>
              {rows.map((a: Applicant) => (
                <tr key={a.id} className="cursor-pointer hover:bg-slate-50" onClick={() => setOpenId(a.id)}>
                  <td className={td}>
                    <button type="button" className="text-left font-medium text-slate-900 hover:text-primary-700" onClick={() => setOpenId(a.id)}>{a.full_name}</button>
                  </td>
                  <td className={td}><p className="text-xs">{a.email}</p><p className="text-xs text-slate-400">{a.phone ?? '—'}</p></td>
                  <td className={td}>{SOURCE_LABEL[a.source]}</td>
                  <td className={td}>{a.has_cv ? <FileText className="size-4 text-primary-600" aria-label="CV uploaded" /> : <span className="text-xs text-slate-400">Missing</span>}</td>
                  <td className={td}><Badge>{APPLICANT_STATUS_LABEL[a.status]}</Badge></td>
                  <td className={td}>{formatDate(a.created_at)}</td>
                </tr>
              ))}
            </Table>
          )}
      {open && <ApplicantDialog key={open.id} applicant={open} post={post} onClose={() => setOpenId(null)} />}
      {adding && <AddApplicantsDialog postId={post.id} onClose={() => setAdding(false)} />}
    </section>
  )
}
