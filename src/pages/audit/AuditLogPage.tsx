import { Fragment, useState } from 'react'
import { ChevronDown, ChevronLeft, ChevronRight, ChevronUp, Lock } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import type { AuditFilters, AuditRow } from '@/lib/hr'
import { useAuditFilterOptions, useAuditLogs } from '@/lib/hr'
import { Alert, Badge, Button, Card, EmptyState, Input, Spinner } from '@/components/ui'
import { PageHeader, Select, Table, td, th } from '@/components/kit'

const PAGE_SIZE = 50
const HIDDEN_KEYS = new Set(['created_at', 'updated_at', 'created_by', 'updated_by', 'org_id'])

function actionTone(action: string) {
  if (action === 'insert' || action.endsWith('created') || action.endsWith('granted')) return 'green' as const
  if (action === 'delete' || action.includes('deactivated') || action.includes('revoked')) return 'red' as const
  if (action === 'update') return 'orange' as const
  return 'slate' as const
}

/** Shows only what changed between old and new values. */
function Diff({ row }: { row: AuditRow }) {
  const o = row.old_value ?? {}
  const n = row.new_value ?? {}
  const keys = [...new Set([...Object.keys(o), ...Object.keys(n)])].filter(
    (k) => !HIDDEN_KEYS.has(k) && JSON.stringify(o[k]) !== JSON.stringify(n[k]),
  )
  const show = (v: unknown) => (v === null || v === undefined ? '—' : typeof v === 'object' ? JSON.stringify(v) : String(v))
  return (
    <div className="space-y-2">
      {keys.length === 0 ? (
        <p className="text-sm text-slate-500">No field changes recorded.</p>
      ) : (
        <table className="w-full text-xs">
          <thead className="text-left text-slate-500">
            <tr><th className="py-1 pr-4 font-medium">Field</th><th className="py-1 pr-4 font-medium">Old</th><th className="py-1 font-medium">New</th></tr>
          </thead>
          <tbody>
            {keys.map((k) => (
              <tr key={k} className="align-top">
                <td className="py-1 pr-4 font-mono text-slate-600">{k}</td>
                <td className="max-w-xs break-all py-1 pr-4 text-red-700">{row.old_value ? show(o[k]) : ''}</td>
                <td className="max-w-xs break-all py-1 text-green-700">{show(n[k])}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p className="text-xs text-slate-400">
        Record {row.entity_id ?? '—'} · IP {row.ip ?? '—'} {row.user_agent ? `· ${row.user_agent.slice(0, 80)}` : ''}
      </p>
    </div>
  )
}

export default function AuditLogPage() {
  const [filters, setFilters] = useState<AuditFilters>({ actor: '', action: '', entity: '', from: '', to: '', page: 0 })
  const [expanded, setExpanded] = useState<string | null>(null)
  const set = (patch: Partial<AuditFilters>) => setFilters((f) => ({ ...f, page: 0, ...patch }))
  const logs = useAuditLogs(filters, PAGE_SIZE)
  const options = useAuditFilterOptions()
  const total = logs.data?.total ?? 0

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader
        title="Audit log"
        description="Who changed what, when, in this organization. Read-only: nobody can edit or delete these rows. Kept at least 3 years."
        actions={<Badge><Lock className="mr-1 inline size-3" />Append-only</Badge>}
      />

      <Card className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-5">
        <Select aria-label="User" value={filters.actor} onChange={(e) => set({ actor: e.target.value })}
          options={(options.data?.actors ?? []).map((a) => ({ value: a.id, label: a.name }))} placeholder="All users" />
        <Select aria-label="Action" value={filters.action} onChange={(e) => set({ action: e.target.value })}
          options={(options.data?.actions ?? []).sort().map((a) => ({ value: a, label: a }))} placeholder="All actions" />
        <Select aria-label="Record type" value={filters.entity} onChange={(e) => set({ entity: e.target.value })}
          options={(options.data?.entities ?? []).sort().map((a) => ({ value: a, label: a.replace(/_/g, ' ') }))} placeholder="All record types" />
        <Input label="From" type="date" name="from" value={filters.from} onChange={(e) => set({ from: e.target.value })} />
        <Input label="To" type="date" name="to" value={filters.to} onChange={(e) => set({ to: e.target.value })} />
      </Card>

      {logs.isError ? (
        <Alert>{errorMessage(logs.error)}</Alert>
      ) : logs.isPending ? (
        <div className="flex justify-center py-16 text-primary-600"><Spinner className="size-8" /></div>
      ) : logs.data.rows.length === 0 ? (
        <EmptyState title="No audit entries match these filters" />
      ) : (
        <>
          <Table
            minWidth={760}
            head={
              <tr>
                <th className={th}>When</th>
                <th className={th}>User</th>
                <th className={th}>Action</th>
                <th className={th}>Record</th>
                <th className={th} />
              </tr>
            }
          >
            {logs.data.rows.map((r) => (
              <Fragment key={r.id}>
                <tr className="hover:bg-slate-50">
                  <td className={`${td} whitespace-nowrap`}>{formatDateTime(r.created_at)}</td>
                  <td className={td}>{r.actor_name ?? <span className="text-slate-400">System</span>}</td>
                  <td className={td}><Badge tone={actionTone(r.action)}>{r.action}</Badge></td>
                  <td className={td}>{r.entity.replace(/_/g, ' ')}</td>
                  <td className="px-4 py-3 text-right">
                    <button
                      onClick={() => setExpanded(expanded === r.id ? null : r.id)}
                      className="rounded-lg p-1.5 text-slate-400 hover:bg-slate-100 hover:text-slate-700"
                      aria-expanded={expanded === r.id}
                      aria-label="Show details"
                    >
                      {expanded === r.id ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}
                    </button>
                  </td>
                </tr>
                {expanded === r.id && (
                  <tr>
                    <td colSpan={5} className="bg-slate-50 px-4 py-3"><Diff row={r} /></td>
                  </tr>
                )}
              </Fragment>
            ))}
          </Table>
          <div className="flex items-center justify-between text-sm text-slate-600">
            <span>{filters.page * PAGE_SIZE + 1}–{Math.min(total, (filters.page + 1) * PAGE_SIZE)} of {total}</span>
            <div className="flex gap-2">
              <Button variant="secondary" disabled={filters.page === 0} onClick={() => setFilters((f) => ({ ...f, page: f.page - 1 }))} aria-label="Previous page"><ChevronLeft className="size-4" /></Button>
              <Button variant="secondary" disabled={(filters.page + 1) * PAGE_SIZE >= total} onClick={() => setFilters((f) => ({ ...f, page: f.page + 1 }))} aria-label="Next page"><ChevronRight className="size-4" /></Button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
