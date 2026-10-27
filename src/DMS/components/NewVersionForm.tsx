import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { renewalExpiry } from '../core/dms'
import type { DmsDocument, DocType } from '../core/types'
import type { UploadResult } from '../data/api'
import { useUpload } from '../data/api'
import { FileDrop } from './FileDrop'
import { TypeFields } from './FieldInputs'

/** A changed file or a licence renewal: same code, next version. */
export function NewVersionForm({ doc, type, onDone }: { doc: DmsDocument; type: DocType | undefined; onDone: (r: UploadResult) => void }) {
  const upload = useUpload()
  const [file, setFile] = useState<File | null>(null)
  const [expiry, setExpiry] = useState(renewalExpiry(type, doc.expiry_date))
  const [fields, setFields] = useState<Record<string, string>>(doc.fields ?? {})
  const [note, setNote] = useState('')
  return (
    <form className="space-y-4" onSubmit={(e) => {
      e.preventDefault()
      if (file) upload.mutate({ file, documentId: doc.id, expiryDate: doc.has_expiry ? expiry : undefined, fields, changeNote: note }, { onSuccess: onDone })
    }}>
      <p className="text-sm text-slate-600">
        Will be saved as <span className="font-mono font-semibold">{doc.doc_code}_v{doc.version + 1}</span>; the current file stays in the history.
      </p>
      <FileDrop file={file} onFile={setFile} />
      {doc.has_expiry && (
        <Input label="New expiry date" type="date" value={expiry} onChange={(e) => setExpiry(e.target.value)} required
          hint={type?.expiry_default === 'fiscal_year_end' ? 'Set to the next 30 June; change it if the licence says otherwise.' : undefined} />
      )}
      {type && <TypeFields schema={type.field_schema} values={fields} onChange={setFields} />}
      <Input label="What changed (optional)" value={note} onChange={(e) => setNote(e.target.value)} maxLength={500}
        placeholder={doc.has_expiry ? 'e.g. Renewed for 2027-28' : 'e.g. Section 4 updated'} />
      {upload.isError && <Alert>{errorMessage(upload.error)}</Alert>}
      <Button type="submit" className="w-full" loading={upload.isPending} disabled={!file || (doc.has_expiry && !expiry)}>
        Upload new version
      </Button>
    </form>
  )
}
