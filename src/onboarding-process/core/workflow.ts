// Vacancy status machine. The database enforces every transition
// (review_vacancy / decide_vacancy / cancel_vacancy); this copy only decides
// which buttons to show for the viewer.
import type { VacancyStatus } from './types'

export type VacancyAction = 'forward' | 'hold' | 'reject' | 'approve' | 'decide_hold' | 'decide_reject' | 'send_back' | 'cancel'

export const VACANCY_STATUS_LABEL: Record<VacancyStatus, string> = {
  draft: 'Draft', hr_reviewed: 'Waiting for approval', approved: 'Approved', on_hold: 'On hold',
  rejected: 'Rejected', cancelled: 'Cancelled', filled: 'Filled',
}

export const OPEN_STATUSES: VacancyStatus[] = ['draft', 'hr_reviewed', 'approved', 'on_hold']

/** Actions that need a written reason (at least 5 characters). */
export const NEEDS_REASON: VacancyAction[] = ['hold', 'reject', 'decide_hold', 'decide_reject', 'send_back', 'cancel']

export interface Viewer { userId: string | null; canReview: boolean; canApprove: boolean }

export function availableActions(
  vacancy: { status: VacancyStatus; hr_reviewed_by: string | null },
  viewer: Viewer,
): VacancyAction[] {
  const actions: VacancyAction[] = []
  if (viewer.canReview) {
    if (vacancy.status === 'draft') actions.push('forward', 'hold', 'reject')
    if (vacancy.status === 'on_hold') actions.push('forward', 'reject')
  }
  // Maker-checker: the person who forwarded it never decides it.
  if (viewer.canApprove && vacancy.status === 'hr_reviewed' && vacancy.hr_reviewed_by !== viewer.userId) {
    actions.push('approve', 'decide_hold', 'decide_reject', 'send_back')
  }
  if (viewer.canReview && OPEN_STATUSES.includes(vacancy.status)) actions.push('cancel')
  return actions
}
