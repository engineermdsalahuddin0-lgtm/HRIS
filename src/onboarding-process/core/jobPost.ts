// Job posts and applications (R2): labels, salary text, deadline, weights, CV
// rules and pasted applicant rows. The database checks the same rules
// (update_job_post, submit_job_application); these copies give instant feedback.
import type {
  ApplicantSource, ApplicantStatus, EducationLevel, EmploymentType, JobPostStatus, PosterTheme, SalaryFields, Weights,
} from './types'

export const DEFAULT_WEIGHTS: Weights = { ats: 10, objective: 25, written: 20, interview: 45 }

export const WEIGHT_LABEL: Record<keyof Weights, string> = {
  ats: 'CV match (ATS)', objective: 'Objective test', written: 'Written test', interview: 'Interview',
}

export const EDUCATION_LABEL: Record<EducationLevel, string> = {
  any: 'Any', ssc: 'SSC or equivalent', hsc: 'HSC or equivalent', diploma: 'Diploma',
  bachelor: "Bachelor's degree (Pass or Honours)", masters: "Master's degree", phd: 'PhD',
}

export const EMPLOYMENT_LABEL: Record<EmploymentType, string> = {
  permanent: 'Permanent', contract: 'Contract', probation: 'Probation', intern: 'Intern', part_time: 'Part time',
}

export const POST_STATUS_LABEL: Record<JobPostStatus, string> = {
  draft: 'Draft', published: 'Published', closed: 'Closed', cancelled: 'Cancelled',
}

export const SOURCE_LABEL: Record<ApplicantSource, string> = {
  form: 'Careers page', email: 'Email', linkedin: 'LinkedIn', bdjobs: 'Bdjobs', referral: 'Referral', other: 'Other',
}

export const APPLICANT_STATUS_LABEL: Record<ApplicantStatus, string> = {
  applied: 'Applied', screened_out: 'Screened out', shortlisted: 'Shortlisted', test_invited: 'Test invited',
  test_done: 'Test done', written_done: 'Written done', interview_scheduled: 'Interview scheduled',
  interviewed: 'Interviewed', selected: 'Selected', rejected: 'Rejected', offer_sent: 'Offer sent',
  offer_accepted: 'Offer accepted', offer_declined: 'Offer declined', prejoining_done: 'Pre-joining done',
  joined: 'Joined', purged: 'Removed',
}

export const POSTER_THEMES: Record<PosterTheme, { label: string; background: string; accent: string; text: string }> = {
  orange: { label: 'Orange', background: '#ea580c', accent: '#fed7aa', text: '#ffffff' },
  navy: { label: 'Navy', background: '#1e3a8a', accent: '#bfdbfe', text: '#ffffff' },
  green: { label: 'Green', background: '#166534', accent: '#bbf7d0', text: '#ffffff' },
  maroon: { label: 'Maroon', background: '#7f1d1d', accent: '#fecaca', text: '#ffffff' },
}

const taka = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 })

/** "Tk 25,000 – 32,000 / month" when the toggle is on, otherwise "Negotiable". */
export function salaryText(post: SalaryFields): string {
  if (!post.show_salary || post.salary_min == null || post.salary_max == null) return 'Negotiable'
  if (Number(post.salary_min) === Number(post.salary_max)) return `Tk ${taka.format(Number(post.salary_min))} / month`
  return `Tk ${taka.format(Number(post.salary_min))} – ${taka.format(Number(post.salary_max))} / month`
}

/** Salary toggle check, same rule as update_job_post. */
export function salaryError(post: SalaryFields): string | null {
  if (!post.show_salary) return null
  const min = Number(post.salary_min)
  const max = Number(post.salary_max)
  if (post.salary_min == null || post.salary_max == null || !(min > 0) || !(max > 0)) return 'Enter both the minimum and the maximum salary'
  if (max < min) return 'The maximum cannot be below the minimum'
  if (max > 99_999_999) return 'The salary is too large'
  return null
}

