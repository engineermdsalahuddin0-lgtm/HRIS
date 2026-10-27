import { useState, type ReactNode } from 'react'
import { Archive, ArchiveRestore, Download, Pencil, Upload } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Input, PageLoader } from '@/components/ui'
import { Modal, Select } from '@/components/kit'
import { CLASSIFICATION, expiryBadge, formatSize } from '../core/dms'
import type { DocumentDetail, Library } from '../core/types'
import { openFile, uploadMessage, useArchiveDocument, useDocument, useUpdateDocument } from '../data/api'
import { ClauseTags } from './ClauseTags'
import { AccessFields, TypeFields, type Access } from './FieldInputs'
import { NewVersionForm } from './NewVersionForm'
import { ReviewDecision } from './ReviewDecision'

type Mode = 'view' | 'version' | 'edit'

/** One document: details, version history with downloads, new version, edit, archive. */
export function DocumentModal({ id, library, initialMode = 'view', requestId, onClose }: {
  id: string | null; library: Library; initialMode?: Mode; requestId?: string; onClose: () => void
}) {
  const doc = useDocument(id)
  const [mode, setMode] = useState<Mode>(initialMode)
  const [message, setMessage] = useState<string | null>(null)
  const archive = useArchiveDocument()
  const [fileError, setFileError] = useState<string | null>(null)
  const d = doc.data
  const type = library.types.find((t) => t.id === d?.doc_type_id)

  const title = mode === 'version' ? 'Upload a new version' : mode === 'edit' ? 'Edit details' : (d?.title ?? 'Document')
  return (
    <Modal open={!!id} onClose={onClose} size="lg" title={title}
      description={d ? <span className="font-mono">{d.version_name ?? d.doc_code}</span> : undefined}>
      {doc.isPending ? <PageLoader /> : doc.isError ? <Alert>{errorMessage(doc.error)}</Alert> : d && (
        mode === 'version' ? (
          <NewVersionForm doc={d} type={type} requestId={requestId} onDone={(r) => { setMode('view'); setMessage(uploadMessage(r)) }} />
        ) : mode === 'edit' ? (
          <EditForm doc={d} library={library} onDone={() => { setMode('view'); setMessage('Saved.') }} onCancel={() => setMode('view')} />
        ) : (
          <div className="space-y-5">
            {message && <Alert tone="success">{message}</Alert>}
            {(archive.error || fileError) && <Alert>{fileError ?? errorMessage(archive.error)}</Alert>}
            <Details doc={d} labels={Object.fromEntries((type?.field_schema ?? []).map((f) => [f.key, f.label]))} />
            {d.lifecycle === 'published' && <ClauseTags documentId={d.id} />}
            <div>
              <h3 className="mb-2 text-sm font-semibold text-slate-900">Versions</h3>
              <ul className="divide-y divide-slate-100 rounded-xl ring-1 ring-slate-200">
                {d.versions.map((v) => (
                  <li key={v.id} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 text-sm">
                    <span className="font-mono text-xs font-semibold">{v.version_name}</span>
                    <VersionBadge status={v.status} overdue={v.review_overdue} />
                    <span className="text-xs text-slate-500">
                      {formatDateTime(v.published_at ?? v.uploaded_at)} · {v.uploaded_by ?? '—'} · {v.file_kind.toUpperCase()} {formatSize(v.size_bytes)}
                      {v.expiry_date ? ` · expiry ${formatDate(v.expiry_date)}` : ''}
                    </span>
                    {v.change_note && <span className="w-full text-xs text-slate-600">{v.change_note}</span>}
                    {v.status === 'in_review' && <span className="w-full text-xs text-slate-500">Waiting for review{v.review_due_date ? ` (due ${formatDate(v.review_due_date)})` : ''}</span>}
                    {v.review_comment && <span className="w-full text-xs text-slate-600">{v.status === 'rejected' ? 'Sent back' : 'Reviewed'} by {v.reviewed_by}: {v.review_comment}</span>}
                    {v.published_without_review && <span className="w-full text-xs text-slate-500">Published by the Admin without review</span>}
                    <button type="button" className="ml-auto inline-flex items-center gap-1 text-xs font-medium text-primary-700 hover:underline"
                      onClick={() => { setFileError(null); openFile(v.id).catch((e) => setFileError(errorMessage(e))) }}>
                      <Download className="size-3.5" aria-hidden /> Download
                    </button>
                  </li>
                ))}
              </ul>
              <p className="mt-1 text-xs text-slate-500">Original file name: {d.versions[0]?.original_file_name ?? '—'} (kept for reference only)</p>
            </div>
            {d.custodians.length > 0 && <p className="text-xs text-slate-500">Responsible for this folder: {d.custodians.join(', ')}</p>}
            {d.can_review && d.versions.filter((v) => v.status === 'in_review' && !v.uploaded_by_me).map((v) => (
              <div key={v.id} className="space-y-2 rounded-xl bg-primary-50 p-3">
                <p className="text-sm font-medium text-slate-900">Review {v.version_name}</p>
                <ReviewDecision versionId={v.id} onDone={(ok) => setMessage(ok ? `${v.version_name} approved and published.` : `${v.version_name} sent back to ${v.uploaded_by ?? 'the uploader'}.`)} />
              </div>
            ))}
            {d.can_edit && (
              <div className="flex flex-wrap gap-2">
                {(d.lifecycle === 'published' || d.lifecycle === 'pending') && !d.versions.some((v) => v.status === 'in_review') && (
                  <Button onClick={() => { setMessage(null); setMode('version') }}><Upload className="size-4" />{d.has_expiry ? 'Upload renewal' : 'New version'}</Button>
                )}
                <Button variant="secondary" onClick={() => { setMessage(null); setMode('edit') }}><Pencil className="size-4" /> Edit details</Button>
                {d.lifecycle === 'published' ? (
                  <Button variant="ghost" loading={archive.isPending}
                    onClick={() => window.confirm(`Archive ${d.doc_code}? Readers will no longer see it.`) && archive.mutate({ id: d.id, archive: true }, { onSuccess: onClose })}>
                    <Archive className="size-4" /> Archive
                  </Button>
                ) : d.lifecycle === 'archived' && (
                  <Button variant="ghost" loading={archive.isPending} onClick={() => archive.mutate({ id: d.id, archive: false })}>
                    <ArchiveRestore className="size-4" /> Restore
                  </Button>
                )}
              </div>
            )}
          </div>
        )
      )}
    </Modal>
  )
}

