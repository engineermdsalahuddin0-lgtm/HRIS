// Payroll settings, with a plain-language hint for every rule. Statutory values
// stay "unconfirmed" until the company checks them against the law.
import type { ReactNode } from 'react'
import { useEffect, useState } from 'react'
import { ShieldAlert, ShieldCheck } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatDateTime } from '@/lib/options'
import type { PayrollSettings } from '@/lib/payroll'
import { usePayrollAction, usePayrollSettings, useSavePayrollRow } from '@/lib/payroll'
import { useMyContext } from '@/lib/appContext'
import { Alert, Button, Card, Input, PageLoader } from '@/components/ui'
import { PageHeader, Select, Switch } from '@/components/kit'

type Editable = Pick<PayrollSettings,
  'deduct_base' | 'ot_rate_basis' | 'ot_hourly_divisor' | 'pay_weekly_off' | 'pay_holidays' | 'half_day_deduction_percent'
  | 'unpaid_leave_base' | 'net_rounding' | 'negative_net_rule' | 'payslip_release' | 'large_change_percent'>

/** Numeric fields are kept as typed text until saved, so partial input ('12.') is not lost. */
type NumericKey = 'ot_hourly_divisor' | 'half_day_deduction_percent' | 'large_change_percent'
type Form = Omit<Editable, NumericKey> & Record<NumericKey, string>

const BASE_OPTIONS = [{ value: 'basic', label: 'Basic' }, { value: 'gross', label: 'Gross (without overtime or bonus)' }]

function Row({ title, hint, children }: { title: string; hint: string; children: ReactNode }) {
  return (
    <div className="grid gap-3 border-b border-slate-100 py-4 last:border-0 sm:grid-cols-[1fr_16rem] sm:items-center">
      <div>
        <p className="text-sm font-medium text-slate-900">{title}</p>
        <p className="text-sm text-slate-500">{hint}</p>
      </div>
      <div>{children}</div>
    </div>
  )
}

