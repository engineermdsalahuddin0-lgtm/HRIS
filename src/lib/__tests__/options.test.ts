import { describe, expect, it } from 'vitest'
import { EMPLOYMENT_TYPES, labelOf } from '@/lib/options'

describe('labelOf', () => {
  it('maps values to labels and falls back safely', () => {
    expect(labelOf(EMPLOYMENT_TYPES, 'part_time')).toBe('Part-time')
    expect(labelOf(EMPLOYMENT_TYPES, 'unknown')).toBe('unknown')
    expect(labelOf(EMPLOYMENT_TYPES, null)).toBe('—')
  })
})
