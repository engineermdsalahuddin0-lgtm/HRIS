import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { AlertTriangle, ArrowLeft, Clock, Lock, Paperclip, Star, StickyNote } from 'lucide-react'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, PageLoader, cx } from '@/components/ui'
import { Modal, Select, Textarea } from '@/components/kit'
import { FilePicker } from '../../shared/FilePicker'
import type { TicketStatus } from '../core/helpdesk'
import { MAX_FILES, PRIORITY_LABEL, STATUS_LABEL, slaLeftLabel, statusLabel, ticketNo } from '../core/helpdesk'
import type { FileRef, TicketDetail } from '../data/api'
import { ticketFileUrl, useHelpdeskSetup, useReply, useTicket, useTicketAction } from '../data/api'

/** /helpdesk/:id: the thread with replies, internal notes (staff only), events, SLA and actions. */
export default function TicketPage() {
  const { id } = useParams()
  const ticket = useTicket(id)
  if (ticket.isPending) return <PageLoader />
  if (ticket.isError) return <div className="mx-auto max-w-4xl"><Alert>{errorMessage(ticket.error)}</Alert></div>
  return <TicketView t={ticket.data} />
}

function Files({ files }: { files: FileRef[] }) {
  const [error, setError] = useState<string | null>(null)
  if (!files.length) return null
  return (
    <div className="mt-2 flex flex-wrap gap-2">
      {files.map((f) => (
        <button key={f.path} type="button"
          onClick={async () => { setError(null); try { window.open(await ticketFileUrl(f.path), '_blank', 'noopener') } catch (e) { setError(errorMessage(e)) } }}
          className="inline-flex max-w-full items-center gap-1.5 rounded-lg bg-white px-2.5 py-1 text-xs text-primary-700 ring-1 ring-slate-200 hover:bg-primary-50">
          <Paperclip className="size-3.5 shrink-0" aria-hidden /><span className="max-w-48 truncate">{f.name}</span>
        </button>
      ))}
      {error && <p className="w-full text-xs text-red-600">{error}</p>}
    </div>
  )
}

function TicketView({ t }: { t: TicketDetail }) {
  const ctx = useMyContext()
  const staff = t.access !== 'requester'
  const open = !['resolved', 'closed'].includes(t.status)
  const left = slaLeftLabel(t.sla.resolution_left_minutes)

  return (
    <div className="mx-auto grid max-w-6xl gap-6 lg:grid-cols-[1fr_320px]">
      <div className="min-w-0 space-y-4">
        <Link to="/helpdesk" className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" aria-hidden /> Helpdesk</Link>
        <div>
          <p className="font-mono text-xs text-slate-500">{ticketNo(t.ticket_no)}</p>
          <h2 className="text-2xl font-semibold text-slate-900">{t.subject}</h2>
          <div className="mt-2 flex flex-wrap items-center gap-2">
            <Badge tone={STATUS_LABEL[t.status].tone}>{statusLabel(t.status, staff)}</Badge>
            <Badge tone={PRIORITY_LABEL[t.priority].tone}>{PRIORITY_LABEL[t.priority].label}</Badge>
            <span className="inline-flex items-center gap-1 text-sm text-slate-600">{t.confidential && <Lock className="size-3.5" aria-label="confidential" />}{t.category}</span>
          </div>
        </div>

        <ol className="space-y-3">
          <li className="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200">
            <p className="text-xs text-slate-500"><b className="text-slate-700">{t.requester}</b> · {formatDateTime(t.created_at)}</p>
            <p className="mt-2 whitespace-pre-line text-sm text-slate-800">{t.description}</p>
          </li>
          {t.messages.map((m) => m.kind === 'event' ? (
            <li key={m.id} className="px-2 text-center text-xs text-slate-500">{m.body} · {formatDateTime(m.created_at)}</li>
          ) : (
            <li key={m.id} className={cx('rounded-2xl p-4 ring-1',
              m.kind === 'note' ? 'bg-amber-50 ring-amber-200' : m.from_staff ? 'bg-primary-50/60 ring-primary-100' : 'bg-white shadow-sm ring-slate-200')}>
              <p className="flex items-center gap-1.5 text-xs text-slate-500">
                {m.kind === 'note' && <StickyNote className="size-3.5 text-amber-600" aria-hidden />}
                <b className="text-slate-700">{m.author ?? 'Someone'}</b>{m.kind === 'note' && ' · internal note'} · {formatDateTime(m.created_at)}
              </p>
              {m.body && <p className="mt-2 whitespace-pre-line text-sm text-slate-800">{m.body}</p>}
              <Files files={m.attachments} />
            </li>
          ))}
        </ol>

        {(t.can.reply || t.can.note) && <Composer t={t} orgId={ctx.organization!.id} />}
        {t.can.rate && <RateOrReopen t={t} />}
        {t.status === 'closed' && (
          <Alert tone="info">
            This ticket is closed{t.closed_reason === 'auto' ? ' automatically' : ''}{t.rating ? ` · rated ${t.rating} of 5` : ''}. If the problem comes back, raise a new ticket.
          </Alert>
        )}
      </div>

      <aside className="space-y-4">
        <Card className="space-y-3 p-5">
          <h3 className="font-semibold text-slate-900">Details</h3>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between gap-3"><dt className="text-slate-500">Raised by</dt><dd className="text-right text-slate-800">{t.requester}</dd></div>
            <div className="flex justify-between gap-3"><dt className="text-slate-500">Assigned to</dt><dd className="text-right text-slate-800">{t.assignee ?? 'HR queue'}</dd></div>
            {t.reopen_count > 0 && <div className="flex justify-between gap-3"><dt className="text-slate-500">Reopened</dt><dd>{t.reopen_count}×</dd></div>}
          </dl>
          {t.can.assign && <AssignBox t={t} />}
        </Card>
        <Card className="space-y-3 p-5">
          <h3 className="flex items-center gap-2 font-semibold text-slate-900"><Clock className="size-4" aria-hidden /> SLA (office hours)</h3>
          <SlaLine label="First response" due={t.sla.response_due_at} done={t.first_response_at} breached={t.sla.response_breached} />
          <SlaLine label="Resolution" due={t.sla.resolution_due_at} done={t.resolved_at} breached={t.sla.resolution_breached}
            note={t.sla.paused ? 'Paused while waiting for the employee' : open ? left : null} />
        </Card>
        {t.can.status && <StatusBox t={t} />}
      </aside>
    </div>
  )
}

