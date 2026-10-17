import type { SpotlightStep } from './SpotlightTour'

/**
 * Step-by-step dashboard guide. Targets use data-tour markers; a step whose
 * target is missing for this role or screen size is skipped automatically.
 */
export const DASHBOARD_TOUR: SpotlightStep[] = [
  {
    title: 'Welcome to Olympus HRIS',
    body: 'A one-minute tour of your dashboard. Use the arrow keys or the buttons below; press Esc to leave at any time.',
  },
  {
    target: ['[data-tour="sidebar"]', '[data-tour="menu-button"]'],
    title: 'Everything is in the menu',
    body: 'Hover the icon rail to see names. Items follow your role: people, attendance, leave, payroll, tax, PF, gratuity and settings.',
    placement: 'right',
    padding: 4,
  },
  {
    target: '[data-tour="org-code"]',
    title: 'Your company code',
    body: 'This 6-digit code identifies your organization. Share it when you contact support.',
  },
  {
    target: '[data-tour="kpis"]',
    title: 'Key numbers at a glance',
    body: 'Total and active employees, who has a login, and how many departments and branches you run.',
  },
  {
    target: '[data-tour="charts"]',
    title: 'Trends',
    body: 'Headcount over the last 12 months and the mix of employment types. Each chart can also be shown as a table.',
  },
  {
    target: '[data-tour="activity"]',
    title: 'Recent activity',
    body: 'Joins, transfers, promotions and exits as they happen. Click a name to open the profile.',
  },
  {
    target: '[data-tour="quick-actions"]',
    title: 'Quick actions',
    body: 'Shortcuts to the jobs you do most often, such as adding an employee.',
    placement: 'left',
  },
  {
    target: '[data-tour="user-menu"]',
    title: 'Your profile',
    body: 'Open your profile, change your password or sign out from here.',
  },
  {
    target: '[data-tour="tour-help"]',
    title: 'Need this again?',
    body: 'Press this button any time to replay the guide.',
  },
]
