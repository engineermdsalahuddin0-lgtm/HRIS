import { useEffect, useRef, useState } from 'react'
import { Sparkles, X } from 'lucide-react'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { cx } from '@/components/ui'
import type { UpdateItem } from '../core/types'
import { useMyConfig, useMyUpdates } from '../data/api'
import { ChatView } from './ChatView'
import { UpdatesView } from './UpdatesView'

type Tab = 'updates' | 'ask'

/**
 * Floating assistant on every signed-in page (mounted once in AppLayout). Hidden when the
 * company or the user's role has it switched off. Alt + A opens and closes it.
 * Config and Updates come from the database (AI3); Updates never need an AI key.
 */
export function AssistantWidget() {
  const ctx = useMyContext()
  const isPreview = useIsPreview()
  const live = !!ctx.organization && !isPreview
  const config = useMyConfig(live)
  const updates = useMyUpdates(live && !!config.data?.enabled)
  const [open, setOpen] = useState(false)
  const [tab, setTab] = useState<Tab>('updates')
  const buttonRef = useRef<HTMLButtonElement>(null)
  const items: UpdateItem[] = (updates.data ?? []).map((u) => ({ ...u, topicKey: u.topic }))
  const actionCount = items.filter((u) => u.tone === 'action').length

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.altKey && e.key.toLowerCase() === 'a') { e.preventDefault(); setOpen((o) => !o) }
      if (e.key === 'Escape' && open && !document.querySelector('dialog[open]')) { setOpen(false); buttonRef.current?.focus() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])

  const c = config.data
  if (!live || !c?.enabled) return null
  const firstName = ctx.user?.full_name.split(' ')[0]
  const messages = { greeting: c.greeting, suggestions: c.suggestions, notice: c.notice, notAllowed: c.not_allowed }

  return (
    <div className="print:hidden">
      {open && (
        <section role="dialog" aria-label={c.name}
          className={cx(
            'fixed z-50 flex flex-col overflow-hidden bg-white shadow-2xl ring-1 ring-slate-200',
            'inset-0 sm:inset-auto sm:bottom-24 sm:right-5 sm:h-[min(620px,calc(100vh-8rem))] sm:w-[390px] sm:rounded-2xl',
          )}>
          <header className="flex items-center gap-2 border-b border-slate-200 px-4 py-3">
            <span className="flex size-8 items-center justify-center rounded-xl bg-primary-600 text-white"><Sparkles className="size-4" aria-hidden /></span>
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold text-slate-900">{c.name}</p>
              <p className="text-[11px] text-slate-500">The app, policies, rules and your updates</p>
            </div>
            <button type="button" onClick={() => setOpen(false)} aria-label="Close" className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100">
              <X className="size-4" />
            </button>
          </header>
          <div className="flex gap-1 border-b border-slate-200 px-3" role="tablist">
            {(['updates', 'ask'] as Tab[]).map((t) => (
              <button key={t} type="button" role="tab" aria-selected={tab === t} onClick={() => setTab(t)}
                className={cx('-mb-px flex items-center gap-1.5 border-b-2 px-3 py-2 text-sm font-medium',
                  tab === t ? 'border-primary-600 text-primary-700' : 'border-transparent text-slate-500 hover:text-slate-800')}>
                {t === 'updates' ? 'Updates' : 'Ask'}
                {t === 'updates' && items.length > 0 && <span className="rounded-full bg-slate-100 px-1.5 text-xs text-slate-600">{items.length}</span>}
              </button>
            ))}
          </div>
          {tab === 'updates' ? (
            <div className="min-h-0 flex-1 overflow-y-auto">
              <UpdatesView updates={items} messages={messages} onNavigate={() => setOpen(false)} />
            </div>
          ) : (
            <div className="flex min-h-0 flex-1 flex-col">
              {c.can_ask ? <ChatView role="employee" firstName={firstName} /> : (
                <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
                  <Sparkles className="size-8 text-slate-300" aria-hidden />
                  <p className="font-medium text-slate-700">Ask is not ready yet</p>
                  <p className="text-sm text-slate-500">{c.ask_blocked_reason}</p>
                </div>
              )}
            </div>
          )}
        </section>
      )}
      <button ref={buttonRef} type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open}
        aria-label={open ? `Close ${c.name}` : `Open ${c.name} (Alt + A)`} title={`${c.name} (Alt + A)`}
        className={cx(
          'fixed bottom-5 right-5 z-50 flex size-14 items-center justify-center rounded-full bg-primary-600 text-white shadow-lg',
          'transition hover:bg-primary-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-600',
          open && 'max-sm:hidden',
        )}>
        {open ? <X className="size-6" /> : <Sparkles className="size-6" />}
        {!open && actionCount > 0 && (
          <span className="absolute -right-0.5 -top-0.5 flex size-5 items-center justify-center rounded-full bg-red-500 text-[11px] font-semibold ring-2 ring-white">{actionCount}</span>
        )}
      </button>
    </div>
  )
}
