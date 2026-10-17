// Spotlight guide ("dark mask" onboarding): a 70% dark overlay over the whole
// screen with a hole punched around one element per step, and a step card
// beside it. Built for production use:
//   * targets by CSS selector (prefer [data-tour="…"]); a list of selectors
//     picks the first one that is visible (e.g. sidebar on desktop, menu
//     button on phones); missing optional targets are skipped
//   * follows the target on scroll, resize and layout changes
//   * keyboard: → / Enter next, ← back, Esc close; focus stays in the card
//     and returns to where it was when the guide closes
//   * respects prefers-reduced-motion; the page behind cannot be clicked
import type { ReactNode } from 'react'
import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { ArrowLeft, ArrowRight, Check, X } from 'lucide-react'
import { cx } from '@/components/ui'
import type { Box, Placement } from './geometry'
import { holeFor, isVisibleBox, placeCard } from './geometry'

export interface SpotlightStep {
  /** CSS selector(s) of the element to light up; omit for a centred step. */
  target?: string | string[]
  title: string
  body: ReactNode
  placement?: Placement
  /** Space between the element and the edge of the hole (px). Default 8. */
  padding?: number
  /** Corner radius of the hole (px). Default 14. */
  radius?: number
  /** Skip this step when its target is not on the page (default true). */
  optional?: boolean
}

export interface SpotlightTourProps {
  steps: SpotlightStep[]
  open: boolean
  /** completed = the user reached the last step and pressed Finish. */
  onClose: (completed: boolean) => void
  startAt?: number
  /** How long to wait for a target that is still rendering (ms). Default 1500. */
  waitForTargetMs?: number
}

const CARD_WIDTH = 340

function findTarget(target: SpotlightStep['target']): HTMLElement | null {
  if (!target) return null
  for (const selector of Array.isArray(target) ? target : [target]) {
    for (const element of document.querySelectorAll<HTMLElement>(selector)) {
      const rect = element.getBoundingClientRect()
      if (rect.width > 0 && rect.height > 0) return element
    }
  }
  return null
}

/** The target is in the page but hidden (e.g. a desktop-only badge on a phone): no point waiting. */
function existsButHidden(target: SpotlightStep['target']): boolean {
  if (!target) return false
  return (Array.isArray(target) ? target : [target]).some((selector) => document.querySelector(selector) !== null)
}

const toBox = (rect: DOMRect): Box => ({ top: rect.top, left: rect.left, width: rect.width, height: rect.height })
const prefersReducedMotion = () =>
  typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

