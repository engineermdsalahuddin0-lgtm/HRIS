import { useState } from 'react'
import { Settings2 } from 'lucide-react'
import { useMutation } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { GRADE_CATEGORIES, labelOf } from '@/lib/options'
import type { Branch, Department, Designation, Grade, Office, Operation, OrgStructure } from '@/lib/hr'
import { useEmployeeOptions, useInvalidate, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Button, PageLoader } from '@/components/ui'
import { Checkbox, Modal, PageHeader, Tabs } from '@/components/kit'
import { StructureTab } from './StructureTab'
import type { DeactivateTarget } from './DeactivateDialog'
import { DeactivateDialog } from './DeactivateDialog'

type TabKey = 'departments' | 'designations' | 'grades' | 'branches' | 'offices' | 'operations'

const name = (list: { id: string; name: string }[], id: string | null) => list.find((x) => x.id === id)?.name ?? '—'

export default function OrganizationPage() {
  const ctx = useMyContext()
  const canManage = ctx.permissions.includes('org.manage')
  const canPickEmployees = ctx.permissions.includes('employees.view')
  const structure = useOrgStructure()
  const employees = useEmployeeOptions(canPickEmployees)
  const [tab, setTab] = useState<TabKey>('departments')
  const [deactivating, setDeactivating] = useState<DeactivateTarget | null>(null)
  const [opsOffice, setOpsOffice] = useState<Office | null>(null)

  if (structure.isPending) return <PageLoader />
  if (structure.isError) return <Alert>{errorMessage(structure.error)}</Alert>
  const s = structure.data

  const active = <T extends { status: string }>(xs: T[]) => xs.filter((x) => x.status === 'active')
  const toOptions = (xs: { id: string; name: string }[]) => xs.map((x) => ({ value: x.id, label: x.name }))
  const employeeOptions = (employees.data ?? []).map((e) => ({ value: e.id, label: `${e.full_name} (${e.card_id})` }))
  const headField = canPickEmployees
    ? [{ name: 'head_employee_id', label: 'Head', type: 'select' as const, options: employeeOptions }]
    : []
  const employeeName = (id: string | null) => (id ? employees.data?.find((e) => e.id === id)?.full_name ?? '—' : '—')

  const tabs: { key: TabKey; label: string; count: number }[] = [
    { key: 'departments', label: 'Departments', count: active(s.departments).length },
    { key: 'designations', label: 'Designations', count: active(s.designations).length },
    { key: 'grades', label: 'Grades', count: active(s.grades).length },
    { key: 'branches', label: 'Branches', count: active(s.branches).length },
    { key: 'offices', label: 'Offices', count: active(s.offices).length },
    { key: 'operations', label: 'Operations', count: active(s.operations).length },
  ]

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader
        title="Organization"
        description="Organization → Branch → Office. Departments are organization-wide; a designation belongs to one department and carries a grade."
      />
      <Tabs tabs={tabs} value={tab} onChange={setTab} />

      {tab === 'departments' && (
        <StructureTab<Department>
          table="departments"
          noun="Department"
          rows={s.departments}
          canManage={canManage}
          searchText={(r) => `${r.name} ${r.code ?? ''}`}
          columns={[
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Code', cell: (r) => r.code ?? '—' },
            { header: 'Designations', cell: (r) => s.designations.filter((d) => d.department_id === r.id && d.status === 'active').length },
            ...(canPickEmployees ? [{ header: 'Head', cell: (r: Department) => employeeName(r.head_employee_id) }] : []),
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            { name: 'code', label: 'Code', placeholder: 'e.g. PROD' },
            ...headField,
            { name: 'description', label: 'Description', type: 'textarea' },
          ]}
          onDeactivate={(r) => setDeactivating({ kind: 'department', id: r.id, name: r.name })}
        />
      )}

      {tab === 'designations' && (
        <StructureTab<Designation>
          table="designations"
          noun="Designation"
          rows={s.designations}
          canManage={canManage}
          searchText={(r) => `${r.name} ${name(s.departments, r.department_id)}`}
          columns={[
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Department', cell: (r) => name(s.departments, r.department_id) },
            { header: 'Grade', cell: (r) => s.grades.find((g) => g.id === r.grade_id)?.code ?? '—' },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            {
              name: 'department_id', label: 'Department', type: 'select', required: true, createOnly: true,
              options: toOptions(active(s.departments)),
            },
            {
              name: 'grade_id', label: 'Grade', type: 'select', required: true,
              options: active(s.grades).map((g) => ({ value: g.id, label: `${g.code} — ${labelOf(GRADE_CATEGORIES, g.category)}` })),
            },
            { name: 'description', label: 'Description', type: 'textarea' },
          ]}
          onDeactivate={(r) => setDeactivating({ kind: 'designation', id: r.id, name: r.name })}
        />
      )}

      {tab === 'grades' && (
        <StructureTab<Grade & { name: string }>
          table="grades"
          noun="Grade"
          rows={s.grades.map((g) => ({ ...g, name: g.code }))}
          canManage={canManage}
          searchText={(r) => `${r.code} ${r.description ?? ''}`}
          columns={[
            { header: 'Code', cell: (r) => <span className="font-mono font-medium text-slate-900">{r.code}</span> },
            { header: 'Category', cell: (r) => labelOf(GRADE_CATEGORIES, r.category) },
            { header: 'Seniority', cell: (r) => r.level },
            { header: 'Description', cell: (r) => r.description ?? '—' },
          ]}
          fields={[
            { name: 'code', label: 'Code', required: true, createOnly: true, placeholder: 'e.g. MS3', hint: 'Capital letters and digits' },
            { name: 'category', label: 'Category', type: 'select', required: true, createOnly: true, options: GRADE_CATEGORIES },
            { name: 'level', label: 'Seniority level', type: 'number', required: true, hint: 'Higher = more senior. Used to detect promotions.' },
            { name: 'description', label: 'Description', type: 'textarea' },
          ]}
        />
      )}

      {tab === 'branches' && (
        <StructureTab<Branch>
          table="branches"
          noun="Branch"
          rows={s.branches}
          canManage={canManage}
          searchText={(r) => `${r.name} ${r.code ?? ''} ${r.address ?? ''}`}
          columns={[
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Code', cell: (r) => r.code ?? '—' },
            { header: 'Offices', cell: (r) => s.offices.filter((o) => o.branch_id === r.id && o.status === 'active').length },
            { header: 'Phone', cell: (r) => r.phone ?? '—' },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true, placeholder: 'Branch or factory name' },
            { name: 'code', label: 'Code' },
            { name: 'phone', label: 'Phone', placeholder: '01XXXXXXXXX' },
            ...headField,
            { name: 'address', label: 'Address', type: 'textarea' },
          ]}
          onDeactivate={(r) => setDeactivating({ kind: 'branch', id: r.id, name: r.name })}
        />
      )}

      {tab === 'offices' && (
        <StructureTab<Office>
          table="offices"
          noun="Office"
          rows={s.offices}
          canManage={canManage}
          searchText={(r) => `${r.name} ${r.code ?? ''} ${name(s.branches, r.branch_id)}`}
          columns={[
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Branch', cell: (r) => name(s.branches, r.branch_id) },
            {
              header: 'Operations',
              cell: (r) => {
                const ops = s.officeOperations.filter((x) => x.office_id === r.id).map((x) => name(s.operations, x.operation_id))
                return ops.length ? ops.join(', ') : <span className="text-slate-400">None</span>
              },
            },
            { header: 'Layout', cell: (r) => r.layout ?? '—' },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            { name: 'branch_id', label: 'Branch', type: 'select', required: true, createOnly: true, options: toOptions(active(s.branches)) },
            { name: 'code', label: 'Code' },
            { name: 'layout', label: 'Layout', placeholder: 'e.g. Floor 2, Line A-D' },
            { name: 'address', label: 'Address', type: 'textarea' },
          ]}
          onDeactivate={(r) => setDeactivating({ kind: 'office', id: r.id, name: r.name })}
          rowActions={(r) =>
            canManage && r.status === 'active' ? (
              <button
                onClick={() => setOpsOffice(r)}
                className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
                title="Operations in this office"
                aria-label="Operations in this office"
              >
                <Settings2 className="size-4" />
              </button>
            ) : null
          }
        />
      )}

      {tab === 'operations' && (
        <StructureTab<Operation>
          table="operations"
          noun="Operation"
          rows={s.operations}
          canManage={canManage}
          searchText={(r) => r.name}
          columns={[
            { header: 'Name', cell: (r) => <span className="font-medium text-slate-900">{r.name}</span> },
            { header: 'Offices', cell: (r) => s.officeOperations.filter((x) => x.operation_id === r.id).length },
            { header: 'Description', cell: (r) => r.description ?? '—' },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true, placeholder: 'e.g. Sewing, Cutting, Finishing' },
            { name: 'description', label: 'Description', type: 'textarea' },
          ]}
        />
      )}

      <DeactivateDialog target={deactivating} structure={s} onClose={() => setDeactivating(null)} />
      <OfficeOperationsDialog office={opsOffice} structure={s} onClose={() => setOpsOffice(null)} />
    </div>
  )
}

