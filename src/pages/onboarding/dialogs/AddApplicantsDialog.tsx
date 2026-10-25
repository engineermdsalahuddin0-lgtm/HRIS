// Add people who sent their CV by email, LinkedIn, Bdjobs or a referral.
// Paste rows (name, email, phone); the same email for this post is skipped.
import { useState } from 'react'
import type { ApplicantSource } from '@/onboarding-process/core/types'
import { SOURCE_LABEL, parseApplicantRows } from '@/onboarding-process/core/jobPost'
import { useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'

export function AddApplicantsDialog({ postId, onClose }: { postId: string; onClose: () => void }) {
  const add = useRecruitAction<{ p_job_post_id: string; p_rows: unknown[]; p_source: string }, { added: number; duplicates: number }>('add_applicants')
  const [source, setSource] = useState<Exclude<ApplicantSource, 'form'>>('email')
  const [text, setText] = useState('')
  const parsed = parseApplicantRows(text)

  return (
    <Modal open onClose={onClose} size="lg" title="Add applicants"
      description="For CVs that came by email, LinkedIn, Bdjobs or a referral. Upload each CV from the applicant's profile afterwards."
      footer={add.isSuccess ? <Button onClick={onClose}>Done</Button> : <>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={add.isPending} disabled={parsed.rows.length === 0 || parsed.rows.length > 200}
          onClick={() => add.mutate({ p_job_post_id: postId, p_rows: parsed.rows, p_source: source })}>
          Add {parsed.rows.length || ''} applicant{parsed.rows.length === 1 ? '' : 's'}
        </Button>
      </>}>
      {add.isSuccess ? (
        <Alert tone="success">
          Added {add.data.added}.{add.data.duplicates > 0 && ` Skipped ${add.data.duplicates} already on the list (same email).`}
        </Alert>
      ) : (
        <div className="space-y-4">
          {add.isError && <Alert>{errorMessage(add.error)}</Alert>}
          <Select label="Where did they apply?" value={source} onChange={(e) => setSource(e.target.value as typeof source)}
            options={(Object.keys(SOURCE_LABEL) as ApplicantSource[]).filter((s) => s !== 'form').map((s) => ({ value: s, label: SOURCE_LABEL[s] }))} />
          <Textarea label="One person per line: name, email, mobile" rows={8} value={text} onChange={(e) => setText(e.target.value)}
            placeholder={'Karim Ahmed, karim@example.com, 01811000002\nSadia Islam, sadia@example.com'}
            hint="Copy rows from Excel or type them. Up to 200 at a time." />
          {parsed.errors.length > 0 && <Alert>{parsed.errors.slice(0, 5).join(' · ')}</Alert>}
          {parsed.rows.length > 0 && <p className="text-sm text-slate-600">{parsed.rows.length} ready to add.</p>}
        </div>
      )}
    </Modal>
  )
}
