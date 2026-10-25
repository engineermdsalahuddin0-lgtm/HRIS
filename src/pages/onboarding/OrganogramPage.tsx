// Department organogram: a tree of positions per department, driven by the headcount budget
// and the grade slots; updates as people join, leave or move and as hiring moves on.
import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Building2, Lock, Plus, Users } from 'lucide-react'
import type { ChartGrade, ChartPosition, PositionState } from '@/onboarding-process/core/organogram'
import { STATE_META, STATE_ORDER, budgetError, budgetSentence, chartLevels, stateCounts } from '@/onboarding-process/core/organogram'
import type { DepartmentChart, OrgGrade } from '@/lib/organogram'
import { useDepartmentBudgets, useDepartmentChart, useOrganogramAction, useOrganogramGrades } from '@/lib/organogram'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, Spinner, cx } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Tabs, Textarea, td, th } from '@/components/kit'
import { OrganogramDemo } from './OrganogramDemo'

type Tab = 'chart' | 'budget' | 'grades' | 'demo'

function PositionCard({ p, grade, onOpen }: { p: ChartPosition; grade: ChartGrade; onOpen: () => void }) {
  const meta = STATE_META[p.state]
  return (
    <button type="button" onClick={onOpen}
      className={cx('relative w-40 rounded-xl border-2 p-2.5 text-left text-xs shadow-sm transition hover:shadow-md', meta.card)}
      aria-label={`${grade.name} ${p.kind === 'extra' ? 'extra' : `slot ${p.slot_no}`}: ${p.employee?.full_name ?? meta.label}`}>
      <div className="flex items-center justify-between gap-1">
        <span className="font-semibold text-slate-700">{grade.code}{p.kind === 'planned' ? ` · ${p.slot_no}` : ''}</span>
        {p.state === 'blocked' ? <Lock className="size-3.5 text-slate-500" /> : <span className={cx('rounded-full px-1.5 py-0.5 text-[10px] font-medium', meta.badge)}>{meta.label}</span>}
      </div>
      {p.employee ? (
        <>
          <p className="mt-1 truncate text-sm font-medium text-slate-900">{p.employee.full_name}</p>
          <p className="truncate text-[11px] text-slate-500">{p.employee.designation} · {p.employee.card_id}</p>
        </>
      ) : p.state === 'in_recruitment' && p.recruitment ? (
        <>
          <p className="mt-1 text-sm font-medium text-sky-900">{p.recruitment.stage}</p>
          <p className="text-[11px] text-sky-700">{p.recruitment.candidates} candidate{p.recruitment.candidates === 1 ? '' : 's'}</p>
        </>
      ) : <p className="mt-1 text-sm font-medium">{p.state === 'blocked' ? 'Frozen' : 'Vacant'}</p>}
    </button>
  )
}

