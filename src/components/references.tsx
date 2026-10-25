// Shows where a calculation comes from: the law (with section and source),
// a company policy, or a company setting. Used next to every explained number.
import { useState } from 'react'
import { BookOpen, ExternalLink, Factory, Scale, ShieldCheck, SlidersHorizontal, TriangleAlert } from 'lucide-react'
import type { ReferenceCategory, StatutoryReference } from '@/lib/statutory'
import { useStatutoryReferences } from '@/lib/statutory'
import { formatDate } from '@/lib/options'
import { cx } from '@/components/ui'

export const SOURCE_STYLE: Record<ReferenceCategory, { label: string; labelBn: string; className: string; icon: typeof Scale }> = {
  law:             { label: 'Law',            labelBn: 'আইন',            className: 'bg-sky-50 text-sky-700 ring-sky-200',           icon: Scale },
  company_policy:  { label: 'Company policy', labelBn: 'প্রতিষ্ঠানের নীতি', className: 'bg-primary-50 text-primary-700 ring-primary-200', icon: BookOpen },
  company_setting: { label: 'Company setting', labelBn: 'প্রতিষ্ঠানের সেটিং', className: 'bg-slate-100 text-slate-700 ring-slate-200',   icon: SlidersHorizontal },
  industry_practice: { label: 'Industry practice', labelBn: 'প্রচলিত পদ্ধতি', className: 'bg-violet-50 text-violet-700 ring-violet-200', icon: Factory },
}

export function SourceBadge({ category, className }: { category: ReferenceCategory; className?: string }) {
  const style = SOURCE_STYLE[category]
  const Icon = style.icon
  return (
    <span className={cx('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ring-1', style.className, className)}>
      <Icon className="size-3" aria-hidden />{style.label}
    </span>
  )
}

/** Full card for one reference: law, section, summary (English + Bangla), source and verification. */
export function ReferenceCard({ reference, compact }: { reference: StatutoryReference; compact?: boolean }) {
  return (
    <div className={cx('rounded-xl bg-white text-sm ring-1 ring-slate-200', compact ? 'p-3' : 'p-4')}>
      <div className="flex flex-wrap items-center gap-2">
        <SourceBadge category={reference.category} />
        <p className="font-medium text-slate-900">{reference.title}</p>
        {reference.status === 'verified'
          ? <span className="inline-flex items-center gap-1 text-[11px] text-green-700"><ShieldCheck className="size-3.5" />Verified{reference.verified_on ? ` ${formatDate(reference.verified_on)}` : ''}</span>
          : <span className="inline-flex items-center gap-1 text-[11px] text-amber-700"><TriangleAlert className="size-3.5" />Company must confirm</span>}
      </div>
      {(reference.law_name || reference.section) && (
        <p className="mt-1 text-xs text-slate-600">
          {reference.law_name}{reference.section ? <span className="font-medium"> · {reference.section}</span> : null}
        </p>
      )}
      <p className="mt-2 text-slate-700">{reference.summary}</p>
      {reference.summary_bn && <p className="mt-1 text-slate-500" lang="bn">{reference.summary_bn}</p>}
      {reference.source_url && (
        <a href={reference.source_url} target="_blank" rel="noopener noreferrer"
          className="mt-2 inline-flex items-center gap-1 text-xs font-medium text-primary-700 hover:underline">
          Source <ExternalLink className="size-3" />
        </a>
      )}
    </div>
  )
}

/** Small clickable chips for reference keys; a chip opens its card underneath. */
export function ReferenceChips({ keys, className }: { keys: string[]; className?: string }) {
  const references = useStatutoryReferences()
  const [openKey, setOpenKey] = useState<string | null>(null)
  if (!keys.length || !references.data) return null
  const byKey = new Map(references.data.map((r) => [r.key, r]))
  const items = keys.map((key) => byKey.get(key)).filter((r): r is StatutoryReference => !!r)
  const open = items.find((r) => r.key === openKey)
  return (
    <div className={className}>
      <div className="flex flex-wrap gap-1.5">
        {items.map((reference) => {
          const style = SOURCE_STYLE[reference.category]
          const Icon = style.icon
          return (
            <button key={reference.key} type="button" aria-expanded={openKey === reference.key}
              onClick={() => setOpenKey(openKey === reference.key ? null : reference.key)}
              className={cx('inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 transition hover:brightness-95',
                style.className, openKey === reference.key && 'ring-2')}>
              <Icon className="size-3" aria-hidden />
              {reference.section && reference.category === 'law' ? `${reference.section}` : reference.title}
            </button>
          )
        })}
      </div>
      {open && <div className="mt-2"><ReferenceCard reference={open} compact /></div>}
    </div>
  )
}
