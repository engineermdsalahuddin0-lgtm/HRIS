import { useState } from 'react'
import { Alert, Button, Card, cx } from '@/components/ui'
import { Select } from '@/components/kit'
import { validateHyper } from '../core/access'
import { HYPER_RANGES, RECOMMENDED_HYPER, providerOf } from '../core/catalog'
import { chunkCount } from '../core/resources'
import type { Hyperparameters } from '../core/types'
import { useAssistantStore } from '../data/store'

type RangeKey = keyof typeof HYPER_RANGES

function Range({ k, label, hint, value, onChange, format = String, ends }: {
  k: RangeKey; label: string; hint: string; value: number; onChange: (v: number) => void
  format?: (v: number) => string; ends?: [string, string]
}) {
  const r = HYPER_RANGES[k]
  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <label htmlFor={`hyper-${k}`} className="text-sm font-medium text-slate-700">{label}</label>
        <span className="font-mono text-sm text-primary-700">{format(value)}</span>
      </div>
      <input id={`hyper-${k}`} type="range" min={r.min} max={r.max} step={r.step} value={value}
        onChange={(e) => onChange(Number(e.target.value))} className="mt-2 w-full accent-primary-600" />
      {ends && <div className="flex justify-between text-[11px] text-slate-400"><span>{ends[0]}</span><span>{ends[1]}</span></div>}
      <p className="mt-1 text-xs text-slate-500">{hint}</p>
    </div>
  )
}

/** The hyperparameters. Changing chunk size or overlap re-processes every document. */
export function ModelTab() {
  const setup = useAssistantStore((s) => s.setup)
  const setHyper = useAssistantStore((s) => s.setHyper)
  const [draft, setDraft] = useState<Hyperparameters>(setup.hyper)
  const [saved, setSaved] = useState(false)
  const provider = providerOf(setup.provider)
  const errors = validateHyper(draft)
  const modelOk = provider.models.some((m) => m.id === draft.model)
  const changed = JSON.stringify(draft) !== JSON.stringify(setup.hyper)
  const rechunk = draft.chunkSize !== setup.hyper.chunkSize || draft.chunkOverlap !== setup.hyper.chunkOverlap
  const set = (patch: Partial<Hyperparameters>) => { setDraft({ ...draft, ...patch }); setSaved(false) }

  return (
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="space-y-5">
          <h3 className="font-semibold text-slate-900">Model</h3>
          <Select label={`${provider.label} model`} name="model" value={modelOk ? draft.model : ''} placeholder={modelOk ? undefined : 'Choose a model'}
            onChange={(e) => set({ model: e.target.value })}
            options={provider.models.map((m) => ({ value: m.id, label: `${m.label} — ${m.note}` }))}
            hint="Change the provider on the API key tab." />
          <Range k="temperature" label="Creativity (temperature)" value={draft.temperature} onChange={(v) => set({ temperature: v })}
            format={(v) => v.toFixed(1)} ends={['Exact wording', 'Freer wording']}
            hint="Policies need exact answers; 0.1–0.3 is best." />
        </Card>

        <Card className="space-y-5">
          <h3 className="font-semibold text-slate-900">Answer</h3>
          <div>
            <p className="mb-1.5 text-sm font-medium text-slate-700">Style</p>
            <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label="Answer style">
              {(['short', 'detailed'] as const).map((s) => (
                <button key={s} type="button" role="radio" aria-checked={draft.answerStyle === s} onClick={() => set({ answerStyle: s })}
                  className={cx('rounded-xl p-3 text-left text-sm ring-1',
                    draft.answerStyle === s ? 'bg-primary-50 ring-2 ring-primary-500' : 'ring-slate-200 hover:bg-slate-50')}>
                  <span className="block font-medium capitalize text-slate-900">{s}</span>
                  <span className="text-xs text-slate-500">{s === 'short' ? 'A few lines, 1–2 sources' : 'Fuller answer, up to 4 sources'}</span>
                </button>
              ))}
            </div>
          </div>
          <Range k="maxAnswerTokens" label="Maximum answer length" value={draft.maxAnswerTokens} onChange={(v) => set({ maxAnswerTokens: v })}
            format={(v) => `${v} tokens`} hint={`About ${Math.round(draft.maxAnswerTokens * 0.75)} English words. Longer answers cost more.`} />
        </Card>

        <Card className="space-y-5">
          <h3 className="font-semibold text-slate-900">Retrieval</h3>
          <Range k="topK" label="Sources per answer (top-k)" value={draft.topK} onChange={(v) => set({ topK: v })}
            hint="How many passages are given to the model. More = better coverage, higher cost." />
          <Range k="minScore" label="Minimum match" value={draft.minScore} onChange={(v) => set({ minScore: v })}
            format={(v) => v.toFixed(2)} ends={['Use loose matches', 'Only close matches']}
            hint={'Higher means more "I don\'t know" but fewer wrong sources.'} />
        </Card>

        <Card className="space-y-5">
          <details>
            <summary className="cursor-pointer font-semibold text-slate-900">Chunking (advanced)</summary>
            <div className="mt-5 space-y-5">
              <Range k="chunkSize" label="Chunk size" value={draft.chunkSize} onChange={(v) => set({ chunkSize: v })}
                format={(v) => `${v} tokens`} hint="How much text one passage holds. 300–500 suits policies." />
              <Range k="chunkOverlap" label="Overlap" value={draft.chunkOverlap} onChange={(v) => set({ chunkOverlap: v })}
                format={(v) => `${v}%`} hint="Repeated text between passages so a rule is not cut in half." />
              <p className="rounded-xl bg-slate-50 p-3 text-xs text-slate-600">
                A 10-page policy becomes about <b>{chunkCount(10 * 450, draft.chunkSize, draft.chunkOverlap)}</b> passages with these settings.
              </p>
            </div>
          </details>
        </Card>
      </div>

      {errors.length > 0 && <Alert>{errors[0]}</Alert>}
      {rechunk && <Alert tone="info">Saving new chunk settings processes every PDF and DOCX again. Answers keep working meanwhile.</Alert>}
      <div className="flex flex-wrap items-center justify-end gap-3">
        {saved && <span className="text-sm text-green-700">Saved</span>}
        <Button variant="secondary" onClick={() => set({ ...RECOMMENDED_HYPER, model: modelOk ? draft.model : provider.models[0].id })}>
          Recommended values
        </Button>
        <Button disabled={!changed || errors.length > 0} onClick={() => { setHyper(draft); setSaved(true) }}>Save settings</Button>
      </div>
    </div>
  )
}
