import { useMemo, useRef, useState } from 'react'
import { FileJson, FileText, FileType2, UploadCloud } from 'lucide-react'
import { Alert, Badge, Button, Card, EmptyState, cx } from '@/components/ui'
import { Checkbox, Modal, Select, Table, td, th } from '@/components/kit'
import { ACCEPT, KNOWLEDGE_TOPICS, MAX_RESOURCE_MB, ROLES, roleLabel, topicOf } from '../core/catalog'
import { estimateDocument, formatSize, kindOf, looksPersonal, parseJsonResource, uploadProblem } from '../core/resources'
import type { Passage, Resource, ResourceKind, ResourceStatus, RoleKey } from '../core/types'
import { useAssistantStore } from '../data/store'

const KIND_ICON: Record<ResourceKind, typeof FileText> = { pdf: FileText, docx: FileType2, json: FileJson }
const STATUS: Record<ResourceStatus, { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  processing: { label: 'Processing…', tone: 'orange' },
  ready: { label: 'Ready', tone: 'green' },
  failed: { label: 'Failed', tone: 'red' },
  archived: { label: 'Archived', tone: 'slate' },
}
const MAX_PREVIEW_PASSAGES = 500

interface PendingJson { file: File; passages: Passage[]; replaceId?: string }

/**
 * Upload PDF, DOCX and JSON. The backend extracts text page by page (records for JSON),
 * splits it into chunks with the Model settings, and embeds it; this tab shows the status.
 */
export function ResourcesTab({ uploader }: { uploader: string }) {
  const setup = useAssistantStore((s) => s.setup)
  const addResource = useAssistantStore((s) => s.addResource)
  const updateResource = useAssistantStore((s) => s.updateResource)
  const loadSamples = useAssistantStore((s) => s.loadSamples)
  const [topicKey, setTopicKey] = useState('kb.company_policy')
  const [audience, setAudience] = useState<RoleKey[]>([])
  const [narrow, setNarrow] = useState(false)
  const [problems, setProblems] = useState<string[]>([])
  const [pendingJson, setPendingJson] = useState<PendingJson | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [dragging, setDragging] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const replaceRef = useRef<HTMLInputElement>(null)
  const replacing = useRef<string | null>(null)

  const list = useMemo(
    () => setup.resources.filter((r) => showArchived || r.status !== 'archived'),
    [setup.resources, showArchived],
  )
  const archivedCount = setup.resources.filter((r) => r.status === 'archived').length

  const store = (file: File, passages: Passage[] | null, replaceId?: string, error?: string) => {
    const kind = kindOf(file.name)!
    const old = replaceId ? setup.resources.find((r) => r.id === replaceId) : undefined
    const estimate = estimateDocument(file.size, setup.hyper.chunkSize, setup.hyper.chunkOverlap)
    if (old) updateResource(old.id, { status: 'archived' })
    addResource({
      id: crypto.randomUUID(),
      name: file.name,
      kind,
      sizeBytes: file.size,
      topicKey: old?.topicKey ?? topicKey,
      audience: old?.audience ?? (narrow ? audience : []),
      status: error ? 'failed' : 'processing',
      error,
      units: passages ? passages.length : estimate.units,
      chunks: passages ? passages.length : estimate.chunks,
      version: (old?.version ?? 0) + 1,
      uploadedAt: new Date().toISOString(),
      uploadedBy: uploader,
      passages: (passages ?? []).slice(0, MAX_PREVIEW_PASSAGES),
    })
  }

  const handleFiles = async (files: FileList | File[], replaceId?: string) => {
    const found: string[] = []
    for (const file of Array.from(files)) {
      // A new version may keep the old name; other uploads must be unique.
      const others = replaceId ? setup.resources.filter((r) => r.id !== replaceId) : setup.resources
      const problem = uploadProblem(file, others)
      if (problem) { found.push(`${file.name}: ${problem}`); continue }
      if (kindOf(file.name) === 'json') {
        const parsed = parseJsonResource(await file.text())
        if ('error' in parsed) { store(file, [], replaceId, parsed.error); continue }
        if (looksPersonal(parsed.passages)) { setPendingJson({ file, passages: parsed.passages, replaceId }); continue }
        store(file, parsed.passages, replaceId)
      } else {
        store(file, null, replaceId)
      }
    }
    setProblems(found)
  }

  return (
    <div className="space-y-6">
      <Card className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <Select label="Topic of the new files" name="topic" value={topicKey} onChange={(e) => setTopicKey(e.target.value)}
            options={KNOWLEDGE_TOPICS.map((t) => ({ value: t.key, label: t.label }))}
            hint={topicOf(topicKey)?.hint} />
          <div>
            <p className="mb-1.5 text-sm font-medium text-slate-700">Who may read them</p>
            <div className="flex flex-wrap gap-x-4 gap-y-2">
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input type="radio" name="audience" checked={!narrow} onChange={() => setNarrow(false)} className="accent-primary-600" />
                Everyone the topic allows
              </label>
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input type="radio" name="audience" checked={narrow} onChange={() => setNarrow(true)} className="accent-primary-600" />
                Only some roles
              </label>
            </div>
            {narrow && (
              <div className="mt-2 flex flex-wrap gap-3">
                {ROLES.filter((r) => r.key !== 'admin').map((r) => (
                  <Checkbox key={r.key} label={r.label} checked={audience.includes(r.key)}
                    onChange={(v) => setAudience(v ? [...audience, r.key] : audience.filter((x) => x !== r.key))} />
                ))}
              </div>
            )}
          </div>
        </div>

        <div
          onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
          onDragLeave={() => setDragging(false)}
          onDrop={(e) => { e.preventDefault(); setDragging(false); void handleFiles(e.dataTransfer.files) }}
          className={cx('rounded-2xl border-2 border-dashed p-8 text-center transition',
            dragging ? 'border-primary-500 bg-primary-50' : 'border-slate-300')}
        >
          <UploadCloud className="mx-auto size-8 text-primary-500" aria-hidden />
          <p className="mt-2 text-sm font-medium text-slate-800">Drop files here or</p>
          <Button className="mt-2" variant="secondary" onClick={() => inputRef.current?.click()} disabled={narrow && audience.length === 0}>
            Choose files
          </Button>
          <p className="mt-2 text-xs text-slate-500">PDF, DOCX or JSON · up to {MAX_RESOURCE_MB} MB each · policies, rules, notices, law</p>
          <input ref={inputRef} type="file" multiple accept={ACCEPT} className="hidden"
            onChange={(e) => { if (e.target.files) void handleFiles(e.target.files); e.target.value = '' }} />
        </div>
        <Alert tone="info">
          Do not upload employee lists, salary sheets, NID or bank details. The assistant is for rules and policies only.
        </Alert>
        {problems.length > 0 && <Alert>{problems.map((p) => <p key={p}>{p}</p>)}</Alert>}
      </Card>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-4">
          <h3 className="font-semibold text-slate-900">Resources</h3>
          {archivedCount > 0 && <Checkbox label={`Show archived (${archivedCount})`} checked={showArchived} onChange={setShowArchived} />}
        </div>
        <Button variant="ghost" onClick={() => void loadSamples()}>Load sample resources</Button>
      </div>

      {list.length === 0 ? (
        <EmptyState title="No resources yet">Upload your first policy, or load the sample resources to try the assistant.</EmptyState>
      ) : (
        <Table minWidth={860} head={
          <tr>
            <th className={th}>Resource</th><th className={th}>Topic</th><th className={th}>Readers</th>
            <th className={th}>Status</th><th className={th}>Size</th><th className={th} aria-label="Actions" />
          </tr>
        }>
          {list.map((r) => <ResourceRow key={r.id} r={r} onReplace={() => { replacing.current = r.id; replaceRef.current?.click() }} />)}
        </Table>
      )}
      <input ref={replaceRef} type="file" accept={ACCEPT} className="hidden"
        onChange={(e) => { if (e.target.files && replacing.current) void handleFiles(e.target.files, replacing.current); e.target.value = '' }} />

      <Modal open={!!pendingJson} onClose={() => setPendingJson(null)} title="This file looks like personal data" size="sm"
        footer={<>
          <Button variant="secondary" onClick={() => setPendingJson(null)}>Cancel</Button>
          <Button variant="danger" onClick={() => { store(pendingJson!.file, pendingJson!.passages, pendingJson!.replaceId); setPendingJson(null) }}>Upload anyway</Button>
        </>}>
        <p className="text-sm text-slate-600">
          Most records in <b>{pendingJson?.file.name}</b> contain fields like salary, phone, NID or bank account.
          Everyone the topic allows could read them through the assistant.
        </p>
      </Modal>
    </div>
  )
}

