import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Building2, ChevronLeft, ChevronRight, KeyRound, Search, UserCheck, UserPlus, Users } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { EMPLOYEE_STATUSES, EMPLOYMENT_TYPES, labelOf } from '@/lib/options'
import type { EmployeeFilters } from '@/lib/hr'
import { useEmployeeStats, useEmployees, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, Spinner } from '@/components/ui'
import { PageHeader, Select, StatusBadge, Table, td, th } from '@/components/kit'

function Kpi({ label, value, icon: Icon }: { label: string; value: number | undefined; icon: LucideIcon }) {
  return (
    <Card className="flex items-center gap-4 p-5">
      <div className="flex size-11 items-center justify-center rounded-xl bg-primary-50 text-primary-600">
        <Icon className="size-5" aria-hidden />
      </div>
      <div>
        <p className="text-sm text-slate-500">{label}</p>
        <p className="text-2xl font-semibold tabular-nums text-slate-900">{value ?? '—'}</p>
      </div>
    </Card>
  )
}

export function Avatar({ name, size = 'md' }: { name: string; size?: 'md' | 'lg' }) {
  const initials = name.split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase()
  return (
    <div
      className={
        size === 'lg'
          ? 'flex size-16 shrink-0 items-center justify-center rounded-2xl bg-primary-100 text-xl font-semibold text-primary-700'
          : 'flex size-9 shrink-0 items-center justify-center rounded-full bg-primary-100 text-xs font-semibold text-primary-700'
      }
      aria-hidden
    >
      {initials}
    </div>
  )
}

const PAGE_SIZE = 20

export default function EmployeesPage() {
  const ctx = useMyContext()
  const navigate = useNavigate()
  const canCreate = ctx.permissions.includes('employees.create')
  const [filters, setFilters] = useState<EmployeeFilters>({
    search: '', status: 'active', department_id: '', branch_id: '', employment_type: '', page: 0, pageSize: PAGE_SIZE,
  })
  const set = (patch: Partial<EmployeeFilters>) => setFilters((f) => ({ ...f, page: 0, ...patch }))

  const stats = useEmployeeStats()
  const list = useEmployees(filters)
  const structure = useOrgStructure()
  const s = structure.data

  const total = list.data?.total ?? 0
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader
        title="Employees"
        description="Everyone in your organization. Fields you are not allowed to see are hidden."
        actions={canCreate && (
          <Button onClick={() => navigate('/employees/new')}>
            <UserPlus className="size-4" /> Add employee
          </Button>
        )}
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi label="Total" value={stats.data?.total} icon={Users} />
        <Kpi label="Active" value={stats.data?.active} icon={UserCheck} />
        <Kpi label="Portal access" value={stats.data?.portal_access} icon={KeyRound} />
        <Kpi label="Departments" value={stats.data?.departments} icon={Building2} />
      </div>

      <Card className="grid gap-3 p-4 md:grid-cols-[1fr_repeat(4,minmax(0,160px))]">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
          <input
            value={filters.search}
            onChange={(e) => set({ search: e.target.value })}
            placeholder="Search name, card ID or phone"
            aria-label="Search employees"
            className="w-full rounded-xl border border-slate-300 bg-white py-2.5 pl-9 pr-3 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100"
          />
        </div>
        <Select aria-label="Status" value={filters.status} onChange={(e) => set({ status: e.target.value })} options={EMPLOYEE_STATUSES} placeholder="All statuses" />
        <Select
          aria-label="Department"
          value={filters.department_id}
          onChange={(e) => set({ department_id: e.target.value })}
          options={(s?.departments ?? []).map((d) => ({ value: d.id, label: d.name }))}
          placeholder="All departments"
        />
        <Select
          aria-label="Branch"
          value={filters.branch_id}
          onChange={(e) => set({ branch_id: e.target.value })}
          options={(s?.branches ?? []).map((b) => ({ value: b.id, label: b.name }))}
          placeholder="All branches"
        />
        <Select
          aria-label="Employment type"
          value={filters.employment_type}
          onChange={(e) => set({ employment_type: e.target.value })}
          options={EMPLOYMENT_TYPES}
          placeholder="All types"
        />
      </Card>

      {list.isError ? (
        <Alert>{errorMessage(list.error)}</Alert>
      ) : list.isPending ? (
        <div className="flex justify-center py-16 text-primary-600"><Spinner className="size-8" /></div>
      ) : list.data.rows.length === 0 ? (
        <EmptyState title="No employees found">
          {canCreate ? 'Try other filters, or add your first employee.' : 'Try other filters.'}
        </EmptyState>
      ) : (
        <>
          <Table
            minWidth={880}
            head={
              <tr>
                <th className={th}>Employee</th>
                <th className={th}>Card ID</th>
                <th className={th}>Department / Designation</th>
                <th className={th}>Branch / Office</th>
                <th className={th}>Type</th>
                <th className={th}>Portal</th>
                <th className={th}>Status</th>
              </tr>
            }
          >
            {list.data.rows.map((e) => (
              <tr key={e.id} className="cursor-pointer hover:bg-slate-50" onClick={() => navigate(`/employees/${e.id}`)}>
                <td className={td}>
                  <Link to={`/employees/${e.id}`} className="flex items-center gap-3" onClick={(ev) => ev.stopPropagation()}>
                    <Avatar name={e.full_name} />
                    <div className="min-w-0">
                      <p className="truncate font-medium text-slate-900">{e.full_name}</p>
                      <p className="truncate text-xs text-slate-500">{e.phone ?? e.email ?? ''}</p>
                    </div>
                  </Link>
                </td>
                <td className={`${td} font-mono text-xs`}>{e.card_id}</td>
                <td className={td}>
                  <p>{e.department_name ?? '—'}</p>
                  <p className="text-xs text-slate-500">
                    {e.designation_name ?? ''} {e.grade_code && <span className="font-mono">· {e.grade_code}</span>}
                  </p>
                </td>
                <td className={td}>
                  <p>{e.branch_name ?? '—'}</p>
                  <p className="text-xs text-slate-500">{e.office_name ?? ''}</p>
                </td>
                <td className={td}>{labelOf(EMPLOYMENT_TYPES, e.employment_type)}</td>
                <td className={td}>{e.has_portal_access ? <Badge tone="green">{e.portal_role_name}</Badge> : <span className="text-xs text-slate-400">No login</span>}</td>
                <td className={td}><StatusBadge status={e.status} /></td>
              </tr>
            ))}
          </Table>
          <div className="flex items-center justify-between text-sm text-slate-600">
            <span>
              {filters.page * PAGE_SIZE + 1}–{Math.min(total, (filters.page + 1) * PAGE_SIZE)} of {total}
              {list.isFetching && <Spinner className="ml-2 inline size-4 text-primary-600" />}
            </span>
            <div className="flex gap-2">
              <Button variant="secondary" disabled={filters.page === 0} onClick={() => setFilters((f) => ({ ...f, page: f.page - 1 }))} aria-label="Previous page">
                <ChevronLeft className="size-4" />
              </Button>
              <Button variant="secondary" disabled={filters.page + 1 >= pages} onClick={() => setFilters((f) => ({ ...f, page: f.page + 1 }))} aria-label="Next page">
                <ChevronRight className="size-4" />
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
