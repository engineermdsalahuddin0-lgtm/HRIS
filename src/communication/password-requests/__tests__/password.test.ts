import { expect, it } from 'vitest'
import { passwordRule } from '@/lib/identity'
import { temporaryPassword } from '../core/password'

it('temporary passwords pass the login rule and avoid look-alike characters', () => {
  for (let i = 0; i < 200; i++) {
    const p = temporaryPassword()
    expect(p).toHaveLength(9)
    expect(passwordRule.test(p)).toBe(true)
    expect(p).not.toMatch(/[01OIl]/)
  }
})

it('is built from the given random source', () => {
  let n = 0
  const seq = (max: number) => (n++ * 7) % max
  expect(temporaryPassword(seq)).toMatch(/^[A-Za-z2-9]{9}$/)
})
