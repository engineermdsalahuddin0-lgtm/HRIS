// The full applicant profile (row click): contact, what was read from the CV, the must-have
// gate and ATS breakdown, HR corrections, the CV text, history. Later steps add test and interview scores.
import { useRef, useState } from 'react'
import { ExternalLink, Pencil, Upload } from 'lucide-react'
import type { Applicant, ApplicantProfile, EducationLevel, JobPost } from '@/onboarding-process/core/types'
import { APPLICANT_STATUS_LABEL, CV_ACCEPT, EDUCATION_LABEL, SOURCE_LABEL } from '@/onboarding-process/core/jobPost'
import { GATE_LABEL, REASON_TEXT } from '@/onboarding-process/core/ats'
import { openCv, useRecruitAction, useUploadApplicantCv } from '@/lib/recruit'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Input } from '@/components/ui'
import { Checkbox, Modal, Select, Textarea } from '@/components/kit'
import { Markdown } from '@/components/Markdown'
import { gateTone } from '../ApplicantsPanel'

const EVENT_LABEL: Record<string, string> = {
  applied: 'Applied on the careers page', added_by_hr: 'Added by HR', cv_uploaded: 'CV uploaded', cv_attached: 'CV uploaded by HR',
  moved_shortlisted: 'Shortlisted', moved_screened_out: 'Screened out', moved_applied: 'Moved back to applied',
}
const SOURCE_TEXT = { ai: 'AI', estimate: 'estimated', hr: 'HR', manual: 'HR', basic: 'basic' } as const
type Level = Exclude<EducationLevel, 'any'>

function Bar({ label, value, max, hint }: { label: string; value: number | null; max: number; hint?: string }) {
  return (
    <div>
      <div className="flex justify-between text-xs"><span className="text-slate-600">{label}</span>
        <span className="font-medium tabular-nums text-slate-900">{value == null ? 'not set' : `${value} / ${max}`}</span></div>
      <div className="mt-1 h-2 rounded-full bg-slate-100">
        <div className="h-2 rounded-full bg-primary-500" style={{ width: `${Math.min(100, ((value ?? 0) / max) * 100)}%` }} />
      </div>
      {hint && <p className="mt-0.5 text-[11px] text-slate-400">{hint}</p>}
    </div>
  )
}

function Correction({ applicant, post, profile, onDone }: { applicant: Applicant; post: JobPost; profile: ApplicantProfile | null; onDone: () => void }) {
  const save = useRecruitAction<{ p_applicant_id: string; p: Record<string, unknown> }>('save_applicant_profile')
  const [years, setYears] = useState(profile?.years == null ? '' : String(profile.years))
  const [level, setLevel] = useState<Level | ''>(profile?.education_level ?? '')
  const [req, setReq] = useState(new Set(profile?.matched_required ?? []))
  const [nice, setNice] = useState(new Set(profile?.matched_nice ?? []))
  const [subject, setSubject] = useState(profile?.subject_matched ?? false)
  const [relevance, setRelevance] = useState(profile?.relevance == null ? '' : String(profile.relevance))
  const [reason, setReason] = useState(profile?.relevance_reason ?? '')
  const flip = (set: Set<string>, value: string) => { const n = new Set(set); if (n.has(value)) n.delete(value); else n.add(value); return n }
  return (
    <div className="space-y-3 rounded-xl border border-primary-200 bg-primary-50/40 p-4">
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <div className="grid gap-3 sm:grid-cols-3">
        <Input label="Years of experience" inputMode="decimal" value={years} onChange={(e) => setYears(e.target.value)} />
        <Select label="Highest education" value={level} onChange={(e) => setLevel(e.target.value as Level | '')} placeholder="Unknown"
          options={(Object.keys(EDUCATION_LABEL) as EducationLevel[]).filter((l) => l !== 'any').map((l) => ({ value: l, label: EDUCATION_LABEL[l] }))} />
        <Input label="Relevance (0–15)" inputMode="decimal" value={relevance} onChange={(e) => setRelevance(e.target.value)} hint="Empty = not set (score out of 85)" />
      </div>
      {post.profile.required_skills.length > 0 && (
        <div><p className="mb-1 text-xs font-medium text-slate-600">Required skills the applicant has</p>
          <div className="flex flex-wrap gap-3">{post.profile.required_skills.map((s) => (
            <Checkbox key={s} label={s} checked={req.has(s)} onChange={() => setReq(flip(req, s))} />))}</div></div>
      )}
      {post.profile.nice_skills.length > 0 && (
        <div><p className="mb-1 text-xs font-medium text-slate-600">Nice-to-have skills</p>
          <div className="flex flex-wrap gap-3">{post.profile.nice_skills.map((s) => (
            <Checkbox key={s} label={s} checked={nice.has(s)} onChange={() => setNice(flip(nice, s))} />))}</div></div>
      )}
      {post.profile.education_subjects.length > 0 && (
        <Checkbox label={`Studied ${post.profile.education_subjects.join(' / ')}`} checked={subject} onChange={setSubject} />
      )}
      <Textarea label="Why this relevance? (optional)" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={onDone}>Cancel</Button>
        <Button loading={save.isPending} onClick={() => save.mutate({ p_applicant_id: applicant.id, p: {
          years: years === '' ? null : Number(years), education_level: level || null, matched_required: [...req], matched_nice: [...nice],
          subject_matched: subject, relevance: relevance === '' ? null : Number(relevance), relevance_reason: reason,
        } }, { onSuccess: onDone })}>Save and rescore</Button>
      </div>
    </div>
  )
}

