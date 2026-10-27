import { useState } from 'react'
import { Lock } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'
import { FilePicker } from '../../shared/FilePicker'
import type { Priority } from '../core/helpdesk'
import { MAX_FILES, PRIORITIES, PRIORITY_LABEL, ticketNo, ticketProblems } from '../core/helpdesk'
import { useCategories, useCreateTicket } from '../data/api'

/** New ticket: subject, category, priority, description, files. Routing happens in the database. */
export function TicketForm({ orgId, onClose, onCreated }: { orgId: string; onClose: () => void; onCreated: (id: string, message: string) => void }) {
  const categories = useCategories()
  const create = useCreateTicket(orgId)
  const [t, setT] = useState({ subject: '', description: '', category_id: '', priority: 'medium' as Priority })
  const [files, setFiles] = useState<File[]>([])
  const [tried, setTried] = useState(false)
  const problems = ticketProblems(t)
  const chosen = categories.data?.find((c) => c.id === t.category_id)

  const submit = () => {
    setTried(true)
    if (Object.keys(problems).length) return
    create.mutate({ input: { ...t, subject: t.subject.trim(), description: t.description.trim() }, files }, {
      onSuccess: (r) => onCreated(r.id, `Ticket ${ticketNo(r.ticket_no)} raised${r.assigned ? ' and sent to the handler' : '; HR will pick it up'}.`),
    })
  }

  return (
    <Modal open onClose={onClose} title="New ticket" size="lg"
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button><Button loading={create.isPending} onClick={submit}>Raise ticket</Button></>}>
      <div className="space-y-4">
        {create.isError && <Alert>{errorMessage(create.error)}</Alert>}
        <Input label="Subject" name="ticket_subject" maxLength={200} value={t.subject} error={tried ? problems.subject : undefined}
          onChange={(e) => setT({ ...t, subject: e.target.value })} />
        <div className="grid gap-4 sm:grid-cols-2">
          <Select label="Category" name="ticket_category" required value={t.category_id} placeholder="Choose…"
            error={tried ? problems.category_id : undefined}
            onChange={(e) => setT({ ...t, category_id: e.target.value })}
            options={(categories.data ?? []).map((c) => ({ value: c.id, label: c.name }))} />
          <Select label="Priority" name="ticket_priority" value={t.priority}
            onChange={(e) => setT({ ...t, priority: e.target.value as Priority })}
            options={PRIORITIES.map((p) => ({ value: p, label: PRIORITY_LABEL[p].label }))} />
        </div>
        {chosen?.confidential && (
          <p className="flex items-center gap-2 rounded-xl bg-slate-50 p-3 text-sm text-slate-600">
            <Lock className="size-4 shrink-0" aria-hidden /> Confidential: only HR will see this ticket.
          </p>
        )}
        <Textarea label="Description" name="ticket_description" rows={6} maxLength={10000} value={t.description}
          error={tried ? problems.description : undefined} onChange={(e) => setT({ ...t, description: e.target.value })}
          hint="What happened, since when, and what you already tried." />
        <FilePicker files={files} onChange={setFiles} max={MAX_FILES} />
        <p className="text-xs text-slate-500">PDF or images, up to 10 MB each.</p>
      </div>
    </Modal>
  )
}
