// R6 / R7 dialogs for HR: decide a candidate, prepare / approve / send an offer, check the
// pre-joining form, convert to an employee, and close the hiring (purge).
import { useEffect, useState } from 'react'
import { Check, Copy, ExternalLink } from 'lucide-react'
import type { OfferRow, PurgePlan } from '@/onboarding-process/core/types'
import { EMPLOYMENT_LABEL } from '@/onboarding-process/core/jobPost'
import { addDays } from '@/onboarding-process/core/jobPost'
import {
  closeHiring, copyPrehirePhoto, getPurgePlan, sendQueuedMessages, signedUrl, useOfferContext, usePrehire, useRecruitAction,
} from '@/lib/recruit'
import { useMyContext } from '@/lib/appContext'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { formatTaka } from '@/lib/payroll'
import { Alert, Button, Input, Spinner } from '@/components/ui'
import { Checkbox, Modal, Select, Textarea } from '@/components/kit'

type Decision = 'selected' | 'waitlist' | 'rejected'
const DECISION_TEXT: Record<Decision, string> = { selected: 'Select', waitlist: 'Waitlist', rejected: 'Not selected' }

export function DecisionDialog({ applicantId, name, decision, onClose }: { applicantId: string; name: string; decision: Decision; onClose: () => void }) {
  const decide = useRecruitAction<{ p_applicant_id: string; p_decision: Decision; p_note: string | null; p_send: boolean }>('decide_candidate')
  const [note, setNote] = useState('')
  const [send, setSend] = useState(true)
  return (
    <Modal open onClose={onClose} title={`${DECISION_TEXT[decision]} · ${name}`}
      description={decision === 'selected' ? 'Takes one seat of the post; prepare the offer next.' : decision === 'waitlist' ? 'Kept as a backup if the offer is declined.' : 'Ends this application.'}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button variant={decision === 'rejected' ? 'danger' : 'primary'} loading={decide.isPending}
          onClick={() => decide.mutate({ p_applicant_id: applicantId, p_decision: decision, p_note: note.trim() || null, p_send: decision === 'rejected' && send },
            { onSuccess: () => { if (decision === 'rejected' && send) void sendQueuedMessages(); onClose() } })}>Confirm</Button>
      </>}>
      <div className="space-y-3">
        {decide.isError && <Alert>{errorMessage(decide.error)}</Alert>}
        <Textarea label="Note (kept in the history)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
        {decision === 'rejected' && <Checkbox label="Send the polite rejection email" checked={send} onChange={setSend} />}
      </div>
    </Modal>
  )
}