function PositionDialog({ p, grade, chart, onClose }: { p: ChartPosition; grade: ChartGrade; chart: DepartmentChart; onClose: () => void }) {
  const hold = useOrganogramAction<{ p_position_id: string; p_state: 'vacant' | 'blocked' }>('set_position_hold')
  const canToggle = chart.can.toggle && !p.employee && p.kind === 'planned'
  return (
    <Modal open onClose={onClose} title={`${grade.name} · ${p.kind === 'extra' ? 'extra position' : `slot ${p.slot_no}`}`}
      description={<span className={cx('rounded-full px-2 py-0.5 text-xs font-medium', STATE_META[p.state].badge)}>{STATE_META[p.state].label}</span>}
      footer={<>
        {canToggle && (
          <Button variant="secondary" className="mr-auto" loading={hold.isPending}
            onClick={() => hold.mutate({ p_position_id: p.id, p_state: p.state === 'blocked' ? 'vacant' : 'blocked' }, { onSuccess: onClose })}>
            {p.state === 'blocked' ? 'Open for hiring (vacant)' : 'Block this slot'}</Button>
        )}
        <Button onClick={onClose}>Close</Button>
      </>}>
      <div className="space-y-3 text-sm">
        {hold.isError && <Alert>{errorMessage(hold.error)}</Alert>}
        {p.employee ? (
          <p><Link to={`/employees/${p.employee.id}`} className="font-medium text-primary-700 hover:underline">{p.employee.full_name}</Link>
            {' '}· {p.employee.designation} · {p.employee.card_id} · joined {formatDate(p.employee.join_date)}</p>
        ) : p.state === 'blocked' ? <p>Frozen: nobody can be hired against this slot until it is opened again.</p>
          : p.recruitment ? (
            <p>Being recruited: {p.recruitment.stage}, {p.recruitment.candidates} candidate(s).{' '}
              {p.recruitment.post_id ? <Link to={`/job-posts/${p.recruitment.post_id}`} className="text-primary-700 hover:underline">Open the job post</Link>
                : <Link to="/vacancies" className="text-primary-700 hover:underline">Open vacancies</Link>}</p>
          ) : <p>Budgeted and open to hire. Raise a vacancy to start recruiting.</p>}
        {p.kind === 'extra' && <Alert tone="info">Above the {grade.planned} planned {grade.name} slot(s). It goes away when this person leaves or moves into a planned slot.</Alert>}
      </div>
    </Modal>
  )
}