function VersionBadge({ status, overdue }: { status: DocumentDetail['versions'][number]['status']; overdue: boolean }) {
  if (status === 'current') return <Badge tone="green">Current</Badge>
  if (status === 'in_review') return <Badge tone={overdue ? 'red' : 'orange'}>{overdue ? 'Review overdue' : 'In review'}</Badge>
  if (status === 'rejected') return <Badge tone="red">Sent back</Badge>
  return <Badge>Old version</Badge>
}

function Details({ doc: d, labels }: { doc: DocumentDetail; labels: Record<string, string> }) {
  const badge = expiryBadge(d.expiry_status, d.days_left)
  const rows: [string, ReactNode][] = [
    ['Folder', d.folder],
    ['Type', `${d.type_name} (${d.type_code})`],
    ['Department', d.department],
    ['Owner', d.owner ?? '—'],
    ['Classification', CLASSIFICATION[d.classification].label + (d.scope === 'departments' ? ' · some departments' : '')],
    ...(d.has_expiry ? [['Expiry', <span key="e" className="inline-flex items-center gap-2">{formatDate(d.expiry_date)} <Badge tone={badge.tone}>{badge.label}</Badge></span>] as [string, ReactNode]] : []),
    ...(d.next_review_date ? [['Next review', formatDate(d.next_review_date)] as [string, ReactNode]] : []),
    ...Object.entries(d.fields).map(([k, v]) => [labels[k] ?? k, v] as [string, ReactNode]),
  ]
  return (
    <dl className="grid gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
      {rows.map(([k, v]) => (
        <div key={k}>
          <dt className="text-xs text-slate-500">{k}</dt>
          <dd className="text-slate-900">{v}</dd>
        </div>
      ))}
    </dl>
  )
}

function EditForm({ doc: d, library, onDone, onCancel }: { doc: DocumentDetail; library: Library; onDone: () => void; onCancel: () => void }) {
  const update = useUpdateDocument()
  const type = library.types.find((t) => t.id === d.doc_type_id)
  const [title, setTitle] = useState(d.title)
  const [folderId, setFolderId] = useState(d.folder_id)
  const [expiry, setExpiry] = useState(d.expiry_date ?? '')
  const [review, setReview] = useState(d.next_review_date ?? '')
  const [fields, setFields] = useState<Record<string, string>>(d.fields)
  const [access, setAccess] = useState<Access>({
    classification: d.classification, scope: d.scope, scope_department_ids: d.scope_department_ids, restricted_role_ids: d.restricted_role_ids,
  })
  return (
    <form className="space-y-4" onSubmit={(e) => {
      e.preventDefault()
      update.mutate({ id: d.id, p: {
        title, folder_id: folderId, ...access, next_review_date: review || null, ...(d.has_expiry ? { expiry_date: expiry || null } : {}),
        ...(type && type.field_schema.length > 0 ? { fields } : {}),
      } }, { onSuccess: onDone })
    }}>
      <p className="text-xs text-slate-500">The code {d.doc_code} and the files never change; moving to another folder keeps both.</p>
      <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} required />
      <Select label="Folder" value={folderId} onChange={(e) => setFolderId(e.target.value)}
        options={library.folders.map((f) => ({ value: f.id, label: f.name }))} />
      {d.has_expiry && <Input label="Expiry date" type="date" value={expiry} onChange={(e) => setExpiry(e.target.value)} required />}
      <Input label="Next review date" type="date" value={review} onChange={(e) => setReview(e.target.value)} />
      {type && <TypeFields schema={type.field_schema} values={fields} onChange={setFields} />}
      <AccessFields value={access} onChange={setAccess} library={library} />
      {update.isError && <Alert>{errorMessage(update.error)}</Alert>}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="secondary" onClick={onCancel}>Cancel</Button>
        <Button type="submit" loading={update.isPending}>Save</Button>
      </div>
    </form>
  )
}
