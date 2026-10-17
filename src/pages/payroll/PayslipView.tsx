import { useState } from 'react'
import { Printer } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import type { Payslip, PayslipLine } from '@/lib/payrollRuns'
import { formatPeriod, usePayslip } from '@/lib/payrollRuns'
import type { PayslipLanguage } from '@/lib/payslipText'
import { formatMoney, formatNumber, lineLabel, payslipText } from '@/lib/payslipText'
import { Alert, Button, Spinner, cx } from '@/components/ui'
import { Modal } from '@/components/kit'

/** "base × rate × quantity" for a line, so every amount is explainable. */
function lineBasis(language: PayslipLanguage, line: PayslipLine): string {
  const n = (v: number | null) => (v === null ? '' : formatNumber(language, Number(v).toLocaleString('en-IN', { maximumFractionDigits: 4 })))
  switch (line.line_type) {
    case 'overtime': return `${n(line.quantity)} h × ${n(line.base)} × ${n(line.rate)}`
    case 'absence':
    case 'unpaid_leave':
    case 'unpaid_off_day': return `${n(line.quantity)} × ${n(line.base)}`
    case 'half_day': return `${n(line.quantity)} × ${n(line.base)} × ${n(line.rate)}%`
    case 'late': return `${n(line.quantity)} × ${n(line.base)}`
    case 'proration': return `${n(line.base)} × ${n(line.quantity)} / ${formatNumber(language, 30)}`
    case 'bonus': return line.rate !== null ? `${n(line.base)} × ${n(line.rate)}%` : ''
    case 'arrear': return line.quantity ? `${n(line.quantity)} month(s)` : ''
    default: return line.rate !== null && line.rate !== undefined ? `${n(line.rate)}%` : ''
  }
}

