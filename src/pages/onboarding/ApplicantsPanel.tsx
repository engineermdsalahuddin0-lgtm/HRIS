// Applicants of one job post: report table (sort, filters), CV reading (AI or basic),
// must-have gate + ATS score, shortlist / screen out (HR), row click → full profile modal.
import { useMemo, useState } from 'react'
import { ArrowDownUp, Bot, FileText, ListChecks, RefreshCw, UserPlus } from 'lucide-react'
import type { Applicant, ApplicantSource, ApplicantStatus, CvMode, JobPost } from '@/onboarding-process/core/types'
import { APPLICANT_STATUS_LABEL, SOURCE_LABEL } from '@/onboarding-process/core/jobPost'
import type { Gate } from '@/onboarding-process/core/ats'
import { GATE_LABEL } from '@/onboarding-process/core/ats'
import { useApplicants, useReadCvs, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, Spinner } from '@/components/ui'
import { Checkbox, Modal, Select, Table, Textarea, td, th } from '@/components/kit'
import { ApplicantDialog } from './dialogs/ApplicantDialog'
import { AddApplicantsDialog } from './dialogs/AddApplicantsDialog'

type SortKey = 'created_at' | 'full_name' | 'source' | 'score'
type Move = 'shortlisted' | 'screened_out' | 'applied'

export const gateTone = (gate: Gate | null | undefined) => (gate === 'pass' ? 'green' : gate === 'fail' ? 'red' : 'orange')

export function ScoreCell({ a }: { a: Applicant }) {
  const p = a.profile
  if (!a.has_cv) return <span className="text-xs text-slate-400">No CV</span>
  if (!p) return <span className="text-xs text-slate-400">Not read</span>
  if (p.status === 'reading') return <span className="text-xs text-slate-500">Reading…</span>
  if (p.status === 'failed') return <Badge tone="orange">Enter by hand</Badge>
  return (
    <div className="flex items-center gap-2">
      <span className="w-10 font-semibold tabular-nums text-slate-900">{p.ats_score ?? '—'}</span>
      <Badge tone={gateTone(p.gate)}>{p.gate ? GATE_LABEL[p.gate] : '—'}</Badge>
    </div>
  )
}