export function ApplicantDialog({ applicant: a, post, onClose }: { applicant: Applicant; post: JobPost; onClose: () => void }) {
  const ctx = useMyContext()
  const manage = post.can?.manage ?? true
  const upload = useUploadApplicantCv(ctx.organization?.id, post.id)
  const input = useRef<HTMLInputElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState(false)
  const [showText, setShowText] = useState(false)
  const p = a.profile ?? null
  const f = p?.figures ?? null

  const view = () => a.cv_path && openCv(a.cv_path).catch((e) => setError(errorMessage(e)))

  return (
    <Modal open onClose={onClose} size="xl" title={a.full_name}
      description={<>{post.title} · <Badge>{APPLICANT_STATUS_LABEL[a.status]}</Badge></>}>
      <div className="grid gap-6 lg:grid-cols-[1fr_1.1fr]">
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
            {a.has_cv && manage && <Button variant="secondary" onClick={view}><ExternalLink className="size-4" />Open CV</Button>}
            {manage && (
              <>
                <input ref={input} type="file" accept={CV_ACCEPT} className="hidden" onChange={(e) => {
                  const file = e.target.files?.[0]
                  e.target.value = ''
                  if (file) upload.mutate({ applicantId: a.id, file, previous: a.cv_path })
                }} />
                <Button variant={a.has_cv ? 'ghost' : 'primary'} loading={upload.isPending} onClick={() => input.current?.click()}>
                  <Upload className="size-4" />{a.has_cv ? 'Replace' : 'Upload CV'}
                </Button>
              </>
            )}
          </div>
          {p?.markdown && (
            <div>
              <button type="button" className="text-sm font-medium text-primary-700 hover:underline" onClick={() => setShowText((s) => !s)}>
                {showText ? 'Hide the CV text' : 'Show the CV text (markdown)'}
              </button>
              {showText && <div className="mt-2 max-h-80 overflow-y-auto rounded-xl bg-slate-50 p-3"><Markdown source={p.markdown} /></div>}
            </div>
          )}
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
            {(a.decisions ?? []).filter((d) => d.note).map((d, i) => (
              <p key={i} className="mt-2 rounded-lg bg-slate-50 p-2 text-xs text-slate-600">{APPLICANT_STATUS_LABEL[d.to_status as Applicant['status']] ?? d.to_status}: {d.note} — {d.actor_name}</p>
            ))}
          </div>
        </div>

        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-slate-900">Screening</h3>
            {manage && !editing && <Button variant="ghost" onClick={() => setEditing(true)}><Pencil className="size-4" />Correct</Button>}
          </div>
          {editing ? <Correction applicant={a} post={post} profile={p} onDone={() => setEditing(false)} />
            : !p ? <Alert tone="info">{a.has_cv ? 'The CV has not been read yet. Use "Read new CVs" on the Applicants tab, or enter the details by hand.' : 'No CV. Upload one or enter the details by hand.'}</Alert>
              : p.status === 'failed' ? <Alert>{p.error ?? 'The CV could not be read.'} Use “Correct” to enter the details.</Alert>
                : (
                  <>
                    <div className="flex items-end gap-3">
                      <span className="text-4xl font-semibold tabular-nums text-slate-900">{p.ats_score ?? '—'}</span>
                      <span className="pb-1 text-sm text-slate-500">/ 100 ATS score</span>
                      {p.gate && <span className="ml-auto pb-1"><Badge tone={gateTone(p.gate)}>{GATE_LABEL[p.gate]}</Badge></span>}
                    </div>
                    {f && f.reasons.length > 0 && <ul className="list-disc pl-5 text-sm text-red-700">{f.reasons.map((r) => <li key={r}>{REASON_TEXT[r]}</li>)}</ul>}
                    {f && (
                      <div className="space-y-3 rounded-xl border border-slate-200 p-4">
                        <Bar label={`Skills (${f.req_matched}/${f.req_total} required${f.nice_total ? `, ${f.nice_matched}/${f.nice_total} nice-to-have` : ''})`} value={f.skills} max={40}
                          hint={p.matched_required.length ? `Found: ${[...p.matched_required, ...p.matched_nice].join(', ')}` : undefined} />
                        <Bar label={`Experience (${p.years ?? '?'} y of ${f.min_years} needed)`} value={f.experience} max={25}
                          hint={p.years_source ? `Years: ${SOURCE_TEXT[p.years_source]}` : undefined} />
                        <Bar label={`Education (${p.education_level ? EDUCATION_LABEL[p.education_level] : 'unknown'})`} value={f.education} max={20}
                          hint={p.subject_matched ? 'Listed subject found' : undefined} />
                        <Bar label="Relevance of past roles" value={f.relevance} max={15} hint={p.relevance_reason ?? (f.relevance == null ? 'Not set: the score is out of 85' : undefined)} />
                        <p className="text-xs text-slate-500">Score = ({f.skills} + {f.experience} + {f.education}{f.relevance != null ? ` + ${f.relevance}` : ''}) ÷ {f.max} × 100 = {f.score}</p>
                      </div>
                    )}
                    {p.summary && <p className="rounded-xl bg-slate-50 p-3 text-sm text-slate-700">{p.summary}</p>}
                    <p className="text-xs text-slate-500">
                      Read {p.mode_used ? `by ${SOURCE_TEXT[p.mode_used]}` : ''}{p.ai_model ? ` (${p.ai_model})` : ''}{p.read_at ? ` · ${formatDateTime(p.read_at)}` : ''}
                      {p.ai_error ? ` · ${p.ai_error}` : ''}
                    </p>
                  </>
                )}
        </div>
      </div>
    </Modal>
  )
}
