import type { ReactNode } from 'react'
import { useState } from 'react'
import { Link, Navigate, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, ArrowRightLeft, BadgeCheck, CalendarDays, KeyRound, MapPin, Network, Pencil, Phone, Power, TrendingDown,
  TrendingUp, UserPlus, Mail, IdCard,
} from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import {
  BLOOD_GROUPS, EMPLOYMENT_TYPES, EVENT_LABELS, GENDERS, LINE_TYPES, MARITAL, RELIGIONS, formatDate, labelOf,
} from '@/lib/options'
import type { HistoryRow } from '@/lib/hr'
import { useEmployeeProfile, useOrgStructure } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Badge, Button, Card, EmptyState, PageLoader } from '@/components/ui'
import { StatusBadge, Tabs } from '@/components/kit'
import { useEmployeeFiles } from '@/lib/files'
import { EmployeeFilesCard } from './EmployeeFiles'
import { IdCardDialog } from './IdCardDialog'
import { FinancialTab, canSeeFinancialTab } from './FinancialTab'
import { EditEmployeeDialog, PortalDialog, ReportingDialog, StatusDialog, TransferDialog } from './profileDialogs'

type Tab = 'personal' | 'history' | 'reporting' | 'financial'
type DialogKey = 'edit' | 'transfer' | 'reporting' | 'status' | 'portal' | 'idcard' | null

function Field({ label, value }: { label: string; value: ReactNode }) {
  const hidden = value === null || value === undefined
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-slate-400">{label}</dt>
      <dd className={hidden ? 'mt-1 text-sm italic text-slate-400' : 'mt-1 text-sm text-slate-800'}>
        {hidden ? 'Hidden or not set' : value || '—'}
      </dd>
    </div>
  )
}

const EVENT_ICON: Record<string, LucideIcon> = {
  joined: UserPlus, promotion: TrendingUp, demotion: TrendingDown, transfer: ArrowRightLeft, branch: ArrowRightLeft,
  office: ArrowRightLeft, department: ArrowRightLeft, designation: BadgeCheck, operation: ArrowRightLeft,
  employment_type: BadgeCheck, status: Power,
}

function describeChange(h: HistoryRow): string {
  const f = (h.from ?? {}) as Record<string, string>
  const t = (h.to ?? {}) as Record<string, string>
  const parts: string[] = []
  const pick = (k: string, label: string) => {
    if (t[k] !== undefined && f[k] !== t[k]) parts.push(`${label}: ${f[k] ?? '—'} → ${t[k]}`)
  }
  if (h.event_type === 'joined') {
    return [t.department, t.designation, t.branch, t.office].filter(Boolean).join(' · ') || 'Joined'
  }
  pick('department', 'Department')
  pick('designation', 'Designation')
  pick('grade', 'Grade')
  pick('branch', 'Branch')
  pick('office', 'Office')
  pick('operation', 'Operation')
  pick('employment_type', 'Type')
  pick('status', 'Status')
  return parts.join(' · ')
}

/** /me → the signed-in user's own profile. */
export function MyProfileRedirect() {
  const me = useQuery({
    queryKey: ['employees', 'me'],
    queryFn: async () => {
      const { data, error } = await supabase.from('employees_v').select('id').eq('is_self', true).maybeSingle()
      if (error) throw error
      return data?.id as string | undefined
    },
  })
  if (me.isPending) return <PageLoader />
  if (!me.data) return <EmptyState title="No employee record is linked to your login" />
  return <Navigate to={`/employees/${me.data}`} replace />
}

