import { describe, expect, it } from 'vitest'
import { canEditTick, canManageAssistant, canReadResource, effectiveTopics, matrixChanges, missingPermission, readiness, roleKeyOf, validateHyper } from '../core/access'
import { DEFAULT_SETUP, RECOMMENDED_HYPER, topicOf } from '../core/catalog'
import type { AssistantSetup } from '../core/types'
import { SAMPLE_RESOURCES } from '../data/sampleData'

const withSamples: AssistantSetup = { ...DEFAULT_SETUP, resources: SAMPLE_RESOURCES }

describe('who manages the assistant (D2)', () => {
  it('Admin always, HR Manager only when handed over, others never', () => {
    expect(canManageAssistant('admin', { hrCanManage: false })).toBe(true)
    expect(canManageAssistant('hr_manager', { hrCanManage: false })).toBe(false)
    expect(canManageAssistant('hr_manager', { hrCanManage: true })).toBe(true)
    expect(canManageAssistant('manager', { hrCanManage: true })).toBe(false)
  })
  it('custom roles use the Employee column', () => {
    expect(roleKeyOf(null)).toBe('employee')
    expect(roleKeyOf('manager')).toBe('manager')
  })
  it('HR Manager cannot tick sensitive topics for its own role, and nobody edits the Admin column', () => {
    const confidential = topicOf('kb.confidential')!
    expect(canEditTick('hr_manager', 'hr_manager', confidential)).toBe(false)
    expect(canEditTick('hr_manager', 'manager', confidential)).toBe(true)
    expect(canEditTick('admin', 'hr_manager', confidential)).toBe(true)
    expect(canEditTick('admin', 'admin', confidential)).toBe(false)
  })
})

describe('a tick never gives more than the permission', () => {
  it('Employee has no employees.view, so Headcount stays off even when ticked', () => {
    const ticked = { ...DEFAULT_SETUP, matrix: { ...DEFAULT_SETUP.matrix, employee: { ...DEFAULT_SETUP.matrix.employee, 'up.headcount': true } } }
    expect(missingPermission('employee', topicOf('up.headcount')!)).toBe('employees.view')
    expect(effectiveTopics(ticked, 'employee').has('up.headcount')).toBe(false)
    expect(effectiveTopics(ticked, 'manager').has('up.headcount')).toBe(false) // manager has the permission but no tick
  })
  it('switched-off company or role gets nothing', () => {
    expect(effectiveTopics({ ...DEFAULT_SETUP, enabled: false }, 'admin').size).toBe(0)
    expect(effectiveTopics({ ...DEFAULT_SETUP, roleEnabled: { ...DEFAULT_SETUP.roleEnabled, manager: false } }, 'manager').size).toBe(0)
  })
})

describe('resources follow topic and audience', () => {
  const confidential = SAMPLE_RESOURCES.find((r) => r.topicKey === 'kb.confidential')!
  const leave = SAMPLE_RESOURCES.find((r) => r.id === 'sample-leave')!
  it('confidential is Admin only by default', () => {
    expect(canReadResource(confidential, 'admin', effectiveTopics(withSamples, 'admin'))).toBe(true)
    expect(canReadResource(confidential, 'hr_manager', effectiveTopics(withSamples, 'hr_manager'))).toBe(false)
  })
  it('a narrowed audience removes roles the topic allows', () => {
    const managersOnly = { ...leave, audience: ['manager' as const] }
    expect(canReadResource(managersOnly, 'employee', effectiveTopics(withSamples, 'employee'))).toBe(false)
    expect(canReadResource(managersOnly, 'manager', effectiveTopics(withSamples, 'manager'))).toBe(true)
  })
  it('processing and archived resources are not read', () => {
    const allowed = effectiveTopics(withSamples, 'employee')
    expect(canReadResource({ ...leave, status: 'processing' }, 'employee', allowed)).toBe(false)
    expect(canReadResource({ ...leave, status: 'archived' }, 'employee', allowed)).toBe(false)
  })
})

describe('readiness: key + resources + settings', () => {
  it('a new company is not ready; key, one ready resource and valid settings make it ready', () => {
    expect(readiness(DEFAULT_SETUP).ready).toBe(false)
    const done = readiness({ ...withSamples, keyStatus: 'tested', keyLast4: 'abcd' })
    expect(done.steps.map((s) => s.done)).toEqual([true, true, true, true])
    expect(done.ready).toBe(true)
  })
  it('a model of another provider is not accepted', () => {
    const r = readiness({ ...withSamples, keyStatus: 'tested', provider: 'gemini' })
    expect(r.steps.find((s) => s.key === 'hyper')!.done).toBe(false)
  })
  it('hyperparameters out of range are reported', () => {
    expect(validateHyper(RECOMMENDED_HYPER)).toEqual([])
    expect(validateHyper({ ...RECOMMENDED_HYPER, temperature: 1.5 })[0]).toMatch(/Creativity/)
  })
})

it('matrix changes are summarised per role', () => {
  const after = { ...DEFAULT_SETUP.matrix, manager: { ...DEFAULT_SETUP.matrix.manager, 'kb.pay_policy': true, 'kb.labour_law': false } }
  expect(matrixChanges(DEFAULT_SETUP.matrix, after)).toEqual({ manager: ['− Labour law', '+ Pay & benefits policy'] })
})
