import { describe, expect, it } from 'vitest'
import { VIEWPORT_MARGIN, holeFor, isVisibleBox, placeCard } from '@/components/spotlight/geometry'

const viewport = { width: 1280, height: 800 }
const card = { width: 340, height: 200 }

describe('holeFor', () => {
  it('grows the target by the padding', () => {
    expect(holeFor({ top: 100, left: 200, width: 300, height: 50 }, 8, viewport))
      .toEqual({ top: 92, left: 192, width: 316, height: 66 })
  })
  it('clips the hole to the viewport', () => {
    expect(holeFor({ top: -20, left: 0, width: 72, height: 900 }, 8, viewport))
      .toEqual({ top: 0, left: 0, width: 80, height: 800 })
  })
})

describe('placeCard', () => {
  it('centres the card when there is no hole', () => {
    expect(placeCard(null, card, viewport)).toEqual({ top: 300, left: 470, placement: 'center' })
  })
  it('puts the card below a hole near the top, centred on it', () => {
    const result = placeCard({ top: 80, left: 400, width: 400, height: 100 }, card, viewport)
    expect(result).toEqual({ top: 194, left: 430, placement: 'bottom' })
  })
  it('goes above when there is no room below', () => {
    expect(placeCard({ top: 600, left: 400, width: 400, height: 150 }, card, viewport).placement).toBe('top')
  })
  it('uses the right side for a tall sidebar', () => {
    const result = placeCard({ top: 0, left: 0, width: 72, height: 800 }, card, viewport, 'right')
    expect(result.placement).toBe('right')
    expect(result.left).toBe(86)
  })
  it('keeps the card inside the screen edge', () => {
    const result = placeCard({ top: 20, left: 1200, width: 60, height: 40 }, card, viewport)
    expect(result.left).toBe(viewport.width - card.width - VIEWPORT_MARGIN)
  })
  it('falls back to the bottom edge when the hole fills the screen', () => {
    const result = placeCard({ top: 0, left: 0, width: 1280, height: 800 }, card, viewport)
    expect(result).toMatchObject({ placement: 'center', top: 800 - 200 - VIEWPORT_MARGIN })
  })
  it('ignores a preferred side that does not fit', () => {
    expect(placeCard({ top: 100, left: 10, width: 100, height: 60 }, card, viewport, 'left').placement).toBe('bottom')
  })
})

describe('isVisibleBox', () => {
  it('rejects missing and zero-sized boxes', () => {
    expect(isVisibleBox(null)).toBe(false)
    expect(isVisibleBox({ top: 0, left: 0, width: 0, height: 10 })).toBe(false)
    expect(isVisibleBox({ top: 0, left: 0, width: 10, height: 10 })).toBe(true)
  })
})
