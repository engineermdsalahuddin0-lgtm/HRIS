// The full applicant profile (row click). R3 adds the parsed CV, ATS breakdown and scores here.
import { useRef, useState } from 'react'
import { ExternalLink, Upload } from 'lucide-react'
import type { Applicant, JobPost } from '@/onboarding-process/core/types'
import { APPLICANT_STATUS_LABEL, CV_ACCEPT, SOURCE_LABEL } from '@/onboarding-process/core/jobPost'
import { openCv, useUploadApplicantCv } from '@/lib/recruit'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button } from '@/components/ui'
import { Modal } from '@/components/kit'

const EVENT_LABEL: Record<string, string> = {
  applied: 'Applied on the careers page', added_by_hr: 'Added by HR', cv_uploaded: 'CV uploaded', cv_attached: 'CV uploaded by HR',
}

export function ApplicantDialog({ applicant: a, post, onClose }: { applicant: Applicant; post: JobPost; onClose: () => void }) {
  const ctx = useMyContext()
  const upload = useUploadApplicantCv(ctx.organization?.id, post.id)
  const input = useRef<HTMLInputElement>(null)
  const [error, setError] = useState<string | null>(null)

  const view = () => a.cv_path && openCv(a.cv_path).catch((e) => setError(errorMessage(e)))

  return (
    <Modal open onClose={onClose} size="lg" title={a.full_name}
      description={<>{post.title} · <Badge>{APPLICANT_STATUS_LABEL[a.status]}</Badge></>}>
      <div className="space-y-5">
        {(error || upload.error) && <Alert>{error ?? errorMessage(upload.error)}</Alert>}
        <dl className="grid gap-3 text-sm sm:grid-cols-2">
          <div><dt className="text-xs text-slate-500">Email</dt><dd className="font-medium break-all">{a.email}</dd></div>
          <div><dt className="text-xs text-slate-500">Mobile</dt><dd className="font-medium">{a.phone ?? '—'}</dd></div>
          <div><dt className="text-xs text-slate-500">Source</dt><dd className="font-medium">{SOURCE_LABEL[a.source]}</dd></div>
          <div><dt className="text-xs text-slate-500">Data consent</dt><dd className="font-medium">
            {a.consent_at ? formatDateTime(a.consent_at) : 'Sent the CV to us directly'}</dd></div>
        </dl>
        {a.cover_note && (
          <div>
            <p className="mb-1 text-xs text-slate-500">Note from the applicant</p>
            <p className="whitespace-pre-wrap rounded-xl bg-slate-50 p-3 text-sm text-slate-700">{a.cover_note}</p>
          </div>
        )}
        <div className="flex flex-wrap items-center gap-2 rounded-xl border border-slate-200 p-3">
          <p className="mr-auto text-sm text-slate-700">{a.has_cv ? 'CV on file (deleted when the vacancy closes)' : 'No CV yet'}</p>
          {a.has_cv && <Button variant="secondary" onClick={view}><ExternalLink className="size-4" />Open CV</Button>}
          <input ref={input} type="file" accept={CV_ACCEPT} className="hidden" onChange={(e) => {
            const file = e.target.files?.[0]
            e.target.value = ''
            if (file) upload.mutate({ applicantId: a.id, file, previous: a.cv_path })
          }} />
          <Button variant={a.has_cv ? 'ghost' : 'primary'} loading={upload.isPending} onClick={() => input.current?.click()}>
            <Upload className="size-4" />{a.has_cv ? 'Replace' : 'Upload CV'}
          </Button>
        </div>
        <div>
          <p className="mb-2 text-sm font-medium text-slate-900">History</p>
          <ol className="space-y-2 border-l border-slate-200 pl-4 text-sm">
            {a.events.map((event, index) => (
              <li key={index} className="relative">
                <span className="absolute -left-[21px] top-1.5 size-2.5 rounded-full bg-primary-500" />
                <p className="font-medium text-slate-800">{EVENT_LABEL[event.event] ?? event.event.replaceAll('_', ' ')}</p>
                <p className="text-xs text-slate-500">{event.actor_name ?? 'Applicant'} · {formatDateTime(event.created_at)}</p>
              </li>
            ))}
          </ol>
        </div>
      </div>
    </Modal>
  )
}
