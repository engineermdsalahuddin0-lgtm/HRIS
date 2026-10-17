import { useMemo, useState } from 'react'
import { FileText, Percent, UserPlus } from 'lucide-react'
import { errorMessage } from '@/lib/identity'
import { formatTaka } from '@/lib/payroll'
import { formatPeriod } from '@/lib/payrollRuns'
import { formatDate, today } from '@/lib/options'
import { useEmployeeOptions } from '@/lib/hr'
import type { PfMemberRow, VestingBand } from '@/lib/statutory'
import { usePfMembers, usePfStatement, usePfWithdrawalPreview, useStatutoryAction, useStatutorySettings } from '@/lib/statutory'
import { ReferenceChips } from '@/components/references'
import { Alert, Badge, Button, Card, EmptyState, Input, PageLoader, Spinner, cx } from '@/components/ui'
import { Modal, PageHeader, Select, Table, Tabs, td, th } from '@/components/kit'

/** Provident fund: members and balances, statements, interest and the withdrawal calculator. */
export default function ProvidentFundPage() {
  const [tab, setTab] = useState<'members' | 'withdrawal'>('members')
  const settings = useStatutorySettings()
  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <PageHeader title="Provident fund" description="Members, contributions posted from locked payroll, interest and what a member takes on leaving." />
      {settings.data && !settings.data.switches.pf_enabled && (
        <Alert tone="info">The provident fund is switched off, so payroll adds no PF lines. The Admin can switch it on in Statutory settings.</Alert>
      )}
      {settings.data && (
        <Card className="grid gap-4 p-4 sm:grid-cols-4">
          <Fact label="Employee rate" value={`${settings.data.pf.employee_rate}% of ${settings.data.pf.basis}`} />
          <Fact label="Employer rate" value={`${settings.data.pf.employer_rate}% of ${settings.data.pf.basis}`} />
          <Fact label="Interest" value={`${settings.data.pf.interest_rate}% a year`} />
          <div><ReferenceChips keys={['labour.provident_fund', 'policy.pf_rules', 'tax.recognised_pf']} /></div>
        </Card>
      )}
      <Tabs tabs={[{ key: 'members' as const, label: 'Members & balances' }, { key: 'withdrawal' as const, label: 'Withdrawal calculator' }]}
        value={tab} onChange={setTab} />
      {tab === 'members' ? <MembersTab /> : <WithdrawalTab />}
    </div>
  )
}

function Fact({ label, value }: { label: string; value: string }) {
  return <div><p className="text-xs text-slate-500">{label}</p><p className="font-medium capitalize text-slate-900">{value}</p></div>
}

function MembersTab() {
  const members = usePfMembers()
  const [enrolOpen, setEnrolOpen] = useState(false)
  const [interestOpen, setInterestOpen] = useState(false)
  const [statementFor, setStatementFor] = useState<PfMemberRow | null>(null)
  const setMembership = useStatutoryAction<{ p_employee_id: string; p_enrolled_from: string; p_status: string }>('set_pf_membership')
  const rows = members.data ?? []
  const totals = useMemo(() => rows.reduce((t, r) => ({
    employee: t.employee + Number(r.employee_total), employer: t.employer + Number(r.employer_total), interest: t.interest + Number(r.interest_total),
  }), { employee: 0, employer: 0, interest: 0 }), [rows])
  if (members.isPending) return <PageLoader />
  if (members.isError) return <Alert>{errorMessage(members.error)}</Alert>
  const fund = totals.employee + totals.employer + totals.interest
  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-4">
        <Kpi label="Members" value={String(rows.filter((r) => r.member_status === 'active').length)} />
        <Kpi label="Employee contributions" value={formatTaka(totals.employee)} />
        <Kpi label="Employer contributions" value={formatTaka(totals.employer)} />
        <Kpi label="Fund balance" value={formatTaka(fund)} accent />
      </div>
      {fund > 0 && (
        <div className="flex h-3 overflow-hidden rounded-full" role="img" aria-label="Fund split: employee, employer, interest">
          <div className="bg-sky-500" style={{ width: `${(totals.employee / fund) * 100}%` }} />
          <div className="bg-primary-500" style={{ width: `${(totals.employer / fund) * 100}%` }} />
          <div className="bg-green-500" style={{ width: `${(totals.interest / fund) * 100}%` }} />
        </div>
      )}
      <div className="flex flex-wrap justify-end gap-2">
        <Button variant="secondary" onClick={() => setInterestOpen(true)}><Percent className="size-4" />Post yearly interest</Button>
        <Button onClick={() => setEnrolOpen(true)}><UserPlus className="size-4" />Enrol member</Button>
      </div>
      {setMembership.isError && <Alert>{errorMessage(setMembership.error)}</Alert>}
      <Table minWidth={820} head={
        <tr><th className={th}>Employee</th><th className={th}>Membership</th><th className={`${th} text-right`}>Own</th>
          <th className={`${th} text-right`}>Employer</th><th className={`${th} text-right`}>Interest</th><th className={th} /></tr>
      }>
        {rows.map((row) => (
          <tr key={row.employee_id}>
            <td className={td}><p className="font-medium text-slate-900">{row.full_name}</p>
              <p className="text-xs text-slate-400"><span className="font-mono">{row.card_id}</span> · joined {formatDate(row.join_date)}</p></td>
            <td className={td}>
              {row.member_status === 'active' ? <Badge tone="green">Since {formatDate(row.enrolled_from)}</Badge>
                : row.member_status === 'left' ? <Badge>Left {formatDate(row.left_on)}</Badge>
                : <span className="text-slate-400">Not a member</span>}
            </td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.employee_total)}</td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.employer_total)}</td>
            <td className={`${td} text-right tabular-nums`}>{formatTaka(row.interest_total)}</td>
            <td className={`${td} whitespace-nowrap text-right`}>
              <Button variant="ghost" onClick={() => setStatementFor(row)} aria-label={`Statement of ${row.full_name}`}><FileText className="size-4" /></Button>
              {row.member_status === 'active' && (
                <Button variant="ghost" loading={setMembership.isPending}
                  onClick={() => confirm(`Mark ${row.full_name} as left the fund?`) && setMembership.mutate({
                    p_employee_id: row.employee_id, p_enrolled_from: row.enrolled_from!, p_status: 'left' })}>Mark left</Button>
              )}
            </td>
          </tr>
        ))}
      </Table>
      {enrolOpen && <EnrolDialog onClose={() => setEnrolOpen(false)} members={rows} />}
      {interestOpen && <InterestDialog onClose={() => setInterestOpen(false)} />}
      {statementFor && <StatementDialog member={statementFor} onClose={() => setStatementFor(null)} />}
    </div>
  )
}

