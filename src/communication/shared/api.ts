// Shared data helpers of the communication module: RPC call, permission check, the app
// address for links in emails, safe storage file names, and the email push.
import { supabase } from '@/lib/supabase'
import type { MyContext } from '@/lib/types'

export async function rpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

/** UI check only (Admin holds every permission); the database enforces the same rule. */
export const can = (ctx: MyContext, key: string) => ctx.permissions.includes(key)

/** Base address for links in emails (the database checks its shape). */
export const appBaseUrl = () => window.location.origin

/** Storage object names: letters, digits, dot, dash and underscore only. */
export function safeFileName(name: string): string {
  const dot = name.lastIndexOf('.')
  const base = (dot > 0 ? name.slice(0, dot) : name).normalize('NFKD').replace(/[^A-Za-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'file'
  const ext = dot > 0 ? name.slice(dot + 1).toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8) : ''
  return ext ? `${base}.${ext}` : base
}

export const ATTACHMENT_TYPES = ['application/pdf', 'image/jpeg', 'image/png', 'image/webp']

export function attachmentProblem(file: File, maxMb: number): string | null {
  if (!ATTACHMENT_TYPES.includes(file.type)) return 'Use a PDF, JPG, PNG or WebP file'
  if (file.size > maxMb * 1024 * 1024) return `The file must be under ${maxMb} MB`
  return null
}

/**
 * Asks the existing Edge Function recruit-notify to send queued emails now. Best effort:
 * when it is not deployed or no channel is set up, the emails stay queued.
 */
export async function pushEmails(): Promise<void> {
  try {
    await supabase.functions.invoke('recruit-notify', { body: { action: 'send' } })
  } catch {
    // Queued emails go out with the next push.
  }
}
