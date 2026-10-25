import { useState } from 'react'
import { NavLink, Outlet, useLocation } from 'react-router-dom'
import type { LucideIcon } from 'lucide-react'
import {
  Award, Banknote, CircleHelp, BookOpen, Building2, HandCoins, PiggyBank, Receipt, Scale, Star, CalendarClock, CalendarDays, Clock, FileText, Fingerprint, Globe, Inbox, Layers, LayoutDashboard, Menu, ScrollText, Settings,
  ShieldCheck, SlidersHorizontal, Timer, UserRound, Users, Wallet, X, Gauge, UserPlus, Megaphone,
} from 'lucide-react'
import { useIsPreview, useMyContext } from '@/lib/appContext'
import { useOrgLogo } from '@/lib/files'
import { cx } from '@/components/ui'
import { UserMenu } from '@/components/UserMenu'
import { SpotlightTour } from '@/components/spotlight/SpotlightTour'
import { useSpotlightTour } from '@/components/spotlight/useSpotlightTour'
import { DASHBOARD_TOUR } from '@/components/spotlight/dashboardTour'

interface NavItem {
  to: string
  label: string
  icon: LucideIcon
  /** Shown when the role has any of these permissions (UI only; the DB enforces it). */
  anyOf?: string[]
  platformOnly?: boolean
  section?: string
}

export const NAV: NavItem[] = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard },
  { to: '/me', label: 'My profile', icon: UserRound },
  { to: '/attendance/me', label: 'My attendance', icon: Fingerprint, anyOf: ['attendance.view_own'] },
  { to: '/leave', label: 'Leave', icon: CalendarDays, anyOf: ['leave.request', 'leave.approve', 'leave.view_all'] },
  { to: '/payslips', label: 'My payslips', icon: FileText, anyOf: ['payroll.view_own'] },
  { to: '/my-reviews', label: 'My reviews', icon: Award },
  { to: '/attendance', label: 'Attendance', icon: Clock, anyOf: ['attendance.view_team', 'attendance.view_all'], section: 'Team' },
  { to: '/overtime', label: 'Overtime', icon: Timer, anyOf: ['overtime.view', 'overtime.approve'] },
  { to: '/employees', label: 'Employees', icon: Users, anyOf: ['employees.view'] },
  { to: '/performance', label: 'Performance', icon: Star, anyOf: ['performance.manage', 'performance.review'] },
  { to: '/workforce', label: 'Workforce', icon: Gauge, anyOf: ['workforce.view', 'workforce.manage', 'headcount.manage'], section: 'Hiring' },
  { to: '/vacancies', label: 'Vacancies', icon: UserPlus, anyOf: ['workforce.view', 'vacancy.request', 'vacancy.review', 'vacancy.approve'] },
  { to: '/job-posts', label: 'Job posts', icon: Megaphone, anyOf: ['recruit.manage'] },
  { to: '/payroll', label: 'Payroll runs', icon: Banknote, anyOf: ['payroll.prepare', 'payroll.review', 'payroll.approve', 'payroll.reopen', 'payroll.lock'], section: 'Payroll' },
  { to: '/compensation', label: 'Compensation', icon: Wallet, anyOf: ['compensation.view', 'increments.approve', 'bonuses.manage', 'deductions.manage'] },
  { to: '/salary', label: 'Salary structure', icon: Layers, anyOf: ['compensation.view', 'compensation.edit'] },
  { to: '/tax', label: 'Tax & TDS', icon: Receipt, anyOf: ['tax.view_profiles', 'tax.manage', 'payroll.prepare', 'payroll_settings.manage'] },
  { to: '/pf', label: 'Provident fund', icon: PiggyBank, anyOf: ['pf.manage'] },
  { to: '/gratuity', label: 'Gratuity', icon: HandCoins, anyOf: ['gratuity.manage'] },
  { to: '/settings/payroll', label: 'Payroll settings', icon: SlidersHorizontal, anyOf: ['payroll_settings.manage', 'compensation.view'] },
  { to: '/settings/statutory', label: 'Statutory settings', icon: Scale, anyOf: ['payroll_settings.manage', 'pf.manage', 'gratuity.manage', 'tax.view_profiles'] },
  { to: '/references', label: 'Law & policy', icon: BookOpen, anyOf: ['compensation.view', 'payroll.prepare', 'payroll.approve', 'payroll_settings.manage', 'tax.view_profiles', 'pf.manage', 'gratuity.manage', 'performance.manage'] },
  { to: '/organization', label: 'Organization', icon: Building2, anyOf: ['org.view'], section: 'Setup' },
  {
    to: '/time', label: 'Time setup', icon: CalendarClock,
    anyOf: ['shifts.manage', 'roster.manage', 'holidays.manage', 'attendance.settings', 'geofences.manage', 'leave.manage_types', 'overtime.manage_policy'],
  },
  { to: '/settings/roles', label: 'Roles & access', icon: ShieldCheck, anyOf: ['roles.view'] },
  { to: '/audit', label: 'Audit log', icon: ScrollText, anyOf: ['audit.view'] },
  { to: '/settings', label: 'Settings', icon: Settings, anyOf: ['settings.manage'] },
  { to: '/platform', label: 'Platform', icon: Globe, platformOnly: true, section: 'Platform' },
  { to: '/platform/applications', label: 'Applications', icon: Inbox, platformOnly: true },
]