export default function PayrollSettingsPage() {
  const context = useMyContext()
  const canManage = context.permissions.includes('payroll_settings.manage')
  const settings = usePayrollSettings()
  const save = useSavePayrollRow('payroll_settings')
  const confirm = usePayrollAction('confirm_payroll_statutory_values')
  const [form, setForm] = useState<Form | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    if (settings.data) {
      const { deduct_base, ot_rate_basis, ot_hourly_divisor, pay_weekly_off, pay_holidays, half_day_deduction_percent,
        unpaid_leave_base, net_rounding, negative_net_rule, payslip_release, large_change_percent } = settings.data
      setForm({ deduct_base, ot_rate_basis, pay_weekly_off, pay_holidays, unpaid_leave_base, net_rounding, negative_net_rule,
        payslip_release, ot_hourly_divisor: String(ot_hourly_divisor),
        half_day_deduction_percent: String(half_day_deduction_percent), large_change_percent: String(large_change_percent) })
    }
  }, [settings.data])

  if (settings.isPending || (settings.data && !form)) return <PageLoader />
  if (settings.isError) return <Alert>{errorMessage(settings.error)}</Alert>
  if (!settings.data || !form) return <Alert>Payroll settings are not set up for this organization.</Alert>

  const set = <K extends keyof Form>(key: K, value: Form[K]) => { setSaved(false); setForm((f) => (f ? { ...f, [key]: value } : f)) }
  const divisorValid = form.ot_hourly_divisor.trim() !== '' && Number(form.ot_hourly_divisor) >= 1 && Number(form.ot_hourly_divisor) <= 744
  const halfDayValid = form.half_day_deduction_percent.trim() !== '' && Number(form.half_day_deduction_percent) >= 0 && Number(form.half_day_deduction_percent) <= 100
  const changeValid = form.large_change_percent.trim() !== '' && Number(form.large_change_percent) >= 0 && Number(form.large_change_percent) <= 1000
  const submit = async () => {
    setSaved(false)
    await save.mutateAsync({
      id: settings.data!.org_id, key: 'org_id',
      values: { ...form, ot_hourly_divisor: Number(form.ot_hourly_divisor), half_day_deduction_percent: Number(form.half_day_deduction_percent),
        large_change_percent: Number(form.large_change_percent) },
    }).then(() => setSaved(true)).catch(() => undefined)
  }

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="Payroll settings" description="How payroll turns attendance, overtime and pay into payslips. The salary month is always 30 days." />

      {settings.data.statutory_confirmed_at ? (
        <Alert tone="success">
          <span className="inline-flex items-center gap-2"><ShieldCheck className="size-4" />
            Statutory values confirmed on {formatDateTime(settings.data.statutory_confirmed_at)}.</span>
        </Alert>
      ) : (
        <Card className="flex flex-wrap items-center justify-between gap-3 bg-amber-50 p-4 ring-amber-200">
          <p className="inline-flex items-center gap-2 text-sm text-amber-900"><ShieldAlert className="size-4 shrink-0" />
            The overtime divisor and half-day rule are placeholders. Check them against your labour law, then confirm.</p>
          {canManage && <Button variant="secondary" loading={confirm.isPending} onClick={() => confirm.mutate({})}>I have checked — confirm</Button>}
        </Card>
      )}
      {confirm.isError && <Alert>{errorMessage(confirm.error)}</Alert>}

      <Card className="py-2">
        <fieldset disabled={!canManage} className="disabled:opacity-80">
          <Row title="Absence deduction base" hint="Daily rate = this amount ÷ 30. Used for absent days.">
            <Select aria-label="Absence deduction base" value={form.deduct_base} onChange={(e) => set('deduct_base', e.target.value as Editable['deduct_base'])} options={BASE_OPTIONS} />
          </Row>
          <Row title="Unpaid leave base" hint="Daily rate for unpaid leave days.">
            <Select aria-label="Unpaid leave base" value={form.unpaid_leave_base} onChange={(e) => set('unpaid_leave_base', e.target.value as Editable['unpaid_leave_base'])} options={BASE_OPTIONS} />
          </Row>
          <Row title="Half-day deduction" hint="Percent of the daily rate taken for a half day.">
            <Input label="Percent" name="half_day_percent" type="number" min={0} max={100} step="0.01" value={form.half_day_deduction_percent}
              onChange={(e) => set('half_day_deduction_percent', e.target.value)} error={halfDayValid ? undefined : '0 to 100'} />
          </Row>
          <Row title="Overtime base" hint="The amount the overtime hourly rate is worked out from.">
            <Select aria-label="Overtime base" value={form.ot_rate_basis} onChange={(e) => set('ot_rate_basis', e.target.value as Editable['ot_rate_basis'])} options={BASE_OPTIONS} />
          </Row>
          <Row title="Overtime hourly divisor" hint="Hourly rate = overtime base ÷ this number, then × the day-type multiplier from the overtime policy. A legal value — confirm it.">
            <Input label="Divisor" name="ot_divisor" type="number" min={1} max={744} step="0.01" value={form.ot_hourly_divisor}
              onChange={(e) => set('ot_hourly_divisor', e.target.value)} error={divisorValid ? undefined : '1 to 744'} />
          </Row>
          <Row title="Pay weekly offs" hint="Weekly off days inside the month stay paid.">
            <Switch label="Pay weekly offs" checked={form.pay_weekly_off} onChange={(v) => set('pay_weekly_off', v)} />
          </Row>
          <Row title="Pay holidays" hint="Holidays inside the month stay paid.">
            <Switch label="Pay holidays" checked={form.pay_holidays} onChange={(v) => set('pay_holidays', v)} />
          </Row>
          <Row title="Net pay rounding" hint="Every line is rounded to 2 decimals; this rule applies to the final net.">
            <Select aria-label="Net pay rounding" value={form.net_rounding} onChange={(e) => set('net_rounding', e.target.value as Editable['net_rounding'])}
              options={[{ value: 'nearest_taka', label: 'Nearest taka' }, { value: 'up_taka', label: 'Up to the next taka' },
                { value: 'down_taka', label: 'Down to the taka' }, { value: 'none', label: 'No rounding (paisa)' }]} />
          </Row>
          <Row title="If net pay is negative" hint="When deductions are larger than the gross.">
            <Select aria-label="Negative net rule" value={form.negative_net_rule} onChange={(e) => set('negative_net_rule', e.target.value as Editable['negative_net_rule'])}
              options={[{ value: 'zero_and_carry', label: 'Pay 0, carry the rest to next month' }, { value: 'block', label: 'Block the slip for review' }]} />
          </Row>
          <Row title="Employees see payslips" hint="When a payslip becomes visible to the employee.">
            <Select aria-label="Payslip release" value={form.payslip_release} onChange={(e) => set('payslip_release', e.target.value as Editable['payslip_release'])}
              options={[{ value: 'approved', label: 'After the run is approved' }, { value: 'paid', label: 'After payment' }]} />
          </Row>
          <Row title="Large change warning" hint="Warn the reviewer when net pay changes more than this percent from last month.">
            <Input label="Percent" name="large_change" type="number" min={0} max={1000} step="0.01" value={form.large_change_percent}
              onChange={(e) => set('large_change_percent', e.target.value)} error={changeValid ? undefined : '0 to 1000'} />
          </Row>
        </fieldset>
        <div className="flex flex-wrap items-center justify-between gap-3 pt-4">
          <p className="text-xs text-slate-500">Tax (TDS), provident fund and gratuity switches arrive with Part 3C.</p>
          {canManage && (
            <div className="flex items-center gap-3">
              {saved && <span className="text-sm text-green-700">Saved</span>}
              <Button disabled={!divisorValid || !halfDayValid || !changeValid} loading={save.isPending} onClick={submit}>Save settings</Button>
            </div>
          )}
        </div>
        {save.isError && <div className="pt-3"><Alert>{errorMessage(save.error)}</Alert></div>}
      </Card>
    </div>
  )
}
