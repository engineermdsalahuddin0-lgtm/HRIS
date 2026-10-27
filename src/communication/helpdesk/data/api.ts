// Helpdesk data hooks (RPCs of 20261102000200_comm_c2_helpdesk.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { attachmentProblem, rpc, safeFileName } from '../../shared/api'
import type { Priority, Sla, TicketStatus } from '../core/helpdesk'
import { MAX_FILES } from '../core/helpdesk'

export type Scope = 'mine' | 'assigned' | 'all'

export interface TicketRow {
  id: string
  ticket_no: number
  subject: string
  priority: Priority
  status: TicketStatus
  category_id: string
  category: string
  confidential: boolean
  requester_employee_id: string
  requester: string
  assignee_employee_id: string | null
  assignee: string | null
  created_at: string
  updated_at: string
  resolved_at: string | null
  closed_at: string | null
  closed_reason: 'rated' | 'auto' | 'manual' | null
  rating: number | null
  response_due_at: string
  resolution_due_at: string
  response_breached: boolean
  resolution_breached: boolean
}

export interface TicketList {
  scope: Scope
  can_handle: boolean
  can_manage: boolean
  kpis: { open: number; in_progress: number; sla_breach: number; my_tickets: number; resolved_today: number }
  tickets: TicketRow[]
}

export interface FileRef { path: string; name: string; type: string }

export interface TicketMessage {
  id: string
  kind: 'reply' | 'note' | 'event'
  body: string
  attachments: FileRef[]
  created_at: string
  author: string | null
  mine: boolean
  from_staff: boolean
}

export interface TicketDetail extends TicketRow {
  description: string
  rating_comment: string | null
  reopen_count: number
  first_response_at: string | null
  access: 'manage' | 'handler' | 'requester'
  sla: { response_due_at: string; resolution_due_at: string; response_breached: boolean; resolution_breached: boolean; paused: boolean; resolution_left_minutes: number | null }
  can: { reply: boolean; note: boolean; status: boolean; assign: boolean; close: boolean; rate: boolean; reopen: boolean }
  messages: TicketMessage[]
}

export interface Category { id: string; name: string; confidential: boolean }
export interface SetupCategory extends Category { status: 'active' | 'inactive'; sort: number; handler_employee_id: string | null; handler: string | null }
export interface Handler { employee_id: string; full_name: string; card_id: string; can_confidential: boolean }
export interface HelpdeskSetup { settings: { sla: Sla; auto_close_days: number }; categories: SetupCategory[]; handlers: Handler[] }

const BUCKET = 'helpdesk-files'

function useRefresh() {
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: ['helpdesk'] })
}

export const useTickets = (scope: Scope) =>
  useQuery({ queryKey: ['helpdesk', 'list', scope], queryFn: () => rpc<TicketList>('list_tickets', { p_scope: scope }) })
export const useTicket = (id: string | undefined) =>
  useQuery({ queryKey: ['helpdesk', 'ticket', id], enabled: !!id, queryFn: () => rpc<TicketDetail>('get_ticket', { p_id: id }) })
export const useCategories = () =>
  useQuery({ queryKey: ['helpdesk', 'categories'], queryFn: () => rpc<Category[]>('list_helpdesk_categories') })
export const useHelpdeskSetup = (enabled: boolean) =>
  useQuery({ queryKey: ['helpdesk', 'setup'], enabled, queryFn: () => rpc<HelpdeskSetup>('get_helpdesk_setup') })

/** Uploads files into helpdesk-files/{org}/{ticket}/ (the storage policy checks the ticket). */
async function uploadFiles(orgId: string, ticketId: string, files: File[]): Promise<FileRef[]> {
  if (files.length > MAX_FILES) throw new Error(`At most ${MAX_FILES} files per message`)
  for (const f of files) {
    const problem = attachmentProblem(f, 10)
    if (problem) throw new Error(`${f.name}: ${problem}`)
  }
  const out: FileRef[] = []
  for (const f of files) {
    const path = `${orgId}/${ticketId}/${Date.now()}-${safeFileName(f.name)}`
    const { error } = await supabase.storage.from(BUCKET).upload(path, f, { contentType: f.type, upsert: false })
    if (error) throw error
    out.push({ path, name: f.name.slice(0, 200), type: f.type })
  }
  return out
}

/** Raise a ticket; files are added right after as the first message (they need the ticket to exist). */
export function useCreateTicket(orgId: string) {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ input, files }: { input: { subject: string; description: string; category_id: string; priority: Priority }; files: File[] }) => {
      const created = await rpc<{ id: string; ticket_no: number; assigned: boolean }>('create_ticket', { p: input })
      if (files.length) {
        const attachments = await uploadFiles(orgId, created.id, files)
        await rpc('reply_ticket', { p_id: created.id, p: { body: '', attachments } })
      }
      return created
    },
    onSuccess: refresh,
  })
}

export function useReply(orgId: string, ticketId: string) {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ body, internal, status, files }: { body: string; internal: boolean; status: TicketStatus | null; files: File[] }) => {
      const attachments = files.length ? await uploadFiles(orgId, ticketId, files) : []
      await rpc('reply_ticket', { p_id: ticketId, p: { body, internal, attachments, status } })
    },
    onSuccess: refresh,
  })
}

export function useTicketAction<A extends Record<string, unknown>>(fn: 'set_ticket_status' | 'assign_ticket' | 'rate_ticket' | 'reopen_ticket') {
  const refresh = useRefresh()
  return useMutation({ mutationFn: (args: A) => rpc<void>(fn, args), onSuccess: refresh })
}

export function useSaveHelpdeskSettings() {
  const refresh = useRefresh()
  return useMutation({ mutationFn: (p: { sla: Sla; auto_close_days: number }) => rpc<void>('save_helpdesk_settings', { p }), onSuccess: refresh })
}

export function useSaveCategory() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, p }: { id: string | null; p: Record<string, unknown> }) => rpc<string>('save_helpdesk_category', { p_id: id, p }),
    onSuccess: refresh,
  })
}

export async function ticketFileUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 300)
  if (error || !data) throw error ?? new Error('The file could not be opened')
  return data.signedUrl
}
