// Demo organograms, run in the browser only (nothing is stored). Same chart as the real page,
// but every number can be played with: budget, slots, offers, joining, leaving, blocking.
import { useState } from 'react'
import { RotateCcw } from 'lucide-react'
import type { ChartGrade, ChartPosition } from '@/onboarding-process/core/organogram'
import { STATE_META, budgetError, budgetSentence } from '@/onboarding-process/core/organogram'
import type { SimResult, SimState } from '@/onboarding-process/core/organogramSim'
import { acceptOffer, applyBudget, dropOffer, joinOffer, leave, sendOffer, simCounts, startRecruiting, toggleHold } from '@/onboarding-process/core/organogramSim'
import { DEMO_SEEDS, demoChart } from '@/onboarding-process/demo/organogramDemo'
import { Alert, Button, Card, Input, cx } from '@/components/ui'
import { Modal, PageHeader, Select, Tabs } from '@/components/kit'
import { Chart } from './OrganogramPage'

type Message = { tone: 'success' | 'error'; text: string } | null

function BudgetEditor({ s, onApply }: { s: SimState; onApply: (approved: number, slots: Record<string, number>, after: SimState['after_separation']) => void }) {
  const [approved, setApproved] = useState(String(s.budget))
  const [after, setAfter] = useState(s.after_separation)
  const [slots, setSlots] = useState<Record<string, string>>(() => Object.fromEntries(s.grades.map((g) => [g.id, String(g.slots)])))
  const values = s.grades.map((g) => Number(slots[g.id] || 0))
  const total = values.reduce((a, b) => a + b, 0)
  const problem = approved === '' ? 'Enter the approved headcount' : budgetError(Number(approved), values, simCounts(s))
  return (
    <Card className="space-y-3">
      <p className="font-semibold text-slate-900">Budget &amp; slots</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Input label="Approved headcount budget" inputMode="numeric" value={approved} onChange={(e) => setApproved(e.target.value.replace(/\D/g, ''))} />
        <Select label="When someone leaves" value={after} onChange={(e) => setAfter(e.target.value as SimState['after_separation'])}
          options={[{ value: 'vacant', label: 'Position becomes vacant' }, { value: 'blocked', label: 'Position is blocked' }]} />
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {[...s.grades].sort((a, b) => a.rank - b.rank).map((g) => (
          <label key={g.id} className="flex items-center justify-between gap-2 rounded-lg bg-slate-50 px-2.5 py-1.5 text-sm">
            <span className="truncate text-slate-700">{g.name}</span>
            <input aria-label={`${g.name} slots`} inputMode="numeric" value={slots[g.id] ?? '0'}
              onChange={(e) => setSlots((x) => ({ ...x, [g.id]: e.target.value.replace(/\D/g, '') }))}
              className="w-14 rounded-md border border-slate-300 px-2 py-1 text-right text-sm" />
          </label>
        ))}
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <span className={cx('text-sm', approved !== '' && total > Number(approved) ? 'text-red-600' : 'text-slate-600')}>
          Slots {total} of {approved || '—'}{approved !== '' && total < Number(approved) ? ` · ${Number(approved) - total} left for extras` : ''}</span>
        <Button className="ml-auto" disabled={!!problem}
          onClick={() => onApply(Number(approved), Object.fromEntries(s.grades.map((g, i) => [g.id, values[i]])), after)}>Apply</Button>
      </div>
      {problem && approved !== '' && <p className="text-xs text-red-600">{problem}</p>}
    </Card>
  )
}

