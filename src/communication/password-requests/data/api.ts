// Password request hooks (RPCs of 20261102000300_comm_c3_password_requests.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { rpc } from '../../shared/api'

export interface PasswordRequest {
  id: string
  employee_id: string
  full_name: string
  card_id: string
  department: string | null
  login_hint: string
  status: 'pending' | 'resolved' | 'dismissed'
  requested_at: string
  resolved_at: string | null
  resolved_by: string | null
  note: string | null
}

export interface PasswordRequestList { kpis: { pending: number; resolved: number }; requests: PasswordRequest[] }

export const usePasswordRequests = () =>
  useQuery({ queryKey: ['password-requests'], queryFn: () => rpc<PasswordRequestList>('list_password_requests') })

function useAction<A extends Record<string, unknown>>(fn: string) {
  const qc = useQueryClient()
  return useMutation({ mutationFn: (args: A) => rpc<void>(fn, args), onSuccess: () => qc.invalidateQueries({ queryKey: ['password-requests'] }) })
}

export const useResolveRequest = () => useAction<{ p_id: string; p_password: string }>('resolve_password_request')
export const useDismissRequest = () => useAction<{ p_id: string; p_note: string }>('dismiss_password_request')

/** Login page (no sign-in): always the same answer whether the ID exists or not. */
export const askForPasswordHelp = (login: string) => rpc<{ ok: true; message: string }>('request_password_help', { p_login: login })
