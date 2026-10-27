import { useState, type ReactNode } from 'react'
import { Download, Send, Upload } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader } from '@/components/ui'
import { Modal } from '@/components/kit'
import type { DmsRequest, Library, VersionTask } from '../core/types'
import { openFile, uploadMessage, useCancelRequest, useTasks } from '../data/api'
import { RequestForm } from './RequestForm'
import { ServerError } from './ServerError'
import { ReviewDecision } from './ReviewDecision'
import { UploadForm } from './UploadForm'

type Open = (documentId: string, mode: 'view' | 'version', requestId?: string) => void

/** My tasks: requested from me, my uploads under review or sent back, requests I made. */
export function MyTasks({ library, onOpen }: { library: Library; onOpen: Open }) {
  const tasks = useTasks()
  const cancel = useCancelRequest()
  const [uploading, setUploading] = useState<DmsRequest | null>(null)
  const [asking, setAsking] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  if (tasks.isPending) return <PageLoader />
  if (tasks.isError) return <ServerError error={tasks.error} step="tasks" />
  const t = tasks.data

  const startUpload = (r: DmsRequest) => {
    setMessage(null)
    if (r.document_id) onOpen(r.document_id, 'version', r.id)
    else setUploading(r)
  }

  return (
    <div className="space-y-6">
      {message && <Alert tone="success">{message}</Alert>}
      {t.can_request && (
        <div className="flex justify-end">
          <Button variant="secondary" onClick={() => { setMessage(null); setAsking(true) }}><Send className="size-4" /> Request a document</Button>
        </div>
      )}

      <Section title="Requested from me" count={t.requested_from_me.length}>
        {t.requested_from_me.length === 0 ? <EmptyState title="Nothing is requested from you" /> : (
          <ul className="space-y-2">
            {t.requested_from_me.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center gap-3 rounded-xl p-3 ring-1 ring-slate-200">
                <RequestText r={r} />
                <Button className="ml-auto" onClick={() => startUpload(r)}><Upload className="size-4" />{r.kind === 'renewal' ? 'Upload renewal' : 'Upload'}</Button>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="My uploads waiting or sent back" count={t.my_uploads.length}>
        {t.my_uploads.length === 0 ? <EmptyState title="No uploads waiting" /> : (
          <ul className="space-y-2">
            {t.my_uploads.map((v) => (
              <li key={v.version_id} className="flex flex-wrap items-center gap-3 rounded-xl p-3 ring-1 ring-slate-200">
                <VersionText v={v} />
                {v.version_status === 'rejected' && (
                  <Button variant="secondary" className="ml-auto" onClick={() => onOpen(v.id, 'version')}><Upload className="size-4" /> Upload again</Button>
                )}
              </li>
            ))}
          </ul>
        )}
      </Section>

      {t.requests_i_made.length > 0 && (
        <Section title="Requests I made" count={t.requests_i_made.length}>
          {cancel.isError && <Alert>{errorMessage(cancel.error)}</Alert>}
          <ul className="space-y-2">
            {t.requests_i_made.map((r) => (
              <li key={r.id} className="flex flex-wrap items-center gap-3 rounded-xl p-3 ring-1 ring-slate-200">
                <RequestText r={r} showAssignee />
                <Button variant="ghost" className="ml-auto" loading={cancel.isPending && cancel.variables === r.id}
                  onClick={() => window.confirm('Cancel this request?') && cancel.mutate(r.id)}>Cancel</Button>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {uploading && (
        <Modal open onClose={() => setUploading(null)} size="lg" title="Upload for the request">
          <UploadForm library={library} folderId={null} request={uploading}
            onDone={(r) => { setUploading(null); setMessage(uploadMessage(r)) }}
            onNewVersion={(d) => { setUploading(null); onOpen(d.id, 'version', uploading.id) }} />
        </Modal>
      )}
      {asking && <RequestForm library={library} onClose={() => setAsking(false)} onDone={(m) => { setAsking(false); setMessage(m) }} />}
    </div>
  )
}

/** Review queue: the Admin sees everything; dms.approve holders their departments. Never approved by itself. */
export function ReviewQueue({ onOpen }: { onOpen: Open }) {
  const tasks = useTasks()
  const [message, setMessage] = useState<string | null>(null)
  const [fileError, setFileError] = useState<string | null>(null)
  if (tasks.isPending) return <PageLoader />
  if (tasks.isError) return <ServerError error={tasks.error} step="tasks" />
  const list = tasks.data.to_review
  return (
    <div className="space-y-4">
      <p className="text-sm text-slate-500">
        Nothing is published until someone here decides. Past the review period an item shows as “Review overdue” and stays until it is decided.
      </p>
      {message && <Alert tone="success">{message}</Alert>}
      {fileError && <Alert>{fileError}</Alert>}
      {list.length === 0 ? <EmptyState title="Nothing waiting for review" /> : list.map((v) => (
        <Card key={v.version_id} className="space-y-3">
          <div className="flex flex-wrap items-center gap-3">
            <VersionText v={v} />
            <div className="ml-auto flex gap-2">
              <Button variant="ghost" onClick={() => { setFileError(null); openFile(v.version_id).catch((e) => setFileError(errorMessage(e))) }}>
                <Download className="size-4" /> Open file
              </Button>
              <Button variant="ghost" onClick={() => onOpen(v.id, 'view')}>Details</Button>
            </div>
          </div>
          <ReviewDecision versionId={v.version_id}
            onDone={(ok) => setMessage(ok ? `${v.pending_version_name} approved and published.` : `${v.pending_version_name} sent back to ${v.uploaded_by_name ?? 'the uploader'}.`)} />
        </Card>
      ))}
    </div>
  )
}

function Section({ title, count, children }: { title: string; count: number; children: ReactNode }) {
  return (
    <section className="space-y-2">
      <h3 className="text-base font-semibold text-slate-900">{title} <span className="text-sm font-normal text-slate-500">({count})</span></h3>
      {children}
    </section>
  )
}

function RequestText({ r, showAssignee }: { r: DmsRequest; showAssignee?: boolean }) {
  const what = r.doc_code ? `${r.doc_code} ${r.doc_title ?? ''}` : r.type_name ?? r.folder ?? 'A document'
  return (
    <div className="min-w-0 flex-1 text-sm">
      <p className="font-medium text-slate-900">
        {r.kind === 'renewal' ? 'Renewal: ' : ''}{what}
        {r.overdue && <> <Badge tone="red">Upload overdue</Badge></>}
        {r.status === 'submitted' && <> <Badge tone="orange">Uploaded, in review</Badge></>}
      </p>
      {r.note && <p className="text-slate-600">{r.note}</p>}
      <p className="text-xs text-slate-500">
        {showAssignee ? `To ${r.assignee ?? '—'}` : `From ${r.requested_by ?? '—'}`}{r.department ? ` · ${r.department}` : ''}
        {r.due_date ? ` · due ${formatDate(r.due_date)}` : ''}
      </p>
    </div>
  )
}

function VersionText({ v }: { v: VersionTask }) {
  return (
    <div className="min-w-0 flex-1 text-sm">
      <p className="font-medium text-slate-900">
        {v.title} <span className="font-mono text-xs text-slate-500">{v.pending_version_name}</span>{' '}
        {v.version_status === 'rejected' ? <Badge tone="red">Sent back</Badge>
          : <Badge tone={v.review_overdue ? 'red' : 'orange'}>{v.review_overdue ? 'Review overdue' : 'In review'}</Badge>}
      </p>
      <p className="text-xs text-slate-500">
        {v.folder} · {v.department} · uploaded by {v.uploaded_by_name ?? '—'}{v.review_due_date ? ` · review by ${formatDate(v.review_due_date)}` : ''}
      </p>
      {v.review_comment && <p className="text-xs text-red-700">Reason: {v.review_comment}{v.reviewed_by_name ? ` (${v.reviewed_by_name})` : ''}</p>}
    </div>
  )
}
