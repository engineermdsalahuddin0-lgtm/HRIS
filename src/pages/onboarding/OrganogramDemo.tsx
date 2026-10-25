// Demo organograms, built in the browser only (nothing is stored). Same chart as the real page.
import { useState } from 'react'
import { DEMO_ORGANOGRAMS } from '@/onboarding-process/demo/organogramDemo'
import { budgetSentence } from '@/onboarding-process/core/organogram'
import { Alert } from '@/components/ui'
import { PageHeader, Tabs } from '@/components/kit'
import { Chart } from './OrganogramPage'

export function OrganogramDemo() {
  const [id, setId] = useState(DEMO_ORGANOGRAMS[0].department.id)
  const demo = DEMO_ORGANOGRAMS.find((d) => d.department.id === id) ?? DEMO_ORGANOGRAMS[0]
  return (
    <div className="space-y-4">
      <Alert tone="info">Demo: two sample departments showing every position state. Click a card to see what it means. Nothing here is saved.</Alert>
      <Tabs value={id} onChange={setId} tabs={DEMO_ORGANOGRAMS.map((d) => ({ key: d.department.id, label: d.department.name }))} />
      <div className="rounded-2xl bg-slate-50 p-4 text-sm text-slate-700">
        <p className="font-medium text-slate-900">{budgetSentence(demo.counts)} · headroom for extras {Math.max(demo.counts.headroom ?? 0, 0)}</p>
        <p className="mt-1">{demo.story}</p>
      </div>
      <Chart chart={demo} />
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
