// Offers and joining (R6 / R7): labels, the joining checklist, the feedback questions and
// the four documents HR prints for the new employee to sign. Documents are plain HTML built
// here (every value escaped) and printed from the browser.

export type OfferStatus = 'draft' | 'approved' | 'sent' | 'accepted' | 'declined' | 'expired' | 'withdrawn'
export const OFFER_STATUS_LABEL: Record<OfferStatus, string> = {
  draft: 'Draft (needs approval)', approved: 'Approved, not sent', sent: 'Sent, waiting for reply', accepted: 'Accepted',
  declined: 'Declined', expired: 'Expired', withdrawn: 'Withdrawn',
}

export type PrehireStatus = 'pending' | 'submitted' | 'returned' | 'verified'
export const PREHIRE_STATUS_LABEL: Record<PrehireStatus, string> = {
  pending: 'Form not filled yet', submitted: 'Form submitted — check it', returned: 'Returned to the applicant', verified: 'Verified',
}

export type TaskKey = 'photo_copied' | 'documents_signed' | 'id_card' | 'portal_access' | 'reporting_manager' | 'workstation' | 'orientation'
export const TASK_LABEL: Record<TaskKey, string> = {
  photo_copied: 'Photo copied to the employee profile',
  documents_signed: 'Four documents signed and scans uploaded',
  id_card: 'ID card printed and handed over',
  portal_access: 'Portal login created (Employee profile → Portal access)',
  reporting_manager: 'Reporting manager set',
  workstation: 'Desk, tools and email ready',
  orientation: 'Orientation / first-day briefing done',
}

export type DocumentKind = 'appointment_letter' | 'joining_report' | 'nominee_form' | 'code_of_conduct'
export const DOCUMENT_LABEL: Record<DocumentKind, string> = {
  appointment_letter: 'Appointment letter', joining_report: 'Joining report', nominee_form: 'Nominee form',
  code_of_conduct: 'Code of conduct acknowledgement',
}

export const FEEDBACK_QUESTIONS = [
  { key: 'overall', label: 'Overall, how was your recruitment experience?' },
  { key: 'recruiter_behaviour', label: 'How did the HR team and interviewers treat you?' },
  { key: 'clarity', label: 'Were the job, salary and next steps explained clearly?' },
  { key: 'first_day', label: 'How was your first day?' },
] as const
export type FeedbackKey = (typeof FEEDBACK_QUESTIONS)[number]['key']

export const NID_PATTERN = /^([0-9]{10}|[0-9]{13}|[0-9]{17})$/

export function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
}

const taka = (n: number) => `Tk ${new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(n)}`
const longDate = (iso: string | null | undefined) =>
  iso ? new Date(`${iso.slice(0, 10)}T00:00:00Z`).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }) : '—'

export interface CaseFacts {
  company: { name: string }
  employee: { card_id: string; full_name: string; designation: string | null; department: string | null; office: string | null
              branch: string | null; present_address: string | null; permanent_address: string | null; date_of_birth: string | null
              probation_end_date: string | null; employment_type: string }
  offer: { gross: number; joining_date: string; probation_months: number; terms: string | null }
  nominees: { name: string; relation: string; phone: string | null }[]
}

const sign = (left: string, right: string) =>
  `<div class="signs"><div><div class="line"></div>${left}</div><div><div class="line"></div>${right}</div></div>`

