import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader } from '@/components/ui'
import { Table, td, th } from '@/components/kit'
import type { Records, RetentionRule } from '../core/types'
import { useApproveDisposal, useFinishDisposal, useRecords, useRecordsAction } from '../data/api'
import { ServerError } from './ServerError'

const START: Record<RetentionRule['start_event'], string> = { published: 'after publishing', archived: 'after archiving', expiry: 'after expiry' }

/**
 * dms.records: retention rules (set by the company, never defaulted), documents due, legal holds, and
 * two-person disposal (one requests, another approves; files removed, proof kept).
 */
export function RecordsPanel({ onOpen }: { onOpen: (id: string) => void }) {
  const data = useRecords(true)
  const act = useRecordsAction()
  const approve = useApproveDisposal()
  const finish = useFinishDisposal()
  const [message, setMessage] = useState<string | null>(null)
  if (data.isPending) return <PageLoader />
  if (data.isError) return <ServerError error={data.error} step="records" />
  const r = data.data
  const error = act.error ?? approve.error ?? finish.error
  const run = (fn: string, args: Record<string, unknown>, done: string) => {
    setMessage(null)
    act.mutate({ fn, args }, { onSuccess: () => setMessage(done) })
  }

  return (
    <div className="space-y-6">
      {message && <Alert tone="success">{message}</Alert>}
      {error && <Alert>{errorMessage(error)}</Alert>}

      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">Due under the retention rules ({r.due.length})</h3>
        {r.due.length === 0 ? <EmptyState title="Nothing is due" /> : (
          <Table minWidth={720} head={<tr><th className={th}>Document</th><th className={th}>Retention ended</th><th className={th}>Rule says</th><th className={th} aria-label="Actions" /></tr>}>
            {r.due.map((d) => (
              <tr key={d.id}>
                <td className={td}>
                  <button type="button" className="text-left font-medium text-slate-900 hover:text-primary-700" onClick={() => onOpen(d.id)}>{d.title}</button>
                  <p className="font-mono text-xs text-slate-500">{d.version_name}{d.legal_hold ? ' · on legal hold' : ''}</p>
                </td>
                <td className={td}>{formatDate(d.retention_ends)}</td>
                <td className={td}><Badge tone={d.retention_action === 'dispose' ? 'red' : 'orange'}>{d.retention_action === 'dispose' ? 'Dispose' : 'Review'}</Badge></td>
                <td className={`${td} text-right`}>
                  {d.disposal ? <Badge>{d.disposal.status === 'requested' ? 'Disposal requested' : 'Disposal approved'}</Badge>
                    : d.retention_action === 'dispose' && !d.legal_hold && (
                      <Button variant="secondary" onClick={() => {
                        const reason = window.prompt(`Why dispose ${d.doc_code}? (another records manager must approve)`, 'Retention period ended')
                        if (reason) run('request_dms_disposal', { p_document_id: d.id, p_reason: reason }, `Disposal of ${d.doc_code} requested; another records manager must approve it.`)
                      }}>Request disposal</Button>
                    )}
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Card>

      <Disposals r={r} busy={approve.isPending || finish.isPending || act.isPending}
        onApprove={(id, code) => { setMessage(null); approve.mutate(id, { onSuccess: () => setMessage(`${code} disposed; the proof is kept below.`) }) }}
        onFinish={(id, paths) => { setMessage(null); finish.mutate({ id, paths }, { onSuccess: () => setMessage('Disposal completed.') }) }}
        onCancel={(id) => run('cancel_dms_disposal', { p_id: id }, 'Disposal request cancelled.')} />

      <Card className="space-y-3">
        <h3 className="text-base font-semibold text-slate-900">Legal holds ({r.holds.length})</h3>
        <p className="text-sm text-slate-500">A held document cannot be disposed. Place a hold from the document itself.</p>
        {r.holds.length === 0 ? <EmptyState title="No document is on hold" /> : (
          <ul className="space-y-2">
            {r.holds.map((h) => (
              <li key={h.id} className="flex flex-wrap items-center gap-3 rounded-xl p-3 text-sm ring-1 ring-slate-200">
                <div className="min-w-0 flex-1">
                  <button type="button" className="font-medium text-slate-900 hover:text-primary-700" onClick={() => onOpen(h.document_id)}>{h.doc_code} {h.title}</button>
                  <p className="text-xs text-slate-500">{h.reason} · {h.placed_by} · {formatDate(h.placed_at)}</p>
                </div>
                <Button variant="ghost" onClick={() => {
                  const reason = window.prompt('Why is the hold released?')
                  if (reason) run('release_dms_hold', { p_hold_id: h.id, p_reason: reason }, 'Hold released.')
                }}>Release</Button>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <RulesCard r={r} saving={act.isPending} onSave={(typeId, p) => run('save_dms_retention_rule', { p_doc_type_id: typeId, p }, 'Rule saved.')} />
    </div>
  )
}

function Disposals({ r, busy, onApprove, onFinish, onCancel }: {
  r: Records; busy: boolean
  onApprove: (id: string, code: string) => void; onFinish: (id: string, paths: string[]) => void; onCancel: (id: string) => void
}) {
  if (r.disposals.length === 0) return null
  return (
    <Card className="space-y-3">
      <h3 className="text-base font-semibold text-slate-900">Disposals</h3>
      <ul className="space-y-2">
        {r.disposals.map((x) => (
          <li key={x.id} className="flex flex-wrap items-center gap-3 rounded-xl p-3 text-sm ring-1 ring-slate-200">
            <div className="min-w-0 flex-1">
              <p className="font-medium text-slate-900">
                <span className="font-mono">{x.doc_code}</span> {x.title}{' '}
                <Badge tone={x.status === 'done' ? 'slate' : 'orange'}>{x.status === 'done' ? 'Disposed' : x.status === 'approved' ? 'Approved, files pending' : 'Waiting for approval'}</Badge>
              </p>
              <p className="text-xs text-slate-500">
                {x.reason} · requested by {x.requested_by} {formatDate(x.requested_at)}
                {x.approved_by ? ` · approved by ${x.approved_by} ${formatDate(x.approved_at)}` : ''}
                {x.completed_at ? ` · ${x.versions} file(s) removed ${formatDate(x.completed_at)}` : ''}
              </p>
              {x.status === 'done' && <p className="break-all font-mono text-[11px] text-slate-400">SHA-256: {x.hashes.join(', ')}</p>}
            </div>
            {x.status === 'requested' && !x.requested_by_me && (
              <Button variant="danger" loading={busy} onClick={() => window.confirm(`Dispose ${x.doc_code}? Its files are deleted for good.`) && onApprove(x.id, x.doc_code)}>
                Approve and dispose
              </Button>
            )}
            {x.status === 'requested' && x.requested_by_me && <span className="text-xs text-slate-500">Another records manager must approve</span>}
            {x.status === 'requested' && <Button variant="ghost" onClick={() => onCancel(x.id)}>Cancel</Button>}
            {x.status === 'approved' && <Button variant="secondary" loading={busy} onClick={() => onFinish(x.id, x.paths)}>Remove files and finish</Button>}
          </li>
        ))}
      </ul>
    </Card>
  )
}

function RulesCard({ r, saving, onSave }: { r: Records; saving: boolean; onSave: (typeId: string, p: Record<string, unknown>) => void }) {
  const [edit, setEdit] = useState<{ typeId: string; start_event: string; retain_years: string; action: string; note: string } | null>(null)
  return (
    <Card className="space-y-3">
      <div>
        <h3 className="text-base font-semibold text-slate-900">Retention rules</h3>
        <p className="text-sm text-slate-500">
          How long each type is kept. Set the years from your legal advice and company policy; without a rule a document is never offered for disposal.
        </p>
      </div>
      <Table minWidth={720} head={<tr><th className={th}>Type</th><th className={th}>Rule</th><th className={th}>Documents</th><th className={th} aria-label="Actions" /></tr>}>
        {r.rules.map((t) => edit?.typeId === t.doc_type_id ? (
          <tr key={t.doc_type_id}>
            <td className={td}>{t.type_name}</td>
            <td className={td} colSpan={2}>
              <div className="flex flex-wrap items-center gap-2 text-xs">
                Keep
                <input type="number" min={1} max={100} value={edit.retain_years} onChange={(e) => setEdit({ ...edit, retain_years: e.target.value })}
                  aria-label="Years" className="w-16 rounded-lg border border-slate-300 px-2 py-1" />
                years
                <select aria-label="Starting" value={edit.start_event} onChange={(e) => setEdit({ ...edit, start_event: e.target.value })} className="rounded-lg border border-slate-300 px-2 py-1">
                  {Object.entries(START).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
                then
                <select aria-label="Action" value={edit.action} onChange={(e) => setEdit({ ...edit, action: e.target.value })} className="rounded-lg border border-slate-300 px-2 py-1">
                  <option value="review">review</option><option value="dispose">dispose</option>
                </select>
                <input value={edit.note} onChange={(e) => setEdit({ ...edit, note: e.target.value })} placeholder="Basis (law / policy)" aria-label="Basis"
                  className="min-w-40 flex-1 rounded-lg border border-slate-300 px-2 py-1" />
              </div>
            </td>
            <td className={`${td} whitespace-nowrap text-right`}>
              <Button loading={saving} onClick={() => { onSave(t.doc_type_id, { ...edit, retain_years: Number(edit.retain_years) }); setEdit(null) }}>Save</Button>
              <Button variant="ghost" onClick={() => setEdit(null)}>Cancel</Button>
            </td>
          </tr>
        ) : (
          <tr key={t.doc_type_id}>
            <td className={td}><span className="font-medium text-slate-900">{t.type_name}</span> <span className="font-mono text-xs text-slate-500">{t.type_code}</span></td>
            <td className={td}>
              {t.rule ? `${t.rule.retain_years} years ${START[t.rule.start_event]}, then ${t.rule.action}` : <span className="text-slate-400">No rule (kept)</span>}
              {t.rule?.note && <p className="text-xs text-slate-500">{t.rule.note}</p>}
            </td>
            <td className={td}>{t.documents}</td>
            <td className={`${td} whitespace-nowrap text-right`}>
              <button type="button" className="text-xs font-medium text-primary-700 hover:underline"
                onClick={() => setEdit({ typeId: t.doc_type_id, start_event: t.rule?.start_event ?? 'published', retain_years: String(t.rule?.retain_years ?? ''),
                                         action: t.rule?.action ?? 'review', note: t.rule?.note ?? '' })}>{t.rule ? 'Change' : 'Set rule'}</button>
              {t.rule && <button type="button" className="ml-3 text-xs text-slate-500 hover:underline" onClick={() => onSave(t.doc_type_id, { active: false })}>Remove</button>}
            </td>
          </tr>
        ))}
      </Table>
    </Card>
  )
}
