import { useState } from 'react'
import { CheckCircle2, ChevronRight, Circle, Sparkles } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { Alert, Button, Card, Input, cx } from '@/components/ui'
import { Select, Switch } from '@/components/kit'
import { serverReadiness } from '../core/access'
import type { ServerSetup } from '../data/api'
import { useDelegation, useSaveSettings } from '../data/api'
import type { SetupTab } from './AssistantSetupPage'

const STEP_TAB: Record<string, SetupTab> = { key: 'key', resources: 'resources', hyper: 'model', roles: 'roles' }

export function OverviewTab({ setup, onGo }: { setup: ServerSetup; onGo: (tab: SetupTab) => void }) {
  const { steps, ready } = serverReadiness(setup)
  const doneCount = steps.filter((s) => s.done).length
  return (
    <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
      <Card>
        <div className="flex items-center gap-3">
          <span className={cx('flex size-11 items-center justify-center rounded-2xl', ready ? 'bg-green-100 text-green-700' : 'bg-primary-50 text-primary-600')}>
            <Sparkles className="size-5" aria-hidden />
          </span>
          <div>
            <h3 className="text-lg font-semibold text-slate-900">{ready ? 'The assistant is ready' : `${doneCount} of ${steps.length} steps done`}</h3>
            <p className="text-sm text-slate-500">
              {ready ? 'Employees can ask questions now. The Updates tab always works, even without a key.'
                : !setup.settings.enabled ? 'The assistant is switched off for the company.' : 'Finish the steps below and the assistant goes live.'}
            </p>
          </div>
        </div>
        <ol className="mt-6 space-y-2">
          {steps.map((s, i) => (
            <li key={s.key}>
              <button type="button" onClick={() => onGo(STEP_TAB[s.key])}
                className="flex w-full items-center gap-3 rounded-xl p-3 text-left ring-1 ring-slate-200 hover:bg-slate-50">
                {s.done ? <CheckCircle2 className="size-5 shrink-0 text-green-600" aria-label="Done" /> : <Circle className="size-5 shrink-0 text-slate-300" aria-label="Not done" />}
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-medium text-slate-900">{i + 1}. {s.label}</span>
                  <span className="block text-xs text-slate-500">{s.detail}</span>
                </span>
                <ChevronRight className="size-4 text-slate-400" aria-hidden />
              </button>
            </li>
          ))}
        </ol>
      </Card>
      <GeneralCard key={JSON.stringify(setup.settings) + setup.hr_can_manage} setup={setup} />
    </div>
  )
}

function GeneralCard({ setup }: { setup: ServerSetup }) {
  const save = useSaveSettings()
  const delegate = useDelegation()
  const [g, setG] = useState({ enabled: setup.settings.enabled, name: setup.settings.name, language_mode: setup.settings.language_mode })
  const dirty = g.enabled !== setup.settings.enabled || g.name !== setup.settings.name || g.language_mode !== setup.settings.language_mode
  return (
    <Card className="space-y-5">
      <h3 className="font-semibold text-slate-900">General</h3>
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-slate-800">Assistant on</p>
          <p className="text-xs text-slate-500">Off hides the floating button for everyone.</p>
        </div>
        <Switch label="Assistant on" checked={g.enabled} onChange={(v) => setG({ ...g, enabled: v })} />
      </div>
      <Input label="Assistant name" name="assistant_name" value={g.name} maxLength={40} onChange={(e) => setG({ ...g, name: e.target.value })} />
      <Select label="Answer language" name="language_mode" value={g.language_mode}
        onChange={(e) => setG({ ...g, language_mode: e.target.value as typeof g.language_mode })}
        options={[
          { value: 'follow', label: 'Same as the question (Bangla or English)' },
          { value: 'bn', label: 'Always Bangla' },
          { value: 'en', label: 'Always English' },
        ]} />
      {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
      <div className="flex items-center justify-end gap-3">
        {save.isSuccess && !dirty && <span className="text-sm text-green-700">Saved</span>}
        <Button disabled={!dirty || g.name.trim().length < 2} loading={save.isPending} onClick={() => save.mutate({ ...g, name: g.name.trim() })}>Save</Button>
      </div>
      <div className="flex items-center justify-between gap-3 border-t border-slate-100 pt-5">
        <div>
          <p className="text-sm font-medium text-slate-800">HR Manager may manage the assistant</p>
          <p className="text-xs text-slate-500">{setup.is_admin ? 'Only an Admin can change this.' : 'An Admin gave you this. Only an Admin can take it back.'}</p>
        </div>
        <Switch label="HR Manager may manage the assistant" checked={setup.hr_can_manage} disabled={!setup.is_admin || delegate.isPending}
          onChange={(v) => delegate.mutate(v)} />
      </div>
      {delegate.isError && <Alert>{errorMessage(delegate.error)}</Alert>}
    </Card>
  )
}