function Kpi({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div className={cx('rounded-2xl p-4 ring-1', accent ? 'bg-primary-600 text-white ring-primary-600' : 'bg-white ring-slate-200')}>
      <p className={cx('text-xs', accent ? 'text-primary-100' : 'text-slate-500')}>{label}</p>
      <p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
    </div>
  )
}

function EnrolDialog({ onClose, members }: { onClose: () => void; members: PfMemberRow[] }) {
  const save = useStatutoryAction<{ p_employee_id: string; p_enrolled_from: string; p_status: string }>('set_pf_membership')
  const candidates = members.filter((m) => m.member_status !== 'active')
  const [employeeId, setEmployeeId] = useState('')
  const [from, setFrom] = useState(today().slice(0, 8) + '01')
  return (
    <Modal open onClose={onClose} title="Enrol in the provident fund"
      footer={<>
        <Button variant="secondary" onClick={onClose}>Cancel</Button>
        <Button loading={save.isPending} disabled={!employeeId || !from}
          onClick={() => save.mutate({ p_employee_id: employeeId, p_enrolled_from: from, p_status: 'active' }, { onSuccess: onClose })}>Enrol</Button>
      </>}>
      <div className="space-y-4">
        {save.isError && <Alert>{errorMessage(save.error)}</Alert>}
        <Select label="Employee" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} placeholder="Choose…"
          options={candidates.map((m) => ({ value: m.employee_id, label: `${m.full_name} (${m.card_id})` }))} />
        <Input label="Contributions start from" type="date" value={from} onChange={(e) => setFrom(e.target.value)}
          hint="Payroll deducts PF for months on or after this date (and after the minimum service)." />
      </div>
    </Modal>
  )
}

function InterestDialog({ onClose }: { onClose: () => void }) {
  const post = useStatutoryAction<{ p_as_of: string }, number>('post_pf_interest')
  const [asOf, setAsOf] = useState(today())
  return (
    <Modal open onClose={onClose} title="Post yearly interest"
      description="Adds interest at the PF settings rate on every member's balance at this date. Once per date."
      footer={<>
        <Button variant="secondary" onClick={onClose}>Close</Button>
        <Button loading={post.isPending} disabled={post.isSuccess} onClick={() => post.mutate({ p_as_of: asOf })}>Post interest</Button>
      </>}>
      <div className="space-y-4">
        {post.isError && <Alert>{errorMessage(post.error)}</Alert>}
        {post.isSuccess && <Alert tone="success">Interest posted for {post.data} member(s).</Alert>}
        <Input label="Balance date" type="date" max={today()} value={asOf} onChange={(e) => setAsOf(e.target.value)} />
      </div>
    </Modal>
  )
}

