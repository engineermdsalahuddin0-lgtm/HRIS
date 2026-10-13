import { describe, expect, it } from 'vitest'
import { idCardQrPayload, validateFile } from '@/lib/files'

const file = (type: string, size: number) => new File([new Uint8Array(size)], 'x', { type })

describe('validateFile', () => {
  it('accepts allowed images under the limit', () => {
    expect(validateFile('photo', file('image/png', 1000))).toBeNull()
    expect(validateFile('nid', file('application/pdf', 1000))).toBeNull()
  })
  it('rejects wrong types', () => {
    expect(validateFile('photo', file('application/pdf', 1000))).toMatch(/Photo/)
    expect(validateFile('logo', file('image/svg+xml', 100))).toMatch(/Logo/)
  })
  it('rejects files over the limit', () => {
    expect(validateFile('signature', file('image/png', 2 * 1024 * 1024))).toMatch(/under 1 MB/)
  })
})

describe('idCardQrPayload', () => {
  it('always carries the organization code', () => {
    expect(idCardQrPayload('482915', '2612345678')).toBe('OLYMPUS:482915:2612345678')
  })
})
