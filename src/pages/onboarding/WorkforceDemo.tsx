// The 10 demo cases, calculated live by the same code as the golden tests.
// Nothing is stored: real company data never mixes with demo numbers.
import { CheckCircle2, CircleAlert } from 'lucide-react'
import { DEMO_CAPACITY, DEMO_CASES, demoInput } from '@/onboarding-process/demo/workloadCases'
import { workloadFigures } from '@/onboarding-process/core/workload'
import { PageHeader } from '@/components/kit'
import { Alert } from '@/components/ui'
import { WorkloadCard } from './WorkloadCard'

export function WorkforceDemo() {
  return (
    <div className="space-y-4">
      <Alert tone="info">
        Demo: ten departments of a sample garments company, each showing a different rule. Capacity is {DEMO_CAPACITY} h per
        person, overload must last 2 months (cases 2, 5 and 10 are in their 2nd month). Hover any (?) to see the formula with
        the numbers filled in.
      </Alert>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {DEMO_CASES.map((demo) => {
          const figures = workloadFigures(demoInput(demo))
          const matches = figures.index === demo.expected.index && figures.backfill_seats === demo.expected.backfill
            && figures.new_positions === demo.expected.newPositions && figures.action === demo.expected.action
          return (
            <WorkloadCard key={demo.id} name={`${demo.id}. ${demo.department}`}
              figures={{ ...figures, method: demo.method, inputs: demo.inputs, capacity_hours_setting: DEMO_CAPACITY, availability: 1,
                         availability_source: 'fixed', org_headcount: demo.ratio?.orgHeadcount, per_employees: demo.ratio?.perEmployees,
                         regular_hours: demo.hours?.regular, overtime_hours: demo.hours?.overtime,
                         monthly_budget: demo.budget?.monthly, department_payroll: demo.budget?.payroll }}
              footer={(
                <div className="space-y-1 text-xs text-slate-600">
                  <p>{demo.story}</p>
                  <p className={matches ? 'inline-flex items-center gap-1 text-green-700' : 'inline-flex items-center gap-1 text-red-700'}>
                    {matches ? <CheckCircle2 className="size-3.5" /> : <CircleAlert className="size-3.5" />}
                    {matches ? 'Matches the hand-calculated result' : 'Differs from the expected result'}
                  </p>
                </div>
              )} />
          )
        })}
      </div>
    </div>
  )
}

/** Stand-alone page for /preview/workforce (dev only, no login). */
export function WorkforceDemoPage() {
  return (
    <div className="mx-auto max-w-7xl space-y-6">
      <PageHeader title="Workforce demo" description="Workload vs capacity, vacancies and hiring suggestions for 10 sample departments." />
      <WorkforceDemo />
    </div>
  )
}
