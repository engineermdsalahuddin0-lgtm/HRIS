// Tests & interviews board of one post: shortlisted applicants with their online-test
// link and score, written marks and interview. Refreshes every 30 s while tests run.
import { useState } from 'react'
import { CalendarClock, ClipboardCheck, Link2, PenLine, XCircle } from 'lucide-react'
import type { BoardRow, JobPost } from '@/onboarding-process/core/types'
import { INVITE_STATUS_LABEL, isoToZoned } from '@/onboarding-process/core/assessment'
import { APPLICANT_STATUS_LABEL } from '@/onboarding-process/core/jobPost'
import { SECTION_LABEL } from '@/onboarding-process/core/questions'
import { useAssessmentBoard, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, Spinner } from '@/components/ui'
import { Checkbox, Table, td, th } from '@/components/kit'
import { InviteLinksDialog } from './dialogs/InviteLinksDialog'
import { WrittenMarksDialog } from './dialogs/WrittenMarksDialog'
import { InterviewDialog } from './dialogs/InterviewDialog'

const passTone = (passed: boolean | null | undefined) => (passed === true ? 'green' : passed === false ? 'red' : 'slate')

export function TestsPanel({ post }: { post: JobPost }) {
  const board = useAssessmentBoard(post.id)
  const cancelLink = useRecruitAction<{ p_invite_id: string }>('cancel_test_invite')
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [inviting, setInviting] = useState(false)
  const [marking, setMarking] = useState<BoardRow | null>(null)
  const [scheduling, setScheduling] = useState<BoardRow | null>(null)

  if (board.isPending) return <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
  if (board.isError) return <Alert>{errorMessage(board.error)}</Alert>
  const b = board.data
  const manage = b.can.manage
  const objective = b.papers.objective
  const written = b.papers.written
  const invitable = b.rows.filter((r) => selected.has(r.applicant_id) && (r.status === 'shortlisted' || r.status === 'test_invited')
    && r.invite?.status !== 'started' && r.invite?.status !== 'submitted')
  const toggle = (id: string) => setSelected((s) => { const n = new Set(s); if (n.has(id)) n.delete(id); else n.add(id); return n })
  const when = (iso: string) => { const z = isoToZoned(iso, b.timezone); return `${formatDate(z.date)} ${z.time}` }

  return (
    <section className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="rounded-2xl bg-slate-50 p-4 text-sm">
          <p className="font-medium text-slate-900">Online objective test</p>
          <p className="text-slate-600">{objective ? `${objective.question_count} questions · ${objective.total_marks} marks · ${objective.duration_minutes} min${objective.pass_percent != null ? ` · pass ${objective.pass_percent} %` : ''}${objective.locked ? ' · locked' : ''}`
            : 'No objective paper yet — set it on the Question papers tab.'}</p>
        </div>
        <div className="rounded-2xl bg-slate-50 p-4 text-sm">
          <p className="font-medium text-slate-900">Written test (on paper)</p>
          <p className="text-slate-600">{written ? `${written.question_count} questions · ${written.total_marks} marks${written.pass_percent != null ? ` · pass ${written.pass_percent} %` : ''}`
            : 'No written paper.'}</p>
        </div>
      </div>
      {cancelLink.isError && <Alert>{errorMessage(cancelLink.error)}</Alert>}

      {manage && selected.size > 0 && (
        <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-primary-50 p-3 text-sm">
          <span className="font-medium text-primary-900">{selected.size} selected</span>
          <Button className="ml-auto" disabled={!objective || invitable.length === 0} onClick={() => setInviting(true)}>
            <Link2 className="size-4" />Send test link{invitable.length > 1 ? `s (${invitable.length})` : ''}
          </Button>
        </div>
      )}

      {b.rows.length === 0 ? (
        <EmptyState title="Nobody is shortlisted yet">Shortlist applicants on the Applicants tab; they appear here for tests and interviews.</EmptyState>
      ) : (
        <Table minWidth={960} head={(
          <tr>{manage && <th className={`${th} w-10`}><span className="sr-only">Select</span></th>}
            <th className={th}>Applicant</th><th className={th}>Online test</th><th className={th}>Written</th>
            <th className={th}>Interview</th><th className={th}>Status</th></tr>
        )}>
          {b.rows.map((r) => (
            <tr key={r.applicant_id} className="align-top">
              {manage && <td className={td}><Checkbox srOnlyLabel label={`Select ${r.full_name}`} checked={selected.has(r.applicant_id)} onChange={() => toggle(r.applicant_id)} /></td>}
              <td className={td}>
                <p className="font-medium text-slate-900">{r.full_name}</p>
                <p className="text-xs text-slate-400">{r.ats_score != null ? `ATS ${r.ats_score}` : 'ATS —'} · {r.email}</p>
              </td>
              <td className={td}>
                {r.objective ? (
                  <div className="space-y-1">
                    <p className="flex items-center gap-2"><span className="font-semibold tabular-nums text-slate-900">{r.objective.percent} %</span>
                      <Badge tone={passTone(r.objective.passed)}>{r.objective.passed === true ? 'Pass' : r.objective.passed === false ? 'Below pass' : `${r.objective.score}/${r.objective.total}`}</Badge></p>
                    <p className="text-[11px] text-slate-500">{Object.entries(r.objective.sections).map(([s, v]) => `${SECTION_LABEL[s as keyof typeof SECTION_LABEL]?.split(' ')[0]} ${v?.percent ?? '—'}%`).join(' · ')}</p>
                    {r.invite?.auto_submitted && <p className="text-[11px] text-amber-700">Time ran out</p>}
                  </div>
                ) : r.invite ? (
                  <div className="space-y-1">
                    <Badge tone={r.invite.status === 'expired' ? 'red' : 'orange'}>{INVITE_STATUS_LABEL[r.invite.status]}</Badge>
                    <p className="text-[11px] text-slate-500">{r.invite.status === 'invited' ? `Valid until ${when(r.invite.expires_at)}` : r.invite.started_at ? `Started ${when(r.invite.started_at)}` : ''}</p>
                    {manage && r.invite.status === 'invited' && (
                      <button type="button" className="inline-flex items-center gap-1 text-[11px] text-slate-500 hover:text-red-600"
                        onClick={() => confirm('Cancel this link?') && cancelLink.mutate({ p_invite_id: r.invite!.id })}><XCircle className="size-3" />Cancel link</button>
                    )}
                  </div>
                ) : <span className="text-xs text-slate-400">{objective ? 'Not invited' : '—'}</span>}
              </td>
              <td className={td}>
                {r.written ? (
                  <p className="flex items-center gap-2"><span className="font-semibold tabular-nums text-slate-900">{r.written.percent} %</span>
                    <Badge tone={passTone(r.written.passed)}>{r.written.score}/{r.written.total}</Badge></p>
                ) : <span className="text-xs text-slate-400">{written ? 'Not marked' : '—'}</span>}
                {manage && written && (
                  <button type="button" className="mt-1 inline-flex items-center gap-1 text-xs text-primary-700 hover:underline" onClick={() => setMarking(r)}>
                    <PenLine className="size-3" />{r.written ? 'Edit marks' : 'Enter marks'}</button>
                )}
              </td>
              <td className={td}>
                {r.interview ? (
                  <div className="space-y-0.5">
                    <p className="font-medium text-slate-900">{when(r.interview.starts_at)}</p>
                    <p className="text-[11px] text-slate-500">{r.interview.mode === 'online' ? 'Online' : r.interview.location} · {(r.interview.panel_names ?? []).join(', ')}</p>
                    {r.interview.late_reason && <p className="text-[11px] text-amber-700">After the due date: {r.interview.late_reason}</p>}
                  </div>
                ) : <p className="text-xs text-slate-500">Due by {formatDate(r.due_by)}{r.due_by < b.today ? ' (overdue)' : ''}</p>}
                <button type="button" className="mt-1 inline-flex items-center gap-1 text-xs text-primary-700 hover:underline" onClick={() => setScheduling(r)}>
                  <CalendarClock className="size-3" />{r.interview ? 'Change' : 'Schedule'}</button>
              </td>
              <td className={td}><Badge tone={r.status === 'interview_scheduled' ? 'green' : 'slate'}>{APPLICANT_STATUS_LABEL[r.status]}</Badge></td>
            </tr>
          ))}
        </Table>
      )}
      <p className="flex items-center gap-1 text-xs text-slate-500"><ClipboardCheck className="size-3.5" />Scores show here as soon as an applicant submits. Nobody is moved automatically.</p>

      {inviting && objective && (
        <InviteLinksDialog postId={post.id} postTitle={post.title} orgName={post.org_name} durationMinutes={objective.duration_minutes}
          applicants={invitable.map((r) => ({ id: r.applicant_id, full_name: r.full_name }))}
          onClose={() => { setInviting(false); setSelected(new Set()) }} />
      )}
      {marking && written && <WrittenMarksDialog row={marking} paper={written} onClose={() => setMarking(null)} />}
      {scheduling && <InterviewDialog postId={post.id} row={scheduling} timezone={b.timezone} onClose={() => setScheduling(null)} />}
    </section>
  )
}
