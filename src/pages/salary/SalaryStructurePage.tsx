// Salary structure: the component catalog and reusable salary templates.
import { useEffect, useMemo, useState } from 'react'
import { Layers, Pencil, Plus, Trash2, Users, Wallet, Clock } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import type { Calc, DraftLine, SalaryComponent, SalaryTemplate, TemplateLine } from '@/lib/payroll'
import {
  CALC_LABEL, formatTaka, parseMoney, previewTemplate, useCompensationStats, usePayrollAction, useSalaryConfig,
} from '@/lib/payroll'
import { useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, PageHeader, Select, StatusBadge, Table, Tabs, Textarea, td, th } from '@/components/kit'
import { StructureTab } from '../organization/StructureTab'
import { ResolvedLines } from './dialogs'

type Tab = 'templates' | 'components'

const CALC_OPTIONS = (Object.keys(CALC_LABEL) as Calc[]).map((value) => ({ value, label: CALC_LABEL[value] }))

export function StatTile({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string | number }) {
  return (
    <Card className="flex items-center gap-4 p-4">
      <span className="rounded-xl bg-primary-50 p-2.5 text-primary-600"><Icon className="size-5" /></span>
      <div>
        <p className="text-xs font-medium uppercase tracking-wide text-slate-400">{label}</p>
        <p className="text-lg font-semibold text-slate-900 tabular-nums">{value}</p>
      </div>
    </Card>
  )
}

export function CompensationStatTiles() {
  const stats = useCompensationStats()
  if (!stats.data) return null
  const s = stats.data
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <StatTile icon={Users} label="Employees with pay" value={`${s.with_pay} / ${s.active_employees}`} />
      <StatTile icon={Wallet} label="Monthly gross (current)" value={formatTaka(s.monthly_gross)} />
      <StatTile icon={Layers} label="Active templates" value={s.templates} />
      <StatTile icon={Clock} label="Pending increments" value={s.pending_increments} />
    </div>
  )
}

export default function SalaryStructurePage() {
  const context = useMyContext()
  const canEdit = context.permissions.includes('compensation.edit')
  const canView = context.permissions.includes('compensation.view')
  const config = useSalaryConfig()
  const [tab, setTab] = useState<Tab>('templates')

  if (config.isPending) return <PageLoader />
  if (config.isError) return <Alert>{errorMessage(config.error)}</Alert>
  const { components, templates, lines } = config.data

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Salary structure" description="Components (Basic, House Rent, Medical…) and templates that resolve them into monthly pay." />
      {canView && <CompensationStatTiles />}
      <Tabs<Tab> tabs={[
        { key: 'templates', label: 'Templates', count: templates.filter((t) => t.status === 'active').length },
        { key: 'components', label: 'Components', count: components.filter((c) => c.status === 'active').length },
      ]} value={tab} onChange={setTab} />
      {tab === 'templates' && <TemplatesTab templates={templates} lines={lines} components={components} canEdit={canEdit} />}
      {tab === 'components' && (
        <StructureTab<SalaryComponent>
          table="salary_components" noun="Component" rows={components} canManage={canEdit} searchText={(r) => `${r.name} ${r.code}`}
          columns={[
            { header: 'Component', cell: (r) => <><span className="font-medium text-slate-900">{r.name}</span> <span className="font-mono text-xs text-slate-400">{r.code}</span></> },
            { header: 'Kind', cell: (r) => <Badge tone={r.kind === 'earning' ? 'green' : 'red'}>{r.kind}</Badge> },
            { header: 'Calculation', cell: (r) => (r.is_basic ? 'Template / employee basic' : CALC_LABEL[r.calc]) },
            { header: 'Default', cell: (r) => (r.is_basic ? '—' : r.calc === 'fixed' ? formatTaka(r.default_value) : `${r.default_value}%`) },
            { header: 'Taxable', cell: (r) => (r.taxable ? 'Yes' : 'No') },
            { header: 'PF', cell: (r) => (r.pf_applicable ? 'Yes' : 'No') },
          ]}
          fields={[
            { name: 'name', label: 'Name', required: true },
            { name: 'code', label: 'Code', required: true, createOnly: true, placeholder: 'e.g. TIFFIN', hint: 'Capital letters, digits and _' },
            { name: 'kind', label: 'Kind', type: 'select', required: true, options: [{ value: 'earning', label: 'Earning' }, { value: 'deduction', label: 'Deduction' }] },
            { name: 'calc', label: 'Calculation', type: 'select', required: true, options: CALC_OPTIONS },
            { name: 'default_value', label: 'Default value', type: 'number', required: true, hint: 'Taka for fixed, percent (0–100) otherwise' },
            { name: 'sort_order', label: 'Order on payslip', type: 'number', required: true },
            { name: 'taxable', label: 'Taxable', type: 'checkbox' },
            { name: 'pf_applicable', label: 'Counts for provident fund', type: 'checkbox' },
          ]}
          toolbar={<span className="hidden self-center text-xs text-slate-500 md:inline">Default values are examples; review them before use.</span>}
        />
      )}
    </div>
  )
}

