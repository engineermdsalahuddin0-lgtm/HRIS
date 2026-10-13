import { useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import type { LucideIcon } from 'lucide-react'
import {
  Bell,
  Building2,
  Inbox,
  LayoutDashboard,
  LogOut,
  Menu,
  ScrollText,
  Settings,
  ShieldCheck,
  UserRound,
  Users,
  X,
} from 'lucide-react'
import { useSession } from '@/stores/session'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { Badge, cx } from '@/components/ui'

interface NavItem {
  to: string
  label: string
  icon: LucideIcon
  /** Shown only when the user's role has this permission (UI only; the DB enforces it). */
  permission?: string
  platformOnly?: boolean
  /** Build step that delivers this screen; until then it is shown as "Soon". */
  soon?: string
}

const NAV: NavItem[] = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/me', label: 'My profile', icon: UserRound },
  { to: '/employees', label: 'Employees', icon: Users, permission: 'employees.view' },
  { to: '/organization', label: 'Organization', icon: Building2, permission: 'org.view' },
  { to: '/settings/roles', label: 'Roles & access', icon: ShieldCheck, permission: 'roles.view' },
  { to: '/audit', label: 'Audit log', icon: ScrollText, permission: 'audit.view' },
  { to: '/settings', label: 'Settings', icon: Settings, permission: 'settings.manage' },
  { to: '/platform/requests', label: 'Sign-up requests', icon: Inbox, platformOnly: true },
]

const TITLES: [string, string][] = [
  ['/employees/new', 'Add employee'],
  ['/employees', 'Employees'],
  ['/organization', 'Organization'],
  ['/settings/roles', 'Roles & access'],
  ['/settings', 'Settings'],
  ['/audit', 'Audit log'],
  ['/platform/requests', 'Sign-up requests'],
  ['/me', 'My profile'],
  ['/', 'Dashboard'],
]
const titleFor = (path: string) => TITLES.find(([prefix]) => path === prefix || (prefix !== '/' && path.startsWith(prefix)))?.[1] ?? 'Dashboard'

function useNavItems() {
  const context = useMyContext()
  return NAV.filter((i) => {
    if (i.platformOnly) return context.is_platform_admin
    if (!context.organization) return false
    return !i.permission || context.permissions.includes(i.permission)
  })
}

/** In the rail, labels appear when the rail expands (hover or keyboard focus); in the drawer they always show. */
function NavList({ rail, onNavigate }: { rail: boolean; onNavigate?: () => void }) {
  const items = useNavItems()
  const isPreview = useIsPreview()
  const label = rail
    ? 'opacity-0 transition-opacity duration-150 group-hover/rail:opacity-100 group-focus-within/rail:opacity-100'
    : ''

  return (
    <nav className="space-y-1" aria-label="Main">
      {items.map(({ to, label: text, icon: Icon, soon }) => {
        const inner = (
          <>
            <Icon className="size-5 shrink-0" aria-hidden />
            <span className={cx('flex-1 truncate', label)}>{text}</span>
            {soon && (
              <span className={cx('rounded-md bg-slate-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-slate-500', label)}>
                Soon
              </span>
            )}
          </>
        )
        const base = 'flex h-11 items-center gap-3 rounded-xl px-3 text-sm font-medium whitespace-nowrap'
        if (soon) {
          return (
            <div key={to} className={cx(base, 'cursor-not-allowed text-slate-400')} title={`${text}: arrives in ${soon}`}>
              {inner}
            </div>
          )
        }
        return (
          <NavLink
            key={to}
            to={isPreview && to === '/' ? '/preview' : to}
            end={to === '/' || to === '/settings'}
            onClick={onNavigate}
            title={text}
            className={({ isActive }) =>
              cx(
                base,
                'transition-colors',
                isActive ? 'bg-primary-50 text-primary-700' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900',
              )
            }
          >
            {inner}
          </NavLink>
        )
      })}
    </nav>
  )
}

function Brand({ rail }: { rail: boolean }) {
  return (
    <div className="flex h-16 items-center gap-3 px-[18px]">
      <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary-600 text-lg font-bold text-white">
        O
      </div>
      <span
        className={cx(
          'whitespace-nowrap text-lg font-semibold text-slate-900',
          rail && 'opacity-0 transition-opacity duration-150 group-hover/rail:opacity-100 group-focus-within/rail:opacity-100',
        )}
      >
        Olympus HRIS
      </span>
    </div>
  )
}