function StatementDialog({ member, onClose }: { member: PfMemberRow; onClose: () => void }) {
  const statement = usePfStatement(member.employee_id)
  return (
    <Modal open onClose={onClose} size="lg" title={`PF statement · ${member.full_name}`}>
      {statement.isPending ? <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
        : statement.isError ? <Alert>{errorMessage(statement.error)}</Alert>
        : statement.data.rows.length === 0 ? <EmptyState title="No contributions yet">Rows appear when a payroll run is locked.</EmptyState> : (
          <Table minWidth={560} head={<tr><th className={th}>Month</th><th className={`${th} text-right`}>Own</th>
            <th className={`${th} text-right`}>Employer</th><th className={`${th} text-right`}>Interest</th><th className={`${th} text-right`}>Balance</th></tr>}>
            {statement.data.rows.map((row) => (
              <tr key={`${row.period_month}-${row.entry_type}`}>
                <td className={td}>{formatPeriod(row.period_month)}{row.entry_type === 'interest' && <span className="text-xs text-green-700"> · interest</span>}</td>
                <td className={`${td} text-right tabular-nums`}>{formatTaka(row.employee_amount)}</td>
                <td className={`${td} text-right tabular-nums`}>{formatTaka(row.employer_amount)}</td>
                <td className={`${td} text-right tabular-nums`}>{formatTaka(row.interest_amount)}</td>
                <td className={`${td} text-right font-medium tabular-nums`}>{formatTaka(row.balance)}</td>
              </tr>
            ))}
          </Table>
        )}
    </Modal>
  )
}

function WithdrawalTab() {
  const employees = useEmployeeOptions()
  const [employeeId, setEmployeeId] = useState('')
  const [leaving, setLeaving] = useState(today())
  const preview = usePfWithdrawalPreview(employeeId, leaving)
  return (
    <div className="grid gap-6 lg:grid-cols-[320px_1fr]">
      <Card className="h-fit space-y-4">
        <Select label="Member" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)} placeholder="Choose…"
          options={(employees.data ?? []).map((e) => ({ value: e.id, label: `${e.full_name} (${e.card_id})` }))} />
        <Input label="Leaving date" type="date" value={leaving} onChange={(e) => setLeaving(e.target.value)} />
      </Card>
      <div>
        {!employeeId ? <EmptyState title="Choose a member to see the payout" />
          : preview.isPending ? <div className="flex justify-center py-16 text-primary-600"><Spinner /></div>
          : preview.isError ? <Alert>{errorMessage(preview.error)}</Alert> : (
            <Card className="space-y-5">
              <p className="text-sm text-slate-600">{preview.data.service_years} completed year(s) of service
                ({formatDate(preview.data.join_date)} – {formatDate(preview.data.leaving_date)})</p>
              <VestingScale vesting={preview.data.vesting} years={preview.data.service_years} />
              <ol className="space-y-2 text-sm">
                <Step n={1} label="Own contributions (always paid in full)" value={preview.data.employee_portion} />
                <Step n={2} label={`Employer contributions × ${preview.data.vested_percent}% vested`}
                  value={preview.data.employer_vested} note={`${formatTaka(preview.data.employer_portion)} × ${preview.data.vested_percent}%`} />
                <Step n={3} label="Interest credited" value={preview.data.interest} />
                <li className="flex items-center justify-between rounded-xl bg-primary-600 p-3 font-semibold text-white">
                  <span>Payable on leaving</span><span className="tabular-nums">{formatTaka(preview.data.total)}</span>
                </li>
              </ol>
              <ReferenceChips keys={preview.data.references} />
            </Card>
          )}
      </div>
    </div>
  )
}

function Step({ n, label, value, note }: { n: number; label: string; value: number; note?: string }) {
  return (
    <li className="flex items-start justify-between gap-3 rounded-xl p-3 ring-1 ring-slate-200">
      <span><span className="mr-2 inline-flex size-5 items-center justify-center rounded-full bg-slate-900 text-[10px] text-white">{n}</span>{label}
        {note && <span className="block pl-7 text-xs text-slate-500">{note}</span>}</span>
      <span className="font-medium tabular-nums">{formatTaka(value)}</span>
    </li>
  )
}

/** Vesting schedule as steps, with the member's position marked. */
export function VestingScale({ vesting, years }: { vesting: VestingBand[]; years: number }) {
  const bands = [...vesting].sort((a, b) => a.min_years - b.min_years)
  return (
    <div>
      <p className="mb-2 text-xs font-medium text-slate-500">Employer share vesting by completed years</p>
      <div className="flex gap-1">
        {bands.map((band, index) => {
          const next = bands[index + 1]
          const reached = years >= band.min_years && (!next || years < next.min_years)
          return (
            <div key={band.min_years} className={cx('flex-1 rounded-lg p-2 text-center text-xs ring-1',
              reached ? 'bg-primary-600 text-white ring-primary-600' : 'bg-slate-50 text-slate-600 ring-slate-200')}>
              <p className="font-semibold">{band.percent}%</p>
              <p>{next ? `${band.min_years}–${next.min_years - 1} y` : `${band.min_years}+ y`}</p>
            </div>
          )
        })}
      </div>
    </div>
  )
}
