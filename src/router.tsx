import { createBrowserRouter, Navigate } from 'react-router-dom'
import AppLayout from '@/components/AppLayout'
import {
  PublicOnly, RequireAppAccess, RequirePermission, RequirePlatformAdmin, RequireSession,
} from '@/components/guards'
import LoginPage from '@/pages/LoginPage'
import SignupPage from '@/pages/SignupPage'
import ChangePasswordPage from '@/pages/ChangePasswordPage'
import OnboardingPage from '@/pages/OnboardingPage'
import DashboardPage from '@/pages/DashboardPage'
import SignupRequestsPage from '@/pages/platform/SignupRequestsPage'
import PreviewPage from '@/pages/PreviewPage'
import OrganizationPage from '@/pages/organization/OrganizationPage'
import RolesPage from '@/pages/settings/RolesPage'
import SettingsPage from '@/pages/settings/SettingsPage'
import EmployeesPage from '@/pages/employees/EmployeesPage'
import AddEmployeePage from '@/pages/employees/AddEmployeePage'
import EmployeeProfilePage, { MyProfileRedirect } from '@/pages/employees/EmployeeProfilePage'
import AuditLogPage from '@/pages/audit/AuditLogPage'

const guarded = (permission: string, path: string, element: React.ReactNode) => ({
  element: <RequirePermission permission={permission} />,
  children: [{ path, element }],
})

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
              { index: true, element: <DashboardPage /> },
              { path: '/me', element: <MyProfileRedirect /> },
              // Profiles: the database decides who may see which employee (self, or employees.view).
              { path: '/employees/:id', element: <EmployeeProfilePage /> },
              guarded('employees.view', '/employees', <EmployeesPage />),
              guarded('employees.create', '/employees/new', <AddEmployeePage />),
              guarded('org.view', '/organization', <OrganizationPage />),
              guarded('roles.view', '/settings/roles', <RolesPage />),
              guarded('settings.manage', '/settings', <SettingsPage />),
              guarded('audit.view', '/audit', <AuditLogPage />),
              {
                element: <RequirePlatformAdmin />,
                children: [{ path: '/platform/requests', element: <SignupRequestsPage /> }],
              },
            ],
          },
        ],
      },
    ],
  },
  // Dev-only: view the app shell without signing in.
  ...(import.meta.env.DEV
    ? [{ path: '/preview', element: <PreviewPage />, children: [{ index: true, element: <DashboardPage /> }] }]
    : []),
  { path: '*', element: <Navigate to="/" replace /> },
])
