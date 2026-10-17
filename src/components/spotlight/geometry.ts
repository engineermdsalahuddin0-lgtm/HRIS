// Pure geometry for the spotlight guide: the punched hole around a target and
// where the step card goes so it never covers the hole or leaves the screen.
// No DOM access here, so every rule is unit-tested.

export interface Box { top: number; left: number; width: number; height: number }
export interface Size { width: number; height: number }
export type Placement = 'auto' | 'top' | 'bottom' | 'left' | 'right'
export type ResolvedPlacement = Exclude<Placement, 'auto'> | 'center'

/** Margin kept between the card and the screen edge. */
export const VIEWPORT_MARGIN = 12

/** The hole: the target grown by padding, clipped to the viewport. */
export function holeFor(target: Box, padding: number, viewport: Size): Box {
  const top = Math.max(target.top - padding, 0)
  const left = Math.max(target.left - padding, 0)
  const bottom = Math.min(target.top + target.height + padding, viewport.height)
  const right = Math.min(target.left + target.width + padding, viewport.width)
  return { top, left, width: Math.max(right - left, 0), height: Math.max(bottom - top, 0) }
}

const clamp = (value: number, min: number, max: number) => Math.min(Math.max(value, min), Math.max(min, max))

/**
 * Card position next to the hole. With "auto" the side with the most room
 * that fits the card wins (bottom, top, right, left); with no hole the card
 * is centred. The result is always inside the viewport margins.
 */
export function placeCard(
  hole: Box | null, card: Size, viewport: Size, preferred: Placement = 'auto', gap = 14,
): { top: number; left: number; placement: ResolvedPlacement } {
  const maxLeft = viewport.width - card.width - VIEWPORT_MARGIN
  const maxTop = viewport.height - card.height - VIEWPORT_MARGIN
  if (!hole) {
    return {
      top: clamp((viewport.height - card.height) / 2, VIEWPORT_MARGIN, maxTop),
      left: clamp((viewport.width - card.width) / 2, VIEWPORT_MARGIN, maxLeft),
      placement: 'center',
    }
  }
  const room = {
    bottom: viewport.height - (hole.top + hole.height) - gap,
    top: hole.top - gap,
    right: viewport.width - (hole.left + hole.width) - gap,
    left: hole.left - gap,
  }
  const fits = {
    bottom: room.bottom >= card.height + VIEWPORT_MARGIN,
    top: room.top >= card.height + VIEWPORT_MARGIN,
    right: room.right >= card.width + VIEWPORT_MARGIN,
    left: room.left >= card.width + VIEWPORT_MARGIN,
  }
  const order: Exclude<Placement, 'auto'>[] = ['bottom', 'top', 'right', 'left']
  let side: Exclude<Placement, 'auto'> | 'center'
  if (preferred !== 'auto' && fits[preferred]) side = preferred
  else side = order.find((s) => fits[s]) ?? 'center'

  const centreX = hole.left + hole.width / 2 - card.width / 2
  const centreY = hole.top + hole.height / 2 - card.height / 2
  switch (side) {
    case 'bottom': return { top: hole.top + hole.height + gap, left: clamp(centreX, VIEWPORT_MARGIN, maxLeft), placement: side }
    case 'top':    return { top: hole.top - gap - card.height, left: clamp(centreX, VIEWPORT_MARGIN, maxLeft), placement: side }
    case 'right':  return { top: clamp(centreY, VIEWPORT_MARGIN, maxTop), left: hole.left + hole.width + gap, placement: side }
    case 'left':   return { top: clamp(centreY, VIEWPORT_MARGIN, maxTop), left: hole.left - gap - card.width, placement: side }
    default:
      // The hole fills the screen: pin the card to the bottom edge, over the overlay.
      return { top: maxTop, left: clamp(centreX, VIEWPORT_MARGIN, maxLeft), placement: 'center' }
  }
}

/** Is the box actually on screen (not display:none, not zero-sized)? */
export function isVisibleBox(box: Box | null | undefined): box is Box {
  return !!box && box.width > 0 && box.height > 0
}