export function OfferDialog({ row, onClose }: { row: OfferRow; onClose: () => void }) {
  const ctx = useOfferContext(row.applicant_id)
  const save = useRecruitAction<{ p_applicant_id: string; p: Record<string, unknown> }>('prepare_offer')
  const draft = row.offer?.status === 'draft' ? row.offer : null
  const [f, setF] = useState({ template: draft?.salary_template_id ?? '', gross: draft ? String(draft.gross) : '', office: draft?.office_id ?? '',
    joining: draft?.joining_date ?? '', expires: draft?.expires_on ?? '', probation: String(draft?.probation_months ?? 6),
    type: draft?.employment_type ?? '', terms: draft?.terms ?? '' })
  const set = (k: keyof typeof f, v: string) => setF((x) => ({ ...x, [k]: v }))
  useEffect(() => {
    if (!ctx.data || draft) return
    const c = ctx.data
    setF((x) => ({ ...x, template: c.templates[0]?.id ?? '', office: c.default_office_id ?? c.offices[0]?.id ?? '',
      joining: addDays(c.today, Math.max(14, c.notice_period_days ?? 0)), expires: addDays(c.today, 5), type: c.post.employment_type,
      gross: c.expected_salary ? String(c.expected_salary) : c.post.salary_max ? String(c.post.salary_max) : '' }))
  }, [ctx.data, draft])
  const c = ctx.data
  const ready = f.template && Number(f.gross) > 0 && f.office && f.joining && f.expires && f.expires <= f.joining

  return (
    <Modal open onClose={onClose} size="lg" title={`${draft ? 'Edit' : 'Prepare'} offer · ${row.full_name}`}
      description="Someone with offer approval (not you) approves it before it can be sent."
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={!ready} onClick={() => save.mutate({ p_applicant_id: row.applicant_id, p: {
          salary_template_id: f.template, gross: Number(f.gross), office_id: f.office, joining_date: f.joining, expires_on: f.expires,
          probation_months: Number(f.probation), employment_type: f.type, terms: f.terms } }, { onSuccess: onClose })}>Save for approval</Button>
      </>}>
      {ctx.isPending ? <div className="flex justify-center py-8"><Spinner /></div> : ctx.isError ? <Alert>{errorMessage(ctx.error)}</Alert> : c && (
        <div className="space-y-4">
          {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
          {draft?.approval_note && <Alert tone="info">Sent back: {draft.approval_note}</Alert>}
          <p className="text-sm text-slate-600">{c.post.designation_name} · {c.post.department_name}
            {c.expected_salary != null && <> · expects {formatTaka(c.expected_salary)}</>}
            {c.post.show_salary && <> · advertised {formatTaka(c.post.salary_min)}–{formatTaka(c.post.salary_max)}</>}
            {c.notice_period_days != null && <> · notice {c.notice_period_days} days</>}</p>
          {c.templates.length === 0 && <Alert>No active salary template. Create one under Salary structure first.</Alert>}
          <div className="grid gap-3 sm:grid-cols-2">
            <Select label="Salary template" value={f.template} onChange={(e) => set('template', e.target.value)} options={c.templates.map((t) => ({ value: t.id, label: t.name }))} />
            <Input label="Monthly gross (Tk)" inputMode="numeric" value={f.gross} onChange={(e) => set('gross', e.target.value.replace(/\D/g, ''))} />
            <Select label="Office" value={f.office} onChange={(e) => set('office', e.target.value)} options={c.offices.map((o) => ({ value: o.id, label: `${o.name} · ${o.branch_name}` }))} />
            <Select label="Employment type" value={f.type} onChange={(e) => set('type', e.target.value)} options={Object.entries(EMPLOYMENT_LABEL).map(([value, label]) => ({ value, label }))} />
            <Input label="Joining date" type="date" min={c.today} value={f.joining} onChange={(e) => set('joining', e.target.value)} />
            <Input label="Reply by" type="date" min={c.today} max={f.joining || undefined} value={f.expires} onChange={(e) => set('expires', e.target.value)}
              error={f.expires && f.joining && f.expires > f.joining ? 'Must be on or before the joining date' : undefined} />
            <Select label="Probation" value={f.probation} onChange={(e) => set('probation', e.target.value)}
              options={[0, 3, 6, 12].map((m) => ({ value: String(m), label: m === 0 ? 'None' : `${m} months` }))} />
          </div>
          <Textarea label="Other terms (shown on the offer and the appointment letter)" rows={3} value={f.terms} maxLength={3000} onChange={(e) => set('terms', e.target.value)} />
        </div>
      )}
    </Modal>
  )
}

export function ApproveOfferDialog({ row, onClose }: { row: OfferRow; onClose: () => void }) {
  const decide = useRecruitAction<{ p_offer_id: string; p_decision: 'approve' | 'send_back'; p_note: string | null }>('decide_offer')
  const [note, setNote] = useState('')
  const o = row.offer!
  return (
    <Modal open onClose={onClose} title={`Approve offer · ${row.full_name}`} description={`Prepared by ${o.prepared_by_name ?? '—'}`}
      footer={<>
        <Button variant="ghost" className="mr-auto" loading={decide.isPending} disabled={note.trim().length < 5}
          onClick={() => decide.mutate({ p_offer_id: o.id, p_decision: 'send_back', p_note: note }, { onSuccess: onClose })}>Send back</Button>
        <Button variant="secondary" onClick={onClose}>Close</Button>
        <Button loading={decide.isPending} onClick={() => decide.mutate({ p_offer_id: o.id, p_decision: 'approve', p_note: note || null }, { onSuccess: onClose })}>Approve</Button>
      </>}>
      <div className="space-y-3 text-sm">
        {decide.isError && <Alert>{errorMessage(decide.error)}</Alert>}
        <dl className="grid gap-2 sm:grid-cols-2">
          <div><dt className="text-xs text-slate-500">Gross / month</dt><dd className="text-lg font-semibold">{formatTaka(o.gross)}</dd></div>
          <div><dt className="text-xs text-slate-500">Salary template</dt><dd>{o.template_name}</dd></div>
          <div><dt className="text-xs text-slate-500">Joining</dt><dd>{formatDate(o.joining_date)} · {o.office_name}</dd></div>
          <div><dt className="text-xs text-slate-500">Reply by</dt><dd>{formatDate(o.expires_on)} · probation {o.probation_months} months</dd></div>
        </dl>
        {o.terms && <p className="rounded-xl bg-slate-50 p-3">{o.terms}</p>}
        {row.decision?.composite != null && <p className="text-xs text-slate-500">Composite score {row.decision.composite}{row.decision.note ? ` · ${row.decision.note}` : ''}</p>}
        <Textarea label="Note (needed to send back)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
      </div>
    </Modal>
  )
}

