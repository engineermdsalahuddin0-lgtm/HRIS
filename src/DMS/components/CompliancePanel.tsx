import { useState } from 'react'
import { Download } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { downloadText, toCsv } from '@/lib/payrollRuns'
import type { ComplianceClause, ComplianceProfile } from '../core/types'
import { useCompliance } from '../data/api'

const STATUS: Record<ComplianceClause['status'], { label: string; tone: 'green' | 'orange' | 'red' }> = {
  ok: { label: 'Evidence', tone: 'green' },
  stale: { label: 'Expired / review due', tone: 'orange' },
  gap: { label: 'Gap', tone: 'red' },
}

/** ISO checklist per selected standard: evidence (green), stale (amber), gap (red). Clause topics are our own words. */
export function CompliancePanel({ onOpen, onSetup }: { onOpen: (id: string) => void; onSetup?: () => void }) {
  const data = useCompliance(true)
  const [profile, setProfile] = useState<string | null>(null)
  const [onlyGaps, setOnlyGaps] = useState(false)
  if (data.isPending) return <PageLoader />
  if (data.isError) return <Alert>{errorMessage(data.error)}</Alert>
  if (data.data.length === 0) {
    return (
      <EmptyState title="No ISO standard selected">
        The checklist appears once a standard is chosen{onSetup ? <> in <button type="button" className="font-medium text-primary-700 underline" onClick={onSetup}>Setup</button></> : ''}.
      </EmptyState>
    )
  }
  const current = data.data.find((p) => p.profile === profile) ?? data.data[0]
  const count = (s: ComplianceClause['status']) => current.clauses.filter((c) => c.status === s).length
  const rows = current.clauses.filter((c) => !onlyGaps || c.status !== 'ok')

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        {data.data.map((p) => (
          <button key={p.profile} type="button" onClick={() => setProfile(p.profile)}
            className={cx('rounded-full px-3 py-1.5 text-sm ring-1 transition', p.profile === current.profile ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white text-slate-700 ring-slate-300')}>
            {p.name}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-3 gap-3">
        {(['ok', 'stale', 'gap'] as const).map((s) => (
          <Card key={s} className="p-4">
            <p className="text-xs text-slate-500">{STATUS[s].label}</p>
            <p className={cx('mt-1 text-2xl font-semibold', s === 'gap' && count(s) > 0 ? 'text-red-600' : 'text-slate-900')}>{count(s)}</p>
          </Card>
        ))}
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={onlyGaps} onChange={(e) => setOnlyGaps(e.target.checked)} className="size-4 accent-primary-600" />
          Show only what needs work
        </label>
        <Button variant="secondary" onClick={() => exportCsv(current)}><Download className="size-4" /> Export CSV</Button>
      </div>
      <p className="text-xs text-slate-500">
        Clause numbers follow edition {current.edition}; check them against the edition your auditor uses. The software keeps the evidence;
        certification is done by an outside auditor.
      </p>
      <ul className="space-y-2">
        {rows.map((c) => (
          <li key={c.clause} className="rounded-xl bg-white p-3 shadow-sm ring-1 ring-slate-200">
            <div className="flex flex-wrap items-center gap-2">
              <span className="w-14 font-mono text-sm font-semibold text-slate-900">{c.clause}</span>
              <span className="flex-1 text-sm text-slate-800">{c.topic}</span>
              <Badge tone={STATUS[c.status].tone}>{STATUS[c.status].label}</Badge>
            </div>
            {c.documents.length > 0 ? (
              <ul className="mt-2 flex flex-wrap gap-2 pl-16">
                {c.documents.map((d) => (
                  <li key={d.id}>
                    <button type="button" onClick={() => onOpen(d.id)}
                      className={cx('rounded-lg px-2 py-1 text-xs ring-1 hover:ring-primary-300', d.stale ? 'bg-primary-50 ring-primary-200' : 'bg-slate-50 ring-slate-200')}>
                      <span className="font-mono">{d.version_name}</span> {d.title}{d.source === 'manual' ? ' (tagged)' : ''}
                    </button>
                  </li>
                ))}
              </ul>
            ) : c.types && c.types.length > 0 && (
              <p className="mt-1 pl-16 text-xs text-slate-500">Upload: {c.types.join(' or ')}</p>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

function exportCsv(p: ComplianceProfile) {
  downloadText(`${p.profile}-checklist-${new Date().toISOString().slice(0, 10)}.csv`,
    toCsv(['Standard', 'Clause', 'Topic', 'Status', 'Evidence'],
      p.clauses.map((c) => [p.name, c.clause, c.topic, STATUS[c.status].label, c.documents.map((d) => d.version_name).join(' ')])))
}
