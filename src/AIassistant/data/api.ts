// Real data layer of the AI assistant (RPCs of 20261103000100_assistant_ai1_foundation.sql and later steps,
// plus the Edge Function "assistant"). Replaces data/store.ts screen by screen (design doc section 11).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export type ChatProvider = 'anthropic' | 'openai' | 'google'
export type EmbedProvider = 'openai' | 'google' | 'voyage'
export type KeySlot = 'chat' | 'embed'

export interface ServerHyper {
  temperature: number
  max_answer_tokens: number
  answer_style: 'short' | 'detailed'
  top_k: number
  min_score: number
  chunk_size: number
  chunk_overlap: number
}

export interface KeyInfo { provider: string; model: string; last4: string | null; status: 'saved' | 'tested' | 'failed'; tested_at: string | null; message: string | null }

export interface ServerTopic { key: string; group: 'updates' | 'knowledge'; label: string; hint: string; needs_any_of: string[]; sensitive: boolean }

export interface ServerRole {
  id: string
  name: string
  system_key: 'admin' | 'hr_manager' | 'manager' | 'employee' | null
  status: string
  enabled: boolean
  daily_limit: number | null
  messages: { greeting: string; suggestions: string[]; notice: string; not_allowed: string }
  ticks: Record<string, boolean>
  usable: Record<string, boolean>
}

export interface ServerSetup {
  is_admin: boolean
  settings: { enabled: boolean; name: string; language_mode: 'follow' | 'bn' | 'en'; hyper: ServerHyper; monthly_token_cap: number | null; retention_days: number }
  hr_can_manage: boolean
  keys: {
    chat: KeyInfo | null
    embed: KeyInfo | null
    embed_effective: { slot: KeySlot; provider: EmbedProvider; model: string; ready: boolean } | null
  }
  models: { chat: Record<ChatProvider, { id: string; label: string }[]>; embed: Record<EmbedProvider, { id: string; label: string }[]> }
  topics: ServerTopic[]
  roles: ServerRole[]
  resources_ready: number
}

export async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

/** Calls the Edge Function "assistant"; turns its JSON error into a readable message. */
export async function callAssistant<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke('assistant', { body })
  if (error) {
    const context = (error as { context?: Response }).context
    const detail = context && typeof context.json === 'function' ? await context.json().catch(() => null) : null
    throw new Error(detail?.error ?? (error.message.includes('Failed to send') ? 'The assistant function is not deployed yet' : error.message))
  }
  return data as T
}

const KEY = ['assistant', 'setup']

export const useServerSetup = (enabled = true) =>
  useQuery({ queryKey: KEY, enabled, queryFn: () => rpc<ServerSetup>('get_assistant_setup') })

function useSetupMutation<A, R>(fn: (a: A) => Promise<R>) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: fn, onSuccess: () => qc.invalidateQueries({ queryKey: ['assistant'] }) })
}

export const useSaveSettings = () =>
  useSetupMutation((p: { enabled: boolean; name: string; language_mode: string; monthly_token_cap?: number | null }) => rpc('save_assistant_settings', { p }))

export const useDelegation = () => useSetupMutation((on: boolean) => rpc('set_assistant_delegation', { p_on: on }))

/** Save the key, then let the Edge Function make one tiny call to prove it works. */
export const useSaveKey = () =>
  useSetupMutation(async (p: { slot: KeySlot; provider: string; model: string; api_key: string | null }) => {
    await rpc('save_assistant_key', { p })
    return callAssistant<{ ok: boolean; message: string }>({ action: 'test_key', slot: p.slot })
  })

export const useTestKey = () => useSetupMutation((slot: KeySlot) => callAssistant<{ ok: boolean; message: string }>({ action: 'test_key', slot }))
export const useRemoveKey = () => useSetupMutation((slot: KeySlot) => rpc('remove_assistant_key', { p_slot: slot }))

/** Returns resource ids that need processing again (changed chunking). */
export const useSaveHyper = () => useSetupMutation((p: ServerHyper) => rpc<string[]>('save_assistant_hyper', { p }))

export const useSaveMatrix = () =>
  useSetupMutation((roles: { role_id: string; enabled: boolean; daily_limit: number | null; ticks: Record<string, boolean> }[]) =>
    rpc('save_assistant_role_matrix', { p: { roles } }))

export const useSaveRoleMessages = () =>
  useSetupMutation(({ roleId, messages }: { roleId: string; messages: ServerRole['messages'] }) =>
    rpc('save_assistant_role_messages', { p_role_id: roleId, p: messages }))
