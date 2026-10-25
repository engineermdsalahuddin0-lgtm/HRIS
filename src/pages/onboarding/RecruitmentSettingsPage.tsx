// Recruitment settings: how CVs are read (basic / AI) and the company's own Claude API key.
// The key is write-only: it is stored encrypted and only the recruit-ai function can read it.
import { useState } from 'react'
import { Bot, FileText, KeyRound, ShieldCheck, Trash2 } from 'lucide-react'
import type { AiModel, CvMode } from '@/onboarding-process/core/types'
import { callRecruitAi, useRecruitAction, useRecruitSettings } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import { Alert, Badge, Button, Card, Input, PageLoader, cx } from '@/components/ui'
import { PageHeader, Select } from '@/components/kit'

const MODELS: { value: AiModel; label: string }[] = [
  { value: 'claude-opus-5-5', label: 'Claude Opus 5.5 — most accurate (default)' },
  { value: 'claude-sonnet-5-5', label: 'Claude Sonnet 5.5 — balanced' },
  { value: 'claude-haiku-5-5', label: 'Claude Haiku 5.5 — lowest cost' },
]

const MODES: { value: CvMode; title: string; icon: typeof Bot; text: string }[] = [
  { value: 'basic', title: 'Basic (no AI)', icon: FileText,
    text: 'The CV is turned into text. Skills are found by keyword, years from work dates, the degree from its name. HR adds the relevance mark. No API cost.' },
  { value: 'ai', title: 'AI (Claude)', icon: Bot,
    text: 'Claude reads the CV, also scanned PDFs, and fills years, degree, skills and a relevance mark with a reason. Uses your API key; falls back to Basic if the key fails.' },
]

export default function RecruitmentSettingsPage() {
  const settings = useRecruitSettings()
  const saveMode = useRecruitAction<{ p: { cv_mode: CvMode } }>('save_recruit_settings')
  const saveKey = useRecruitAction<{ p: Record<string, unknown> }>('save_ai_integration')
  const removeKey = useRecruitAction<Record<string, never>>('remove_ai_integration')
  const [apiKey, setApiKey] = useState('')
  const [model, setModel] = useState<AiModel | null>(null)
  const [test, setTest] = useState<{ busy: boolean; result?: { ok: boolean; message: string }; error?: string }>({ busy: false })

  if (settings.isPending) return <PageLoader />
  if (settings.isError) return <Alert>{errorMessage(settings.error)}</Alert>
  const s = settings.data
  const ai = s.ai
  const chosenModel = model ?? ai?.model ?? 'claude-opus-5-5'

  const runTest = async () => {
    setTest({ busy: true })
    try {
      const result = await callRecruitAi<{ ok: boolean; message: string }>({ action: 'test_key' })
      setTest({ busy: false, result })
      settings.refetch()
    } catch (e) {
      setTest({ busy: false, error: errorMessage(e) })
    }
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="Recruitment settings" description="How CVs are read, and the AI key your company pays for." />

      <Card className="space-y-4">
        <h3 className="font-semibold text-slate-900">Reading CVs</h3>
        {saveMode.isError && <Alert>{errorMessage(saveMode.error)}</Alert>}
        <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="CV reading mode">
          {MODES.map((m) => (
            <button key={m.value} type="button" role="radio" aria-checked={s.cv_mode === m.value} disabled={saveMode.isPending}
              onClick={() => saveMode.mutate({ p: { cv_mode: m.value } })}
              className={cx('rounded-2xl p-4 text-left ring-1 transition',
                s.cv_mode === m.value ? 'bg-primary-50 ring-2 ring-primary-500' : 'ring-slate-200 hover:ring-slate-300')}>
              <span className="flex items-center gap-2 font-medium text-slate-900"><m.icon className="size-4 text-primary-600" />{m.title}</span>
              <span className="mt-1 block text-sm text-slate-600">{m.text}</span>
            </button>
          ))}
        </div>
        {s.cv_mode === 'ai' && !ai?.configured && <Alert tone="info">AI is chosen but no key is saved yet, so CVs are read in Basic mode until the Admin adds one.</Alert>}
        <p className="text-xs text-slate-500">A single job post can use a different mode (on the post's Applicants tab). Nobody is rejected automatically: HR decides.</p>
      </Card>

      <Card className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h3 className="flex items-center gap-2 font-semibold text-slate-900"><KeyRound className="size-4" />Claude API key</h3>
          {ai?.configured && (ai.test_status === 'ok' ? <Badge tone="green">Working</Badge>
            : ai.test_status === 'failed' ? <Badge tone="red">Test failed</Badge> : <Badge>Not tested</Badge>)}
        </div>
        {!s.is_admin ? (
          <p className="text-sm text-slate-600">{ai?.configured ? `A key ending in ••••${ai.last4} is set (${ai.model}).` : 'No key is set.'} Only the company Admin can change it.</p>
        ) : (
          <>
            {(saveKey.isError || removeKey.isError) && <Alert>{errorMessage(saveKey.error ?? removeKey.error)}</Alert>}
            {saveKey.isSuccess && !apiKey && <Alert tone="success">Saved. Run a test to check the key.</Alert>}
            <p className="text-sm text-slate-600">
              Create a key in the Anthropic Console (console.anthropic.com → API keys) and paste it here. It is stored encrypted, never shown
              again, and only used by this system to read CVs and draft questions. Usage is billed to your Anthropic account.
            </p>
            <div className="grid gap-4 sm:grid-cols-2">
              <Input label={ai?.configured ? `New key (current ends in ${ai.last4})` : 'API key'} type="password" autoComplete="off"
                placeholder="sk-ant-..." value={apiKey} onChange={(e) => setApiKey(e.target.value.trim())} />
              <Select label="Model" value={chosenModel} onChange={(e) => setModel(e.target.value as AiModel)} options={MODELS} />
            </div>
            <div className="flex flex-wrap gap-2">
              <Button loading={saveKey.isPending} disabled={!apiKey && (!ai?.configured || chosenModel === ai.model)}
                onClick={() => saveKey.mutate({ p: { api_key: apiKey || null, model: chosenModel, enabled: true } }, { onSuccess: () => setApiKey('') })}>
                <ShieldCheck className="size-4" />Save
              </Button>
              {ai?.configured && <Button variant="secondary" loading={test.busy} onClick={runTest}>Test the key</Button>}
              {ai?.configured && (
                <Button variant="ghost" loading={removeKey.isPending}
                  onClick={() => confirm('Remove the AI key? CVs will be read in Basic mode.') && removeKey.mutate({})}>
                  <Trash2 className="size-4" />Remove
                </Button>
              )}
            </div>
            {test.result && <Alert tone={test.result.ok ? 'success' : 'error'}>{test.result.message}</Alert>}
            {test.error && <Alert>{test.error}</Alert>}
            {ai?.tested_at && <p className="text-xs text-slate-500">Last test {formatDateTime(ai.tested_at)}: {ai.test_message}</p>}
          </>
        )}
      </Card>
    </div>
  )
}
