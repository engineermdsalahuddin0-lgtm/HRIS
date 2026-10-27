// Everything the widget needs for one role, derived from the setup in one place, so the
// floating widget and "Test as role" always behave the same.
import { useMemo } from 'react'
import { canReadResource, effectiveTopics } from '../core/access'
import { buildUpdates } from '../core/digest'
import type { RoleKey } from '../core/types'
import { SAMPLE_SNAPSHOT } from './sampleData'
import { questionsUsedToday, useAssistantStore } from './store'

export function useAssistantFor(role: RoleKey) {
  const setup = useAssistantStore((s) => s.setup)
  const usage = useAssistantStore((s) => s.usage)
  return useMemo(() => {
    const allowed = effectiveTopics(setup, role)
    const readable = setup.resources.filter((r) => canReadResource(r, role, allowed))
    const updates = buildUpdates(allowed, SAMPLE_SNAPSHOT, readable)
    const limit = setup.dailyLimit[role]
    const used = questionsUsedToday(usage)
    return {
      setup,
      allowed,
      readable,
      updates,
      messages: setup.messages[role],
      /** D1: Updates work without a key; only Ask needs it. */
      canAsk: setup.keyStatus === 'tested' && readable.length > 0,
      visible: setup.enabled && setup.roleEnabled[role],
      left: limit == null ? null : Math.max(0, limit - used),
    }
  }, [setup, usage, role])
}
