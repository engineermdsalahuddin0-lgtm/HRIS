import { useEffect, useMemo, useState } from 'react'
import { ArrowLeft, Lock, Pencil, Play, Plus, Star, Trash2 } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { PerformanceCycle, PerformancePerson, PerformanceReviewDetail } from '@/lib/statutory'
import { usePerformanceCycle, usePerformanceCycles, usePerformanceReview, useStatutoryAction } from '@/lib/statutory'
import { ratingFor, weightedScore } from '@/lib/calculationGuide'
import { useMyContext } from '@/lib/appContext'
import { ReferenceChips } from '@/components/references'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, Spinner, cx } from '@/components/ui'
import { Modal, PageHeader, Table, Textarea, td, th } from '@/components/kit'

const STATUS_TONE = { draft: 'slate', open: 'green', closed: 'orange' } as const
const REVIEW_LABEL: Record<PerformancePerson['review_status'], string> = {
  not_started: 'Not started', draft: 'Draft', submitted: 'Submitted', acknowledged: 'Acknowledged',
}
export const RATING_BANDS = [
  { min: 4.5, label: 'Outstanding', color: 'bg-green-600' },
  { min: 3.5, label: 'Exceeds expectations', color: 'bg-green-400' },
  { min: 2.5, label: 'Meets expectations', color: 'bg-sky-400' },
  { min: 1.5, label: 'Needs improvement', color: 'bg-amber-400' },
  { min: 0, label: 'Unsatisfactory', color: 'bg-red-500' },
]

