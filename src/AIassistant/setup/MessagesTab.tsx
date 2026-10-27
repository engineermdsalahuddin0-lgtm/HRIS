import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, Input, cx } from '@/components/ui'
import { Textarea } from '@/components/kit'
import type { ServerRole, ServerSetup } from '../data/api'
import { useSaveRoleMessages } from '../data/api'

const MAX_SUGGESTIONS = 6

/** What each role sees first: greeting, suggested questions, a pinned notice, the "not allowed" reply. */
export function MessagesTab({ setup }: { setup: ServerSetup }) {
  const [roleId, setRoleId] = useState(setup.roles.find((r) => r.system_key === 'employee')?.id ?? setup.roles[0].id)
  const role = setup.roles.find((r) => r.id === roleId)!
  return (
    <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
      <Card className="h-fit p-2">
        <ul className="space-y-1">
          {setup.roles.map((r) => (
            <li key={r.id}>
              <button type="button" onClick={() => setRoleId(r.id)}
                className={cx('w-full rounded-xl px-3 py-2.5 text-left text-sm font-medium', r.id === roleId ? 'bg-primary-50 text-primary-700' : 'text-slate-700 hover:bg-slate-50')}>
                {r.name}
              </button>
            </li>
          ))}
        </ul>
      </Card>
      <RoleMessages key={role.id + JSON.stringify(role.messages)} role={role} />
    </div>
  )
}

function RoleMessages({ role }: { role: ServerRole }) {
  const save = useSaveRoleMessages()
  const [m, setM] = useState(role.messages)
  const [suggestions, setSuggestions] = useState(role.messages.suggestions.join('\n'))
  const lines = suggestions.split('\n').map((s) => s.trim()).filter(Boolean)
  return (
    <Card className="space-y-5">
      <Textarea label="Greeting" name="greeting" value={m.greeting} maxLength={240} onChange={(e) => setM({ ...m, greeting: e.target.value })}
        hint='Starts with "Hi!" to add the person’s first name.' />
      <Textarea label="Suggested questions" name="suggestions" rows={4} value={suggestions} onChange={(e) => setSuggestions(e.target.value)}
        hint={`One per line, up to ${MAX_SUGGESTIONS}. Bangla is fine.`}
        error={lines.length > MAX_SUGGESTIONS ? `At most ${MAX_SUGGESTIONS}.` : undefined} />
      <Input label="Pinned notice (top of Updates)" name="notice" value={m.notice} maxLength={160} placeholder="e.g. Office closed on 16 December"
        onChange={(e) => setM({ ...m, notice: e.target.value })} />
      <Textarea label='"Not allowed" reply' name="not_allowed" value={m.not_allowed} maxLength={240} onChange={(e) => setM({ ...m, not_allowed: e.target.value })}
        hint="Shown when the answer is in a document this role may not read. The content itself is never shown." />
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <div className="flex items-center justify-end gap-3">
        {save.isSuccess && <span className="text-sm text-green-700">Saved</span>}
        <Button loading={save.isPending} disabled={m.greeting.trim().length < 2 || m.not_allowed.trim().length < 2 || lines.length > MAX_SUGGESTIONS}
          onClick={() => save.mutate({ roleId: role.id, messages: { ...m, suggestions: lines } })}>Save messages</Button>
      </div>
    </Card>
  )
}
