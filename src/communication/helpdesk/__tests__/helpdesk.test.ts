import { describe, expect, it } from 'vitest'
import { DEFAULT_SLA, hoursOf, minutesOf, officeDuration, slaLeftLabel, slaProblems, statusLabel, ticketNo, ticketProblems } from '../core/helpdesk'

it('ticket numbers have four digits', () => {
  expect(ticketNo(1)).toBe('#0001')
  expect(ticketNo(12345)).toBe('#12345')
})

describe('SLA display', () => {
  it('office durations in hours and minutes', () => {
    expect(officeDuration(45)).toBe('45 min')
    expect(officeDuration(150)).toBe('2 h 30 min')
    expect(officeDuration(-120)).toBe('2 h')
  })
  it('left or overdue; nothing while paused', () => {
    expect(slaLeftLabel(190)).toBe('3 h 10 min left')
    expect(slaLeftLabel(-40)).toBe('overdue by 40 min')
    expect(slaLeftLabel(null)).toBeNull()
  })
  it('hours <-> minutes for the setup form', () => {
    expect(hoursOf(90)).toBe(1.5)
    expect(minutesOf(0.25)).toBe(15)
  })
})

describe('SLA setup checks (same as save_helpdesk_settings)', () => {
  it('defaults are valid', () => {
    expect(slaProblems(DEFAULT_SLA, 3)).toEqual([])
  })
  it('response after resolution, out of range, bad auto-close', () => {
    expect(slaProblems({ ...DEFAULT_SLA, critical: { response: 300, resolution: 60 } }, 3)[0]).toMatch(/Critical: the first response/)
    expect(slaProblems({ ...DEFAULT_SLA, low: { response: 10, resolution: 100 } }, 3)[0]).toMatch(/Low: give 15 minutes/)
    expect(slaProblems(DEFAULT_SLA, 0)).toEqual(['Auto-close: 1 to 30 working days'])
  })
})

it('ticket form checks', () => {
  expect(ticketProblems({ subject: 'Hi', description: '', category_id: '' })).toEqual({
    subject: 'At least 3 characters', description: 'Describe the problem', category_id: 'Choose a category',
  })
  expect(ticketProblems({ subject: 'Printer jam', description: 'Floor 2', category_id: 'x' })).toEqual({})
})

it('waiting reads from each side', () => {
  expect(statusLabel('waiting', false)).toBe('Waiting for you')
  expect(statusLabel('waiting', true)).toBe('Waiting for the employee')
})
