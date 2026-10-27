import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { ExternalLink, MousePointerClick, SendHorizontal, ThumbsDown } from 'lucide-react'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import { cx } from '@/components/ui'
import type { AskResult, LiveCitation } from '../data/api'
import { askLive, rpc, useHistory } from '../data/api'

interface Line { id: string; from: 'user' | 'ai'; text: string; result?: AskResult; shown?: number }

const KIND_TONE: Partial<Record<AskResult['kind'], string>> = {
  not_allowed: 'bg-amber-50 ring-amber-200',
  personal_data: 'bg-sky-50 ring-sky-200',
  dont_know: 'bg-slate-50 ring-slate-200',
  refused: 'bg-slate-50 ring-slate-200',
}

const locationLabel = (c: LiveCitation) => (c.source === 'guide' ? c.route ?? '' : /^\$/.test(c.location) ? c.location : `p.${c.location}`)

/**
 * The Ask tab on the real backend: the question goes to the Edge Function with the current page; the answer
 * comes back whole and is revealed word by word. Citations open the source (signed URL) or the guide page;
 * "Show me" opens the page and highlights the control. previewRoleId = Test as role (nothing recorded).
 */
export function LiveChat({ greeting, suggestions, left: initialLeft, firstName, previewRoleId, debug = false, pending, onPendingDone, onHighlight }: {
  greeting: string; suggestions: string[]; left: number | null; firstName?: string; previewRoleId?: string; debug?: boolean
  pending?: { question: string; errorText?: string } | null; onPendingDone?: () => void
  onHighlight?: (h: NonNullable<AskResult['highlight']>) => void
}) {
  const location = useLocation()
  const navigate = useNavigate()
  const history = useHistory(!previewRoleId)
  const [lines, setLines] = useState<Line[]>([])
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [busy, setBusy] = useState(false)
  const [left, setLeft] = useState(initialLeft)
  const [error, setError] = useState<string | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const loaded = useRef(false)

  // Earlier answers of my latest conversation (own only, 90 days).
  useEffect(() => {
    if (loaded.current || !history.data) return
    loaded.current = true
    setConversationId(history.data.conversation_id)
    setLines(history.data.messages.slice(-12).map((m, i) => ({
      id: `h${i}`, from: m.sender, text: m.content,
      result: m.sender === 'ai' ? { kind: (m.kind ?? 'answer') as AskResult['kind'], text: m.content, citations: m.citations ?? [], links: [], highlight: null } : undefined,
    })))
  }, [history.data])
  useEffect(() => { listRef.current?.scrollTo({ top: listRef.current.scrollHeight }) }, [lines])

  // Reveal the newest answer a few words at a time.
  const revealing = lines.find((l) => l.from === 'ai' && l.shown !== undefined && l.shown < l.text.length)
  useEffect(() => {
    if (!revealing) return
    const t = setTimeout(() => setLines((prev) => prev.map((l) => (l.id === revealing.id ? { ...l, shown: Math.min(l.text.length, (l.shown ?? 0) + 24) } : l))), 30)
    return () => clearTimeout(t)
  }, [revealing])

  const ask = async (question: string, errorText?: string) => {
    const q = question.trim()
    if (q.length < 2 || busy || left === 0) return
    setBusy(true)
    setError(null)
    setDraft('')
    const id = String(Date.now())
    setLines((prev) => [...prev, { id: `${id}u`, from: 'user', text: errorText ? `${q}\n“${errorText}”` : q }])
    try {
      const r = await askLive({ question: q, route: location.pathname, conversation_id: previewRoleId ? null : conversationId, error_text: errorText, preview_role_id: previewRoleId })
      if (r.conversation_id) setConversationId(r.conversation_id)
      if (r.left !== undefined) setLeft(r.left)
      setLines((prev) => [...prev, { id, from: 'ai', text: r.text, result: r, shown: 0 }])
    } catch (e) {
      setError(errorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    if (!pending) return
    void ask(pending.question, pending.errorText)
    onPendingDone?.()
  }, [pending]) // eslint-disable-line react-hooks/exhaustive-deps

  const openCitation = async (c: LiveCitation) => {
    if (c.source === 'guide' && c.route) { navigate(c.route); return }
    if (!c.resource_id) return
    try {
      const path = await rpc<string | null>('assistant_resource_path', { p_resource_id: c.resource_id })
      if (!path) throw new Error('You cannot open this document')
      const { data, error: e } = await supabase.storage.from('assistant-resources').createSignedUrl(path, 300)
      if (e || !data) throw e ?? new Error('The file could not be opened')
      const page = /^\d+$/.test(c.location) ? `#page=${c.location}` : ''
      window.open(data.signedUrl + page, '_blank', 'noopener')
    } catch (e) {
      setError(errorMessage(e))
    }
  }

  const greet = greeting.replace(/^Hi!/, firstName ? `Hi ${firstName}!` : 'Hi!')

  return (
    <div className="flex h-full min-h-0 flex-col">
      <div ref={listRef} className="min-h-0 flex-1 space-y-3 overflow-y-auto p-4" aria-live="polite">
        <div className="rounded-2xl rounded-tl-sm bg-primary-50 p-3 text-sm text-primary-900">{greet}</div>
        {lines.length === 0 && suggestions.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {suggestions.map((s) => (
              <button key={s} type="button" onClick={() => void ask(s)}
                className="rounded-full bg-white px-3 py-1.5 text-left text-xs text-slate-700 ring-1 ring-slate-300 hover:bg-slate-50">{s}</button>
            ))}
          </div>
        )}
        {lines.map((l) => l.from === 'user' ? (
          <div key={l.id} className="ml-8 whitespace-pre-line rounded-2xl rounded-tr-sm bg-primary-600 p-3 text-sm text-white">{l.text}</div>
        ) : (
          <div key={l.id} className={cx('mr-4 space-y-2 rounded-2xl rounded-tl-sm p-3 text-sm ring-1', KIND_TONE[l.result!.kind] ?? 'bg-white ring-slate-200')}>
            <p className="whitespace-pre-line text-slate-800">{l.shown === undefined ? l.text : l.text.slice(0, l.shown)}</p>
            {(l.shown === undefined || l.shown >= l.text.length) && (
              <>
                {l.result!.citations.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {l.result!.citations.map((c) => (
                      <button key={c.n} type="button" onClick={() => void openCitation(c)}
                        className="rounded-lg bg-slate-100 px-2 py-1 text-left text-xs text-slate-700 hover:bg-primary-50 hover:text-primary-700">
                        [{c.n}] {c.name}{locationLabel(c) && ` · ${locationLabel(c)}`}
                      </button>
                    ))}
                  </div>
                )}
                {(l.result!.links.length > 0 || l.result!.highlight) && (
                  <div className="flex flex-wrap gap-1.5">
                    {l.result!.links.map((k) => (
                      <button key={k.route} type="button" onClick={() => navigate(k.route)}
                        className="inline-flex items-center gap-1 rounded-lg bg-primary-50 px-2 py-1 text-xs font-medium text-primary-700 hover:bg-primary-100">
                        <ExternalLink className="size-3" aria-hidden /> Open {k.title}
                      </button>
                    ))}
                    {l.result!.highlight && onHighlight && (
                      <button type="button" onClick={() => onHighlight(l.result!.highlight!)}
                        className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-2 py-1 text-xs font-medium text-white hover:bg-primary-700">
                        <MousePointerClick className="size-3" aria-hidden /> Show me
                      </button>
                    )}
                  </div>
                )}
                {debug && <p className="border-t border-slate-200 pt-2 text-xs text-slate-500">Result: <b>{l.result!.kind.replace('_', ' ')}</b>
                  {l.result!.usedTopics?.length ? ` · topics: ${l.result!.usedTopics.join(', ')}` : ''}</p>}
                {!debug && l.result!.log_id && (
                  <button type="button" title="Not helpful" aria-label="Not helpful"
                    onClick={() => { void rpc('assistant_feedback', { p_log_id: l.result!.log_id, p_helpful: false }); setLines((prev) => prev.map((x) => (x.id === l.id ? { ...x, result: { ...x.result!, log_id: undefined } } : x))) }}
                    className="rounded p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-700"><ThumbsDown className="size-3.5" /></button>
                )}
              </>
            )}
          </div>
        ))}
        {busy && <div className="mr-4 w-16 animate-pulse rounded-2xl bg-slate-100 p-3 text-center text-slate-400">…</div>}
        {error && <p className="rounded-xl bg-red-50 p-3 text-sm text-red-700">{error}</p>}
      </div>
      <form className="border-t border-slate-200 p-3" onSubmit={(e) => { e.preventDefault(); void ask(draft) }}>
        <div className="flex items-end gap-2">
          <label htmlFor={`live-ask-${previewRoleId ?? 'me'}`} className="sr-only">Your question</label>
          <textarea id={`live-ask-${previewRoleId ?? 'me'}`} rows={1} value={draft} disabled={left === 0} maxLength={2000}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void ask(draft) } }}
            placeholder={left === 0 ? 'Daily question limit reached' : 'Ask about a page, a policy… / প্রশ্ন লিখুন…'}
            className="max-h-28 min-h-10 flex-1 resize-none rounded-xl border border-slate-300 px-3 py-2 text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 disabled:bg-slate-50" />
          <button type="submit" disabled={draft.trim().length < 2 || busy || left === 0} aria-label="Send"
            className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50">
            <SendHorizontal className="size-4" />
          </button>
        </div>
        <p className="mt-1.5 text-[11px] leading-snug text-slate-400">
          Answers come from the app guide and company documents only. Check important details with HR.
          {left != null && !previewRoleId && <> · {left} questions left today</>}
        </p>
      </form>
    </div>
  )
}
