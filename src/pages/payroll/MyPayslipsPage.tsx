import { useState } from 'react'
import { FileText } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatTaka } from '@/lib/payroll'
import { formatPeriod, useMyPayslips } from '@/lib/payrollRuns'
import { Alert, Badge, Card, EmptyState, PageLoader } from '@/components/ui'
import { PageHeader } from '@/components/kit'
import { PayslipDialog } from './PayslipView'

/** An employee's own payslips, shown once the company releases them. */
export default function MyPayslipsPage() {
  const payslips = useMyPayslips()
  const [openSlipId, setOpenSlipId] = useState<string | null>(null)

  return (
    <div className="mx-auto max-w-4xl space-y-6">
      <PageHeader title="My payslips" description="Open a payslip to see every line, switch to Bangla, or print it as a PDF." />
      {payslips.isPending ? <PageLoader /> : payslips.isError ? <Alert>{errorMessage(payslips.error)}</Alert>
        : payslips.data.length === 0 ? <EmptyState title="No payslips yet">Payslips appear here once payroll is approved.</EmptyState> : (
          <div className="grid gap-3 sm:grid-cols-2">
            {payslips.data.map((slip) => (
              <button key={slip.id} onClick={() => setOpenSlipId(slip.id)} className="text-left">
                <Card className="flex items-center gap-4 p-5 transition hover:ring-primary-200">
                  <span className="flex size-11 items-center justify-center rounded-xl bg-primary-50 text-primary-600"><FileText className="size-5" /></span>
                  <div className="flex-1">
                    <p className="font-medium text-slate-900">{formatPeriod(slip.period_month)}</p>
                    <p className="text-xs text-slate-500">Gross {formatTaka(slip.gross_earnings)} · Deductions {formatTaka(slip.total_deductions)}</p>
                  </div>
                  <div className="text-right">
                    <p className="text-lg font-semibold tabular-nums text-slate-900">{formatTaka(slip.net)}</p>
                    <Badge tone={slip.payment_status === 'paid' ? 'green' : 'orange'}>{slip.payment_status === 'paid' ? 'Paid' : 'Pending'}</Badge>
                  </div>
                </Card>
              </button>
            ))}
          </div>
        )}
      <PayslipDialog slipId={openSlipId} onClose={() => setOpenSlipId(null)} />
    </div>
  )
}
