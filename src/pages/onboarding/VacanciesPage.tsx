import { useMemo, useState } from 'react'
import { Plus } from 'lucide-react'
import type { Vacancy } from '@/onboarding-process/core/types'
import { OPEN_STATUSES, VACANCY_STATUS_LABEL } from '@/onboarding-process/core/workflow'
import { useVacancies } from '@/lib/onboarding'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, PageLoader } from '@/components/ui'
import { PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { REASON_LABEL, VacancyDialog, vacancyStatusTone } from './dialogs/VacancyDialog'
import { DraftVacancyDialog } from './dialogs/DraftVacancyDialog'

type Filter = 'action' | 'open' | 'closed'

/** Vacancies drafted from workload, separations or requests, with the review → approval flow. */
export default function VacanciesPage() {
  const ctx = useMyContext()
  const vacancies = useVacancies()
  const [filter, setFilter] = useState<Filter>('action')
  const [openId, setOpenId] = useState<string | null>(null)
  const [drafting, setDrafting] = useState(false)
  const canReview = ctx.permissions.includes('vacancy.review')
  const canApprove = ctx.permissions.includes('vacancy.approve')
  const userId = ctx.user?.id ?? null

  const groups = useMemo(() => {
    const all = vacancies.data ?? []
    const needsMe = (v: Vacancy) => (canReview && (v.status === 'draft' || v.status === 'on_hold'))
      || (canApprove && v.status === 'hr_reviewed' && v.hr_reviewed_by !== userId)
    return {
      action: all.filter(needsMe),
      open: all.filter((v) => OPEN_STATUSES.includes(v.status)),
      closed: all.filter((v) => !OPEN_STATUSES.includes(v.status)),
    }
  }, [vacancies.data, canReview, canApprove, userId])
  const open = vacancies.data?.find((v) => v.id === openId)

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Vacancies"
        description="Drafted automatically when someone leaves or a department is overloaded. HR reviews, someone else approves."
        actions={ctx.permissions.includes('vacancy.request') && <Button onClick={() => setDrafting(true)}><Plus className="size-4" />Request vacancy</Button>} />
      {vacancies.isPending ? <PageLoader /> : vacancies.isError ? <Alert>{errorMessage(vacancies.error)}</Alert> : (
        <>
          <Tabs value={filter} onChange={setFilter} tabs={[
            { key: 'action', label: 'Needs my action', count: groups.action.length },
            { key: 'open', label: 'Open', count: groups.open.length },
            { key: 'closed', label: 'Closed', count: groups.closed.length },
          ]} />
          {groups[filter].length === 0 ? (
            <EmptyState title={filter === 'action' ? 'Nothing waiting for you' : 'No vacancies here'}>
              Vacancies appear when a person in a sanctioned position leaves, or when the monthly workload suggests hiring.
            </EmptyState>
          ) : (
            <Table minWidth={760} head={(
              <tr><th className={th}>Position</th><th className={th}>Seats</th><th className={th}>Reason</th><th className={th}>Origin</th>
                <th className={th}>Budget</th><th className={th}>Status</th><th className={th}>Created</th></tr>
            )}>
              {groups[filter].map((vacancy) => (
                <tr key={vacancy.id} className="cursor-pointer hover:bg-slate-50" onClick={() => setOpenId(vacancy.id)}>
                  <td className={td}>
                    <button type="button" className="text-left font-medium text-slate-900 hover:text-primary-700" onClick={() => setOpenId(vacancy.id)}>
                      {vacancy.designation_name}
                    </button>
                    <p className="text-xs text-slate-400">{vacancy.department_name} · {vacancy.grade_code}</p>
                  </td>
                  <td className={`${td} tabular-nums`}>{vacancy.seats}</td>
                  <td className={td}>{REASON_LABEL[vacancy.reason]}</td>
                  <td className={td}>{vacancy.origin === 'separation' ? 'Someone left' : vacancy.origin === 'snapshot' ? 'Workload' : 'Request'}</td>
                  <td className={td}>{vacancy.budget_status === 'blocked' ? <Badge tone="red">Over budget</Badge>
                    : vacancy.budget_status === 'ok' ? <Badge tone="green">Within</Badge> : <span className="text-slate-400">—</span>}</td>
                  <td className={td}><Badge tone={vacancyStatusTone(vacancy.status)}>{VACANCY_STATUS_LABEL[vacancy.status]}</Badge></td>
                  <td className={td}>{formatDate(vacancy.created_at)}</td>
                </tr>
              ))}
            </Table>
          )}
        </>
      )}
      {open && <VacancyDialog key={open.id} vacancy={open} onClose={() => setOpenId(null)} />}
      {drafting && <DraftVacancyDialog onClose={() => setDrafting(false)} />}
    </div>
  )
}
