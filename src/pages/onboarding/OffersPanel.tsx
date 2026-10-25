// Offers & joining tab (HR): selected applicants → offer (maker-checker) → pre-joining form →
// employee → joining checklist; and closing the hiring when it is all done.
import { useState } from 'react'
import { BadgeCheck, FileSignature, Send, Trash2, UserCheck } from 'lucide-react'
import type { JobPost, OfferRow } from '@/onboarding-process/core/types'
import { OFFER_STATUS_LABEL, PREHIRE_STATUS_LABEL } from '@/onboarding-process/core/joining'
import { APPLICANT_STATUS_LABEL } from '@/onboarding-process/core/jobPost'
import { useOffers, useOnboardingCases } from '@/lib/recruit'
import { errorMessage } from '@/lib/identity'
import { formatDate } from '@/lib/options'
import { formatTaka } from '@/lib/payroll'
import { Alert, Badge, Button, EmptyState, Spinner } from '@/components/ui'
import { Table, td, th } from '@/components/kit'
import {
  ApproveOfferDialog, ClosePurgeDialog, ConvertDialog, OfferDialog, PrehireDialog, SendOfferDialog, WithdrawOfferDialog,
} from './dialogs/OfferDialogs'
import { OnboardingCaseDialog } from './dialogs/OnboardingCaseDialog'

type Open = { kind: 'offer' | 'approve' | 'send' | 'withdraw' | 'prehire' | 'convert'; row: OfferRow } | { kind: 'case'; caseId: string } | { kind: 'purge' }