const day = (iso: string) => Date.UTC(Number(iso.slice(0, 4)), Number(iso.slice(5, 7)) - 1, Number(iso.slice(8, 10)))

/** Whole days from today to the deadline (0 = closes today, negative = passed). */
export function daysLeft(deadline: string, today: string): number {
  return Math.round((day(deadline) - day(today)) / 86_400_000)
}

export function deadlineText(deadline: string, today: string): string {
  const left = daysLeft(deadline, today)
  if (left < 0) return 'Deadline passed'
  if (left === 0) return 'Closes today'
  if (left === 1) return 'Closes tomorrow'
  return `${left} days left`
}

export function addDays(iso: string, days: number): string {
  return new Date(day(iso) + days * 86_400_000).toISOString().slice(0, 10)
}

export function weightsTotal(w: Weights): number {
  return w.ats + w.objective + w.written + w.interview
}

/** Same rule as update_job_post: whole numbers 0–100 that add up to 100. */
export function weightsError(w: Weights): string | null {
  const values = [w.ats, w.objective, w.written, w.interview]
  if (values.some((v) => !Number.isInteger(v) || v < 0 || v > 100)) return 'Each weight is a whole number from 0 to 100'
  const total = weightsTotal(w)
  return total === 100 ? null : `The weights add up to ${total}; they must add up to 100`
}

export const SLUG_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/

export function slugify(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80).replace(/-+$/, '')
}

export const careersPath = (orgCode: string, slug?: string) => (slug ? `/careers/${orgCode}/${slug}` : `/careers/${orgCode}`)

// ---------------------------------------------------------------------------- CV files
export const CV_MAX_BYTES = 5 * 1024 * 1024
export const CV_TYPES = {
  pdf: 'application/pdf',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
} as const
export type CvExtension = keyof typeof CV_TYPES
export const CV_ACCEPT = `.pdf,.docx,${CV_TYPES.pdf},${CV_TYPES.docx}`

export function cvExtension(fileName: string): CvExtension | null {
  const ext = fileName.toLowerCase().match(/\.([a-z0-9]+)$/)?.[1]
  return ext === 'pdf' || ext === 'docx' ? ext : null
}

/** Same rule as submit_job_application: PDF or DOCX (name and type agree), 1 byte to 5 MB. */
export function cvError(file: { name: string; size: number; type: string }): string | null {
  const ext = cvExtension(file.name)
  if (!ext || file.type !== CV_TYPES[ext]) return 'Attach your CV as a PDF or DOCX file'
  if (file.size <= 0) return 'The file is empty'
  if (file.size > CV_MAX_BYTES) return 'The CV must be smaller than 5 MB'
  return null
}

// ---------------------------------------------------------------------------- pasted applicants
export interface ApplicantDraft { full_name: string; email: string; phone: string }

const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

/**
 * Rows pasted from a spreadsheet or typed one per line: name, email, phone (comma or tab).
 * The cells may come in any order; the email and the phone are recognised by their shape.
 */
export function parseApplicantRows(text: string): { rows: ApplicantDraft[]; errors: string[] } {
  const rows: ApplicantDraft[] = []
  const errors: string[] = []
  text.split(/\r?\n/).forEach((line, index) => {
    const cells = line.split(/\t|,/).map((c) => c.trim()).filter(Boolean)
    if (cells.length === 0) return
    const email = cells.find((c) => EMAIL.test(c))
    if (!email) {
      if (index > 0 || !/name|email/i.test(line)) errors.push(`Line ${index + 1}: no email address`)
      return
    }
    const phone = cells.find((c) => c !== email && /^\+?[0-9][0-9\s-]{8,}$/.test(c)) ?? ''
    const name = cells.find((c) => c !== email && c !== phone) ?? ''
    if (name.length < 2) {
      errors.push(`Line ${index + 1}: no name`)
      return
    }
    rows.push({ full_name: name, email: email.toLowerCase(), phone })
  })
  return { rows, errors }
}
