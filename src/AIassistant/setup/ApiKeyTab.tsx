import { useState } from 'react'
import { CheckCircle2, Eye, EyeOff, KeyRound, XCircle } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Button, Card, cx } from '@/components/ui'
import { Label, Select } from '@/components/kit'
import type { KeyInfo, KeySlot, ServerSetup } from '../data/api'
import { useRemoveKey, useSaveKey, useTestKey } from '../data/api'

const PROVIDER_LABEL: Record<string, { label: string; help: string; example: string }> = {
  anthropic: { label: 'Anthropic Claude', help: 'console.anthropic.com → API keys', example: 'sk-ant-…' },
  openai: { label: 'OpenAI', help: 'platform.openai.com → API keys', example: 'sk-…' },
  google: { label: 'Google Gemini', help: 'aistudio.google.com → Get API key', example: 'AIza…' },
  voyage: { label: 'Voyage AI', help: 'dashboard.voyageai.com → API keys (recommended with Claude)', example: 'pa-…' },
}

/**
 * Two slots: the chat model, and the embedding model that builds the company's vector store.
 * OpenAI and Gemini chat keys also embed, so the second slot is only needed with Claude.
 * Keys are sent once, stored encrypted, and tested by the Edge Function.
 */
export function ApiKeyTab({ setup }: { setup: ServerSetup }) {
  const chatProvider = setup.keys.chat?.provider
  const needsEmbedKey = !chatProvider || chatProvider === 'anthropic' || !!setup.keys.embed
  return (
    <div className="space-y-6">
      <KeySlotCard slot="chat" title="1. Chat model" description="Answers the questions. Your company pays the provider directly."
        info={setup.keys.chat} providers={Object.keys(setup.models.chat)} models={setup.models.chat} />
      {needsEmbedKey ? (
        <KeySlotCard slot="embed" title="2. Embedding model"
          description={chatProvider === 'anthropic'
            ? 'Claude has no embedding service, so your documents need a second key to be searchable. Voyage AI is recommended with Claude.'
            : 'Turns your documents into a searchable vector store (1024 dimensions).'}
          info={setup.keys.embed} providers={Object.keys(setup.models.embed)} models={setup.models.embed} />
      ) : (
        <Card className="flex items-start gap-3">
          <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-green-600" aria-hidden />
          <div>
            <h3 className="font-semibold text-slate-900">2. Embedding model</h3>
            <p className="text-sm text-slate-500">
              Your {PROVIDER_LABEL[chatProvider!].label} key also builds the vector store
              ({setup.keys.embed_effective?.model}). No second key needed.
            </p>
          </div>
        </Card>
      )}
      <p className="text-xs text-slate-500">
        The full key never comes back to the browser. Only the assistant's server function reads it, to answer and to index.
        Changing the embedding provider re-indexes your documents.
      </p>
    </div>
  )
}

