import { useState } from 'react'
import { Lock } from 'lucide-react'
import { Button, Card, cx } from '@/components/ui'
import { Modal, Switch } from '@/components/kit'
import { canEditTick, matrixChanges, missingPermission } from '../core/access'
import { ROLES, TOPICS, roleLabel } from '../core/catalog'
import type { AssistantSetup, RoleKey, TopicGroup } from '../core/types'
import { useAssistantStore } from '../data/store'

const GROUPS: { key: TopicGroup; label: string; hint: string }[] = [
  { key: 'updates', label: 'Updates', hint: 'Dashboard numbers and statuses, never amounts' },
  { key: 'knowledge', label: 'Knowledge', hint: 'What the uploaded resources are about' },
]

type Draft = Pick<AssistantSetup, 'matrix' | 'roleEnabled' | 'dailyLimit'>

/**
 * The role matrix, like Roles & access: a tick only works when the role already has the
 * permission behind it, so the assistant can never show more than the role may see.
 */
export function RoleAccessTab({ editor }: { editor: RoleKey }) {
  const setup = useAssistantStore((s) => s.setup)
  const update = useAssistantStore((s) => s.update)
  const [draft, setDraft] = useState<Draft>({ matrix: setup.matrix, roleEnabled: setup.roleEnabled, dailyLimit: setup.dailyLimit })
  const [confirming, setConfirming] = useState(false)
  const [saved, setSaved] = useState(false)
  const changes = matrixChanges(setup.matrix, draft.matrix)
  const dirty = JSON.stringify(draft) !== JSON.stringify({ matrix: setup.matrix, roleEnabled: setup.roleEnabled, dailyLimit: setup.dailyLimit })

  const tick = (role: RoleKey, key: string, v: boolean) => {
    setDraft({ ...draft, matrix: { ...draft.matrix, [role]: { ...draft.matrix[role], [key]: v } } })
    setSaved(false)
  }
  const save = () => { update(draft); setConfirming(false); setSaved(true) }

  return (
    <div className="space-y-4">
      <Card className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 text-left font-medium">What the assistant may show</th>
                {ROLES.map((r) => (
                  <th key={r.key} className="w-28 px-2 py-3 text-center font-medium">
                    {r.label} {r.key === 'admin' && <Lock className="inline size-3" aria-label="fixed" />}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              <tr className="bg-white">
                <td className="px-4 py-3 font-medium text-slate-800">Assistant on for this role</td>
                {ROLES.map((r) => (
                  <td key={r.key} className="px-2 py-3 text-center">
                    <div className="flex justify-center">
                      <Switch label={`Assistant on for ${r.label}`} checked={draft.roleEnabled[r.key]} disabled={r.key === 'admin'}
                        onChange={(v) => { setDraft({ ...draft, roleEnabled: { ...draft.roleEnabled, [r.key]: v } }); setSaved(false) }} />
                    </div>
                  </td>
                ))}
              </tr>
            </tbody>
            {GROUPS.map((g) => (
              <tbody key={g.key} className="divide-y divide-slate-100">
                <tr>
                  <td colSpan={ROLES.length + 1} className="bg-slate-50/60 px-4 pb-1 pt-4 text-xs font-semibold text-slate-500">
                    {g.label} <span className="font-normal text-slate-400">· {g.hint}</span>
                  </td>
                </tr>
                {TOPICS.filter((t) => t.group === g.key).map((t) => (
                  <tr key={t.key}>
                    <td className="px-4 py-2.5">
                      <p className="text-slate-800">{t.label} {t.sensitive && <span className="text-xs text-red-600">· sensitive</span>}</p>
                      <p className="text-xs text-slate-500">{t.hint}</p>
                    </td>
                    {ROLES.map((r) => {
                      const missing = missingPermission(r.key, t)
                      const editable = canEditTick(editor, r.key, t) && !missing && draft.roleEnabled[r.key]
                      const checked = r.key === 'admin' || (!missing && !!draft.matrix[r.key]?.[t.key])
                      const why = missing ? `${r.label} has no ${missing}. Change it in Roles & access first.`
                        : r.key === 'admin' ? 'Admin always sees everything.'
                        : !canEditTick(editor, r.key, t) ? 'Only an Admin can change this for HR Manager.' : undefined
                      return (
                        <td key={r.key} className="px-2 py-2.5 text-center" title={why}>
                          <input type="checkbox" aria-label={`${t.label} for ${r.label}`} checked={checked} disabled={!editable}
                            onChange={(e) => tick(r.key, t.key, e.target.checked)}
                            className={cx('size-4 rounded accent-primary-600', !editable && 'cursor-not-allowed opacity-40')} />
                          {missing && <span className="block text-[10px] text-slate-400">no permission</span>}
                        </td>
                      )
                    })}
                  </tr>
                ))}
              </tbody>
            ))}
            <tbody>
              <tr className="border-t border-slate-200">
                <td className="px-4 py-3">
                  <p className="font-medium text-slate-800">Questions per day</p>
                  <p className="text-xs text-slate-500">Empty = no limit. Keeps the AI bill under control.</p>
                </td>
                {ROLES.map((r) => (
                  <td key={r.key} className="px-2 py-3 text-center">
                    <input type="number" min={1} max={500} aria-label={`Questions per day for ${r.label}`} placeholder="∞"
                      value={draft.dailyLimit[r.key] ?? ''}
                      onChange={(e) => {
                        const n = e.target.value === '' ? null : Math.max(1, Math.min(500, Math.round(Number(e.target.value))))
                        setDraft({ ...draft, dailyLimit: { ...draft.dailyLimit, [r.key]: n } }); setSaved(false)
                      }}
                      className="w-20 rounded-lg border border-slate-300 px-2 py-1 text-center text-sm" />
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      </Card>

      <div className="flex flex-wrap items-center justify-end gap-3">
        {saved && <span className="text-sm text-green-700">Saved. It applies on everyone's next question.</span>}
        <Button variant="secondary" disabled={!dirty} onClick={() => setDraft({ matrix: setup.matrix, roleEnabled: setup.roleEnabled, dailyLimit: setup.dailyLimit })}>
          Undo changes
        </Button>
        <Button disabled={!dirty} onClick={() => (Object.keys(changes).length ? setConfirming(true) : save())}>Save role access</Button>
      </div>

      <Modal open={confirming} onClose={() => setConfirming(false)} title="Save these changes?" size="sm"
        footer={<><Button variant="secondary" onClick={() => setConfirming(false)}>Cancel</Button><Button onClick={save}>Save</Button></>}>
        <ul className="space-y-3 text-sm">
          {(Object.entries(changes) as [RoleKey, string[]][]).map(([role, lines]) => (
            <li key={role}>
              <p className="font-medium text-slate-900">{roleLabel(role)}</p>
              {lines.map((l) => <p key={l} className={l.startsWith('+') ? 'text-green-700' : 'text-red-600'}>{l}</p>)}
            </li>
          ))}
        </ul>
      </Modal>
    </div>
  )
}
