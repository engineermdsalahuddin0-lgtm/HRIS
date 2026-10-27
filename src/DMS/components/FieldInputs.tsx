import { Input } from '@/components/ui'
import { Checkbox, Label, Select } from '@/components/kit'
import { CLASSIFICATION } from '../core/dms'
import type { Classification, FieldDef, Library } from '../core/types'

/** The type's own fields (licence number, authority, ...). */
export function TypeFields({ schema, values, onChange }: {
  schema: FieldDef[]; values: Record<string, string>; onChange: (v: Record<string, string>) => void
}) {
  if (schema.length === 0) return null
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {schema.map((f) => (
        <Input key={f.key} label={f.label + (f.required ? ' *' : '')} type={f.type === 'date' ? 'date' : 'text'}
          inputMode={f.type === 'number' ? 'decimal' : undefined} required={f.required}
          value={values[f.key] ?? ''} onChange={(e) => onChange({ ...values, [f.key]: e.target.value })} />
      ))}
    </div>
  )
}

export interface Access {
  classification: Classification
  scope: 'company' | 'departments'
  scope_department_ids: string[]
  restricted_role_ids: string[]
}

/** Who may read the document. Defaults come from the type, so most uploads never open this. */
export function AccessFields({ value, onChange, library }: { value: Access; onChange: (v: Access) => void; library: Library }) {
  const toggle = (list: string[], id: string, on: boolean) => (on ? [...list, id] : list.filter((x) => x !== id))
  return (
    <div className="space-y-3">
      <Select label="Classification" value={value.classification}
        hint={CLASSIFICATION[value.classification].hint}
        onChange={(e) => onChange({ ...value, classification: e.target.value as Classification })}
        options={(Object.keys(CLASSIFICATION) as Classification[]).map((k) => ({ value: k, label: CLASSIFICATION[k].label }))} />
      {value.classification === 'restricted' ? (
        <div>
          <Label required>Roles that may read it</Label>
          <div className="flex flex-wrap gap-x-4 gap-y-2">
            {library.roles.map((r) => (
              <Checkbox key={r.id} label={r.name} checked={value.restricted_role_ids.includes(r.id)}
                onChange={(on) => onChange({ ...value, restricted_role_ids: toggle(value.restricted_role_ids, r.id, on) })} />
            ))}
          </div>
        </div>
      ) : value.classification !== 'confidential' && (
        <div>
          <Select label="Who can read it" value={value.scope}
            onChange={(e) => onChange({ ...value, scope: e.target.value as Access['scope'] })}
            options={[{ value: 'company', label: 'The whole company' }, { value: 'departments', label: 'Only some departments' }]} />
          {value.scope === 'departments' && (
            <div className="mt-2 flex flex-wrap gap-x-4 gap-y-2">
              {library.all_departments.map((d) => (
                <Checkbox key={d.id} label={d.name} checked={value.scope_department_ids.includes(d.id)}
                  onChange={(on) => onChange({ ...value, scope_department_ids: toggle(value.scope_department_ids, d.id, on) })} />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
