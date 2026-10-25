// Request a vacancy by hand. Managers may request only for their own department;
// a replacement needs an open sanctioned position (the database checks both).
import { useMemo, useState } from 'react'
import type { VacancyReason } from '@/onboarding-process/core/types'
import { useWorkforceAction } from '@/lib/onboarding'
import { useOrgStructure } from '@/lib/hr'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Input, Spinner } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'

export function DraftVacancyDialog({ onClose }: { onClose: () => void }) {
  const structure = useOrgStructure()
  const draft = useWorkforceAction<{ p: Record<string, unknown> }, string>('draft_vacancy')
  const [departmentId, setDepartmentId] = useState('')
  const [designationId, setDesignationId] = useState('')
  const [seats, setSeats] = useState('1')
  const [reason, setReason] = useState<VacancyReason>('replacement')
  const [note, setNote] = useState('')
  const departments = useMemo(() => (structure.data?.departments ?? []).filter((d) => d.status === 'active'), [structure.data])
  const designations = useMemo(() => (structure.data?.designations ?? [])
    .filter((d) => d.status === 'active' && d.department_id === departmentId), [structure.data, departmentId])
  return (
    <Modal open onClose={onClose} title="Request a vacancy"
      description="HR reviews the request and someone else approves it."
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={draft.isPending} disabled={!departmentId || !designationId || !(Number(seats) >= 1)}
          onClick={() => draft.mutate({ p: { department_id: departmentId, designation_id: designationId, seats: Number(seats), reason, note } },
            { onSuccess: onClose })}>Request</Button>
      </>}>
      {structure.isPending ? <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
        : structure.isError ? <Alert>{errorMessage(structure.error)}</Alert> : (
          <div className="space-y-4">
            {draft.isError && <Alert>{errorMessage(draft.error)}</Alert>}
            <Select label="Department" required value={departmentId} placeholder="Choose a department"
              onChange={(e) => { setDepartmentId(e.target.value); setDesignationId('') }}
              options={departments.map((d) => ({ value: d.id, label: d.name }))} />
            <Select label="Designation" required value={designationId} placeholder="Choose a designation" disabled={!departmentId}
              onChange={(e) => setDesignationId(e.target.value)} options={designations.map((d) => ({ value: d.id, label: d.name }))} />
            <div className="grid gap-4 sm:grid-cols-2">
              <Select label="Reason" value={reason} onChange={(e) => setReason(e.target.value as VacancyReason)}
                hint={reason === 'replacement' ? 'Fills an open sanctioned position' : 'Raises the sanctioned headcount when approved'}
                options={[{ value: 'replacement', label: 'Replacement' }, { value: 'new_position', label: 'New position' }]} />
              <Input label="Seats" inputMode="numeric" value={seats} onChange={(e) => setSeats(e.target.value)} />
            </div>
            <Textarea label="Why is it needed?" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
          </div>
        )}
    </Modal>
  )
}
