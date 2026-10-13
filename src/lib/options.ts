import type { Option } from '@/components/kit'

const opts = (pairs: [string, string][]): Option[] => pairs.map(([value, label]) => ({ value, label }))

export const EMPLOYMENT_TYPES = opts([
  ['permanent', 'Permanent'],
  ['contract', 'Contract'],
  ['probation', 'Probation'],
  ['intern', 'Intern'],
  ['part_time', 'Part-time'],
])
export const GENDERS = opts([['male', 'Male'], ['female', 'Female'], ['other', 'Other']])
export const MARITAL = opts([['single', 'Single'], ['married', 'Married'], ['divorced', 'Divorced'], ['widowed', 'Widowed']])
export const RELIGIONS = opts([
  ['islam', 'Islam'],
  ['hinduism', 'Hinduism'],
  ['buddhism', 'Buddhism'],
  ['christianity', 'Christianity'],
  ['other', 'Other'],
])
export const BLOOD_GROUPS = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map((b) => ({ value: b, label: b }))
export const EMPLOYEE_STATUSES = opts([['active', 'Active'], ['inactive', 'Inactive'], ['terminated', 'Terminated']])
export const LINE_TYPES = opts([
  ['reporting_manager', 'Reporting Manager'],
  ['supervisor', 'Supervisor'],
  ['it_manager', 'IT Manager'],
  ['finance_manager', 'Finance Manager'],
])
export const GRADE_CATEGORIES = opts([['EM', 'Employee (EM)'], ['MS', 'Management (MS)'], ['OWNER', 'Owner']])

export function labelOf(options: Option[], value: string | null | undefined): string {
  if (!value) return '—'
  return options.find((o) => o.value === value)?.label ?? value
}

export const EVENT_LABELS: Record<string, string> = {
  joined: 'Joined',
  transfer: 'Transferred',
  promotion: 'Promoted',
  demotion: 'Demoted',
  designation: 'Designation changed',
  department: 'Department changed',
  branch: 'Branch changed',
  office: 'Office changed',
  operation: 'Operation changed',
  employment_type: 'Employment type changed',
  status: 'Status changed',
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return '—'
  const d = new Date(value.length === 10 ? `${value}T00:00:00` : value)
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
}

export function formatDateTime(value: string | null | undefined): string {
  if (!value) return '—'
  return new Date(value).toLocaleString(undefined, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}

export const today = () => new Date().toISOString().slice(0, 10)
