import { Fragment, useRef } from 'react'
import { Bold, Heading2, Italic, Link2, List } from 'lucide-react'
import { cx } from '@/components/ui'
import { Label } from '@/components/kit'
import type { Inline } from './markup'
import { applyFormat, parseRichText } from './markup'

function InlineParts({ parts }: { parts: Inline[] }) {
  return (
    <>
      {parts.map((p, i) => {
        if (p.kind === 'link') {
          return <a key={i} href={p.href} target="_blank" rel="noopener noreferrer" className="font-medium text-primary-700 underline">{p.text}</a>
        }
        if (p.bold) return <strong key={i} className="font-semibold text-slate-900">{p.text}</strong>
        if (p.italic) return <em key={i}>{p.text}</em>
        return <Fragment key={i}>{p.text}</Fragment>
      })}
    </>
  )
}

/** Notice / ticket text rendered as elements, never as raw HTML. */
export function RichText({ source, className }: { source: string; className?: string }) {
  return (
    <div className={cx('space-y-3 break-words text-sm leading-relaxed text-slate-700', className)}>
      {parseRichText(source).map((block, i) => {
        if (block.kind === 'heading') {
          return block.level === 2
            ? <h3 key={i} className="pt-1 text-base font-semibold text-slate-900"><InlineParts parts={block.parts} /></h3>
            : <h4 key={i} className="font-semibold text-slate-900"><InlineParts parts={block.parts} /></h4>
        }
        if (block.kind === 'list') {
          return (
            <ul key={i} className="list-disc space-y-1 pl-5 marker:text-primary-500">
              {block.items.map((item, j) => <li key={j}><InlineParts parts={item} /></li>)}
            </ul>
          )
        }
        return <p key={i}><InlineParts parts={block.parts} /></p>
      })}
    </div>
  )
}

const TOOLS = [
  { action: 'bold', icon: Bold, label: 'Bold' },
  { action: 'italic', icon: Italic, label: 'Italic' },
  { action: 'list', icon: List, label: 'Bullet list' },
  { action: 'heading', icon: Heading2, label: 'Heading' },
  { action: 'link', icon: Link2, label: 'Link' },
] as const

/** Textarea with a small toolbar (bold, italic, list, heading, link) that writes the safe markdown. */
export function RichTextEditor({ id, label, value, onChange, rows = 8, required, placeholder, hint, lang }: {
  id: string; label: string; value: string; onChange: (v: string) => void; rows?: number; required?: boolean
  placeholder?: string; hint?: string; lang?: string
}) {
  const ref = useRef<HTMLTextAreaElement>(null)
  const apply = (action: (typeof TOOLS)[number]['action']) => {
    const el = ref.current
    if (!el) return
    const url = action === 'link' ? window.prompt('Link address (https://…)', 'https://') : undefined
    if (action === 'link' && !url) return
    const out = applyFormat(value, { start: el.selectionStart, end: el.selectionEnd }, action, url ?? undefined)
    onChange(out.text)
    requestAnimationFrame(() => { el.focus(); el.setSelectionRange(out.sel.start, out.sel.end) })
  }
  return (
    <div>
      <Label htmlFor={id} required={required}>{label}</Label>
      <div className="overflow-hidden rounded-xl border border-slate-300 focus-within:border-primary-500 focus-within:ring-2 focus-within:ring-primary-100">
        <div className="flex gap-1 border-b border-slate-200 bg-slate-50 px-2 py-1" role="toolbar" aria-label={`${label} formatting`}>
          {TOOLS.map(({ action, icon: Icon, label: l }) => (
            <button key={action} type="button" title={l} aria-label={l} onClick={() => apply(action)}
              className="rounded-lg p-1.5 text-slate-600 hover:bg-white hover:text-slate-900">
              <Icon className="size-4" />
            </button>
          ))}
        </div>
        <textarea ref={ref} id={id} rows={rows} value={value} lang={lang} placeholder={placeholder}
          onChange={(e) => onChange(e.target.value)}
          className="block w-full resize-y bg-white px-3.5 py-2.5 text-sm outline-none" />
      </div>
      {hint && <p className="mt-1 text-xs text-slate-500">{hint}</p>}
    </div>
  )
}
