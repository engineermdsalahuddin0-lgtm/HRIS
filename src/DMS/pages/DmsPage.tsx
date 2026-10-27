import { useMemo, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { CheckCircle2, ChevronRight, Circle, FolderPlus, Search, Sparkles, Upload } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, cx } from '@/components/ui'
import { Modal, PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { addDays, buildTree, expiryBadge } from '../core/dms'
import type { DmsDocument, ExpiryStatus, Library } from '../core/types'
import { uploadMessage, useDocuments, useLibrary, useOverview, useSaveFolder } from '../data/api'
import { useMyContext } from '@/lib/appContext'
import { CompliancePanel } from '../components/CompliancePanel'
import { DocumentModal } from '../components/DocumentModal'
import { DocumentTable } from '../components/DocumentTable'
import { FolderTree } from '../components/FolderTree'
import { SetupPanel } from '../components/SetupPanel'
import { MyTasks, ReviewQueue } from '../components/TasksPanel'
import { UploadForm } from '../components/UploadForm'

type Tab = 'overview' | 'library' | 'tasks' | 'review' | 'expiry' | 'iso' | 'setup'
type OpenDoc = { id: string; mode: 'view' | 'version'; requestId?: string }

/**
 * /documents: the document library. The user opens a folder and uploads; the system names the file
 * ({DEPT}-{TYPE}-{SEQ}_v{n}), refuses duplicates and keeps every version.
 */
export default function DmsPage() {
  const ctx = useMyContext()
  // UI check only; the database decides (dms.manage or dms.audit).
  const auditor = ctx.permissions.includes('dms.manage') || ctx.permissions.includes('dms.audit')
  const library = useLibrary()
  const [params, setParams] = useSearchParams()
  const tab = (params.get('tab') as Tab | null) ?? 'overview'
  const folder = params.get('folder')
  const [open, setOpen] = useState<OpenDoc | null>(params.get('doc') ? { id: params.get('doc')!, mode: 'view' } : null)
  const go = (next: Partial<{ tab: Tab; folder: string | null }>) => {
    const p = new URLSearchParams(params)
    if (next.tab) p.set('tab', next.tab)
    if (next.folder !== undefined) {
      if (next.folder) p.set('folder', next.folder)
      else p.delete('folder')
    }
    p.delete('doc')
    setParams(p, { replace: true })
  }

  if (library.isPending) return <PageLoader />
  if (library.isError) return <div className="mx-auto max-w-3xl"><Alert>{errorMessage(library.error)}</Alert></div>
  const lib = library.data
  const tabs: { key: Tab; label: string }[] = [
    { key: 'overview', label: 'Overview' },
    { key: 'library', label: 'Library' },
    { key: 'tasks', label: 'My tasks' },
    ...(lib.can.review ? [{ key: 'review' as Tab, label: 'Review' }] : []),
    { key: 'expiry', label: 'Expiry & renewals' },
    ...(auditor ? [{ key: 'iso' as Tab, label: 'ISO compliance' }] : []),
    ...(lib.can.manage ? [{ key: 'setup' as Tab, label: 'Setup' }] : []),
  ]

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Document library" description="Upload a file and the system names, files and keeps every version for you." />
      {!lib.enabled && <Alert tone="info">The document library is switched off for your company.</Alert>}
      <Alert tone="info">
        Naming standard for every file: <span className="font-mono font-semibold">{'{DEPT}-{TYPE}-{SEQ}_v{VER}'}</span>, e.g.{' '}
        <span className="font-mono">HR-POL-0012_v3</span>. Folders only decide where a file is shown.
      </Alert>
      <Tabs<Tab> value={tab} onChange={(t) => go({ tab: t })} tabs={tabs} />
      {tab === 'overview' && <OverviewTab lib={lib} onOpen={(d, mode = 'view') => setOpen({ id: d.id, mode })} go={go} />}
      {tab === 'library' && <LibraryTab lib={lib} folder={folder} onFolder={(f) => go({ folder: f })} onOpen={(d) => setOpen({ id: d.id, mode: 'view' })} />}
      {tab === 'tasks' && <MyTasks library={lib} onOpen={(id, mode, requestId) => setOpen({ id, mode, requestId })} />}
      {tab === 'review' && lib.can.review && <ReviewQueue onOpen={(id, mode) => setOpen({ id, mode })} />}
      {tab === 'expiry' && <ExpiryTab onOpen={(d, mode) => setOpen({ id: d.id, mode })} canUpload={lib.can.upload} />}
      {tab === 'iso' && auditor && <CompliancePanel onOpen={(id) => setOpen({ id, mode: 'view' })} onSetup={lib.can.manage ? () => go({ tab: 'setup' }) : undefined} />}
      {tab === 'setup' && lib.can.manage && <SetupPanel />}
      {open && <DocumentModal key={`${open.id}-${open.mode}`} id={open.id} initialMode={open.mode} requestId={open.requestId} library={lib} onClose={() => setOpen(null)} />}
    </div>
  )
}

