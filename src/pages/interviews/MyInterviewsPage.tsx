// Interviews where the signed-in employee sits on the panel (any role).
import { Link } from 'react-router-dom'
import { CalendarClock, CheckCircle2 } from 'lucide-react'
import { isoToZoned } from '@/onboarding-process/core/assessment'
import { useMyInterviews } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { Alert, Badge, EmptyState, PageLoader } from '@/components/ui'
import { PageHeader } from '@/components/kit'

export default function MyInterviewsPage() {
  const list = useMyInterviews()
  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const rows = list.data
  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="My interviews" description="Interviews where you are on the panel. Open one to see the applicant and give your scores." />
      {rows.length === 0 ? <EmptyState title="No interviews for you">When HR or a manager puts you on an interview panel, it appears here.</EmptyState> : (
        <div className="space-y-3">
          {rows.map((r) => {
            const z = isoToZoned(r.starts_at, r.timezone)
            return (
              <Link key={r.id} to={`/my-interviews/${r.id}`} className="flex flex-wrap items-center gap-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-200 hover:ring-primary-300">
                <CalendarClock className="size-5 text-primary-600" />
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-slate-900">{r.applicant_name} · {r.job_title}</p>
                  <p className="text-sm text-slate-500">{formatDate(z.date)} {z.time} · {r.mode === 'online' ? 'Online' : r.location} · {r.duration_minutes} min</p>
                </div>
                {r.scored ? <Badge tone="green"><CheckCircle2 className="mr-1 inline size-3" />Scored</Badge>
                  : r.status === 'done' ? <Badge>Done</Badge> : <Badge tone="orange">To score</Badge>}
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