function LineTable({ language, title, lines, total, totalLabel }: {
  language: PayslipLanguage; title: string; lines: PayslipLine[]; total: number; totalLabel: string
}) {
  return (
    <div>
      <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">{title}</h3>
      <table className="w-full text-sm">
        <tbody className="divide-y divide-slate-100">
          {lines.map((line, index) => (
            <tr key={`${line.code}-${index}`}>
              <td className="py-1.5 pr-2 text-slate-800">{lineLabel(language, line.line_type, line.label)}</td>
              <td className="py-1.5 pr-2 text-right text-xs text-slate-400">{lineBasis(language, line)}</td>
              <td className={cx('py-1.5 text-right tabular-nums', line.amount < 0 ? 'text-red-600' : 'text-slate-900')}>
                {line.amount < 0 ? '−' : ''}{formatMoney(language, Math.abs(line.amount))}
              </td>
            </tr>
          ))}
          {lines.length === 0 && <tr><td className="py-2 text-slate-400" colSpan={3}>—</td></tr>}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-slate-200 font-semibold">
            <td className="pt-2" colSpan={2}>{totalLabel}</td>
            <td className="pt-2 text-right tabular-nums">{formatMoney(language, total)}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

/** The printable payslip document. */
export function PayslipDocument({ payslip, language }: { payslip: Payslip; language: PayslipLanguage }) {
  const t = (key: Parameters<typeof payslipText>[1]) => payslipText(language, key)
  const { slip, employee, organization, payment } = payslip
  const earnings = payslip.lines.filter((l) => l.direction === 'earning')
  const deductions = payslip.lines.filter((l) => l.direction === 'deduction')
  return (
    <article className="print-area mx-auto w-full max-w-3xl bg-white p-6 text-slate-900 sm:p-8" lang={language}>
      <header className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-4">
        <div>
          <p className="text-lg font-bold">{organization.name}</p>
          <p className="text-xs text-slate-500">{formatNumber(language, organization.org_code)}</p>
        </div>
        <div className="text-right">
          <p className="text-xl font-bold text-primary-700">{t('payslip')}</p>
          <p className="text-sm text-slate-600">{t('period')}: {formatPeriod(slip.period_month, language === 'bn' ? 'bn-BD' : 'en-GB')}</p>
        </div>
      </header>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 border-b border-slate-200 py-4 text-sm sm:grid-cols-3">
        <div><dt className="text-xs text-slate-500">{t('employee')}</dt><dd className="font-medium">{employee.full_name}</dd></div>
        <div><dt className="text-xs text-slate-500">{t('cardId')}</dt><dd className="font-mono">{employee.card_id}</dd></div>
        <div><dt className="text-xs text-slate-500">{t('designation')}</dt><dd>{employee.designation_name ?? '—'}{employee.grade_code ? ` (${employee.grade_code})` : ''}</dd></div>
        <div><dt className="text-xs text-slate-500">{t('department')}</dt><dd>{employee.department_name ?? '—'}</dd></div>
        <div><dt className="text-xs text-slate-500">{t('payableDays')}</dt><dd>{formatNumber(language, slip.payable_days)} / {formatNumber(language, 30)}</dd></div>
        <div><dt className="text-xs text-slate-500">{t('absentDays')}</dt><dd>{formatNumber(language, slip.absent_days)}</dd></div>
        {slip.overtime_minutes > 0 && (
          <div><dt className="text-xs text-slate-500">{t('overtimeHours')}</dt><dd>{formatNumber(language, (slip.overtime_minutes / 60).toFixed(2))}</dd></div>
        )}
        {payment && (
          <div><dt className="text-xs text-slate-500">{t('paidTo')}</dt>
            <dd>{payment.bank_name ?? payment.wallet_provider ?? payment.method} {payment.masked_number ?? ''}</dd></div>
        )}
        <div><dt className="text-xs text-slate-500">{t('status')}</dt><dd>{slip.payment_status === 'paid' ? t('paid') : t('pending')}</dd></div>
      </dl>

      <div className="grid gap-6 py-4 sm:grid-cols-2">
        <LineTable language={language} title={t('earnings')} lines={earnings} total={slip.gross_earnings} totalLabel={t('grossEarnings')} />
        <LineTable language={language} title={t('deductions')} lines={deductions} total={slip.total_deductions} totalLabel={t('totalDeductions')} />
      </div>

      <footer className="rounded-xl bg-primary-50 p-4">
        <div className="flex items-center justify-between">
          <span className="font-semibold text-slate-800">{t('netPay')}</span>
          <span className="text-2xl font-bold tabular-nums text-primary-700">{formatMoney(language, slip.net)}</span>
        </div>
        {Number(slip.rounding_adjustment) !== 0 && (
          <p className="mt-1 text-right text-xs text-slate-500">{t('roundingAdjustment')}: {formatMoney(language, slip.rounding_adjustment)}</p>
        )}
        {Number(slip.carry_forward_out) > 0 && (
          <p className="mt-1 text-right text-xs text-red-600">{t('carryForward')}: {formatMoney(language, slip.carry_forward_out)}</p>
        )}
      </footer>
      <p className="mt-4 text-center text-[11px] text-slate-400">{t('generated')}</p>
    </article>
  )
}

/** Dialog with a language switch and Print (save as PDF from the print dialog). */
export function PayslipDialog({ slipId, onClose }: { slipId: string | null; onClose: () => void }) {
  const payslip = usePayslip(slipId)
  const [language, setLanguage] = useState<PayslipLanguage>('en')
  return (
    <Modal open={!!slipId} onClose={onClose} size="xl" title="Payslip"
      footer={
        <>
          <div className="mr-auto flex gap-1 rounded-xl bg-slate-100 p-1" role="tablist" aria-label="Language">
            {(['en', 'bn'] as PayslipLanguage[]).map((code) => (
              <button key={code} role="tab" aria-selected={language === code} onClick={() => setLanguage(code)}
                className={cx('rounded-lg px-3 py-1 text-sm', language === code ? 'bg-white font-medium shadow-sm' : 'text-slate-500')}>
                {code === 'en' ? 'English' : 'বাংলা'}
              </button>
            ))}
          </div>
          <Button variant="secondary" onClick={onClose}>Close</Button>
          <Button onClick={() => window.print()} disabled={!payslip.data}><Printer className="size-4" />Print / PDF</Button>
        </>
      }
    >
      {payslip.isPending ? <div className="flex justify-center py-10 text-primary-600"><Spinner /></div>
        : payslip.isError ? <Alert>{errorMessage(payslip.error)}</Alert>
        : <PayslipDocument payslip={payslip.data} language={language} />}
    </Modal>
  )
}
