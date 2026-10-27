import { useState } from 'react'
import { Check, X } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button } from '@/components/ui'
import { Textarea } from '@/components/kit'
import { useDecide } from '../data/api'

/** Approve publishes the version; reject sends it back with the reason (required). */
export function ReviewDecision({ versionId, onDone }: { versionId: string; onDone: (approved: boolean) => void }) {
  const decide = useDecide()
  const [comment, setComment] = useState('')
  const [needReason, setNeedReason] = useState(false)
  return (
    <div className="space-y-2">
      <Textarea label="Comment" value={comment} onChange={(e) => { setComment(e.target.value); setNeedReason(false) }} maxLength={1000}
        placeholder="Optional when approving; required when sending back" error={needReason ? 'Write why it is sent back, so the uploader can fix it' : undefined} />
      {decide.isError && <Alert>{errorMessage(decide.error)}</Alert>}
      <div className="flex flex-wrap gap-2">
        <Button loading={decide.isPending && decide.variables?.approve}
          onClick={() => decide.mutate({ versionId, approve: true, comment }, { onSuccess: () => onDone(true) })}>
          <Check className="size-4" /> Approve and publish
        </Button>
        <Button variant="secondary" loading={decide.isPending && !decide.variables?.approve}
          onClick={() => {
            if (comment.trim().length < 3) return setNeedReason(true)
            decide.mutate({ versionId, approve: false, comment }, { onSuccess: () => onDone(false) })
          }}>
          <X className="size-4" /> Send back
        </Button>
      </div>
    </div>
  )
}
