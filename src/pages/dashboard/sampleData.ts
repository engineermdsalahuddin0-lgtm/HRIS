// Sample figures for the dashboard until the Employees module (Step 5) supplies real data.
// Shapes match what the real queries will return, so swapping the source is the only change.

export const kpis = {
  totalEmployees: 248,
  newThisMonth: 12,
  active: 231,
  portalAccess: 186,
  departments: 9,
}

export const headcountTrend = [
  { month: 'Nov', headcount: 196 },
  { month: 'Dec', headcount: 201 },
  { month: 'Jan', headcount: 205 },
  { month: 'Feb', headcount: 209 },
  { month: 'Mar', headcount: 214 },
  { month: 'Apr', headcount: 218 },
  { month: 'May', headcount: 222 },
  { month: 'Jun', headcount: 225 },
  { month: 'Jul', headcount: 231 },
  { month: 'Aug', headcount: 236 },
  { month: 'Sep', headcount: 241 },
  { month: 'Oct', headcount: 248 },
]

export const employmentTypes = [
  { type: 'Permanent', count: 182 },
  { type: 'Contract', count: 44 },
  { type: 'Probation', count: 22 },
]

export const byDepartment = [
  { department: 'Production', count: 86 },
  { department: 'Quality', count: 34 },
  { department: 'Merchandising', count: 28 },
  { department: 'Finance', count: 22 },
  { department: 'HR & Admin', count: 21 },
  { department: 'IT', count: 18 },
  { department: 'Supply chain', count: 17 },
  { department: 'Sales', count: 14 },
  { department: 'Maintenance', count: 8 },
]

export const joinersLeavers = [
  { month: 'May', joiners: 7, leavers: 3 },
  { month: 'Jun', joiners: 5, leavers: 2 },
  { month: 'Jul', joiners: 9, leavers: 3 },
  { month: 'Aug', joiners: 8, leavers: 3 },
  { month: 'Sep', joiners: 7, leavers: 2 },
  { month: 'Oct', joiners: 12, leavers: 5 },
]

export const recentActivity = [
  { who: 'Farhana Akter', what: 'joined Quality as QC Inspector', when: '2h ago', kind: 'joined' },
  { who: 'Rakib Hasan', what: 'transferred to Dhaka Factory 2', when: '5h ago', kind: 'transfer' },
  { who: 'Nusrat Jahan', what: 'promoted to Senior Merchandiser (EM3)', when: 'Yesterday', kind: 'promotion' },
  { who: 'Tanvir Ahmed', what: 'was given portal access', when: 'Yesterday', kind: 'access' },
  { who: 'Sadia Islam', what: 'reporting manager changed', when: '2 days ago', kind: 'reporting' },
] as const
