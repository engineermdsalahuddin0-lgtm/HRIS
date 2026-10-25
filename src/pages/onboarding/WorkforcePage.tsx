import { useState } from 'react'
import { Link } from 'react-router-dom'
import { RefreshCw } from 'lucide-react'
import type { DepartmentWorkforce } from '@/onboarding-process/core/types'
import { METHOD_LABEL } from '@/onboarding-process/core/workload'
import { monthStart, useWorkforceAction, useWorkforceDashboard } from '@/lib/onboarding'
import { errorMessage } from '@/lib/identity'
import { formatMonth } from '@/lib/payroll'
import { Alert, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { PageHeader, Tabs } from '@/components/kit'
import { BAND_STYLE, WorkloadCard } from './WorkloadCard'
import { InputsPanel, PlanPanel, SettingsPanel } from './WorkforceSetup'
import { WorkforceDemo } from './WorkforceDemo'

type Tab = 'overview' | 'inputs' | 'plan' | 'settings' | 'demo'

interface BuildResult { period_month: string; departments: number; seats_drafted: number; drafting: boolean }

/** Workforce planning: workload vs capacity per department, vacancies and hiring suggestions. */
export default function WorkforcePage() {
  const thisMonth = monthStart()
  const [month, setMonth] = useState(thisMonth)
  const [tab, setTab] = useState<Tab>('overview')
  const dashboard = useWorkforceDashboard(month)
  const build = useWorkforceAction<{ p_month: string }, BuildResult>('build_workload_snapshots')
  const data = dashboard.data

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Workforce planning"
        description="Workload against capacity in every department, sanctioned headcount, vacancies and hiring suggestions."
        actions={(
          <>
            <label className="sr-only" htmlFor="workforce-month">Month</label>
            <input id="workforce-month" type="month" value={month.slice(0, 7)} max={thisMonth.slice(0, 7)}
              onChange={(e) => e.target.value && setMonth(`${e.target.value}-01`)}
              className="rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm" />
            {data?.can.manage && (
              <Button loading={build.isPending} onClick={() => build.mutate({ p_month: month })}>
                <RefreshCw className="size-4" />Build {formatMonth(month)}
              </Button>
            )}
          </>
        )} />
      {build.isError && <Alert>{errorMessage(build.error)}</Alert>}
      {build.isSuccess && (
        <Alert tone="success">
          Built {build.data.departments} department(s) for {formatMonth(build.data.period_month)}.{' '}
          {build.data.drafting
            ? `${build.data.seats_drafted} seat(s) drafted as vacancies.`
            : 'Older months are kept as history: no vacancies are drafted from them.'}
          {build.data.seats_drafted > 0 && <> <Link to="/vacancies" className="font-medium underline">Review vacancies</Link></>}
        </Alert>
      )}
      <Tabs value={tab} onChange={setTab} tabs={[
        { key: 'overview', label: 'Overview' }, { key: 'inputs', label: 'Output data' },
        { key: 'plan', label: 'Plan & methods' }, { key: 'settings', label: 'Settings' }, { key: 'demo', label: 'Demo cases' },
      ]} />
      {tab === 'demo' ? <WorkforceDemo />
        : dashboard.isPending ? <PageLoader />
        : dashboard.isError ? <Alert>{errorMessage(dashboard.error)}</Alert>
        : tab === 'inputs' ? <InputsPanel data={dashboard.data} />
        : tab === 'plan' ? <PlanPanel data={dashboard.data} />
        : tab === 'settings' ? <SettingsPanel key={dashboard.data.settings?.confirmed_at ?? 'new'} data={dashboard.data} />
        : <Overview departments={dashboard.data.departments} canManage={dashboard.data.can.manage} />}
    </div>
  )
}

function Overview({ departments, canManage }: { departments: DepartmentWorkforce[]; canManage: boolean }) {
  if (!departments.length) return <EmptyState title="No departments yet">Add departments and designations in Organization, then set the headcount plan.</EmptyState>
  const built = departments.filter((d) => d.snapshot)
  const sum = (pick: (d: DepartmentWorkforce) => number) => departments.reduce((total, d) => total + pick(d), 0)
  const sanctioned = sum((d) => d.plan.reduce((s, p) => s + p.sanctioned, 0))
  const active = sum((d) => d.plan.reduce((s, p) => s + p.active, 0))
  const kpis = [
    { label: 'Sanctioned', value: sanctioned },
    { label: 'Active', value: active },
    { label: 'Vacancy', value: Math.max(sanctioned - active, 0) },
    { label: 'Open vacancy seats', value: sum((d) => d.open_seats) },
    { label: 'Overloaded departments', value: built.filter((d) => d.snapshot && ['overload', 'critical'].includes(d.snapshot.band)).length },
    { label: 'Suggested seats', value: built.reduce((s, d) => s + (d.snapshot?.seats_total ?? 0), 0) },
  ]
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
        {kpis.map((kpi) => (
          <Card key={kpi.label} className="p-4">
            <p className="text-xs text-slate-500">{kpi.label}</p>
            <p className="mt-1 text-2xl font-semibold tabular-nums">{kpi.value}</p>
          </Card>
        ))}
      </div>
      {built.length < departments.length && (
        <Alert tone="info">
          {departments.length - built.length} department(s) have no figures for this month yet.
          {canManage ? ' Enter output data where needed, then press Build.' : ' HR builds them each month.'}
        </Alert>
      )}
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {departments.map((department) => department.snapshot ? (
          <WorkloadCard key={department.id} name={department.name}
            figures={{ ...department.snapshot, inputs: department.inputs }}
            footer={<DepartmentFooter department={department} />} />
        ) : (
          <div key={department.id} className="rounded-2xl border border-dashed border-slate-300 p-4">
            <p className="font-semibold text-slate-900">{department.name}</p>
            <p className="text-xs text-slate-500">{METHOD_LABEL[department.method]}</p>
            <p className="mt-3 text-sm text-slate-500">Not built for this month.</p>
            <DepartmentFooter department={department} />
          </div>
        ))}
      </div>
    </div>
  )
}

function DepartmentFooter({ department }: { department: DepartmentWorkforce }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-2 border-t border-slate-100 pt-3 text-xs text-slate-500">
      <div>
        <p className="mb-1">Last 6 months</p>
        <div className="flex h-8 items-end gap-1" aria-label="Workload index trend">
          {department.trend.length === 0 ? <span>—</span> : department.trend.map((point) => (
            <span key={point.period_month} title={`${formatMonth(point.period_month)}: ${point.index ?? '—'}`}
              className={cx('w-3 rounded-sm', BAND_STYLE[point.band].bar)}
              style={{ height: `${Math.max(Math.min((point.index ?? 1.5) / 1.5, 1) * 100, 8)}%` }} />
          ))}
        </div>
      </div>
      {department.open_seats > 0 && <Link to="/vacancies" className="font-medium text-primary-700 hover:underline">{department.open_seats} open vacancy seat(s)</Link>}
    </div>
  )
}
