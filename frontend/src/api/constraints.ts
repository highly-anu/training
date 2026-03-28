import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { EquipmentProfile, InjuryFlag } from './types'

export function useEquipmentProfiles() {
  return useQuery({
    queryKey: queryKeys.constraints.equipmentProfiles,
    queryFn: () => apiClient.get('/constraints/equipment-profiles') as unknown as Promise<EquipmentProfile[]>,
    staleTime: Infinity,
  })
}

export function useInjuryFlags() {
  return useQuery({
    queryKey: queryKeys.constraints.injuryFlags,
    queryFn: () => apiClient.get('/constraints/injury-flags') as unknown as Promise<InjuryFlag[]>,
    staleTime: Infinity,
  })
}
