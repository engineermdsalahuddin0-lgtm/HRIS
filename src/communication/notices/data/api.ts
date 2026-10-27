// Notices data hooks (RPCs of 20261102000100_comm_c1_notices.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { appBaseUrl, attachmentProblem, pushEmails, rpc, safeFileName } from '../../shared/api'
import type { Audience, NoticeCategory, ShownStatus } from '../core/notices'

export interface Notice {
  id: string
  category: NoticeCategory
  title: string
  title_bn: string | null
  body: string
  body_bn: string | null
  audience: Audience
  department_ids: string[]
  branch_ids: string[]
  employee_ids: string[]
  pinned: boolean
  requires_ack: boolean
  email_copy: boolean
  status: 'draft' | 'published' | 'archived'
  shown_status: ShownStatus
  publish_at: string | null
  expires_at: string | null
  attachment_path: string | null
  attachment_name: string | null
  attachment_type: string | null
  email_queued_at: string | null
  last_reminded_at: string | null
  created_at: string
  updated_at: string
  author: string | null
  audience_label: string
}

export interface MyNotice extends Notice { read: boolean; acknowledged_at: string | null }
export interface ManagedNotice extends Notice { targets: number; portal: number; reads: number; acks: number }
export interface OpenedNotice extends MyNotice { can_manage: boolean; in_audience: boolean }

export interface ManageList {
  kpis: { total: number; pinned: number; active: number; this_month: number }
  can_target_all: boolean
  notices: ManagedNotice[]
}

export interface Receipt {
  employee_id: string
  full_name: string
  card_id: string
  department: string | null
  has_portal: boolean
  first_read_at: string | null
  acknowledged_at: string | null
}

export interface NoticeAlerts {
  pinned: { id: string; title: string; title_bn: string | null; category: NoticeCategory; read: boolean }[]
  unread: number
  pending_ack: number
}

const KEYS = ['notices']
const BUCKET = 'notice-files'

function useRefresh() {
  const qc = useQueryClient()
  return () => Promise.all(KEYS.map((k) => qc.invalidateQueries({ queryKey: [k] })))
}

export const useMyNotices = () => useQuery({ queryKey: ['notices', 'mine'], queryFn: () => rpc<MyNotice[]>('my_notices') })
export const useNoticeAlerts = () =>
  useQuery({ queryKey: ['notices', 'alerts'], queryFn: () => rpc<NoticeAlerts>('my_notice_alerts'), staleTime: 60_000 })
export const useManageNotices = (enabled: boolean) =>
  useQuery({ queryKey: ['notices', 'manage'], enabled, queryFn: () => rpc<ManageList>('list_notices_manage') })
export const useReceipts = (id: string | null) =>
  useQuery({ queryKey: ['notices', 'receipts', id], enabled: !!id, queryFn: () => rpc<Receipt[]>('notice_receipts', { p_id: id }) })

/** Opening records the read; the list is refreshed so the unread dot goes away. */
export function useOpenNotice(id: string | null) {
  const qc = useQueryClient()
  return useQuery({
    queryKey: ['notice-open', id],
    enabled: !!id,
    queryFn: async () => {
      const n = await rpc<OpenedNotice>('open_notice', { p_id: id })
      void qc.invalidateQueries({ queryKey: ['notices', 'mine'] })
      void qc.invalidateQueries({ queryKey: ['notices', 'alerts'] })
      return n
    },
  })
}

export function useAcknowledge() {
  const qc = useQueryClient()
  const refresh = useRefresh()
  return useMutation({
    mutationFn: (id: string) => rpc<string>('acknowledge_notice', { p_id: id }),
    onSuccess: (_, id) => Promise.all([refresh(), qc.invalidateQueries({ queryKey: ['notice-open', id] })]),
  })
}

export interface SaveInput { id: string | null; payload: Record<string, unknown>; file: File | null; removeFile: boolean; orgId: string; publish: boolean }
export interface SaveResult { id: string; publish?: { status: ShownStatus; emails_queued: number; email_skipped: string | null } }

/**
 * Save (draft first when new), upload the attachment into notice-files/{org}/{notice}/,
 * then publish when asked. A file needs the notice to exist, hence the two saves for new notices.
 */
export function useSaveNotice() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ id, payload, file, removeFile, orgId, publish }: SaveInput): Promise<SaveResult> => {
      if (file) {
        const problem = attachmentProblem(file, 10)
        if (problem) throw new Error(problem)
      }
      let noticeId = await rpc<string>('save_notice', { p_id: id, p: payload })
      if (file) {
        const path = `${orgId}/${noticeId}/${Date.now()}-${safeFileName(file.name)}`
        const { error } = await supabase.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false })
        if (error) throw error
        noticeId = await rpc<string>('save_notice', {
          p_id: noticeId, p: { ...payload, attachment_path: path, attachment_name: file.name.slice(0, 200), attachment_type: file.type },
        })
      } else if (removeFile) {
        noticeId = await rpc<string>('save_notice', { p_id: noticeId, p: { ...payload, attachment_path: null } })
      }
      if (!publish) return { id: noticeId }
      const result = await rpc<SaveResult['publish']>('publish_notice', { p_id: noticeId, p_base_url: appBaseUrl() })
      if (result && result.emails_queued > 0) void pushEmails()
      return { id: noticeId, publish: result }
    },
    onSuccess: refresh,
  })
}

export function usePublishNotice() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await rpc<NonNullable<SaveResult['publish']>>('publish_notice', { p_id: id, p_base_url: appBaseUrl() })
      if (result.emails_queued > 0) void pushEmails()
      return result
    },
    onSuccess: refresh,
  })
}

export function useNoticeAction<A extends Record<string, unknown>>(fn: 'set_notice_pin' | 'archive_notice') {
  const refresh = useRefresh()
  return useMutation({ mutationFn: (args: A) => rpc<void>(fn, args), onSuccess: refresh })
}

export function useRemind() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async (id: string) => {
      const result = await rpc<{ emails_queued: number }>('remind_notice_ack', { p_id: id, p_base_url: appBaseUrl() })
      if (result.emails_queued > 0) void pushEmails()
      return result
    },
    onSuccess: refresh,
  })
}

/** Short signed URL for the attachment (the storage policy checks who may read it). */
export async function attachmentUrl(path: string): Promise<string> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, 300)
  if (error || !data) throw error ?? new Error('The file could not be opened')
  return data.signedUrl
}
