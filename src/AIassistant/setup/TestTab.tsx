import { useState } from 'react'
import { CheckCircle2, MinusCircle } from 'lucide-react'
import { Alert, Card, cx } from '@/components/ui'
import type { ServerSetup } from '../data/api'
import { LiveChat } from '../widget/LiveChat'

/**
 * Ask the real assistant as if you had another role (assistant_preview_as_role): the same keys, index, role
 * ticks and permissions; no limits, nothing recorded. Updates are personal, so they are not previewed.
 */
export function TestTab({ setup }: { setup: ServerSetup }) {
  const [roleId, setRoleId] = useState(setup.roles.find((r) => r.system_key === 'employee')?.id ?? setup.roles[0].id)
  const role = setup.roles.find((r) => r.id === roleId)!
  const allowed = (key: string) => role.system_key === 'admin' || (!!role.ticks[key] && role.usable[key])
  const ready = setup.keys.chat?.status === 'tested' && !!setup.keys.embed_effective?.ready

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Test as role">
        {setup.roles.map((r) => (
          <button key={r.id} type="button" role="radio" aria-checked={roleId === r.id} onClick={() => setRoleId(r.id)}
            className={cx('rounded-full px-4 py-1.5 text-sm font-medium ring-1',
              roleId === r.id ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-700 ring-slate-300 hover:bg-slate-50')}>
            {r.name}
          </button>
        ))}
      </div>
      {!ready && <Alert tone="info">Test the chat and embedding keys first (API keys tab).</Alert>}
      <div className="grid gap-6 lg:grid-cols-[300px_1fr]">
        <Card className="h-fit space-y-4">
          <div>
            <h3 className="font-semibold text-slate-900">What {role.name} gets</h3>
            <p className="text-xs text-slate-500">{role.system_key === 'admin' || role.enabled ? 'Assistant on' : 'The assistant is off for this role.'}</p>
          </div>
          {(['knowledge', 'updates'] as const).map((g) => (
            <div key={g}>
              <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">{g}</p>
              <ul className="space-y-1">
                {setup.topics.filter((t) => t.group === g).map((t) => (
                  <li key={t.key} className={cx('flex items-center gap-2 text-sm', allowed(t.key) ? 'text-slate-800' : 'text-slate-400')}>
                    {allowed(t.key) ? <CheckCircle2 className="size-4 text-green-600" aria-label="allowed" /> : <MinusCircle className="size-4" aria-label="not allowed" />}
                    {t.label}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </Card>
        <Card className="flex h-[600px] flex-col overflow-hidden p-0">
          {ready ? (
            <LiveChat key={role.id} greeting={role.messages.greeting} suggestions={role.messages.suggestions} left={null}
              previewRoleId={role.id} debug />
          ) : (
            <p className="p-8 text-center text-sm text-slate-500">The preview needs working keys.</p>
          )}
        </Card>
      </div>
      <p className="text-xs text-slate-500">
        Try: “How do I apply for leave?”, “How do I run payroll?” (an Employee gets “Your role is not permitted for that feature.”),
        “What is Rahim's salary?”, a question about a confidential document.
      </p>
    </div>
  )
}
