// Onboarding process R1 (workforce planning): React Query hooks. Types and the
// calculation mirror live in src/onboarding-process/; every saved number is
// calculated in the database.
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { Vacancy, WorkforceDashboard } from '@/onboarding-process/core/types'

async function callRpc<T>(fn: string, args?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw error
  return data as T
}

/** First day of a month as YYYY-MM-DD. */
export const monthStart = (date = new Date()) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-01`

export function useWorkforceDashboard(month: string) {
  return useQuery({
    queryKey: ['workforce', 'dashboard', month],
    queryFn: () => callRpc<WorkforceDashboard>('get_workforce_dashboard', { p_month: month }),
  })
}

export function useVacancies() {
  return useQuery({ queryKey: ['workforce', 'vacancies'], queryFn: () => callRpc<Vacancy[]>('list_vacancies', { p_status: null }) })
}

/** Any workforce RPC; refreshes every workforce query afterwards. */
export function useWorkforceAction<A extends Record<string, unknown>, R = unknown>(fn: string) {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (args: A) => callRpc<R>(fn, args),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['workforce'] }),
  })
}
