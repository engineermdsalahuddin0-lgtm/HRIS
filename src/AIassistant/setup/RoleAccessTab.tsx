import { useState } from 'react'
import { Lock } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, cx } from '@/components/ui'
import { Modal, Switch } from '@/components/kit'
import type { ServerRole, ServerSetup } from '../data/api'
import { useSaveMatrix } from '../data/api'

const GROUPS = [
  { key: 'updates', label: 'Updates', hint: 'Dashboard numbers and statuses, never amounts' },
  { key: 'knowledge', label: 'Knowledge', hint: 'The app guide and what the uploaded resources are about' },
] as const

type Draft = Record<string, { enabled: boolean; daily_limit: number | null; ticks: Record<string, boolean> }>

const draftOf = (roles: ServerRole[]): Draft =>
  Object.fromEntries(roles.map((r) => [r.id, { enabled: r.enabled, daily_limit: r.daily_limit, ticks: { ...r.ticks } }]))

/**
 * The role matrix (every company role, custom roles too). A tick only works when the role already
 * holds a permission behind the topic; sensitive ticks for HR Manager are Admin-only.
 */
export function RoleAccessTab({ setup }: { setup: ServerSetup }) {
  const save = useSaveMatrix()
  const [draft, setDraft] = useState<Draft>(() => draftOf(setup.roles))
  const [confirming, setConfirming] = useState(false)
  const original = draftOf(setup.roles)
  const changes = setup.roles.flatMap((r) => {
    const lines = setup.topics.filter((t) => !!original[r.id].ticks[t.key] !== !!draft[r.id].ticks[t.key])
      .map((t) => `${draft[r.id].ticks[t.key] ? '+' : '−'} ${t.label}`)
    if (original[r.id].enabled !== draft[r.id].enabled) lines.push(draft[r.id].enabled ? '+ assistant on' : '− assistant off')
    if (original[r.id].daily_limit !== draft[r.id].daily_limit) lines.push(`limit ${draft[r.id].daily_limit ?? '∞'} per day`)
    return lines.length ? [{ role: r.name, lines }] : []
  })

  const update = (roleId: string, patch: Partial<Draft[string]>) => setDraft({ ...draft, [roleId]: { ...draft[roleId], ...patch } })
  const doSave = () => save.mutate(
    setup.roles.filter((r) => r.system_key !== 'admin').map((r) => ({ role_id: r.id, ...draft[r.id] })),
    { onSuccess: () => setConfirming(false) },
  )

  return (
    <div className="space-y-4">
      <Card className="p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-sm" style={{ minWidth: 260 + setup.roles.length * 112 }}>
            <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 text-left font-medium">What the assistant may show</th>
                {setup.roles.map((r) => (
                  <th key={r.id} className="w-28 px-2 py-3 text-center font-medium">
                    {r.name} {r.system_key === 'admin' && <Lock className="inline size-3" aria-label="fixed" />}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              <tr>
                <td className="px-4 py-3 font-medium text-slate-800">Assistant on for this role</td>
                {setup.roles.map((r) => (
                  <td key={r.id} className="px-2 py-3"><div className="flex justify-center">
                    <Switch label={`Assistant on for ${r.name}`} checked={r.system_key === 'admin' || draft[r.id].enabled} disabled={r.system_key === 'admin'}
                      onChange={(v) => update(r.id, { enabled: v })} />
                  </div></td>
                ))}
              </tr>
            </tbody>
            {GROUPS.map((g) => (
              <tbody key={g.key} className="divide-y divide-slate-100">
                <tr>
                  <td colSpan={setup.roles.length + 1} className="bg-slate-50/60 px-4 pb-1 pt-4 text-xs font-semibold text-slate-500">
                    {g.label} <span className="font-normal text-slate-400">· {g.hint}</span>
                  </td>
                </tr>
                {setup.topics.filter((t) => t.group === g.key).map((t) => (
                  <tr key={t.key}>
                    <td className="px-4 py-2.5">
                      <p className="text-slate-800">{t.label} {t.sensitive && <span className="text-xs text-red-600">· sensitive</span>}</p>
                      <p className="text-xs text-slate-500">{t.hint}</p>
                    </td>
                    {setup.roles.map((r) => {
                      const isAdmin = r.system_key === 'admin'
                      const usable = r.usable[t.key]
                      const hrLocked = t.sensitive && r.system_key === 'hr_manager' && !setup.is_admin
                      const editable = !isAdmin && usable && !hrLocked && draft[r.id].enabled
                      const checked = isAdmin || (usable && !!draft[r.id].ticks[t.key])
                      const why = isAdmin ? 'Admin always sees everything.'
                        : !usable ? `${r.name} has no ${t.needs_any_of.join(' or ')}. Change it in Roles & access first.`
                        : hrLocked ? 'Only an Admin can change this for HR Manager.' : undefined
                      return (
                        <td key={r.id} className="px-2 py-2.5 text-center" title={why}>
                          <input type="checkbox" aria-label={`${t.label} for ${r.name}`} checked={checked} disabled={!editable}
                            onChange={(e) => update(r.id, { ticks: { ...draft[r.id].ticks, [t.key]: e.target.checked } })}
                            className={cx('size-4 rounded accent-primary-600', !editable && 'cursor-not-allowed opacity-40')} />
                          {!usable && <span className="block text-[10px] text-slate-400">no permission</span>}
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
                {setup.roles.map((r) => (
                  <td key={r.id} className="px-2 py-3 text-center">
                    <input type="number" min={1} max={500} aria-label={`Questions per day for ${r.name}`} placeholder="∞" disabled={r.system_key === 'admin'}
                      value={draft[r.id].daily_limit ?? ''}
                      onChange={(e) => update(r.id, { daily_limit: e.target.value === '' ? null : Math.max(1, Math.min(500, Math.round(Number(e.target.value)))) })}
                      className="w-20 rounded-lg border border-slate-300 px-2 py-1 text-center text-sm disabled:bg-slate-50" />
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      </Card>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <div className="flex flex-wrap items-center justify-end gap-3">
        {save.isSuccess && changes.length === 0 && <span className="text-sm text-green-700">Saved. It applies on everyone's next question.</span>}
        <Button variant="secondary" disabled={changes.length === 0} onClick={() => setDraft(draftOf(setup.roles))}>Undo changes</Button>
        <Button disabled={changes.length === 0} onClick={() => setConfirming(true)}>Save role access</Button>
      </div>
      <Modal open={confirming} onClose={() => setConfirming(false)} title="Save these changes?" size="sm"
        footer={<><Button variant="secondary" onClick={() => setConfirming(false)}>Cancel</Button><Button loading={save.isPending} onClick={doSave}>Save</Button></>}>
        <ul className="space-y-3 text-sm">
          {changes.map((c) => (
            <li key={c.role}>
              <p className="font-medium text-slate-900">{c.role}</p>
              {c.lines.map((l) => <p key={l} className={l.startsWith('−') ? 'text-red-600' : 'text-green-700'}>{l}</p>)}
            </li>
          ))}
        </ul>
      </Modal>
    </div>
  )
}
