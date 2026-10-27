import { Link } from 'react-router-dom'
import { ChevronRight, Pin } from 'lucide-react'
import { cx } from '@/components/ui'
import type { RoleMessages, UpdateItem } from '../core/types'

const DOT = { info: 'bg-sky-500', action: 'bg-primary-500', good: 'bg-green-500' }

/** The digest: no AI call, so it works even before an API key is given (decision D1). */
export function UpdatesView({ updates, messages, onNavigate }: { updates: UpdateItem[]; messages: RoleMessages; onNavigate?: () => void }) {
  return (
    <div className="space-y-3 p-4">
      {messages.notice && (
        <div className="flex gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-800 ring-1 ring-amber-200">
          <Pin className="mt-0.5 size-4 shrink-0" aria-hidden />
          <p>{messages.notice}</p>
        </div>
      )}
      {updates.length === 0 ? (
        <p className="py-10 text-center text-sm text-slate-500">No updates for you right now.</p>
      ) : (
        <ul className="space-y-2">
          {updates.map((u) => {
            const inner = (
              <>
                <span className={cx('mt-1.5 size-2 shrink-0 rounded-full', DOT[u.tone])} aria-hidden />
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-medium text-slate-900">{u.title}</span>
                  <span className="block text-xs text-slate-500">{u.detail}</span>
                </span>
                {u.link && <ChevronRight className="mt-1 size-4 shrink-0 text-slate-400" aria-hidden />}
              </>
            )
            const cls = 'flex gap-3 rounded-xl p-3 ring-1 ring-slate-200'
            return (
              <li key={u.key}>
                {u.link ? (
                  <Link to={u.link} onClick={onNavigate} className={cx(cls, 'hover:bg-slate-50')}>{inner}</Link>
                ) : (
                  <div className={cls}>{inner}</div>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
