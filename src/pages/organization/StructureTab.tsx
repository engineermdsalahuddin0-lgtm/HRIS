import type { ReactNode } from 'react'
import { useMemo, useState } from 'react'
import { Pencil, Plus, Search } from 'lucide-react'
import { Alert, Button, EmptyState, Input } from '@/components/ui'
import type { Option } from '@/components/kit'
import { Modal, Select, StatusBadge, Switch, Table, Textarea, td, th } from '@/components/kit'
import { errorMessage } from '@/lib/identity'
import { useSaveStructure } from '@/lib/hr'

export interface FieldSpec {
  name: string
  label: string
  type?: 'text' | 'textarea' | 'select' | 'number'
  options?: Option[]
  required?: boolean
  /** Not editable after creation (e.g. an office's branch). */
  createOnly?: boolean
  placeholder?: string
  hint?: string
}

export interface Column<T> {
  header: string
  cell: (row: T) => ReactNode
  className?: string
}

interface Row {
  id: string
  status: 'active' | 'inactive'
}

export function StructureTab<T extends Row>({
  table,
  noun,
  rows,
  columns,
  fields,
  canManage,
  searchText,
  onDeactivate,
  rowActions,
  toolbar,
}: {
  table: string
  noun: string
  rows: T[]
  columns: Column<T>[]
  fields: FieldSpec[]
  canManage: boolean
  searchText: (row: T) => string
  /** Custom deactivation flow; when absent the status flips directly. */
  onDeactivate?: (row: T) => void
  rowActions?: (row: T) => ReactNode
  toolbar?: ReactNode
}) {
  const save = useSaveStructure(table)
  const [query, setQuery] = useState('')
  const [showInactive, setShowInactive] = useState(false)
  const [editing, setEditing] = useState<T | 'new' | null>(null)
  const [values, setValues] = useState<Record<string, string>>({})
  const [formError, setFormError] = useState<string | null>(null)
  const [rowError, setRowError] = useState<string | null>(null)

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase()
    return rows.filter((r) => (showInactive || r.status === 'active') && (!q || searchText(r).toLowerCase().includes(q)))
  }, [rows, query, showInactive, searchText])

  const open = (row: T | 'new') => {
    setFormError(null)
    const init: Record<string, string> = {}
    for (const f of fields) {
      const v = row === 'new' ? '' : (row as unknown as Record<string, unknown>)[f.name]
      init[f.name] = v === null || v === undefined ? '' : String(v)
    }
    setValues(init)
    setEditing(row)
  }

  const submit = async () => {
    for (const f of fields) {
      if (f.required && !values[f.name]?.trim()) {
        setFormError(`${f.label} is required`)
        return
      }
    }
    const isNew = editing === 'new'
    const payload: Record<string, unknown> = {}
    for (const f of fields) {
      if (!isNew && f.createOnly) continue
      const v = values[f.name]?.trim() ?? ''
      payload[f.name] = v === '' ? null : f.type === 'number' ? Number(v) : v
    }
    try {
      await save.mutateAsync({ id: isNew ? undefined : (editing as T).id, values: payload })
      setEditing(null)
    } catch (e) {
      setFormError(errorMessage(e))
    }
  }

  const toggle = async (row: T) => {
    setRowError(null)
    if (row.status === 'active' && onDeactivate) {
      onDeactivate(row)
      return
    }
    try {
      await save.mutateAsync({ id: row.id, values: { status: row.status === 'active' ? 'inactive' : 'active' } })
    } catch (e) {
      setRowError(errorMessage(e))
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-56 flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={`Search ${noun.toLowerCase()}s`}
            aria-label={`Search ${noun.toLowerCase()}s`}
            className="w-full rounded-xl border border-slate-300 bg-white py-2 pl-9 pr-3 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
          />
        </div>
        <label className="flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} className="accent-primary-600" />
          Show inactive
        </label>
        <div className="ml-auto flex gap-2">
          {toolbar}
          {canManage && (
            <Button onClick={() => open('new')}>
              <Plus className="size-4" /> Add {noun.toLowerCase()}
            </Button>
          )}
        </div>
      </div>

      {rowError && <Alert>{rowError}</Alert>}

      {visible.length === 0 ? (
        <EmptyState title={`No ${noun.toLowerCase()}s yet`}>
          {canManage ? `Use "Add ${noun.toLowerCase()}" to create the first one.` : 'Nothing to show.'}
        </EmptyState>
      ) : (
        <Table
          head={
            <tr>
              {columns.map((c) => (
                <th key={c.header} className={th}>{c.header}</th>
              ))}
              <th className={th}>Status</th>
              <th className={th} />
            </tr>
          }
        >
          {visible.map((r) => (
            <tr key={r.id} className={r.status === 'inactive' ? 'bg-slate-50/60' : undefined}>
              {columns.map((c) => (
                <td key={c.header} className={c.className ?? td}>{c.cell(r)}</td>
              ))}
              <td className={td}>
                <div className="flex items-center gap-2">
                  {canManage && (
                    <Switch
                      checked={r.status === 'active'}
                      onChange={() => toggle(r)}
                      label={`${r.status === 'active' ? 'Deactivate' : 'Activate'} ${noun.toLowerCase()}`}
                    />
                  )}
                  <StatusBadge status={r.status} />
                </div>
              </td>
              <td className="px-4 py-3 text-right">
                <div className="flex justify-end gap-1">
                  {rowActions?.(r)}
                  {canManage && (
                    <button
                      onClick={() => open(r)}
                      className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
                      aria-label={`Edit ${noun.toLowerCase()}`}
                      title="Edit"
                    >
                      <Pencil className="size-4" />
                    </button>
                  )}
                </div>
              </td>
            </tr>
          ))}
        </Table>
      )}

      <Modal
        open={editing !== null}
        onClose={() => setEditing(null)}
        title={editing === 'new' ? `Add ${noun.toLowerCase()}` : `Edit ${noun.toLowerCase()}`}
        footer={
          <>
            <Button variant="secondary" onClick={() => setEditing(null)}>Cancel</Button>
            <Button loading={save.isPending} onClick={submit}>Save</Button>
          </>
        }
      >
        <form
          className="grid gap-4 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault()
            submit()
          }}
        >
          {formError && <div className="sm:col-span-2"><Alert>{formError}</Alert></div>}
          {fields.map((f) => {
            const disabled = editing !== 'new' && f.createOnly
            const common = {
              name: f.name,
              value: values[f.name] ?? '',
              disabled,
              placeholder: f.placeholder,
            }
            if (f.type === 'select') {
              return (
                <Select
                  key={f.name}
                  {...common}
                  label={f.label}
                  required={f.required}
                  hint={disabled ? 'Cannot be changed after creation' : f.hint}
                  options={f.options ?? []}
                  placeholder="Select…"
                  onChange={(e) => setValues((v) => ({ ...v, [f.name]: e.target.value }))}
                />
              )
            }
            if (f.type === 'textarea') {
              return (
                <Textarea
                  key={f.name}
                  {...common}
                  label={f.label}
                  className="sm:col-span-2"
                  onChange={(e) => setValues((v) => ({ ...v, [f.name]: e.target.value }))}
                />
              )
            }
            return (
              <Input
                key={f.name}
                {...common}
                label={f.required ? `${f.label} *` : f.label}
                type={f.type === 'number' ? 'number' : 'text'}
                hint={disabled ? 'Cannot be changed after creation' : f.hint}
                onChange={(e) => setValues((v) => ({ ...v, [f.name]: e.target.value }))}
              />
            )
          })}
          <button type="submit" hidden />
        </form>
      </Modal>
    </div>
  )
}
