// One vacancy: the workload behind it, its history, and the review / approval
// actions the viewer may take (maker-checker is enforced by the database).
import { useState } from 'react'
import type { Vacancy } from '@/onboarding-process/core/types'
import type { VacancyAction } from '@/onboarding-process/core/workflow'
import { NEEDS_REASON, VACANCY_STATUS_LABEL, availableActions } from '@/onboarding-process/core/workflow'
import { useWorkforceAction } from '@/lib/onboarding'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { formatMonth, formatTaka } from '@/lib/payroll'
import { Alert, Badge, Button } from '@/components/ui'
import { Checkbox, Modal, Textarea } from '@/components/kit'
import { WorkloadCard } from '../WorkloadCard'

const ACTION_LABEL: Record<VacancyAction, string> = {
  forward: 'Send for approval', hold: 'Put on hold', reject: 'Reject', approve: 'Approve',
  decide_hold: 'Hold', decide_reject: 'Reject', send_back: 'Send back to HR', cancel: 'Cancel vacancy',
}

export const REASON_LABEL = { replacement: 'Replacement', new_position: 'New position' } as const

export function vacancyStatusTone(status: Vacancy['status']) {
  return status === 'approved' || status === 'filled' ? 'green'
    : status === 'rejected' || status === 'cancelled' ? 'red'
      : status === 'hr_reviewed' ? 'orange' : 'slate'
}

