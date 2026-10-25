// Results of one post: every interviewed applicant ranked by the composite score, with each
// component, the panel's scores and a flag when the interviewers disagree a lot. HR decides (next step).
import { AlertTriangle, Trophy } from 'lucide-react'
import type { JobPost } from '@/onboarding-process/core/types'
import { COMPONENT_LABEL } from '@/onboarding-process/core/composite'
import { RECOMMENDATION_LABEL } from '@/onboarding-process/core/interview'
import { WEIGHT_LABEL } from '@/onboarding-process/core/jobPost'
import { useCandidateResults } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { Alert, Badge, EmptyState, Spinner } from '@/components/ui'
import { Table, td, th } from '@/components/kit'

export function ResultsPanel({ post }: { post: JobPost }) {
  const results = useCandidateResults(post.id)
  if (results.isPending) return <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
  if (results.isError) return <Alert>{errorMessage(results.error)}</Alert>
  const r = results.data
  return (
    <section className="space-y-4">
      <p className="text-sm text-slate-600">
        Composite = each score × its weight ÷ the weights of the scores that exist
        ({(Object.keys(WEIGHT_LABEL) as (keyof typeof WEIGHT_LABEL)[]).filter((k) => k !== 'written' || r.has_written_test).map((k) => `${WEIGHT_LABEL[k]} ${r.weights[k]}`).join(' · ')}).
        Interview % = (panel mean − 1) ÷ 4 × 100. Missing scores are left out, not counted as zero.
      </p>
      {r.rows.length === 0 ? <EmptyState title="No interviews yet">Applicants appear here once they have an interview.</EmptyState> : (
        <Table minWidth={900} head={(
          <tr><th className={th}>#</th><th className={th}>Applicant</th><th className={th}>Composite</th><th className={th}>Components</th><th className={th}>Panel</th></tr>
        )}>
          {r.rows.map((row, i) => {
            const f = row.figures
            const complete = row.interview_status === 'done'
            return (
              <tr key={row.applicant_id} className="align-top">
                <td className={`${td} tabular-nums`}>{i === 0 && complete ? <Trophy className="size-4 text-amber-500" aria-label="Top" /> : i + 1}</td>
                <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p>
                  <p className="text-xs text-slate-400">{complete ? 'Interview done' : `${row.scores.length}/${row.panel_size} scored`}</p></td>
                <td className={td}><p className="text-2xl font-semibold tabular-nums text-slate-900">{f.composite ?? '—'}</p>
                  {f.spread_flag && <p className="flex items-center gap-1 text-[11px] text-amber-700"><AlertTriangle className="size-3" />Panel disagrees (spread {f.spread})</p>}</td>
                <td className={td}>
                  <ul className="space-y-0.5 text-xs">{f.components.map((c) => (
                    <li key={c.key}><span className="inline-block w-20 text-slate-500">{COMPONENT_LABEL[c.key]}</span>
                      <span className="tabular-nums text-slate-800">{c.percent}%</span>
                      <span className="text-slate-400"> × {c.effective_weight}% = {c.points}</span></li>
                  ))}</ul>
                </td>
                <td className={td}>
                  <ul className="space-y-0.5 text-xs">{row.scores.map((s) => (
                    <li key={s.full_name}><span className="font-medium text-slate-800">{s.full_name}</span> {s.mean} · <Badge tone={s.recommendation.endsWith('yes') ? 'green' : 'red'}>{RECOMMENDATION_LABEL[s.recommendation]}</Badge></li>
                  ))}</ul>
                  {f.panel_mean != null && <p className="mt-1 text-[11px] text-slate-500">Mean {f.panel_mean} → {f.interview_percent}%</p>}
                </td>
              </tr>
            )
          })}
        </Table>
      )}
    </section>
  )
}
