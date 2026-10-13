import { createBrowserRouter, Navigate } from 'react-router-dom'
import AppLayout from '@/components/AppLayout'
import { PublicOnly, RequireAppAccess, RequirePlatformAdmin, RequireSession } from '@/components/guards'
import LoginPage from '@/pages/LoginPage'
import SignupPage from '@/pages/SignupPage'
import ChangePasswordPage from '@/pages/ChangePasswordPage'
import OnboardingPage from '@/pages/OnboardingPage'
import DashboardPage from '@/pages/DashboardPage'
import SignupRequestsPage from '@/pages/platform/SignupRequestsPage'
import PreviewPage from '@/pages/PreviewPage'

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
