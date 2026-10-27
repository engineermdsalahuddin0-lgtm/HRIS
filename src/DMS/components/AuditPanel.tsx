import { useState } from 'react'
import { Download, ShieldCheck } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { downloadText, toCsv } from '@/lib/payrollRuns'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Select, Table, Textarea, td, th } from '@/components/kit'
import { addDays } from '../core/dms'
import type { AuditRow } from '../core/types'
import { useAccessReview, useAudit, useSignAccessReview } from '../data/api'

const ACTION: Record<string, string> = {
  'dms.document_published': 'Published (v1)',
  'dms.version_published': 'New version published',
  'dms.published_without_review': 'Published by the Admin (no review)',
  'dms.submitted_for_review': 'Sent for review',
  'dms.approved': 'Approved',
  'dms.rejected': 'Sent back',
  'dms.clauses_tagged': 'ISO clauses tagged',
  'dms.disposal_requested': 'Disposal requested',
  'dms.disposal_approved': 'Disposal approved',
  'dms.disposed': 'Disposed',
  'dms.access_reviewed': 'Access review signed',
  'dms.download': 'Downloaded',
}

const describe = (r: AuditRow) =>
  ACTION[r.action] ?? `${r.action === 'insert' ? 'Created' : r.action === 'update' ? 'Changed' : r.action} ${r.entity.replace(/^dms_/, '').replace(/_/g, ' ')}`

const detailText = (r: AuditRow) => {
  if (!r.detail) return ''
  if (r.kind === 'download') return `v${r.detail.version ?? '?'}`
  if (r.action === 'update') return Object.keys(r.detail).join(', ')
  return Object.entries(r.detail).filter(([, v]) => typeof v !== 'object').map(([k, v]) => `${k}: ${v}`).join(' · ')
}

/** dms.manage / dms.audit: every change, approval and download, plus the quarterly access review. */
export function AuditPanel({ onOpen }: { onOpen: (id: string) => void }) {
  const [from, setFrom] = useState(addDays(-30))
  const [to, setTo] = useState(addDays(0))
  const [kind, setKind] = useState('all')
  const [q, setQ] = useState('')
  const audit = useAudit({ from, to, kind, q: q.trim() || null })

  const exportCsv = (rows: AuditRow[]) => downloadText(`documents-audit-${from}-to-${to}.csv`,
    toCsv(['When', 'What', 'Document', 'Title', 'By', 'Detail'],
      rows.map((r) => [formatDateTime(r.at), describe(r), r.doc_code ?? '', r.title ?? '', r.by ?? '', detailText(r)])))

  return (
    <div className="space-y-6">
      <AccessReviewCard />
      <Card className="space-y-4">
        <div className="flex flex-wrap items-end gap-3">
          <Input label="From" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          <Input label="To" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          <Select label="Show" value={kind} onChange={(e) => setKind(e.target.value)}
            options={[{ value: 'all', label: 'Everything' }, { value: 'changes', label: 'Changes and approvals' }, { value: 'downloads', label: 'Downloads' }]} />
          <Input label="Code or title" value={q} onChange={(e) => setQ(e.target.value)} placeholder="HR-POL" />
          <Button variant="secondary" className="ml-auto" disabled={!audit.data?.length} onClick={() => audit.data && exportCsv(audit.data)}>
            <Download className="size-4" /> Export CSV
          </Button>
        </div>
        {audit.isPending ? <PageLoader /> : audit.isError ? <Alert>{errorMessage(audit.error)}</Alert>
          : audit.data.length === 0 ? <EmptyState title="Nothing in this period" /> : (
            <Table minWidth={760} head={<tr><th className={th}>When</th><th className={th}>What</th><th className={th}>Document</th><th className={th}>By</th><th className={th}>Detail</th></tr>}>
              {audit.data.map((r, i) => (
                <tr key={`${r.at}-${i}`}>
                  <td className={`${td} whitespace-nowrap text-xs`}>{formatDateTime(r.at)}</td>
                  <td className={td}><Badge tone={r.kind === 'download' ? 'slate' : r.action === 'dms.disposed' || r.action === 'dms.rejected' ? 'red' : 'orange'}>{describe(r)}</Badge></td>
                  <td className={td}>
                    {r.document_id && r.doc_code ? (
                      <button type="button" className="text-left hover:text-primary-700" onClick={() => onOpen(r.document_id!)}>
                        <span className="font-mono text-xs">{r.doc_code}</span> {r.title}
                      </button>
                    ) : '—'}
                  </td>
                  <td className={td}>{r.by ?? 'System'}</td>
                  <td className={`${td} max-w-64 truncate text-xs text-slate-500`} title={detailText(r)}>{detailText(r)}</td>
                </tr>
              ))}
            </Table>
          )}
      </Card>
    </div>
  )
}

function AccessReviewCard() {
  const review = useAccessReview()
  const sign = useSignAccessReview()
  const [note, setNote] = useState('')
  if (review.isPending) return null
  if (review.isError) return <Alert>{errorMessage(review.error)}</Alert>
  const r = review.data
  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-start gap-3">
        <ShieldCheck className="size-6 text-primary-600" aria-hidden />
        <div className="min-w-0 flex-1">
          <h3 className="text-base font-semibold text-slate-900">Access review</h3>
          <p className="text-sm text-slate-500">
            Every quarter, check who holds document rights and sign it off (evidence for ISO 27001).{' '}
            {r.last_reviewed_at ? `Last signed ${formatDate(r.last_reviewed_at)}.` : 'Never signed yet.'}
          </p>
        </div>
        {r.due && <Badge tone="red">Review due</Badge>}
      </div>
      <Table minWidth={640} head={<tr><th className={th}>Role</th><th className={th}>Document rights</th><th className={th}>People</th></tr>}>
        {r.current.roles.map((x) => (
          <tr key={x.role}>
            <td className={td}>{x.role}</td>
            <td className={`${td} text-xs`}>{x.rights.map((k) => k.replace('dms.', '')).join(', ')}</td>
            <td className={`${td} text-xs`}>{x.people.join(', ') || '—'}</td>
          </tr>
        ))}
      </Table>
      {r.current.custodians.length > 0 && (
        <p className="text-xs text-slate-500">Responsible for folders: {r.current.custodians.map((c) => `${c.person} (${c.folder})`).join(', ')}</p>
      )}
      {r.can_sign && (
        <div className="space-y-2">
          <Textarea label="Note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="e.g. Q4 review: removed upload right from the Sales role" maxLength={1000} />
          {sign.isError && <Alert>{errorMessage(sign.error)}</Alert>}
          {sign.isSuccess && <Alert tone="success">Signed. The snapshot is kept below.</Alert>}
          <Button loading={sign.isPending} onClick={() => sign.mutate(note, { onSuccess: () => setNote('') })}>Sign off this review</Button>
        </div>
      )}
      {r.history.length > 0 && (
        <ul className="space-y-1 text-xs text-slate-600">
          {r.history.map((h) => <li key={h.id}>{formatDateTime(h.reviewed_at)} · {h.reviewed_by} · {h.note ?? 'no note'}</li>)}
        </ul>
      )}
    </Card>
  )
}
