// Department organogram: React Query hooks. Positions and their states come from the database.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { ChartGrade, DepartmentCounts } from '@/onboarding-process/core/organogram'

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

export interface OrgGrade { id: string; code: string; name: string; rank: number; status: 'active' | 'inactive'; designations: number }
export interface GradeDesignation { id: string; name: string; department_id: string; department_name: string; pay_grade: string; organogram_grade_id: string | null }
export interface GradeList { can: { manage: boolean }; grades: OrgGrade[]; designations: GradeDesignation[] }
export interface DepartmentBudgetRow { department_id: string; name: string; has_budget: boolean; slots: number; counts: DepartmentCounts }
export interface DepartmentChart {
  department: { id: string; name: string; head: { id: string; full_name: string } | null }
  can: { budget: boolean; toggle: boolean }
  budget: { approved_headcount: number; after_separation: 'vacant' | 'blocked'; note: string | null; updated_at: string } | null
  counts: DepartmentCounts
  grades: ChartGrade[]
  unmapped: { id: string; full_name: string; designation: string | null }[]
}

export function useOrganogramGrades() {
  return useQuery({ queryKey: ['organogram', 'grades'], queryFn: () => callRpc<GradeList>('list_organogram_grades') })
}

export function useDepartmentBudgets() {
  return useQuery({ queryKey: ['organogram', 'departments'], queryFn: () => callRpc<DepartmentBudgetRow[]>('list_department_budgets') })
}

/** The chart refreshes every 30 s and when the window gets focus, so hiring shows up live. */
export function useDepartmentChart(departmentId: string | undefined) {
  return useQuery({
    queryKey: ['organogram', 'chart', departmentId],
    enabled: !!departmentId,
    refetchInterval: 30_000,
    queryFn: () => callRpc<DepartmentChart>('get_department_organogram', { p_department_id: departmentId }),
  })
}

export function useOrganogramAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (args: A) => callRpc<R>(fn, args),
    onSuccess: () => Promise.all([qc.invalidateQueries({ queryKey: ['organogram'] }), qc.invalidateQueries({ queryKey: ['workforce'] })]),
  })
}