function OffersCard({ s, run }: { s: SimState; run: (f: (s: SimState) => SimResult) => void }) {
  const grades = [...s.grades].sort((a, b) => a.rank - b.rank)
  const [grade, setGrade] = useState(grades.at(-1)?.id ?? '')
  const name = (id: string) => s.grades.find((g) => g.id === id)?.name ?? id
  return (
    <Card className="space-y-3">
      <p className="font-semibold text-slate-900">Offers</p>
      <div className="flex items-end gap-2">
        <Select className="flex-1" label="Grade" value={grade} onChange={(e) => setGrade(e.target.value)} options={grades.map((g) => ({ value: g.id, label: g.name }))} />
        <Button variant="secondary" onClick={() => run((x) => sendOffer(x, grade))}>Send offer</Button>
      </div>
      {s.offers.length === 0 ? <p className="text-sm text-slate-500">No offers in process.</p> : (
        <ul className="divide-y divide-slate-100 text-sm">
          {s.offers.map((o) => (
            <li key={o.id} className="flex flex-wrap items-center gap-2 py-2">
              <span className="font-medium text-slate-900">{o.name}</span>
              <span className="text-slate-500">{name(o.grade_id)} · {o.status === 'accepted' ? 'accepted' : 'sent'}</span>
              <span className="ml-auto flex gap-1">
                {o.status === 'sent' && <Button variant="ghost" className="px-2 py-1 text-xs" onClick={() => run((x) => acceptOffer(x, o.id))}>Accept</Button>}
                <Button variant="ghost" className="px-2 py-1 text-xs" onClick={() => run((x) => joinOffer(x, o.id))}>Joins</Button>
                <Button variant="ghost" className="px-2 py-1 text-xs text-red-600" onClick={() => run((x) => dropOffer(x, o.id))}>Declines</Button>
              </span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  )
}

function PositionActions({ p, g, run, onClose }: { p: ChartPosition; g: ChartGrade; run: (f: (s: SimState) => SimResult) => void; onClose: () => void }) {
  const act = (f: (s: SimState) => SimResult) => { run(f); onClose() }
  return (
    <Modal open onClose={onClose} title={`${g.name} · ${p.kind === 'extra' ? 'extra position' : `slot ${p.slot_no}`}`}
      description={<span className={cx('rounded-full px-2 py-0.5 text-xs font-medium', STATE_META[p.state].badge)}>{STATE_META[p.state].label}</span>}
      footer={<Button onClick={onClose}>Close</Button>}>
      <div className="space-y-3 text-sm">
        {p.employee ? <p>{p.employee.full_name} · {p.employee.designation} · {p.employee.card_id}</p>
          : p.state === 'blocked' ? <p>Frozen: nobody can be hired against this slot until it is opened.</p>
            : p.recruitment && p.state === 'in_recruitment' ? <p>Being recruited: {p.recruitment.stage}, {p.recruitment.candidates} candidate(s).</p>
              : <p>Budgeted and open to hire.</p>}
        <div className="flex flex-wrap gap-2">
          {p.employee && <Button variant="secondary" onClick={() => act((s) => leave(s, p.id))}>Employee leaves</Button>}
          {!p.employee && p.kind === 'planned' && (
            <Button variant="secondary" onClick={() => act((s) => toggleHold(s, p.id))}>{p.state === 'blocked' ? 'Open for hiring' : 'Block this slot'}</Button>)}
          {p.state === 'vacant' && <Button variant="secondary" onClick={() => act((s) => startRecruiting(s, g.id))}>Start recruiting</Button>}
          {!p.employee && p.state !== 'blocked' && <Button variant="secondary" onClick={() => act((s) => sendOffer(s, g.id))}>Send offer for this grade</Button>}
        </div>
      </div>
    </Modal>
  )
}

export function OrganogramDemo() {
  const [index, setIndex] = useState(0)
  const [states, setStates] = useState<SimState[]>(() => DEMO_SEEDS.map((d) => d.seed()))
  const [version, setVersion] = useState(0)
  const [message, setMessage] = useState<Message>(null)
  const [open, setOpen] = useState<{ p: ChartPosition; g: ChartGrade } | null>(null)
  const s = states[index]
  const chart = demoChart(s)

  const run = (f: (s: SimState) => SimResult) => {
    const r = f(states[index])
    setMessage(r.error ? { tone: 'error', text: r.error } : r.note ? { tone: 'success', text: r.note } : null)
    if (!r.error) setStates((all) => all.map((x, i) => (i === index ? r.state : x)))
  }
  const reset = () => {
    setStates((all) => all.map((x, i) => (i === index ? DEMO_SEEDS[i].seed() : x)))
    setVersion((v) => v + 1)
    setMessage(null)
  }

  return (
    <div className="space-y-4">
      <Alert tone="info">Demo: play with the budget, slots, offers, joining and leaving. Click a card for its actions. Nothing here is saved; Reset starts over.</Alert>
      <div className="flex flex-wrap items-center gap-3">
        <Tabs value={String(index)} onChange={(v) => { setIndex(Number(v)); setMessage(null) }}
          tabs={DEMO_SEEDS.map((_d, i) => ({ key: String(i), label: states[i].department.name }))} />
        <Button variant="ghost" className="ml-auto" onClick={reset}><RotateCcw className="size-4" />Reset</Button>
      </div>
      <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-700">
        <p className="font-medium text-slate-900">{budgetSentence(chart.counts)} · headroom for extras {Math.max(chart.counts.headroom ?? 0, 0)}</p>
        <p className="mt-1">{DEMO_SEEDS[index].story}</p>
      </div>
      {message && <Alert tone={message.tone === 'error' ? undefined : 'success'}>{message.text}</Alert>}
      <div className="grid gap-4 lg:grid-cols-2">
        <BudgetEditor key={`${index}-${version}-${s.budget}-${s.after_separation}-${s.grades.map((g) => g.slots).join('.')}`} s={s}
          onApply={(a, sl, af) => run((x) => applyBudget(x, a, sl, af))} />
        <OffersCard key={`${index}-${version}`} s={s} run={run} />
      </div>
      <Chart chart={chart} onPosition={(p, g) => setOpen({ p, g })} />
      {open && <PositionActions p={open.p} g={open.g} run={run} onClose={() => setOpen(null)} />}
    </div>
  )
}

/** Stand-alone page for /preview/organogram (dev only, no login). */
export function OrganogramDemoPage() {
  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Organogram demo" description="Positions driven by the headcount budget: filled, extra, in recruitment, vacant and blocked." />
      <OrganogramDemo />
    </div>
  )
}
