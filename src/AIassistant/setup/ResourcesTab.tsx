import { useEffect, useRef, useState } from 'react'
import { BookOpen, FileJson, FileText, FileType2, UploadCloud } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { Checkbox, Modal, Select, Table, td, th } from '@/components/kit'
import { ACCEPT, MAX_RESOURCE_MB } from '../core/catalog'
import { formatSize, kindOf, looksPersonal, parseJsonResource, uploadProblem } from '../core/resources'
import type { ServerResource, ServerSetup } from '../data/api'
import { ingestOnce, useIndexGuide, useResources, useUpdateResource, useUploadResource } from '../data/api'

const KIND_ICON = { pdf: FileText, docx: FileType2, json: FileJson }
const STATUS: Record<ServerResource['status'], { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  uploading: { label: 'Uploading…', tone: 'orange' },
  processing: { label: 'Indexing…', tone: 'orange' },
  ready: { label: 'Ready', tone: 'green' },
  failed: { label: 'Failed', tone: 'red' },
  archived: { label: 'Archived', tone: 'slate' },
}

/**
 * Indexes every resource waiting for it, one batch at a time, while this tab is open. Resume points live in the
 * database, so closing the page only pauses the work.
 */
function useIngestRunner(resources: ServerResource[] | undefined) {
  const qc = useQueryClient()
  const busy = useRef(false)
  const [error, setError] = useState<string | null>(null)
  const next = resources?.find((r) => r.status === 'processing')
  useEffect(() => {
    if (!next || busy.current) return
    busy.current = true
    let cancelled = false
    ;(async () => {
      try {
        let more = true
        while (more && !cancelled) {
          const r = await ingestOnce(next.id)
          more = r.more
          if (r.error) setError(`${next.name}: ${r.error}`)
          await qc.invalidateQueries({ queryKey: ['assistant'] })
        }
      } catch (e) {
        setError(errorMessage(e))
      } finally {
        busy.current = false
      }
    })()
    return () => { cancelled = true }
  }, [next?.id]) // eslint-disable-line react-hooks/exhaustive-deps
  return error
}

