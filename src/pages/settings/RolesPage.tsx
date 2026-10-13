import { useEffect, useMemo, useState } from 'react'
import { Lock, Plus, ShieldCheck } from 'lucide-react'
import { useMutation } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import type { Role } from '@/lib/hr'
import { useInvalidate, useRolesData } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Textarea } from '@/components/kit'

const MODULE_LABELS: Record<string, string> = {
  organization: 'Organization',
  employees: 'Employees',
  security: 'Security',
  settings: 'Settings',
}

type FieldTicks = Record<string, { view: boolean; edit: boolean }>

export default function RolesPage() {
  const ctx = useMyContext()
  const isAdmin = ctx.role?.system_key === 'admin'
  const data = useRolesData()
  const invalidate = useInvalidate()
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [perms, setPerms] = useState<Set<string>>(new Set())
  const [fields, setFields] = useState<FieldTicks>({})
  const [saved, setSaved] = useState(false)
  const [creating, setCreating] = useState(false)

  const roles = data.data?.roles ?? []
  const selected = roles.find((r) => r.id === selectedId) ?? roles[0]

  // Load the selected role's ticks into local (editable) state.
  useEffect(() => {
    if (!data.data || !selected) return
    setPerms(new Set(data.data.rolePerms.filter((p) => p.role_id === selected.id).map((p) => p.permission_key)))
    const ticks: FieldTicks = {}
    for (const a of data.data.access.filter((x) => x.role_id === selected.id)) {
      ticks[`${a.resource}.${a.field_key}`] = { view: a.can_view, edit: a.can_edit }
    }
    setFields(ticks)
    setSaved(false)
  }, [data.data, selected?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const save = useMutation({
    mutationFn: async () => {
      const { error: e1 } = await supabase.rpc('set_role_permissions', { p_role_id: selected!.id, p_keys: [...perms] })
      if (e1) throw e1
      const payload = Object.entries(fields).map(([k, v]) => {
        const [resource, field_key] = k.split('.')
        return { resource, field_key, can_view: v.view || v.edit, can_edit: v.edit }
      })
      const { error: e2 } = await supabase.rpc('set_role_field_access', { p_role_id: selected!.id, p_fields: payload })
      if (e2) throw e2
    },
    onSuccess: async () => {
      await invalidate('roles')
      setSaved(true)
    },
  })

  const toggleStatus = useMutation({
    mutationFn: async (r: Role) => {
      const { error } = await supabase.from('roles').update({ status: r.status === 'active' ? 'inactive' : 'active' }).eq('id', r.id)
      if (error) throw error
    },
    onSuccess: () => invalidate('roles'),
  })

  const grouped = useMemo(() => {
    const m = new Map<string, NonNullable<typeof data.data>['permissions']>()
    for (const p of data.data?.permissions ?? []) m.set(p.module, [...(m.get(p.module) ?? []), p])
    return [...m.entries()]
  }, [data.data])

  const fieldGroups = useMemo(() => {
    const m = new Map<string, NonNullable<typeof data.data>['fields']>()
    for (const f of data.data?.fields ?? []) m.set(f.group_name, [...(m.get(f.group_name) ?? []), f])
    return [...m.entries()]
  }, [data.data])

  if (data.isPending) return <PageLoader />
  if (data.isError) return <Alert>{errorMessage(data.error)}</Alert>
  if (!selected) return null

  const locked = !isAdmin || selected.system_key === 'admin'
  const isEmployeeRole = selected.system_key === 'employee'

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader
        title="Roles & access"
        description="A role holds permissions and per-field visibility. Grades never grant access."
        actions={isAdmin && <Button onClick={() => setCreating(true)}><Plus className="size-4" /> New role</Button>}
      />
      {!isAdmin && <Alert tone="info">Only an Admin can create, change or assign roles. You can view them.</Alert>}

      <div className="grid gap-6 lg:grid-cols-[280px_1fr]">
        <Card className="h-fit p-2">
          <ul className="space-y-1">
            {roles.map((r) => (
              <li key={r.id}>
                <button
                  onClick={() => setSelectedId(r.id)}
                  className={cx(
                    'flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left text-sm transition',
                    r.id === selected.id ? 'bg-primary-50 text-primary-700' : 'text-slate-700 hover:bg-slate-50',
                  )}
                >
                  <ShieldCheck className="size-4 shrink-0" aria-hidden />
                  <span className="flex-1 truncate font-medium">{r.name}</span>
                  {r.is_system && <Badge>System</Badge>}
                  {r.status === 'inactive' && <Badge tone="red">Inactive</Badge>}
                </button>
              </li>
            ))}
          </ul>
        </Card>

        <div className="space-y-6">
          <Card>
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <h3 className="text-lg font-semibold text-slate-900">{selected.name}</h3>
                <p className="text-sm text-slate-500">{selected.description ?? 'No description'}</p>
              </div>
              {isAdmin && !selected.is_system && (
                <Button variant="secondary" loading={toggleStatus.isPending} onClick={() => toggleStatus.mutate(selected)}>
                  {selected.status === 'active' ? 'Deactivate role' : 'Activate role'}
                </Button>
              )}
            </div>
            {toggleStatus.isError && <div className="mt-3"><Alert>{errorMessage(toggleStatus.error)}</Alert></div>}
            {selected.system_key === 'admin' && (
              <div className="mt-4 flex items-center gap-2 rounded-xl bg-slate-50 p-3 text-sm text-slate-600">
                <Lock className="size-4" aria-hidden /> Admin always has every permission and sees every field. It cannot be changed.
              </div>
            )}
          </Card>

          {selected.system_key !== 'admin' && (
            <>
              <Card>
                <h3 className="font-semibold text-slate-900">Permissions</h3>
                <p className="mb-4 text-sm text-slate-500">What this role may do. Admin-only permissions cannot be given to other roles.</p>
                <div className="grid gap-6 md:grid-cols-2">
                  {grouped.map(([module, list]) => (
                    <div key={module}>
                      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">{MODULE_LABELS[module] ?? module}</p>
                      <div className="space-y-2">
                        {list.map((p) => (
                          <div key={p.key} className="flex items-start gap-2">
                            <Checkbox
                              label={p.description}
                              checked={perms.has(p.key)}
                              disabled={locked || p.admin_only}
                              onChange={(v) => {
                                const next = new Set(perms)
                                if (v) next.add(p.key)
                                else next.delete(p.key)
                                setPerms(next)
                              }}
                            />
                            {p.admin_only && <Badge>Admin only</Badge>}
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </Card>

              <Card>
                <h3 className="font-semibold text-slate-900">Field visibility</h3>
                <p className="mb-4 text-sm text-slate-500">
                  {isEmployeeRole
                    ? 'People always see their whole own profile. "Edit" decides which of their own fields they may change.'
                    : 'Which employee fields this role can see and edit on other people. Name, card ID, department, designation, branch and office are always visible.'}
                </p>
                <div className="overflow-x-auto">
                  <table className="w-full min-w-[420px] text-sm">
                    <thead className="text-left text-xs uppercase tracking-wide text-slate-500">
                      <tr>
                        <th className="py-2 font-medium">Field</th>
                        <th className="w-20 py-2 text-center font-medium">View</th>
                        <th className="w-20 py-2 text-center font-medium">Edit</th>
                      </tr>
                    </thead>
                    {fieldGroups.map(([group, list]) => (
                      <tbody key={group} className="divide-y divide-slate-100">
                        <tr>
                          <td colSpan={3} className="pb-1 pt-4 text-xs font-semibold text-slate-400">{group}</td>
                        </tr>
                        {list.map((f) => {
                          const key = `${f.resource}.${f.field_key}`
                          const tick = fields[key] ?? { view: false, edit: false }
                          return (
                            <tr key={key}>
                              <td className="py-2 text-slate-700">
                                {f.label} {f.sensitive && <Badge tone="red">Sensitive</Badge>}
                              </td>
                              <td className="py-2 text-center">
                                <Checkbox
                                  srOnlyLabel
                                  label={`View ${f.label}`}
                                  checked={tick.view || tick.edit}
                                  disabled={locked}
                                  onChange={(v) => setFields({ ...fields, [key]: { view: v, edit: v ? tick.edit : false } })}
                                />
                              </td>
                              <td className="py-2 text-center">
                                <Checkbox
                                  srOnlyLabel
                                  label={`Edit ${f.label}`}
                                  checked={tick.edit}
                                  disabled={locked}
                                  onChange={(v) => setFields({ ...fields, [key]: { view: tick.view || v, edit: v } })}
                                />
                              </td>
                            </tr>
                          )
                        })}
                      </tbody>
                    ))}
                  </table>
                </div>
              </Card>

              {isAdmin && (
                <div className="flex items-center justify-end gap-3">
                  {save.isError && <span className="text-sm text-red-600">{errorMessage(save.error)}</span>}
                  {saved && !save.isPending && <span className="text-sm text-green-700">Saved</span>}
                  <Button loading={save.isPending} onClick={() => save.mutate()}>Save changes</Button>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      <CreateRoleDialog
        open={creating}
        onClose={() => setCreating(false)}
        onCreated={(id) => {
          setCreating(false)
          setSelectedId(id)
        }}
      />
    </div>
  )
}

function CreateRoleDialog({ open, onClose, onCreated }: { open: boolean; onClose: () => void; onCreated: (id: string) => void }) {
  const invalidate = useInvalidate()
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const create = useMutation({
    mutationFn: async () => {
      const { data, error } = await supabase.from('roles').insert({ name: name.trim(), description: description.trim() || null }).select('id').single()
      if (error) throw error
      return data.id as string
    },
    onSuccess: async (id) => {
      await invalidate('roles')
      setName('')
      setDescription('')
      onCreated(id)
    },
  })
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="New role"
      size="sm"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button loading={create.isPending} disabled={name.trim().length < 2} onClick={() => create.mutate()}>Create</Button>
        </>
      }
    >
      <div className="space-y-4">
        {create.isError && <Alert>{errorMessage(create.error)}</Alert>}
        <Input label="Role name" name="role_name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Line Supervisor" />
        <Textarea label="Description" name="role_description" value={description} onChange={(e) => setDescription(e.target.value)} />
        <p className="text-xs text-slate-500">The new role starts with no permissions. Tick them after creating it.</p>
      </div>
    </Modal>
  )
}
