import { useState } from 'react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, cx } from '@/components/ui'
import { HYPER_RANGES } from '../core/catalog'
import { chunkCount } from '../core/resources'
import type { ServerHyper, ServerSetup } from '../data/api'
import { useSaveHyper } from '../data/api'

type RangeKey = keyof typeof HYPER_RANGES

const RECOMMENDED: ServerHyper = {
  temperature: 0.2, max_answer_tokens: 600, answer_style: 'short', top_k: 6, min_score: 0.3, chunk_size: 400, chunk_overlap: 15,
}

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

/** The hyperparameters (the model itself is chosen on the API keys tab). New chunking re-processes PDF / DOCX. */
export function ModelTab({ setup }: { setup: ServerSetup }) {
  const save = useSaveHyper()
  const saved = setup.settings.hyper
  const [d, setD] = useState<ServerHyper>(saved)
  const changed = JSON.stringify(d) !== JSON.stringify(saved)
  const rechunk = d.chunk_size !== saved.chunk_size || d.chunk_overlap !== saved.chunk_overlap
  const set = (patch: Partial<ServerHyper>) => setD({ ...d, ...patch })

  return (
    <div className="space-y-6">
      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="space-y-5">
          <h3 className="font-semibold text-slate-900">Answer</h3>
          <Range k="temperature" label="Creativity (temperature)" value={d.temperature} onChange={(v) => set({ temperature: v })}
            format={(v) => v.toFixed(1)} ends={['Exact wording', 'Freer wording']} hint="Policies need exact answers; 0.1–0.3 is best." />
          <div>
            <p className="mb-1.5 text-sm font-medium text-slate-700">Style</p>
            <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label="Answer style">
              {(['short', 'detailed'] as const).map((s) => (
                <button key={s} type="button" role="radio" aria-checked={d.answer_style === s} onClick={() => set({ answer_style: s })}
                  className={cx('rounded-xl p-3 text-left text-sm ring-1', d.answer_style === s ? 'bg-primary-50 ring-2 ring-primary-500' : 'ring-slate-200 hover:bg-slate-50')}>
                  <span className="block font-medium capitalize text-slate-900">{s}</span>
                  <span className="text-xs text-slate-500">{s === 'short' ? 'A few lines' : 'Fuller answer with more sources'}</span>
                </button>
              ))}
            </div>
          </div>
          <Range k="maxAnswerTokens" label="Maximum answer length" value={d.max_answer_tokens} onChange={(v) => set({ max_answer_tokens: v })}
            format={(v) => `${v} tokens`} hint={`About ${Math.round(d.max_answer_tokens * 0.75)} English words. Longer answers cost more.`} />
        </Card>
        <Card className="space-y-5">
          <h3 className="font-semibold text-slate-900">Retrieval</h3>
          <Range k="topK" label="Sources per answer (top-k)" value={d.top_k} onChange={(v) => set({ top_k: v })}
            hint="How many passages are given to the model. More = better coverage, higher cost." />
          <Range k="minScore" label="Minimum match" value={d.min_score} onChange={(v) => set({ min_score: v })}
            format={(v) => v.toFixed(2)} ends={['Use loose matches', 'Only close matches']} hint={'Higher means more "I don\'t know" but fewer wrong sources.'} />
          <details className="border-t border-slate-100 pt-4">
            <summary className="cursor-pointer text-sm font-semibold text-slate-900">Chunking (advanced)</summary>
            <div className="mt-5 space-y-5">
              <Range k="chunkSize" label="Chunk size" value={d.chunk_size} onChange={(v) => set({ chunk_size: v })}
                format={(v) => `${v} tokens`} hint="How much text one passage holds. 300–500 suits policies." />
              <Range k="chunkOverlap" label="Overlap" value={d.chunk_overlap} onChange={(v) => set({ chunk_overlap: v })}
                format={(v) => `${v}%`} hint="Repeated text between passages so a rule is not cut in half." />
              <p className="rounded-xl bg-slate-50 p-3 text-xs text-slate-600">
                A 10-page policy becomes about <b>{chunkCount(10 * 450, d.chunk_size, d.chunk_overlap)}</b> passages with these settings.
              </p>
            </div>
          </details>
        </Card>
      </div>
      {rechunk && <Alert tone="info">Saving new chunk settings processes every PDF and DOCX again. Answers keep working meanwhile.</Alert>}
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      {save.isSuccess && !changed && (
        <Alert tone="success">Saved.{save.data.length > 0 && ` ${save.data.length} documents will be processed again.`}</Alert>
      )}
      <div className="flex flex-wrap items-center justify-end gap-3">
        <Button variant="secondary" onClick={() => setD(RECOMMENDED)}>Recommended values</Button>
        <Button disabled={!changed} loading={save.isPending} onClick={() => save.mutate(d)}>Save settings</Button>
      </div>
    </div>
  )
}
