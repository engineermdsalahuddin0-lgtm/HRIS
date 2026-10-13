import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/identity'
import type { OrgSignupRequest, SignupRequestStatus } from '@/lib/types'
import { Alert, Badge, Button, Card, EmptyState, PageLoader, cx } from '@/components/ui'

type Row = OrgSignupRequest & { applicant: { email: string | null; full_name: string } | null }

const FILTERS: { key: SignupRequestStatus | 'all'; label: string }[] = [
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
  { key: 'all', label: 'All' },
]

const STATUS_TONE = { pending: 'orange', approved: 'green', rejected: 'red', cancelled: 'slate' } as const

export default function SignupRequestsPage() {
  const queryClient = useQueryClient()
  const [filter, setFilter] = useState<SignupRequestStatus | 'all'>('pending')
  const [rejecting, setRejecting] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [actionError, setActionError] = useState<string | null>(null)

  const requests = useQuery({
    queryKey: ['signup-requests', filter],
    queryFn: async () => {
      let q = supabase
        .from('org_signup_requests')
        .select('*, applicant:user_profiles!org_signup_requests_applicant_user_id_fkey(email, full_name)')
        .order('created_at', { ascending: false })
      if (filter !== 'all') q = q.eq('status', filter)
      const { data, error } = await q
      if (error) throw error
      return data as Row[]
    },
  })

  const onDone = () => {
    setRejecting(null)
    setNote('')
    queryClient.invalidateQueries({ queryKey: ['signup-requests'] })
  }

  const approve = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('approve_org_signup_request', { p_request_id: id })
      if (error) throw error
    },
    onMutate: () => setActionError(null),
    onSuccess: onDone,
    onError: (e) => setActionError(errorMessage(e)),
  })

  const reject = useMutation({
    mutationFn: async ({ id, note }: { id: string; note: string }) => {
      const { error } = await supabase.rpc('reject_org_signup_request', { p_request_id: id, p_note: note })
      if (error) throw error
    },
    onMutate: () => setActionError(null),
    onSuccess: onDone,
    onError: (e) => setActionError(errorMessage(e)),
  })

  return (
    <div className="mx-auto max-w-6xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">Organization sign-up requests</h1>
        <p className="text-sm text-slate-500">Approving creates the organization, its default roles, and makes the applicant its Admin.</p>
      </div>

      <div className="flex flex-wrap gap-2" role="tablist">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            role="tab"
            aria-selected={filter === f.key}
            onClick={() => setFilter(f.key)}
            className={cx(
              'rounded-full px-4 py-1.5 text-sm font-medium transition',
              filter === f.key ? 'bg-primary-600 text-white' : 'bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50',
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      {actionError && <Alert>{actionError}</Alert>}

      {requests.isPending ? (
        <PageLoader />
      ) : requests.isError ? (
        <Alert>{errorMessage(requests.error)}</Alert>
      ) : requests.data.length === 0 ? (
        <EmptyState title="No requests here">New sign-ups will appear in Pending.</EmptyState>
      ) : (
        <Card className="overflow-x-auto p-0">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th className="px-4 py-3 font-medium">Organization</th>
                <th className="px-4 py-3 font-medium">Applicant</th>
                <th className="px-4 py-3 font-medium">Contact</th>
                <th className="px-4 py-3 font-medium">Submitted</th>
                <th className="px-4 py-3 font-medium">Status</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100">
              {requests.data.map((r) => (
                <tr key={r.id} className="align-top">
                  <td className="px-4 py-3 font-medium text-slate-900">{r.org_name}</td>
                  <td className="px-4 py-3 text-slate-600">{r.applicant?.email ?? '-'}</td>
                  <td className="px-4 py-3 text-slate-600">
                    {r.contact_name}
                    {r.contact_phone && <div className="text-xs text-slate-400">{r.contact_phone}</div>}
                  </td>
                  <td className="px-4 py-3 text-slate-600">{new Date(r.created_at).toLocaleString()}</td>
                  <td className="px-4 py-3">
                    <Badge tone={STATUS_TONE[r.status]}>{r.status}</Badge>
                    {r.review_note && <div className="mt-1 max-w-48 text-xs text-slate-400">{r.review_note}</div>}
                  </td>
                  <td className="px-4 py-3">
                    {r.status === 'pending' &&
                      (rejecting === r.id ? (
                        <form
                          className="flex min-w-64 flex-col gap-2"
                          onSubmit={(e) => {
                            e.preventDefault()
                            if (note.trim()) reject.mutate({ id: r.id, note: note.trim() })
                          }}
                        >
                          <input
                            autoFocus
                            value={note}
                            onChange={(e) => setNote(e.target.value)}
                            placeholder="Reason (shown to the applicant)"
                            aria-label="Rejection reason"
                            className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm outline-none focus:border-primary-500"
                          />
                          <div className="flex gap-2">
                            <Button type="submit" variant="danger" loading={reject.isPending} disabled={!note.trim()}>
                              Reject
                            </Button>
                            <Button type="button" variant="ghost" onClick={() => setRejecting(null)}>
                              Cancel
                            </Button>
                          </div>
                        </form>
                      ) : (
                        <div className="flex justify-end gap-2">
                          <Button
                            loading={approve.isPending && approve.variables === r.id}
                            onClick={() => {
                              if (confirm(`Approve "${r.org_name}"? This creates the organization.`)) approve.mutate(r.id)
                            }}
                          >
                            Approve
                          </Button>
                          <Button variant="secondary" onClick={() => setRejecting(r.id)}>
                            Reject
                          </Button>
                        </div>
                      ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  )
}
