import type { ReactNode } from 'react'
import { Suspense, lazy } from 'react'
import type { LucideIcon } from 'lucide-react'
import {
  ArrowRight, ArrowRightLeft, BadgeCheck, Building2, CalendarDays, KeyRound, Power, ShieldCheck, TrendingDown,
  TrendingUp, UserCheck, UserPlus, Users,
} from 'lucide-react'
import { Link, Navigate } from 'react-router-dom'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { EVENT_LABELS, formatDate } from '@/lib/options'
import { useDashboardStats } from '@/lib/hr'
import { Alert, Badge, Card, EmptyState, PageLoader } from '@/components/ui'
import { ChartCard, DepartmentBars, EmploymentDonut, HeadcountArea, JoinersLeaversBars } from './dashboard/charts'
import { sampleStats } from './dashboard/sampleData'

// Pinned / unread / to-acknowledge notices (src/communication); hidden when there is nothing.
const NoticeBanner = lazy(() => import('@/communication/notices/components/NoticeBanner'))

function KpiTile({ label, value, icon: Icon, note }: { label: string; value: number | string; icon: LucideIcon; note?: ReactNode }) {
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

const ACTIVITY_ICON: Record<string, LucideIcon> = {
  joined: UserPlus, transfer: ArrowRightLeft, branch: ArrowRightLeft, office: ArrowRightLeft, promotion: TrendingUp,
  demotion: TrendingDown, status: Power, designation: BadgeCheck, employment_type: BadgeCheck,
}

const QUICK_ACTIONS: { label: string; to: string; icon: LucideIcon; permission: string }[] = [
  { label: 'Add employee', to: '/employees/new', icon: UserPlus, permission: 'employees.create' },
  { label: 'Organization structure', to: '/organization', icon: Building2, permission: 'org.manage' },
  { label: 'Roles & access', to: '/settings/roles', icon: ShieldCheck, permission: 'roles.manage' },
]

function greeting() {
  const h = new Date().getHours()
  return h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening'
}

function relative(iso: string) {
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  if (mins < 60) return `${Math.max(mins, 1)}m ago`
  if (mins < 1440) return `${Math.round(mins / 60)}h ago`
  return formatDate(iso)
}

export default function DashboardPage() {
  const context = useMyContext()
  const isPreview = useIsPreview()
  const canView = context.permissions.includes('employees.view')
  const stats = useDashboardStats(!isPreview && canView && !!context.organization)

  // A platform admin without a company lands on the platform dashboard.
  if (!context.organization) return <Navigate to="/platform" replace />

  const { organization, user, permissions } = context
  const firstName = user?.full_name?.split(' ')[0]
  const todayLabel = new Date().toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })

  const header = (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h2 className="text-2xl font-semibold text-slate-900">{greeting()}{firstName ? `, ${firstName}` : ''}</h2>
        <p className="mt-1 flex items-center gap-1.5 text-sm text-slate-500">
          <CalendarDays className="size-4" aria-hidden />
          {todayLabel} · {organization.name}
        </p>
      </div>
      {isPreview && <Badge tone="orange">Preview — sample data</Badge>}
    </div>
  )
  const notices = isPreview ? null : <Suspense fallback={null}><NoticeBanner /></Suspense>

  // Roles without the people list (e.g. Employee) get a personal home.
  if (!canView && !isPreview) {
    return (
      <div className="mx-auto max-w-4xl space-y-6">
        {header}
        {notices}
        <div className="grid gap-4 sm:grid-cols-2">
          <Link to="/me" className="block">
            <Card className="flex h-full items-center gap-4 transition hover:ring-primary-200">
              <div className="flex size-11 items-center justify-center rounded-xl bg-primary-50 text-primary-600"><UserCheck className="size-5" /></div>
              <div className="flex-1">
                <p className="font-medium text-slate-900">My profile</p>
                <p className="text-sm text-slate-500">Personal info, history and reporting chain</p>
              </div>
              <ArrowRight className="size-4 text-slate-400" />
            </Card>
          </Link>
          <Card>
            <p className="text-xs font-medium uppercase tracking-wide text-slate-500">Your role</p>
            <p className="mt-2 text-2xl font-semibold text-slate-900">{context.role?.name ?? '—'}</p>
            <p className="mt-1 text-sm text-slate-500">Org code <span className="font-mono">{organization.org_code}</span></p>
          </Card>
        </div>
      </div>
    )
  }

  if (!isPreview && stats.isPending) return <PageLoader />
  if (!isPreview && stats.isError) return <Alert>{errorMessage(stats.error)}</Alert>
  const d = isPreview ? sampleStats : stats.data
  if (!d) return <EmptyState title="No data yet" />
  const k = d.kpis
  const hasPeople = k.total > 0

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      {header}
      {notices}

      <div data-tour="kpis" className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiTile
          label="Total employees"
          value={k.total}
          icon={Users}
          note={<span className="inline-flex items-center gap-1"><TrendingUp className="size-3.5" aria-hidden />+{k.new_this_month} this month</span>}
        />
        <KpiTile label="Active" value={k.active} icon={UserCheck} note={hasPeople ? `${Math.round((k.active / k.total) * 100)}% of all employees` : undefined} />
        <KpiTile label="Portal access" value={k.portal_access} icon={KeyRound} note={`${Math.max(k.active - k.portal_access, 0)} active without a login`} />
        <KpiTile label="Departments" value={k.departments} icon={Building2} note={`${k.branches} branch${k.branches === 1 ? '' : 'es'}`} />
      </div>

      {!hasPeople ? (
        <EmptyState title="No employees yet">
          Set up departments, designations, branches and offices in Organization, then add your first employee.
        </EmptyState>
      ) : (
        <>
          <div data-tour="charts" className="grid gap-4 lg:grid-cols-3">
            <ChartCard
              className="lg:col-span-2"
              title="Headcount"
              subtitle="Employees on the books at month end, last 12 months"
              table={{ columns: ['Month', 'Headcount'], rows: d.headcount_trend.map((x) => [x.month, x.headcount]) }}
            >
              <HeadcountArea data={d.headcount_trend} />
            </ChartCard>
            <ChartCard title="Employment type" subtitle="Active employees" table={{ columns: ['Type', 'Employees'], rows: d.employment_types.map((x) => [x.type, x.count]) }}>
              <EmploymentDonut data={d.employment_types.slice(0, 3)} />
            </ChartCard>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <ChartCard title="Employees by department" subtitle="Active employees, top 10" table={{ columns: ['Department', 'Employees'], rows: d.by_department.map((x) => [x.department, x.count]) }}>
              <DepartmentBars data={d.by_department} />
            </ChartCard>
            <ChartCard
              title="Joiners and leavers"
              subtitle="Last 6 months"
              table={{ columns: ['Month', 'Joiners', 'Leavers'], rows: d.joiners_leavers.map((x) => [x.month, x.joiners, x.leavers]) }}
            >
              <JoinersLeaversBars data={d.joiners_leavers} />
            </ChartCard>
          </div>
        </>
      )}

      <div className="grid gap-4 lg:grid-cols-3">
        <div data-tour="activity" className="lg:col-span-2">
        <Card className="h-full">
          <h2 className="mb-4 font-semibold text-slate-900">Recent activity</h2>
          {d.recent_activity.length === 0 ? (
            <p className="text-sm text-slate-500">No activity yet.</p>
          ) : (
            <ul className="divide-y divide-slate-100">
              {d.recent_activity.map((a, i) => {
                const Icon = ACTIVITY_ICON[a.event_type] ?? BadgeCheck
                const to = a.to as Record<string, string> | null
                const detail = to?.designation ?? to?.office ?? to?.branch ?? to?.status ?? ''
                return (
                  <li key={a.employee_id + i} className="flex items-center gap-3 py-3">
                    <div className="flex size-9 shrink-0 items-center justify-center rounded-full bg-slate-100 text-slate-600">
                      <Icon className="size-4" aria-hidden />
                    </div>
                    <p className="min-w-0 flex-1 text-sm text-slate-600">
                      {isPreview ? (
                        <span className="font-medium text-slate-900">{a.who}</span>
                      ) : (
                        <Link to={`/employees/${a.employee_id}`} className="font-medium text-slate-900 hover:text-primary-700">{a.who}</Link>
                      )}{' '}
                      — {(EVENT_LABELS[a.event_type] ?? a.event_type).toLowerCase()}
                      {detail && <span className="text-slate-500"> · {detail}</span>}
                    </p>
                    <span className="shrink-0 text-xs text-slate-400">{relative(a.created_at)}</span>
                  </li>
                )
              })}
            </ul>
          )}
        </Card>
        </div>

        <div data-tour="quick-actions">
        <Card className="h-full">
          <h2 className="mb-4 font-semibold text-slate-900">Quick actions</h2>
          <div className="space-y-2">
            {QUICK_ACTIONS.filter((q) => permissions.includes(q.permission)).map(({ label, to, icon: Icon }) => (
              <Link
                key={label}
                to={isPreview ? '#' : to}
                className="flex w-full items-center gap-3 rounded-xl border border-slate-200 px-4 py-3 text-sm font-medium text-slate-700 transition hover:border-primary-200 hover:bg-primary-50"
              >
                <Icon className="size-4 text-primary-600" aria-hidden />
                {label}
                <ArrowRight className="ml-auto size-4 text-slate-400" aria-hidden />
              </Link>
            ))}
            {!QUICK_ACTIONS.some((q) => permissions.includes(q.permission)) && (
              <p className="text-sm text-slate-500">Your role has no admin actions.</p>
            )}
          </div>
        </Card>
        </div>
      </div>
    </div>
  )
}
