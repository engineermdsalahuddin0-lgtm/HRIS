import { Fragment } from 'react'
import type { InlinePart } from '@/onboarding-process/core/markdown'
import { parseMarkdown } from '@/onboarding-process/core/markdown'
import { cx } from '@/components/ui'

function Inline({ parts }: { parts: InlinePart[] }) {
  return <>{parts.map((p, i) => (p.bold ? <strong key={i} className="font-semibold text-slate-900">{p.text}</strong> : <Fragment key={i}>{p.text}</Fragment>))}</>
}

/** Job-post Markdown (headings, lists, bold) rendered as elements, never as raw HTML. */
export function Markdown({ source, className }: { source: string; className?: string }) {
  return (
    <div className={cx('space-y-3 text-sm leading-relaxed text-slate-700', className)}>
      {parseMarkdown(source).map((block, i) => {
        if (block.kind === 'heading') {
          return block.level === 2
            ? <h3 key={i} className="pt-2 text-base font-semibold text-slate-900"><Inline parts={block.parts} /></h3>
            : <h4 key={i} className="pt-1 font-semibold text-slate-900"><Inline parts={block.parts} /></h4>
        }
        if (block.kind === 'list') {
          return (
            <ul key={i} className="list-disc space-y-1 pl-5 marker:text-primary-500">
              {block.items.map((item, j) => <li key={j}><Inline parts={item} /></li>)}
            </ul>
          )
        }
        return <p key={i}><Inline parts={block.parts} /></p>
      })}
    </div>
  )
}
