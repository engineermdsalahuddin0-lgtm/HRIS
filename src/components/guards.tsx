import type { ReactNode } from 'react'
import { Suspense, lazy } from 'react'
import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useSession } from '@/stores/session'
import { Alert, AuthShell, Button, PageLoader } from '@/components/ui'

/** Login and sign-up pages: send already signed-in users into the app. */
export function PublicOnly({ children }: { children: ReactNode }) {
  const { status, session, context } = useSession()
  if (status === 'loading') return <PageLoader />
  if (session && context) return <Navigate to="/" replace />
  return children
}

const LandingPage = lazy(() => import('@/pages/public/LandingPage'))

/**
 * Any page that needs a signed-in user. Visitors who are not signed in see the
 * public landing page at "/" and are sent to the login page everywhere else.
 */
export function RequireSession() {
  const { status, session, context, contextError, refreshContext, signOut } = useSession()
  const { pathname } = useLocation()
  if (status === 'loading') return <PageLoader />
  if (!session) {
    if (pathname === '/') return <Suspense fallback={<PageLoader />}><LandingPage /></Suspense>
    return <Navigate to="/login" replace />
  }
  if (!context?.user) {
    return (
      <AuthShell title="Could not load your account">
        <div className="space-y-4">
          <Alert>{contextError ?? 'Your account could not be loaded.'}</Alert>
          <div className="flex gap-2">
            <Button onClick={() => refreshContext()}>Try again</Button>
            <Button variant="secondary" onClick={() => signOut()}>Sign out</Button>
          </div>
        </div>
      </AuthShell>
    )
  }
  return <Outlet />
}

/** The main app: password must be changed first, and the user needs an organization. */
export function RequireAppAccess() {
  const context = useSession((s) => s.context)!
  if (context.user?.must_change_password) return <Navigate to="/change-password" replace />
  if (!context.organization && !context.is_platform_admin) return <Navigate to="/onboarding" replace />
  return <Outlet />
}

export function RequirePlatformAdmin() {
  const isPlatformAdmin = useSession((s) => s.context?.is_platform_admin)
  if (!isPlatformAdmin) return <Navigate to="/" replace />
  return <Outlet />
}

/** Hides a page from roles without the permission (UI only; the database enforces it too). */
export function RequirePermission({ permission }: { permission: string | string[] }) {
  const allowed = useSession((s) => {
    const have = s.context?.permissions ?? []
    return (Array.isArray(permission) ? permission : [permission]).some((p) => have.includes(p))
  })
  if (!allowed) return <Navigate to="/" replace />
  return <Outlet />
}