// ------------------------------------------------------------------ templates --
function TemplatesTab({ templates, lines, components, canEdit }: {
  templates: SalaryTemplate[]; lines: TemplateLine[]; components: SalaryComponent[]; canEdit: boolean
}) {
  const structure = useOrgStructure()
  const [editing, setEditing] = useState<SalaryTemplate | 'new' | null>(null)
  const [showInactive, setShowInactive] = useState(false)
  const componentById = useMemo(() => new Map(components.map((c) => [c.id, c])), [components])
  const gradeCode = (id: string | null) => structure.data?.grades.find((g) => g.id === id)?.code ?? '—'

  const draftLinesOf = (templateId: string): DraftLine[] =>
    lines.filter((l) => l.template_id === templateId).flatMap((l) => {
      const component = componentById.get(l.component_id)
      return component ? [{ component_id: l.component_id, code: component.code, name: component.name, kind: component.kind, calc: l.calc, value: l.value }] : []
    })
  const visible = templates.filter((t) => showInactive || t.status === 'active')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} className="accent-primary-600" />
          Show inactive
        </label>
        {canEdit && <Button onClick={() => setEditing('new')}><Plus className="size-4" />New template</Button>}
      </div>
      {visible.length === 0 ? (
        <EmptyState title="No salary templates yet">Create one for each grade or role, e.g. “Operator EM1”.</EmptyState>
      ) : (
        <Table minWidth={760} head={
          <tr><th className={th}>Template</th><th className={th}>Grade</th><th className={th}>Basic</th><th className={th}>Gross</th>
            <th className={th}>Components</th><th className={th}>Status</th><th className={th} /></tr>
        }>
          {visible.map((template) => {
            const preview = previewTemplate(template.basic_amount, draftLinesOf(template.id))
            return (
              <tr key={template.id}>
                <td className={td}><p className="font-medium text-slate-900">{template.name}</p>
                  {template.description && <p className="max-w-64 truncate text-xs text-slate-400">{template.description}</p>}</td>
                <td className={td}>{gradeCode(template.grade_id)}</td>
                <td className={`${td} tabular-nums`}>{formatTaka(template.basic_amount)}</td>
                <td className={`${td} font-medium tabular-nums`}>{preview.valid ? formatTaka(preview.gross) : '—'}</td>
                <td className={td}>{draftLinesOf(template.id).length + 1}</td>
                <td className={td}><StatusBadge status={template.status} /></td>
                <td className="px-4 py-3 text-right">
                  {canEdit && <Button variant="ghost" onClick={() => setEditing(template)} aria-label={`Edit ${template.name}`}><Pencil className="size-4" /></Button>}
                </td>
              </tr>
            )
          })}
        </Table>
      )}
      <TemplateBuilder
        open={editing !== null} onClose={() => setEditing(null)} template={editing === 'new' ? null : editing}
        initialLines={editing && editing !== 'new' ? draftLinesOf(editing.id) : null} components={components}
        grades={(structure.data?.grades ?? []).filter((g) => g.status === 'active')}
      />
    </div>
  )
}