export function ApplicantsPanel({ post }: { post: JobPost }) {
  const manage = post.can?.manage ?? true
  const applicants = useApplicants(post.id)
  const read = useReadCvs(post.id)
  const setMode = useRecruitAction<{ p_job_post_id: string; p_mode: CvMode | null }>('set_post_cv_mode')
  const move = useRecruitAction<{ p_job_post_id: string; p_ids: string[]; p_to: Move; p_note: string | null }, number>('move_applicants')
  const [source, setSource] = useState<ApplicantSource | ''>('')
  const [status, setStatus] = useState<ApplicantStatus | ''>('')
  const [sort, setSort] = useState<{ key: SortKey; desc: boolean }>({ key: 'score', desc: true })
  const [openId, setOpenId] = useState<string | null>(null)
  const [adding, setAdding] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [moving, setMoving] = useState<Move | null>(null)
  const [note, setNote] = useState('')
  const [progress, setProgress] = useState<number | null>(null)

  const all = applicants.data ?? []
  const rows = useMemo(() => {
    const list = all.filter((a) => (!source || a.source === source) && (!status || a.status === status))
    const dir = sort.desc ? -1 : 1
    const value = (a: Applicant) => (sort.key === 'score' ? a.profile?.ats_score ?? -1 : a[sort.key])
    return [...list].sort((a, b) => (value(a) < value(b) ? -dir : value(a) > value(b) ? dir : 0))
  }, [all, source, status, sort])
  const unread = all.filter((a) => a.has_cv && !a.profile).length
  const open = all.find((a) => a.id === openId)
  const chosen = all.filter((a) => selected.has(a.id))
  const needsReason = moving === 'screened_out' || (moving === 'shortlisted' && chosen.some((a) => a.profile?.gate !== 'pass'))

  const toggle = (id: string) => setSelected((s) => {
    const next = new Set(s)
    if (next.has(id)) next.delete(id)
    else next.add(id)
    return next
  })
  const header = (key: SortKey, label: string) => (
    <th className={th}>
      <button type="button" className="inline-flex items-center gap-1 uppercase hover:text-slate-800"
        onClick={() => setSort((s) => ({ key, desc: s.key === key ? !s.desc : key === 'created_at' || key === 'score' }))}>
        {label}<ArrowDownUp className="size-3" />
      </button>
    </th>
  )
  const startRead = (again: boolean) => {
    setProgress(0)
    read.mutate({ again, onRound: setProgress }, { onSettled: () => setProgress(null) })
  }
  const doMove = () => moving && move.mutate(
    { p_job_post_id: post.id, p_ids: chosen.map((a) => a.id), p_to: moving, p_note: note.trim() || null },
    { onSuccess: () => { setMoving(null); setNote(''); setSelected(new Set()) } },
  )

  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <p className="text-sm text-slate-500">CVs are kept only until the vacancy closes. The score helps; HR decides.</p>
        <div className="flex flex-wrap items-end gap-2">
          <Select aria-label="Filter by status" value={status} onChange={(e) => setStatus(e.target.value as ApplicantStatus | '')}
            options={[{ value: '', label: 'All statuses' }, ...(['applied', 'shortlisted', 'screened_out'] as ApplicantStatus[])
              .map((v) => ({ value: v, label: APPLICANT_STATUS_LABEL[v] }))]} />
          <Select aria-label="Filter by source" value={source} onChange={(e) => setSource(e.target.value as ApplicantSource | '')}
            options={[{ value: '', label: 'All sources' }, ...Object.entries(SOURCE_LABEL).map(([value, label]) => ({ value, label }))]} />
          {manage && <Button variant="secondary" onClick={() => setAdding(true)}><UserPlus className="size-4" />Add applicants</Button>}
        </div>
      </div>

      {manage && (
        <div className="flex flex-wrap items-center gap-3 rounded-2xl bg-slate-50 p-3">
          <Bot className="size-4 text-primary-600" />
          <Select aria-label="CV reading for this post" value={post.cv_mode ?? ''} disabled={setMode.isPending}
            onChange={(e) => setMode.mutate({ p_job_post_id: post.id, p_mode: (e.target.value || null) as CvMode | null })}
            options={[{ value: '', label: `Company setting (${post.cv_mode_effective === 'ai' ? 'AI' : 'Basic'})` },
              { value: 'basic', label: 'Basic (no AI) for this post' }, { value: 'ai', label: 'AI for this post' }]} />
          {post.cv_mode_effective === 'ai' && !post.ai_ready && <span className="text-xs text-amber-700">No AI key set: Basic is used.</span>}
          <div className="ml-auto flex flex-wrap gap-2">
            <Button disabled={unread === 0 || read.isPending} loading={read.isPending && progress !== null} onClick={() => startRead(false)}>
              <FileText className="size-4" />{read.isPending ? `Reading… ${progress ?? 0} done` : `Read ${unread} new CV${unread === 1 ? '' : 's'}`}
            </Button>
            <Button variant="ghost" disabled={read.isPending} onClick={() => confirm('Read all CVs again? HR corrections are kept.') && startRead(true)}>
              <RefreshCw className="size-4" />Read again
            </Button>
          </div>
        </div>
      )}
      {read.isError && <Alert>{errorMessage(read.error)}</Alert>}
      {read.isSuccess && <Alert tone={read.data.failed ? 'info' : 'success'}>
        Read {read.data.total} CV{read.data.total === 1 ? '' : 's'}.{read.data.failed > 0 && ` ${read.data.failed} could not be read — open them and enter the details by hand.`}
      </Alert>}

      {manage && selected.size > 0 && (
        <div className="flex flex-wrap items-center gap-2 rounded-2xl bg-primary-50 p-3 text-sm">
          <ListChecks className="size-4 text-primary-700" /><span className="font-medium text-primary-900">{selected.size} selected</span>
          <Button className="ml-auto" onClick={() => setMoving('shortlisted')}>Shortlist</Button>
          <Button variant="secondary" onClick={() => setMoving('screened_out')}>Screen out</Button>
          <Button variant="ghost" onClick={() => setMoving('applied')}>Back to applied</Button>
        </div>
      )}

      {applicants.isPending ? <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
        : applicants.isError ? <Alert>{errorMessage(applicants.error)}</Alert>
          : rows.length === 0 ? (
            <EmptyState title={source || status ? 'No applicants match the filter' : 'No applicants yet'}>
              Share the apply link or the poster, or add people who sent their CV by email, LinkedIn or Bdjobs.
            </EmptyState>
          ) : (
            <Table minWidth={860} head={(
              <tr>{manage && <th className={`${th} w-10`}><span className="sr-only">Select</span></th>}
                {header('full_name', 'Name')}{header('score', 'Score')}<th className={th}>Contact</th>{header('source', 'Source')}
                <th className={th}>Status</th>{header('created_at', 'Applied')}</tr>
            )}>
              {rows.map((a) => (
                <tr key={a.id} className="cursor-pointer hover:bg-slate-50" onClick={() => setOpenId(a.id)}>
                  {manage && (
                    <td className={td} onClick={(e) => e.stopPropagation()}>
                      <Checkbox srOnlyLabel label={`Select ${a.full_name}`} checked={selected.has(a.id)} onChange={() => toggle(a.id)} />
                    </td>
                  )}
                  <td className={td}>
                    <button type="button" className="text-left font-medium text-slate-900 hover:text-primary-700" onClick={() => setOpenId(a.id)}>{a.full_name}</button>
                    {a.profile?.years != null && <p className="text-xs text-slate-400">{a.profile.years} y · {a.profile.education_level ?? 'education ?'}</p>}
                  </td>
                  <td className={td}><ScoreCell a={a} /></td>
                  <td className={td}><p className="text-xs">{a.email}</p><p className="text-xs text-slate-400">{a.phone ?? '—'}</p></td>
                  <td className={td}>{SOURCE_LABEL[a.source]}</td>
                  <td className={td}><Badge tone={a.status === 'shortlisted' ? 'green' : a.status === 'screened_out' ? 'red' : 'slate'}>{APPLICANT_STATUS_LABEL[a.status]}</Badge></td>
                  <td className={td}>{formatDate(a.created_at)}</td>
                </tr>
              ))}
            </Table>
          )}

      {moving && (
        <Modal open onClose={() => setMoving(null)} title={moving === 'shortlisted' ? 'Shortlist' : moving === 'screened_out' ? 'Screen out' : 'Back to applied'}
          description={`${chosen.length} applicant${chosen.length === 1 ? '' : 's'}`}
          footer={<>
            <Button variant="secondary" onClick={() => setMoving(null)}>Cancel</Button>
            <Button loading={move.isPending} disabled={needsReason && note.trim().length < 5} onClick={doMove}>Confirm</Button>
          </>}>
          <div className="space-y-3">
            {move.isError && <Alert>{errorMessage(move.error)}</Alert>}
            {moving === 'shortlisted' && needsReason && <Alert tone="info">Some of them did not pass the must-have check (or it needs checking by hand). Write why you shortlist them.</Alert>}
            <Textarea label={needsReason ? 'Reason (required)' : 'Note (optional)'} value={note} maxLength={500} onChange={(e) => setNote(e.target.value)} />
          </div>
        </Modal>
      )}
      {open && <ApplicantDialog key={open.id} applicant={open} post={post} onClose={() => setOpenId(null)} />}
      {adding && <AddApplicantsDialog postId={post.id} onClose={() => setAdding(false)} />}
    </section>
  )
}
