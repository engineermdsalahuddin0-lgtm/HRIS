import { formatDate } from '@/lib/options'
import { Badge } from '@/components/ui'
import { Table, td, th } from '@/components/kit'
import { CLASSIFICATION, expiryBadge } from '../core/dms'
import type { DmsDocument } from '../core/types'

export function DocumentTable({ docs, onOpen, showFolder = true }: { docs: DmsDocument[]; onOpen: (d: DmsDocument) => void; showFolder?: boolean }) {
  return (
    <Table minWidth={760} head={
      <tr>
        <th className={th}>Document</th>
        {showFolder && <th className={th}>Folder</th>}
        <th className={th}>Department</th>
        <th className={th}>Access</th>
        <th className={th}>Expiry</th>
        <th className={th}>Updated</th>
      </tr>
    }>
      {docs.map((d) => {
        const badge = expiryBadge(d.expiry_status, d.days_left)
        return (
          <tr key={d.id} className="cursor-pointer hover:bg-slate-50" onClick={() => onOpen(d)}>
            <td className={td}>
              <button type="button" className="text-left font-medium text-slate-900 hover:text-primary-700" onClick={(e) => { e.stopPropagation(); onOpen(d) }}>
                {d.title}
              </button>
              <p className="font-mono text-xs text-slate-500">{d.version_name} · {d.type_name}</p>
            </td>
            {showFolder && <td className={td}>{d.folder}</td>}
            <td className={td}>{d.department}</td>
            <td className={td}>{CLASSIFICATION[d.classification].label}</td>
            <td className={td}>{d.has_expiry ? <span className="inline-flex flex-col gap-1">{formatDate(d.expiry_date)}<Badge tone={badge.tone}>{badge.label}</Badge></span> : '—'}</td>
            <td className={`${td} whitespace-nowrap`}>{formatDate(d.updated_at)}</td>
          </tr>
        )
      })}
    </Table>
  )
}