export function OffersPanel({ post }: { post: JobPost }) {
  const offers = useOffers(post.id)
  const cases = useOnboardingCases(post.id)
  const [open, setOpen] = useState<Open | null>(null)
  if (offers.isPending) return <div className="flex justify-center py-8 text-primary-600"><Spinner /></div>
  if (offers.isError) return <Alert>{errorMessage(offers.error)}</Alert>
  const o = offers.data
  const caseOf = (applicantId: string) => cases.data?.find((c) => c.applicant_id === applicantId)

  const actions = (r: OfferRow) => {
    const of = r.offer
    const out: React.ReactNode[] = []
    const btn = (label: string, kind: Exclude<Open, { kind: 'case' } | { kind: 'purge' }>['kind'], variant: 'primary' | 'secondary' | 'ghost' = 'secondary', icon?: React.ReactNode) =>
      out.push(<Button key={kind} variant={variant} onClick={() => setOpen({ kind, row: r })}>{icon}{label}</Button>)
    const active = of && ['draft', 'approved', 'sent', 'accepted'].includes(of.status)
    if (r.status === 'selected' && !active) btn('Prepare offer', 'offer', 'primary', <FileSignature className="size-4" />)
    if (of?.status === 'draft') {
      if (o.can.approve && of.created_by !== o.can.user_id) btn('Approve', 'approve', 'primary', <BadgeCheck className="size-4" />)
      btn('Edit', 'offer', 'ghost')
    }
    if (of?.status === 'approved') btn('Send offer', 'send', 'primary', <Send className="size-4" />)
    if (of?.status === 'sent') btn('Send again', 'send', 'ghost')
    if (of && ['draft', 'approved', 'sent'].includes(of.status)) btn('Withdraw', 'withdraw', 'ghost')
    if (r.prehire && ['submitted', 'returned', 'verified'].includes(r.prehire.status) && !r.prehire.employee_id) btn(r.prehire.status === 'submitted' ? 'Check form' : 'View form', 'prehire', r.prehire.status === 'submitted' ? 'primary' : 'ghost')
    if (r.prehire?.status === 'verified' && !r.prehire.employee_id) btn('Make employee', 'convert', 'primary', <UserCheck className="size-4" />)
    const c = caseOf(r.applicant_id)
    if (c) out.push(<Button key="case" variant={c.status === 'open' ? 'primary' : 'ghost'} onClick={() => setOpen({ kind: 'case', caseId: c.id })}>Joining {c.tasks_done}/{c.tasks_total}</Button>)
    return out
  }

  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <p className="text-sm text-slate-600">Seats: <span className="font-semibold text-slate-900">{o.seats_taken} of {o.seats}</span> taken.
          Decide on the Results tab; offers need approval by someone other than the person who prepared them.</p>
        <Button variant="ghost" className="ml-auto" onClick={() => setOpen({ kind: 'purge' })}><Trash2 className="size-4" />Close hiring & delete data</Button>
      </div>
      {o.rows.length === 0 ? <EmptyState title="Nobody selected yet">Select applicants on the Results tab.</EmptyState> : (
        <Table minWidth={980} head={(
          <tr><th className={th}>Applicant</th><th className={th}>Offer</th><th className={th}>Pre-joining</th><th className={th}>Status</th><th className={th} /></tr>
        )}>
          {o.rows.map((r) => (
            <tr key={r.applicant_id} className="align-top">
              <td className={td}><p className="font-medium text-slate-900">{r.full_name}</p>
                <p className="text-xs text-slate-400">{r.decision?.decision === 'waitlist' ? 'Waitlist' : r.decision?.decision ?? ''}{r.decision?.composite != null ? ` · score ${r.decision.composite}` : ''}</p></td>
              <td className={td}>{r.offer ? (
                <div className="space-y-0.5 text-xs">
                  <Badge tone={r.offer.status === 'accepted' ? 'green' : ['declined', 'expired', 'withdrawn'].includes(r.offer.status) ? 'red' : 'orange'}>{OFFER_STATUS_LABEL[r.offer.status]}</Badge>
                  <p className="text-slate-700">{formatTaka(r.offer.gross)} · joins {formatDate(r.offer.joining_date)}</p>
                  <p className="text-slate-400">By {r.offer.prepared_by_name ?? '—'}{r.offer.approved_by_name ? ` · approved by ${r.offer.approved_by_name}` : ''}</p>
                  {r.offer.status === 'draft' && r.offer.approval_note && <p className="text-amber-700">Sent back: {r.offer.approval_note}</p>}
                  {r.offer.response_note && <p className="italic text-slate-500">“{r.offer.response_note}”</p>}
                </div>
              ) : <span className="text-xs text-slate-400">—</span>}</td>
              <td className={td}>{r.prehire ? <Badge tone={r.prehire.status === 'verified' ? 'green' : r.prehire.status === 'submitted' ? 'orange' : 'slate'}>{PREHIRE_STATUS_LABEL[r.prehire.status]}</Badge>
                : <span className="text-xs text-slate-400">—</span>}</td>
              <td className={td}><Badge tone={r.status === 'joined' ? 'green' : 'slate'}>{APPLICANT_STATUS_LABEL[r.status]}</Badge></td>
              <td className={`${td} text-right`}><div className="flex flex-wrap justify-end gap-1.5">{actions(r)}</div></td>
            </tr>
          ))}
        </Table>
      )}

      {open?.kind === 'offer' && <OfferDialog row={open.row} onClose={() => setOpen(null)} />}
      {open?.kind === 'approve' && <ApproveOfferDialog row={open.row} onClose={() => setOpen(null)} />}
      {open?.kind === 'send' && <SendOfferDialog row={open.row} onClose={() => setOpen(null)} />}
      {open?.kind === 'withdraw' && <WithdrawOfferDialog row={open.row} onClose={() => setOpen(null)} />}
      {open?.kind === 'prehire' && open.row.prehire && <PrehireDialog prehireId={open.row.prehire.id} name={open.row.full_name} onClose={() => setOpen(null)} />}
      {open?.kind === 'convert' && <ConvertDialog row={open.row} onClose={() => setOpen(null)} onConverted={(caseId) => setOpen({ kind: 'case', caseId })} />}
      {open?.kind === 'case' && <OnboardingCaseDialog caseId={open.caseId} onClose={() => setOpen(null)} />}
      {open?.kind === 'purge' && <ClosePurgeDialog postId={post.id} onClose={() => setOpen(null)} />}
    </section>
  )
}
