// Sends online-test links to the selected applicants. The links are shown once
// (only their fingerprint is stored): copy them or open a ready email.
import { useState } from 'react'
import { Check, Copy, Mail } from 'lucide-react'
import { testPath } from '@/onboarding-process/core/assessment'
import { useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Button } from '@/components/ui'
import { Modal, Select } from '@/components/kit'

type Link = { applicant_id: string; full_name: string; email: string; token: string }

export function InviteLinksDialog({ postId, postTitle, orgName, applicants, durationMinutes, onClose }: {
  postId: string; postTitle: string; orgName: string; applicants: { id: string; full_name: string }[]
  durationMinutes: number | null; onClose: () => void
}) {
  const invite = useRecruitAction<{ p_job_post_id: string; p_ids: string[]; p_valid_days: number }, Link[]>('invite_to_test')
  const [days, setDays] = useState(3)
  const [copied, setCopied] = useState<string | null>(null)
  const url = (token: string) => `${window.location.origin}${testPath(token)}`
  const copy = async (key: string, text: string) => {
    await navigator.clipboard.writeText(text)
    setCopied(key)
    setTimeout(() => setCopied(null), 1500)
  }
  const mail = (l: Link) => {
    const subject = `Online test for ${postTitle} — ${orgName}`
    const body = `Dear ${l.full_name},\n\nThank you for applying for ${postTitle} at ${orgName}. Please take the online test using this personal link:\n\n${url(l.token)}\n\n`
      + `The test takes ${durationMinutes ?? '—'} minutes and can be taken once. The clock starts when you press Start. The link is valid for ${days} day${days === 1 ? '' : 's'}.\n\nBest regards,\n${orgName}`
    return `mailto:${encodeURIComponent(l.email)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`
  }

  return (
    <Modal open onClose={onClose} size="lg" title="Send online test links"
      description={`${applicants.length} applicant${applicants.length === 1 ? '' : 's'} · email sending comes in the next step; for now copy the links or open a ready email.`}
      footer={invite.isSuccess ? <Button onClick={onClose}>Done</Button> : <>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={invite.isPending} onClick={() => invite.mutate({ p_job_post_id: postId, p_ids: applicants.map((a) => a.id), p_valid_days: days })}>
          Create links
        </Button>
      </>}>
      {invite.isSuccess ? (
        <div className="space-y-3">
          <Alert tone="info">These links are shown only now. Copy them before closing; you can always create a new link later (the old one stops working).</Alert>
          <Button variant="secondary" onClick={() => copy('all', invite.data.map((l) => `${l.full_name} <${l.email}>: ${url(l.token)}`).join('\n'))}>
            {copied === 'all' ? <Check className="size-4" /> : <Copy className="size-4" />}Copy all
          </Button>
          <ul className="divide-y divide-slate-100 rounded-xl ring-1 ring-slate-200">
            {invite.data.map((l) => (
              <li key={l.applicant_id} className="flex flex-wrap items-center gap-2 p-3">
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">{l.full_name}</p>
                  <p className="truncate text-xs text-slate-500">{url(l.token)}</p>
                </div>
                <Button variant="ghost" aria-label={`Copy the link for ${l.full_name}`} onClick={() => copy(l.applicant_id, url(l.token))}>
                  {copied === l.applicant_id ? <Check className="size-4" /> : <Copy className="size-4" />}
                </Button>
                <a href={mail(l)} className="inline-flex items-center gap-1 rounded-lg px-2 py-1.5 text-sm text-primary-700 hover:bg-primary-50">
                  <Mail className="size-4" />Email</a>
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <div className="space-y-4">
          {invite.isError && <Alert>{errorMessage(invite.error)}</Alert>}
          <p className="text-sm text-slate-600">{applicants.map((a) => a.full_name).join(', ')}</p>
          <Select label="The link stays valid for" value={String(days)} onChange={(e) => setDays(Number(e.target.value))}
            options={[1, 2, 3, 5, 7, 14].map((d) => ({ value: String(d), label: `${d} day${d === 1 ? '' : 's'}` }))} />
          <p className="text-xs text-slate-500">Sending the first link locks the objective paper so everyone gets the same questions (in a shuffled order).</p>
        </div>
      )}
    </Modal>
  )
}