// ----------------------------------------------------------------------------- Overview
function OverviewTab({ lib, onOpen, go }: {
  lib: Library; onOpen: (d: DmsDocument, mode?: 'view' | 'version') => void; go: (n: { tab?: Tab; folder?: string | null }) => void
}) {
  const [from, setFrom] = useState(addDays(0))
  const [to, setTo] = useState(addDays(90))
  const overview = useOverview(from, to)
  const [saved, setSaved] = useState<string | null>(null)
  const tree = useMemo(() => buildTree(lib.folders), [lib.folders])
  if (overview.isPending) return <PageLoader />
  if (overview.isError) return <Alert>{errorMessage(overview.error)}</Alert>
  const o = overview.data
  const steps = [
    { done: o.steps.iso.done, title: '1. ISO standard (optional)',
      text: o.steps.iso.profiles.length ? `${o.steps.iso.profiles.map((p) => p.replace('_', ' ')).join(', ')} selected.` : o.steps.iso.no_iso ? 'No ISO standard: base folders only.' : 'Pick the standards you follow, or say you use none.',
      action: lib.can.manage ? () => go({ tab: 'setup' }) : undefined },
    { done: o.steps.departments.done, title: '2. Department codes',
      text: o.steps.departments.missing_code ? `${o.steps.departments.missing_code} of ${o.steps.departments.total} departments still need a short code.` : `${o.steps.departments.total} departments ready.`,
      href: '/organization' },
    { done: o.steps.documents.done, title: '3. Documents', text: o.steps.documents.total ? `${o.steps.documents.total} documents in the library.` : 'Upload at least one PDF, DOCX, XLSX or JSON file.',
      action: () => go({ tab: 'library' }) },
    { done: o.steps.ai.done, title: '4. Index for AI assistant', text: 'Comes with the AI step: approved Public and Internal documents will be indexed with their source details.' },
  ]
  const doneCount = steps.filter((s) => s.done).length
  const counts: [string, number, string, Tab | null][] = [
    ['Documents', o.counts.documents, o.counts.documents ? 'In the library' : 'Upload to begin', 'library'],
    ['Expiring in 60 days', o.counts.expiring_60, o.counts.expired ? `${o.counts.expired} already expired` : 'Licences and contracts', 'expiry'],
    ['Awaiting approval', o.counts.awaiting_approval, o.counts.review_overdue ? `${o.counts.review_overdue} review overdue` : 'No pending items', lib.can.review ? 'review' : null],
    ['Requested from me', o.counts.requested_from_me, o.counts.upload_overdue ? `${o.counts.upload_overdue} upload overdue` : 'Nothing overdue', 'tasks'],
    ['Indexed for AI', o.counts.indexed, o.counts.indexed ? 'Answers can cite them' : 'Step 4 not started', null],
  ]

  return (
    <div className="grid gap-6 lg:grid-cols-3">
      <div className="space-y-6 lg:col-span-2">
        <Card className="space-y-3">
          <div className="flex items-center gap-3">
            <span className="flex size-10 items-center justify-center rounded-xl bg-primary-50 text-primary-600"><Sparkles className="size-5" aria-hidden /></span>
            <div>
              <h3 className="text-lg font-semibold text-slate-900">{doneCount} of 4 steps done</h3>
              <p className="text-sm text-slate-500">Finish the steps and the assistant can answer from your documents.</p>
            </div>
          </div>
          <ul className="space-y-2">
            {steps.map((s) => {
              const body = (
                <>
                  {s.done ? <CheckCircle2 className="size-5 shrink-0 text-green-600" aria-label="done" /> : <Circle className="size-5 shrink-0 text-slate-300" aria-label="not done" />}
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-medium text-slate-900">{s.title}</span>
                    <span className="block text-xs text-slate-500">{s.text}</span>
                  </span>
                  {(s.action || s.href) && <ChevronRight className="size-4 text-slate-400" aria-hidden />}
                </>
              )
              const cls = 'flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left ring-1 ring-slate-200'
              return (
                <li key={s.title}>
                  {s.href ? <Link to={s.href} className={cx(cls, 'hover:ring-primary-300')}>{body}</Link>
                    : s.action ? <button type="button" onClick={s.action} className={cx(cls, 'hover:ring-primary-300')}>{body}</button>
                    : <div className={cls}>{body}</div>}
                </li>
              )
            })}
          </ul>
        </Card>

        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          {counts.map(([label, value, hint, target]) => (
            <button key={label} type="button" disabled={!target} onClick={() => target && go({ tab: target })}
              className="rounded-2xl bg-white p-4 text-left shadow-sm ring-1 ring-slate-200 transition enabled:hover:ring-primary-300">
              <p className="text-xs text-slate-500">{label}</p>
              <p className={cx('mt-1 text-2xl font-semibold', value > 0 && label !== 'Documents' && label !== 'Indexed for AI' ? 'text-primary-700' : 'text-slate-900')}>{value}</p>
              <p className={cx('text-xs', /overdue/.test(hint) ? 'font-medium text-red-600' : 'text-slate-500')}>{hint}</p>
            </button>
          ))}
        </div>

        <Card className="space-y-4">
          <div className="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h3 className="text-base font-semibold text-slate-900">Licences by expiry date</h3>
              <p className="text-sm text-slate-500">Everything with an expiry date; expired ones always show.</p>
            </div>
            <div className="flex gap-2">
              <Input label="From" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
              <Input label="To" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
            </div>
          </div>
          {o.expiring.length === 0 ? <EmptyState title="Nothing expires in this range" /> : <ExpiryRows docs={o.expiring} onOpen={onOpen} canUpload={lib.can.upload} />}
        </Card>
      </div>

      <div className="space-y-6">
        {lib.can.upload && (
          <Card className="space-y-3">
            <h3 className="text-base font-semibold text-slate-900">Upload document</h3>
            {saved && <Alert tone="success">{saved}</Alert>}
            <UploadForm library={lib} folderId={null} onDone={(r) => setSaved(uploadMessage(r))} onNewVersion={(d) => onOpen(d, 'version')} />
          </Card>
        )}
        <Card className="space-y-2">
          <h3 className="text-base font-semibold text-slate-900">Folders</h3>
          <ul className="space-y-0.5">
            {tree.map((f) => (
              <li key={f.id}>
                <button type="button" onClick={() => go({ tab: 'library', folder: f.id })}
                  className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-sm text-slate-700 hover:bg-slate-100">
                  <span>{f.name}</span><span className="text-xs text-slate-500">{f.total}</span>
                </button>
              </li>
            ))}
          </ul>
        </Card>
        <Card className="space-y-2">
          <h3 className="text-base font-semibold text-slate-900">Fixed naming standard</h3>
          <pre className="rounded-lg bg-slate-50 p-3 font-mono text-xs text-slate-700">{'{DEPT}-{TYPE}-{SEQ}_v{VER}\nHR-POL-0012_v3'}</pre>
          <p className="text-xs text-slate-500">Names are made by the system and cannot be edited, so every file is stored and found the same way.</p>
        </Card>
      </div>
    </div>
  )
}

