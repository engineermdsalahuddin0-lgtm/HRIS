// DMS data hooks (RPCs of 20261104000100_dms_d1_foundation.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { rpc } from '@/communication/shared/api'
import { detectKind } from '../core/dms'
import type { DmsDocument, DocumentDetail, DocumentFilter, Library, Overview, Setup } from '../core/types'

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

export interface UploadInput {
  file: File
  /** New version of this document; otherwise a new document from `details`. */
  documentId?: string
  details?: Record<string, unknown>
  expiryDate?: string
  fields?: Record<string, string>
  changeNote?: string
}

export interface UploadResult { document_id: string; doc_code: string; version_name: string; version: number }

/**
 * Hash → register (the database names it and refuses duplicates before any upload) → upload to the
 * reserved path → confirm (publishes; the previous version is superseded). A failed upload is cancelled.
 */
export function useUpload() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ file, documentId, details, expiryDate, fields, changeNote }: UploadInput): Promise<UploadResult> => {
      const detected = detectKind(file)
      if ('problem' in detected) throw new Error(detected.problem)
      const reg = await rpc<UploadResult & { version_id: string; path: string }>('dms_register_upload', {
        p: {
          ...(documentId ? { document_id: documentId } : details),
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
      await rpc('dms_confirm_upload', { p_version_id: reg.version_id })
      return reg
    },
    onSuccess: refresh,
  })
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
