// Who may manage the assistant, which topics a role really gets (tick AND permission),
// which resources a role may read, and whether the setup is ready.
import { HYPER_RANGES, PROVIDERS, ROLE_PERMISSIONS, TOPICS, topicOf } from './catalog'
import type { AssistantSetup, Hyperparameters, Resource, RoleKey, Topic } from './types'

/** Maps the signed-in role to a matrix column; custom roles use the Employee column for now. */
export function roleKeyOf(systemKey: string | null | undefined): RoleKey {
  return systemKey === 'admin' || systemKey === 'hr_manager' || systemKey === 'manager' ? systemKey : 'employee'
}

/** Decision D2: Admin always; HR Manager only when an Admin has handed over the setup. */
export function canManageAssistant(role: RoleKey, setup: Pick<AssistantSetup, 'hrCanManage'>): boolean {
  return role === 'admin' || (role === 'hr_manager' && setup.hrCanManage)
}

/** A topic is usable by a role only if the role already has one of its permissions. */
export function missingPermission(role: RoleKey, topic: Topic): string | null {
  if (role === 'admin' || topic.needsAnyOf.length === 0) return null
  const have = ROLE_PERMISSIONS[role]
  return topic.needsAnyOf.some((p) => have.includes(p)) ? null : topic.needsAnyOf.join(' or ')
}

/** Who may change a tick: Admin column is fixed; sensitive topics for HR Manager are Admin-only. */
export function canEditTick(editor: RoleKey, column: RoleKey, topic: Topic): boolean {
  if (column === 'admin') return false
  if (editor === 'admin') return true
  return !(column === 'hr_manager' && topic.sensitive)
}

/** The topics the assistant may use for this role right now. */
export function effectiveTopics(setup: AssistantSetup, role: RoleKey): Set<string> {
  if (!setup.enabled || !setup.roleEnabled[role]) return new Set()
  return new Set(
    TOPICS.filter((t) => (role === 'admin' || setup.matrix[role]?.[t.key]) && !missingPermission(role, t)).map((t) => t.key),
  )
}

/** Topic ticked for the role, and the resource does not narrow the audience away from it. */
export function canReadResource(resource: Resource, role: RoleKey, allowed: Set<string>): boolean {
  if (resource.status !== 'ready' || !allowed.has(resource.topicKey)) return false
  return role === 'admin' || resource.audience.length === 0 || resource.audience.includes(role)
}

export function validateHyper(h: Hyperparameters): string[] {
  const errors: string[] = []
  const inRange = (k: keyof typeof HYPER_RANGES, label: string) => {
    const { min, max } = HYPER_RANGES[k]
    const v = h[k]
    if (!(v >= min && v <= max)) errors.push(`${label} must be between ${min} and ${max}.`)
  }
  inRange('temperature', 'Creativity')
  inRange('maxAnswerTokens', 'Answer length')
  inRange('topK', 'Sources per answer')
  inRange('minScore', 'Minimum match')
  inRange('chunkSize', 'Chunk size')
  inRange('chunkOverlap', 'Overlap')
  if (!PROVIDERS.some((p) => p.models.some((m) => m.id === h.model))) errors.push('Choose a model.')
  return errors
}

export interface ReadinessStep {
  key: 'key' | 'resources' | 'hyper' | 'roles'
  label: string
  done: boolean
  detail: string
}

/** The three things a company must give (key, resources, settings) plus at least one role switched on. */
export function readiness(setup: AssistantSetup): { steps: ReadinessStep[]; ready: boolean } {
  const ready = setup.resources.filter((r) => r.status === 'ready').length
  const processing = setup.resources.filter((r) => r.status === 'processing').length
  const hyperErrors = validateHyper(setup.hyper)
  const modelOk = PROVIDERS.find((p) => p.key === setup.provider)?.models.some((m) => m.id === setup.hyper.model)
  const rolesOn = Object.values(setup.roleEnabled).filter(Boolean).length
  const steps: ReadinessStep[] = [
    {
      key: 'key', label: 'API key',
      done: setup.keyStatus === 'tested',
      detail: setup.keyStatus === 'tested' ? `Connected (••••${setup.keyLast4})`
        : setup.keyStatus === 'failed' ? 'The key did not work. Check it and test again.'
        : setup.keyStatus === 'saved' ? 'Saved, not tested yet.' : 'Not given yet.',
    },
    {
      key: 'resources', label: 'Resources',
      done: ready > 0,
      detail: ready > 0 ? `${ready} ready${processing ? `, ${processing} processing` : ''}`
        : processing ? `${processing} processing…` : 'Upload at least one PDF, DOCX or JSON file.',
    },
    {
      key: 'hyper', label: 'Model settings',
      done: hyperErrors.length === 0 && !!modelOk,
      detail: !modelOk ? 'Pick a model of the chosen provider.' : hyperErrors[0] ?? 'Set.',
    },
    { key: 'roles', label: 'Role access', done: rolesOn > 0, detail: `${rolesOn} of 4 roles switched on` },
  ]
  return { steps, ready: setup.enabled && steps.every((s) => s.done) }
}

/** Summary shown before saving the matrix ("Manager: + Labour law, − Headcount"). */
export function matrixChanges(before: AssistantSetup['matrix'], after: AssistantSetup['matrix']): Record<RoleKey, string[]> {
  const out = {} as Record<RoleKey, string[]>
  for (const role of Object.keys(after) as RoleKey[]) {
    const lines: string[] = []
    for (const t of TOPICS) {
      const a = !!before[role]?.[t.key]
      const b = !!after[role]?.[t.key]
      if (a !== b) lines.push(`${b ? '+' : '−'} ${topicOf(t.key)!.label}`)
    }
    if (lines.length) out[role] = lines
  }
  return out
}