function SlaLine({ label, due, done, breached, note }: { label: string; due: string; done: string | null; breached: boolean; note?: string | null }) {
  return (
    <div className="text-sm">
      <p className="flex items-center justify-between gap-2">
        <span className="text-slate-500">{label}</span>
        {breached ? <span className="inline-flex items-center gap-1 font-medium text-red-600"><AlertTriangle className="size-3.5" aria-hidden /> Breached</span>
          : done ? <span className="text-green-700">Met</span> : null}
      </p>
      <p className="text-slate-800">Due {formatDateTime(due)}</p>
      {done && <p className="text-xs text-slate-500">Done {formatDateTime(done)}</p>}
      {note && <p className={cx('text-xs', note.startsWith('overdue') ? 'text-red-600' : 'text-slate-500')}>{note}</p>}
    </div>
  )
}

function Composer({ t, orgId }: { t: TicketDetail; orgId: string }) {
  const reply = useReply(orgId, t.id)
  const [body, setBody] = useState('')
  const [files, setFiles] = useState<File[]>([])
  const [internal, setInternal] = useState(false)
  const [status, setStatus] = useState<'' | TicketStatus>('')
  const staff = t.access !== 'requester'
  const send = () => reply.mutate({ body: body.trim(), internal, status: status || null, files }, {
    onSuccess: () => { setBody(''); setFiles([]); setStatus(''); setInternal(false) },
  })
  return (
    <Card className={cx('space-y-3 p-4', internal && 'ring-amber-300')}>
      {staff && (
        <div className="inline-flex rounded-lg bg-slate-100 p-0.5 text-sm" role="radiogroup" aria-label="Message type">
          {([[false, 'Reply to employee'], [true, 'Internal note']] as const).map(([v, l]) => (
            <button key={l} type="button" role="radio" aria-checked={internal === v} onClick={() => setInternal(v)} disabled={v ? !t.can.note : !t.can.reply}
              className={cx('rounded-md px-3 py-1 font-medium disabled:opacity-40', internal === v ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>{l}</button>
          ))}
        </div>
      )}
      <Textarea label={internal ? 'Internal note (the employee does not see it)' : 'Message'} name="ticket_reply" rows={4}
        maxLength={10000} value={body} onChange={(e) => setBody(e.target.value)} />
      <FilePicker files={files} onChange={setFiles} max={MAX_FILES} />
      {reply.isError && <Alert>{errorMessage(reply.error)}</Alert>}
      <div className="flex flex-wrap items-end justify-end gap-3">
        {staff && !internal && (
          <Select label="Then set status" name="reply_status" value={status} placeholder="Keep as it is" className="w-56"
            onChange={(e) => setStatus(e.target.value as TicketStatus)}
            options={[{ value: 'in_progress', label: 'In progress' }, { value: 'waiting', label: 'Waiting for the employee' }, { value: 'resolved', label: 'Resolved' }]} />
        )}
        <Button loading={reply.isPending} disabled={!body.trim() && files.length === 0} onClick={send}>
          {internal ? 'Add note' : 'Send'}
        </Button>
      </div>
    </Card>
  )
}

function StatusBox({ t }: { t: TicketDetail }) {
  const setStatus = useTicketAction<{ p_id: string; p_status: TicketStatus; p_note: string | null }>('set_ticket_status')
  const [closing, setClosing] = useState(false)
  const [note, setNote] = useState('')
  const options: { s: TicketStatus; label: string }[] = [
    { s: 'in_progress', label: 'In progress' }, { s: 'waiting', label: 'Waiting for the employee' }, { s: 'resolved', label: 'Resolved' },
  ]
  return (
    <Card className="space-y-3 p-5">
      <h3 className="font-semibold text-slate-900">Status</h3>
      <div className="grid gap-2">
        {options.filter((o) => o.s !== t.status).map((o) => (
          <Button key={o.s} variant="secondary" loading={setStatus.isPending && setStatus.variables?.p_status === o.s}
            onClick={() => setStatus.mutate({ p_id: t.id, p_status: o.s, p_note: null })}>{o.label}</Button>
        ))}
        {t.can.close && <Button variant="ghost" onClick={() => setClosing(true)}>Close without rating…</Button>}
      </div>
      {setStatus.isError && <Alert>{errorMessage(setStatus.error)}</Alert>}
      <Modal open={closing} onClose={() => setClosing(false)} size="sm" title="Close the ticket"
        footer={<><Button variant="secondary" onClick={() => setClosing(false)}>Cancel</Button>
          <Button variant="danger" disabled={note.trim().length < 3} loading={setStatus.isPending}
            onClick={() => setStatus.mutate({ p_id: t.id, p_status: 'closed', p_note: note.trim() }, { onSuccess: () => setClosing(false) })}>Close</Button></>}>
        <Textarea label="Reason" name="close_reason" value={note} onChange={(e) => setNote(e.target.value)} hint="For example: duplicate of #0012." />
      </Modal>
    </Card>
  )
}

function AssignBox({ t }: { t: TicketDetail }) {
  const setup = useHelpdeskSetup(true)
  const assign = useTicketAction<{ p_id: string; p_employee_id: string | null }>('assign_ticket')
  const handlers = (setup.data?.handlers ?? []).filter((h) => !t.confidential || h.can_confidential)
  return (
    <div className="space-y-2 border-t border-slate-100 pt-3">
      <Select label="Reassign" name="assign_to" value={t.assignee_employee_id ?? ''} placeholder="HR queue (unassigned)"
        disabled={assign.isPending}
        onChange={(e) => assign.mutate({ p_id: t.id, p_employee_id: e.target.value || null })}
        options={handlers.map((h) => ({ value: h.employee_id, label: h.full_name }))}
        hint={t.confidential ? 'Confidential: only HR can take it.' : undefined} />
      {assign.isError && <Alert>{errorMessage(assign.error)}</Alert>}
    </div>
  )
}

function RateOrReopen({ t }: { t: TicketDetail }) {
  const rate = useTicketAction<{ p_id: string; p_rating: number; p_comment: string | null }>('rate_ticket')
  const reopen = useTicketAction<{ p_id: string; p_reason: string }>('reopen_ticket')
  const [stars, setStars] = useState(0)
  const [comment, setComment] = useState('')
  const [reason, setReason] = useState('')
  const [mode, setMode] = useState<'rate' | 'reopen'>('rate')
  return (
    <Card className="space-y-4 p-5 ring-green-200">
      <div>
        <h3 className="font-semibold text-slate-900">Is it solved?</h3>
        <p className="text-sm text-slate-500">Rate the help to close the ticket, or reopen it. Without an answer it closes after a few working days.</p>
      </div>
      <div className="inline-flex rounded-lg bg-slate-100 p-0.5 text-sm" role="radiogroup" aria-label="Choice">
        {([['rate', 'Yes, rate it'], ['reopen', 'No, reopen']] as const).map(([k, l]) => (
          <button key={k} type="button" role="radio" aria-checked={mode === k} onClick={() => setMode(k)}
            className={cx('rounded-md px-3 py-1 font-medium', mode === k ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>{l}</button>
        ))}
      </div>
      {mode === 'rate' ? (
        <div className="space-y-3">
          <div className="flex gap-1" role="radiogroup" aria-label="Rating">
            {[1, 2, 3, 4, 5].map((n) => (
              <button key={n} type="button" role="radio" aria-checked={stars === n} aria-label={`${n} star${n === 1 ? '' : 's'}`} onClick={() => setStars(n)}
                className="rounded p-1 text-amber-400 hover:scale-110">
                <Star className={cx('size-7', n <= stars ? 'fill-amber-400' : 'fill-none text-slate-300')} />
              </button>
            ))}
          </div>
          <Textarea label="Comment (optional)" name="rating_comment" maxLength={1000} value={comment} onChange={(e) => setComment(e.target.value)} />
          {rate.isError && <Alert>{errorMessage(rate.error)}</Alert>}
          <Button disabled={!stars} loading={rate.isPending} onClick={() => rate.mutate({ p_id: t.id, p_rating: stars, p_comment: comment.trim() || null })}>Rate and close</Button>
        </div>
      ) : (
        <div className="space-y-3">
          <Textarea label="What is still wrong?" name="reopen_reason" maxLength={10000} value={reason} onChange={(e) => setReason(e.target.value)} />
          {reopen.isError && <Alert>{errorMessage(reopen.error)}</Alert>}
          <Button variant="secondary" disabled={reason.trim().length < 3} loading={reopen.isPending}
            onClick={() => reopen.mutate({ p_id: t.id, p_reason: reason.trim() })}>Reopen</Button>
        </div>
      )}
    </Card>
  )
}