export function SendOfferDialog({ row, onClose }: { row: OfferRow; onClose: () => void }) {
  const send = useRecruitAction<{ p_offer_id: string; p_base_url: string }, { queued: number; offer_link: string }>('send_offer')
  const [sent, setSent] = useState<string | null>(null)
  const [copied, setCopied] = useState(false)
  const o = row.offer!
  return (
    <Modal open onClose={onClose} title={`${o.status === 'sent' ? 'Send again' : 'Send offer'} · ${row.full_name}`}
      description={o.status === 'sent' ? 'A new link is made; the old one stops working.' : 'Emailed with a private link to accept or decline.'}
      footer={send.isSuccess ? <Button onClick={onClose}>Done</Button> : <>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={send.isPending} onClick={() => send.mutate({ p_offer_id: o.id, p_base_url: window.location.origin }, { onSuccess: async () => {
          const r = await sendQueuedMessages()
          setSent('error' in r ? `The email is queued (${r.error}).` : `Email sent (${r.sent}).`)
        } })}>Send</Button>
      </>}>
      {send.isError && <Alert>{errorMessage(send.error)}</Alert>}
      {send.isSuccess ? (
        <div className="space-y-3">
          {sent && <Alert tone="success">{sent}</Alert>}
          <p className="text-sm text-slate-600">The link (shown only now):</p>
          <div className="flex items-center gap-2"><code className="min-w-0 flex-1 truncate rounded-lg bg-slate-50 px-3 py-2 text-xs">{send.data.offer_link}</code>
            <Button variant="secondary" onClick={async () => { await navigator.clipboard.writeText(send.data.offer_link); setCopied(true) }}>
              {copied ? <Check className="size-4" /> : <Copy className="size-4" />}</Button></div>
        </div>
      ) : <p className="text-sm text-slate-600">{formatTaka(o.gross)} / month · joining {formatDate(o.joining_date)} · reply by {formatDate(o.expires_on)}</p>}
    </Modal>
  )
}

export function WithdrawOfferDialog({ row, onClose }: { row: OfferRow; onClose: () => void }) {
  const withdraw = useRecruitAction<{ p_offer_id: string; p_reason: string }>('withdraw_offer')
  const [reason, setReason] = useState('')
  return (
    <Modal open onClose={onClose} title={`Withdraw offer · ${row.full_name}`} description="The link stops working; the applicant stays selected so a new offer can be made."
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button variant="danger" loading={withdraw.isPending} disabled={reason.trim().length < 5}
          onClick={() => withdraw.mutate({ p_offer_id: row.offer!.id, p_reason: reason }, { onSuccess: onClose })}>Withdraw</Button>
      </>}>
      {withdraw.isError && <Alert>{errorMessage(withdraw.error)}</Alert>}
      <Textarea label="Reason (required)" value={reason} maxLength={300} onChange={(e) => setReason(e.target.value)} />
    </Modal>
  )
}

