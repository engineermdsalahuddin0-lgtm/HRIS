import { useState } from 'react'
import { CheckCircle2, Copy, RefreshCw } from 'lucide-react'
import { errorMessage, passwordRule } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader } from '@/components/ui'
import { Modal, PageHeader, Table, Textarea, td, th } from '@/components/kit'
import { temporaryPassword } from '../core/password'
import type { PasswordRequest } from '../data/api'
import { useDismissRequest, usePasswordRequests, useResolveRequest } from '../data/api'

const STATUS = { pending: { label: 'Pending', tone: 'orange' }, resolved: { label: 'Reset', tone: 'green' }, dismissed: { label: 'Dismissed', tone: 'slate' } } as const

/** /password-requests (users.reset_password): reset with a temporary password, or dismiss. */
export default function PasswordRequestsPage() {
  const list = usePasswordRequests()
  const [resetting, setResetting] = useState<PasswordRequest | null>(null)
  const [dismissing, setDismissing] = useState<PasswordRequest | null>(null)

  if (list.isPending) return <PageLoader />
  if (list.isError) return <Alert>{errorMessage(list.error)}</Alert>
  const { kpis, requests } = list.data

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <PageHeader title="Password requests" description="Employee portal password reset requests" />
      <div className="grid grid-cols-2 gap-3 sm:max-w-md">
        <Card className="p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Pending</p>
          <p className="mt-1 text-2xl font-semibold text-slate-900">{kpis.pending}</p>
        </Card>
        <Card className="p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">Reset (30 days)</p>
          <p className="mt-1 text-2xl font-semibold text-slate-900">{kpis.resolved}</p>
        </Card>
      </div>
      {kpis.pending === 0 && (
        <p className="inline-flex items-center gap-2 rounded-full bg-green-50 px-3 py-1 text-sm font-medium text-green-700">
          <CheckCircle2 className="size-4" aria-hidden /> All clear
        </p>
      )}
      {requests.length === 0 ? <EmptyState title="No requests in the last 90 days" /> : (
        <Table minWidth={720} head={
          <tr><th className={th}>Employee</th><th className={th}>Asked with</th><th className={th}>Requested at</th><th className={th}>Status</th><th className={th} aria-label="Actions" /></tr>
        }>
          {requests.map((r) => (
            <tr key={r.id}>
              <td className={td}>
                <p className="font-medium text-slate-900">{r.full_name}</p>
                <p className="text-xs text-slate-500">{r.card_id}{r.department && ` · ${r.department}`}</p>
              </td>
              <td className={`${td} font-mono text-xs`}>{r.login_hint}</td>
              <td className={`${td} whitespace-nowrap`}>{formatDateTime(r.requested_at)}</td>
              <td className={td}>
                <Badge tone={STATUS[r.status].tone}>{STATUS[r.status].label}</Badge>
                {r.status !== 'pending' && (
                  <p className="mt-1 text-xs text-slate-500">{r.resolved_by ?? '—'} · {formatDateTime(r.resolved_at)}{r.note && ` · ${r.note}`}</p>
                )}
              </td>
              <td className={`${td} whitespace-nowrap text-right`}>
                {r.status === 'pending' && (
                  <>
                    <Button variant="ghost" onClick={() => setDismissing(r)}>Dismiss</Button>
                    <Button onClick={() => setResetting(r)}>Reset</Button>
                  </>
                )}
              </td>
            </tr>
          ))}
        </Table>
      )}
      {resetting && <ResetDialog request={resetting} onClose={() => setResetting(null)} />}
      {dismissing && <DismissDialog request={dismissing} onClose={() => setDismissing(null)} />}
    </div>
  )
}

function ResetDialog({ request, onClose }: { request: PasswordRequest; onClose: () => void }) {
  const resolve = useResolveRequest()
  const [password, setPassword] = useState(() => temporaryPassword())
  const [copied, setCopied] = useState(false)
  const ok = passwordRule.test(password)
  return (
    <Modal open onClose={onClose} size="sm" title={`New password for ${request.full_name}`}
      description="They must change it when they sign in. All their open sessions end now."
      footer={resolve.isSuccess
        ? <Button onClick={onClose}>Done</Button>
        : <><Button variant="secondary" onClick={onClose}>Cancel</Button>
            <Button loading={resolve.isPending} disabled={!ok} onClick={() => resolve.mutate({ p_id: request.id, p_password: password })}>Set password</Button></>}>
      <div className="space-y-3">
        {resolve.isError && <Alert>{errorMessage(resolve.error)}</Alert>}
        {resolve.isSuccess && <Alert tone="success">Done. Give this password to {request.full_name} in person or by phone.</Alert>}
        <div className="flex items-end gap-2">
          <Input className="flex-1" label="Temporary password" name="temp_password" value={password} readOnly={resolve.isSuccess}
            onChange={(e) => setPassword(e.target.value)} error={!ok ? passwordRule.message : undefined} />
          {!resolve.isSuccess && (
            <Button variant="secondary" aria-label="New suggestion" title="New suggestion" onClick={() => setPassword(temporaryPassword())}><RefreshCw className="size-4" /></Button>
          )}
          <Button variant="secondary" aria-label="Copy" title="Copy"
            onClick={() => { void navigator.clipboard?.writeText(password); setCopied(true) }}><Copy className="size-4" /></Button>
        </div>
        {copied && <p className="text-xs text-green-700">Copied</p>}
      </div>
    </Modal>
  )
}

function DismissDialog({ request, onClose }: { request: PasswordRequest; onClose: () => void }) {
  const dismiss = useDismissRequest()
  const [note, setNote] = useState('')
  return (
    <Modal open onClose={onClose} size="sm" title="Dismiss the request" description={request.full_name}
      footer={<><Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={dismiss.isPending} disabled={note.trim().length < 3}
          onClick={() => dismiss.mutate({ p_id: request.id, p_note: note.trim() }, { onSuccess: onClose })}>Dismiss</Button></>}>
      <div className="space-y-3">
        {dismiss.isError && <Alert>{errorMessage(dismiss.error)}</Alert>}
        <Textarea label="Reason" name="dismiss_note" maxLength={300} value={note} onChange={(e) => setNote(e.target.value)}
          hint="For example: they remembered it, or the request did not come from them." />
      </div>
    </Modal>
  )
}
