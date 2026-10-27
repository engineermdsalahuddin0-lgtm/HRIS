import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Archive, CheckCircle2, Eye, Paperclip, Pencil, Pin, PinOff, Plus, Send, Users } from 'lucide-react'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDate, formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'
import { PageHeader, Table, Tabs, td, th } from '@/components/kit'
import { can } from '../../shared/api'
import { plainText } from '../../shared/markup'
import { CATEGORY_LABEL, STATUS_LABEL, percentOf } from '../core/notices'
import type { ManagedNotice, SaveResult } from '../data/api'
import { useManageNotices, useMyNotices, useNoticeAction, usePublishNotice } from '../data/api'
import { NoticeForm } from '../components/NoticeForm'
import { NoticeReader } from '../components/NoticeReader'
import { ReceiptsModal } from '../components/ReceiptsModal'

type Tab = 'mine' | 'manage'

/** /notices: everyone reads their notices; publishers (notices.manage / notices.department) also manage them. */
export default function NoticesPage() {
  const ctx = useMyContext()
  const publisher = can(ctx, 'notices.manage') || can(ctx, 'notices.department')
  const [params, setParams] = useSearchParams()
  const [tab, setTab] = useState<Tab>('mine')
  const openId = params.get('open')
  const setOpen = (id: string | null) => setParams(id ? { open: id } : {}, { replace: true })

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Notices" description="Company announcements and policy updates" />
      {publisher && (
        <Tabs<Tab> value={tab} onChange={setTab} tabs={[{ key: 'mine', label: 'For me' }, { key: 'manage', label: 'Manage' }]} />
      )}
      {tab === 'mine' || !publisher ? <MyNotices onOpen={setOpen} /> : <ManageNotices onOpen={setOpen} orgId={ctx.organization!.id} />}
      <NoticeReader id={openId} onClose={() => setOpen(null)} />
    </div>
  )
}

function MyNotices({ onOpen }: { onOpen: (id: string) => void }) {
  const list = useMyNotices()
  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  if (list.data.length === 0) return <EmptyState title="No notices for you right now" />
  return (
    <ul className="space-y-3">
      {list.data.map((n) => (
        <li key={n.id}>
          <button type="button" onClick={() => onOpen(n.id)}
            className={cx('w-full rounded-2xl bg-white p-4 text-left shadow-sm ring-1 transition hover:ring-primary-300',
              n.pinned ? 'ring-primary-200' : 'ring-slate-200')}>
            <div className="flex flex-wrap items-center gap-2">
              {!n.read && <span className="size-2 rounded-full bg-primary-500" aria-label="unread" />}
              {n.pinned && <Pin className="size-4 text-primary-600" aria-label="pinned" />}
              <Badge tone={CATEGORY_LABEL[n.category].tone}>{CATEGORY_LABEL[n.category].label}</Badge>
              {n.requires_ack && (n.acknowledged_at
                ? <span className="inline-flex items-center gap-1 text-xs text-green-700"><CheckCircle2 className="size-3.5" aria-hidden /> Acknowledged</span>
                : <Badge tone="red">Please acknowledge</Badge>)}
              {n.attachment_name && <Paperclip className="size-4 text-slate-400" aria-label="has a file" />}
              <span className="ml-auto text-xs text-slate-500">{formatDate(n.publish_at)}</span>
            </div>
            <p className={cx('mt-2 text-base text-slate-900', !n.read && 'font-semibold')}>{n.title}</p>
            {n.title_bn && <p className="text-sm text-slate-600" lang="bn">{n.title_bn}</p>}
            <p className="mt-1 line-clamp-2 text-sm text-slate-500">{plainText(n.body)}</p>
          </button>
        </li>
      ))}
    </ul>
  )
}

