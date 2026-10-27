import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'
import type { Library } from '../core/types'
import { useCreateRequest, usePeople } from '../data/api'

/** Ask someone to upload a document. Admin / HR: anyone; Manager: their own department (the database checks). */
export function RequestForm({ library, onClose, onDone }: { library: Library; onClose: () => void; onDone: (msg: string) => void }) {
  const people = usePeople(true)
  const create = useCreateRequest()
  const [assignee, setAssignee] = useState('')
  const [folderId, setFolderId] = useState('')
  const [typeId, setTypeId] = useState('')
  const [due, setDue] = useState('')
  const [note, setNote] = useState('')
  const types = library.types.filter((t) => !folderId || t.folder_id === folderId)
  const person = people.data?.find((p) => p.user_id === assignee)
  return (
    <Modal open onClose={onClose} title="Request a document"
      description="The person who handles the work uploads it; you only say what is needed. It comes back to review.">
      <form className="space-y-4" onSubmit={(e) => {
        e.preventDefault()
        create.mutate({ assignee_user_id: assignee, folder_id: folderId || null, doc_type_id: typeId || null, due_date: due || null, note },
          { onSuccess: () => onDone(`Request sent to ${person?.name ?? 'them'}.`) })
      }}>
        {people.isError && <Alert>{errorMessage(people.error)}</Alert>}
        <Select label="Who should upload it" value={assignee} onChange={(e) => setAssignee(e.target.value)} placeholder="Choose a person" required
          options={(people.data ?? []).map((p) => ({ value: p.user_id, label: p.department ? `${p.name} · ${p.department}` : p.name }))} />
        <Textarea label="What is needed" value={note} onChange={(e) => setNote(e.target.value)} maxLength={1000}
          placeholder="e.g. All transport papers: fitness, tax token and route permit of every vehicle" />
        <div className="grid gap-3 sm:grid-cols-2">
          <Select label="Folder (optional)" value={folderId} onChange={(e) => { setFolderId(e.target.value); setTypeId('') }} placeholder="Any folder"
            options={library.folders.map((f) => ({ value: f.id, label: f.name }))} />
          <Select label="Document type (optional)" value={typeId} onChange={(e) => setTypeId(e.target.value)} placeholder="Any type"
            options={types.map((t) => ({ value: t.id, label: t.name }))} />
        </div>
        <Input label="Due date (optional)" type="date" value={due} onChange={(e) => setDue(e.target.value)}
          hint="Past this date it shows as “Upload overdue” until it is done." />
        {create.isError && <Alert>{errorMessage(create.error)}</Alert>}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button type="submit" loading={create.isPending} disabled={!assignee || (!note.trim() && !typeId)}>Send request</Button>
        </div>
      </form>
    </Modal>
  )
}