export function VacancyDialog({ vacancy, onClose }: { vacancy: Vacancy; onClose: () => void }) {
  const ctx = useMyContext()
  const review = useWorkforceAction<{ p_vacancy_id: string; p_action: string; p_note: string | null; p: Record<string, unknown> }>('review_vacancy')
  const decide = useWorkforceAction<{ p_vacancy_id: string; p_decision: string; p_note: string | null; p_over_budget: boolean }>('decide_vacancy')
  const cancel = useWorkforceAction<{ p_vacancy_id: string; p_reason: string }>('cancel_vacancy')
  const [pending, setPending] = useState<VacancyAction | null>(null)
  const [note, setNote] = useState('')
  const [seats, setSeats] = useState(String(vacancy.seats))
  const [overBudget, setOverBudget] = useState(false)
  const actions = availableActions(vacancy, {
    userId: ctx.user?.id ?? null,
    canReview: ctx.permissions.includes('vacancy.review'),
    canApprove: ctx.permissions.includes('vacancy.approve'),
  })
  const busy = review.isPending || decide.isPending || cancel.isPending
  const error = review.error ?? decide.error ?? cancel.error
  const figures = vacancy.latest_snapshot ?? vacancy.recommendation

  const run = (action: VacancyAction) => {
    const done = { onSuccess: onClose }
    const text = note.trim() || null
    if (action === 'forward' || action === 'hold' || action === 'reject') {
      review.mutate({ p_vacancy_id: vacancy.id, p_action: action, p_note: text,
        p: vacancy.status === 'draft' && Number(seats) !== vacancy.seats ? { seats: Number(seats) } : {} }, done)
    } else if (action === 'cancel') {
      cancel.mutate({ p_vacancy_id: vacancy.id, p_reason: note.trim() }, done)
    } else {
      const decision = action === 'decide_hold' ? 'hold' : action === 'decide_reject' ? 'reject' : action
      decide.mutate({ p_vacancy_id: vacancy.id, p_decision: decision, p_note: text, p_over_budget: action === 'approve' && overBudget }, done)
    }
  }

  return (
    <Modal open onClose={onClose} size="xl" title={`${vacancy.designation_name} · ${vacancy.department_name}`}
      description={<>{vacancy.seats} seat(s) · {REASON_LABEL[vacancy.reason]} · <Badge tone={vacancyStatusTone(vacancy.status)}>{VACANCY_STATUS_LABEL[vacancy.status]}</Badge></>}>
      <div className="grid gap-5 lg:grid-cols-[1fr_1.1fr]">
        <div className="space-y-4">
          <dl className="grid grid-cols-2 gap-3 text-sm">
            <div><dt className="text-xs text-slate-500">Grade</dt><dd className="font-medium">{vacancy.grade_code}</dd></div>
            <div><dt className="text-xs text-slate-500">Origin</dt><dd className="font-medium">
              {vacancy.origin === 'separation' ? `${vacancy.separated_employee_name ?? 'A person'} left`
                : vacancy.origin === 'snapshot' ? `Workload ${formatMonth(vacancy.period_month)}` : `Requested by ${vacancy.drafted_by_name ?? '—'}`}
            </dd></div>
            <div><dt className="text-xs text-slate-500">Estimated monthly cost</dt><dd className="font-medium">
              {vacancy.estimated_monthly_cost === undefined ? 'Hidden' : formatTaka(vacancy.estimated_monthly_cost)}</dd></div>
            <div><dt className="text-xs text-slate-500">Budget</dt><dd className="font-medium">
              {vacancy.budget_status === 'blocked' ? <Badge tone="red">Over budget</Badge> : vacancy.budget_status === 'ok' ? <Badge tone="green">Within budget</Badge> : 'Not checked'}
            </dd></div>
            {vacancy.office_name && <div><dt className="text-xs text-slate-500">Office</dt><dd className="font-medium">{vacancy.office_name}</dd></div>}
          </dl>
          {vacancy.note && <p className="rounded-xl bg-slate-50 p-3 text-sm text-slate-700">{vacancy.note}</p>}
          {vacancy.decision_note && <Alert tone="info">Decision note: {vacancy.decision_note}</Alert>}
          <div>
            <p className="mb-2 text-sm font-medium text-slate-900">History</p>
            <ol className="space-y-2 border-l border-slate-200 pl-4 text-sm">
              {vacancy.events.map((event, index) => (
                <li key={index} className="relative">
                  <span className="absolute -left-[21px] top-1.5 size-2.5 rounded-full bg-primary-500" />
                  <p className="font-medium text-slate-800">{event.event.replaceAll('_', ' ')}{event.to_status ? ` → ${VACANCY_STATUS_LABEL[event.to_status as Vacancy['status']] ?? event.to_status}` : ''}</p>
                  <p className="text-xs text-slate-500">{event.actor_name ?? 'System'} · {formatDateTime(event.created_at)}</p>
                  {event.note && <p className="text-xs text-slate-600">{event.note}</p>}
                </li>
              ))}
            </ol>
          </div>
        </div>
        <div className="space-y-4">
          {figures ? (
            <WorkloadCard name={`Workload · ${formatMonth(figures.period_month)}`} figures={figures} />
          ) : <Alert tone="info">No workload snapshot for this department yet. Build one on the Workforce page to see the numbers.</Alert>}
          {actions.length > 0 && (
            <div className="space-y-3 rounded-2xl bg-slate-50 p-4">
              {error && <Alert>{errorMessage(error)}</Alert>}
              {vacancy.status === 'draft' && actions.includes('forward') && (
                <label className="flex items-center gap-2 text-sm text-slate-700">Seats
                  <input inputMode="numeric" value={seats} onChange={(e) => setSeats(e.target.value)} aria-label="Seats"
                    className="w-20 rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm" />
                </label>
              )}
              {actions.includes('approve') && vacancy.budget_status === 'blocked' && (
                <Checkbox checked={overBudget} onChange={setOverBudget} label="Approve over the department budget (reason required)" />
              )}
              <Textarea label="Reason or note" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)}
                hint="A reason of 5+ characters is needed to hold, reject, send back, cancel or approve over budget." />
              <div className="flex flex-wrap gap-2">
                {actions.map((action) => (
                  <Button key={action} variant={action === 'approve' || action === 'forward' ? 'primary' : action === 'cancel' || action.endsWith('reject') ? 'danger' : 'secondary'}
                    loading={busy && pending === action}
                    disabled={busy || ((NEEDS_REASON.includes(action) || (action === 'approve' && overBudget)) && note.trim().length < 5)}
                    onClick={() => { setPending(action); run(action) }}>
                    {ACTION_LABEL[action]}
                  </Button>
                ))}
              </div>
              {vacancy.status === 'hr_reviewed' && vacancy.hr_reviewed_by === ctx.user?.id && (
                <p className="text-xs text-slate-500">You sent this for approval, so someone else must decide it.</p>
              )}
            </div>
          )}
        </div>
      </div>
    </Modal>
  )
}
