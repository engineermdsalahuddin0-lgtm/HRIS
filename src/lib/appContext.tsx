import { createContext, useContext } from 'react'
import type { MyContext } from '@/lib/types'
import { useSession } from '@/stores/session'

/**
 * Lets the dev-only /preview route render the app shell with a mock user,
 * without touching the real session store.
 */
export const PreviewContext = createContext<MyContext | null>(null)

export function useMyContext(): MyContext {
  const preview = useContext(PreviewContext)
  const real = useSession((s) => s.context)
  return (preview ?? real)!
}

export function useIsPreview(): boolean {
  return useContext(PreviewContext) !== null
}
