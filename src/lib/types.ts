export type SystemRoleKey = 'admin' | 'hr_manager' | 'manager' | 'employee'

export interface MyContext {
  user: {
    id: string
    email: string | null
    phone: string | null
    full_name: string
    status: 'active' | 'disabled'
    must_change_password: boolean
  } | null
  organization: { id: string; org_code: string; name: string; timezone: string } | null
  role: { id: string; name: string; system_key: SystemRoleKey | null } | null
  permissions: string[]
  is_platform_admin: boolean
  pending_signup_request: { id: string; org_name: string; status: string; created_at: string } | null
}

export type SignupRequestStatus = 'pending' | 'approved' | 'rejected' | 'cancelled'

export interface OrgSignupRequest {
  id: string
  applicant_user_id: string
  org_name: string
  contact_name: string
  contact_phone: string | null
  timezone: string
  status: SignupRequestStatus
  review_note: string | null
  reviewed_at: string | null
  organization_id: string | null
  created_at: string
}