export default function EmployeeProfilePage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const ctx = useMyContext()
  const profile = useEmployeeProfile(id)
  const structure = useOrgStructure()
  // ?tab=financial opens the Financial tab directly (linked from the Compensation page).
  const [searchParams] = useSearchParams()
  const [tab, setTab] = useState<Tab>(searchParams.get('tab') === 'financial' ? 'financial' : 'personal')
  const [dialog, setDialog] = useState<DialogKey>(null)
  const files = useEmployeeFiles(ctx.organization?.id, id)

  if (profile.isPending || structure.isPending) return <PageLoader />
  if (profile.isError) return <Alert>{errorMessage(profile.error)}</Alert>
  if (structure.isError) return <Alert>{errorMessage(structure.error)}</Alert>

  const p = profile.data
  const e = p.employee
  const can = (k: string) => ctx.permissions.includes(k)
  const canEdit = (p.editable_fields?.length ?? 0) > 0
  const canTransfer = can('employees.transfer') && e.status === 'active'
  const canReporting = can('employees.reporting') && e.status === 'active'
  const canStatus = can('employees.deactivate') && !e.is_self
  const canPortal = (can('employees.portal_access') || can('users.reset_password')) && (e.status === 'active' || e.has_portal_access)
  const showFinancial = canSeeFinancialTab(ctx.permissions, e.is_self)
  const close = () => setDialog(null)

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      {can('employees.view') && (
        <button onClick={() => navigate('/employees')} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800">
          <ArrowLeft className="size-4" /> Employees
        </button>
      )}

      <Card>
        <div className="flex flex-wrap items-start gap-5">
          {files.data?.photo ? (
            <img src={files.data.photo.url} alt="" className="size-16 shrink-0 rounded-2xl object-cover ring-1 ring-slate-200" />
          ) : (
            <div className="flex size-16 shrink-0 items-center justify-center rounded-2xl bg-primary-100 text-xl font-semibold text-primary-700" aria-hidden>
              {e.full_name.split(/s+/).map((x) => x[0]).slice(0, 2).join('').toUpperCase()}
            </div>
          )}
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-2xl font-semibold text-slate-900">{e.full_name}</h2>
              <StatusBadge status={e.status} />
              {e.is_self && <Badge tone="orange">You</Badge>}
            </div>
            <p className="mt-1 text-sm text-slate-600">
              {e.designation_name ?? 'No designation'}
              {e.grade_code && <span className="ml-1 font-mono text-xs text-slate-500">({e.grade_code})</span>}
              {e.department_name && <> · {e.department_name}</>}
            </p>
            <div className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-sm text-slate-500">
              <span className="inline-flex items-center gap-1.5"><BadgeCheck className="size-4" />Card <span className="font-mono text-slate-700">{e.card_id}</span></span>
              {e.branch_name && <span className="inline-flex items-center gap-1.5"><MapPin className="size-4" />{e.branch_name} / {e.office_name}</span>}
              {e.join_date && <span className="inline-flex items-center gap-1.5"><CalendarDays className="size-4" />Joined {formatDate(e.join_date)}</span>}
              {e.phone && <span className="inline-flex items-center gap-1.5"><Phone className="size-4" />{e.phone}</span>}
              {e.email && <span className="inline-flex items-center gap-1.5"><Mail className="size-4" />{e.email}</span>}
              <span className="inline-flex items-center gap-1.5">
                <KeyRound className="size-4" />{e.has_portal_access ? `Portal: ${e.portal_role_name}` : 'No portal access'}
              </span>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            {canEdit && <Button variant="secondary" onClick={() => setDialog('edit')}><Pencil className="size-4" />Edit</Button>}
            <Button variant="secondary" onClick={() => setDialog('idcard')}><IdCard className="size-4" />ID card</Button>
            {canTransfer && <Button variant="secondary" onClick={() => setDialog('transfer')}><ArrowRightLeft className="size-4" />Transfer / promote</Button>}
            {canPortal && <Button variant="secondary" onClick={() => setDialog('portal')}><KeyRound className="size-4" />Portal access</Button>}
            {canStatus && (
              <Button variant={e.status === 'active' ? 'danger' : 'primary'} onClick={() => setDialog('status')}>
                <Power className="size-4" />{e.status === 'active' ? 'Deactivate' : 'Reactivate'}
              </Button>
            )}
          </div>
        </div>
      </Card>

      <Tabs<Tab>
        tabs={[
          { key: 'personal', label: 'Personal info' },
          { key: 'history', label: 'History', count: p.history?.length },
          { key: 'reporting', label: 'Reporting chain' },
          ...(showFinancial ? [{ key: 'financial' as const, label: 'Financial' }] : []),
        ]}
        value={tab}
        onChange={setTab}
      />

      {tab === 'personal' && (
        <div className="grid gap-6 lg:grid-cols-2">
          <Card>
            <h3 className="mb-4 font-semibold text-slate-900">Personal</h3>
            <dl className="grid grid-cols-2 gap-4">
              <Field label="Full name" value={e.full_name} />
              <Field label="Date of birth" value={e.date_of_birth && formatDate(e.date_of_birth)} />
              <Field label="Gender" value={e.gender && labelOf(GENDERS, e.gender)} />
              <Field label="Marital status" value={e.marital_status && labelOf(MARITAL, e.marital_status)} />
              <Field label="Religion" value={e.religion && labelOf(RELIGIONS, e.religion)} />
              <Field label="Blood group" value={e.blood_group && labelOf(BLOOD_GROUPS, e.blood_group)} />
              <Field label="NID number" value={e.nid_number} />
            </dl>
          </Card>
          <Card>
            <h3 className="mb-4 font-semibold text-slate-900">Job</h3>
            <dl className="grid grid-cols-2 gap-4">
              <Field label="Card ID" value={<span className="font-mono">{e.card_id}</span>} />
              <Field label="Employment type" value={e.employment_type && labelOf(EMPLOYMENT_TYPES, e.employment_type)} />
              <Field label="Department" value={e.department_name ?? ''} />
              <Field label="Designation" value={e.designation_name ? `${e.designation_name} (${e.grade_code})` : ''} />
              <Field label="Branch" value={e.branch_name ?? ''} />
              <Field label="Office" value={e.office_name ?? ''} />
              <Field label="Operation" value={e.operation_name ?? ''} />
              <Field label="Join date" value={e.join_date && formatDate(e.join_date)} />
              <Field label="Probation ends" value={e.probation_end_date && formatDate(e.probation_end_date)} />
              <Field label="Confirmed on" value={e.confirmation_date && formatDate(e.confirmation_date)} />
              {e.exit_date && <Field label="Exit date" value={formatDate(e.exit_date)} />}
            </dl>
          </Card>
          <Card>
            <h3 className="mb-4 font-semibold text-slate-900">Contact & address</h3>
            <dl className="grid gap-4 sm:grid-cols-2">
              <Field label="Phone" value={e.phone} />
              <Field label="Email" value={e.email} />
              <Field label="Present address" value={e.present_address} />
              <Field label="Permanent address" value={e.permanent_address} />
            </dl>
          </Card>
          <EmployeeFilesCard profile={p} />
          <Card>
            <h3 className="mb-4 font-semibold text-slate-900">Nominees</h3>
            {p.nominees === null ? (
              <p className="text-sm italic text-slate-400">Hidden for your role</p>
            ) : p.nominees.length === 0 ? (
              <p className="text-sm text-slate-500">No nominees.</p>
            ) : (
              <ul className="divide-y divide-slate-100">
                {p.nominees.map((n) => (
                  <li key={n.id} className="flex items-center justify-between py-2 text-sm">
                    <span className="font-medium text-slate-800">{n.name}</span>
                    <span className="text-slate-500">{n.relation}{n.phone ? ` · ${n.phone}` : ''}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      )}

      {tab === 'history' && (
        <Card>
          {!p.history?.length ? (
            <p className="text-sm text-slate-500">No history yet.</p>
          ) : (
            <ol className="relative space-y-6 border-l border-slate-200 pl-6">
              {p.history.map((h) => {
                const Icon = EVENT_ICON[h.event_type] ?? BadgeCheck
                return (
                  <li key={h.id} className="relative">
                    <span className="absolute -left-[37px] flex size-6 items-center justify-center rounded-full bg-primary-100 text-primary-700 ring-4 ring-white">
                      <Icon className="size-3.5" aria-hidden />
                    </span>
                    <div className="flex flex-wrap items-baseline gap-x-3">
                      <p className="font-medium text-slate-900">{EVENT_LABELS[h.event_type] ?? h.event_type}</p>
                      <p className="text-xs text-slate-500">Effective {formatDate(h.effective_date)}</p>
                    </div>
                    <p className="mt-0.5 text-sm text-slate-600">{describeChange(h)}</p>
                    {h.reason && <p className="mt-0.5 text-sm italic text-slate-500">“{h.reason}”</p>}
                    <p className="mt-0.5 text-xs text-slate-400">Recorded by {h.created_by_name || 'system'} on {formatDate(h.created_at)}</p>
                  </li>
                )
              })}
            </ol>
          )}
        </Card>
      )}

      {tab === 'financial' && showFinancial && (
        <FinancialTab employee={{ id: e.id, full_name: e.full_name, join_date: e.join_date, status: e.status, is_self: e.is_self }} />
      )}

      {tab === 'reporting' && (
        <div className="grid gap-6 lg:grid-cols-2">
          <Card>
            <div className="mb-4 flex items-center justify-between">
              <h3 className="font-semibold text-slate-900">Reports to</h3>
              {canReporting && <Button variant="secondary" onClick={() => setDialog('reporting')}><Network className="size-4" />Change</Button>}
            </div>
            {LINE_TYPES.map((l) => {
              const current = p.reporting?.find((r) => r.line_type === l.value && !r.end_date)
              return (
                <div key={l.value} className="flex items-center justify-between border-b border-slate-100 py-2.5 text-sm last:border-0">
                  <span className="text-slate-500">{l.label}</span>
                  {current ? (
                    <Link to={`/employees/${current.manager_id}`} className="font-medium text-primary-700 hover:underline">
                      {current.manager_name} <span className="font-mono text-xs text-slate-400">{current.manager_card_id}</span>
                      {current.manager_status !== 'active' && <Badge tone="red">Inactive</Badge>}
                    </Link>
                  ) : (
                    <span className="text-slate-400">—</span>
                  )}
                </div>
              )
            })}
          </Card>
          <Card>
            <h3 className="mb-4 font-semibold text-slate-900">Direct reports</h3>
            {!p.direct_reports?.length ? (
              <p className="text-sm text-slate-500">Nobody reports to {e.is_self ? 'you' : 'this employee'}.</p>
            ) : (
              <ul className="divide-y divide-slate-100">
                {p.direct_reports.map((d) => (
                  <li key={d.id + d.line_type} className="flex items-center justify-between py-2 text-sm">
                    <Link to={`/employees/${d.id}`} className="font-medium text-primary-700 hover:underline">{d.full_name}</Link>
                    <span className="text-xs text-slate-500">{labelOf(LINE_TYPES, d.line_type)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
          <Card className="lg:col-span-2">
            <h3 className="mb-4 font-semibold text-slate-900">Reporting history</h3>
            {!p.reporting?.length ? (
              <p className="text-sm text-slate-500">No reporting lines yet.</p>
            ) : (
              <ul className="divide-y divide-slate-100 text-sm">
                {p.reporting.map((r) => (
                  <li key={r.id} className="flex flex-wrap items-center justify-between gap-2 py-2.5">
                    <span>
                      <span className="text-slate-500">{labelOf(LINE_TYPES, r.line_type)}:</span>{' '}
                      <span className="font-medium text-slate-800">{r.manager_name}</span>
                      {r.reason && <span className="ml-2 italic text-slate-400">“{r.reason}”</span>}
                    </span>
                    <span className="text-xs text-slate-500">
                      {formatDate(r.start_date)} → {r.end_date ? formatDate(r.end_date) : <Badge tone="green">Current</Badge>}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      )}

      <EditEmployeeDialog profile={p} open={dialog === 'edit'} onClose={close} />
      <TransferDialog profile={p} open={dialog === 'transfer'} onClose={close} structure={structure.data} />
      <ReportingDialog profile={p} open={dialog === 'reporting'} onClose={close} />
      <StatusDialog profile={p} open={dialog === 'status'} onClose={close} structure={structure.data} />
      <PortalDialog profile={p} open={dialog === 'portal'} onClose={close} />
      <IdCardDialog profile={p} open={dialog === 'idcard'} onClose={close} />
    </div>
  )
}
