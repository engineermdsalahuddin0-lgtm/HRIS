import { describe, expect, it } from 'vitest'
import { EMPTY_DRAFT, ackByDefault, draftProblems, fromLocalInput, percentOf, shownStatus, toLocalInput } from '../core/notices'

const now = Date.parse('2026-11-02T10:00:00Z')

describe('shown status (same as private.notice_shown_status)', () => {
  it('draft, scheduled, active, expired, archived', () => {
    expect(shownStatus({ status: 'draft', publish_at: null, expires_at: null }, now)).toBe('draft')
    expect(shownStatus({ status: 'published', publish_at: '2026-11-03T00:00:00Z', expires_at: null }, now)).toBe('scheduled')
    expect(shownStatus({ status: 'published', publish_at: '2026-11-01T00:00:00Z', expires_at: null }, now)).toBe('active')
    expect(shownStatus({ status: 'published', publish_at: '2026-10-01T00:00:00Z', expires_at: '2026-11-02T09:00:00Z' }, now)).toBe('expired')
    expect(shownStatus({ status: 'archived', publish_at: '2026-10-01T00:00:00Z', expires_at: null }, now)).toBe('archived')
  })
})

describe('form checks', () => {
  const ok = { ...EMPTY_DRAFT, title: 'Eid holiday', body: 'Office closed' }
  it('a filled draft has no problems', () => {
    expect(draftProblems(ok, true, now)).toEqual({})
  })
  it('title, body and audience lists are required', () => {
    expect(draftProblems({ ...ok, title: 'Hi', body: ' ' }, true, now)).toMatchObject({ title: expect.any(String), body: expect.any(String) })
    expect(draftProblems({ ...ok, audience: 'department' }, true, now).department_ids).toBeTruthy()
    // A manager's audience is filled by the database.
    expect(draftProblems({ ...ok, audience: 'department' }, false, now).department_ids).toBeUndefined()
  })
  it('expiry must follow publish', () => {
    expect(draftProblems({ ...ok, publish_now: false, publish_at: '' }, true, now).publish_at).toBeTruthy()
    expect(draftProblems({ ...ok, publish_now: false, publish_at: '2026-11-05T10:00', expires_at: '2026-11-04T10:00' }, true, now).expires_at).toBeTruthy()
  })
  it('policy updates and safety notices ask for acknowledgement', () => {
    expect(ackByDefault('policy_update') && ackByDefault('safety') && !ackByDefault('event')).toBe(true)
  })
})

it('read share is a whole percent of portal users', () => {
  expect(percentOf(1, 3)).toBe(33)
  expect(percentOf(5, 4)).toBe(100)
  expect(percentOf(0, 0)).toBeNull()
})

it('datetime-local round trip keeps the minute', () => {
  const iso = '2026-11-02T04:30:00.000Z'
  expect(fromLocalInput(toLocalInput(iso))).toBe(iso)
})
