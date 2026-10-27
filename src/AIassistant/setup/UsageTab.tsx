import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { Alert, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { Table, td, th } from '@/components/kit'
import { useRunPurge, useUsage } from '../data/api'

const KIND_LABEL: Record<string, string> = {
  answer: 'Answered', dont_know: "Didn't know", not_allowed: 'Not allowed', personal_data: 'Personal data', updates: 'Updates', refused: 'Refused',
}

/** Admin only (assistant.view_usage): questions, tokens against the cap, gaps in the documents, purge. */
export function UsageTab() {
  const [days, setDays] = useState(30)
  const usage = useUsage(days, true)
  const purge = useRunPurge()
  if (usage.isPending) return <PageLoader />
  if (usage.isError) return <Alert>{errorMessage(usage.error)}</Alert>
  const u = usage.data
  const max = Math.max(1, ...u.per_day.map((d) => d.questions))
  const capPct = u.monthly_cap ? Math.min(100, Math.round((u.tokens_month / u.monthly_cap) * 100)) : null

  return (
    <div className="space-y-6">
      <div className="inline-flex rounded-lg bg-slate-100 p-0.5 text-sm" role="radiogroup" aria-label="Period">
        {[7, 30, 90].map((d) => (
          <button key={d} type="button" role="radio" aria-checked={days === d} onClick={() => setDays(d)}
            className={cx('rounded-md px-3 py-1 font-medium', days === d ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>{d} days</button>
        ))}
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Card className="p-4"><p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Questions</p><p className="mt-1 text-2xl font-semibold text-slate-900">{u.total}</p></Card>
        <Card className="p-4"><p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Answered</p><p className="mt-1 text-2xl font-semibold text-slate-900">{u.by_kind.answer ?? 0}</p></Card>
        <Card className="p-4"><p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Not answered</p><p className="mt-1 text-2xl font-semibold text-slate-900">{(u.by_kind.dont_know ?? 0) + (u.by_kind.not_allowed ?? 0)}</p></Card>
        <Card className="p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Tokens this month</p>
          <p className="mt-1 text-2xl font-semibold text-slate-900">{u.tokens_month.toLocaleString()}</p>
          <p className="text-xs text-slate-500">{u.monthly_cap ? `${capPct}% of ${u.monthly_cap.toLocaleString()}` : 'No monthly cap'}</p>
        </Card>
      </div>

      <Card className="space-y-3">
        <h3 className="font-semibold text-slate-900">Questions per day</h3>
        {u.per_day.length === 0 ? <p className="text-sm text-slate-500">No questions yet.</p> : (
          <ul className="space-y-1.5" aria-label="Questions per day">
            {u.per_day.map((d) => (
              <li key={d.day} className="flex items-center gap-3 text-xs">
                <span className="w-20 shrink-0 text-slate-500">{formatDate(d.day)}</span>
                <span className="h-3 rounded bg-primary-500" style={{ width: `${(d.questions / max) * 100}%`, minWidth: 4 }} aria-hidden />
                <span className="text-slate-700">{d.questions}</span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="space-y-3">
          <h3 className="font-semibold text-slate-900">By role</h3>
          {u.per_role.length === 0 ? <p className="text-sm text-slate-500">—</p> : (
            <Table minWidth={300} head={<tr><th className={th}>Role</th><th className={th}>Questions</th><th className={th}>People</th></tr>}>
              {u.per_role.map((r) => <tr key={r.role}><td className={td}>{r.role}</td><td className={td}>{r.questions}</td><td className={td}>{r.people}</td></tr>)}
            </Table>
          )}
          <div className="flex flex-wrap gap-2 pt-2 text-xs text-slate-500">
            {Object.entries(u.by_kind).map(([k, n]) => <span key={k} className="rounded-full bg-slate-100 px-2 py-0.5">{KIND_LABEL[k] ?? k}: {n}</span>)}
          </div>
        </Card>
        <Card className="space-y-3">
          <h3 className="font-semibold text-slate-900">Could not answer</h3>
          <p className="text-xs text-slate-500">Questions without an answer in your documents or the app guide: upload the missing policy.</p>
          {u.unanswered.length === 0 ? <EmptyState title="Nothing missing" /> : (
            <ul className="space-y-2 text-sm">
              {u.unanswered.map((q, i) => <li key={i} className="rounded-xl bg-slate-50 p-2.5"><p className="text-slate-800">{q.question}</p><p className="text-xs text-slate-500">{q.route ?? ''} · {formatDateTime(q.asked_at)}</p></li>)}
            </ul>
          )}
        </Card>
      </div>

      <Card className="space-y-3">
        <h3 className="font-semibold text-slate-900">Marked “not helpful”</h3>
        {u.not_helpful.length === 0 ? <p className="text-sm text-slate-500">None.</p> : (
          <ul className="space-y-2 text-sm">
            {u.not_helpful.map((q, i) => <li key={i} className="rounded-xl bg-slate-50 p-2.5"><p className="text-slate-800">{q.question}</p><p className="text-xs text-slate-500">{q.route ?? ''} · {formatDateTime(q.asked_at)}</p></li>)}
          </ul>
        )}
      </Card>

      <Card className="flex flex-wrap items-center gap-4">
        <div className="min-w-0 flex-1">
          <h3 className="font-semibold text-slate-900">Retention</h3>
          <p className="text-sm text-slate-500">Question text and chats older than {u.retention_days} days are removed; the counts stay. Run it now, or let the scheduled job do it once pg_cron is set up.</p>
        </div>
        <Button variant="secondary" loading={purge.isPending} onClick={() => purge.mutate()}>Remove old questions now</Button>
        {purge.isSuccess && <p className="w-full text-sm text-green-700">Cleared {purge.data.questions_cleared} questions, deleted {purge.data.conversations_deleted} chats.</p>}
        {purge.isError && <p className="w-full text-sm text-red-600">{errorMessage(purge.error)}</p>}
      </Card>
    </div>
  )
}
