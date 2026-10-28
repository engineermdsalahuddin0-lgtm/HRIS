// TMS data hooks (RPCs of 20261105000*_tms_*.sql).
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { pushEmails, rpc, safeFileName } from '@/communication/shared/api'
import type {
  AssignOptions, Costs, Driver, Fleet, FuelLog, FuelVehicle, Inventory, Maintenance, TmsMe, TmsOverview, TmsSettings, Trip, TripDetail, VehicleDetail,
} from '../core/types'

function useRefresh() {
  const qc = useQueryClient()
  return () => qc.invalidateQueries({ queryKey: ['tms'] })
}

export const useFleet = (enabled = true) => useQuery({ queryKey: ['tms', 'fleet'], enabled, queryFn: () => rpc<Fleet>('get_tms_fleet') })
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

export const useTmsMe = () => useQuery({ queryKey: ['tms', 'me-all'], queryFn: () => rpc<TmsMe>('get_tms_me') })
export const useTrips = (scope: 'mine' | 'approve' | 'all' | 'driver', enabled = true) =>
  useQuery({ queryKey: ['tms', 'trips', scope], enabled, queryFn: () => rpc<Trip[]>('list_tms_trips', { p: { scope } }) })
export const useTrip = (id: string | null) =>
  useQuery({ queryKey: ['tms', 'trip', id], enabled: !!id, queryFn: () => rpc<TripDetail>('get_tms_trip', { p_id: id }) })
export const useAssignOptions = (id: string | null) =>
  useQuery({ queryKey: ['tms', 'assign-options', id], enabled: !!id, queryFn: () => rpc<AssignOptions>('tms_assign_options', { p_id: id }) })

/** Trip actions: create, decide, assign, cancel, start, end (each refreshes the transport data). */
export function useTripAction() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ fn, args }: { fn: string; args: Record<string, unknown> }) => rpc<unknown>(fn, args),
    onSuccess: () => { void pushEmails(); return refresh() },
  })
}

/** Adds a trip expense; the receipt (optional) goes to tms-files/{org}/trip/{trip}/ first. */
export function useAddExpense() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ orgId, tripId, p, file }: { orgId: string; tripId: string; p: Record<string, unknown>; file: File | null }) => {
      let receipt_path: string | null = null
      if (file) {
        receipt_path = `${orgId}/trip/${tripId}/${Date.now()}-${safeFileName(file.name)}`
        const { error } = await supabase.storage.from('tms-files').upload(receipt_path, file, { contentType: file.type, upsert: false })
        if (error) throw error
      }
      return rpc<string>('add_tms_trip_expense', { p_id: tripId, p: { ...p, receipt_path } })
    },
    onSuccess: refresh,
  })
}

export async function openTmsFile(path: string): Promise<void> {
  const { data, error } = await supabase.storage.from('tms-files').createSignedUrl(path, 60)
  if (error || !data) throw error ?? new Error('The file could not be opened')
  window.open(data.signedUrl, '_blank', 'noopener')
}

/** One GPS reading from the phone (only when the driver presses Start / End or logs fuel). */
export function currentPosition(): Promise<{ lat: number; lng: number; accuracy_m: number } | null> {
  return new Promise((resolve) => {
    if (!('geolocation' in navigator)) return resolve(null)
    navigator.geolocation.getCurrentPosition(
      (p) => resolve({ lat: +p.coords.latitude.toFixed(6), lng: +p.coords.longitude.toFixed(6), accuracy_m: Math.round(p.coords.accuracy) }),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 60_000 },
    )
  })
}

export const useFuel = (p: { scope: 'mine' | 'all'; flagged?: boolean }) =>
  useQuery({ queryKey: ['tms', 'fuel', p], queryFn: () => rpc<FuelLog[]>('list_tms_fuel', { p }) })
export const useFuelVehicles = () => useQuery({ queryKey: ['tms', 'fuel-vehicles'], queryFn: () => rpc<FuelVehicle[]>('tms_fuel_vehicles') })
export const useTmsSettings = (enabled: boolean) =>
  useQuery({ queryKey: ['tms', 'settings'], enabled, queryFn: () => rpc<TmsSettings | null>('get_tms_settings') })

/** Logs a fill: the receipt (optional) goes to tms-files/{org}/fuel/{vehicle}/ first, plus one GPS reading. */
export function useLogFuel() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: async ({ orgId, p, file }: { orgId: string; p: Record<string, unknown> & { vehicle_id: string }; file: File | null }) => {
      let receipt_path: string | null = null
      if (file) {
        receipt_path = `${orgId}/fuel/${p.vehicle_id}/${Date.now()}-${safeFileName(file.name)}`
        const { error } = await supabase.storage.from('tms-files').upload(receipt_path, file, { contentType: file.type, upsert: false })
        if (error) throw error
      }
      const pos = await currentPosition()
      return rpc<FuelLog>('log_tms_fuel', { p: { ...p, receipt_path, ...(pos ? { lat: pos.lat, lng: pos.lng } : {}) } })
    },
    onSuccess: refresh,
  })
}

export const useCosts = (from: string, to: string) =>
  useQuery({ queryKey: ['tms', 'costs', from, to], queryFn: () => rpc<Costs>('get_tms_costs', { p_from: from || null, p_to: to || null }) })
export const useMaintenance = () => useQuery({ queryKey: ['tms', 'maintenance'], queryFn: () => rpc<Maintenance>('get_tms_maintenance') })
export const useInventory = () => useQuery({ queryKey: ['tms', 'inventory'], queryFn: () => rpc<Inventory>('get_tms_inventory') })

/** Links a DMS document (vehicle paper or licence copy) to a vehicle or a driver. */
export function useLinkPaper() {
  const refresh = useRefresh()
  return useMutation({
    mutationFn: ({ documentId, vehicleId, driverId }: { documentId: string; vehicleId?: string; driverId?: string }) =>
      rpc<void>('tms_link_document', { p_document_id: documentId, p_vehicle_id: vehicleId ?? null, p_driver_id: driverId ?? null }),
    onSuccess: refresh,
  })
}
