import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ChevronDown, FileText } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Select } from '@/components/kit'
import { defaultExpiry, titleFromFileName, typesForFolder } from '../core/dms'
import type { DmsDocument, DmsRequest, Library } from '../core/types'
import type { UploadResult } from '../data/api'
import { useDocuments, useNextCode, useUpload } from '../data/api'
import { AccessFields, TypeFields, type Access } from './FieldInputs'
import { FileDrop } from './FileDrop'

/**
 * New document: the user picks (or is given) the folder, the type and drops a file. Everything else
 * has a default; the name is shown before saving. Existing documents of the same type and department
 * are offered as "upload a new version" so the same paper is never saved twice.
 */
export function UploadForm({ library, folderId: givenFolder, request, onDone, onNewVersion }: {
  library: Library
  /** Upload inside this folder; without it the user picks a category. */
  folderId: string | null
  /** Uploading for a request: its folder, type and department are fixed. */
  request?: DmsRequest
  onDone: (r: UploadResult) => void
  onNewVersion: (doc: DmsDocument) => void
}) {
  const upload = useUpload()
  const folderId = request?.folder_id ?? givenFolder
  const categories = useMemo(() => library.folders.filter((f) => f.origin !== 'custom' && library.types.some((t) => t.folder_id === f.id)),
    [library])
  const [category, setCategory] = useState(folderId ? '' : (categories[0]?.id ?? ''))
  const targetFolder = folderId ?? category
  const types = typesForFolder(library.types, library.folders, targetFolder || null)
  const [typeId, setTypeId] = useState(request?.doc_type_id ?? (types.length === 1 ? types[0].id : ''))
  const type = library.types.find((t) => t.id === typeId)
  const [departmentId, setDepartmentId] = useState(request?.department_id ??
    (library.departments.some((d) => d.id === library.my_department_id) ? library.my_department_id! : (library.departments[0]?.id ?? '')))
  // A request fixes the department; the database checks its code.
  const department = request ? { id: request.department_id, name: request.department ?? '', code: 'set' } : library.departments.find((d) => d.id === departmentId)
  const [file, setFile] = useState<File | null>(null)
  const [title, setTitle] = useState('')
  const [expiry, setExpiry] = useState(defaultExpiry(type))
  const [fields, setFields] = useState<Record<string, string>>({})
  const [more, setMore] = useState(false)
  const [access, setAccess] = useState<Access>({
    classification: type?.default_classification ?? 'internal', scope: 'company', scope_department_ids: [], restricted_role_ids: [],
  })
  const [language, setLanguage] = useState('en')

  const nextCode = useNextCode(typeId, departmentId)
  const existing = useDocuments({ doc_type_id: typeId, department_id: departmentId }, !!typeId && !!departmentId)
  const folderName = library.folders.find((f) => f.id === (folderId ?? type?.folder_id ?? category))?.name

  const pickType = (id: string) => {
    const t = library.types.find((x) => x.id === id)
    setTypeId(id)
    setExpiry(defaultExpiry(t))
    setFields({})
    setAccess((a) => ({ ...a, classification: t?.default_classification ?? 'internal' }))
  }
  const pickCategory = (id: string) => {
    setCategory(id)
    const own = typesForFolder(library.types, library.folders, id)
    pickType(own.length === 1 ? own[0].id : '')
  }
  const pickFile = (f: File | null) => {
    setFile(f)
    if (f && !title) setTitle(titleFromFileName(f.name))
  }

  const submit = () => {
    if (!file || !type) return
    upload.mutate({
      file,
      requestId: request?.id,
      expiryDate: type.has_expiry ? expiry : undefined,
      details: {
        title, folder_id: folderId ?? type.folder_id, doc_type_id: type.id, department_id: departmentId,
        fields, language, ...access,
      },
    }, {
      onSuccess: (r) => {
        setFile(null); setTitle(''); setFields({}); setExpiry(defaultExpiry(type))
        onDone(r)
      },
    })
  }

  if (library.types.length === 0) {
    return <Alert tone="info">No document types are switched on yet. Ask the person who manages documents to open Setup.</Alert>
  }
  const sameTitle = existing.data?.find((d) => d.title.trim().toLowerCase() === title.trim().toLowerCase())

  return (
    <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); submit() }}>
      {request && (
        <Alert tone="info">
          Requested by {request.requested_by}{request.due_date ? ` — due ${request.due_date}` : ''}{request.note ? `: ${request.note}` : ''}
        </Alert>
      )}
      {!folderId && (
        <Select label="Category" value={category} onChange={(e) => pickCategory(e.target.value)}
          options={categories.map((f) => ({ value: f.id, label: f.name }))} />
      )}
      <Select label="Document type" value={typeId} onChange={(e) => pickType(e.target.value)} placeholder="Choose…"
        options={types.map((t) => ({ value: t.id, label: t.name }))} />
      {!request && library.departments.length > 1 ? (
        <Select label="Department" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}
          options={library.departments.map((d) => ({ value: d.id, label: d.name }))} />
      ) : department && <p className="text-sm text-slate-600">Department: <span className="font-medium">{department.name}</span></p>}
      {department && !department.code && (
        <Alert>
          “{department.name}” has no short code yet, so its documents cannot be named.{' '}
          <Link to="/organization" className="font-medium underline">Add one in Organization → Departments</Link> (e.g. HR, ACC).
        </Alert>
      )}

      <FileDrop file={file} onFile={pickFile} />
      <Input label="Title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Trade Licence Dhaka" required />

      {type?.has_expiry && (
        <Input label="Expiry date" type="date" value={expiry} onChange={(e) => setExpiry(e.target.value)} required
          hint={type.expiry_default === 'fiscal_year_end' ? 'Set to 30 June (end of the fiscal year); change it if the licence says otherwise.' : undefined} />
      )}
      {type && <TypeFields schema={type.field_schema} values={fields} onChange={setFields} />}

      {existing.data && existing.data.length > 0 && (
        <div className="rounded-xl bg-slate-50 p-3 text-sm">
          <p className="font-medium text-slate-700">Already in the library ({type?.name}, {department?.name}):</p>
          <ul className="mt-2 space-y-1">
            {existing.data.slice(0, 5).map((d) => (
              <li key={d.id} className="flex flex-wrap items-center gap-2">
                <FileText className="size-4 text-slate-400" aria-hidden />
                <span className="font-mono text-xs">{d.version_name}</span>
                <span className="text-slate-700">{d.title}</span>
                <button type="button" className="ml-auto text-xs font-medium text-primary-700 hover:underline" onClick={() => onNewVersion(d)}>
                  Upload as its new version
                </button>
              </li>
            ))}
          </ul>
          {sameTitle && <p className="mt-2 text-xs text-red-600">A document with this title exists. Upload the file as its new version instead.</p>}
        </div>
      )}

      <button type="button" onClick={() => setMore(!more)} className="inline-flex items-center gap-1 text-sm font-medium text-slate-600 hover:text-slate-900">
        <ChevronDown className={more ? 'size-4 rotate-180' : 'size-4'} aria-hidden /> More (who can read it, language)
      </button>
      {more && (
        <div className="space-y-3 rounded-xl ring-1 ring-slate-200 p-3">
          <AccessFields value={access} onChange={setAccess} library={library} />
          <Select label="Language" value={language} onChange={(e) => setLanguage(e.target.value)}
            options={[{ value: 'en', label: 'English' }, { value: 'bn', label: 'বাংলা' }, { value: 'both', label: 'Both' }]} />
        </div>
      )}

      {nextCode.data && (
        <p className="rounded-xl bg-primary-50 px-3 py-2 text-sm text-primary-800">
          Will be saved as <span className="font-mono font-semibold">{nextCode.data}_v1</span>{folderName ? <> in {folderName}</> : null}
        </p>
      )}
      {upload.isError && <Alert>{errorMessage(upload.error)}</Alert>}
      <Button type="submit" className="w-full" loading={upload.isPending}
        disabled={!file || !type || !department?.code || !title.trim() || !!sameTitle}>
        Upload
      </Button>
    </form>
  )
}
