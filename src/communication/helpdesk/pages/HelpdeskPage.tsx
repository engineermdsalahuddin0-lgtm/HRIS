import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { AlertTriangle, Lock, Plus } from 'lucide-react'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { can } from '../../shared/api'
import { PRIORITY_LABEL, STATUS_LABEL, statusLabel, ticketNo } from '../core/helpdesk'
import type { Scope } from '../data/api'
import { useTickets } from '../data/api'
import { HelpdeskSetup } from '../components/HelpdeskSetup'
import { TicketForm } from '../components/TicketForm'

type Tab = Scope | 'setup'

/** /helpdesk: My tickets for everyone; Assigned to me for handlers; All + Setup for helpdesk.manage. */
export default function HelpdeskPage() {
  const ctx = useMyContext()
  const manage = can(ctx, 'helpdesk.manage')
  const handle = manage || can(ctx, 'helpdesk.handle')
  const [tab, setTab] = useState<Tab>(manage ? 'all' : handle ? 'assigned' : 'mine')
  const [creating, setCreating] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const navigate = useNavigate()

  const tabs: { key: Tab; label: string }[] = [
    { key: 'mine', label: 'My tickets' },
    ...(handle ? [{ key: 'assigned' as Tab, label: 'Assigned to me' }] : []),
    ...(manage ? [{ key: 'all' as Tab, label: 'All tickets' }, { key: 'setup' as Tab, label: 'Setup' }] : []),
  ]

  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Helpdesk" description="Internal support tickets"
        actions={<Button data-tour="new-ticket" onClick={() => setCreating(true)}><Plus className="size-4" /> New ticket</Button>} />
      {message && <Alert tone="success">{message}</Alert>}
      {tabs.length > 1 && <Tabs<Tab> value={tab} onChange={setTab} tabs={tabs} />}
      {tab === 'setup' ? <HelpdeskSetup /> : <TicketTable key={tab} scope={tab} staffView={tab !== 'mine'} />}
      {creating && (
        <TicketForm orgId={ctx.organization!.id} onClose={() => setCreating(false)}
          onCreated={(id, text) => { setCreating(false); setMessage(text); navigate(`/helpdesk/${id}`) }} />
      )}
    </div>
  )
}

function TicketTable({ scope, staffView }: { scope: Scope; staffView: boolean }) {
  const list = useTickets(scope)
  const [filter, setFilter] = useState<'open' | 'done' | 'all'>('open')
  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const { kpis, tickets } = list.data
  const shown = tickets.filter((t) => filter === 'all' || (filter === 'open' ? !['resolved', 'closed'].includes(t.status) : ['resolved', 'closed'].includes(t.status)))

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        {([['Open', kpis.open], ['In progress', kpis.in_progress], ['SLA breach', kpis.sla_breach], ['My tickets', kpis.my_tickets], ['Resolved today', kpis.resolved_today]] as const).map(([label, value]) => (
          <Card key={label} className={cx('p-4', label === 'SLA breach' && value > 0 && 'ring-red-200')}>
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">{label}</p>
            <p className={cx('mt-1 text-2xl font-semibold', label === 'SLA breach' && value > 0 ? 'text-red-600' : 'text-slate-900')}>{value}</p>
          </Card>
        ))}
      </div>
      <div className="inline-flex rounded-lg bg-slate-100 p-0.5 text-sm" role="radiogroup" aria-label="Show">
        {([['open', 'Open'], ['done', 'Resolved & closed'], ['all', 'All']] as const).map(([k, l]) => (
          <button key={k} type="button" role="radio" aria-checked={filter === k} onClick={() => setFilter(k)}
            className={cx('rounded-md px-3 py-1 font-medium', filter === k ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500')}>{l}</button>
        ))}
      </div>
      {shown.length === 0 ? (
        <EmptyState title={scope === 'mine' ? 'You have no tickets here' : 'No tickets here'}>
          {scope === 'mine' && 'Something not working? Raise a ticket with “New ticket”.'}
        </EmptyState>
      ) : (
        <Table minWidth={960} head={
          <tr>
            <th className={th}>Ticket</th><th className={th}>Subject</th>{staffView && <th className={th}>Submitted by</th>}
            <th className={th}>Category</th><th className={th}>Priority</th><th className={th}>Assigned to</th>
            <th className={th}>Status</th><th className={th}>SLA due</th><th className={th}>Created</th>
          </tr>
        }>
          {shown.map((t) => {
            const open = !['resolved', 'closed'].includes(t.status)
            const breached = open && (t.response_breached || t.resolution_breached)
            return (
              <tr key={t.id} className="hover:bg-slate-50">
                <td className={cx(td, 'font-mono text-xs')}><Link to={`/helpdesk/${t.id}`} className="text-primary-700 hover:underline">{ticketNo(t.ticket_no)}</Link></td>
                <td className={cx(td, 'max-w-64')}>
                  <Link to={`/helpdesk/${t.id}`} className="block truncate font-medium text-slate-900 hover:text-primary-700">{t.subject}</Link>
                </td>
                {staffView && <td className={td}>{t.requester}</td>}
                <td className={td}>
                  <span className="inline-flex items-center gap-1">{t.confidential && <Lock className="size-3 text-slate-400" aria-label="confidential" />}{t.category}</span>
                </td>
                <td className={td}><Badge tone={PRIORITY_LABEL[t.priority].tone}>{PRIORITY_LABEL[t.priority].label}</Badge></td>
                <td className={td}>{t.assignee ?? <span className="text-slate-400">HR queue</span>}</td>
                <td className={td}><Badge tone={STATUS_LABEL[t.status].tone}>{statusLabel(t.status, staffView)}</Badge></td>
                <td className={cx(td, 'whitespace-nowrap text-xs')}>
                  {!open ? '—' : t.status === 'waiting' ? <span className="text-slate-500">Paused</span> : (
                    <span className={cx('inline-flex items-center gap-1', breached && 'font-medium text-red-600')}>
                      {breached && <AlertTriangle className="size-3.5" aria-label="SLA breached" />}
                      {formatDateTime(t.resolution_due_at)}
                    </span>
                  )}
                </td>
                <td className={cx(td, 'whitespace-nowrap text-xs')}>{formatDateTime(t.created_at)}</td>
              </tr>
            )
          })}
        </Table>
      )}
    </div>
  )
}
