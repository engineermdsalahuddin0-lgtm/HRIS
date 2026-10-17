import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { Building2, CheckCircle2, ChevronRight, Clock, PauseCircle, Search, XCircle } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { OrganizationRow, OrgPaymentSummary } from '@/lib/platform'
import { SUBSCRIPTION_LABELS, usePlatformOverview } from '@/lib/platform'
import { Alert, Badge, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { PageHeader, Table, td, th } from '@/components/kit'

type OrgFilter = 'all' | 'active' | 'non_active'

/** A clickable status tile; `to` links it to the matching list. */
function StatusTile({ label, value, icon: Icon, tone, to, onClick, selected }: {
  label: string; value: number; icon: LucideIcon; tone: string; to?: string; onClick?: () => void; selected?: boolean
}) {
  const body = (
    <Card className={cx('flex items-center gap-4 p-5 transition hover:ring-primary-200', selected && 'ring-2 ring-primary-400')}>
      <div className={cx('flex size-11 items-center justify-center rounded-xl', tone)}><Icon className="size-5" aria-hidden /></div>
      <div>
        <p className="text-sm text-slate-500">{label}</p>
        <p className="text-2xl font-semibold tabular-nums text-slate-900">{value}</p>
      </div>
    </Card>
  )
  if (to) return <Link to={to} className="block">{body}</Link>
  return <button type="button" onClick={onClick} className="block w-full text-left" aria-pressed={selected}>{body}</button>
}

export function OrgStatusBadge({ status }: { status: OrganizationRow['status'] }) {
  return status === 'active'
    ? <Badge tone="green">Active</Badge>
    : <Badge tone="red">{status === 'suspended' ? 'Suspended' : 'Inactive'}</Badge>
}

export function PaymentBadge({ status }: { status: OrgPaymentSummary | string }) {
  const tone = status === 'paid' ? 'green' : status === 'overdue' ? 'red' : status === 'due' ? 'orange' : 'slate'
  const label = status === 'none' ? 'No invoices' : status.charAt(0).toUpperCase() + status.slice(1)
  return <Badge tone={tone}>{label}</Badge>
}

/** Platform admin home: application and organization status at a glance. */
export default function PlatformDashboardPage() {
  const navigate = useNavigate()
  const overview = usePlatformOverview()
  const [filter, setFilter] = useState<OrgFilter>('all')
  const [query, setQuery] = useState('')

  const organizations = overview.data?.organizations ?? []
  const activeCount = organizations.filter((o) => o.status === 'active').length
  const visibleOrganizations = useMemo(() => {
    const needle = query.trim().toLowerCase()
    return organizations.filter((o) =>
      (filter === 'all' || (filter === 'active' ? o.status === 'active' : o.status !== 'active'))
      && (!needle || o.name.toLowerCase().includes(needle) || o.org_code.includes(needle)))
  }, [organizations, filter, query])

  if (overview.isPending) return <PageLoader />
  if (overview.isError) return <Alert>{errorMessage(overview.error)}</Alert>
  const applications = overview.data.applications

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Platform" description="Organization applications and the status of every organization on Olympus HRIS." />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">
        <StatusTile label="Pending applications" value={applications.pending} icon={Clock} tone="bg-amber-50 text-amber-700" to="/platform/applications?status=pending" />
        <StatusTile label="Accepted" value={applications.approved} icon={CheckCircle2} tone="bg-green-50 text-green-700" to="/platform/applications?status=approved" />
        <StatusTile label="Rejected" value={applications.rejected} icon={XCircle} tone="bg-red-50 text-red-700" to="/platform/applications?status=rejected" />
        <StatusTile label="Active organizations" value={activeCount} icon={Building2} tone="bg-primary-50 text-primary-700"
          onClick={() => setFilter('active')} selected={filter === 'active'} />
        <StatusTile label="Non-active organizations" value={organizations.length - activeCount} icon={PauseCircle} tone="bg-slate-100 text-slate-600"
          onClick={() => setFilter('non_active')} selected={filter === 'non_active'} />
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <div className="relative min-w-56 flex-1 sm:max-w-xs">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name or org code" aria-label="Search organizations"
            className="w-full rounded-xl border border-slate-300 bg-white py-2 pl-9 pr-3 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
        </div>
        <div className="flex gap-1 rounded-xl bg-slate-100 p-1" role="tablist" aria-label="Organization status">
          {(['all', 'active', 'non_active'] as OrgFilter[]).map((key) => (
            <button key={key} role="tab" aria-selected={filter === key} onClick={() => setFilter(key)}
              className={cx('rounded-lg px-3 py-1.5 text-sm font-medium', filter === key ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>
              {key === 'all' ? 'All' : key === 'active' ? 'Active' : 'Non-active'}
            </button>
          ))}
        </div>
      </div>

      {visibleOrganizations.length === 0 ? (
        <EmptyState title="No organizations here" />
      ) : (
        <Table minWidth={860} head={
          <tr>
            <th className={th}>Organization</th><th className={th}>Status</th><th className={th}>Employees</th>
            <th className={th}>Plan</th><th className={th}>Subscription</th><th className={th}>Payment</th>
            <th className={th}>Joined</th><th className={th} />
          </tr>
        }>
          {visibleOrganizations.map((org) => (
            <tr key={org.id} className="cursor-pointer hover:bg-slate-50" onClick={() => navigate(`/platform/organizations/${org.id}`)}>
              <td className={td}>
                <Link to={`/platform/organizations/${org.id}`} className="font-medium text-slate-900" onClick={(e) => e.stopPropagation()}>{org.name}</Link>
                <p className="font-mono text-xs text-slate-400">{org.org_code}</p>
              </td>
              <td className={td}><OrgStatusBadge status={org.status} /></td>
              <td className={`${td} tabular-nums`}>{org.active_employees}</td>
              <td className={td}>{org.plan_name ?? '—'}</td>
              <td className={td}>{org.subscription_status ? SUBSCRIPTION_LABELS[org.subscription_status] : '—'}</td>
              <td className={td}><PaymentBadge status={org.payment_status} /></td>
              <td className={td}>{formatDate(org.created_at)}</td>
              <td className="px-4 py-3 text-right text-slate-400"><ChevronRight className="inline size-4" /></td>
            </tr>
          ))}
        </Table>
      )}
    </div>
  )
}
