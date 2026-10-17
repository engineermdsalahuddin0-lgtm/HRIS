import { useState } from 'react'
import { CheckCircle2 } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import type { PerformanceReviewDetail } from '@/lib/statutory'
import { useMyPerformanceReviews, useStatutoryAction } from '@/lib/statutory'
import { ReferenceChips } from '@/components/references'
import { Alert, Badge, Button, Card, EmptyState, PageLoader } from '@/components/ui'
import { PageHeader, Textarea } from '@/components/kit'

/** An employee's own submitted reviews, with the weighted working, and acknowledgement. */
export default function MyReviewsPage() {
  const reviews = useMyPerformanceReviews()
  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="My reviews" description="Your performance reviews and how each score adds up to your rating." />
      {reviews.isPending ? <PageLoader /> : reviews.isError ? <Alert>{errorMessage(reviews.error)}</Alert>
        : reviews.data.length === 0 ? <EmptyState title="No reviews yet">Submitted reviews appear here.</EmptyState>
        : reviews.data.map((review) => <ReviewCard key={review.review!.id} detail={review} />)}
    </div>
  )
}

function ReviewCard({ detail }: { detail: PerformanceReviewDetail }) {
  const acknowledge = useStatutoryAction<{ p_review_id: string; p_comment: string | null }>('acknowledge_performance_review')
  const [comment, setComment] = useState('')
  const review = detail.review!
  return (
    <Card className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="font-semibold text-slate-900">{detail.cycle.name}</p>
          <p className="text-xs text-slate-500">{formatDate(detail.cycle.period_from)} – {formatDate(detail.cycle.period_to)} · reviewed by {review.reviewer_name ?? '—'}</p>
        </div>
        <div className="text-right">
          <p className="text-2xl font-bold tabular-nums text-primary-700">{review.overall_score !== null ? Number(review.overall_score).toFixed(2) : '—'}</p>
          <Badge tone="orange">{review.rating ?? '—'}</Badge>
        </div>
      </div>
      <table className="w-full text-sm">
        <thead className="text-xs text-slate-500"><tr><th className="pb-1 text-left font-medium">Criterion</th>
          <th className="pb-1 text-right font-medium">Score</th><th className="pb-1 text-right font-medium">× weight</th><th className="pb-1 text-right font-medium">= points</th></tr></thead>
        <tbody className="divide-y divide-slate-100">
          {detail.criteria.map((c) => (
            <tr key={c.id}>
              <td className="py-1.5">{c.name}{c.comment && <span className="block text-xs text-slate-500">{c.comment}</span>}</td>
              <td className="py-1.5 text-right tabular-nums">{c.score ?? '—'}</td>
              <td className="py-1.5 text-right tabular-nums">{c.weight}%</td>
              <td className="py-1.5 text-right tabular-nums">{c.weighted !== null ? Number(c.weighted).toFixed(2) : '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {(review.strengths || review.improvements) && (
        <div className="grid gap-3 sm:grid-cols-2 text-sm">
          {review.strengths && <div className="rounded-xl bg-green-50 p-3"><p className="text-xs font-medium text-green-800">Strengths</p><p>{review.strengths}</p></div>}
          {review.improvements && <div className="rounded-xl bg-amber-50 p-3"><p className="text-xs font-medium text-amber-800">To improve</p><p>{review.improvements}</p></div>}
        </div>
      )}
      <ReferenceChips keys={detail.references} />
      {review.status === 'acknowledged' ? (
        <p className="flex items-center gap-1.5 text-sm text-green-700"><CheckCircle2 className="size-4" />Acknowledged {formatDate(review.acknowledged_at)}
          {review.employee_comment ? ` — "${review.employee_comment}"` : ''}</p>
      ) : (
        <div className="space-y-2">
          {acknowledge.isError && <Alert>{errorMessage(acknowledge.error)}</Alert>}
          <Textarea label="Your comment (optional)" value={comment} maxLength={1000} onChange={(e) => setComment(e.target.value)} />
          <div className="flex justify-end">
            <Button loading={acknowledge.isPending} onClick={() => acknowledge.mutate({ p_review_id: review.id, p_comment: comment || null })}>Acknowledge review</Button>
          </div>
        </div>
      )}
    </Card>
  )
}
