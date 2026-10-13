// Sample figures shown only on the dev-only /preview route (no login there).
// Same shape as get_dashboard_stats(), so the page renders both identically.
import type { DashboardStats } from '@/lib/hr'

const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000).toISOString()

export const sampleStats: DashboardStats = {
  kpis: { total: 248, active: 231, new_this_month: 12, portal_access: 186, departments: 9, branches: 3 },
  headcount_trend: [
    ['Nov', 196], ['Dec', 201], ['Jan', 205], ['Feb', 209], ['Mar', 214], ['Apr', 218],
    ['May', 222], ['Jun', 225], ['Jul', 231], ['Aug', 236], ['Sep', 241], ['Oct', 248],
  ].map(([month, headcount]) => ({ month: month as string, headcount: headcount as number })),
  employment_types: [
    { type: 'Permanent', count: 182 },
    { type: 'Contract', count: 44 },
    { type: 'Probation', count: 22 },
  ],
  by_department: [
    { department: 'Production', count: 86 },
    { department: 'Quality', count: 34 },
    { department: 'Merchandising', count: 28 },
    { department: 'Finance', count: 22 },
    { department: 'HR & Admin', count: 21 },
    { department: 'IT', count: 18 },
    { department: 'Supply chain', count: 17 },
    { department: 'Sales', count: 14 },
    { department: 'Maintenance', count: 8 },
  ],
  joiners_leavers: [
    { month: 'May', joiners: 7, leavers: 3 },
    { month: 'Jun', joiners: 5, leavers: 2 },
    { month: 'Jul', joiners: 9, leavers: 3 },
    { month: 'Aug', joiners: 8, leavers: 3 },
    { month: 'Sep', joiners: 7, leavers: 2 },
    { month: 'Oct', joiners: 12, leavers: 5 },
  ],
  recent_activity: [
    { employee_id: 'x1', who: 'Farhana Akter', event_type: 'joined', to: { designation: 'QC Inspector' }, effective_date: daysAgo(0), created_at: daysAgo(0) },
    { employee_id: 'x2', who: 'Rakib Hasan', event_type: 'transfer', to: { office: 'Factory 2' }, effective_date: daysAgo(0), created_at: daysAgo(0.3) },
    { employee_id: 'x3', who: 'Nusrat Jahan', event_type: 'promotion', to: { designation: 'Senior Merchandiser' }, effective_date: daysAgo(1), created_at: daysAgo(1) },
    { employee_id: 'x4', who: 'Sadia Islam', event_type: 'branch', to: { branch: 'Gazipur' }, effective_date: daysAgo(2), created_at: daysAgo(2) },
  ],
}
