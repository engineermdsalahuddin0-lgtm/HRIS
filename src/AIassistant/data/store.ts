// Preview data layer: the whole setup lives in this browser (localStorage) until the backend
// steps (AI1–AI5) exist. Pages talk only to this store, so swapping it for RPC hooks later
// does not touch the UI. The API key itself is never stored here, only its last 4 characters.
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { DEFAULT_SETUP } from '../core/catalog'
import { estimateDocument } from '../core/resources'
import type { AssistantSetup, Hyperparameters, ProviderKey, Resource } from '../core/types'

const STORE_KEY = 'olympus.ai-assistant.v1'

const PROCESSING_MS = 2500

interface Usage { day: string; count: number }

interface AssistantStore {
  setup: AssistantSetup
  usage: Usage
  update: (patch: Partial<AssistantSetup>) => void
  setKeyResult: (provider: ProviderKey, last4: string, ok: boolean) => void
  removeKey: () => void
  setHyper: (hyper: Hyperparameters) => void
  addResource: (resource: Resource) => void
  updateResource: (id: string, patch: Partial<Resource>) => void
  loadSamples: () => Promise<void>
  countQuestion: () => void
  reset: () => void
}

const today = () => new Date().toISOString().slice(0, 10)

// Stand-in for the backend worker: a processing resource becomes ready after a short wait.
const timers = new Map<string, ReturnType<typeof setTimeout>>()
function finishLater(id: string) {
  if (timers.has(id)) return
  timers.set(id, setTimeout(() => {
    timers.delete(id)
    useAssistantStore.getState().updateResource(id, { status: 'ready' })
  }, PROCESSING_MS))
}

export const useAssistantStore = create<AssistantStore>()(
  persist(
    (set, get) => ({
      setup: DEFAULT_SETUP,
      usage: { day: today(), count: 0 },
      update: (patch) => set({ setup: { ...get().setup, ...patch } }),
      setKeyResult: (provider, last4, ok) =>
        set({ setup: { ...get().setup, provider, keyLast4: last4, keyStatus: ok ? 'tested' : 'failed', keyCheckedAt: new Date().toISOString() } }),
      removeKey: () => set({ setup: { ...get().setup, keyLast4: null, keyStatus: 'missing', keyCheckedAt: null } }),
      setHyper: (hyper) => {
        const before = get().setup.hyper
        const rechunk = before.chunkSize !== hyper.chunkSize || before.chunkOverlap !== hyper.chunkOverlap
        // New chunk settings mean every document is split again.
        const resources = rechunk
          ? get().setup.resources.map((r) =>
              r.status === 'ready' && r.kind !== 'json'
                ? { ...r, status: 'processing' as const, chunks: estimateDocument(r.sizeBytes, hyper.chunkSize, hyper.chunkOverlap).chunks }
                : r)
          : get().setup.resources
        set({ setup: { ...get().setup, hyper, resources } })
        resources.filter((r) => r.status === 'processing').forEach((r) => finishLater(r.id))
      },
      addResource: (resource) => {
        set({ setup: { ...get().setup, resources: [resource, ...get().setup.resources] } })
        if (resource.status === 'processing') finishLater(resource.id)
      },
      updateResource: (id, patch) => {
        set({ setup: { ...get().setup, resources: get().setup.resources.map((r) => (r.id === id ? { ...r, ...patch } : r)) } })
        if (patch.status === 'processing') finishLater(id)
      },
      loadSamples: async () => {
        // Loaded on demand: the store is in the first download (sidebar), the samples are not.
        const { SAMPLE_RESOURCES } = await import('./sampleData')
        const have = new Set(get().setup.resources.map((r) => r.id))
        set({ setup: { ...get().setup, resources: [...SAMPLE_RESOURCES.filter((r) => !have.has(r.id)), ...get().setup.resources] } })
      },
      countQuestion: () => {
        const u = get().usage
        set({ usage: u.day === today() ? { ...u, count: u.count + 1 } : { day: today(), count: 1 } })
      },
      reset: () => set({ setup: DEFAULT_SETUP, usage: { day: today(), count: 0 } }),
    }),
    {
      name: STORE_KEY,
      storage: createJSONStorage(() => localStorage),
      onRehydrateStorage: () => (state) => {
        state?.setup.resources.filter((r) => r.status === 'processing').forEach((r) => finishLater(r.id))
      },
    },
  ),
)

export const questionsUsedToday = (usage: Usage) => (usage.day === today() ? usage.count : 0)