function ResourceRow({ r, onReplace }: { r: Resource; onReplace: () => void }) {
  const updateResource = useAssistantStore((s) => s.updateResource)
  const Icon = KIND_ICON[r.kind]
  const status = STATUS[r.status]
  return (
    <tr className={cx(r.status === 'archived' && 'opacity-60')}>
      <td className={td}>
        <div className="flex items-center gap-3">
          <Icon className="size-5 shrink-0 text-primary-600" aria-hidden />
          <div className="min-w-0">
            <p className="truncate font-medium text-slate-900">{r.name}</p>
            <p className="text-xs text-slate-500">
              v{r.version} · {r.uploadedBy} · {new Date(r.uploadedAt).toLocaleDateString()}
            </p>
          </div>
        </div>
      </td>
      <td className={td}>
        <select aria-label={`Topic of ${r.name}`} value={r.topicKey} disabled={r.status === 'archived'}
          onChange={(e) => updateResource(r.id, { topicKey: e.target.value })}
          className="rounded-lg border border-slate-300 bg-white px-2 py-1 text-sm">
          {KNOWLEDGE_TOPICS.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
        </select>
      </td>
      <td className={td}>{r.audience.length === 0 ? <span className="text-slate-500">Topic roles</span> : r.audience.map(roleLabel).join(', ')}</td>
      <td className={td}>
        <Badge tone={status.tone}>{status.label}</Badge>
        {r.error && <p className="mt-1 max-w-48 text-xs text-red-600">{r.error}</p>}
      </td>
      <td className={cx(td, 'whitespace-nowrap text-xs')}>
        {formatSize(r.sizeBytes)}<br />
        <span className="text-slate-500">{r.units} {r.kind === 'json' ? 'records' : 'pages'} · {r.chunks} chunks</span>
      </td>
      <td className={cx(td, 'whitespace-nowrap text-right')}>
        {r.status === 'failed' && r.kind !== 'json' && <Button variant="ghost" onClick={() => updateResource(r.id, { status: 'processing', error: undefined })}>Retry</Button>}
        {r.status === 'ready' && <Button variant="ghost" onClick={onReplace}>New version</Button>}
        {r.status === 'archived'
          ? <Button variant="ghost" onClick={() => updateResource(r.id, { status: 'ready' })}>Restore</Button>
          : r.status !== 'processing' && <Button variant="ghost" onClick={() => updateResource(r.id, { status: 'archived' })}>Archive</Button>}
      </td>
    </tr>
  )
}
