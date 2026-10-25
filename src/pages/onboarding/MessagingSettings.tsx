// Email (Resend) and SMS (generic gateway, off until switched on) settings, and the
// message templates. Keys are write-only; only the recruit-notify function reads them.
import { useState } from 'react'
import { Mail, MessageSquare, Send, Trash2 } from 'lucide-react'
import type { Channel, MessageTemplate, MessagingChannel } from '@/onboarding-process/core/types'
import type { TemplateKey } from '@/onboarding-process/core/interview'
import { PLACEHOLDERS, TEMPLATE_LABEL } from '@/onboarding-process/core/interview'
import { testMessaging, useMessagingSettings, useRecruitAction } from '@/lib/recruit'
import { useMyContext } from '@/lib/appContext'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, Input, Spinner } from '@/components/ui'
import { Select, Switch, Textarea } from '@/components/kit'

function Status({ c }: { c?: MessagingChannel }) {
  if (!c) return <Badge>Not set up</Badge>
  if (!c.enabled) return <Badge>Off</Badge>
  return c.test_status === 'ok' ? <Badge tone="green">Working</Badge> : c.test_status === 'failed' ? <Badge tone="red">Test failed</Badge> : <Badge tone="orange">Not tested</Badge>
}

function TestBox({ channel, placeholder, onDone }: { channel: Channel; placeholder: string; onDone: () => void }) {
  const [to, setTo] = useState('')
  const [state, setState] = useState<{ busy: boolean; result?: { ok: boolean; message: string } }>({ busy: false })
  return (
    <div className="flex flex-wrap items-end gap-2">
      <Input label={`Send a test ${channel === 'email' ? 'email' : 'SMS'} to`} placeholder={placeholder} value={to} onChange={(e) => setTo(e.target.value)} className="min-w-56" />
      <Button variant="secondary" loading={state.busy} disabled={!to} onClick={async () => {
        setState({ busy: true })
        const result = await testMessaging(channel, to)
        setState({ busy: false, result })
        onDone()
      }}><Send className="size-4" />Send test</Button>
      {state.result && <Alert tone={state.result.ok ? 'success' : 'error'}>{state.result.message}</Alert>}
    </div>
  )
}

function EmailCard({ c, admin, refetch }: { c?: MessagingChannel; admin: boolean; refetch: () => void }) {
  const ctx = useMyContext()
  const save = useRecruitAction<{ p_channel: Channel; p: Record<string, unknown> }>('save_messaging_channel')
  const remove = useRecruitAction<{ p_channel: Channel }>('remove_messaging_channel')
  const [name, setName] = useState(c?.config.from_name ?? ctx.organization?.name ?? '')
  const [from, setFrom] = useState(c?.config.from_address ?? '')
  const [key, setKey] = useState('')
  return (
    <Card className="space-y-4">
      <div className="flex items-center justify-between"><h3 className="flex items-center gap-2 font-semibold text-slate-900"><Mail className="size-4" />Email</h3><Status c={c} /></div>
      {!admin ? <p className="text-sm text-slate-600">{c ? `Sending from ${c.config.from_name} <${c.config.from_address}>.` : 'Email is not set up.'} Only the company Admin can change it.</p> : (
        <>
          {(save.isError || remove.isError) && <Alert>{errorMessage(save.error ?? remove.error)}</Alert>}
          <p className="text-sm text-slate-600">Uses <span className="font-medium">Resend</span> (resend.com). Verify your domain there, create an API key and paste it here. Until email works, copy links by hand from the Tests & interviews tab.</p>
          <div className="grid gap-3 sm:grid-cols-3">
            <Input label="Sender name" value={name} onChange={(e) => setName(e.target.value)} />
            <Input label="Sender address" placeholder="hr@yourcompany.com" value={from} onChange={(e) => setFrom(e.target.value.trim())} />
            <Input label={c?.configured ? `New API key (ends ${c.last4})` : 'API key'} type="password" autoComplete="off" placeholder="re_..." value={key} onChange={(e) => setKey(e.target.value.trim())} />
          </div>
          <div className="flex flex-wrap gap-2">
            <Button loading={save.isPending} disabled={!from || !name || (!key && !c?.configured)}
              onClick={() => save.mutate({ p_channel: 'email', p: { from_name: name, from_address: from, api_key: key || null, enabled: true } }, { onSuccess: () => setKey('') })}>Save</Button>
            {c && <Button variant="ghost" loading={remove.isPending} onClick={() => confirm('Remove email settings?') && remove.mutate({ p_channel: 'email' })}><Trash2 className="size-4" />Remove</Button>}
          </div>
          {c?.configured && <TestBox channel="email" placeholder="you@yourcompany.com" onDone={refetch} />}
          {c?.tested_at && <p className="text-xs text-slate-500">Last test {formatDateTime(c.tested_at)}: {c.test_message}</p>}
        </>
      )}
    </Card>
  )
}

