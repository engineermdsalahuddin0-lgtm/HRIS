import { describe, expect, it } from 'vitest'
import { errorMessage, normalizeBdPhone, parseLoginIdentifier, passwordRule } from '@/lib/identity'

describe('normalizeBdPhone', () => {
  it.each([
    ['01712345678', '+8801712345678'],
    ['8801712345678', '+8801712345678'],
    ['+8801712345678', '+8801712345678'],
    ['017 1234-5678', '+8801712345678'],
  ])('%s -> %s', (input, out) => expect(normalizeBdPhone(input)).toBe(out))

  it.each(['01212345678', '0171234567', '123', '+44 7700 900123', ''])('rejects %s', (input) => {
    expect(normalizeBdPhone(input)).toBeNull()
  })
})

describe('parseLoginIdentifier', () => {
  it('detects email and lowercases it', () => {
    expect(parseLoginIdentifier('  Admin@Company.COM ')).toEqual({ kind: 'email', email: 'admin@company.com' })
  })
  it('detects a mobile number', () => {
    expect(parseLoginIdentifier('01811000005')).toEqual({ kind: 'phone', phone: '+8801811000005' })
  })
  it('rejects garbage', () => {
    expect(parseLoginIdentifier('not-an-id')).toBeNull()
    expect(parseLoginIdentifier('a@b')).toBeNull()
  })
})

describe('passwordRule', () => {
  it('needs 8+ chars with letters and digits', () => {
    expect(passwordRule.test('Passw0rd')).toBe(true)
    expect(passwordRule.test('password')).toBe(false)
    expect(passwordRule.test('12345678')).toBe(false)
    expect(passwordRule.test('Ab1')).toBe(false)
  })
})

describe('errorMessage', () => {
  it('uses the message from Supabase errors', () => {
    expect(errorMessage({ message: 'Only an Admin can assign roles' })).toBe('Only an Admin can assign roles')
    expect(errorMessage('weird')).toMatch(/Something went wrong/)
  })
})
