import { describe, expect, it } from 'vitest'
import { classCovers, classNeeded, formatKm, normRegNo } from '../core/tms'

describe('registration numbers', () => {
  it('are normalised like the database does', () => {
    expect(normRegNo('  dhaka metro-ga   12-3456 ')).toBe('DHAKA METRO-GA 12-3456')
  })
})

describe('licence classes', () => {
  it('match the vehicle type', () => {
    expect(classNeeded('car')).toBe('light')
    expect(classNeeded('covered_van')).toBe('medium')
    expect(classNeeded('truck')).toBe('heavy')
    expect(classNeeded('motorcycle')).toBe('motorcycle')
  })
  it('a higher class covers a lower one, motorcycle only itself', () => {
    expect(classCovers('heavy', 'car')).toBe(true)
    expect(classCovers('light', 'truck')).toBe(false)
    expect(classCovers('medium', 'covered_van')).toBe(true)
    expect(classCovers('heavy', 'motorcycle')).toBe(false)
    expect(classCovers('motorcycle', 'car')).toBe(false)
  })
})

it('formats kilometres', () => {
  expect(formatKm(52000)).toBe('52,000 km')
  expect(formatKm(null)).toBe('—')
})
