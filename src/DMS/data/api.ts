// DMS data hooks (RPCs of 20261104000100_dms_d1_foundation.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { pushEmails, rpc } from '@/communication/shared/api'
import { detectKind } from '../core/dms'
import type {
  ComplianceProfile, DmsDocument, DocumentClauses, DocumentDetail, DocumentFilter, Library, Overview, Person, Setup, Tasks,
} from '../core/types'

const BUCKET = 'dms-documents'

async function sha256Hex(file: File): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function useRefresh() {
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: ['dms'] })
}

export const useLibrary = () => useQuery({ queryKey: ['dms', 'library'], queryFn: () => rpc<Library>('get_dms_library') })
export const useDocuments = (filter: DocumentFilter, enabled = true) =>
  useQuery({ queryKey: ['dms', 'documents', filter], enabled, queryFn: () => rpc<DmsDocument[]>('list_dms_documents', { p: filter }) })
export const useDocument = (id: string | null) =>
  useQuery({ queryKey: ['dms', 'document', id], enabled: !!id, queryFn: () => rpc<DocumentDetail>('get_dms_document', { p_id: id }) })
export const useOverview = (from: string, to: string) =>
  useQuery({ queryKey: ['dms', 'overview', from, to], queryFn: () => rpc<Overview>('get_dms_overview', { p_from: from || null, p_to: to || null }) })
export const useSetup = (enabled: boolean) =>
  useQuery({ queryKey: ['dms', 'setup'], enabled, queryFn: () => rpc<Setup>('get_dms_setup') })
export const useNextCode = (typeId: string, departmentId: string) =>
  useQuery({
    queryKey: ['dms', 'next-code', typeId, departmentId],
    enabled: !!typeId && !!departmentId,
    queryFn: () => rpc<string | null>('dms_next_code', { p_doc_type_id: typeId, p_department_id: departmentId }),
  })

export const useCompliance = (enabled: boolean) =>
  useQuery({ queryKey: ['dms', 'compliance'], enabled, queryFn: () => rpc<ComplianceProfile[]>('get_dms_compliance', { p_profile: null }) })
export const useDocumentClauses = (id: string | null) =>
  useQuery({ queryKey: ['dms', 'clauses', id], enabled: !!id, queryFn: () => rpc<DocumentClauses>('get_dms_document_clauses', { p_id: id }) })

export function useSetClauses() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, tags }: { id: string; tags: { profile: string; clause: string }[] }) => rpc<void>('set_dms_document_clauses', { p_id: id, p_tags: tags }),
    onSuccess: refresh,
  })
}

export const useTasks = () => useQuery({ queryKey: ['dms', 'tasks'], queryFn: () => rpc<Tasks>('list_dms_tasks') })
export const usePeople = (enabled: boolean) =>
  useQuery({ queryKey: ['dms', 'people'], enabled, queryFn: () => rpc<Person[]>('list_dms_people') })

export interface UploadInput {
  file: File
  /** New version of this document; otherwise a new document from `details`. */
  documentId?: string
  /** Uploading for a request: the database fills in what the request fixes. */
  requestId?: string
  details?: Record<string, unknown>
  expiryDate?: string
  fields?: Record<string, string>
  changeNote?: string
}

export interface UploadResult {
  document_id: string; doc_code: string; version_name: string; version: number
  /** published (Admin, or review switched off) or in_review. */
  status: 'published' | 'in_review'
}

export const uploadMessage = (r: UploadResult) =>
  r.status === 'in_review' ? `Saved as ${r.version_name} and sent for review.` : `Saved and published as ${r.version_name}.`

/**
 * Hash → register (the database names it and refuses duplicates before any upload) → upload to the
 * reserved path → confirm (publishes; the previous version is superseded). A failed upload is cancelled.
 */
