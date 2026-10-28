// TMS data hooks (RPCs of 20261105000*_tms_*.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { rpc } from '@/communication/shared/api'
import type { Driver, Fleet, TmsOverview, VehicleDetail } from '../core/types'

function useRefresh() {
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: ['tms'] })
}

export const useFleet = () => useQuery({ queryKey: ['tms', 'fleet'], queryFn: () => rpc<Fleet>('get_tms_fleet') })
export const useTmsOverview = (enabled: boolean) =>
  useQuery({ queryKey: ['tms', 'overview'], enabled, queryFn: () => rpc<TmsOverview>('get_tms_overview') })
export const useVehicle = (id: string | null) =>
  useQuery({ queryKey: ['tms', 'vehicle', id], enabled: !!id, queryFn: () => rpc<VehicleDetail>('get_tms_vehicle', { p_id: id }) })
export const useMyDriver = () => useQuery({ queryKey: ['tms', 'me'], queryFn: () => rpc<Driver | null>('my_tms_driver') })

export function useSaveVehicle() {
  const refresh = useRefresh()
  return useMutation({ mutationFn: ({ id, p }: { id: string | null; p: Record<string, unknown> }) => rpc<string>('save_tms_vehicle', { p_id: id, p }), onSuccess: refresh })
}

export function useSaveDriver() {
  const refresh = useRefresh()
  return useMutation({ mutationFn: ({ id, p }: { id: string | null; p: Record<string, unknown> }) => rpc<string>('save_tms_driver', { p_id: id, p }), onSuccess: refresh })
}

/** Links a DMS document (vehicle paper or licence copy) to a vehicle or a driver. */
export function useLinkPaper() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ documentId, vehicleId, driverId }: { documentId: string; vehicleId?: string; driverId?: string }) =>
      rpc<void>('tms_link_document', { p_document_id: documentId, p_vehicle_id: vehicleId ?? null, p_driver_id: driverId ?? null }),
    onSuccess: refresh,
  })
}