function OfficeOperationsDialog({ office, structure, onClose }: { office: Office | null; structure: OrgStructure; onClose: () => void }) {
  const invalidate = useInvalidate()
  const current = new Set(structure.officeOperations.filter((x) => x.office_id === office?.id).map((x) => x.operation_id))
  const [selected, setSelected] = useState<Set<string> | null>(null)
  const chosen = selected ?? current
  const save = useMutation({
    mutationFn: async () => {
      const add = [...chosen].filter((id) => !current.has(id))
      const remove = [...current].filter((id) => !chosen.has(id))
      if (add.length) {
        const { error } = await supabase.from('office_operations').insert(add.map((operation_id) => ({ office_id: office!.id, operation_id })))
        if (error) throw error
      }
      if (remove.length) {
        const { error } = await supabase.from('office_operations').delete().eq('office_id', office!.id).in('operation_id', remove)
        if (error) throw error
      }
    },
    onSuccess: async () => {
      await invalidate('org-structure')
      setSelected(null)
      onClose()
    },
  })
  const ops = structure.operations.filter((o) => o.status === 'active')

  return (
    <Modal
      open={!!office}
      onClose={() => {
        setSelected(null)
        onClose()
      }}
      title="Operations in this office"
      description={office?.name}
      size="sm"
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button loading={save.isPending} onClick={() => save.mutate()}>Save</Button>
        </>
      }
    >
      <div className="space-y-3">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        {ops.length === 0 ? (
          <p className="text-sm text-slate-500">Create operations in the Operations tab first.</p>
        ) : (
          ops.map((o) => (
            <div key={o.id}>
              <Checkbox
                label={o.name}
                checked={chosen.has(o.id)}
                onChange={(v) => {
                  const next = new Set(chosen)
                  if (v) next.add(o.id)
                  else next.delete(o.id)
                  setSelected(next)
                }}
              />
            </div>
          ))
        )}
      </div>
    </Modal>
  )
}