function TemplateBuilder({ open, onClose, template, initialLines, components, grades }: {
  open: boolean; onClose: () => void; template: SalaryTemplate | null; initialLines: DraftLine[] | null
  components: SalaryComponent[]; grades: { id: string; code: string }[]
}) {
  const save = usePayrollAction<{ p_template_id: string | null; p: Record<string, unknown> }>('save_salary_template')
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [gradeId, setGradeId] = useState('')
  const [basicText, setBasicText] = useState('')
  const [active, setActive] = useState(true)
  const [draftLines, setDraftLines] = useState<DraftLine[]>([])
  const [error, setError] = useState<string | null>(null)
  const usable = components.filter((c) => c.status === 'active' && !c.is_basic)

  useEffect(() => {
    if (!open) return
    setError(null)
    setName(template?.name ?? '')
    setDescription(template?.description ?? '')
    setGradeId(template?.grade_id ?? '')
    setBasicText(template ? String(template.basic_amount) : '')
    setActive((template?.status ?? 'active') === 'active')
    // A new template starts with every active component at its default value.
    setDraftLines(initialLines ?? usable.map((c) => ({ component_id: c.id, code: c.code, name: c.name, kind: c.kind, calc: c.calc, value: c.default_value })))
  }, [open, template])

  const basic = parseMoney(basicText)
  const preview = basic ? previewTemplate(basic, draftLines) : null
  const unused = usable.filter((c) => !draftLines.some((l) => l.component_id === c.id))
  const updateLine = (index: number, patch: Partial<DraftLine>) =>
    setDraftLines((current) => current.map((l, i) => (i === index ? { ...l, ...patch } : l)))
  const addLine = (componentId: string) => {
    const component = usable.find((c) => c.id === componentId)
    if (component) setDraftLines((current) => [...current, { component_id: component.id, code: component.code, name: component.name, kind: component.kind, calc: component.calc, value: component.default_value }])
  }

  const submit = async () => {
    setError(null)
    try {
      await save.mutateAsync({ p_template_id: template?.id ?? null, p: {
        name: name.trim(), description: description.trim() || null, grade_id: gradeId || null, basic_amount: basic,
        status: active ? 'active' : 'inactive',
        lines: draftLines.map((l) => ({ component_id: l.component_id, calc: l.calc, value: l.value })),
      } })
      onClose()
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  return (
    <Modal open={open} onClose={onClose} size="xl" title={template ? 'Edit salary template' : 'New salary template'}
      description="Changing a template never changes anyone's current pay; pay keeps its own snapshot."
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button disabled={name.trim().length < 2 || !basic || !preview?.valid} loading={save.isPending} onClick={submit}>Save template</Button></>}
    >
      <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
        <div className="space-y-4">
          {error && <Alert>{error}</Alert>}
          <div className="grid gap-4 sm:grid-cols-2">
            <Input label="Name" name="template_name" value={name} onChange={(e) => setName(e.target.value)} maxLength={80} placeholder="e.g. Operator EM1" />
            <Select label="Grade (optional)" value={gradeId} onChange={(e) => setGradeId(e.target.value)} placeholder="Any grade"
              options={grades.map((g) => ({ value: g.id, label: g.code }))} />
            <Input label="Basic (৳ per month)" name="template_basic" inputMode="decimal" value={basicText} onChange={(e) => setBasicText(e.target.value)}
              error={basicText && basic === null ? 'Enter an amount with up to 2 decimals' : undefined} />
            {template && (
              <Select label="Status" value={active ? 'active' : 'inactive'} onChange={(e) => setActive(e.target.value === 'active')}
                options={[{ value: 'active', label: 'Active' }, { value: 'inactive', label: 'Inactive' }]} />
            )}
          </div>
          <Textarea label="Description" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={500} />

          <div className="space-y-2">
            <p className="text-sm font-medium text-slate-700">Components</p>
            {draftLines.map((line, index) => (
              <div key={line.component_id} className="flex flex-wrap items-end gap-2 rounded-xl bg-slate-50 p-3">
                <div className="min-w-32 flex-1">
                  <p className="text-sm font-medium text-slate-800">{line.name}</p>
                  <p className="text-xs text-slate-400">{line.kind}</p>
                </div>
                <Select aria-label={`${line.name} calculation`} value={line.calc} options={CALC_OPTIONS}
                  onChange={(e) => updateLine(index, { calc: e.target.value as Calc })} />
                <LineValueInput label={`${line.name} value`} value={line.value} onChange={(value) => updateLine(index, { value })} />
                <Button variant="ghost" aria-label={`Remove ${line.name}`} onClick={() => setDraftLines((current) => current.filter((_, i) => i !== index))}>
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))}
            {unused.length > 0 && (
              <Select aria-label="Add component" value="" placeholder="+ Add component…" onChange={(e) => addLine(e.target.value)}
                options={unused.map((c) => ({ value: c.id, label: `${c.name} (${c.code})` }))} />
            )}
          </div>
        </div>
        <div className="space-y-2">
          <p className="text-sm font-medium text-slate-700">Monthly preview</p>
          {!basic ? <p className="text-sm text-slate-500">Enter a basic to see the gross.</p>
            : preview && !preview.valid ? <Alert>{preview.error}</Alert>
              : preview && (
                <ResolvedLines salary={{
                  gross: preview.gross, total_deductions: preview.totalDeductions,
                  lines: [{ component_id: 'basic', code: 'BASIC', name: 'Basic', kind: 'earning', calc: 'fixed', rate: null, amount: basic },
                    ...preview.lines.map((l) => ({ ...l, rate: l.calc === 'fixed' ? null : l.value }))],
                }} />
              )}
        </div>
      </div>
    </Modal>
  )
}

/** Amount/percent cell that keeps what the user is typing ("12.") and reports only valid numbers. */
function LineValueInput({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  const [text, setText] = useState(String(value))
  const invalid = parseMoney(text) === null
  return (
    <input aria-label={label} aria-invalid={invalid} inputMode="decimal" value={text}
      onChange={(e) => {
        setText(e.target.value)
        const parsed = parseMoney(e.target.value)
        if (parsed !== null) onChange(parsed)
      }}
      className={`w-28 rounded-xl border bg-white px-3 py-2.5 text-right text-sm tabular-nums outline-none focus:ring-2 ${invalid ? 'border-red-400 focus:ring-red-100' : 'border-slate-300 focus:border-primary-500 focus:ring-primary-100'}`} />
  )
}
