// Helpdesk (C2): labels, ticket numbers, SLA display and the setup form checks. The SLA clock
// itself (office time) runs in the database; these only format and validate.

export const PRIORITIES = ['low', 'medium', 'high', 'critical'] as const
export type Priority = (typeof PRIORITIES)[number]
export const PRIORITY_LABEL: Record<Priority, { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  low: { label: 'Low', tone: 'slate' },
  medium: { label: 'Medium', tone: 'green' },
  high: { label: 'High', tone: 'orange' },
  critical: { label: 'Critical', tone: 'red' },
}

export type TicketStatus = 'open' | 'in_progress' | 'waiting' | 'resolved' | 'closed'
export const STATUS_LABEL: Record<TicketStatus, { label: string; tone: 'slate' | 'orange' | 'green' | 'red' }> = {
  open: { label: 'Open', tone: 'orange' },
  in_progress: { label: 'In progress', tone: 'orange' },
  waiting: { label: 'Waiting for you', tone: 'slate' },
  resolved: { label: 'Resolved', tone: 'green' },
  closed: { label: 'Closed', tone: 'slate' },
}
/** Staff see "waiting" from their side. */
export const statusLabel = (s: TicketStatus, staff: boolean) => (s === 'waiting' && staff ? 'Waiting for the employee' : STATUS_LABEL[s].label)

export const ticketNo = (n: number) => `#${String(n).padStart(4, '0')}`

/** Office minutes as "2 h 30 min" (an office day is 9 hours, so no day unit). */
export function officeDuration(minutes: number): string {
  const m = Math.abs(Math.round(minutes))
  const h = Math.floor(m / 60)
  const rest = m % 60
  if (h === 0) return `${rest} min`
  return rest ? `${h} h ${rest} min` : `${h} h`
}

/** "3 h 10 min left" or "overdue by 40 min"; null when the clock is stopped. */
export function slaLeftLabel(minutes: number | null): string | null {
  if (minutes == null) return null
  return minutes >= 0 ? `${officeDuration(minutes)} left` : `overdue by ${officeDuration(minutes)}`
}

export type Sla = Record<Priority, { response: number; resolution: number }>

export const DEFAULT_SLA: Sla = {
  critical: { response: 60, resolution: 240 },
  high: { response: 240, resolution: 1440 },
  medium: { response: 1440, resolution: 4320 },
  low: { response: 4320, resolution: 10080 },
}

/** Same limits as save_helpdesk_settings: 15 min … 720 h, response not after resolution, 1–30 days. */
export function slaProblems(sla: Sla, autoCloseDays: number): string[] {
  const out: string[] = []
  for (const p of PRIORITIES) {
    const { response, resolution } = sla[p]
    if (![response, resolution].every((v) => Number.isInteger(v) && v >= 15 && v <= 43200)) {
      out.push(`${PRIORITY_LABEL[p].label}: give 15 minutes to 720 hours`)
    } else if (response > resolution) {
      out.push(`${PRIORITY_LABEL[p].label}: the first response cannot come after the resolution`)
    }
  }
  if (!Number.isInteger(autoCloseDays) || autoCloseDays < 1 || autoCloseDays > 30) out.push('Auto-close: 1 to 30 working days')
  return out
}

export const hoursOf = (minutes: number) => Math.round((minutes / 60) * 100) / 100
export const minutesOf = (hours: number) => Math.round(hours * 60)

/** Ticket form checks (the database repeats them). */
export function ticketProblems(t: { subject: string; description: string; category_id: string }): Partial<Record<'subject' | 'description' | 'category_id', string>> {
  const out: Partial<Record<'subject' | 'description' | 'category_id', string>> = {}
  if (t.subject.trim().length < 3) out.subject = 'At least 3 characters'
  if (t.subject.length > 200) out.subject = 'At most 200 characters'
  if (!t.description.trim()) out.description = 'Describe the problem'
  if (t.description.length > 10000) out.description = 'At most 10,000 characters'
  if (!t.category_id) out.category_id = 'Choose a category'
  return out
}

export const MAX_FILES = 5
