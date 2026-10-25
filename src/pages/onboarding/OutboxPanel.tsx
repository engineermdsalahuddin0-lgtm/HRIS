// Messages of one post: what was emailed / texted, what failed and why; send now or retry.
import { useState } from 'react'
import { RefreshCw, Send } from 'lucide-react'
import type { JobPost } from '@/onboarding-process/core/types'
import { TEMPLATE_LABEL, type TemplateKey } from '@/onboarding-process/core/interview'
import { sendQueuedMessages, useNotifications, useRecruitAction } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, EmptyState, Spinner } from '@/components/ui'
import { Table, td, th } from '@/components/kit'

const TONE = { queued: 'orange', sending: 'orange', sent: 'green', failed: 'red' } as const

export function OutboxPanel({ post }: { post: JobPost }) {
  const outbox = useNotifications(post.id)
  const retry = useRecruitAction<{ p_id: string }>('retry_notification')
  const [sending, setSending] = useState<{ busy: boolean; message?: string; error?: boolean }>({ busy: false })
  const manage = post.can?.manage ?? true

  const sendNow = async () => {
    setSending({ busy: true })
    const r = await sendQueuedMessages()
    setSending('error' in r ? { busy: false, message: r.error, error: true } : { busy: false, message: `Sent ${r.sent}, failed ${r.failed}.` })
    void outbox.refetch()
  }

  if (outbox.isPending) return <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
  if (outbox.isError) return <Alert>{errorMessage(outbox.error)}</Alert>
  const rows = outbox.data
  const waiting = rows.filter((n) => n.status === 'queued').length
  return (
    <section className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <p className="text-sm text-slate-600">{waiting > 0 ? `${waiting} waiting to be sent.` : 'Nothing waiting.'} Messages wait while email is not set up (Recruitment settings).</p>
        {manage && <Button className="ml-auto" variant="secondary" loading={sending.busy} disabled={waiting === 0} onClick={sendNow}><Send className="size-4" />Send now</Button>}
      </div>
      {sending.message && <Alert tone={sending.error ? 'error' : 'success'}>{sending.message}</Alert>}
      {retry.isError && <Alert>{errorMessage(retry.error)}</Alert>}
      {rows.length === 0 ? <EmptyState title="No messages yet">Test links and interview invitations you send appear here.</EmptyState> : (
        <Table minWidth={760} head={(
          <tr><th className={th}>To</th><th className={th}>Message</th><th className={th}>Status</th><th className={th}>When</th><th className={th} /></tr>
        )}>
          {rows.map((n) => (
            <tr key={n.id}>
              <td className={td}><p className="font-medium text-slate-900">{n.full_name}</p><p className="text-xs text-slate-400">{n.channel === 'sms' ? 'SMS' : 'Email'} · {n.to_address}</p></td>
              <td className={td}>{TEMPLATE_LABEL[n.template_key as TemplateKey] ?? n.template_key}{n.subject && <p className="text-xs text-slate-400">{n.subject}</p>}</td>
              <td className={td}><Badge tone={TONE[n.status]}>{n.status}</Badge>{n.error && <p className="mt-1 max-w-xs text-xs text-red-600">{n.error}</p>}</td>
              <td className={td}>{formatDateTime(n.sent_at ?? n.created_at)}</td>
              <td className={`${td} text-right`}>{manage && n.status === 'failed' && (
                <Button variant="ghost" loading={retry.isPending && retry.variables?.p_id === n.id} onClick={() => retry.mutate({ p_id: n.id })}><RefreshCw className="size-4" />Retry</Button>
              )}</td>
            </tr>
          ))}
        </Table>
      )}
    </section>
  )
}