export function Chart({ chart }: { chart: DepartmentChart }) {
  const [open, setOpen] = useState<{ p: ChartPosition; g: ChartGrade } | null>(null)
  const levels = chartLevels(chart.grades)
  const counts = stateCounts(chart.grades)
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {STATE_ORDER.map((s: PositionState) => (
          <span key={s} className={cx('inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-medium', STATE_META[s].badge)}>
            {STATE_META[s].label} <span className="tabular-nums">{counts[s]}</span></span>
        ))}
      </div>
      {chart.unmapped.length > 0 && (
        <Alert tone="info">{chart.unmapped.length} employee(s) have a designation without an organogram grade and are not on the chart:{' '}
          {chart.unmapped.slice(0, 5).map((e) => `${e.full_name} (${e.designation ?? '—'})`).join(', ')}. Map designations on the Grades tab.</Alert>
      )}
      {levels.length === 0 ? <EmptyState title="No positions yet">Set the budget and the slots per grade on the Budget tab.</EmptyState> : (
        <div className="overflow-x-auto rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200">
          <div className="mx-auto flex min-w-max flex-col items-center">
            <div className="rounded-xl bg-slate-900 px-5 py-3 text-center text-white shadow">
              <p className="flex items-center justify-center gap-2 font-semibold"><Building2 className="size-4" />{chart.department.name}</p>
              <p className="text-xs text-slate-300">{chart.department.head ? `Head: ${chart.department.head.full_name}` : budgetSentence(chart.counts)}</p>
            </div>
            {levels.map((g) => (
              <div key={g.id} className="flex flex-col items-center">
                <div className="h-6 w-px bg-slate-300" />
                <div className="relative rounded-2xl border border-slate-200 px-4 pb-4 pt-6">
                  <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-white px-3 py-0.5 text-xs font-semibold text-slate-600 ring-1 ring-slate-200">
                    {g.name} · {g.positions.filter((p) => p.employee).length}/{g.planned}</span>
                  <div className="flex max-w-5xl flex-wrap justify-center gap-3">
                    {g.positions.map((p) => <PositionCard key={p.id} p={p} grade={g} onOpen={() => setOpen({ p, g })} />)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      {open && <PositionDialog p={open.p} grade={open.g} chart={chart} onClose={() => setOpen(null)} />}
    </div>
  )
}

function BudgetForm({ chart, grades }: { chart: DepartmentChart; grades: OrgGrade[] }) {
  const save = useOrganogramAction<{ p_department_id: string; p: Record<string, unknown> }>('save_department_budget')
  const holds = useOrganogramAction<{ p_department_id: string; p_state: 'vacant' | 'blocked'; p_grade_id: string | null }, number>('set_department_holds')
  const active = grades.filter((g) => g.status === 'active').sort((a, b) => a.rank - b.rank)
  const [approved, setApproved] = useState(String(chart.budget?.approved_headcount ?? ''))
  const [after, setAfter] = useState<'vacant' | 'blocked'>(chart.budget?.after_separation ?? 'vacant')
  const [note, setNote] = useState(chart.budget?.note ?? '')
  const [slots, setSlots] = useState<Record<string, string>>(() =>
    Object.fromEntries(active.map((g) => [g.id, String(chart.grades.find((x) => x.id === g.id)?.planned ?? 0)])))
  const values = active.map((g) => Number(slots[g.id] || 0))
  const total = values.reduce((a, b) => a + b, 0)
  const problem = approved === '' ? 'Enter the approved headcount' : budgetError(Number(approved), values, chart.counts)
  if (!chart.can.budget) return <Alert tone="info">Only the Admin (headcount permission) sets the budget. {budgetSentence(chart.counts)}</Alert>
  return (
    <Card className="space-y-4">
      {(save.isError || holds.isError) && <Alert>{errorMessage(save.error ?? holds.error)}</Alert>}
      {save.isSuccess && <Alert tone="success">Saved. The chart is updated.</Alert>}
      <div className="grid gap-3 sm:grid-cols-3">
        <Input label="Approved headcount budget" inputMode="numeric" value={approved} onChange={(e) => setApproved(e.target.value.replace(/\D/g, ''))}
          hint={`${chart.counts.filled} filled · ${chart.counts.offers_in_process} offer(s) in process`} />
        <Select label="When someone leaves, the position becomes" value={after} onChange={(e) => setAfter(e.target.value as 'vacant' | 'blocked')}
          options={[{ value: 'vacant', label: 'Vacant (replace; a replacement is drafted)' }, { value: 'blocked', label: 'Blocked (frozen until opened)' }]} />
        <Textarea label="Note (optional)" rows={1} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
      </div>
      <Table minWidth={480} head={<tr><th className={th}>Grade</th><th className={th}>Planned slots</th><th className={th}>Now</th><th className={th} /></tr>}>
        {active.map((g) => {
          const row = chart.grades.find((x) => x.id === g.id)
          const filled = row?.positions.filter((p) => p.employee).length ?? 0
          const blocked = row?.positions.filter((p) => p.state === 'blocked').length ?? 0
          const open = row?.positions.filter((p) => p.state === 'vacant' || p.state === 'in_recruitment').length ?? 0
          return (
            <tr key={g.id}>
              <td className={td}><span className="font-medium text-slate-900">{g.name}</span> <span className="text-xs text-slate-400">{g.code}</span></td>
              <td className={td}><input aria-label={`${g.name} slots`} inputMode="numeric" value={slots[g.id] ?? '0'}
                onChange={(e) => setSlots((s) => ({ ...s, [g.id]: e.target.value.replace(/\D/g, '') }))}
                className="w-20 rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm" /></td>
              <td className={`${td} text-xs`}>{filled} filled · {open} open · {blocked} blocked</td>
              <td className={`${td} text-right`}>
                {open > 0 && <Button variant="ghost" className="px-2 py-1 text-xs" loading={holds.isPending}
                  onClick={() => holds.mutate({ p_department_id: chart.department.id, p_state: 'blocked', p_grade_id: g.id })}>Block open</Button>}
                {blocked > 0 && <Button variant="ghost" className="px-2 py-1 text-xs" loading={holds.isPending}
                  onClick={() => holds.mutate({ p_department_id: chart.department.id, p_state: 'vacant', p_grade_id: g.id })}>Open blocked</Button>}
              </td>
            </tr>
          )
        })}
      </Table>
      <div className="flex flex-wrap items-center gap-3">
        <span className={cx('text-sm', approved !== '' && total > Number(approved) ? 'text-red-600' : 'text-slate-600')}>Slots {total} of {approved || '—'} budget
          {approved !== '' && total < Number(approved) ? ` · ${Number(approved) - total} left for extras` : ''}</span>
        <Button className="ml-auto" loading={save.isPending} disabled={!!problem} onClick={() => save.mutate({ p_department_id: chart.department.id, p: {
          approved_headcount: Number(approved), after_separation: after, note, slots: active.map((g, i) => ({ grade_id: g.id, planned: values[i] })) } })}>Save budget</Button>
      </div>
      {problem && approved !== '' && <Alert>{problem}</Alert>}
      <p className="text-xs text-slate-500">Hard rule: filled + offers in process can never pass the approved budget — offers are refused once it is full.
        Extra positions (more people than a grade's slots) are allowed only while the budget has room.</p>
    </Card>
  )
}

function GradesPanel() {
  const list = useOrganogramGrades()
  const save = useOrganogramAction<{ p_id: string | null; p: Record<string, unknown> }>('save_organogram_grade')
  const map = useOrganogramAction<{ p_designation_id: string; p_grade_id: string | null }>('set_designation_organogram_grade')
  const [edit, setEdit] = useState<{ id: string | null; code: string; name: string; rank: string; status: 'active' | 'inactive' } | null>(null)
  if (list.isPending) return <div className="flex justify-center py-8"><Spinner /></div>
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const l = list.data
  const manage = l.can.manage
  const gradeOptions = [{ value: '', label: '— not on the chart —' }, ...l.grades.filter((g) => g.status === 'active').map((g) => ({ value: g.id, label: `${g.rank}. ${g.name}` }))]
  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_1.4fr]">
      <Card className="space-y-3">
        <div className="flex items-center justify-between"><h3 className="font-semibold text-slate-900">Organogram grades</h3>
          {manage && <Button variant="secondary" onClick={() => setEdit({ id: null, code: '', name: '', rank: String((l.grades.at(-1)?.rank ?? 0) + 1), status: 'active' })}><Plus className="size-4" />Add</Button>}</div>
        {(save.isError) && <Alert>{errorMessage(save.error)}</Alert>}
        <ul className="divide-y divide-slate-100">
          {l.grades.map((g) => (
            <li key={g.id} className="flex items-center gap-3 py-2 text-sm">
              <span className="w-6 text-right tabular-nums text-slate-400">{g.rank}</span>
              <span className="font-medium text-slate-900">{g.name}</span><span className="text-xs text-slate-400">{g.code}</span>
              {g.status === 'inactive' && <Badge>Inactive</Badge>}
              <span className="ml-auto text-xs text-slate-500">{g.designations} designation(s)</span>
              {manage && <Button variant="ghost" className="px-2 py-1 text-xs" onClick={() => setEdit({ id: g.id, code: g.code, name: g.name, rank: String(g.rank), status: g.status })}>Edit</Button>}
            </li>
          ))}
        </ul>
        <p className="text-xs text-slate-500">Rank 1 is the top of the chart. These are separate from the pay grades (EM / MS) used for salary.</p>
      </Card>
      <Card className="space-y-3">
        <h3 className="font-semibold text-slate-900">Designation → organogram grade</h3>
        {map.isError && <Alert>{errorMessage(map.error)}</Alert>}
        <Table minWidth={520} head={<tr><th className={th}>Designation</th><th className={th}>Pay grade</th><th className={th}>Organogram grade</th></tr>}>
          {l.designations.map((d) => (
            <tr key={d.id}>
              <td className={td}><p className="font-medium text-slate-900">{d.name}</p><p className="text-xs text-slate-400">{d.department_name}</p></td>
              <td className={`${td} text-xs`}>{d.pay_grade}</td>
              <td className={td}><Select aria-label={`Organogram grade of ${d.name}`} value={d.organogram_grade_id ?? ''} disabled={!manage || map.isPending}
                onChange={(e) => map.mutate({ p_designation_id: d.id, p_grade_id: e.target.value || null })} options={gradeOptions} /></td>
            </tr>
          ))}
        </Table>
      </Card>
      {edit && (
        <Modal open onClose={() => setEdit(null)} title={edit.id ? 'Edit grade' : 'Add grade'}
          footer={<><Button variant="secondary" onClick={() => setEdit(null)}>Cancel</Button>
            <Button loading={save.isPending} onClick={() => save.mutate({ p_id: edit.id, p: { code: edit.code, name: edit.name, rank: Number(edit.rank), status: edit.status } }, { onSuccess: () => setEdit(null) })}>Save</Button></>}>
          <div className="grid gap-3 sm:grid-cols-2">
            <Input label="Code" value={edit.code} onChange={(e) => setEdit({ ...edit, code: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '') })} />
            <Input label="Name" value={edit.name} onChange={(e) => setEdit({ ...edit, name: e.target.value })} />
            <Input label="Rank (1 = top)" inputMode="numeric" value={edit.rank} onChange={(e) => setEdit({ ...edit, rank: e.target.value.replace(/\D/g, '') })} />
            <Select label="Status" value={edit.status} onChange={(e) => setEdit({ ...edit, status: e.target.value as 'active' | 'inactive' })}
              options={[{ value: 'active', label: 'Active' }, { value: 'inactive', label: 'Inactive' }]} />
          </div>
        </Modal>
      )}
    </div>
  )
}

export default function OrganogramPage() {
  const departments = useDepartmentBudgets()
  const grades = useOrganogramGrades()
  const [deptId, setDeptId] = useState<string | undefined>()
  const [tab, setTab] = useState<Tab>('chart')
  useEffect(() => {
    if (!deptId && departments.data?.length) setDeptId(departments.data[0].department_id)
  }, [departments.data, deptId])
  const chart = useDepartmentChart(deptId)
  const current = useMemo(() => departments.data?.find((d) => d.department_id === deptId), [departments.data, deptId])

  if (departments.isPending) return <PageLoader />
  if (departments.isError) return <Alert>{errorMessage(departments.error)}</Alert>
  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Organogram" description="Positions per department, driven by the approved headcount budget and the slots per grade. Updates as people join and leave." />
      {departments.data.length === 0 ? <EmptyState title="No departments">Add departments on the Organization page first.</EmptyState> : (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <Select label="Department" className="min-w-56" value={deptId ?? ''} onChange={(e) => setDeptId(e.target.value)}
              options={departments.data.map((d) => ({ value: d.department_id, label: `${d.name}${d.has_budget ? ` · ${d.counts.filled}/${d.counts.budget}` : ' · no budget'}` }))} />
            {current && (
              <div className="flex flex-wrap gap-2 text-sm">
                <span className="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 ring-1 ring-slate-200"><Users className="size-4 text-slate-400" />{budgetSentence(current.counts)}</span>
                {current.counts.headroom != null && <span className="rounded-xl bg-white px-3 py-2 ring-1 ring-slate-200">Headroom for extras: <b>{Math.max(current.counts.headroom, 0)}</b></span>}
              </div>
            )}
          </div>
          <Tabs value={tab} onChange={setTab} tabs={[{ key: 'chart', label: 'Chart' }, { key: 'budget', label: 'Budget & slots' },
            { key: 'grades', label: 'Grades & designations' }, { key: 'demo', label: 'Demo' }]} />
          {tab === 'demo' ? <OrganogramDemo /> : tab === 'grades' ? <GradesPanel />
            : chart.isPending ? <PageLoader /> : chart.isError ? <Alert>{errorMessage(chart.error)}</Alert>
              : tab === 'chart' ? <Chart chart={chart.data} />
                : grades.data ? <BudgetForm key={`${chart.data.department.id}-${chart.data.budget?.updated_at ?? ''}`} chart={chart.data} grades={grades.data.grades} /> : <Spinner />}
        </>
      )}
    </div>
  )
}
