import type { Session } from '@supabase/supabase-js'
import { create } from 'zustand'
import { supabase } from '@/lib/supabase'
import { queryClient } from '@/lib/queryClient'
import type { MyContext } from '@/lib/types'

interface SessionState {
  status: 'loading' | 'ready'
  session: Session | null
  context: MyContext | null
  contextError: string | null
  init: () => () => void
  refreshContext: () => Promise<void>
  signOut: () => Promise<void>
}

async function fetchContext(): Promise<MyContext> {
  const { data, error } = await supabase.rpc('get_my_context')
  if (error) throw error
  return data as MyContext
}

export const useSession = create<SessionState>((set, get) => ({
  status: 'loading',
  session: null,
  context: null,
  contextError: null,

  init: () => {
    const load = async (session: Session | null) => {
      if (!session) {
        set({ status: 'ready', session: null, context: null, contextError: null })
        return
      }
      // Keep showing the loader until we know the user's organization and role.
      set({ session, status: get().context ? 'ready' : 'loading' })
      try {
        set({ context: await fetchContext(), contextError: null, status: 'ready' })
      } catch (e) {
        set({ context: null, contextError: (e as Error).message, status: 'ready' })
      }
    }

    supabase.auth.getSession().then(({ data }) => load(data.session))
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      // A token refresh does not change who the user is.
      if (event === 'TOKEN_REFRESHED') {
        set({ session })
        return
      }
      if (event === 'SIGNED_IN' || event === 'SIGNED_OUT' || event === 'USER_UPDATED') {
        // Deferred: calling supabase inside this callback can deadlock the auth lock.
        setTimeout(() => load(session), 0)
      }
    })
    return () => sub.subscription.unsubscribe()
  },

  refreshContext: async () => {
    if (!get().session) return
    set({ context: await fetchContext() })
  },

  signOut: async () => {
    await supabase.auth.signOut()
    queryClient.clear()
    set({ session: null, context: null })
  },
}))

/** For showing/hiding UI only. The database enforces every permission. */
export function useCan(permission: string): boolean {
  return useSession((s) => s.context?.permissions.includes(permission) ?? false)
}