function ExpiryRows({ docs, onOpen, canUpload }: { docs: DmsDocument[]; onOpen: (d: DmsDocument, mode: 'view' | 'version') => void; canUpload: boolean }) {
  return (
    <Table minWidth={640} head={
      <tr><th className={th}>Document</th><th className={th}>Authority / party</th><th className={th}>Expiry</th><th className={th}>Status</th><th className={th} aria-label="Actions" /></tr>
    }>
      {docs.map((d) => {
        const badge = expiryBadge(d.expiry_status, d.days_left)
        return (
          <tr key={d.id}>
            <td className={td}>
              <button type="button" onClick={() => onOpen(d, 'view')} className="text-left font-medium text-slate-900 hover:text-primary-700">{d.title}</button>
              <p className="font-mono text-xs text-slate-500">{d.version_name}</p>
            </td>
            <td className={td}>{d.fields.authority ?? d.fields.party ?? '—'}</td>
            <td className={cx(td, 'whitespace-nowrap')}>{formatDate(d.expiry_date)}</td>
            <td className={td}><Badge tone={badge.tone}>{badge.label}</Badge></td>
            <td className={cx(td, 'text-right')}>
              {canUpload && d.expiry_status !== 'active' && (
                <button type="button" onClick={() => onOpen(d, 'version')} className="text-xs font-medium text-primary-700 hover:underline">Upload renewal</button>
              )}
            </td>
          </tr>
        )
      })}
    </Table>
  )
}