export function SpotlightTour({ steps, open, onClose, startAt = 0, waitForTargetMs = 1500 }: SpotlightTourProps) {
  const [index, setIndex] = useState(startAt)
  const [element, setElement] = useState<HTMLElement | null>(null)
  const [hole, setHole] = useState<Box | null>(null)
  const [cardSize, setCardSize] = useState({ width: CARD_WIDTH, height: 200 })
  const [viewport, setViewport] = useState({ width: window.innerWidth, height: window.innerHeight })
  const [ready, setReady] = useState(false)
  const cardRef = useRef<HTMLDivElement>(null)
  const directionRef = useRef<1 | -1>(1)
  const returnFocusRef = useRef<HTMLElement | null>(null)
  const titleId = useId()
  const bodyId = useId()
  const reduced = prefersReducedMotion()
  const step = steps[index]

  // Reset when (re)opened; remember the focused element to restore later.
  useEffect(() => {
    if (!open) return
    returnFocusRef.current = document.activeElement as HTMLElement | null
    directionRef.current = 1
    setIndex(startAt)
    return () => returnFocusRef.current?.focus?.()
  }, [open, startAt])

  const close = useCallback((completed: boolean) => onClose(completed), [onClose])

  // Resolve the step's target (waiting briefly for content that is still
  // loading); skip optional steps whose target never appears.
  useEffect(() => {
    if (!open || !step) return
    setReady(false)
    if (!step.target) {
      setElement(null)
      setReady(true)
      return
    }
    let cancelled = false
    const started = performance.now()
    const look = () => {
      if (cancelled) return
      const found = findTarget(step.target)
      if (found) {
        found.scrollIntoView({ block: 'center', inline: 'nearest', behavior: reduced ? 'auto' : 'smooth' })
        setElement(found)
        setReady(true)
      } else if (!existsButHidden(step.target) && performance.now() - started < waitForTargetMs) {
        window.setTimeout(look, 100)
      } else if (step.optional !== false) {
        const next = index + directionRef.current
        if (next >= 0 && next < steps.length) setIndex(next)
        else close(false)
      } else {
        setElement(null)
        setReady(true)
      }
    }
    look()
    return () => { cancelled = true }
  }, [open, step, index, steps.length, waitForTargetMs, reduced, close])

  // Keep the hole on the element while the page scrolls, resizes or reflows.
  useLayoutEffect(() => {
    if (!open || !ready) return
    let frame = 0
    const measure = () => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const size = { width: window.innerWidth, height: window.innerHeight }
        setViewport(size)
        const box = element ? toBox(element.getBoundingClientRect()) : null
        setHole(isVisibleBox(box) ? holeFor(box, step?.padding ?? 8, size) : null)
        if (cardRef.current) setCardSize({ width: cardRef.current.offsetWidth, height: cardRef.current.offsetHeight })
      })
    }
    measure()
    window.addEventListener('resize', measure)
    window.addEventListener('scroll', measure, true)
    const observer = new ResizeObserver(measure)
    if (element) observer.observe(element)
    if (cardRef.current) observer.observe(cardRef.current)
    return () => {
      cancelAnimationFrame(frame)
      window.removeEventListener('resize', measure)
      window.removeEventListener('scroll', measure, true)
      observer.disconnect()
    }
  }, [open, ready, element, step])

  const go = useCallback((delta: 1 | -1) => {
    const next = index + delta
    if (next < 0) return
    if (next >= steps.length) { close(true); return }
    directionRef.current = delta
    setIndex(next)
  }, [index, steps.length, close])

  // Keyboard control and a focus trap inside the card.
  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') { event.preventDefault(); close(false) }
      else if (event.key === 'ArrowRight') { event.preventDefault(); go(1) }
      else if (event.key === 'ArrowLeft') { event.preventDefault(); go(-1) }
      else if (event.key === 'Tab' && cardRef.current) {
        const focusable = [...cardRef.current.querySelectorAll<HTMLElement>('button:not([disabled])')]
        if (focusable.length === 0) return
        const first = focusable[0]
        const last = focusable[focusable.length - 1]
        if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
        else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
      }
    }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, go, close])

  // Move focus to the primary button on every step so screen readers read it.
  useEffect(() => {
    if (open && ready) cardRef.current?.querySelector<HTMLElement>('[data-primary]')?.focus({ preventScroll: true })
  }, [open, ready, index])

  if (!open || !step) return null

  const radius = step.radius ?? 14
  const position = placeCard(hole, cardSize, viewport, step.placement ?? 'auto')
  const motion = reduced ? '' : 'transition-all duration-300 ease-out'
  const isLast = index === steps.length - 1

  return createPortal(
    <div className="fixed inset-0 z-[100] print:hidden" aria-hidden={false}>
      {/* Click shield: the page behind is not interactive during the guide. */}
      <div className="absolute inset-0" onClick={(e) => e.stopPropagation()} />

      {/* The mask: one element whose huge shadow darkens everything except the hole. */}
      {hole ? (
        <div className={cx('pointer-events-none absolute', motion)} style={{
          top: hole.top, left: hole.left, width: hole.width, height: hole.height, borderRadius: radius,
          boxShadow: '0 0 0 9999px rgba(15, 23, 42, 0.7)',
        }}>
          <div className="absolute inset-0 rounded-[inherit] ring-2 ring-primary-400/90 ring-offset-0" />
        </div>
      ) : (
        <div className={cx('pointer-events-none absolute inset-0 bg-slate-900/70', motion)} />
      )}

      {/* Step card */}
      <div ref={cardRef} role="dialog" aria-modal="true" aria-labelledby={titleId} aria-describedby={bodyId}
        className={cx('absolute rounded-2xl bg-white p-5 shadow-2xl ring-1 ring-slate-200', motion, !ready && 'opacity-0')}
        style={{ top: position.top, left: position.left, width: `min(${CARD_WIDTH}px, calc(100vw - 24px))` }}>
        <div className="flex items-start justify-between gap-3">
          <p className="text-xs font-medium text-primary-700" aria-live="polite">Step {index + 1} of {steps.length}</p>
          <button type="button" onClick={() => close(false)} aria-label="Close guide"
            className="-m-1 rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700"><X className="size-4" /></button>
        </div>
        <h2 id={titleId} className="mt-1 text-base font-semibold text-slate-900">{step.title}</h2>
        <div id={bodyId} className="mt-1.5 text-sm leading-relaxed text-slate-600">{step.body}</div>

        <div className="mt-4 flex items-center gap-1.5" aria-hidden>
          {steps.map((_, dot) => (
            <span key={dot} className={cx('h-1.5 rounded-full transition-all', dot === index ? 'w-5 bg-primary-600' : 'w-1.5 bg-slate-200')} />
          ))}
        </div>

        <div className="mt-4 flex items-center justify-between gap-2">
          <button type="button" onClick={() => close(false)} className="rounded-lg px-2 py-1.5 text-sm text-slate-500 hover:text-slate-800">
            Skip guide
          </button>
          <div className="flex gap-2">
            {index > 0 && (
              <button type="button" onClick={() => go(-1)}
                className="inline-flex items-center gap-1 rounded-xl px-3 py-2 text-sm font-medium text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50">
                <ArrowLeft className="size-4" />Back
              </button>
            )}
            <button type="button" data-primary onClick={() => go(1)}
              className="inline-flex items-center gap-1 rounded-xl bg-primary-600 px-3.5 py-2 text-sm font-medium text-white hover:bg-primary-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600">
              {isLast ? <><Check className="size-4" />Finish</> : <>Next<ArrowRight className="size-4" /></>}
            </button>
          </div>
        </div>
      </div>
    </div>,
    document.body,
  )
}
