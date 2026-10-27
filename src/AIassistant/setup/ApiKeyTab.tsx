import { useState } from 'react'
import { CheckCircle2, Eye, EyeOff, KeyRound, XCircle } from 'lucide-react'
import { Alert, Button, Card, cx } from '@/components/ui'
import { Label } from '@/components/kit'
import { PROVIDERS, providerOf } from '../core/catalog'
import type { ProviderKey } from '../core/types'
import { useAssistantStore } from '../data/store'

/**
 * The company's own AI key. It is sent once to the backend (stored encrypted, like the
 * recruitment key) and tested there; the browser only keeps the last 4 characters.
 */
export function ApiKeyTab() {
  const setup = useAssistantStore((s) => s.setup)
  const setKeyResult = useAssistantStore((s) => s.setKeyResult)
  const removeKey = useAssistantStore((s) => s.removeKey)
  const setHyper = useAssistantStore((s) => s.setHyper)
  const [provider, setProvider] = useState<ProviderKey>(setup.provider)
  const [key, setKey] = useState('')
  const [show, setShow] = useState(false)
  const [testing, setTesting] = useState(false)
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null)
  const p = providerOf(provider)

  const saveAndTest = () => {
    const value = key.trim()
    setTesting(true)
    setMessage(null)
    // Stand-in for the backend test call (a tiny request to the provider).
    setTimeout(() => {
      const ok = p.keyPattern.test(value)
      setKeyResult(provider, value.slice(-4), ok)
      if (!p.models.some((m) => m.id === setup.hyper.model)) setHyper({ ...setup.hyper, model: p.models[0].id })
      setMessage(ok
        ? { ok, text: `Connected to ${p.label}. The key is saved encrypted.` }
        : { ok, text: `${p.label} did not accept this key. Copy it again from ${p.keyHelp}.` })
      setKey('')
      setTesting(false)
    }, 900)
  }

  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_340px]">
      <Card className="space-y-5">
        <div>
          <h3 className="font-semibold text-slate-900">AI provider</h3>
          <p className="text-sm text-slate-500">Your company pays the provider directly for its use.</p>
        </div>
        <div className="grid gap-3 sm:grid-cols-3" role="radiogroup" aria-label="AI provider">
          {PROVIDERS.map((x) => (
            <button key={x.key} type="button" role="radio" aria-checked={provider === x.key} onClick={() => setProvider(x.key)}
              className={cx('rounded-xl p-3 text-left ring-1 transition',
                provider === x.key ? 'bg-primary-50 ring-2 ring-primary-500' : 'ring-slate-200 hover:bg-slate-50')}>
              <p className="text-sm font-medium text-slate-900">{x.label}</p>
              <p className="mt-0.5 text-xs text-slate-500">{x.models.length} models</p>
            </button>
          ))}
        </div>

        <div>
          <Label htmlFor="ai_key" required>API key</Label>
          <div className="flex gap-2">
            <input id="ai_key" type={show ? 'text' : 'password'} autoComplete="off" spellCheck={false} value={key}
              onChange={(e) => setKey(e.target.value)} placeholder={p.keyExample}
              className="block w-full rounded-xl border border-slate-300 px-3.5 py-2.5 font-mono text-sm outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100" />
            <button type="button" onClick={() => setShow(!show)} aria-label={show ? 'Hide key' : 'Show key'}
              className="rounded-xl px-3 text-slate-500 ring-1 ring-slate-300 hover:bg-slate-50">
              {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
            </button>
          </div>
          <p className="mt-1 text-xs text-slate-500">Get it from {p.keyHelp}.</p>
        </div>
        {message && <Alert tone={message.ok ? 'success' : 'error'}>{message.text}</Alert>}
        <div className="flex justify-end">
          <Button loading={testing} disabled={key.trim().length < 10} onClick={saveAndTest}>Save and test</Button>
        </div>
      </Card>

      <Card className="h-fit space-y-4">
        <h3 className="font-semibold text-slate-900">Current key</h3>
        {setup.keyStatus === 'missing' ? (
          <div className="flex items-center gap-3 text-sm text-slate-500">
            <KeyRound className="size-5 text-slate-300" aria-hidden /> No key yet. Updates still work; Ask needs a key.
          </div>
        ) : (
          <>
            <div className="flex items-center gap-3">
              {setup.keyStatus === 'tested'
                ? <CheckCircle2 className="size-5 text-green-600" aria-hidden />
                : <XCircle className="size-5 text-red-500" aria-hidden />}
              <div className="text-sm">
                <p className="font-medium text-slate-900">{providerOf(setup.provider).label} · <span className="font-mono">••••{setup.keyLast4}</span></p>
                <p className="text-xs text-slate-500">
                  {setup.keyStatus === 'tested' ? 'Working' : 'Not working'}
                  {setup.keyCheckedAt && ` · checked ${new Date(setup.keyCheckedAt).toLocaleString()}`}
                </p>
              </div>
            </div>
            <Button variant="secondary" className="w-full" onClick={() => window.confirm('Remove the key? Ask stops working until a new key is saved.') && removeKey()}>
              Remove key
            </Button>
          </>
        )}
        <p className="border-t border-slate-100 pt-4 text-xs text-slate-500">
          The full key never comes back to the browser. Only the backend reads it, to answer questions.
        </p>
      </Card>
    </div>
  )
}
