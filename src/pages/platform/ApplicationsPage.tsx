import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ArrowLeft, MailCheck, MailWarning } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import type { ApplicationRow, ApplicationStatus } from '@/lib/platform'
import { usePlatformAction, usePlatformApplications } from '@/lib/platform'
import { Alert, Badge, Button, EmptyState, PageLoader, cx } from '@/components/ui'
import { Modal, PageHeader, Table, Textarea, td, th } from '@/components/kit'

const FILTERS: { key: ApplicationStatus | 'all'; label: string }[] = [
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Accepted' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'all', label: 'All' },
]
const STATUS_TONE = { pending: 'orange', approved: 'green', rejected: 'red', cancelled: 'slate' } as const
const STATUS_LABEL = { pending: 'Pending', approved: 'Accepted', rejected: 'Rejected', cancelled: 'Cancelled' } as const

/** Organization applications submitted from the landing page: review, accept or reject with remarks. */
export default function ApplicationsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const filter = (searchParams.get('status') as ApplicationStatus | null) ?? 'pending'
  const applications = usePlatformApplications(filter === ('all' as string) ? null : filter)
  const approve = usePlatformAction<{ p_request_id: string }, string>('approve_org_signup_request')
  const reject = usePlatformAction<{ p_request_id: string; p_note: string }>('reject_org_signup_request')
  const [selected, setSelected] = useState<ApplicationRow | null>(null)
  const [mode, setMode] = useState<'view' | 'reject'>('view')
  const [remarks, setRemarks] = useState('')
  const [actionError, setActionError] = useState<string | null>(null)

  const open = (row: ApplicationRow) => {
    setSelected(row)
    setMode('view')
    setRemarks('')
    setActionError(null)
  }

  const runApprove = async () => {
    if (!selected) return
    setActionError(null)
    try {
      await approve.mutateAsync({ p_request_id: selected.id })
      setSelected(null)
    } catch (err) {
      setActionError(errorMessage(err))
    }
  }

  const runReject = async () => {
    if (!selected || !remarks.trim()) return
    setActionError(null)
    try {
      await reject.mutateAsync({ p_request_id: selected.id, p_note: remarks.trim() })
      setSelected(null)
    } catch (err) {
      setActionError(errorMessage(err))
    }
  }

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <Link to="/platform" className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
        <ArrowLeft className="size-4" /> Platform
      </Link>
      <PageHeader title="Organization applications" description="Accepting creates the organization (on a free trial) and makes the applicant its Admin." />

      <div className="flex flex-wrap gap-2" role="tablist">
        {FILTERS.map((f) => (
          <button key={f.key} role="tab" aria-selected={filter === f.key} onClick={() => setSearchParams({ status: f.key })}
            className={cx('rounded-full px-4 py-1.5 text-sm font-medium transition',
              filter === f.key ? 'bg-primary-600 text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50')}>
            {f.label}
          </button>
        ))}
      </div>

      {applications.isPending ? <PageLoader /> : applications.isError ? <Alert>{errorMessage(applications.error)}</Alert>
        : applications.data.length === 0 ? <EmptyState title="No applications here" /> : (
          <Table minWidth={820} head={
            <tr>
              <th className={th}>Organization</th><th className={th}>Applicant</th><th className={th}>Size</th>
              <th className={th}>Submitted</th><th className={th}>Status</th><th className={th} />
            </tr>
          }>
            {applications.data.map((row) => (
              <tr key={row.id} className="cursor-pointer hover:bg-slate-50" onClick={() => open(row)}>
                <td className={td}>
                  <p className="font-medium text-slate-900">{row.org_name}</p>
                  <p className="text-xs text-slate-400">{row.industry ?? ''}</p>
                </td>
                <td className={td}>
                  <p>{row.contact_name}</p>
                  <p className="flex items-center gap-1 text-xs text-slate-400">
                    {row.email_confirmed ? <MailCheck className="size-3.5 text-green-600" /> : <MailWarning className="size-3.5 text-amber-600" />}
                    {row.applicant_email}
                  </p>
                </td>
                <td className={td}>{row.employee_range ?? '—'}</td>
                <td className={td}>{formatDateTime(row.created_at)}</td>
                <td className={td}>
                  <Badge tone={STATUS_TONE[row.status]}>{STATUS_LABEL[row.status]}</Badge>
                  {row.review_note && <p className="mt-1 max-w-56 truncate text-xs text-slate-400" title={row.review_note}>{row.review_note}</p>}
                </td>
                <td className="px-4 py-3 text-right"><Button variant="ghost">View</Button></td>
              </tr>
            ))}
          </Table>
        )}

      <Modal
        open={!!selected}
        onClose={() => setSelected(null)}
        size="md"
        title={selected?.org_name ?? ''}
        description={selected ? `Submitted ${formatDateTime(selected.created_at)}` : undefined}
        footer={selected?.status === 'pending' ? (
          mode === 'view' ? (
            <>
              <Button variant="secondary" onClick={() => setMode('reject')}>Reject</Button>
              <Button loading={approve.isPending} onClick={runApprove}>Accept and create organization</Button>
            </>
          ) : (
            <>
              <Button variant="secondary" onClick={() => setMode('view')}>Back</Button>
              <Button variant="danger" loading={reject.isPending} disabled={!remarks.trim()} onClick={runReject}>Reject with remarks</Button>
            </>
          )
        ) : selected?.organization_id ? (
          <Link to={`/platform/organizations/${selected.organization_id}`}><Button>Open organization</Button></Link>
        ) : undefined}
      >
        {selected && (
          <div className="space-y-4">
            {actionError && <Alert>{actionError}</Alert>}
            {!selected.email_confirmed && selected.status === 'pending' && (
              <Alert tone="info">The applicant has not confirmed their email yet. You can accept now; they can sign in after confirming.</Alert>
            )}
            <dl className="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
              <Detail label="Contact person" value={selected.contact_name} />
              <Detail label="Email" value={selected.applicant_email} />
              <Detail label="Phone" value={selected.contact_phone} />
              <Detail label="Employees" value={selected.employee_range} />
              <Detail label="Industry" value={selected.industry} />
              <Detail label="Interested plan" value={selected.plan_interest} />
              <div className="sm:col-span-2"><Detail label="Address" value={selected.address} /></div>
              {selected.review_note && <div className="sm:col-span-2"><Detail label="Remarks" value={selected.review_note} /></div>}
            </dl>
            {mode === 'reject' && (
              <Textarea label="Remarks (shown to the applicant)" value={remarks} onChange={(e) => setRemarks(e.target.value)}
                placeholder="e.g. Please use a company email address and give the correct employee count." />
            )}
          </div>
        )}
      </Modal>
    </div>
  )
}

function Detail({ label, value }: { label: string; value: string | null | undefined }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-slate-400">{label}</dt>
      <dd className="mt-0.5 text-slate-800">{value || '—'}</dd>
    </div>
  )
}
