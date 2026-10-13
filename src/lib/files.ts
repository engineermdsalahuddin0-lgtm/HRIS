// Private file storage: employee photo / signature / NID scan and the company logo.
// Paths: employee-files/{org}/{employee}/{kind}, org-assets/{org}/logo.
// The database (storage policies) decides who may read or write each file.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export type EmployeeFileKind = 'photo' | 'signature' | 'nid'

export const FILE_RULES: Record<EmployeeFileKind | 'logo', { accept: string; maxBytes: number; label: string }> = {
  photo: { accept: 'image/jpeg,image/png,image/webp', maxBytes: 2 * 1024 * 1024, label: 'Photo' },
  signature: { accept: 'image/jpeg,image/png,image/webp', maxBytes: 1024 * 1024, label: 'Signature' },
  nid: { accept: 'image/jpeg,image/png,image/webp,application/pdf', maxBytes: 5 * 1024 * 1024, label: 'NID scan' },
  logo: { accept: 'image/jpeg,image/png,image/webp', maxBytes: 2 * 1024 * 1024, label: 'Logo' },
}

/** Client-side check before upload (the bucket enforces the same limits). */
export function validateFile(kind: keyof typeof FILE_RULES, file: File): string | null {
  const rule = FILE_RULES[kind]
  if (!rule.accept.split(',').includes(file.type)) return `${rule.label}: use ${rule.accept.replace(/image\/|application\//g, '').toUpperCase()}`
  if (file.size > rule.maxBytes) return `${rule.label} must be under ${Math.round(rule.maxBytes / 1024 / 1024)} MB`
  return null
}

const employeePath = (orgId: string, employeeId: string, kind: EmployeeFileKind) => `${orgId}/${employeeId}/${kind}`

/** Signed URLs for the files that exist (and that the caller may read). */
export function useEmployeeFiles(orgId: string | undefined, employeeId: string | undefined) {
  return useQuery({
    queryKey: ['files', 'employee', employeeId],
    enabled: !!orgId && !!employeeId,
    staleTime: 10 * 60_000,
    queryFn: async () => {
      const bucket = supabase.storage.from('employee-files')
      const { data: listed } = await bucket.list(`${orgId}/${employeeId}`)
      const names = new Set((listed ?? []).map((f) => f.name))
      const result: Partial<Record<EmployeeFileKind, { url: string; isPdf: boolean }>> = {}
      for (const kind of ['photo', 'signature', 'nid'] as EmployeeFileKind[]) {
        if (!names.has(kind)) continue
        const { data } = await bucket.createSignedUrl(employeePath(orgId!, employeeId!, kind), 3600)
        const meta = listed?.find((f) => f.name === kind)?.metadata as { mimetype?: string } | undefined
        if (data?.signedUrl) result[kind] = { url: data.signedUrl, isPdf: meta?.mimetype === 'application/pdf' }
      }
      return result
    },
  })
}

export function useUploadEmployeeFile(orgId: string | undefined, employeeId: string | undefined) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ kind, file }: { kind: EmployeeFileKind; file: File }) => {
      const problem = validateFile(kind, file)
      if (problem) throw new Error(problem)
      const { error } = await supabase.storage
        .from('employee-files')
        .upload(employeePath(orgId!, employeeId!, kind), file, { upsert: true, contentType: file.type, cacheControl: '60' })
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['files', 'employee', employeeId] }),
  })
}

export function useRemoveEmployeeFile(orgId: string | undefined, employeeId: string | undefined) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (kind: EmployeeFileKind) => {
      const { error } = await supabase.storage.from('employee-files').remove([employeePath(orgId!, employeeId!, kind)])
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['files', 'employee', employeeId] }),
  })
}

export function useOrgLogo(orgId: string | undefined) {
  return useQuery({
    queryKey: ['files', 'logo', orgId],
    enabled: !!orgId,
    staleTime: 10 * 60_000,
    queryFn: async () => {
      const bucket = supabase.storage.from('org-assets')
      const { data: listed } = await bucket.list(orgId!)
      if (!listed?.some((f) => f.name === 'logo')) return null
      const { data } = await bucket.createSignedUrl(`${orgId}/logo`, 3600)
      return data?.signedUrl ?? null
    },
  })
}

export function useUploadOrgLogo(orgId: string | undefined) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (file: File | null) => {
      const bucket = supabase.storage.from('org-assets')
      if (!file) {
        const { error } = await bucket.remove([`${orgId}/logo`])
        if (error) throw error
        return
      }
      const problem = validateFile('logo', file)
      if (problem) throw new Error(problem)
      const { error } = await bucket.upload(`${orgId}/logo`, file, { upsert: true, contentType: file.type, cacheControl: '60' })
      if (error) throw error
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['files', 'logo', orgId] }),
  })
}

/** QR payload printed on ID cards: always resolved inside a known organization. */
export function idCardQrPayload(orgCode: string, cardId: string) {
  return `OLYMPUS:${orgCode}:${cardId}`
}