function ManageNotices({ onOpen, orgId }: { onOpen: (id: string) => void; orgId: string }) {
  const list = useManageNotices(true)
  const pin = useNoticeAction<{ p_id: string; p_pinned: boolean }>('set_notice_pin')
  const archive = useNoticeAction<{ p_id: string }>('archive_notice')
  const publish = usePublishNotice()
  const [editing, setEditing] = useState<ManagedNotice | 'new' | null>(null)
  const [receipts, setReceipts] = useState<ManagedNotice | null>(null)
  const [result, setResult] = useState<string | null>(null)
  const [showArchived, setShowArchived] = useState(false)

  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const { kpis, notices, can_target_all } = list.data
  const rows = notices.filter((n) => showArchived || n.shown_status !== 'archived')
  const actionError = pin.error ?? archive.error ?? publish.error

  const describe = (p: SaveResult['publish']) => {
    if (!p) return 'Saved.'
    const parts = [p.status === 'scheduled' ? 'Scheduled.' : 'Published.']
    if (p.emails_queued > 0) parts.push(`${p.emails_queued} emails queued.`)
    if (p.email_skipped) parts.push(p.email_skipped + '.')
    return parts.join(' ')
  }

  return (
    <div className="space-y-5">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {[['Total', kpis.total], ['Pinned', kpis.pinned], ['Active', kpis.active], ['This month', kpis.this_month]].map(([label, value]) => (
          <Card key={label} className="p-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">{label}</p>
            <p className="mt-1 text-2xl font-semibold text-slate-900">{value}</p>
          </Card>
        ))}
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <label className="inline-flex items-center gap-2 text-sm text-slate-600">
          <input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} className="size-4 accent-primary-600" />
          Show archived
        </label>
        <Button data-tour="new-notice" onClick={() => { setResult(null); setEditing('new') }}><Plus className="size-4" /> New notice</Button>
      </div>
      {result && <Alert tone="success">{result}</Alert>}
      {actionError && <Alert>{errorMessage(actionError)}</Alert>}

      {rows.length === 0 ? (
        <EmptyState title="No notices yet">Write the first one with “New notice”.</EmptyState>
      ) : (
        <Table minWidth={900} head={
          <tr>
            <th className={th}>Title</th><th className={th}>Category</th><th className={th}>Target</th><th className={th}>Published</th>
            <th className={th}>Expires</th><th className={th}>Status</th><th className={th}>Reach</th><th className={th} aria-label="Actions" />
          </tr>
        }>
          {rows.map((n) => {
            const status = STATUS_LABEL[n.shown_status]
            const readPct = percentOf(n.reads, n.portal)
            const editable = n.shown_status !== 'archived'
            return (
              <tr key={n.id} className={cx(n.shown_status === 'archived' && 'opacity-60')}>
                <td className={td}>
                  <div className="flex items-center gap-2">
                    {n.pinned && <Pin className="size-3.5 shrink-0 text-primary-600" aria-label="pinned" />}
                    <span className="font-medium text-slate-900">{n.title}</span>
                  </div>
                  {n.author && <p className="text-xs text-slate-500">by {n.author}</p>}
                </td>
                <td className={td}><Badge tone={CATEGORY_LABEL[n.category].tone}>{CATEGORY_LABEL[n.category].label}</Badge></td>
                <td className={cx(td, 'max-w-44 truncate')} title={n.audience_label}>{n.audience_label}</td>
                <td className={cx(td, 'whitespace-nowrap')}>{n.publish_at ? formatDateTime(n.publish_at) : '—'}</td>
                <td className={cx(td, 'whitespace-nowrap')}>{n.expires_at ? formatDate(n.expires_at) : 'Never'}</td>
                <td className={td}><Badge tone={status.tone}>{status.label}</Badge></td>
                <td className={cx(td, 'whitespace-nowrap text-xs')}>
                  {n.status === 'draft' ? '—' : (
                    <button type="button" onClick={() => setReceipts(n)} className="text-left hover:text-primary-700">
                      <span className="font-medium">{readPct ?? 0}% read</span>
                      {n.requires_ack && <span className="block">{n.acks}/{n.portal} acknowledged</span>}
                      <span className="block text-slate-500">{n.targets} people</span>
                    </button>
                  )}
                </td>
                <td className={cx(td, 'whitespace-nowrap text-right')}>
                  <div className="flex justify-end gap-1">
                    <IconButton label="Preview" icon={Eye} onClick={() => onOpen(n.id)} />
                    {editable && <IconButton label="Edit" icon={Pencil} onClick={() => { setResult(null); setEditing(n) }} />}
                    {n.status === 'draft' && <IconButton label="Publish" icon={Send} disabled={publish.isPending}
                      onClick={() => publish.mutate(n.id, { onSuccess: (r) => setResult(describe(r)) })} />}
                    {n.status !== 'draft' && <IconButton label="Read receipts" icon={Users} onClick={() => setReceipts(n)} />}
                    {editable && <IconButton label={n.pinned ? 'Unpin' : 'Pin'} icon={n.pinned ? PinOff : Pin}
                      onClick={() => pin.mutate({ p_id: n.id, p_pinned: !n.pinned })} />}
                    {editable && <IconButton label="Archive" icon={Archive}
                      onClick={() => window.confirm(`Archive “${n.title}”? Readers will no longer see it.`) && archive.mutate({ p_id: n.id })} />}
                  </div>
                </td>
              </tr>
            )
          })}
        </Table>
      )}

      {editing && (
        <NoticeForm key={editing === 'new' ? 'new' : editing.id} open notice={editing === 'new' ? null : editing}
          canTargetAll={can_target_all} myDepartment={null} orgId={orgId}
          onClose={() => setEditing(null)} onDone={(r) => { setEditing(null); setResult(describe(r.publish)) }} />
      )}
      <ReceiptsModal notice={receipts} onClose={() => setReceipts(null)} />
    </div>
  )
}

function IconButton({ label, icon: Icon, onClick, disabled }: { label: string; icon: typeof Eye; onClick: () => void; disabled?: boolean }) {
  return (
    <button type="button" title={label} aria-label={label} disabled={disabled} onClick={onClick}
      className="rounded-lg p-1.5 text-slate-500 hover:bg-slate-100 hover:text-slate-900 disabled:opacity-40">
      <Icon className="size-4" />
    </button>
  )
}
