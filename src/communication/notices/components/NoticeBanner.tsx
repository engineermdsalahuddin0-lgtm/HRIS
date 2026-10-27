import { Link } from 'react-router-dom'
import { BellRing, ChevronRight, Pin } from 'lucide-react'
import { useNoticeAlerts } from '../data/api'

/** Dashboard strip: pinned notices, unread count and acknowledgements still waiting. Hidden when empty. */
export default function NoticeBanner() {
  const alerts = useNoticeAlerts()
  const a = alerts.data
  if (!a || (a.pinned.length === 0 && a.unread === 0 && a.pending_ack === 0)) return null
  return (
    <section aria-label="Notices" className="rounded-2xl bg-primary-50 p-4 ring-1 ring-primary-100">
      <div className="flex flex-wrap items-center gap-3">
        <BellRing className="size-5 text-primary-600" aria-hidden />
        <p className="flex-1 text-sm text-primary-900">
          {a.pending_ack > 0 && <b>{a.pending_ack} notice{a.pending_ack === 1 ? '' : 's'} need your acknowledgement. </b>}
          {a.unread > 0 && <>{a.unread} unread notice{a.unread === 1 ? '' : 's'}.</>}
        </p>
        <Link to="/notices" className="inline-flex items-center gap-1 text-sm font-medium text-primary-700 hover:underline">
          Open notices <ChevronRight className="size-4" aria-hidden />
        </Link>
      </div>
      {a.pinned.length > 0 && (
        <ul className="mt-3 space-y-1.5">
          {a.pinned.slice(0, 3).map((p) => (
            <li key={p.id}>
              <Link to={`/notices?open=${p.id}`} className="flex items-center gap-2 rounded-xl bg-white px-3 py-2 text-sm text-slate-800 ring-1 ring-primary-100 hover:bg-primary-50">
                <Pin className="size-3.5 shrink-0 text-primary-600" aria-hidden />
                <span className="flex-1 truncate">{p.title}</span>
                {!p.read && <span className="size-2 rounded-full bg-primary-500" aria-label="unread" />}
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