/** Body of one document (inside the print page). Values are escaped. */
export function documentBody(kind: DocumentKind, f: CaseFacts, today: string): string {
  const e = f.employee
  const name = escapeHtml(e.full_name)
  const company = escapeHtml(f.company.name)
  const head = `<p class="meta">${company}<br>Date: ${escapeHtml(longDate(today))}</p>`
  if (kind === 'appointment_letter') {
    return `${head}<h1>Appointment letter</h1>
<p>To<br><b>${name}</b><br>${escapeHtml(e.present_address ?? '')}</p>
<p>Dear ${name},</p>
<p>We are pleased to appoint you as <b>${escapeHtml(e.designation)}</b> in the ${escapeHtml(e.department)} department at
${escapeHtml(e.office)}${e.branch ? `, ${escapeHtml(e.branch)}` : ''}, with effect from <b>${escapeHtml(longDate(f.offer.joining_date))}</b>, on the following terms:</p>
<ol>
<li>Employee ID: ${escapeHtml(e.card_id)}. Employment type: ${escapeHtml(e.employment_type.replace('_', ' '))}.</li>
<li>Monthly gross salary: <b>${escapeHtml(taka(f.offer.gross))}</b>, paid as per the company salary structure, less lawful deductions.</li>
<li>${f.offer.probation_months > 0 ? `Probation: ${f.offer.probation_months} months (until ${escapeHtml(longDate(e.probation_end_date))}); confirmation is in writing.` : 'No probation period.'}</li>
<li>Working hours, leave, and other conditions follow the company service rules and the applicable labour law of Bangladesh.</li>
${f.offer.terms ? `<li>${escapeHtml(f.offer.terms)}</li>` : ''}
</ol>
<p>Please sign the copy of this letter to confirm that you accept these terms.</p>
${sign('For ' + company + '<br>Authorised signatory', 'Accepted by ' + name + '<br>Signature and date')}`
  }
  if (kind === 'joining_report') {
    return `${head}<h1>Joining report</h1>
<p>I, <b>${name}</b>, have joined ${company} today as ${escapeHtml(e.designation)} (${escapeHtml(e.department)}).</p>
<table><tr><th>Employee ID</th><td>${escapeHtml(e.card_id)}</td></tr>
<tr><th>Joining date</th><td>${escapeHtml(longDate(f.offer.joining_date))}</td></tr>
<tr><th>Office</th><td>${escapeHtml(e.office)}${e.branch ? `, ${escapeHtml(e.branch)}` : ''}</td></tr>
<tr><th>Date of birth</th><td>${escapeHtml(longDate(e.date_of_birth))}</td></tr>
<tr><th>Present address</th><td>${escapeHtml(e.present_address)}</td></tr>
<tr><th>Permanent address</th><td>${escapeHtml(e.permanent_address)}</td></tr></table>
<p>I confirm that the information I gave is true.</p>
${sign('Signature of the employee', 'Received by HR')}`
  }
  if (kind === 'nominee_form') {
    const rows = f.nominees.map((n, i) => `<tr><td>${i + 1}</td><td>${escapeHtml(n.name)}</td><td>${escapeHtml(n.relation)}</td><td>${escapeHtml(n.phone ?? '')}</td><td></td></tr>`).join('')
    return `${head}<h1>Nomination form</h1>
<p>I, <b>${name}</b> (Employee ID ${escapeHtml(e.card_id)}), nominate the person(s) below to receive any amount due to me from ${company} in the event of my death.</p>
<table><tr><th>#</th><th>Name</th><th>Relation</th><th>Phone</th><th>Share (%)</th></tr>${rows}</table>
<p class="small">Fill in the shares by hand if there is more than one nominee; they must add up to 100%.</p>
${sign('Signature of the employee', 'Witness / HR')}`
  }
  return `${head}<h1>Code of conduct — acknowledgement</h1>
<p>I, <b>${name}</b> (Employee ID ${escapeHtml(e.card_id)}), confirm that I have received, read and understood the code of conduct and
service rules of ${company}, including attendance, leave, confidentiality, safety, harassment-free workplace and use of company property.</p>
<p>I agree to follow them, and I understand that breaking them may lead to disciplinary action under the company rules and the applicable law.</p>
${sign('Signature of the employee', 'HR')}`
}

/** A complete page to print (all documents, or one), with print-friendly styles. */
export function printPage(kinds: DocumentKind[], f: CaseFacts, today: string): string {
  const style = `body{font-family:"Segoe UI",system-ui,sans-serif;color:#0f172a;margin:0}
.page{padding:48px 56px;page-break-after:always;max-width:780px;margin:auto}
h1{font-size:20px;margin:24px 0 16px}.meta{text-align:right;color:#475569;font-size:13px}
p,li,td,th{font-size:14px;line-height:1.6}table{border-collapse:collapse;width:100%;margin:12px 0}
th,td{border:1px solid #cbd5e1;padding:6px 8px;text-align:left}th{background:#f8fafc;width:32%}
.signs{display:flex;justify-content:space-between;gap:48px;margin-top:64px;font-size:13px}.signs>div{flex:1}
.line{border-top:1px solid #0f172a;margin-bottom:6px}.small{font-size:12px;color:#64748b}`
  const pages = kinds.map((k) => `<section class="page">${documentBody(k, f, today)}</section>`).join('')
  return `<!doctype html><html><head><meta charset="utf-8"><title>${escapeHtml(f.employee.full_name)} — joining documents</title><style>${style}</style></head><body>${pages}</body></html>`
}
