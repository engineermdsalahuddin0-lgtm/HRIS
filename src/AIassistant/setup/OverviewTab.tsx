import { CheckCircle2, Circle, ChevronRight, Sparkles } from 'lucide-react'
import { Button, Card, Input, cx } from '@/components/ui'
import { Select, Switch } from '@/components/kit'
import { readiness } from '../core/access'
import type { AssistantSetup, RoleKey } from '../core/types'
import { useAssistantStore } from '../data/store'
import type { SetupTab } from './AssistantSetupPage'

const STEP_TAB: Record<string, SetupTab> = { key: 'key', resources: 'resources', hyper: 'model', roles: 'roles' }

export function OverviewTab({ editor, onGo }: { editor: RoleKey; onGo: (tab: SetupTab) => void }) {
  const setup = useAssistantStore((s) => s.setup)
  const update = useAssistantStore((s) => s.update)
  const reset = useAssistantStore((s) => s.reset)
  const { steps, ready } = readiness(setup)
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
              {ready
                ? 'Employees can ask questions now. The Updates tab always works, even without a key.'
                : !setup.enabled ? 'The assistant is switched off for the company.' : 'Finish the steps below and the assistant goes live.'}
            </p>
          </div>
        </div>
        <ol className="mt-6 space-y-2">
          {steps.map((s, i) => (
            <li key={s.key}>
              <button type="button" onClick={() => onGo(STEP_TAB[s.key])}
                className="flex w-full items-center gap-3 rounded-xl p-3 text-left ring-1 ring-slate-200 hover:bg-slate-50">
                {s.done
                  ? <CheckCircle2 className="size-5 shrink-0 text-green-600" aria-label="Done" />
                  : <Circle className="size-5 shrink-0 text-slate-300" aria-label="Not done" />}
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

      <GeneralCard setup={setup} editor={editor} update={update} onReset={reset} />
    </div>
  )
}

function GeneralCard({ setup, editor, update, onReset }: {
  setup: AssistantSetup; editor: RoleKey; update: (p: Partial<AssistantSetup>) => void; onReset: () => void
}) {
  return (
    <Card className="space-y-5">
      <h3 className="font-semibold text-slate-900">General</h3>
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-slate-800">Assistant on</p>
          <p className="text-xs text-slate-500">Off hides the floating button for everyone.</p>
        </div>
        <Switch label="Assistant on" checked={setup.enabled} onChange={(v) => update({ enabled: v })} />
      </div>
      <Input label="Assistant name" name="assistant_name" value={setup.name} maxLength={40}
        onChange={(e) => update({ name: e.target.value })} onBlur={(e) => !e.target.value.trim() && update({ name: 'Olympus Assistant' })} />
      <Select label="Answer language" name="language_mode" value={setup.languageMode}
        onChange={(e) => update({ languageMode: e.target.value as AssistantSetup['languageMode'] })}
        options={[
          { value: 'follow', label: 'Same as the question (Bangla or English)' },
          { value: 'bn', label: 'Always Bangla' },
          { value: 'en', label: 'Always English' },
        ]} />
      <div className="flex items-center justify-between gap-3 border-t border-slate-100 pt-5">
        <div>
          <p className="text-sm font-medium text-slate-800">HR Manager may manage the assistant</p>
          <p className="text-xs text-slate-500">
            {editor === 'admin' ? 'Only an Admin can change this.' : 'An Admin gave you this. Only an Admin can take it back.'}
          </p>
        </div>
        <Switch label="HR Manager may manage the assistant" checked={setup.hrCanManage} disabled={editor !== 'admin'}
          onChange={(v) => update({ hrCanManage: v })} />
      </div>
      {editor === 'admin' && (
        <Button variant="ghost" className="w-full" onClick={() => window.confirm('Clear the whole preview setup in this browser?') && onReset()}>
          Reset preview
        </Button>
      )}
    </Card>
  )
}
