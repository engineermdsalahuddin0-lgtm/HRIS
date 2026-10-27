import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, PageLoader } from '@/components/ui'
import { Modal, Table, Tabs, td, th } from '@/components/kit'
import { percentOf } from '../core/notices'
import type { ManagedNotice } from '../data/api'
import { useReceipts, useRemind } from '../data/api'

type Filter = 'all' | 'read' | 'unread' | 'not_ack'

/** Who read / acknowledged a notice, and the 24-hour reminder for the rest. */
export function ReceiptsModal({ notice, onClose }: { notice: ManagedNotice | null; onClose: () => void }) {
  const receipts = useReceipts(notice?.id ?? null)
  const remind = useRemind()
  const [filter, setFilter] = useState<Filter>('all')
  const rows = receipts.data ?? []
  const read = rows.filter((r) => r.first_read_at).length
  const acked = rows.filter((r) => r.acknowledged_at).length
  const portal = rows.filter((r) => r.has_portal).length
  const shown = rows.filter((r) => filter === 'all' || (filter === 'read' ? r.first_read_at : filter === 'unread' ? !r.first_read_at : !r.acknowledged_at))
  const remindedRecently = !!notice?.last_reminded_at && Date.now() - Date.parse(notice.last_reminded_at) < 24 * 3600 * 1000

  return (
    <Modal open={!!notice} onClose={onClose} size="xl" title="Read receipts" description={notice?.title}
      footer={notice?.requires_ack && notice.shown_status === 'active' && (
        <div className="flex flex-wrap items-center gap-3">
          {remind.isSuccess && <span className="text-sm text-green-700">{remind.data.emails_queued} reminder emails queued</span>}
          {remind.isError && <span className="text-sm text-red-600">{errorMessage(remind.error)}</span>}
          <Button variant="secondary" loading={remind.isPending} disabled={remindedRecently || acked >= rows.length}
            title={remindedRecently ? 'A reminder was sent in the last 24 hours' : undefined}
            onClick={() => remind.mutate(notice.id)}>
            Email a reminder to those who have not acknowledged
          </Button>
        </div>
      )}>
      {receipts.isPending ? <PageLoader /> : receipts.isError ? <Alert>{errorMessage(receipts.error)}</Alert> : (
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-3">
            {[
              { label: 'Read', value: read, of: portal },
              ...(notice?.requires_ack ? [{ label: 'Acknowledged', value: acked, of: portal }] : []),
              { label: 'Without portal login', value: rows.length - portal, of: null },
            ].map((s) => (
              <div key={s.label} className="rounded-xl bg-slate-50 p-3">
                <p className="text-xs font-medium uppercase tracking-wide text-slate-500">{s.label}</p>
                <p className="text-xl font-semibold text-slate-900">
                  {s.value}{s.of != null && <span className="text-sm font-normal text-slate-500"> / {s.of} · {percentOf(s.value, s.of) ?? 0}%</span>}
                </p>
              </div>
            ))}
          </div>
          <Tabs<Filter> value={filter} onChange={setFilter} tabs={[
            { key: 'all', label: 'Everyone', count: rows.length },
            { key: 'read', label: 'Read', count: read },
            { key: 'unread', label: 'Not read', count: rows.length - read },
            ...(notice?.requires_ack ? [{ key: 'not_ack' as Filter, label: 'Not acknowledged', count: rows.length - acked }] : []),
          ]} />
          <Table minWidth={620} head={
            <tr><th className={th}>Employee</th><th className={th}>Department</th><th className={th}>Read</th>{notice?.requires_ack && <th className={th}>Acknowledged</th>}</tr>
          }>
            {shown.map((r) => (
              <tr key={r.employee_id}>
                <td className={td}>
                  <p className="font-medium text-slate-900">{r.full_name}</p>
                  <p className="text-xs text-slate-500">{r.card_id}{!r.has_portal && ' · no portal login'}</p>
                </td>
                <td className={td}>{r.department ?? '—'}</td>
                <td className={td}>{r.first_read_at ? formatDateTime(r.first_read_at) : <Badge>Not yet</Badge>}</td>
                {notice?.requires_ack && <td className={td}>{r.acknowledged_at ? formatDateTime(r.acknowledged_at) : <Badge tone="orange">Waiting</Badge>}</td>}
              </tr>
            ))}
          </Table>
        </div>
      )}
    </Modal>
  )
}
