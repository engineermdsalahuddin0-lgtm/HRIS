// The update digest: short items from the same numbers the dashboard shows, kept only when
// the topic is allowed for the role. Counts and statuses only: no amounts, no other people's details.
import type { Resource, UpdateItem } from './types'

export interface DashboardSnapshot {
  myDay: { checkedInAt: string | null; late: boolean; shift: string }
  myLeave: { casualLeft: number; sickLeft: number; pending: number }
  myPayslip: { month: string; ready: boolean }
  teamToday: { present: number; late: number; absent: number }
  approvals: { leave: number; overtime: number; swaps: number }
  headcount: { active: number; newThisMonth: number }
  payroll: { month: string; status: 'draft' | 'calculated' | 'reviewed' | 'approved' | 'paid' | 'locked' | null }
  hiring: { openVacancies: number; applicantsWaiting: number }
}

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`

export function buildUpdates(allowed: Set<string>, snap: DashboardSnapshot, readable: Resource[]): UpdateItem[] {
  const items: UpdateItem[] = []
  const add = (item: UpdateItem) => allowed.has(item.topicKey) && items.push(item)

  add(snap.myDay.checkedInAt
    ? { key: 'my_day', topicKey: 'up.my_day', title: `You checked in at ${snap.myDay.checkedInAt}`, detail: snap.myDay.late ? `Late for ${snap.myDay.shift}` : `On time · ${snap.myDay.shift}`, link: '/attendance/me', tone: snap.myDay.late ? 'action' : 'good' }
    : { key: 'my_day', topicKey: 'up.my_day', title: 'You have not checked in today', detail: snap.myDay.shift, link: '/attendance/me', tone: 'action' })

  add({
    key: 'my_leave', topicKey: 'up.my_leave', title: `${snap.myLeave.casualLeft} casual, ${snap.myLeave.sickLeft} sick leave left`,
    detail: snap.myLeave.pending ? `${plural(snap.myLeave.pending, 'request')} waiting for approval` : 'No pending requests', link: '/leave', tone: 'info',
  })

  if (snap.myPayslip.ready) {
    add({ key: 'my_payslip', topicKey: 'up.my_payslip', title: `Your ${snap.myPayslip.month} payslip is ready`, detail: 'Open it to see the details', link: '/payslips', tone: 'good' })
  }

  add({
    key: 'team_today', topicKey: 'up.team_today', title: `Team today: ${snap.teamToday.present} present`,
    detail: `${snap.teamToday.late} late · ${snap.teamToday.absent} absent`, link: '/attendance', tone: snap.teamToday.absent ? 'action' : 'info',
  })

  const waiting = snap.approvals.leave + snap.approvals.overtime + snap.approvals.swaps
  if (waiting > 0) {
    const parts = [
      snap.approvals.leave && plural(snap.approvals.leave, 'leave'),
      snap.approvals.overtime && `${snap.approvals.overtime} overtime`,
      snap.approvals.swaps && plural(snap.approvals.swaps, 'shift swap'),
    ].filter(Boolean)
    add({ key: 'approvals', topicKey: 'up.approvals', title: `${plural(waiting, 'request')} wait for you`, detail: parts.join(' · '), link: '/leave', tone: 'action' })
  }

  add({
    key: 'headcount', topicKey: 'up.headcount', title: `${snap.headcount.active} active employees`,
    detail: `${snap.headcount.newThisMonth} joined this month`, link: '/employees', tone: 'info',
  })

  if (snap.payroll.status) {
    add({ key: 'payroll', topicKey: 'up.payroll_status', title: `${snap.payroll.month} payroll: ${snap.payroll.status}`, detail: 'Status only; open the run for figures', link: '/payroll', tone: snap.payroll.status === 'locked' ? 'good' : 'action' })
  }

  add({
    key: 'hiring', topicKey: 'up.hiring', title: `${snap.hiring.openVacancies} open ${snap.hiring.openVacancies === 1 ? 'vacancy' : 'vacancies'}`,
    detail: `${plural(snap.hiring.applicantsWaiting, 'applicant')} waiting for screening`, link: '/job-posts', tone: 'info',
  })

  // Newest readable resources from the last 14 days.
  const cutoff = Date.now() - 14 * 24 * 3600 * 1000
  for (const r of readable.filter((r) => Date.parse(r.uploadedAt) >= cutoff).slice(0, 3)) {
    add({ key: `res_${r.id}`, topicKey: 'up.new_resources', title: `New: ${r.name}`, detail: 'Ask me anything about it', link: '', tone: 'info' })
  }
  return items
}

/** The digest as plain lines, the only "data" the model may receive besides passages. */
export const digestText = (items: UpdateItem[]) => items.map((i) => `- ${i.title} (${i.detail})`).join('\n')