/** Upload PDF, DOCX and JSON; the Edge Function indexes them into the company's vector store. */
export function ResourcesTab({ setup }: { setup: ServerSetup }) {
  const list = useResources()
  const upload = useUploadResource()
  const update = useUpdateResource()
  const guide = useIndexGuide()
  const runnerError = useIngestRunner(list.data)
  const knowledge = setup.topics.filter((t) => t.group === 'knowledge' && t.key !== 'kb.app_guide')
  const roles = setup.roles.filter((r) => r.system_key !== 'admin')
  const [topicKey, setTopicKey] = useState('kb.company_policy')
  const [narrow, setNarrow] = useState(false)
  const [audience, setAudience] = useState<string[]>([])
  const [problems, setProblems] = useState<string[]>([])
  const [pendingJson, setPendingJson] = useState<File | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [dragging, setDragging] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)
  const replaceRef = useRef<HTMLInputElement>(null)
  const replacing = useRef<ServerResource | null>(null)
  const embedReady = !!setup.keys.embed_effective?.ready

  const send = (file: File, replacesId?: string) =>
    upload.mutateAsync({ file, kind: kindOf(file.name)!, topicKey, audienceRoleIds: narrow ? audience : [], replacesId })

  const handleFiles = async (files: FileList | File[], replace?: ServerResource) => {
    const found: string[] = []
    for (const file of Array.from(files)) {
      const problem = uploadProblem(file, [])
      if (problem) { found.push(`${file.name}: ${problem}`); continue }
      try {
        if (kindOf(file.name) === 'json') {
          const parsed = parseJsonResource(await file.text())
          if ('error' in parsed) { found.push(`${file.name}: ${parsed.error}`); continue }
          if (looksPersonal(parsed.passages)) { setPendingJson(file); continue }
        }
        await send(file, replace?.id)
      } catch (e) {
        found.push(`${file.name}: ${errorMessage(e)}`)
      }
    }
    setProblems(found)
  }

  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const rows = list.data.filter((r) => showArchived || r.status !== 'archived')
  const archived = list.data.filter((r) => r.status === 'archived').length
  const topicLabel = (k: string) => setup.topics.find((t) => t.key === k)?.label ?? k
  const stale = (r: ServerResource) => r.status === 'ready' && setup.keys.embed_effective && r.embedding_model !== setup.keys.embed_effective.model

  return (
    <div className="space-y-6">
      {!embedReady && <Alert tone="info">Add and test the embedding key on the API keys tab first; files are indexed with it.</Alert>}

      <Card className="flex flex-wrap items-center gap-4">
        <BookOpen className="size-6 text-primary-600" aria-hidden />
        <div className="min-w-0 flex-1">
          <h3 className="font-semibold text-slate-900">App guide</h3>
          <p className="text-sm text-slate-500">
            Help for every Olympus page, written by us. {setup.guide.indexed}/{setup.guide.articles} pages indexed for your company
            {setup.guide.indexed_at && ` · ${formatDateTime(setup.guide.indexed_at)}`}.
          </p>
        </div>
        <Button variant="secondary" disabled={!embedReady} loading={guide.isPending} onClick={() => guide.mutate()}>
          {setup.guide.indexed ? 'Index again' : 'Index the app guide'}
        </Button>
        {guide.isError && <p className="w-full text-sm text-red-600">{errorMessage(guide.error)}</p>}
      </Card>

      <Card className="space-y-4">
        <div className="grid gap-4 md:grid-cols-2">
          <Select label="Topic of the new files" name="topic" value={topicKey} onChange={(e) => setTopicKey(e.target.value)}
            options={knowledge.map((t) => ({ value: t.key, label: t.label }))} hint={knowledge.find((t) => t.key === topicKey)?.hint} />
          <div>
            <p className="mb-1.5 text-sm font-medium text-slate-700">Who may read them</p>
            <div className="flex flex-wrap gap-x-4 gap-y-2">
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input type="radio" name="audience" checked={!narrow} onChange={() => setNarrow(false)} className="accent-primary-600" /> Everyone the topic allows
              </label>
              <label className="inline-flex items-center gap-2 text-sm text-slate-700">
                <input type="radio" name="audience" checked={narrow} onChange={() => setNarrow(true)} className="accent-primary-600" /> Only some roles
              </label>
            </div>
            {narrow && (
              <div className="mt-2 flex flex-wrap gap-3">
                {roles.map((r) => (
                  <Checkbox key={r.id} label={r.name} checked={audience.includes(r.id)}
                    onChange={(v) => setAudience(v ? [...audience, r.id] : audience.filter((x) => x !== r.id))} />
                ))}
              </div>
            )}
          </div>
        </div>
        <div
          onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
          onDragLeave={() => setDragging(false)}
          onDrop={(e) => { e.preventDefault(); setDragging(false); void handleFiles(e.dataTransfer.files) }}
          className={cx('rounded-2xl border-2 border-dashed p-8 text-center transition', dragging ? 'border-primary-500 bg-primary-50' : 'border-slate-300')}>
          <UploadCloud className="mx-auto size-8 text-primary-500" aria-hidden />
          <p className="mt-2 text-sm font-medium text-slate-800">Drop files here or</p>
          <Button className="mt-2" variant="secondary" loading={upload.isPending} disabled={!embedReady || (narrow && audience.length === 0)}
            onClick={() => inputRef.current?.click()}>Choose files</Button>
          <p className="mt-2 text-xs text-slate-500">PDF, DOCX or JSON · up to {MAX_RESOURCE_MB} MB each · policies, rules, notices, law</p>
          <input ref={inputRef} type="file" multiple accept={ACCEPT} className="hidden"
            onChange={(e) => { if (e.target.files) void handleFiles(e.target.files); e.target.value = '' }} />
        </div>
        <Alert tone="info">Do not upload employee lists, salary sheets, NID or bank details. The assistant is for rules and policies only.</Alert>
        {problems.length > 0 && <Alert>{problems.map((p) => <p key={p}>{p}</p>)}</Alert>}
        {runnerError && <Alert>{runnerError}</Alert>}
      </Card>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <h3 className="font-semibold text-slate-900">Resources</h3>
        {archived > 0 && <Checkbox label={`Show archived (${archived})`} checked={showArchived} onChange={setShowArchived} />}
      </div>
      {rows.length === 0 ? <EmptyState title="No resources yet">Upload your first policy above.</EmptyState> : (
        <Table minWidth={900} head={
          <tr><th className={th}>Resource</th><th className={th}>Topic</th><th className={th}>Readers</th><th className={th}>Status</th><th className={th}>Size</th><th className={th} aria-label="Actions" /></tr>
        }>
          {rows.map((r) => {
            const Icon = KIND_ICON[r.kind]
            const s = STATUS[r.status]
            return (
              <tr key={r.id} className={cx(r.status === 'archived' && 'opacity-60')}>
                <td className={td}>
                  <div className="flex items-center gap-3">
                    <Icon className="size-5 shrink-0 text-primary-600" aria-hidden />
                    <div className="min-w-0">
                      <p className="truncate font-medium text-slate-900">{r.name}</p>
                      <p className="text-xs text-slate-500">v{r.version} · {r.uploaded_by ?? '—'} · {formatDateTime(r.uploaded_at)}</p>
                    </div>
                  </div>
                </td>
                <td className={td}>
                  <select aria-label={`Topic of ${r.name}`} value={r.topic_key} disabled={r.status === 'archived'}
                    onChange={(e) => update.mutate({ id: r.id, p: { topic_key: e.target.value } })}
                    className="rounded-lg border border-slate-300 bg-white px-2 py-1 text-sm">
                    {knowledge.map((t) => <option key={t.key} value={t.key}>{t.label}</option>)}
                  </select>
                </td>
                <td className={td}>{r.audience_role_ids.length === 0 ? <span className="text-slate-500">{topicLabel(r.topic_key)} roles</span>
                  : r.audience_role_ids.map((id) => setup.roles.find((x) => x.id === id)?.name ?? '?').join(', ')}</td>
                <td className={td}>
                  <Badge tone={s.tone}>{s.label}</Badge>
                  {r.status === 'processing' && r.chunks ? <p className="mt-1 text-xs text-slate-500">{r.processed_through}/{r.chunks} passages</p> : null}
                  {stale(r) && <p className="mt-1 text-xs text-amber-700">Indexed with an older model</p>}
                  {r.error && <p className="mt-1 max-w-56 text-xs text-red-600">{r.error}</p>}
                </td>
                <td className={cx(td, 'whitespace-nowrap text-xs')}>
                  {formatSize(r.size_bytes)}<br />
                  <span className="text-slate-500">{r.units ?? '—'} {r.kind === 'json' ? 'records' : r.kind === 'docx' ? 'sections' : 'pages'} · {r.chunks ?? '—'} chunks</span>
                </td>
                <td className={cx(td, 'whitespace-nowrap text-right')}>
                  {(r.status === 'failed' || stale(r)) && <Button variant="ghost" onClick={() => update.mutate({ id: r.id, p: { action: 'retry' } })}>
                    {r.status === 'failed' ? 'Retry' : 'Index again'}</Button>}
                  {(r.status === 'ready' || r.status === 'failed') && <Button variant="ghost" onClick={() => { replacing.current = r; replaceRef.current?.click() }}>New version</Button>}
                  {r.status === 'archived'
                    ? <Button variant="ghost" onClick={() => update.mutate({ id: r.id, p: { action: 'restore' } })}>Restore</Button>
                    : r.status !== 'processing' && <Button variant="ghost" onClick={() => update.mutate({ id: r.id, p: { action: 'archive' } })}>Archive</Button>}
                </td>
              </tr>
            )
          })}
        </Table>
      )}
      {update.isError && <Alert>{errorMessage(update.error)}</Alert>}
      <input ref={replaceRef} type="file" accept={ACCEPT} className="hidden"
        onChange={(e) => { if (e.target.files && replacing.current) void handleFiles(e.target.files, replacing.current); e.target.value = '' }} />

      <Modal open={!!pendingJson} onClose={() => setPendingJson(null)} title="This file looks like personal data" size="sm"
        footer={<>
          <Button variant="secondary" onClick={() => setPendingJson(null)}>Cancel</Button>
          <Button variant="danger" onClick={() => { const f = pendingJson!; setPendingJson(null); void send(f).catch((e) => setProblems([`${f.name}: ${errorMessage(e)}`])) }}>Upload anyway</Button>
        </>}>
        <p className="text-sm text-slate-600">
          Most records in <b>{pendingJson?.name}</b> contain fields like salary, phone, NID or bank account.
          Everyone the topic allows could read them through the assistant.
        </p>
      </Modal>
    </div>
  )
}
