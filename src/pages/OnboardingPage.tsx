import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Navigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { errorMessage, normalizeBdPhone } from '@/lib/identity'
import type { OrgSignupRequest } from '@/lib/types'
import { useSession } from '@/stores/session'
import { Alert, AuthShell, Button, Input, PageLoader } from '@/components/ui'

const schema = z.object({
  org_name: z.string().trim().min(2, 'Enter the company name').max(200),
  contact_name: z.string().trim().min(2, 'Enter the contact person').max(120),
  contact_phone: z
    .string()
    .trim()
    .refine((v) => v === '' || normalizeBdPhone(v) !== null, 'Use 01XXXXXXXXX or +8801XXXXXXXXX'),
})
type FormValues = z.infer<typeof schema>

function useMyRequests() {
  return useQuery({
    queryKey: ['my-signup-requests'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('org_signup_requests')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(1)
      if (error) throw error
      return data as OrgSignupRequest[]
    },
  })
}

export default function OnboardingPage() {
  const { context, signOut, refreshContext } = useSession()
  const queryClient = useQueryClient()
  const requests = useMyRequests()
  const [formError, setFormError] = useState<string | null>(null)

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { org_name: '', contact_name: context?.user?.full_name ?? '', contact_phone: '' },
  })

  const submit = useMutation({
    mutationFn: async (v: FormValues) => {
      const { error } = await supabase.rpc('submit_org_signup_request', {
        p_org_name: v.org_name,
        p_contact_name: v.contact_name,
        p_contact_phone: v.contact_phone || null,
      })
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['my-signup-requests'] }),
    onError: (e) => setFormError(errorMessage(e)),
  })

  const cancel = useMutation({
    mutationFn: async (id: string) => {
      const { error } = await supabase.rpc('cancel_org_signup_request', { p_request_id: id })
      if (error) throw error
    },
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['my-signup-requests'] }),
  })

  if (context?.organization) return <Navigate to="/" replace />
  if (requests.isPending) return <PageLoader />

  const latest = requests.data?.[0]

  if (requests.isError) {
    return (
      <AuthShell title="Something went wrong">
        <Alert>{errorMessage(requests.error)}</Alert>
        <Button className="mt-4" onClick={() => requests.refetch()}>Try again</Button>
      </AuthShell>
    )
  }

  if (latest?.status === 'pending') {
    return (
      <AuthShell title="Request submitted" subtitle="We are reviewing your organization.">
        <div className="space-y-4">
          <Alert tone="info">
            <strong>{latest.org_name}</strong> was submitted on {new Date(latest.created_at).toLocaleDateString()}.
            You will get access as soon as it is approved.
          </Alert>
          <div className="flex flex-wrap gap-2">
            <Button
              variant="secondary"
              onClick={async () => {
                await requests.refetch()
                await refreshContext()
              }}
            >
              Check status
            </Button>
            <Button variant="ghost" loading={cancel.isPending} onClick={() => cancel.mutate(latest.id)}>
              Cancel request
            </Button>
            <Button variant="ghost" onClick={() => signOut()}>Sign out</Button>
          </div>
        </div>
      </AuthShell>
    )
  }

  if (latest?.status === 'approved') {
    // Approved but the context is stale: reload it.
    return (
      <AuthShell title="Your organization is ready">
        <Button className="w-full" onClick={() => refreshContext()}>Open dashboard</Button>
      </AuthShell>
    )
  }

  const { register, handleSubmit, formState: { errors } } = form

  return (
    <AuthShell title="Organization details" subtitle="Step 2 of 2: tell us about your company.">
      <form
        onSubmit={handleSubmit((v) => {
          setFormError(null)
          submit.mutate(v)
        })}
        className="space-y-4"
        noValidate
      >
        {latest?.status === 'rejected' && (
          <Alert>
            Your previous request for <strong>{latest.org_name}</strong> was not approved
            {latest.review_note ? `: ${latest.review_note}` : '.'} You can submit a new one.
          </Alert>
        )}
        {formError && <Alert>{formError}</Alert>}
        <Input label="Company name" error={errors.org_name?.message} {...register('org_name')} />
        <Input label="Contact person" error={errors.contact_name?.message} {...register('contact_name')} />
        <Input
          label="Contact mobile (optional)"
          placeholder="01XXXXXXXXX"
          error={errors.contact_phone?.message}
          {...register('contact_phone')}
        />
        <Button type="submit" loading={submit.isPending} className="w-full">
          Submit for approval
        </Button>
        <Button type="button" variant="ghost" className="w-full" onClick={() => signOut()}>
          Sign out
        </Button>
      </form>
    </AuthShell>
  )
}