export function PrehireDialog({ prehireId, name, onClose }: { prehireId: string; name: string; onClose: () => void }) {
  const pre = usePrehire(prehireId)
  const verify = useRecruitAction<{ p_prehire_id: string; p_decision: 'verify' | 'return'; p_note: string | null }>('verify_prehire')
  const [note, setNote] = useState('')
  const [photo, setPhoto] = useState<string | null>(null)
  useEffect(() => {
    if (pre.data?.photo_path) signedUrl('prehire-files', pre.data.photo_path).then(setPhoto).catch(() => setPhoto(null))
  }, [pre.data?.photo_path])
  const p = pre.data
  const d = p?.data
  return (
    <Modal open onClose={onClose} size="lg" title={`Pre-joining form · ${name}`}
      footer={p?.status === 'submitted' ? <>
        <Button variant="ghost" className="mr-auto" loading={verify.isPending} disabled={note.trim().length < 5}
          onClick={() => verify.mutate({ p_prehire_id: prehireId, p_decision: 'return', p_note: note }, { onSuccess: onClose })}>Return to fix</Button>
        <Button variant="secondary" onClick={onClose}>Close</Button>
        <Button loading={verify.isPending} onClick={() => verify.mutate({ p_prehire_id: prehireId, p_decision: 'verify', p_note: null }, { onSuccess: onClose })}>Verified — correct</Button>
      </> : <Button onClick={onClose}>Close</Button>}>
      {pre.isPending ? <div className="flex justify-center py-8"><Spinner /></div> : pre.isError ? <Alert>{errorMessage(pre.error)}</Alert> : p && d && (
        <div className="grid gap-5 sm:grid-cols-[9rem_1fr]">
          <div>{photo ? <img src={photo} alt={`Photo of ${name}`} className="w-36 rounded-xl object-cover ring-1 ring-slate-200" /> : <div className="flex h-44 w-36 items-center justify-center rounded-xl bg-slate-100 text-xs text-slate-400">No photo</div>}</div>
          <div className="space-y-3 text-sm">
            {verify.isError && <Alert>{errorMessage(verify.error)}</Alert>}
            {p.return_note && p.status === 'returned' && <Alert tone="info">Returned: {p.return_note}</Alert>}
            <dl className="grid gap-2 sm:grid-cols-2">
              <div><dt className="text-xs text-slate-500">Father / mother</dt><dd>{d.father_name} / {d.mother_name}</dd></div>
              <div><dt className="text-xs text-slate-500">Date of birth</dt><dd>{formatDate(d.date_of_birth)}{d.gender ? ` · ${d.gender}` : ''}{d.blood_group ? ` · ${d.blood_group}` : ''}</dd></div>
              <div><dt className="text-xs text-slate-500">NID</dt><dd className="font-mono">{p.nid ?? '—'}</dd></div>
              <div><dt className="text-xs text-slate-500">Salary account</dt><dd>{p.payment_method === 'bank' ? `${p.bank_name}${p.branch_name ? `, ${p.branch_name}` : ''} ${p.number ?? ''}`
                : p.payment_method === 'mobile_wallet' ? `${p.wallet_provider} ${p.number ?? ''}` : p.payment_method === 'cash' ? 'Cash' : '—'}</dd></div>
              <div className="sm:col-span-2"><dt className="text-xs text-slate-500">Present address</dt><dd>{d.present_address}</dd></div>
              <div className="sm:col-span-2"><dt className="text-xs text-slate-500">Permanent address</dt><dd>{d.permanent_address}</dd></div>
              <div><dt className="text-xs text-slate-500">Emergency contact</dt><dd>{d.emergency_name ?? '—'} {d.emergency_phone ?? ''}</dd></div>
              <div><dt className="text-xs text-slate-500">Nominees</dt><dd>{(d.nominees ?? []).map((n) => `${n.name} (${n.relation})`).join(', ') || '—'}</dd></div>
            </dl>
            <p className="text-xs text-slate-500">NID and account numbers are stored encrypted; only the last 4 digits are shown. Check them against the originals on joining day.</p>
            {p.status === 'submitted' && <Textarea label="What to fix (needed to return)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />}
          </div>
        </div>
      )}
    </Modal>
  )
}

export function ConvertDialog({ row, onClose, onConverted }: { row: OfferRow; onClose: () => void; onConverted: (caseId: string) => void }) {
  const ctx = useMyContext()
  const convert = useRecruitAction<{ p_prehire_id: string; p: Record<string, unknown> }, { employee_id: string; case_id: string; card_id: string; photo_path: string | null }>('convert_to_employee')
  const markTask = useRecruitAction<{ p_task_id: string; p_done: boolean }>('set_onboarding_task')
  const [cardId, setCardId] = useState('')
  const [send, setSend] = useState(true)
  const [after, setAfter] = useState<string | null>(null)
  return (
    <Modal open onClose={onClose} title={`Make ${row.full_name} an employee`}
      description={`Joining ${formatDate(row.offer?.joining_date)}: creates the employee with the offer's pay and the salary account, and opens the joining checklist.`}
      footer={after ? <Button onClick={() => onConverted(convert.data!.case_id)}>Open the checklist</Button> : <>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={convert.isPending} onClick={() => convert.mutate({ p_prehire_id: row.prehire!.id, p: { card_id: cardId || null, send_feedback: send, base_url: window.location.origin } },
          { onSuccess: async (r) => {
            const notes: string[] = [`Employee ${r.card_id} created.`]
            if (r.photo_path && ctx.organization) {
              try {
                await copyPrehirePhoto(ctx.organization.id, r.employee_id, r.photo_path)
                const { data } = await supabase.rpc('get_onboarding_case', { p_case_id: r.case_id })
                const task = (data?.tasks as { id: string; key: string }[] | undefined)?.find((t) => t.key === 'photo_copied')
                if (task) markTask.mutate({ p_task_id: task.id, p_done: true })
                notes.push('Photo copied to the profile.')
              } catch {
                notes.push('Copy the photo by hand (Employee profile → Photo).')
              }
            }
            if (send) { const s = await sendQueuedMessages(); notes.push('error' in s ? 'Welcome email queued.' : 'Welcome email with the feedback link sent.') }
            setAfter(notes.join(' '))
          } })}>Create employee</Button>
      </>}>
      <div className="space-y-3">
        {convert.isError && <Alert>{errorMessage(convert.error)}</Alert>}
        {after ? <Alert tone="success">{after}</Alert> : (
          <>
            <Input label="Employee ID (only if your company types its own IDs)" value={cardId} onChange={(e) => setCardId(e.target.value.toUpperCase())} hint="Leave empty to generate one" />
            <Checkbox label="Email the welcome message with the named feedback form" checked={send} onChange={setSend} />
          </>
        )}
      </div>
    </Modal>
  )
}

export function ClosePurgeDialog({ postId, onClose }: { postId: string; onClose: () => void }) {
  const [plan, setPlan] = useState<PurgePlan | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [typed, setTyped] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState<number | null>(null)
  useEffect(() => { getPurgePlan(postId).then(setPlan).catch((e) => setError(errorMessage(e))) }, [postId])
  const files = plan ? plan.files['recruit-cvs'].length + plan.files['prehire-files'].length : 0
  return (
    <Modal open onClose={onClose} title="Close hiring and delete applicant data"
      description="Decision 10: no CV or applicant data is kept once the vacancy is closed. This cannot be undone."
      footer={done != null ? <Button onClick={onClose}>Done</Button> : <>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button variant="danger" loading={busy} disabled={!plan || plan.blocking > 0 || typed !== 'DELETE'} onClick={async () => {
          setBusy(true)
          setError(null)
          try { setDone((await closeHiring(postId, plan!)).purged) } catch (e) { setError(errorMessage(e)) } finally { setBusy(false) }
        }}>Delete and close</Button>
      </>}>
      <div className="space-y-3 text-sm">
        {error && <Alert>{error}</Alert>}
        {done != null ? <Alert tone="success">Removed the data of {done} applicant{done === 1 ? '' : 's'}. Joined employees keep their employee records.</Alert>
          : !plan ? <div className="flex justify-center py-6"><Spinner /></div> : (
            <>
              {plan.blocking > 0 && <Alert>{plan.blocking} offer(s) are still open or accepted without joining. Finish or withdraw them first.</Alert>}
              <ul className="list-disc space-y-1 pl-5 text-slate-700">
                <li>{plan.applicants} applicant(s): name, email, phone, CV text, forms, messages and pre-joining data are deleted.</li>
                <li>{files} file(s) (CVs and photos) are deleted from storage.</li>
                <li>{plan.joined} joined applicant(s) stay as employees; counts and scores stay for reports.</li>
                <li>The job post is closed.</li>
              </ul>
              <Input label='Type DELETE to confirm' value={typed} onChange={(e) => setTyped(e.target.value)} />
            </>
          )}
      </div>
    </Modal>
  )
}

export function OpenFile({ bucket, path, label }: { bucket: string; path: string; label: string }) {
  const [error, setError] = useState<string | null>(null)
  return (
    <span className="inline-flex items-center gap-1">
      <button type="button" className="inline-flex items-center gap-1 text-xs text-primary-700 hover:underline"
        onClick={() => signedUrl(bucket, path).then((u) => window.open(u, '_blank', 'noopener')).catch((e) => setError(errorMessage(e)))}>
        <ExternalLink className="size-3" />{label}</button>
      {error && <span className="text-xs text-red-600">{error}</span>}
    </span>
  )
}
