import { describe, expect, it } from 'vitest'
import { effectiveTopics } from '../core/access'
import { answerQuestion, hasBangla, terms } from '../core/answer'
import { DEFAULT_SETUP } from '../core/catalog'
import { buildUpdates } from '../core/digest'
import type { AssistantSetup, RoleKey } from '../core/types'
import { SAMPLE_RESOURCES, SAMPLE_SNAPSHOT } from '../data/sampleData'

const setup: AssistantSetup = { ...DEFAULT_SETUP, resources: SAMPLE_RESOURCES, keyStatus: 'tested' }

function ask(question: string, role: RoleKey, s: AssistantSetup = setup) {
  const allowed = effectiveTopics(s, role)
  const updates = buildUpdates(allowed, SAMPLE_SNAPSHOT, [])
  return answerQuestion(question, { setup: s, role, allowed, updates, messages: s.messages[role] })
}

describe('answers come only from allowed resources', () => {
  it('answers a policy question with a citation to the page', () => {
    const a = ask('How many casual leaves do I get?', 'employee')
    expect(a.kind).toBe('answer')
    expect(a.text).toMatch(/10 days of casual leave/)
    expect(a.citations[0]).toMatchObject({ n: 1, resourceName: 'Leave Policy 2026.pdf', location: '2' })
  })
  it('says "not allowed" (never the content) when only a hidden resource matches', () => {
    const a = ask('What is the show-cause notice reply time?', 'employee')
    expect(a.kind).toBe('not_allowed')
    expect(a.text).toBe(setup.messages.employee.notAllowed)
    expect(a.text).not.toMatch(/7 days/)
    expect(ask('What is the show-cause notice reply time?', 'admin').kind).toBe('answer')
  })
  it('says "I don\'t know" when nothing matches', () => {
    expect(ask('Is there a gym membership?', 'employee').kind).toBe('dont_know')
  })
  it('refuses questions about records and points to the page', () => {
    expect(ask("What is Rahim's salary?", 'hr_manager')).toMatchObject({ kind: 'personal_data', citations: [] })
    expect(ask('What is my net pay?', 'employee').text).toMatch(/My payslips/)
  })
  it('lists the role\'s updates on request, nothing more', () => {
    const a = ask('What is waiting for me today?', 'manager')
    expect(a.kind).toBe('updates')
    expect(a.text).toMatch(/wait for you/)
    expect(a.text).not.toMatch(/active employees/) // headcount is not ticked for Manager
  })
})

describe('language and style', () => {
  it('Bangla questions get a Bangla lead-in and match Bangla text', () => {
    expect(hasBangla('অফিস কয়টায় শুরু হয়?')).toBe(true)
    const a = ask('অফিস কখন শুরু হয়?', 'employee')
    expect(a.kind).toBe('answer')
    expect(a.text.startsWith('নথি অনুযায়ী')).toBe(true)
  })
  it('a high minimum match turns weak matches into "I don\'t know"', () => {
    const strict = { ...setup, hyper: { ...setup.hyper, minScore: 0.9 } }
    expect(ask('casual leave carried forward gym', 'employee', strict).kind).toBe('dont_know')
  })
  it('short style cites at most 2 sources, detailed up to 4', () => {
    expect(ask('annual leave days', 'hr_manager').citations.length).toBeLessThanOrEqual(2)
    const detailed = { ...setup, hyper: { ...setup.hyper, answerStyle: 'detailed' as const } }
    expect(ask('annual leave days', 'hr_manager', detailed).citations.length).toBeGreaterThan(2)
  })
  it('ignores stop words', () => {
    expect(terms('How many casual leaves do I get?')).toEqual(['casual', 'leaves'])
  })
})
