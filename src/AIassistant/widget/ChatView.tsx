import { useEffect, useRef, useState } from 'react'
import { SendHorizontal, Sparkles } from 'lucide-react'
import { cx } from '@/components/ui'
import { answerQuestion, locationLabel } from '../core/answer'
import { topicOf } from '../core/catalog'
import type { Answer, Citation, RoleKey } from '../core/types'
import { useAssistantStore } from '../data/store'
import { useAssistantFor } from '../data/useAssistant'
import { SourceViewer } from './SourceViewer'

interface Line { id: number; from: 'user' | 'ai'; text: string; answer?: Answer; streaming?: boolean }

const KIND_TONE: Partial<Record<Answer['kind'], string>> = {
  not_allowed: 'bg-amber-50 ring-amber-200',
  personal_data: 'bg-sky-50 ring-sky-200',
  dont_know: 'bg-slate-50 ring-slate-200',
}

/**
 * The Ask tab. `debug` (Test as role) shows which topics and sources an answer used.
 * The answer is revealed word by word, the way the backend will stream it.
 */
export function ChatView({ role, debug = false, firstName }: { role: RoleKey; debug?: boolean; firstName?: string }) {
  const a = useAssistantFor(role)
  const countQuestion = useAssistantStore((s) => s.countQuestion)
  const [lines, setLines] = useState<Line[]>([])
  const [draft, setDraft] = useState('')
  const [viewing, setViewing] = useState<Citation | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)
  const busy = lines.some((l) => l.streaming)

  useEffect(() => () => { if (timer.current) clearInterval(timer.current) }, [])
  useEffect(() => { listRef.current?.scrollTo({ top: listRef.current.scrollHeight }) }, [lines])

  const ask = (question: string) => {
    const q = question.trim()
    if (!q || busy || a.left === 0) return
    if (!debug) countQuestion()
    const answer = answerQuestion(q, { setup: a.setup, role, allowed: a.allowed, updates: a.updates, messages: a.messages })
    const id = Date.now()
    setLines((prev) => [...prev, { id: id - 1, from: 'user', text: q }, { id, from: 'ai', text: '', answer, streaming: true }])
    setDraft('')
    const words = answer.text.split(/(\s+)/)
    let shown = 0
    timer.current = setInterval(() => {
      shown = Math.min(words.length, shown + 4)
      const done = shown >= words.length
      setLines((prev) => prev.map((l) => (l.id === id ? { ...l, text: words.slice(0, shown).join(''), streaming: !done } : l)))
      if (done && timer.current) clearInterval(timer.current)
    }, 35)
  }

  if (!a.canAsk) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center">
        <Sparkles className="size-8 text-slate-300" aria-hidden />
        <p className="font-medium text-slate-700">Ask is not ready yet</p>
        <p className="text-sm text-slate-500">
          {a.setup.keyStatus !== 'tested'
            ? 'The company has not connected an AI key yet. Updates still work.'
            : 'No documents are published for your role yet.'}
        </p>
      </div>
    )
  }

  const greeting = a.messages.greeting.replace(/^Hi!/, firstName ? `Hi ${firstName}!` : 'Hi!')

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div ref={listRef} className="min-h-0 flex-1 space-y-3 overflow-y-auto p-4" aria-live="polite">
        <div className="rounded-2xl rounded-tl-sm bg-primary-50 p-3 text-sm text-primary-900">{greeting}</div>
        {lines.length === 0 && a.messages.suggestions.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {a.messages.suggestions.map((s) => (
              <button key={s} type="button" onClick={() => ask(s)}
                className="rounded-full bg-white px-3 py-1.5 text-left text-xs text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50">
                {s}
              </button>
            ))}
          </div>
        )}
        {lines.map((l) =>
          l.from === 'user' ? (
            <div key={l.id} className="ml-8 rounded-2xl rounded-tr-sm bg-primary-600 p-3 text-sm text-white">{l.text}</div>
          ) : (
            <div key={l.id} className={cx('mr-4 space-y-2 rounded-2xl rounded-tl-sm p-3 text-sm ring-1', KIND_TONE[l.answer!.kind] ?? 'bg-white ring-slate-200')}>
              <p className="whitespace-pre-line text-slate-800">{l.text}{l.streaming && <span className="animate-pulse">▍</span>}</p>
              {!l.streaming && l.answer!.citations.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {l.answer!.citations.map((c) => (
                    <button key={c.n} type="button" onClick={() => setViewing(c)}
                      className="rounded-lg bg-slate-100 px-2 py-1 text-left text-xs text-slate-700 hover:bg-primary-50 hover:text-primary-700">
                      [{c.n}] {c.resourceName} · {locationLabel(c.location)}
                    </button>
                  ))}
                </div>
              )}
              {debug && !l.streaming && (
                <p className="border-t border-slate-200 pt-2 text-xs text-slate-500">
                  Result: <b>{l.answer!.kind.replace('_', ' ')}</b>
                  {l.answer!.usedTopics.length > 0 && <> · topics: {l.answer!.usedTopics.map((t) => topicOf(t)?.label).join(', ')}</>}
                </p>
              )}
            </div>
          ),
        )}
      </div>

      <form className="border-t border-slate-200 p-3" onSubmit={(e) => { e.preventDefault(); ask(draft) }}>
        <div className="flex items-end gap-2">
          <label htmlFor={`ask-${role}-${debug}`} className="sr-only">Your question</label>
          <textarea
            id={`ask-${role}-${debug}`}
            rows={1}
            value={draft}
            disabled={a.left === 0}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); ask(draft) } }}
            placeholder={a.left === 0 ? 'Daily question limit reached' : 'Type a question… / প্রশ্ন লিখুন…'}
            className="max-h-28 min-h-10 flex-1 resize-none rounded-xl border border-slate-300 px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 disabled:bg-slate-50"
          />
          <button type="submit" disabled={!draft.trim() || busy || a.left === 0} aria-label="Send"
            className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50">
            <SendHorizontal className="size-4" />
          </button>
        </div>
        <p className="mt-1.5 text-[11px] leading-snug text-slate-400">
          Answers come only from company documents. Check important details with HR.
          {a.left != null && !debug && <> · {a.left} questions left today</>}
        </p>
      </form>
      <SourceViewer citation={viewing} onClose={() => setViewing(null)} />
    </div>
  )
}
