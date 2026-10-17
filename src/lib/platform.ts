// Platform (SaaS) administration: types and React Query hooks used by the
// platform-admin screens and the public landing page. Every call goes through
// a database function that re-checks the caller is a platform admin.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

export type OrganizationStatus = 'active' | 'suspended' | 'inactive'
export type SubscriptionStatus = 'trial' | 'active' | 'past_due' | 'suspended' | 'cancelled' | 'expired'
export type PaymentStatus = 'due' | 'paid' | 'overdue' | 'waived' | 'refunded'
export type OrgPaymentSummary = 'none' | 'paid' | 'due' | 'overdue'
export type ApplicationStatus = 'pending' | 'approved' | 'rejected' | 'cancelled'

export interface PublicPlan {
  code: string
  name: string
  tagline: string | null
  price_per_employee: number | null
  max_employees: number | null
  trial_days: number | null
  features: string[]
}

export interface OrganizationRow {
  id: string
  name: string
  org_code: string
  status: OrganizationStatus
  created_at: string
  active_employees: number
  plan_name: string | null
  subscription_status: SubscriptionStatus | null
  payment_status: OrgPaymentSummary
}

export interface PlatformOverview {
  applications: { pending: number; approved: number; rejected: number }
  organizations: OrganizationRow[]
}

export interface ApplicationRow {
  id: string
  org_name: string
  contact_name: string
  contact_phone: string | null
  employee_range: string | null
  industry: string | null
  address: string | null
  plan_interest: string | null
  status: ApplicationStatus
  review_note: string | null
  created_at: string
  reviewed_at: string | null
  organization_id: string | null
  applicant_email: string | null
  email_confirmed: boolean
}

export interface OrgPayment {
  id: string
  period_start: string
  period_end: string
  amount: number
  status: PaymentStatus
  due_date: string
  paid_on: string | null
  method: string | null
  reference: string | null
  note: string | null
}

export interface OrganizationDetails {
  organization: {
    id: string; name: string; org_code: string; status: OrganizationStatus; timezone: string; created_at: string
    labor_regime: string | null
  }
  application: {
    contact_name: string; contact_phone: string | null; employee_range: string | null; industry: string | null
    address: string | null; plan_interest: string | null; submitted_at: string; reviewed_at: string | null
    applicant_email: string | null
  } | null
  admins: { full_name: string; email: string | null; phone: string | null; last_login_at: string | null }[]
  employees: {
    total: number; active: number; inactive: number; terminated: number; portal_users: number
    departments: number; branches: number
  }
  subscription: {
    plan_code: string; plan_name: string; status: SubscriptionStatus; billing_cycle: 'monthly' | 'yearly'
    seats: number | null; price_per_employee: number | null; started_on: string; current_period_end: string | null
    trial_ends_on: string | null; note: string | null
  } | null
  payment_status: OrgPaymentSummary
  payments: OrgPayment[]
  payment_totals: { paid: number; outstanding: number }
}

export const EMPLOYEE_RANGES = ['1-25', '26-100', '101-500', '501-1000', '1000+'] as const

export const SUBSCRIPTION_LABELS: Record<SubscriptionStatus, string> = {
  trial: 'Trial', active: 'Active', past_due: 'Past due', suspended: 'Suspended', cancelled: 'Cancelled', expired: 'Expired',
}
export const PAYMENT_METHODS = ['bank', 'bkash', 'nagad', 'rocket', 'card', 'cash', 'other'] as const

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

/** Plans shown on the landing page; works without login. */
export function usePublicPlans() {
  return useQuery({
    queryKey: ['public-plans'],
    staleTime: 60 * 60_000,
    queryFn: () => callRpc<PublicPlan[]>('get_public_plans'),
  })
}

export function usePlatformOverview() {
  return useQuery({ queryKey: ['platform', 'overview'], queryFn: () => callRpc<PlatformOverview>('platform_overview') })
}

export function usePlatformApplications(status: ApplicationStatus | null) {
  return useQuery({
    queryKey: ['platform', 'applications', status],
    queryFn: () => callRpc<ApplicationRow[]>('platform_list_applications', { p_status: status }),
  })
}

export function useOrganizationDetails(orgId: string | undefined) {
  return useQuery({
    queryKey: ['platform', 'organization', orgId],
    enabled: !!orgId,
    queryFn: () => callRpc<OrganizationDetails>('platform_organization_details', { p_org_id: orgId }),
  })
}

/** Runs a platform RPC and refreshes every platform screen afterwards. */
export function usePlatformAction<TArgs extends Record<string, unknown>, TResult = unknown>(fn: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (args: TArgs) => callRpc<TResult>(fn, args),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['platform'] }),
  })
}
