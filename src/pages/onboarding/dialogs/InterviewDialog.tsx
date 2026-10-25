// Schedule, reschedule or cancel one applicant's interview. "Propose a time" asks the
// database for the first slot that suits every panel member (working day, no leave, no clash).
import { useMemo, useState } from 'react'
import { Sparkles } from 'lucide-react'
import type { BoardRow } from '@/onboarding-process/core/types'
import { isoToZoned, zonedToIso } from '@/onboarding-process/core/assessment'
import { sendQueuedMessages, useInterviewerOptions, useRecruitAction } from '@/lib/recruit'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Button, Input, Spinner } from '@/components/ui'
import { Checkbox, Modal, Select, Textarea } from '@/components/kit'

export function InterviewDialog({ postId, row, timezone, onClose }: { postId: string; row: BoardRow; timezone: string; onClose: () => void }) {
  const current = row.interview
  const options = useInterviewerOptions(postId, true)
  const save = useRecruitAction<{ p_applicant_id: string; p: Record<string, unknown> }, string>('save_interview')
  const invite = useRecruitAction<{ p_interview_id: string; p_base_url: string }>('send_interview_invite')
  const [notify, setNotify] = useState(!current?.invite_sent)
  const [after, setAfter] = useState<string | null>(null)
  const cancel = useRecruitAction<{ p_interview_id: string; p_reason: string }>('cancel_interview')
  const start = current ? isoToZoned(current.starts_at, timezone) : { date: '', time: '10:00' }
  const [panel, setPanel] = useState<Set<string>>(new Set(current?.panel ?? []))
  const [date, setDate] = useState(start.date)
  const [time, setTime] = useState(start.time)
  const [minutes, setMinutes] = useState(current?.duration_minutes ?? 45)
  const [mode, setMode] = useState<'in_person' | 'online'>(current?.mode ?? 'in_person')
  const [location, setLocation] = useState(current?.location ?? '')
  const [link, setLink] = useState(current?.online_link ?? '')
  const [note, setNote] = useState(current?.note ?? '')
  const [late, setLate] = useState(current?.late_reason ?? '')
  const [search, setSearch] = useState('')
  const [proposedBy, setProposedBy] = useState<'system' | 'user'>(current?.proposed_by ?? 'user')
  const [proposal, setProposal] = useState<{ busy: boolean; message?: string }>({ busy: false })
  const [cancelling, setCancelling] = useState(false)
  const [cancelReason, setCancelReason] = useState('')

  const people = useMemo(() => (options.data ?? []).filter((o) => !search || o.full_name.toLowerCase().includes(search.toLowerCase())), [options.data, search])
  const isLate = !!date && date > row.due_by
  const ready = panel.size >= 1 && panel.size <= 4 && !!date && !!time
    && (mode === 'online' ? link.startsWith('https://') : location.trim().length >= 2) && (!isLate || late.trim().length >= 5)

  const propose = async () => {
    setProposal({ busy: true })
    const { data, error } = await supabase.rpc('propose_interview_slot', { p_applicant_id: row.applicant_id, p: { panel: [...panel], duration_minutes: minutes } })
    if (error) return setProposal({ busy: false, message: errorMessage(error) })
    if (!data.found) return setProposal({ busy: false, message: `No free slot for this panel up to ${formatDate(data.due_by)}. Pick a time by hand.` })
    const z = isoToZoned(data.starts_at, timezone)
    setDate(z.date)
    setTime(z.time)
    setProposedBy('system')
    setProposal({ busy: false, message: `First free slot for everyone: ${formatDate(z.date)} at ${z.time}.` })
  }
  const toggle = (id: string) => setPanel((s) => {
    const n = new Set(s)
    if (n.has(id)) n.delete(id)
    else if (n.size < 4) n.add(id)
    return n
  })

  return (
    <Modal open onClose={onClose} size="lg" title={`${current ? 'Reschedule' : 'Schedule'} interview · ${row.full_name}`}
      description={<>Due by {formatDate(row.due_by)} (15 days after the last result) · times in {timezone}</>}
      footer={cancelling ? <>
        <Button variant="secondary" onClick={() => setCancelling(false)}>Back</Button>
        <Button variant="danger" loading={cancel.isPending} disabled={cancelReason.trim().length < 5}
          onClick={() => current && cancel.mutate({ p_interview_id: current.id, p_reason: cancelReason }, { onSuccess: onClose })}>Cancel interview</Button>
      </> : <>
        {current && <Button variant="ghost" className="mr-auto" onClick={() => setCancelling(true)}>Cancel interview</Button>}
        <Button variant="secondary" onClick={onClose}>Close</Button>
        {after ? <Button onClick={onClose}>Done</Button> : (
          <Button loading={save.isPending || invite.isPending} disabled={!ready} onClick={() => save.mutate({ p_applicant_id: row.applicant_id, p: {
            starts_at: zonedToIso(date, time, timezone), duration_minutes: minutes, mode, location, online_link: link,
            panel: [...panel], note, late_reason: isLate ? late : null, proposed_by: proposedBy,
          } }, { onSuccess: (id) => {
            if (!notify) return onClose()
            invite.mutate({ p_interview_id: id, p_base_url: window.location.origin }, { onSuccess: async () => {
              const r = await sendQueuedMessages()
              setAfter('error' in r ? `Saved. The invitation is queued (${r.error}).` : `Saved and sent ${r.sent} message${r.sent === 1 ? '' : 's'}${r.failed ? `, ${r.failed} failed (see Messages)` : ''}.`)
            } })
          } })}>{notify ? 'Save and send invitation' : 'Save'}</Button>
        )}
      </>}>
      {cancelling ? (
        <div className="space-y-3">
          {cancel.isError && <Alert>{errorMessage(cancel.error)}</Alert>}
          <Textarea label="Why is it cancelled? (required)" value={cancelReason} maxLength={300} onChange={(e) => setCancelReason(e.target.value)} />
        </div>
      ) : (
        <div className="space-y-4">
          {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
          <div>
            <div className="mb-1.5 flex items-center justify-between">
              <span className="text-sm font-medium text-slate-700">Panel (1–4) · {panel.size} chosen</span>
              <input aria-label="Search people" placeholder="Search" value={search} onChange={(e) => setSearch(e.target.value)}
                className="w-40 rounded-lg border border-slate-300 px-2.5 py-1 text-sm" />
            </div>
            <div className="max-h-44 space-y-1 overflow-y-auto rounded-xl border border-slate-200 p-2">
              {options.isPending ? <div className="flex justify-center py-3"><Spinner /></div> : people.map((o) => (
                <div key={o.id} className="flex items-center justify-between gap-2 px-1">
                  <Checkbox label={o.full_name} checked={panel.has(o.id)} disabled={!panel.has(o.id) && panel.size >= 4} onChange={() => toggle(o.id)} />
                  <span className="truncate text-xs text-slate-400">{o.designation_name ?? ''}{o.department_name ? ` · ${o.department_name}` : ''}</span>
                </div>
              ))}
            </div>
            <p className="mt-1 text-xs text-slate-500">Any employee may sit on the panel; they will only score the applicants given to them.</p>
          </div>
          <div className="flex flex-wrap items-end gap-3">
            <Button variant="secondary" disabled={panel.size === 0} loading={proposal.busy} onClick={propose}><Sparkles className="size-4" />Propose a time</Button>
            {proposal.message && <p className="text-sm text-slate-600">{proposal.message}</p>}
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <Input label="Date" type="date" value={date} onChange={(e) => { setDate(e.target.value); setProposedBy('user') }} />
            <Input label="Time" type="time" value={time} onChange={(e) => { setTime(e.target.value); setProposedBy('user') }} />
            <Select label="Length" value={String(minutes)} onChange={(e) => setMinutes(Number(e.target.value))}
              options={[30, 45, 60, 90].map((m) => ({ value: String(m), label: `${m} minutes` }))} />
          </div>
          {isLate && <Textarea label={`Reason for after ${formatDate(row.due_by)} (required)`} value={late} maxLength={300} onChange={(e) => setLate(e.target.value)} />}
          <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
            <Select label="How" value={mode} onChange={(e) => setMode(e.target.value as 'in_person' | 'online')}
              options={[{ value: 'in_person', label: 'In person' }, { value: 'online', label: 'Online' }]} />
            {mode === 'online'
              ? <Input label="Meeting link" placeholder="https://meet.google.com/..." value={link} onChange={(e) => setLink(e.target.value.trim())} />
              : <Input label="Place" placeholder="Head Office, 3rd floor meeting room" value={location} onChange={(e) => setLocation(e.target.value)} />}
          </div>
          <Textarea label="Note for the panel (optional)" value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
          <Checkbox label={current?.invite_sent ? 'Send the invitation again (new form link)' : 'Email the applicant the invitation with the pre-interview form'}
            checked={notify} onChange={setNotify} />
          {invite.isError && <Alert>{errorMessage(invite.error)}</Alert>}
          {after && <Alert tone="success">{after}</Alert>}
        </div>
      )}
    </Modal>
  )
}