/** Performance review cycles (manual scoring demo): list, cycle detail and scoring. */
export default function PerformancePage() {
  const ctx = useMyContext()
  const canManage = ctx.permissions.includes('performance.manage')
  const cycles = usePerformanceCycles()
  const [openCycleId, setOpenCycleId] = useState<string | null>(null)
  const [editing, setEditing] = useState<PerformanceCycle | 'new' | null>(null)

  if (openCycleId) return <CycleDetail cycleId={openCycleId} onBack={() => setOpenCycleId(null)} />
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Performance reviews"
        description="Manual scoring: weighted criteria, 1–5 scores with comments, and a rating everyone can trace."
        actions={canManage && <Button onClick={() => setEditing('new')}><Plus className="size-4" />New cycle</Button>} />
      <Card className="p-4">
        <p className="mb-2 text-sm font-medium text-slate-900">How the score is worked out</p>
        <p className="text-sm text-slate-600">Overall = Σ (score × weight) ÷ Σ weight. Rating bands:</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {RATING_BANDS.map((band) => (
            <span key={band.label} className="inline-flex items-center gap-1.5 text-xs text-slate-700">
              <span className={cx('size-2.5 rounded-full', band.color)} />{band.label} ({band.min > 0 ? `${band.min}+` : '< 1.5'})
            </span>
          ))}
        </div>
        <ReferenceChips keys={['policy.performance']} className="mt-2" />
      </Card>
      {cycles.isPending ? <PageLoader /> : cycles.isError ? <Alert>{errorMessage(cycles.error)}</Alert>
        : cycles.data.length === 0 ? <EmptyState title="No review cycles yet">{canManage ? 'Create a cycle with its criteria to start.' : 'HR has not opened a cycle yet.'}</EmptyState> : (
          <div className="grid gap-4 md:grid-cols-2">
            {cycles.data.map((cycle) => (
              <Card key={cycle.id} className="space-y-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <p className="font-semibold text-slate-900">{cycle.name}</p>
                    <p className="text-xs text-slate-500">{formatDate(cycle.period_from)} – {formatDate(cycle.period_to)}</p>
                  </div>
                  <Badge tone={STATUS_TONE[cycle.status]}>{cycle.status}</Badge>
                </div>
                <WeightBar criteria={cycle.criteria} />
                <div className="flex flex-wrap items-center justify-between gap-2 text-sm text-slate-600">
                  <span>{cycle.submitted} submitted{cycle.average_score !== null ? ` · average ${Number(cycle.average_score).toFixed(2)}` : ''}</span>
                  <div className="flex gap-2">
                    {canManage && cycle.status === 'draft' && (
                      <Button variant="ghost" onClick={() => setEditing(cycle)} aria-label={`Edit ${cycle.name}`}><Pencil className="size-4" /></Button>
                    )}
                    <Button variant="secondary" onClick={() => setOpenCycleId(cycle.id)}>Open</Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      {editing && <CycleDialog cycle={editing === 'new' ? null : editing} onClose={() => setEditing(null)} />}
    </div>
  )
}

/** Criteria weights as one stacked bar. */
function WeightBar({ criteria }: { criteria: { name: string; weight: number }[] }) {
  const colors = ['bg-primary-500', 'bg-sky-500', 'bg-green-500', 'bg-amber-400', 'bg-violet-500', 'bg-rose-400']
  return (
    <div>
      <div className="flex h-2.5 overflow-hidden rounded-full">
        {criteria.map((c, i) => <div key={c.name} className={colors[i % colors.length]} style={{ width: `${c.weight}%` }} title={`${c.name} ${c.weight}%`} />)}
      </div>
      <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
        {criteria.map((c, i) => (
          <span key={c.name} className="inline-flex items-center gap-1 text-xs text-slate-600">
            <span className={cx('size-2 rounded-full', colors[i % colors.length])} />{c.name} {c.weight}%
          </span>
        ))}
      </div>
    </div>
  )
}

interface DraftCriterion { id?: string; name: string; description: string; weight: string }

function CycleDialog({ cycle, onClose }: { cycle: PerformanceCycle | null; onClose: () => void }) {
  const save = useStatutoryAction<{ p_cycle_id: string | null; p: Record<string, unknown> }, string>('save_performance_cycle')
  const [name, setName] = useState(cycle?.name ?? '')
  const [from, setFrom] = useState(cycle?.period_from ?? '')
  const [to, setTo] = useState(cycle?.period_to ?? '')
  const [criteria, setCriteria] = useState<DraftCriterion[]>(cycle?.criteria.map((c) => ({
    id: c.id, name: c.name, description: c.description ?? '', weight: String(c.weight) })) ?? [
    { name: 'Quality of work', description: 'Accuracy and finish of the work', weight: '40' },
    { name: 'Teamwork', description: 'Helps others, shares knowledge', weight: '30' },
    { name: 'Attendance & discipline', description: 'On time, follows rules', weight: '30' },
  ])
  const total = criteria.reduce((sum, c) => sum + (Number(c.weight) || 0), 0)
  const update = (index: number, patch: Partial<DraftCriterion>) => setCriteria(criteria.map((c, i) => (i === index ? { ...c, ...patch } : c)))
  return (
    <Modal open onClose={onClose} size="lg" title={cycle ? 'Edit review cycle' : 'New review cycle'}
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={total !== 100 || name.trim().length < 3 || !from || !to}
          onClick={() => save.mutate({ p_cycle_id: cycle?.id ?? null, p: {
            name, period_from: from, period_to: to,
            criteria: criteria.map((c) => ({ id: c.id, name: c.name, description: c.description, weight: Number(c.weight) })),
          } }, { onSuccess: onClose })}>Save</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <Input label="Name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. H2 2026 review" />
        <div className="grid gap-4 sm:grid-cols-2">
          <Input label="Period from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          <Input label="Period to" type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        </div>
        <div>
          <div className="mb-2 flex items-center justify-between">
            <p className="text-sm font-medium text-slate-700">Criteria</p>
            <span className={cx('text-sm font-medium', total === 100 ? 'text-green-700' : 'text-red-600')}>Weights: {total} / 100</span>
          </div>
          <div className="space-y-2">
            {criteria.map((c, index) => (
              <div key={index} className="grid gap-2 rounded-xl p-3 ring-1 ring-slate-200 sm:grid-cols-[1fr_1.4fr_80px_auto]">
                <input aria-label="Criterion name" value={c.name} onChange={(e) => update(index, { name: e.target.value })} placeholder="Name"
                  className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-sm" />
                <input aria-label="Description" value={c.description} onChange={(e) => update(index, { description: e.target.value })} placeholder="What good looks like"
                  className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-sm" />
                <input aria-label="Weight percent" inputMode="decimal" value={c.weight} onChange={(e) => update(index, { weight: e.target.value })}
                  className="rounded-lg border border-slate-300 px-2.5 py-1.5 text-right text-sm" />
                <button type="button" aria-label="Remove criterion" disabled={criteria.length === 1}
                  onClick={() => setCriteria(criteria.filter((_, i) => i !== index))}
                  className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-red-600 disabled:opacity-30"><Trash2 className="size-4" /></button>
              </div>
            ))}
          </div>
          <Button variant="ghost" className="mt-1" onClick={() => setCriteria([...criteria, { name: '', description: '', weight: '0' }])}>
            <Plus className="size-4" />Add criterion
          </Button>
        </div>
      </div>
    </Modal>
  )
}

function CycleDetail({ cycleId, onBack }: { cycleId: string; onBack: () => void }) {
  const detail = usePerformanceCycle(cycleId)
  const setStatus = useStatutoryAction<{ p_cycle_id: string; p_status: string }>('set_performance_cycle_status')
  const [scoring, setScoring] = useState<PerformancePerson | null>(null)
  const distribution = useMemo(() => RATING_BANDS.map((band) => ({
    ...band, count: (detail.data?.people ?? []).filter((p) => p.rating === band.label).length,
  })), [detail.data])
  if (detail.isPending) return <PageLoader />
  if (detail.isError) return <Alert>{errorMessage(detail.error)}</Alert>
  const { cycle, people, can_manage } = detail.data
  const scored = distribution.reduce((s, d) => s + d.count, 0)
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <button onClick={onBack} className="inline-flex items-center gap-1 text-sm text-slate-500 hover:text-slate-800"><ArrowLeft className="size-4" />All cycles</button>
      <PageHeader title={cycle.name} description={`${formatDate(cycle.period_from)} – ${formatDate(cycle.period_to)} · ${cycle.status}`}
        actions={can_manage && (
          cycle.status === 'draft' ? <Button loading={setStatus.isPending} onClick={() => setStatus.mutate({ p_cycle_id: cycle.id, p_status: 'open' })}><Play className="size-4" />Open for scoring</Button>
          : cycle.status === 'open' ? <Button variant="secondary" loading={setStatus.isPending}
              onClick={() => confirm('Close this cycle? No more scores can be entered.') && setStatus.mutate({ p_cycle_id: cycle.id, p_status: 'closed' })}><Lock className="size-4" />Close cycle</Button>
          : null)} />
      {setStatus.isError && <Alert>{errorMessage(setStatus.error)}</Alert>}
      {cycle.status === 'draft' && <Alert tone="info">This cycle is a draft. Open it to start scoring.</Alert>}
      <Card className="p-4">
        <p className="mb-3 text-sm font-medium text-slate-900">Rating distribution ({scored} scored of {people.length})</p>
        <div className="space-y-1.5">
          {distribution.map((band) => (
            <div key={band.label} className="flex items-center gap-3 text-xs">
              <span className="w-40 shrink-0 text-slate-600">{band.label}</span>
              <div className="h-3 flex-1 rounded-full bg-slate-100">
                <div className={cx('h-3 rounded-full', band.color)} style={{ width: `${scored ? (band.count / scored) * 100 : 0}%` }} />
              </div>
              <span className="w-6 text-right tabular-nums">{band.count}</span>
            </div>
          ))}
        </div>
      </Card>
      <Table minWidth={680} head={
        <tr><th className={th}>Employee</th><th className={th}>Status</th><th className={th}>Score</th><th className={th}>Rating</th><th className={th} /></tr>
      }>
        {people.map((person) => (
          <tr key={person.employee_id}>
            <td className={td}><p className="font-medium text-slate-900">{person.full_name}</p>
              <p className="text-xs text-slate-400">{person.designation_name ?? ''}{person.department_name ? ` · ${person.department_name}` : ''}</p></td>
            <td className={td}><Badge tone={person.review_status === 'not_started' ? 'slate' : person.review_status === 'draft' ? 'orange' : 'green'}>{REVIEW_LABEL[person.review_status]}</Badge></td>
            <td className={`${td} tabular-nums`}>{person.overall_score !== null ? Number(person.overall_score).toFixed(2) : '—'}</td>
            <td className={td}>{person.rating ?? '—'}</td>
            <td className={`${td} text-right`}>
              <Button variant="secondary" disabled={cycle.status === 'draft'} onClick={() => setScoring(person)}>
                <Star className="size-4" />{person.review_status === 'not_started' || person.review_status === 'draft' ? 'Score' : 'View'}
              </Button>
            </td>
          </tr>
        ))}
      </Table>
      {people.length === 0 && <p className="text-center text-sm text-slate-400">No one to review in your scope.</p>}
      {scoring && <ScoreDialog cycleId={cycle.id} person={scoring} onClose={() => setScoring(null)} />}
    </div>
  )
}

function ScoreDialog({ cycleId, person, onClose }: { cycleId: string; person: PerformancePerson; onClose: () => void }) {
  const review = usePerformanceReview(cycleId, person.employee_id)
  return (
    <Modal open onClose={onClose} size="xl" title={`Review · ${person.full_name}`}>
      {review.isPending ? <div className="flex justify-center py-10 text-primary-600"><Spinner /></div>
        : review.isError ? <Alert>{errorMessage(review.error)}</Alert>
        : <ScoreForm detail={review.data} cycleId={cycleId} employeeId={person.employee_id} onDone={onClose} />}
    </Modal>
  )
}

function ScoreForm({ detail, cycleId, employeeId, onDone }: {
  detail: PerformanceReviewDetail; cycleId: string; employeeId: string; onDone: () => void
}) {
  const save = useStatutoryAction<{ p_cycle_id: string; p_employee_id: string; p: Record<string, unknown> }>('save_performance_review')
  const editable = !!detail.can_edit
  const [scores, setScores] = useState<Record<string, { score: number | null; comment: string }>>({})
  const [strengths, setStrengths] = useState('')
  const [improvements, setImprovements] = useState('')
  useEffect(() => {
    setScores(Object.fromEntries(detail.criteria.map((c) => [c.id, { score: c.score, comment: c.comment ?? '' }])))
    setStrengths(detail.review?.strengths ?? '')
    setImprovements(detail.review?.improvements ?? '')
  }, [detail])
  const rows = detail.criteria.map((c) => ({ ...c, score: scores[c.id]?.score ?? null }))
  const overall = weightedScore(rows)
  const missing = rows.filter((r) => r.score === null).length
  const submit = (finalise: boolean) => save.mutate({ p_cycle_id: cycleId, p_employee_id: employeeId, p: {
    scores: rows.map((r) => ({ criterion_id: r.id, score: r.score, comment: scores[r.id]?.comment ?? '' })),
    strengths, improvements, submit: finalise,
  } }, { onSuccess: () => finalise && onDone() })
  return (
    <div className="space-y-5">
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {!editable && detail.review && <Alert tone="info">This review was {detail.review.status} by {detail.review.reviewer_name ?? 'the reviewer'} and can no longer change.</Alert>}
      <div className="space-y-3">
        {rows.map((criterion) => (
          <div key={criterion.id} className="rounded-xl p-3 ring-1 ring-slate-200">
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="font-medium text-slate-900">{criterion.name} <span className="text-xs font-normal text-slate-500">· weight {criterion.weight}%</span></p>
                {criterion.description && <p className="text-xs text-slate-500">{criterion.description}</p>}
              </div>
              <div className="flex gap-1" role="radiogroup" aria-label={`Score for ${criterion.name}`}>
                {[1, 2, 3, 4, 5].map((value) => (
                  <button key={value} type="button" role="radio" aria-checked={criterion.score === value} disabled={!editable}
                    onClick={() => setScores({ ...scores, [criterion.id]: { ...scores[criterion.id], score: value } })}
                    className={cx('size-9 rounded-lg text-sm font-semibold ring-1 transition disabled:cursor-default',
                      criterion.score === value ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-600 ring-slate-300 hover:bg-slate-50')}>
                    {value}
                  </button>
                ))}
              </div>
            </div>
            <input aria-label={`Comment for ${criterion.name}`} disabled={!editable} value={scores[criterion.id]?.comment ?? ''} maxLength={500}
              onChange={(e) => setScores({ ...scores, [criterion.id]: { ...scores[criterion.id], comment: e.target.value } })}
              placeholder="Comment (example of the behaviour)" className="mt-2 w-full rounded-lg border border-slate-200 px-2.5 py-1.5 text-sm disabled:bg-slate-50" />
            {criterion.score !== null && (
              <p className="mt-1 text-right text-xs text-slate-500">{criterion.score} × {criterion.weight}% = {(criterion.score * criterion.weight / 100).toFixed(2)}</p>
            )}
          </div>
        ))}
      </div>
      <div className="rounded-xl bg-primary-50 p-4">
        <div className="flex items-center justify-between">
          <span className="font-medium text-slate-900">Overall (weighted)</span>
          <span className="text-2xl font-bold tabular-nums text-primary-700">{overall !== null ? overall.toFixed(2) : '—'}</span>
        </div>
        <p className="text-right text-sm text-slate-600">{ratingFor(overall) ?? 'Score the criteria to see the rating'}</p>
        <p className="mt-1 text-xs text-slate-500">Σ (score × weight) ÷ Σ weight of scored criteria</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Textarea label="Strengths" value={strengths} disabled={!editable} maxLength={1000} onChange={(e) => setStrengths(e.target.value)} />
        <Textarea label="To improve" value={improvements} disabled={!editable} maxLength={1000} onChange={(e) => setImprovements(e.target.value)} />
      </div>
      {detail.review?.employee_comment && <Alert tone="info">Employee's comment: {detail.review.employee_comment}</Alert>}
      {editable && (
        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="secondary" loading={save.isPending} onClick={() => submit(false)}>Save draft</Button>
          <Button loading={save.isPending} disabled={missing > 0} onClick={() => submit(true)}
            title={missing > 0 ? `Score all criteria (${missing} left)` : undefined}>Submit review</Button>
        </div>
      )}
    </div>
  )
}
