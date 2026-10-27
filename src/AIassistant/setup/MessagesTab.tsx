import { useEffect, useState } from 'react'
import { Button, Card, Input, cx } from '@/components/ui'
import { Textarea } from '@/components/kit'
import { ROLES } from '../core/catalog'
import type { RoleKey, RoleMessages } from '../core/types'
import { useAssistantStore } from '../data/store'

const MAX_SUGGESTIONS = 6

/** What each role sees first: greeting, suggested questions, a pinned notice, the "not allowed" reply. */
export function MessagesTab() {
  const setup = useAssistantStore((s) => s.setup)
  const update = useAssistantStore((s) => s.update)
  const [role, setRole] = useState<RoleKey>('employee')
  const [draft, setDraft] = useState<RoleMessages>(setup.messages[role])
  const [suggestions, setSuggestions] = useState(draft.suggestions.join('\n'))
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    setDraft(setup.messages[role])
    setSuggestions(setup.messages[role].suggestions.join('\n'))
    setSaved(false)
  }, [role]) // eslint-disable-line react-hooks/exhaustive-deps

  const lines = suggestions.split('\n').map((s) => s.trim()).filter(Boolean)
  const save = () => {
    update({ messages: { ...setup.messages, [role]: { ...draft, suggestions: lines.slice(0, MAX_SUGGESTIONS) } } })
    setSaved(true)
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
      <Card className="h-fit p-2">
        <ul className="space-y-1">
          {ROLES.map((r) => (
            <li key={r.key}>
              <button type="button" onClick={() => setRole(r.key)}
                className={cx('w-full rounded-xl px-3 py-2.5 text-left text-sm font-medium',
                  r.key === role ? 'bg-primary-50 text-primary-700' : 'text-slate-700 hover:bg-slate-50')}>
                {r.label}
              </button>
            </li>
          ))}
        </ul>
      </Card>
      <Card className="space-y-5">
        <Textarea label="Greeting" name="greeting" value={draft.greeting} maxLength={240}
          onChange={(e) => { setDraft({ ...draft, greeting: e.target.value }); setSaved(false) }}
          hint='Starts with "Hi!" to add the person’s first name.' />
        <Textarea label="Suggested questions" name="suggestions" rows={4} value={suggestions}
          onChange={(e) => { setSuggestions(e.target.value); setSaved(false) }}
          hint={`One per line, up to ${MAX_SUGGESTIONS}. Bangla is fine.`}
          error={lines.length > MAX_SUGGESTIONS ? `Only the first ${MAX_SUGGESTIONS} are shown.` : undefined} />
        <Input label="Pinned notice (top of Updates)" name="notice" value={draft.notice} maxLength={160}
          placeholder="e.g. Office closed on 16 December"
          onChange={(e) => { setDraft({ ...draft, notice: e.target.value }); setSaved(false) }} />
        <Textarea label='"Not allowed" reply' name="not_allowed" value={draft.notAllowed} maxLength={240}
          onChange={(e) => { setDraft({ ...draft, notAllowed: e.target.value }); setSaved(false) }}
          hint="Shown when the answer is in a document this role may not read. The content itself is never shown." />
        <div className="flex items-center justify-end gap-3">
          {saved && <span className="text-sm text-green-700">Saved</span>}
          <Button disabled={!draft.greeting.trim() || !draft.notAllowed.trim()} onClick={save}>Save messages</Button>
        </div>
      </Card>
    </div>
  )
}