const TITLES: [string, string][] = [
  ['/employees/new', 'Add employee'],
  ['/employees', 'Employees'],
  ['/attendance/me', 'My attendance'],
  ['/attendance/qr', 'QR check-in'],
  ['/attendance', 'Attendance'],
  ['/leave', 'Leave'],
  ['/overtime', 'Overtime'],
  ['/time', 'Time setup'],
  ['/organization', 'Organization'],
  ['/settings/roles', 'Roles & access'],
  ['/settings/payroll', 'Payroll settings'],
  ['/settings/statutory', 'Statutory settings'],
  ['/tax', 'Income tax & TDS'],
  ['/pf', 'Provident fund'],
  ['/gratuity', 'Gratuity'],
  ['/references', 'Law & policy'],
  ['/performance', 'Performance'],
  ['/workforce', 'Workforce planning'],
  ['/vacancies', 'Vacancies'],
  ['/preview/workforce', 'Workforce demo'],
  ['/job-posts', 'Job posts'],
  ['/preview/job-post', 'Job post demo'],
  ['/my-reviews', 'My reviews'],
  ['/compensation', 'Compensation'],
  ['/payroll', 'Payroll'],
  ['/payslips', 'My payslips'],
  ['/salary', 'Salary structure'],
  ['/settings', 'Settings'],
  ['/audit', 'Audit log'],
  ['/platform/applications', 'Applications'],
  ['/platform/organizations', 'Organization'],
  ['/platform', 'Platform'],
  ['/me', 'My profile'],
  ['/', 'Dashboard'],
]
const titleFor = (path: string) =>
  TITLES.find(([prefix]) => path === prefix || (prefix !== '/' && path.startsWith(prefix)))?.[1] ?? 'Dashboard'

function useNavItems() {
  const context = useMyContext()
  return NAV.filter((i) => {
    if (i.platformOnly) return context.is_platform_admin
    if (!context.organization) return false
    return !i.anyOf || i.anyOf.some((p) => context.permissions.includes(p))
  })
}

const EXACT = new Set(['/', '/settings', '/attendance', '/platform'])

/** In the rail, labels appear when the rail expands (hover or keyboard focus); in the drawer they always show. */
function NavList({ rail, onNavigate }: { rail: boolean; onNavigate?: () => void }) {
  const items = useNavItems()
  const isPreview = useIsPreview()
  const fade = rail ? 'opacity-0 transition-opacity duration-150 group-hover/rail:opacity-100 group-focus-within/rail:opacity-100' : ''

  return (
    <nav className="space-y-1" aria-label="Main">
      {items.map(({ to, label, icon: Icon, section }, i) => (
        <div key={to}>
          {section && i > 0 && (
            <p className={cx('mb-1 mt-4 h-4 whitespace-nowrap px-3 text-[10px] font-semibold uppercase tracking-wider text-slate-400', fade)}>
              {section}
            </p>
          )}
          <NavLink
            to={isPreview && to === '/' ? '/preview' : to}
            end={EXACT.has(to)}
            onClick={onNavigate}
            title={label}
            className={({ isActive }) =>
              cx(
                'flex h-11 items-center gap-3 whitespace-nowrap rounded-xl px-3 text-sm font-medium transition-colors',
                isActive ? 'bg-primary-50 text-primary-700' : 'text-slate-600 hover:bg-slate-100 hover:text-slate-900',
              )
            }
          >
            <Icon className="size-5 shrink-0" aria-hidden />
            <span className={cx('flex-1 truncate', fade)}>{label}</span>
          </NavLink>
        </div>
      ))}
    </nav>
  )
}