export function useUpload() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ file, documentId, requestId, details, expiryDate, fields, changeNote }: UploadInput): Promise<UploadResult> => {
      const detected = detectKind(file)
      if ('problem' in detected) throw new Error(detected.problem)
      const reg = await rpc<Omit<UploadResult, 'status'> & { version_id: string; path: string }>('dms_register_upload', {
        p: {
          ...(documentId ? { document_id: documentId } : details),
          ...(requestId ? { request_id: requestId } : {}),
          ...(expiryDate !== undefined ? { expiry_date: expiryDate || null } : {}),
          ...(fields ? { fields } : {}),
          change_note: changeNote || null,
          file: { name: file.name, kind: detected.kind, mime: detected.mime, size_bytes: file.size, hash: await sha256Hex(file) },
        },
      })
      const { error } = await supabase.storage.from(BUCKET).upload(reg.path, file, { contentType: detected.mime, upsert: false })
      if (error) {
        await rpc('dms_cancel_upload', { p_version_id: reg.version_id }).catch(() => undefined)
        throw error
      }
      const done = await rpc<{ status: UploadResult['status'] }>('dms_confirm_upload', { p_version_id: reg.version_id })
      if (done.status === 'in_review') void pushEmails()
      return { ...reg, status: done.status }
    },
    onSuccess: refresh,
  })
}

export function useDecide() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ versionId, approve, comment }: { versionId: string; approve: boolean; comment?: string }) =>
      rpc<{ status: string }>('dms_decide', { p_version_id: versionId, p_approve: approve, p_comment: comment || null }),
    onSuccess: () => { void pushEmails(); return refresh() },
  })
}

export function useCreateRequest() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: (p: Record<string, unknown>) => rpc<string>('create_dms_request', { p }),
    onSuccess: () => { void pushEmails(); return refresh() },
  })
}

export function useCancelRequest() {
  const refresh = useRefresh()
  return useMutation({ mutationFn: (id: string) => rpc<void>('cancel_dms_request', { p_id: id }), onSuccess: refresh })
}

export function useSaveCustodian() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ folderId, userId, active }: { folderId: string; userId: string; active: boolean }) =>
      rpc<void>('save_dms_custodian', { p_folder_id: folderId, p_user_id: userId, p_active: active }),
    onSuccess: refresh,
  })
}

export function useSaveSettings() {
  const refresh = useRefresh()
  return useMutation({ mutationFn: (p: Record<string, unknown>) => rpc<void>('save_dms_settings', { p }), onSuccess: refresh })
}

export function useUpdateDocument() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, p }: { id: string; p: Record<string, unknown> }) => rpc<DmsDocument>('update_dms_document', { p_id: id, p }),
    onSuccess: refresh,
  })
}

export function useArchiveDocument() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, archive }: { id: string; archive: boolean }) => rpc<void>('archive_dms_document', { p_id: id, p_archive: archive }),
    onSuccess: refresh,
  })
}

export function useSaveFolder() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, p }: { id: string | null; p: Record<string, unknown> }) => rpc<string>('save_dms_folder', { p_id: id, p }),
    onSuccess: refresh,
  })
}

export function useSaveDocType() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ id, p }: { id: string | null; p: Record<string, unknown> }) => rpc<string>('save_dms_doc_type', { p_id: id, p }),
    onSuccess: refresh,
  })
}

export function useSetProfiles() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ codes, noIso }: { codes: string[]; noIso: boolean }) => rpc<void>('set_dms_profiles', { p_codes: codes, p_no_iso: noIso }),
    onSuccess: refresh,
  })
}

/** Logs the download, then opens a 60-second signed link named after the document code. */
export async function openFile(versionId: string): Promise<void> {
  const f = await rpc<{ path: string; file_name: string }>('dms_file_path', { p_version_id: versionId })
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(f.path, 60, { download: f.file_name })
  if (error || !data) throw error ?? new Error('The file could not be opened')
  window.open(data.signedUrl, '_blank', 'noopener')
}
