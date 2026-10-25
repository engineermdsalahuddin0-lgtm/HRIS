import { useMemo, useState } from 'react'
import { errorMessage } from '@/lib/identity'
import type { ReferenceCategory } from '@/lib/statutory'
import { useStatutoryReferences } from '@/lib/statutory'
import { ReferenceCard, SOURCE_STYLE } from '@/components/references'
import { Alert, Card, PageLoader, cx } from '@/components/ui'
import { PageHeader } from '@/components/kit'

const AREA_LABEL: Record<string, string> = {
  tax: 'Income tax', pf: 'Provident fund', gratuity: 'Gratuity', overtime: 'Overtime', attendance: 'Attendance & deductions',
  salary: 'Salary', performance: 'Performance', workforce: 'Workforce planning',
}

/** The library behind every calculation: laws (with section and source) and company rules. */
export default function ReferencesPage() {
  const references = useStatutoryReferences()
  const [category, setCategory] = useState<ReferenceCategory | 'all'>('all')
  const groups = useMemo(() => {
    const map = new Map<string, NonNullable<typeof references.data>>()
    for (const ref of references.data ?? []) {
      if (category !== 'all' && ref.category !== category) continue
      map.set(ref.area, [...(map.get(ref.area) ?? []), ref])
    }
    return [...map.entries()]
  }, [references.data, category])
  if (references.isPending) return <PageLoader />
  if (references.isError) return <Alert>{errorMessage(references.error)}</Alert>
  const toConfirm = references.data.filter((r) => r.status === 'needs_confirmation').length
  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader title="Law & policy references"
        description="Where every payroll calculation comes from. Each payslip line links to one of these." />
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {(Object.keys(SOURCE_STYLE) as ReferenceCategory[]).map((key) => (
          <Card key={key} className="p-4">
            <p className="text-xs text-slate-500">{SOURCE_STYLE[key].label}</p>
            <p className="mt-1 text-2xl font-semibold">{references.data.filter((r) => r.category === key).length}</p>
          </Card>
        ))}
      </div>
      {toConfirm > 0 && (
        <Alert tone="info">{toConfirm} rule(s) are marked "Company must confirm": check them with your legal or tax adviser before relying on them.</Alert>
      )}
      <div className="flex flex-wrap gap-2" role="tablist" aria-label="Filter by source">
        {(['all', 'law', 'company_policy', 'company_setting', 'industry_practice'] as const).map((key) => (
          <button key={key} role="tab" aria-selected={category === key} onClick={() => setCategory(key)}
            className={cx('rounded-full px-3 py-1.5 text-sm ring-1',
              category === key ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-600 ring-slate-200 hover:bg-slate-50')}>
            {key === 'all' ? 'All' : SOURCE_STYLE[key].label}
          </button>
        ))}
      </div>
      {groups.map(([area, items]) => (
        <section key={area} className="space-y-3">
          <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">{AREA_LABEL[area] ?? area}</h3>
          <div className="grid gap-3 md:grid-cols-2">
            {items.map((ref) => <ReferenceCard key={ref.key} reference={ref} />)}
          </div>
        </section>
      ))}
    </div>
  )
}
