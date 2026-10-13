import { useRef, useState } from 'react'
import { FileText, ImageUp, Trash2 } from 'lucide-react'
import type { EmployeeFileKind } from '@/lib/files'
import { FILE_RULES, useEmployeeFiles, useRemoveEmployeeFile, useUploadEmployeeFile, validateFile } from '@/lib/files'
import { errorMessage } from '@/lib/identity'
import type { EmployeeProfile } from '@/lib/hr'
import { useMyContext } from '@/lib/appContext'
import { Alert, Button, Card } from '@/components/ui'

/** Which files the caller may replace (the storage policy enforces the same rule). */
export function useFileRights(profile: EmployeeProfile) {
  const ctx = useMyContext()
  const isAdmin = ctx.role?.system_key === 'admin'
  const e = profile.employee
  const canEdit = isAdmin || e.is_self || ctx.permissions.includes('employees.edit')
  return {
    photo: canEdit,
    signature: canEdit,
    nid: isAdmin || (profile.editable_fields ?? []).includes('employee_sensitive.nid_number'),
  } satisfies Record<EmployeeFileKind, boolean>
}

function Slot({
  kind,
  url,
  isPdf,
  canWrite,
  busy,
  onPick,
  onRemove,
}: {
  kind: EmployeeFileKind
  url?: string
  isPdf?: boolean
  canWrite: boolean
  busy: boolean
  onPick: (f: File) => void
  onRemove: () => void
}) {
  const input = useRef<HTMLInputElement>(null)
  const rule = FILE_RULES[kind]
  return (
    <div className="flex flex-col gap-3 rounded-xl border border-slate-200 p-3">
      <p className="text-sm font-medium text-slate-700">{rule.label}</p>
      <div
        className={
          kind === 'signature'
            ? 'flex h-24 items-center justify-center overflow-hidden rounded-lg bg-slate-50'
            : 'flex h-40 items-center justify-center overflow-hidden rounded-lg bg-slate-50'
        }
      >
        {url ? (
          isPdf ? (
            <a href={url} target="_blank" rel="noreferrer" className="flex flex-col items-center gap-1 text-sm text-primary-700">
              <FileText className="size-8" /> Open PDF
            </a>
          ) : (
            <a href={url} target="_blank" rel="noreferrer" className="h-full w-full">
              <img src={url} alt={rule.label} className="h-full w-full object-contain" />
            </a>
          )
        ) : (
          <span className="text-xs text-slate-400">{canWrite ? 'Not uploaded' : 'Not uploaded or hidden'}</span>
        )}
      </div>
      {canWrite && (
        <div className="flex gap-2">
          <input
            ref={input}
            type="file"
            accept={rule.accept}
            className="hidden"
            onChange={(ev) => {
              const f = ev.target.files?.[0]
              if (f) onPick(f)
              ev.target.value = ''
            }}
          />
          <Button variant="secondary" className="flex-1" loading={busy} onClick={() => input.current?.click()}>
            <ImageUp className="size-4" /> {url ? 'Replace' : 'Upload'}
          </Button>
          {url && (
            <Button variant="ghost" onClick={onRemove} aria-label={`Remove ${rule.label}`}>
              <Trash2 className="size-4" />
            </Button>
          )}
        </div>
      )}
      <p className="text-[11px] text-slate-400">
        Max {Math.round(rule.maxBytes / 1024 / 1024)} MB · {kind === 'nid' ? 'JPG, PNG, WEBP or PDF' : 'JPG, PNG or WEBP'}
      </p>
    </div>
  )
}

export function EmployeeFilesCard({ profile }: { profile: EmployeeProfile }) {
  const ctx = useMyContext()
  const orgId = ctx.organization?.id
  const e = profile.employee
  const files = useEmployeeFiles(orgId, e.id)
  const upload = useUploadEmployeeFile(orgId, e.id)
  const remove = useRemoveEmployeeFile(orgId, e.id)
  const rights = useFileRights(profile)
  const [error, setError] = useState<string | null>(null)
  const [busyKind, setBusyKind] = useState<EmployeeFileKind | null>(null)

  const pick = async (kind: EmployeeFileKind, file: File) => {
    setError(null)
    const problem = validateFile(kind, file)
    if (problem) return setError(problem)
    setBusyKind(kind)
    try {
      await upload.mutateAsync({ kind, file })
    } catch (err) {
      setError(errorMessage(err))
    } finally {
      setBusyKind(null)
    }
  }

  return (
    <Card className="lg:col-span-2">
      <h3 className="mb-1 font-semibold text-slate-900">Photo, signature & NID</h3>
      <p className="mb-4 text-sm text-slate-500">Stored privately. Used on the ID card. NID scans are visible only to roles allowed to see the NID.</p>
      {error && <div className="mb-3"><Alert>{error}</Alert></div>}
      <div className="grid gap-4 sm:grid-cols-3">
        {(['photo', 'signature', 'nid'] as EmployeeFileKind[]).map((kind) => (
          <Slot
            key={kind}
            kind={kind}
            url={files.data?.[kind]?.url}
            isPdf={files.data?.[kind]?.isPdf}
            canWrite={rights[kind]}
            busy={busyKind === kind}
            onPick={(f) => pick(kind, f)}
            onRemove={() => confirm(`Remove ${FILE_RULES[kind].label.toLowerCase()}?`) && remove.mutate(kind)}
          />
        ))}
      </div>
    </Card>
  )
}
