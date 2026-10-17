// Remembers per browser whether a guide was finished or skipped, and opens it
// automatically the first time. Bump the version in the key to show a guide
// again after it changes ("dashboard-v2").
import { useCallback, useEffect, useState } from 'react'

const storageKey = (tourKey: string) => `olympus.tour.${tourKey}`

function readSeen(tourKey: string): boolean {
  try {
    return window.localStorage.getItem(storageKey(tourKey)) !== null
  } catch {
    return false // private mode / blocked storage: just behave as unseen
  }
}

function writeSeen(tourKey: string, outcome: 'completed' | 'skipped') {
  try {
    window.localStorage.setItem(storageKey(tourKey), outcome)
  } catch {
    // Storage unavailable: the guide may show again next time, which is harmless.
  }
}

export function useSpotlightTour(tourKey: string, { autoStart = true, delayMs = 600 } = {}) {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    if (!autoStart || readSeen(tourKey)) return
    // Give the page a moment to render its data before the first step.
    const timer = window.setTimeout(() => setOpen(true), delayMs)
    return () => window.clearTimeout(timer)
  }, [tourKey, autoStart, delayMs])

  const start = useCallback(() => setOpen(true), [])
  const close = useCallback((completed: boolean) => {
    writeSeen(tourKey, completed ? 'completed' : 'skipped')
    setOpen(false)
  }, [tourKey])

  return { open, start, close }
}
