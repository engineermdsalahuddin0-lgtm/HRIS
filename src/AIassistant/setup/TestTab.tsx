import { useState } from 'react'
import { CheckCircle2, MinusCircle } from 'lucide-react'
import { Card, cx } from '@/components/ui'
import { Tabs } from '@/components/kit'
import { ROLES, TOPICS } from '../core/catalog'
import type { RoleKey } from '../core/types'
import { useAssistantFor } from '../data/useAssistant'
import { ChatView } from '../widget/ChatView'
import { UpdatesView } from '../widget/UpdatesView'

/** Try the assistant exactly as a role would see it, with sample dashboard numbers. */
export function TestTab() {
  const [role, setRole] = useState<RoleKey>('employee')
  const [view, setView] = useState<'ask' | 'updates'>('ask')
  const a = useAssistantFor(role)

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Test as role">
        {ROLES.map((r) => (
          <button key={r.key} type="button" role="radio" aria-checked={role === r.key} onClick={() => setRole(r.key)}
            className={cx('rounded-full px-4 py-1.5 text-sm font-medium ring-1',
              role === r.key ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-700 ring-slate-300 hover:bg-slate-50')}>
            {r.label}
          </button>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[300px_1fr]">
        <Card className="h-fit space-y-4">
          <div>
            <h3 className="font-semibold text-slate-900">What this role gets</h3>
            <p className="text-xs text-slate-500">
              {!a.visible ? 'The assistant is off for this role.' : `${a.readable.length} resources readable`}
            </p>
          </div>
          {(['updates', 'knowledge'] as const).map((g) => (
            <div key={g}>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">{g}</p>
              <ul className="space-y-1">
                {TOPICS.filter((t) => t.group === g).map((t) => {
                  const on = a.allowed.has(t.key)
                  return (
                    <li key={t.key} className={cx('flex items-center gap-2 text-sm', on ? 'text-slate-800' : 'text-slate-400')}>
                      {on ? <CheckCircle2 className="size-4 text-green-600" aria-label="allowed" /> : <MinusCircle className="size-4" aria-label="not allowed" />}
                      {t.label}
                    </li>
                  )
                })}
              </ul>
            </div>
          ))}
        </Card>

        <Card className="flex h-[600px] flex-col overflow-hidden p-0">
          <div className="px-4 pt-2">
            <Tabs value={view} onChange={setView} tabs={[{ key: 'ask', label: 'Ask' }, { key: 'updates', label: 'Updates', count: a.updates.length }]} />
          </div>
          {!a.visible ? (
            <p className="p-8 text-center text-sm text-slate-500">This role does not see the floating button.</p>
          ) : view === 'ask' ? (
            <div className="flex min-h-0 flex-1 flex-col"><ChatView key={role} role={role} debug /></div>
          ) : (
            <div className="min-h-0 flex-1 overflow-y-auto"><UpdatesView updates={a.updates} messages={a.messages} /></div>
          )}
        </Card>
      </div>
      <p className="text-xs text-slate-500">
        Try: “How many casual leaves do I get?”, “What is Rahim's salary?”, “Show-cause notice rule?” (confidential), “অফিস কয়টায় শুরু হয়?”
      </p>
    </div>
  )
}