// ----------------------------------------------------------------------------- Library
function LibraryTab({ lib, folder, onFolder, onOpen }: {
  lib: Library; folder: string | null; onFolder: (id: string | null) => void; onOpen: (d: DmsDocument) => void
}) {
  const [q, setQ] = useState('')
  const [showArchived, setShowArchived] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [newFolder, setNewFolder] = useState<string | null>(null)
  const [saved, setSaved] = useState<string | null>(null)
  const saveFolder = useSaveFolder()
  const tree = useMemo(() => buildTree(lib.folders), [lib.folders])
  const total = tree.reduce((s, n) => s + n.total, 0)
  const current = lib.folders.find((f) => f.id === folder) ?? null
  const docs = useDocuments({ folder_id: current?.id ?? null, q: q.trim() || undefined, archived: showArchived || undefined })

  return (
    <div className="grid gap-6 lg:grid-cols-[260px_1fr]">
      <Card className="h-fit space-y-3 p-4">
        <FolderTree tree={tree} selected={current?.id ?? null} onSelect={onFolder} total={total} />
        {lib.can.upload && (
          newFolder === null ? (
            <Button variant="ghost" className="w-full" onClick={() => setNewFolder('')}><FolderPlus className="size-4" /> New folder{current ? ' here' : ''}</Button>
          ) : (
            <form className="space-y-2" onSubmit={(e) => {
              e.preventDefault()
              saveFolder.mutate({ id: null, p: { name: newFolder, parent_id: current?.id ?? null } }, {
                onSuccess: (id) => { setNewFolder(null); onFolder(id) },
              })
            }}>
              <Input label={current ? `New folder in ${current.name}` : 'New folder'} value={newFolder} autoFocus onChange={(e) => setNewFolder(e.target.value)} />
              {saveFolder.isError && <p className="text-xs text-red-600">{errorMessage(saveFolder.error)}</p>}
              <div className="flex gap-2">
                <Button type="submit" className="flex-1" loading={saveFolder.isPending}>Create</Button>
                <Button type="button" variant="ghost" onClick={() => setNewFolder(null)}>Cancel</Button>
              </div>
            </form>
          )
        )}
      </Card>

      <div className="min-w-0 space-y-4">
        <div className="flex flex-wrap items-center gap-3">
          <h3 className="text-lg font-semibold text-slate-900">{current?.name ?? 'All documents'}</h3>
          <div className="relative ml-auto w-full sm:w-64">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" aria-hidden />
            <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search code or title" aria-label="Search code or title"
              className="w-full rounded-xl border border-slate-300 py-2 pl-9 pr-3 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
          </div>
          {lib.can.upload && <Button onClick={() => { setSaved(null); setUploading(true) }}><Upload className="size-4" /> Upload</Button>}
        </div>
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} className="size-4 accent-primary-600" />
          Show archived
        </label>
        {saved && <Alert tone="success">{saved}</Alert>}
        {docs.isPending ? <PageLoader /> : docs.isError ? <Alert>{errorMessage(docs.error)}</Alert>
          : docs.data.length === 0 ? (
            <EmptyState title={q ? 'Nothing matches your search' : 'No documents here yet'}>
              {lib.can.upload && !q ? 'Press Upload and drop a file; the system names it for you.' : null}
            </EmptyState>
          ) : <DocumentTable docs={docs.data} onOpen={onOpen} showFolder={!current} />}
      </div>

      {uploading && (
        <Modal open onClose={() => setUploading(false)} size="lg" title={current ? `Upload to ${current.name}` : 'Upload document'}>
          <UploadForm library={lib} folderId={current?.id ?? null}
            onDone={(r) => { setUploading(false); setSaved(uploadMessage(r)) }}
            onNewVersion={(d) => { setUploading(false); onOpen(d) }} />
        </Modal>
      )}
    </div>
  )
}

// ----------------------------------------------------------------------------- Expiry & renewals
function ExpiryTab({ onOpen, canUpload }: { onOpen: (d: DmsDocument, mode: 'view' | 'version') => void; canUpload: boolean }) {
  const [filter, setFilter] = useState<ExpiryStatus | 'all'>('all')
  const docs = useDocuments(filter === 'all' ? {} : { expiry: filter })
  const rows = (docs.data ?? []).filter((d) => d.expiry_date).sort((a, b) => a.expiry_date!.localeCompare(b.expiry_date!))
  const chips: [ExpiryStatus | 'all', string][] = [['all', 'All with expiry'], ['expired', 'Expired'], ['due', 'Due within 60 days'], ['active', 'Active']]
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {chips.map(([k, label]) => (
          <button key={k} type="button" onClick={() => setFilter(k)}
            className={cx('rounded-full px-3 py-1.5 text-sm ring-1 transition', filter === k ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-700 ring-slate-300 hover:ring-slate-400')}>
            {label}
          </button>
        ))}
      </div>
      <p className="text-sm text-slate-500">The owner and the people responsible for the folder get reminders (60, 30, 7 days and on the day; set in Setup) and a renewal task. “Upload renewal” keeps the code and adds the next version.</p>
      {docs.isPending ? <PageLoader /> : docs.isError ? <Alert>{errorMessage(docs.error)}</Alert>
        : rows.length === 0 ? <EmptyState title="No documents with an expiry date here" />
        : <ExpiryRows docs={rows} onOpen={onOpen} canUpload={canUpload} />}
    </div>
  )
}
