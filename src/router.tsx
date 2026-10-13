import type { ComponentType, ReactNode } from 'react'
import { Suspense, lazy } from 'react'
import { createBrowserRouter, Navigate } from 'react-router-dom'
import AppLayout from '@/components/AppLayout'
import {
  PublicOnly, RequireAppAccess, RequirePermission, RequirePlatformAdmin, RequireSession,
} from '@/components/guards'
import { PageLoader } from '@/components/ui'
import LoginPage from '@/pages/LoginPage'
import SignupPage from '@/pages/SignupPage'
import ChangePasswordPage from '@/pages/ChangePasswordPage'
import OnboardingPage from '@/pages/OnboardingPage'
import PreviewPage from '@/pages/PreviewPage'

// Feature pages load on demand to keep the first download small.
const page = (load: () => Promise<{ default: ComponentType }>) => {
  const C = lazy(load)
  return (
    <Suspense fallback={<PageLoader />}>
      <C />
    </Suspense>
  )
}
const named = <K extends string>(load: () => Promise<Record<K, ComponentType>>, name: K) =>
  page(() => load().then((m) => ({ default: m[name] })))

const guarded = (permission: string | string[], path: string, element: ReactNode) => ({
  element: <RequirePermission permission={permission} />,
  children: [{ path, element }],
})

const TIME_SETUP = [
  'shifts.manage', 'roster.manage', 'holidays.manage', 'attendance.settings', 'geofences.manage',
  'leave.manage_types', 'overtime.manage_policy', 'attendance.lock_period', 'attendance.qr_display',
]

export const router = createBrowserRouter([
  { path: '/login', element: <PublicOnly><LoginPage /></PublicOnly> },
  { path: '/signup', element: <PublicOnly><SignupPage /></PublicOnly> },
  {
    element: <RequireSession />,
    children: [
      { path: '/change-password', element: <ChangePasswordPage /> },
      { path: '/onboarding', element: <OnboardingPage /> },
      {
        element: <RequireAppAccess />,
        children: [
          {
            element: <AppLayout />,
            children: [
              { index: true, element: page(() => import('@/pages/DashboardPage')) },
              { path: '/me', element: named(() => import('@/pages/employees/EmployeeProfilePage'), 'MyProfileRedirect') },
              // Profiles: the database decides who may see which employee (self, or employees.view).
              { path: '/employees/:id', element: page(() => import('@/pages/employees/EmployeeProfilePage')) },
              guarded('employees.view', '/employees', page(() => import('@/pages/employees/EmployeesPage'))),
              guarded('employees.create', '/employees/new', page(() => import('@/pages/employees/AddEmployeePage'))),
              guarded('org.view', '/organization', page(() => import('@/pages/organization/OrganizationPage'))),
              guarded('roles.view', '/settings/roles', page(() => import('@/pages/settings/RolesPage'))),
              guarded('settings.manage', '/settings', page(() => import('@/pages/settings/SettingsPage'))),
              guarded('audit.view', '/audit', page(() => import('@/pages/audit/AuditLogPage'))),
              // Part 2: time & attendance
              guarded('attendance.view_own', '/attendance/me', page(() => import('@/pages/attendance/MyAttendancePage'))),
              guarded('attendance.view_own', '/attendance/qr', named(() => import('@/pages/attendance/QrPages'), 'QrCheckinPage')),
              guarded('attendance.qr_display', '/attendance/qr-display/:officeId', named(() => import('@/pages/attendance/QrPages'), 'QrDisplayPage')),
              guarded(['attendance.view_team', 'attendance.view_all'], '/attendance', page(() => import('@/pages/attendance/AttendancePage'))),
              guarded(['leave.request', 'leave.approve', 'leave.view_all'], '/leave', page(() => import('@/pages/leave/LeavePage'))),
              guarded(['overtime.view', 'overtime.approve'], '/overtime', page(() => import('@/pages/overtime/OvertimePage'))),
              guarded(TIME_SETUP, '/time', page(() => import('@/pages/time/TimeSetupPage'))),
              {
                element: <RequirePlatformAdmin />,
                children: [{ path: '/platform/requests', element: page(() => import('@/pages/platform/SignupRequestsPage')) }],
              },
            ],
          },
        ],
      },
    ],
  },
  // Dev-only: view the app shell without signing in.
  ...(import.meta.env.DEV
    ? [{ path: '/preview', element: <PreviewPage />, children: [{ index: true, element: page(() => import('@/pages/DashboardPage')) }] }]
    : []),
  { path: '*', element: <Navigate to="/" replace /> },
])
