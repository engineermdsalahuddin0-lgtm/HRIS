import type { ComponentType, ReactNode } from 'react'
import { Suspense, lazy } from 'react'
import { createBrowserRouter, Navigate } from 'react-router-dom'
import AppLayout from '@/components/AppLayout'
import {
  PublicOnly, RequireAppAccess, RequirePermission, RequirePlatformAdmin, RequireSession,
} from '@/components/guards'
import { PageLoader } from '@/components/ui'
import LoginPage from '@/pages/LoginPage'
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

// Part 3A: any money permission opens the Compensation page; its tabs follow the permissions.
const COMPENSATION = ['compensation.view', 'increments.approve', 'bonuses.manage', 'deductions.manage']

// Law & policy library: anyone who works with pay or its settings.
const REFERENCES = ['compensation.view', 'payroll.prepare', 'payroll.approve', 'payroll_settings.manage', 'tax.view_profiles', 'pf.manage', 'gratuity.manage', 'performance.manage']

// Onboarding process: the dashboard needs workforce rights; vacancies also open for requesters.
const WORKFORCE = ['workforce.view', 'workforce.manage', 'headcount.manage']
const VACANCIES = ['workforce.view', 'vacancy.request', 'vacancy.review', 'vacancy.approve']
// Recruitment: Admin / HR (recruit.manage) everything, Manager (recruit.department) own department.
const RECRUIT = ['recruit.manage', 'recruit.department']
// Organogram: anyone who plans or hires; managers see their own department (the database checks it).
const ORGANOGRAM = ['workforce.view', 'workforce.manage', 'headcount.manage', 'recruit.manage', 'vacancy.request', 'recruit.department']

export const router = createBrowserRouter([
  { path: '/login', element: <PublicOnly><LoginPage /></PublicOnly> },
  { path: '/register', element: <PublicOnly>{page(() => import('@/pages/public/RegisterPage'))}</PublicOnly> },
  { path: '/signup', element: <Navigate to="/register" replace /> },
  // Public careers page and apply form (no login, signed-in visitors too).
  { path: '/careers/:orgCode', element: named(() => import('@/pages/public/careers/CareersPages'), 'CareersPage') },
  { path: '/careers/:orgCode/:slug', element: named(() => import('@/pages/public/careers/CareersPages'), 'JobApplyPage') },
  // R4: the online test; the link's token is the only key.
  { path: '/t/:token', element: named(() => import('@/pages/public/careers/TestPage'), 'TestPage') },
  // R5: the pre-interview form link from the interview email.
  { path: '/f/:token', element: named(() => import('@/pages/public/careers/PreinterviewFormPage'), 'PreinterviewFormPage') },
  // R6 / R7: the offer + pre-joining form, and the named joining feedback.
  { path: '/offer/:token', element: named(() => import('@/pages/public/careers/OfferPage'), 'OfferPage') },
  { path: '/joining-feedback/:token', element: named(() => import('@/pages/public/careers/JoiningFeedbackPage'), 'JoiningFeedbackPage') },
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
              // Part 3B: payroll runs and payslips
              guarded(['payroll.prepare', 'payroll.review', 'payroll.approve', 'payroll.reopen', 'payroll.lock'], '/payroll', page(() => import('@/pages/payroll/PayrollRunsPage'))),
              guarded(['payroll.prepare', 'payroll.review', 'payroll.approve', 'payroll.reopen', 'payroll.lock'], '/payroll/runs/:id', page(() => import('@/pages/payroll/PayrollRunPage'))),
              guarded('payroll.view_own', '/payslips', page(() => import('@/pages/payroll/MyPayslipsPage'))),
              // Part 3A: salary structure
              guarded(COMPENSATION, '/compensation', page(() => import('@/pages/salary/CompensationPage'))),
              guarded(['compensation.view', 'compensation.edit'], '/salary', page(() => import('@/pages/salary/SalaryStructurePage'))),
              guarded(['payroll_settings.manage', 'compensation.view'], '/settings/payroll', page(() => import('@/pages/salary/PayrollSettingsPage'))),
              // Part 3C: tax, provident fund, gratuity, law references
              guarded(['tax.view_profiles', 'tax.manage', 'payroll.prepare', 'payroll_settings.manage'], '/tax', page(() => import('@/pages/statutory/TaxPage'))),
              guarded('pf.manage', '/pf', page(() => import('@/pages/statutory/ProvidentFundPage'))),
              guarded('gratuity.manage', '/gratuity', page(() => import('@/pages/statutory/GratuityPage'))),
              guarded(['payroll_settings.manage', 'pf.manage', 'gratuity.manage', 'tax.view_profiles'], '/settings/statutory', page(() => import('@/pages/statutory/StatutorySettingsPage'))),
              guarded(REFERENCES, '/references', page(() => import('@/pages/statutory/ReferencesPage'))),
              // Performance (manual scoring demo)
              guarded(['performance.manage', 'performance.review'], '/performance', page(() => import('@/pages/performance/PerformancePage'))),
              { path: '/my-reviews', element: page(() => import('@/pages/performance/MyReviewsPage')) },
              // Onboarding process R1: workforce planning and vacancies
              guarded(WORKFORCE, '/workforce', page(() => import('@/pages/onboarding/WorkforcePage'))),
              guarded(VACANCIES, '/vacancies', page(() => import('@/pages/onboarding/VacanciesPage'))),
              guarded(ORGANOGRAM, '/organogram', page(() => import('@/pages/onboarding/OrganogramPage'))),
              // R2: job profiles, posts, applicants
              guarded(RECRUIT, '/job-posts', page(() => import('@/pages/onboarding/JobPostsPage'))),
              guarded(RECRUIT, '/job-posts/:id', page(() => import('@/pages/onboarding/JobPostPage'))),
              guarded('recruit.manage', '/settings/recruitment', page(() => import('@/pages/onboarding/RecruitmentSettingsPage'))),
              // R5: any employee on an interview panel (the database checks the panel).
              { path: '/my-interviews', element: page(() => import('@/pages/interviews/MyInterviewsPage')) },
              { path: '/my-interviews/:id', element: page(() => import('@/pages/interviews/InterviewKitPage')) },
              {
                element: <RequirePlatformAdmin />,
                children: [
                  { path: '/platform', element: page(() => import('@/pages/platform/PlatformDashboardPage')) },
                  { path: '/platform/applications', element: page(() => import('@/pages/platform/ApplicationsPage')) },
                  { path: '/platform/organizations/:id', element: page(() => import('@/pages/platform/OrganizationDetailsPage')) },
                  { path: '/platform/requests', element: <Navigate to="/platform/applications" replace /> },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
  // Dev-only: view the app shell without signing in.
  ...(import.meta.env.DEV
    ? [{ path: '/preview', element: <PreviewPage />, children: [
        { index: true, element: page(() => import('@/pages/DashboardPage')) },
        { path: 'workforce', element: named(() => import('@/pages/onboarding/WorkforceDemo'), 'WorkforceDemoPage') },
        { path: 'job-post', element: named(() => import('@/pages/onboarding/JobPostPage'), 'JobPostDemoPage') },
        { path: 'organogram', element: named(() => import('@/pages/onboarding/OrganogramDemo'), 'OrganogramDemoPage') },
      ] }]
    : []),
  { path: '*', element: <Navigate to="/" replace /> },
])
