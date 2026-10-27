import { useState } from 'react'
import { Lock, Plus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Badge, Button, Card, Input, PageLoader } from '@/components/ui'
import { Modal, Select, Switch, Table, td, th } from '@/components/kit'
import type { Sla } from '../core/helpdesk'
import { DEFAULT_SLA, PRIORITIES, PRIORITY_LABEL, hoursOf, minutesOf, slaProblems } from '../core/helpdesk'
import type { HelpdeskSetup as Setup, SetupCategory } from '../data/api'
import { useHelpdeskSetup, useSaveCategory, useSaveHelpdeskSettings } from '../data/api'

/** helpdesk.manage: categories with their handler, SLA targets (office hours), auto-close days. */
export function HelpdeskSetup() {
  const setup = useHelpdeskSetup(true)
  if (setup.isPending) return <PageLoader />
  if (setup.isError) return <Alert>{errorMessage(setup.error)}</Alert>
  return (
    <div className="space-y-6">
      <Categories setup={setup.data} />
      <SlaForm key={JSON.stringify(setup.data.settings)} initial={setup.data.settings} />
    </div>
  )
}

function Categories({ setup }: { setup: Setup }) {
  const [editing, setEditing] = useState<SetupCategory | 'new' | null>(null)
  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h3 className="font-semibold text-slate-900">Categories and handlers</h3>
          <p className="text-sm text-slate-500">A new ticket goes to its category's handler. Without one it waits for HR.</p>
        </div>
        <Button variant="secondary" onClick={() => setEditing('new')}><Plus className="size-4" /> Category</Button>
      </div>
      {setup.handlers.length === 0 && (
        <Alert tone="info">Nobody can handle tickets yet. Give a role the permission “helpdesk.handle” in Roles & access.</Alert>
      )}
      <Table minWidth={560} head={<tr><th className={th}>Category</th><th className={th}>Handler</th><th className={th}>Status</th><th className={th} aria-label="Actions" /></tr>}>
        {setup.categories.map((c) => (
          <tr key={c.id}>
            <td className={td}>
              <span className="font-medium text-slate-900">{c.name}</span>
              {c.confidential && <span className="ml-2 inline-flex items-center gap-1 text-xs text-slate-500"><Lock className="size-3" aria-hidden /> confidential</span>}
            </td>
            <td className={td}>{c.handler ?? <span className="text-slate-400">HR queue</span>}</td>
            <td className={td}><Badge tone={c.status === 'active' ? 'green' : 'slate'}>{c.status}</Badge></td>
            <td className={`${td} text-right`}><Button variant="ghost" onClick={() => setEditing(c)}>Edit</Button></td>
          </tr>
        ))}
      </Table>
      {editing && <CategoryDialog category={editing === 'new' ? null : editing} handlers={setup.handlers} onClose={() => setEditing(null)} />}
    </Card>
  )
}

function CategoryDialog({ category, handlers, onClose }: { category: SetupCategory | null; handlers: Setup['handlers']; onClose: () => void }) {
  const save = useSaveCategory()
  const [c, setC] = useState({
    name: category?.name ?? '', confidential: category?.confidential ?? false,
    handler_employee_id: category?.handler_employee_id ?? '', status: category?.status ?? 'active',
  })
  const options = handlers.filter((h) => !c.confidential || h.can_confidential)
  return (
    <Modal open onClose={onClose} size="sm" title={category ? 'Edit category' : 'New category'}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={c.name.trim().length < 2}
          onClick={() => save.mutate({ id: category?.id ?? null, p: { ...c, name: c.name.trim(), handler_employee_id: c.handler_employee_id || null } }, { onSuccess: onClose })}>
          Save
        </Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <Input label="Name" name="category_name" maxLength={80} value={c.name} onChange={(e) => setC({ ...c, name: e.target.value })} />
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="text-sm font-medium text-slate-800">Confidential</p>
            <p className="text-xs text-slate-500">Only people with helpdesk.manage (HR) can handle it.</p>
          </div>
          <Switch label="Confidential" checked={c.confidential}
            onChange={(v) => setC({ ...c, confidential: v, handler_employee_id: v && !handlers.find((h) => h.employee_id === c.handler_employee_id)?.can_confidential ? '' : c.handler_employee_id })} />
        </div>
        <Select label="Handler" name="category_handler" value={c.handler_employee_id} placeholder="HR queue (no handler)"
          onChange={(e) => setC({ ...c, handler_employee_id: e.target.value })}
          options={options.map((h) => ({ value: h.employee_id, label: `${h.full_name} · ${h.card_id}` }))} />
        <Select label="Status" name="category_status" value={c.status} onChange={(e) => setC({ ...c, status: e.target.value as 'active' | 'inactive' })}
          options={[{ value: 'active', label: 'Active' }, { value: 'inactive', label: 'Inactive (hidden from new tickets)' }]} />
      </div>
    </Modal>
  )
}

function SlaForm({ initial }: { initial: Setup['settings'] }) {
  const save = useSaveHelpdeskSettings()
  const [sla, setSla] = useState<Sla>(initial.sla)
  const [days, setDays] = useState(initial.auto_close_days)
  const problems = slaProblems(sla, days)
  const setHours = (p: keyof Sla, k: 'response' | 'resolution', hours: string) =>
    setSla({ ...sla, [p]: { ...sla[p], [k]: minutesOf(Number(hours)) } })

  return (
    <Card className="space-y-4">
      <div>
        <h3 className="font-semibold text-slate-900">SLA targets</h3>
        <p className="text-sm text-slate-500">Office hours only: evenings, weekly off days and holidays do not count. The clock stops while waiting for the employee.</p>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[420px] text-sm">
          <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
            <tr><th className="py-2 font-medium">Priority</th><th className="py-2 font-medium">First response (h)</th><th className="py-2 font-medium">Resolution (h)</th></tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {PRIORITIES.slice().reverse().map((p) => (
              <tr key={p}>
                <td className="py-2"><Badge tone={PRIORITY_LABEL[p].tone}>{PRIORITY_LABEL[p].label}</Badge></td>
                {(['response', 'resolution'] as const).map((k) => (
                  <td key={k} className="py-2 pr-4">
                    <input type="number" min={0.25} max={720} step={0.25} aria-label={`${PRIORITY_LABEL[p].label} ${k} hours`}
                      value={hoursOf(sla[p][k])} onChange={(e) => setHours(p, k, e.target.value)}
                      className="w-28 rounded-lg border border-slate-300 px-2 py-1.5" />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="max-w-xs">
        <Input label="Auto-close resolved tickets after (working days)" name="auto_close_days" type="number" min={1} max={30}
          value={days} onChange={(e) => setDays(Number(e.target.value))} />
      </div>
      {problems.length > 0 && <Alert>{problems[0]}</Alert>}
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <div className="flex flex-wrap items-center justify-end gap-3">
        {save.isSuccess && <span className="text-sm text-green-700">Saved. New tickets use these targets.</span>}
        <Button variant="secondary" onClick={() => { setSla(DEFAULT_SLA); setDays(3) }}>Default values</Button>
        <Button loading={save.isPending} disabled={problems.length > 0} onClick={() => save.mutate({ sla, auto_close_days: days })}>Save SLA</Button>
      </div>
    </Card>
  )
}