function SmsCard({ c, admin, refetch }: { c?: MessagingChannel; admin: boolean; refetch: () => void }) {
  const save = useRecruitAction<{ p_channel: Channel; p: Record<string, unknown> }>('save_messaging_channel')
  const [f, setF] = useState({
    url: c?.config.url ?? '', method: c?.config.method ?? 'POST', to_param: c?.config.to_param ?? 'to', text_param: c?.config.text_param ?? 'message',
    key_param: c?.config.key_param ?? 'api_key', sender_param: c?.config.sender_param ?? '', sender_id: c?.config.sender_id ?? '', api_key: '',
  })
  const [enabled, setEnabled] = useState(c?.enabled ?? false)
  const set = (k: keyof typeof f, v: string) => setF((x) => ({ ...x, [k]: v }))
  return (
    <Card className="space-y-4">
      <div className="flex items-center justify-between"><h3 className="flex items-center gap-2 font-semibold text-slate-900"><MessageSquare className="size-4" />SMS</h3><Status c={c} /></div>
      {!admin ? <p className="text-sm text-slate-600">{c?.enabled ? 'SMS is switched on.' : 'SMS is off.'} Only the company Admin can change it.</p> : (
        <>
          {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
          <p className="text-sm text-slate-600">Off until you have an SMS gateway account and an approved sender ID (BTRC). Enter the gateway's API address and the names of its fields as given in its documentation.</p>
          <div className="grid gap-3 sm:grid-cols-[1fr_7rem]">
            <Input label="Gateway API address" placeholder="https://api.gateway.com.bd/sms/send" value={f.url} onChange={(e) => set('url', e.target.value.trim())} />
            <Select label="Method" value={f.method} onChange={(e) => set('method', e.target.value)} options={[{ value: 'POST', label: 'POST' }, { value: 'GET', label: 'GET' }]} />
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <Input label="Number field" value={f.to_param} onChange={(e) => set('to_param', e.target.value.trim())} />
            <Input label="Message field" value={f.text_param} onChange={(e) => set('text_param', e.target.value.trim())} />
            <Input label="Key field" value={f.key_param} onChange={(e) => set('key_param', e.target.value.trim())} />
            <Input label="Sender field (optional)" value={f.sender_param} onChange={(e) => set('sender_param', e.target.value.trim())} />
            <Input label="Sender ID (optional)" value={f.sender_id} onChange={(e) => set('sender_id', e.target.value.trim())} />
            <Input label={c?.configured ? `New API key (ends ${c.last4})` : 'API key'} type="password" autoComplete="off" value={f.api_key} onChange={(e) => set('api_key', e.target.value.trim())} />
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <span className="flex items-center gap-2 text-sm text-slate-700"><Switch label="Send SMS" checked={enabled} onChange={setEnabled} />Send SMS</span>
            <Button className="ml-auto" loading={save.isPending} disabled={!f.url || (!f.api_key && !c?.configured)}
              onClick={() => save.mutate({ p_channel: 'sms', p: { ...f, api_key: f.api_key || null, enabled } }, { onSuccess: () => set('api_key', '') })}>Save</Button>
          </div>
          {c?.configured && <TestBox channel="sms" placeholder="01XXXXXXXXX" onDone={refetch} />}
        </>
      )}
    </Card>
  )
}

function TemplateEditor({ t }: { t: MessageTemplate }) {
  const save = useRecruitAction<{ p_key: TemplateKey; p_channel: Channel; p_subject: string | null; p_body: string }>('save_message_template')
  const [subject, setSubject] = useState(t.subject ?? '')
  const [body, setBody] = useState(t.body)
  const dirty = subject !== (t.subject ?? '') || body !== t.body
  return (
    <div className="space-y-2 rounded-xl border border-slate-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-medium text-slate-900">{TEMPLATE_LABEL[t.key]} · {t.channel === 'email' ? 'Email' : 'SMS'}</p>
        <p className="text-xs text-slate-500">Placeholders: {PLACEHOLDERS[t.key].map((p) => `{${p}}`).join(' ')}</p>
      </div>
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {t.channel === 'email' && <Input label="Subject" value={subject} maxLength={200} onChange={(e) => setSubject(e.target.value)} />}
      <Textarea aria-label="Message" rows={t.channel === 'email' ? 7 : 3} value={body} maxLength={t.channel === 'sms' ? 480 : 5000} onChange={(e) => setBody(e.target.value)}
        hint={t.channel === 'sms' ? `${body.length} characters (one SMS is 160; Bangla 70)` : undefined} />
      <div className="flex justify-end">
        <Button variant="secondary" disabled={!dirty} loading={save.isPending}
          onClick={() => save.mutate({ p_key: t.key, p_channel: t.channel, p_subject: t.channel === 'email' ? subject : null, p_body: body })}>Save template</Button>
      </div>
    </div>
  )
}

export function MessagingSettings() {
  const settings = useMessagingSettings()
  if (settings.isPending) return <div className="flex justify-center py-6"><Spinner /></div>
  if (settings.isError) return <Alert>{errorMessage(settings.error)}</Alert>
  const s = settings.data
  const refetch = () => void settings.refetch()
  return (
    <>
      <div className="grid gap-6 lg:grid-cols-2">
        <EmailCard key={`e-${s.channels.email?.last4 ?? ''}`} c={s.channels.email} admin={s.is_admin} refetch={refetch} />
        <SmsCard key={`s-${s.channels.sms?.last4 ?? ''}`} c={s.channels.sms} admin={s.is_admin} refetch={refetch} />
      </div>
      <Card className="space-y-4">
        <h3 className="font-semibold text-slate-900">Message templates</h3>
        <p className="text-sm text-slate-600">The words in {'{braces}'} are filled in for each applicant. Edit freely; Bangla text works too.</p>
        <div className="space-y-3">{s.templates.filter((t) => t.key === 'test_invite' || t.key === 'interview_invite')
          .map((t) => <TemplateEditor key={`${t.key}-${t.channel}-${t.updated_at}`} t={t} />)}</div>
      </Card>
    </>
  )
}
