// Notices (C1): labels, shown status, reach figures and form checks. The database applies the
// same rules (save_notice / publish_notice); these give instant feedback in the form.

export const CATEGORIES = ['general', 'policy_update', 'event', 'urgent', 'hr_notice', 'safety'] as const
export type NoticeCategory = (typeof CATEGORIES)[number]

export const CATEGORY_LABEL: Record<NoticeCategory, { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  general: { label: 'General', tone: 'slate' },
  policy_update: { label: 'Policy update', tone: 'orange' },
  event: { label: 'Event', tone: 'green' },
  urgent: { label: 'Urgent', tone: 'red' },
  hr_notice: { label: 'HR notice', tone: 'orange' },
  safety: { label: 'Safety', tone: 'red' },
}

/** Policy updates and safety notices ask for "I have read and agree" by default. */
export const ackByDefault = (c: NoticeCategory) => c === 'policy_update' || c === 'safety'

export type ShownStatus = 'draft' | 'scheduled' | 'active' | 'expired' | 'archived'
export const STATUS_LABEL: Record<ShownStatus, { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  draft: { label: 'Draft', tone: 'slate' },
  scheduled: { label: 'Scheduled', tone: 'orange' },
  active: { label: 'Active', tone: 'green' },
  expired: { label: 'Expired', tone: 'slate' },
  archived: { label: 'Archived', tone: 'slate' },
}

export type Audience = 'all' | 'department' | 'branch' | 'employees'
export const AUDIENCE_LABEL: Record<Audience, string> = {
  all: 'All employees', department: 'Specific departments', branch: 'Specific branches', employees: 'Specific employees',
}

/** Same as private.notice_shown_status. */
export function shownStatus(n: { status: 'draft' | 'published' | 'archived'; publish_at: string | null; expires_at: string | null }, now = Date.now()): ShownStatus {
  if (n.status === 'draft') return 'draft'
  if (n.status === 'archived') return 'archived'
  if (n.publish_at && Date.parse(n.publish_at) > now) return 'scheduled'
  if (n.expires_at && Date.parse(n.expires_at) <= now) return 'expired'
  return 'active'
}

/** Share of portal users who read (or acknowledged), as a whole percent; null when nobody can read it. */
export function percentOf(part: number, whole: number): number | null {
  return whole > 0 ? Math.round((Math.min(part, whole) / whole) * 100) : null
}

export interface NoticeDraft {
  category: NoticeCategory
  title: string
  title_bn: string
  body: string
  body_bn: string
  audience: Audience
  department_ids: string[]
  branch_ids: string[]
  employee_ids: string[]
  pinned: boolean
  requires_ack: boolean
  email_copy: boolean
  publish_now: boolean
  publish_at: string // datetime-local value
  expires_at: string // datetime-local value
}

export const EMPTY_DRAFT: NoticeDraft = {
  category: 'general', title: '', title_bn: '', body: '', body_bn: '', audience: 'all', department_ids: [], branch_ids: [],
  employee_ids: [], pinned: false, requires_ack: false, email_copy: false, publish_now: true, publish_at: '', expires_at: '',
}

/** Field errors before saving; the database repeats every check. */
export function draftProblems(d: NoticeDraft, canTargetAll: boolean, now = Date.now()): Partial<Record<keyof NoticeDraft, string>> {
  const out: Partial<Record<keyof NoticeDraft, string>> = {}
  if (d.title.trim().length < 3) out.title = 'At least 3 characters'
  if (d.title.length > 200) out.title = 'At most 200 characters'
  if (!d.body.trim()) out.body = 'Write the notice text'
  if (d.body.length > 20000 || d.body_bn.length > 20000) out.body = 'At most 20,000 characters'
  if (d.title_bn && d.title_bn.trim().length < 2) out.title_bn = 'At least 2 characters'
  if (canTargetAll) {
    if (d.audience === 'department' && d.department_ids.length === 0) out.department_ids = 'Choose at least one department'
    if (d.audience === 'branch' && d.branch_ids.length === 0) out.branch_ids = 'Choose at least one branch'
    if (d.audience === 'employees' && d.employee_ids.length === 0) out.employee_ids = 'Choose at least one employee'
  }
  const publish = d.publish_now || !d.publish_at ? now : Date.parse(d.publish_at)
  if (!d.publish_now && !d.publish_at) out.publish_at = 'Pick the publish time'
  if (d.expires_at && Date.parse(d.expires_at) <= Math.max(publish, now)) out.expires_at = 'Must be after the publish time'
  return out
}

/** ISO time → value for <input type="datetime-local"> in the viewer's time zone. */
export function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export const fromLocalInput = (value: string) => (value ? new Date(value).toISOString() : null)
