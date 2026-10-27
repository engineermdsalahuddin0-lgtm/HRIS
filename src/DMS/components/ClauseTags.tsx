import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button } from '@/components/ui'
import { useDocumentClauses, useSetClauses } from '../data/api'

/** The ISO clauses a document is evidence for: from its type (fixed) and manual tags (dms.manage). */
export function ClauseTags({ documentId }: { documentId: string }) {
  const data = useDocumentClauses(documentId)
  const save = useSetClauses()
  const [editing, setEditing] = useState<string[] | null>(null)
  if (!data.data) return null
  const { tags, can_tag, clauses } = data.data
  if (tags.length === 0 && !can_tag) return null
  const key = (t: { profile: string; clause: string }) => `${t.profile}|${t.clause}`
  const fromType = new Set(tags.filter((t) => t.source === 'type').map(key))
  return (
    <div className="space-y-2">
      <h3 className="text-sm font-semibold text-slate-900">ISO evidence for</h3>
      {editing === null ? (
        <div className="flex flex-wrap items-center gap-2">
          {tags.length === 0 && <span className="text-xs text-slate-500">No ISO clause.</span>}
          {tags.map((t) => (
            <span key={key(t)} title={t.topic} className="rounded-full bg-slate-100 px-2.5 py-0.5 text-xs text-slate-700">
              {t.profile.replace('_', ' ')} {t.clause}{t.source === 'manual' ? ' (tagged)' : ''}
            </span>
          ))}
          {can_tag && clauses && clauses.length > 0 && (
            <button type="button" className="text-xs font-medium text-primary-700 hover:underline"
              onClick={() => setEditing(tags.filter((t) => t.source === 'manual').map(key))}>Tag clauses</button>
          )}
        </div>
      ) : (
        <div className="space-y-2 rounded-xl p-3 ring-1 ring-slate-200">
          <div className="max-h-56 space-y-1 overflow-y-auto">
            {(clauses ?? []).map((c) => {
              const k = key(c)
              const fixed = fromType.has(k)
              return (
                <label key={k} className="flex items-center gap-2 text-xs text-slate-700">
                  <input type="checkbox" className="size-4 accent-primary-600" disabled={fixed} checked={fixed || editing.includes(k)}
                    onChange={(e) => setEditing(e.target.checked ? [...editing, k] : editing.filter((x) => x !== k))} />
                  <span className="font-mono">{c.profile.replace('_', ' ')} {c.clause}</span> {c.topic}{fixed ? ' (from its type)' : ''}
                </label>
              )
            })}
          </div>
          {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setEditing(null)}>Cancel</Button>
            <Button loading={save.isPending} onClick={() => save.mutate(
              { id: documentId, tags: editing.map((k) => ({ profile: k.split('|')[0], clause: k.split('|')[1] })) },
              { onSuccess: () => setEditing(null) })}>Save tags</Button>
          </div>
        </div>
      )}
    </div>
  )
}