/** Company logo if uploaded, otherwise the Olympus mark. */
function BrandMark() {
  const ctx = useMyContext()
  const isPreview = useIsPreview()
  const logo = useOrgLogo(isPreview ? undefined : ctx.organization?.id)
  if (logo.data) {
    return <img src={logo.data} alt="" className="size-9 shrink-0 rounded-xl bg-white object-contain ring-1 ring-slate-200" />
  }
  return (
    <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary-600 text-lg font-bold text-white">O</div>
  )
}

function Brand({ rail }: { rail: boolean }) {
  const ctx = useMyContext()
  return (
    <div className="flex h-16 items-center gap-3 px-[18px]">
      <BrandMark />
      <div
        className={cx(
          'min-w-0 whitespace-nowrap',
          rail && 'opacity-0 transition-opacity duration-150 group-hover/rail:opacity-100 group-focus-within/rail:opacity-100',
        )}
      >
        <p className="truncate text-base font-semibold leading-tight text-slate-900">{ctx.organization?.name ?? 'Olympus HRIS'}</p>
        <p className="text-[11px] text-slate-500">Olympus HRIS</p>
      </div>
    </div>
  )
}

export default function AppLayout() {
  const context = useMyContext()
  const { pathname } = useLocation()
  // Dashboard guide: opens once per browser on the first dashboard visit; the ? button replays it.
  const onDashboard = (pathname === '/' || pathname === '/preview') && !!context.organization
  const tour = useSpotlightTour('dashboard-v1', { autoStart: onDashboard })
  const [drawerOpen, setDrawerOpen] = useState(false)

  return (
    <div className="min-h-screen">
      {/* Desktop: icon rail that expands over the content on hover or keyboard focus. */}
      <aside
        data-tour="sidebar"
        className={cx(
          'group/rail fixed inset-y-0 left-0 z-40 hidden w-[72px] flex-col overflow-hidden border-r border-slate-200 bg-white',
          'transition-[width,box-shadow] duration-200 ease-out hover:w-64 hover:shadow-xl focus-within:w-64 focus-within:shadow-xl md:flex print:hidden',
        )}
      >
        <Brand rail />
        <div className="nav-scroll min-h-0 flex-1 overflow-y-auto overflow-x-hidden overscroll-contain px-4 py-2">
          <NavList rail />
        </div>
      </aside>

      {/* Mobile drawer */}
      {drawerOpen && (
        <div className="fixed inset-0 z-50 md:hidden print:hidden" role="dialog" aria-modal="true" aria-label="Menu">
          <div className="absolute inset-0 bg-slate-900/40" onClick={() => setDrawerOpen(false)} />
          <div className="absolute inset-y-0 left-0 flex w-72 max-w-[85vw] flex-col bg-white shadow-xl">
            <div className="flex items-center justify-between pr-3">
              <Brand rail={false} />
              <button className="rounded-lg p-2 text-slate-500 hover:bg-slate-100" aria-label="Close menu" onClick={() => setDrawerOpen(false)}>
                <X className="size-5" />
              </button>
            </div>
            <div className="nav-scroll min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pb-6">
              <NavList rail={false} onNavigate={() => setDrawerOpen(false)} />
            </div>
          </div>
        </div>
      )}

      <div className="flex min-h-screen flex-col md:pl-[72px] print:pl-0">
        <header className="sticky top-0 z-30 flex h-16 items-center gap-2 border-b border-slate-200 bg-white/90 px-3 backdrop-blur sm:gap-3 md:px-8 print:hidden">
          <button data-tour="menu-button" className="rounded-lg p-2 text-slate-600 hover:bg-slate-100 md:hidden" aria-label="Open menu" onClick={() => setDrawerOpen(true)}>
            <Menu className="size-5" />
          </button>
          <h1 className="truncate text-base font-semibold text-slate-900 sm:text-lg">{titleFor(pathname)}</h1>
          <div className="ml-auto flex items-center gap-2 md:gap-3">
            {context.organization && (
              <span data-tour="org-code" className="hidden rounded-lg bg-slate-100 px-2.5 py-1 font-mono text-xs font-medium tracking-wider text-slate-600 lg:inline">
                {context.organization.org_code}
              </span>
            )}
            {onDashboard && (
              <button type="button" data-tour="tour-help" onClick={tour.start} aria-label="Replay the dashboard guide" title="Dashboard guide"
                className="rounded-lg p-2 text-slate-500 hover:bg-slate-100 hover:text-slate-800">
                <CircleHelp className="size-5" />
              </button>
            )}
            <div data-tour="user-menu"><UserMenu /></div>
          </div>
        </header>

        <SpotlightTour steps={DASHBOARD_TOUR} open={tour.open && onDashboard} onClose={tour.close} />
        <main className="min-w-0 flex-1 p-3 sm:p-4 md:p-8 print:p-0">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
