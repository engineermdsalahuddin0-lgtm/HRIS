// Catalog of the assistant: providers and models, topics (the rows of the role matrix),
// accepted resource types, hyperparameter ranges and the default setup of a new company.
import type { AssistantSetup, Hyperparameters, ProviderKey, RoleKey, RoleMessages, Topic } from './types'

export interface Provider {
  key: ProviderKey
  label: string
  /** Where the company finds its key. */
  keyHelp: string
  /** Light format check before the backend test call. */
  keyPattern: RegExp
  keyExample: string
  models: { id: string; label: string; note: string }[]
}

// The model lists will come from the backend later; these are the ones the preview offers.
export const PROVIDERS: Provider[] = [
  {
    key: 'claude', label: 'Anthropic Claude', keyHelp: 'console.anthropic.com → API keys',
    keyPattern: /^sk-ant-[A-Za-z0-9_-]{20,}$/, keyExample: 'sk-ant-…',
    models: [
      { id: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5', note: 'Recommended: good answers, fair cost' },
      { id: 'claude-haiku-5-5', label: 'Claude Haiku 5.5', note: 'Fastest and cheapest' },
      { id: 'claude-opus-5-5', label: 'Claude Opus 5.5', note: 'Most capable, highest cost' },
    ],
  },
  {
    key: 'openai', label: 'OpenAI', keyHelp: 'platform.openai.com → API keys',
    keyPattern: /^sk-[A-Za-z0-9_-]{20,}$/, keyExample: 'sk-…',
    models: [
      { id: 'gpt-4.1', label: 'GPT-4.1', note: 'Balanced' },
      { id: 'gpt-4.1-mini', label: 'GPT-4.1 mini', note: 'Faster and cheaper' },
    ],
  },
  {
    key: 'gemini', label: 'Google Gemini', keyHelp: 'aistudio.google.com → Get API key',
    keyPattern: /^AIza[A-Za-z0-9_-]{30,}$/, keyExample: 'AIza…',
    models: [
      { id: 'gemini-2.5-pro', label: 'Gemini 2.5 Pro', note: 'Most capable' },
      { id: 'gemini-2.5-flash', label: 'Gemini 2.5 Flash', note: 'Faster and cheaper' },
    ],
  },
]
export const providerOf = (key: ProviderKey) => PROVIDERS.find((p) => p.key === key)!

export const ROLES: { key: RoleKey; label: string }[] = [
  { key: 'admin', label: 'Admin' },
  { key: 'hr_manager', label: 'HR Manager' },
  { key: 'manager', label: 'Manager' },
  { key: 'employee', label: 'Employee' },
]
export const roleLabel = (key: RoleKey) => ROLES.find((r) => r.key === key)!.label

/**
 * Default permissions of the system roles (handbook A7). The matrix greys out a tick the
 * role cannot use; the backend will read the org's real role_permissions instead.
 */
export const ROLE_PERMISSIONS: Record<Exclude<RoleKey, 'admin'>, string[]> = {
  hr_manager: [
    'org.view', 'employees.view', 'attendance.view_own', 'attendance.view_team', 'attendance.view_all',
    'leave.request', 'leave.approve', 'leave.view_all', 'overtime.view', 'overtime.approve', 'swaps.approve',
    'compensation.view', 'payroll.view_own', 'payroll.prepare', 'payroll.review', 'recruit.manage', 'workforce.view',
  ],
  manager: [
    'org.view', 'employees.view', 'attendance.view_own', 'attendance.view_team', 'swaps.approve',
    'leave.request', 'leave.approve', 'overtime.view', 'overtime.approve', 'payroll.view_own',
  ],
  employee: ['attendance.view_own', 'leave.request', 'payroll.view_own'],
}

export const TOPICS: Topic[] = [
  // Updates: the same numbers and statuses the dashboard shows, never amounts or other people's details.
  { key: 'up.my_day', group: 'updates', label: 'My day', hint: 'My check-in today and shift', needsAnyOf: ['attendance.view_own'] },
  { key: 'up.my_leave', group: 'updates', label: 'My leave', hint: 'Balance and pending requests', needsAnyOf: ['leave.request'] },
  { key: 'up.my_payslip', group: 'updates', label: 'My payslip', hint: '"Your payslip is ready" (no amounts)', needsAnyOf: ['payroll.view_own'] },
  { key: 'up.team_today', group: 'updates', label: 'Team today', hint: 'Present / late / absent counts of my team', needsAnyOf: ['attendance.view_team', 'attendance.view_all'] },
  { key: 'up.approvals', group: 'updates', label: 'Approvals waiting', hint: 'Leave, overtime, swap requests for me', needsAnyOf: ['leave.approve', 'overtime.approve', 'swaps.approve'] },
  { key: 'up.headcount', group: 'updates', label: 'Headcount', hint: 'Total, active, new this month', needsAnyOf: ['employees.view'] },
  { key: 'up.payroll_status', group: 'updates', label: 'Payroll status', hint: 'Run status only, no amounts', needsAnyOf: ['payroll.prepare', 'payroll.approve'], sensitive: true },
  { key: 'up.hiring', group: 'updates', label: 'Hiring', hint: 'Open vacancies and applicants waiting', needsAnyOf: ['recruit.manage', 'workforce.view'] },
  { key: 'up.new_resources', group: 'updates', label: 'New policies', hint: '"New policy published" for documents the role may read', needsAnyOf: [] },
  // Knowledge: the app guide (written by us) and what the uploaded resources are about.
  { key: 'kb.app_guide', group: 'knowledge', label: 'App guide', hint: 'How to use Olympus pages and features', needsAnyOf: [] },
  { key: 'kb.company_policy', group: 'knowledge', label: 'Company policies', hint: 'Leave, attendance, conduct, dress code', needsAnyOf: [] },
  { key: 'kb.hr_rules', group: 'knowledge', label: 'HR rules & procedures', hint: 'Joining, transfer, resignation, settlement', needsAnyOf: [] },
  { key: 'kb.circulars', group: 'knowledge', label: 'Notices & circulars', hint: 'Holiday notices, office closures', needsAnyOf: [] },
  { key: 'kb.labour_law', group: 'knowledge', label: 'Labour law', hint: 'Bangladesh Labour Act / EPZ Act', needsAnyOf: [] },
  { key: 'kb.tax_pf_gratuity', group: 'knowledge', label: 'Tax, PF & gratuity', hint: 'Statutory rules', needsAnyOf: [] },
  { key: 'kb.pay_policy', group: 'knowledge', label: 'Pay & benefits policy', hint: 'Salary structure, bonus, allowances', needsAnyOf: [] },
  { key: 'kb.manager_guide', group: 'knowledge', label: 'Manager guide', hint: 'Approving requests, reviews', needsAnyOf: [] },
  { key: 'kb.confidential', group: 'knowledge', label: 'Confidential HR', hint: 'Disciplinary and investigation SOPs', needsAnyOf: [], sensitive: true },
]
export const topicOf = (key: string) => TOPICS.find((t) => t.key === key)
export const KNOWLEDGE_TOPICS = TOPICS.filter((t) => t.group === 'knowledge')

export const RESOURCE_TYPES = {
  pdf: { label: 'PDF', extensions: ['pdf'], mime: 'application/pdf' },
  docx: { label: 'Word', extensions: ['docx'], mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
  json: { label: 'JSON', extensions: ['json'], mime: 'application/json' },
} as const
export const ACCEPT = '.pdf,.docx,.json,application/pdf,application/json,application/vnd.openxmlformats-officedocument.wordprocessingml.document'
export const MAX_RESOURCE_MB = 20

export const HYPER_RANGES = {
  temperature: { min: 0, max: 1, step: 0.1 },
  maxAnswerTokens: { min: 200, max: 2000, step: 100 },
  topK: { min: 2, max: 12, step: 1 },
  minScore: { min: 0, max: 0.9, step: 0.05 },
  chunkSize: { min: 200, max: 1000, step: 50 },
  chunkOverlap: { min: 0, max: 30, step: 5 },
} as const

export const RECOMMENDED_HYPER: Hyperparameters = {
  model: 'claude-sonnet-5-5',
  temperature: 0.2,
  maxAnswerTokens: 600,
  answerStyle: 'short',
  topK: 6,
  minScore: 0.3,
  chunkSize: 400,
  chunkOverlap: 15,
}

const allOn = (keys: string[]) => Object.fromEntries(TOPICS.map((t) => [t.key, keys.includes(t.key)]))
const EVERYONE = ['up.my_day', 'up.my_leave', 'up.my_payslip', 'up.new_resources', 'kb.app_guide', 'kb.company_policy', 'kb.hr_rules', 'kb.circulars']

const message = (greeting: string, suggestions: string[]): RoleMessages => ({
  greeting,
  suggestions,
  notice: '',
  notAllowed: 'This topic is not open for your role. Please ask HR.',
})

export const DEFAULT_SETUP: AssistantSetup = {
  enabled: true,
  name: 'Olympus Assistant',
  languageMode: 'follow',
  hrCanManage: false,
  provider: 'claude',
  keyLast4: null,
  keyStatus: 'missing',
  keyCheckedAt: null,
  hyper: RECOMMENDED_HYPER,
  roleEnabled: { admin: true, hr_manager: true, manager: true, employee: true },
  dailyLimit: { admin: null, hr_manager: 50, manager: 30, employee: 20 },
  matrix: {
    admin: allOn(TOPICS.map((t) => t.key)),
    hr_manager: allOn([...EVERYONE, 'up.team_today', 'up.approvals', 'up.headcount', 'up.payroll_status', 'up.hiring',
      'kb.labour_law', 'kb.tax_pf_gratuity', 'kb.pay_policy', 'kb.manager_guide']),
    manager: allOn([...EVERYONE, 'up.team_today', 'up.approvals', 'kb.labour_law', 'kb.manager_guide']),
    employee: allOn(EVERYONE),
  },
  messages: {
    admin: message('Hi! Ask me about any company document or today’s updates.', ['What changed in the leave policy?', 'Payroll status this month?']),
    hr_manager: message('Hi! I can answer from company policies, labour law and your updates.', ['How many casual leaves per year?', 'Maternity leave rule under the Labour Act?']),
    manager: message('Hi! Ask me about policies or what is waiting for your approval.', ['What is waiting for my approval?', 'How should I approve overtime?']),
    employee: message('Hi! Ask me about company policies, rules and your own updates.', ['How many casual leaves do I get?', 'অফিস কয়টায় শুরু হয়?']),
  },
  resources: [],
}