function KeySlotCard({ slot, title, description, info, providers, models }: {
  slot: KeySlot; title: string; description: string; info: KeyInfo | null; providers: string[]
  models: Record<string, { id: string; label: string }[]>
}) {
  const save = useSaveKey()
  const test = useTestKey()
  const remove = useRemoveKey()
  const [provider, setProvider] = useState(info?.provider ?? providers[0])
  const [model, setModel] = useState(info?.model ?? models[providers[0]][0].id)
  const [key, setKey] = useState('')
  const [show, setShow] = useState(false)
  const p = PROVIDER_LABEL[provider]
  const result = save.data ?? test.data
  const changedModelOnly = !!info && !key && (provider === info.provider) && model !== info.model

  const choose = (next: string) => { setProvider(next); setModel(models[next][0].id) }

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
      <Card className="space-y-5">
        <div>
          <h3 className="font-semibold text-slate-900">{title}</h3>
          <p className="text-sm text-slate-500">{description}</p>
        </div>
        <div className={cx('grid gap-3', providers.length === 3 ? 'sm:grid-cols-3' : 'sm:grid-cols-2')} role="radiogroup" aria-label={`${title} provider`}>
          {providers.map((x) => (
            <button key={x} type="button" role="radio" aria-checked={provider === x} onClick={() => choose(x)}
              className={cx('rounded-xl p-3 text-left ring-1 transition', provider === x ? 'bg-primary-50 ring-2 ring-primary-500' : 'ring-slate-200 hover:bg-slate-50')}>
              <p className="text-sm font-medium text-slate-900">{PROVIDER_LABEL[x].label}</p>
              <p className="mt-0.5 text-xs text-slate-500">{models[x].length} models</p>
            </button>
          ))}
        </div>
        <Select label="Model" name={`${slot}_model`} value={model} onChange={(e) => setModel(e.target.value)}
          options={models[provider].map((m) => ({ value: m.id, label: m.label }))} />
        <div>
          <Label htmlFor={`${slot}_key`} required={!info || info.provider !== provider}>API key</Label>
          <div className="flex gap-2">
            <input id={`${slot}_key`} type={show ? 'text' : 'password'} autoComplete="off" spellCheck={false} value={key}
              onChange={(e) => setKey(e.target.value)} placeholder={info && info.provider === provider ? `Keep ••••${info.last4}` : p.example}
              className="block w-full rounded-xl border border-slate-300 px-3.5 py-2.5 font-mono text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
            <button type="button" onClick={() => setShow(!show)} aria-label={show ? 'Hide key' : 'Show key'}
              className="rounded-xl px-3 text-slate-500 ring-1 ring-slate-300 hover:bg-slate-50">
              {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </button>
          </div>
          <p className="mt-1 text-xs text-slate-500">Get it from {p.help}.</p>
        </div>
        {(save.isError || test.isError) && <Alert>{errorMessage(save.error ?? test.error)}</Alert>}
        {result && <Alert tone={result.ok ? 'success' : 'error'}>{result.message}</Alert>}
        <div className="flex justify-end">
          <Button loading={save.isPending}
            disabled={(key.trim().length < 10 && !changedModelOnly) || (!info && !key) || (!!info && info.provider !== provider && !key)}
            onClick={() => save.mutate({ slot, provider, model, api_key: key.trim() || null }, { onSuccess: () => setKey('') })}>
            Save and test
          </Button>
        </div>
      </Card>

      <Card className="h-fit space-y-4">
        <h3 className="font-semibold text-slate-900">Current key</h3>
        {!info ? (
          <div className="flex items-center gap-3 text-sm text-slate-500"><KeyRound className="size-5 text-slate-300" aria-hidden /> Not given yet.</div>
        ) : (
          <>
            <div className="flex items-center gap-3">
              {info.status === 'tested' ? <CheckCircle2 className="size-5 text-green-600" aria-hidden /> : <XCircle className={cx('size-5', info.status === 'failed' ? 'text-red-500' : 'text-slate-300')} aria-hidden />}
              <div className="text-sm">
                <p className="font-medium text-slate-900">{PROVIDER_LABEL[info.provider]?.label ?? info.provider} · <span className="font-mono">••••{info.last4}</span></p>
                <p className="text-xs text-slate-500">{info.model}</p>
                <p className="text-xs text-slate-500">
                  {info.status === 'tested' ? 'Working' : info.status === 'failed' ? 'Not working' : 'Not tested yet'}
                  {info.tested_at && ` · ${formatDateTime(info.tested_at)}`}
                </p>
              </div>
            </div>
            {info.status === 'failed' && info.message && <p className="text-xs text-red-600">{info.message}</p>}
            <div className="grid gap-2">
              <Button variant="secondary" loading={test.isPending} onClick={() => test.mutate(slot)}>Test again</Button>
              <Button variant="ghost" loading={remove.isPending}
                onClick={() => window.confirm('Remove this key? The assistant stops answering until a new key is saved.') && remove.mutate(slot)}>
                Remove key
              </Button>
            </div>
          </>
        )}
      </Card>
    </div>
  )
}
