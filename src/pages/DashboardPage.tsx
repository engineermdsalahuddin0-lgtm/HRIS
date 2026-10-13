import type { ReactNode } from 'react'
import type { LucideIcon } from 'lucide-react'
import {
  ArrowRightLeft,
  Building2,
  CalendarDays,
  KeyRound,
  Network,
  Plus,
  ShieldCheck,
  TrendingUp,
  UserCheck,
  UserPlus,
  Users,
} from 'lucide-react'
import { Navigate } from 'react-router-dom'
import { useMyContext } from '@/lib/appContext'
import { Badge, Card, cx } from '@/components/ui'
import { ChartCard, DepartmentBars, EmploymentDonut, HeadcountArea, JoinersLeaversBars } from './dashboard/charts'
import * as sample from './dashboard/sampleData'

function KpiTile({
  label,
  value,
  icon: Icon,
  note,
}: {
  label: string
  value: number | string
  icon: LucideIcon
  note?: ReactNode
}) {
  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <p className="text-sm font-medium text-slate-500">{label}</p>
        <div className="flex size-9 items-center justify-center rounded-xl bg-primary-50 text-primary-600">
          <Icon className="size-5" aria-hidden />
        </div>
      </div>
      <p className="mt-2 text-3xl font-semibold tabular-nums tracking-tight text-slate-900">{value}</p>
      {note && <div className="mt-1 text-xs text-slate-500">{note}</div>}
    </Card>
  )
}

const ACTIVITY_ICON: Record<(typeof sample.recentActivity)[number]['kind'], LucideIcon> = {
  joined: UserPlus,
  transfer: ArrowRightLeft,
  promotion: TrendingUp,
  access: KeyRound,
  reporting: Network,
}

const QUICK_ACTIONS: { label: string; icon: LucideIcon; permission: string; soon: string }[] = [
  { label: 'Add employee', icon: UserPlus, permission: 'employees.create', soon: 'Step 5' },
  { label: 'Add department', icon: Building2, permission: 'org.manage', soon: 'Step 3' },
  { label: 'Manage roles', icon: ShieldCheck, permission: 'roles.manage', soon: 'Step 4' },
]

function greeting() {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
}

export default function DashboardPage() {
  const context = useMyContext()
  // A platform admin without a company lands on the approvals screen.
  if (!context.organization) return <Navigate to="/platform/requests" replace />

  const { organization, user, permissions } = context
  const firstName = user?.full_name?.split(' ')[0]
  const today = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
  const k = sample.kpis

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-semibold text-slate-900">
            {greeting()}
            {firstName ? `, ${firstName}` : ''}
          </h2>
          <p className="mt-1 flex items-center gap-1.5 text-sm text-slate-500">
            <CalendarDays className="size-4" aria-hidden />
            {today} · {organization.name}
          </p>
        </div>
        <Badge tone="orange">Sample data until the Employees module (Step 5)</Badge>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiTile
          label="Total employees"
          value={k.totalEmployees}
          icon={Users}
          note={
            <span className="inline-flex items-center gap-1">
              <TrendingUp className="size-3.5" aria-hidden />+{k.newThisMonth} this month
            </span>
          }
        />
        <KpiTile label="Active" value={k.active} icon={UserCheck} note={`${Math.round((k.active / k.totalEmployees) * 100)}% of all employees`} />
        <KpiTile label="Portal access" value={k.portalAccess} icon={KeyRound} note={`${k.totalEmployees - k.portalAccess} without a login`} />
        <KpiTile label="Departments" value={k.departments} icon={Building2} note="Across all branches" />
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <ChartCard
          className="lg:col-span-2"
          title="Headcount"
          subtitle="Active employees at month end, last 12 months"
          table={{ columns: ['Month', 'Headcount'], rows: sample.headcountTrend.map((d) => [d.month, d.headcount]) }}
        >
          <HeadcountArea data={sample.headcountTrend} />
        </ChartCard>
        <ChartCard
          title="Employment type"
          table={{ columns: ['Type', 'Employees'], rows: sample.employmentTypes.map((d) => [d.type, d.count]) }}
        >
          <EmploymentDonut data={sample.employmentTypes} />
        </ChartCard>
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <ChartCard
          title="Employees by department"
          table={{ columns: ['Department', 'Employees'], rows: sample.byDepartment.map((d) => [d.department, d.count]) }}
        >
          <DepartmentBars data={sample.byDepartment} />
        </ChartCard>
        <ChartCard
          title="Joiners and leavers"
          subtitle="Last 6 months"
          table={{
            columns: ['Month', 'Joiners', 'Leavers'],
            rows: sample.joinersLeavers.map((d) => [d.month, d.joiners, d.leavers]),
          }}
        >
          <JoinersLeaversBars data={sample.joinersLeavers} />
        </ChartCard>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <h2 className="mb-4 font-semibold text-slate-900">Recent activity</h2>
          <ul className="divide-y divide-slate-100">
            {sample.recentActivity.map((a) => {
              const Icon = ACTIVITY_ICON[a.kind]
              return (
                <li key={a.who + a.kind} className="flex items-center gap-3 py-3">
                  <div className="flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-100 text-slate-600">
                    <Icon className="size-4" aria-hidden />
                  </div>
                  <p className="min-w-0 flex-1 text-sm text-slate-600">
                    <span className="font-medium text-slate-900">{a.who}</span> {a.what}
                  </p>
                  <span className="shrink-0 text-xs text-slate-400">{a.when}</span>
                </li>
              )
            })}
          </ul>
        </Card>

        <Card>
          <h2 className="mb-4 font-semibold text-slate-900">Quick actions</h2>
          <div className="space-y-2">
            {QUICK_ACTIONS.filter((q) => permissions.includes(q.permission)).map(({ label, icon: Icon, soon }) => (
              <button
                key={label}
                disabled
                title={`Arrives in ${soon}`}
                className={cx(
                  'flex w-full items-center gap-3 rounded-xl border border-slate-200 px-4 py-3 text-left text-sm font-medium',
                  'text-slate-700 disabled:cursor-not-allowed disabled:opacity-60',
                )}
              >
                <Icon className="size-4 text-primary-600" aria-hidden />
                {label}
                <span className="ml-auto inline-flex items-center gap-1 text-xs font-normal text-slate-400">
                  <Plus className="size-3" aria-hidden />
                  {soon}
                </span>
              </button>
            ))}
            {!QUICK_ACTIONS.some((q) => permissions.includes(q.permission)) && (
              <p className="text-sm text-slate-500">Your role has no admin actions.</p>
            )}
          </div>
        </Card>
      </div>
    </div>
  )
}
