// The (?) next to an explained number: shows the formula, the same formula with
// the real numbers, and where the rule comes from. Opens on hover or focus, and
// on tap for touch screens.
import { useId, useState } from 'react'
import { CircleHelp, ShieldCheck, TriangleAlert } from 'lucide-react'
import type { Explanation } from '@/onboarding-process/core/explain'
import { useStatutoryReferences } from '@/lib/statutory'
import { SourceBadge } from '@/components/references'
import { cx } from '@/components/ui'

export function InfoTip({ explanation, align = 'left' }: { explanation: Explanation; align?: 'left' | 'right' }) {
  const [open, setOpen] = useState(false)
  const id = useId()
  const references = useStatutoryReferences()
  const items = (references.data ?? []).filter((r) => explanation.references.includes(r.key))
  return (
    <span className="relative inline-flex" onMouseEnter={() => setOpen(true)} onMouseLeave={() => setOpen(false)}>
      <button type="button" aria-label={`How "${explanation.title}" is worked out`} aria-expanded={open} aria-describedby={open ? id : undefined}
        onClick={() => setOpen(!open)} onFocus={() => setOpen(true)} onBlur={() => setOpen(false)}
        className="rounded-full text-slate-400 transition hover:text-primary-600 focus-visible:text-primary-600 focus-visible:outline-2 focus-visible:outline-primary-500">
        <CircleHelp className="size-4" />
      </button>
      {open && (
        <span id={id} role="tooltip"
          className={cx('absolute top-6 z-30 w-72 max-w-[calc(100vw-2rem)] rounded-xl bg-white p-3 text-left text-xs font-normal normal-case tracking-normal text-slate-700 shadow-xl ring-1 ring-slate-200',
            align === 'right' ? 'right-0' : 'left-0')}>
          <span className="block text-sm font-semibold text-slate-900">{explanation.title}</span>
          <span className="mt-1.5 block text-slate-500">Formula</span>
          <span className="block font-medium">{explanation.formula}</span>
          <span className="mt-1.5 block text-slate-500">With this month's numbers</span>
          <span className="block font-mono text-[11px] text-primary-800">{explanation.working}</span>
          {items.length > 0 && (
            <span className="mt-2 block space-y-1.5 border-t border-slate-100 pt-2">
              {items.map((reference) => (
                <span key={reference.key} className="block">
                  <span className="flex flex-wrap items-center gap-1.5">
                    <SourceBadge category={reference.category} />
                    <span className="font-medium text-slate-800">{reference.title}</span>
                    {reference.status === 'verified'
                      ? <ShieldCheck className="size-3.5 text-green-600" aria-label="Verified" />
                      : <TriangleAlert className="size-3.5 text-amber-600" aria-label="Company must confirm" />}
                  </span>
                  <span className="mt-0.5 block text-slate-600">{reference.summary}</span>
                </span>
              ))}
            </span>
          )}
        </span>
      )}
    </span>
  )
}
