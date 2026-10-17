import { PreviewContext } from '@/lib/appContext'
import type { MyContext } from '@/lib/types'
import AppLayout from '@/components/AppLayout'

// Dev-only: shows the signed-in app shell with a mock Admin, no login needed.
const MOCK: MyContext = {
  user: {
    id: 'preview',
    email: 'admin@example.com',
    phone: null,
    full_name: 'Demo Admin',
    status: 'active',
    must_change_password: false,
  },
  organization: { id: 'preview', org_code: '482915', name: 'Demo Apparels Ltd', timezone: 'Asia/Dhaka' },
  role: { id: 'preview', name: 'Admin', system_key: 'admin' },
  permissions: [
    'audit.view', 'employees.create', 'employees.view', 'org.manage', 'org.view',
    'roles.manage', 'roles.view', 'settings.manage',
    'attendance.view_own', 'attendance.view_all', 'leave.request', 'leave.approve', 'overtime.view', 'shifts.manage',
    'payroll.view_own', 'payroll.prepare', 'compensation.view', 'payroll_settings.manage', 'tax.view_profiles',
    'pf.manage', 'gratuity.manage', 'performance.manage',
  ],
  is_platform_admin: true,
  pending_signup_request: null,
}

export default function PreviewPage() {
  return (
    <PreviewContext.Provider value={MOCK}>
      <AppLayout />
    </PreviewContext.Provider>
  )
}
