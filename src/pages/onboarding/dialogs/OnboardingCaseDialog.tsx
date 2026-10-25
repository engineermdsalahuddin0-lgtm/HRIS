// The joining checklist of one new employee: tasks, the four documents (print, upload the
// signed scan), the named feedback, and completing the case.
import { useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { CheckCircle2, Printer, Upload } from 'lucide-react'
import type { DocumentKind } from '@/onboarding-process/core/joining'
import { DOCUMENT_LABEL, FEEDBACK_QUESTIONS, TASK_LABEL, printPage } from '@/onboarding-process/core/joining'
import { useOnboardingCase, useRecruitAction } from '@/lib/recruit'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Spinner } from '@/components/ui'
import { Checkbox, Modal } from '@/components/kit'
import { OpenFile } from './OfferDialogs'

const localToday = () => new Date().toLocaleDateString('en-CA')

export function OnboardingCaseDialog({ caseId, onClose }: { caseId: string; onClose: () => void }) {
  const c = useOnboardingCase(caseId)
  const task = useRecruitAction<{ p_task_id: string; p_done: boolean }>('set_onboarding_task')
  const printed = useRecruitAction<{ p_case_id: string; p_kind: DocumentKind }>('mark_document_printed')
  const attach = useRecruitAction<{ p_case_id: string; p_kind: DocumentKind; p_ext: string }>('attach_signed_document')
  const complete = useRecruitAction<{ p_case_id: string }>('complete_onboarding')
  const input = useRef<HTMLInputElement>(null)
  const [uploadKind, setUploadKind] = useState<DocumentKind | null>(null)
  const [error, setError] = useState<string | null>(null)

  if (c.isPending) return <Modal open onClose={onClose} title="Joining"><div className="flex justify-center py-8"><Spinner /></div></Modal>
  if (c.isError) return <Modal open onClose={onClose} title="Joining"><Alert>{errorMessage(c.error)}</Alert></Modal>
  const k = c.data
  const open = k.status === 'open'

  const print = (kinds: DocumentKind[]) => {
    const w = window.open('', '_blank')
    if (!w) return setError('Allow pop-ups to print the documents')
    w.document.write(printPage(kinds, k, localToday()))
    w.document.close()
    w.focus()
    setTimeout(() => w.print(), 300)
    kinds.forEach((kind) => printed.mutate({ p_case_id: k.id, p_kind: kind }))
  }
  const upload = async (file: File) => {
    if (!uploadKind) return
    setError(null)
    const ext = file.type === 'application/pdf' ? 'pdf' : file.type === 'image/png' ? 'png' : file.type === 'image/jpeg' ? 'jpg' : null
    if (!ext || file.size > 5 * 1024 * 1024) return setError('Upload a PDF, JPG or PNG up to 5 MB')
    const { error: up } = await supabase.storage.from('onboarding-docs').upload(`${k.org_id}/${k.id}/${uploadKind}.${ext}`, file, { upsert: true, contentType: file.type })
    if (up) return setError(errorMessage(up))
    attach.mutate({ p_case_id: k.id, p_kind: uploadKind, p_ext: ext })
  }
  const allDone = k.tasks.every((t) => t.done_at)

  return (
    <Modal open onClose={onClose} size="xl" title={`Joining · ${k.employee.full_name} (${k.employee.card_id})`}
      description={<>{k.employee.designation} · {k.employee.department} · joins {formatDate(k.joining_date)} · <Badge tone={open ? 'orange' : 'green'}>{open ? 'Open' : 'Completed'}</Badge></>}
      footer={<>
        <Link to={`/employees/${k.employee.id}`} className="mr-auto text-sm text-primary-700 hover:underline">Open the employee profile</Link>
        <Button variant="secondary" onClick={onClose}>Close</Button>
        {open && <Button loading={complete.isPending} disabled={!allDone} onClick={() => complete.mutate({ p_case_id: k.id })}>Complete joining</Button>}
      </>}>
      <div className="grid gap-6 lg:grid-cols-2">
        <div className="space-y-3">
          {(error || task.error || attach.error || complete.error) && <Alert>{error ?? errorMessage(task.error ?? attach.error ?? complete.error)}</Alert>}
          <h3 className="font-semibold text-slate-900">Checklist</h3>
          <ul className="space-y-2">
            {k.tasks.map((t) => (
              <li key={t.id} className="flex items-start justify-between gap-2 rounded-xl border border-slate-200 p-3">
                <Checkbox label={TASK_LABEL[t.key]} checked={!!t.done_at} disabled={!open || t.key === 'documents_signed'}
                  onChange={(v) => task.mutate({ p_task_id: t.id, p_done: v })} />
                {t.done_at && <span className="shrink-0 text-[11px] text-slate-400">{t.done_by_name ?? ''} · {formatDateTime(t.done_at)}</span>}
              </li>
            ))}
          </ul>
          <p className="text-xs text-slate-500">"Documents signed" ticks itself when all four signed scans are uploaded.</p>
        </div>
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-slate-900">Documents</h3>
            <Button variant="secondary" onClick={() => print(k.documents.map((d) => d.kind))}><Printer className="size-4" />Print all</Button>
          </div>
          <input ref={input} type="file" accept="application/pdf,image/jpeg,image/png" className="hidden"
            onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void upload(f) }} />
          <ul className="space-y-2">
            {k.documents.map((d) => (
              <li key={d.kind} className="flex flex-wrap items-center gap-2 rounded-xl border border-slate-200 p-3 text-sm">
                <span className="mr-auto font-medium text-slate-800">{DOCUMENT_LABEL[d.kind]}
                  <span className="block text-[11px] font-normal text-slate-400">{d.signed_at ? `Signed copy uploaded ${formatDate(d.signed_at)}` : d.printed_at ? `Printed ${formatDate(d.printed_at)}` : 'Not printed'}</span></span>
                <Button variant="ghost" onClick={() => print([d.kind])} aria-label={`Print ${DOCUMENT_LABEL[d.kind]}`}><Printer className="size-4" /></Button>
                {d.signed_path && <OpenFile bucket="onboarding-docs" path={d.signed_path} label="Signed copy" />}
                {open && <Button variant={d.signed_path ? 'ghost' : 'secondary'} loading={attach.isPending && uploadKind === d.kind}
                  onClick={() => { setUploadKind(d.kind); input.current?.click() }}><Upload className="size-4" />{d.signed_path ? 'Replace' : 'Upload signed'}</Button>}
              </li>
            ))}
          </ul>
          <div className="rounded-xl bg-slate-50 p-3 text-sm">
            <p className="font-medium text-slate-900">Joining feedback (named)</p>
            {k.feedback ? (
              <ul className="mt-1 space-y-0.5 text-slate-700">
                {FEEDBACK_QUESTIONS.map((q) => <li key={q.key}>{q.label} <span className="font-semibold">{k.feedback!.ratings[q.key]}/5</span></li>)}
                {k.feedback.comment && <li className="pt-1 italic">“{k.feedback.comment}”</li>}
              </ul>
            ) : <p className="text-slate-500">Not given yet. The link went with the welcome email.</p>}
          </div>
          {!open && <Alert tone="success"><CheckCircle2 className="mr-1 inline size-4" />Joining completed {formatDateTime(k.completed_at)}.</Alert>}
        </div>
      </div>
    </Modal>
  )
}