export default function AppLayout() {
  const context = useMyContext()
  const isPreview = useIsPreview()
  const signOut = useSession((s) => s.signOut)
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const [drawerOpen, setDrawerOpen] = useState(false)

  const user = context.user!
  const displayName = user.full_name || user.email || user.phone || 'User'
  const initials = displayName
    .split(/\s+/)
    .map((p) => p[0])
    .slice(0, 2)
    .join('')
    .toUpperCase()
  const handleSignOut = () => (isPreview ? navigate('/login') : signOut())

  return (
    <div className="min-h-screen">
      {/* Desktop: icon rail that expands over the content on hover or keyboard focus. */}
      <aside
        className={cx(
          'group/rail fixed inset-y-0 left-0 z-40 hidden w-[72px] flex-col overflow-hidden border-r border-slate-200 bg-white',
          'transition-[width,box-shadow] duration-200 ease-out hover:w-64 hover:shadow-xl focus-within:w-64 focus-within:shadow-xl md:flex',
        )}
      >
        <Brand rail />
        <div className="flex-1 overflow-y-auto overflow-x-hidden px-4 py-2 [scrollbar-width:none]">
          <NavList rail />
        </div>
        {context.organization && (
          <div className="m-3 flex items-center gap-3 rounded-xl bg-slate-50 p-2">
            <div className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-white text-xs font-semibold text-slate-600 ring-1 ring-slate-200">
              {context.organization.name.charAt(0).toUpperCase()}
            </div>
            <div className="min-w-0 whitespace-nowrap opacity-0 transition-opacity duration-150 group-hover/rail:opacity-100 group-focus-within/rail:opacity-100">
              <p className="truncate text-xs font-medium text-slate-800">{context.organization.name}</p>
              <p className="text-[11px] text-slate-500">Org code {context.organization.org_code}</p>
            </div>
          </div>
        )}
      </aside>

      {/* Mobile drawer */}
      {drawerOpen && (
        <div className="fixed inset-0 z-50 md:hidden" role="dialog" aria-modal="true" aria-label="Menu">
          <div className="absolute inset-0 bg-slate-900/40" onClick={() => setDrawerOpen(false)} />
          <div className="absolute inset-y-0 left-0 flex w-72 flex-col bg-white shadow-xl">
            <div className="flex items-center justify-between pr-3">
              <Brand rail={false} />
              <button
                className="rounded-lg p-2 text-slate-500 hover:bg-slate-100"
                aria-label="Close menu"
                onClick={() => setDrawerOpen(false)}
              >
                <X className="size-5" />
              </button>
            </div>
            <div className="px-4">
              <NavList rail={false} onNavigate={() => setDrawerOpen(false)} />
            </div>
          </div>
        </div>
      )}

      <div className="flex min-h-screen flex-col md:pl-[72px]">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-slate-200 bg-white/90 px-4 backdrop-blur md:px-8">
          <button
            className="rounded-lg p-2 text-slate-600 hover:bg-slate-100 md:hidden"
            aria-label="Open menu"
            onClick={() => setDrawerOpen(true)}
          >
            <Menu className="size-5" />
          </button>
          <h1 className="text-lg font-semibold text-slate-900">{titleFor(pathname)}</h1>

          <div className="ml-auto flex items-center gap-2 md:gap-4">
            {context.organization && (
              <span className="hidden rounded-lg bg-slate-100 px-2.5 py-1 font-mono text-xs font-medium tracking-wider text-slate-600 sm:inline">
                {context.organization.org_code}
              </span>
            )}
            <button className="relative rounded-lg p-2 text-slate-500 hover:bg-slate-100" aria-label="Notifications">
              <Bell className="size-5" />
            </button>
            <div className="flex items-center gap-3">
              <div className="hidden text-right sm:block">
                <p className="text-sm font-medium leading-tight text-slate-800">{displayName}</p>
                <div className="mt-0.5 flex justify-end gap-1">
                  {context.role && <Badge tone="orange">{context.role.name}</Badge>}
                  {context.is_platform_admin && <Badge>Platform</Badge>}
                </div>
              </div>
              <div className="flex size-9 items-center justify-center rounded-full bg-primary-100 text-sm font-semibold text-primary-700">
                {initials}
              </div>
            </div>
            <button
              className="rounded-lg p-2 text-slate-500 hover:bg-slate-100 hover:text-slate-900"
              aria-label="Sign out"
              title="Sign out"
              onClick={handleSignOut}
            >
              <LogOut className="size-5" />
            </button>
          </div>
        </header>

        <main className="flex-1 p-4 md:p-8">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
