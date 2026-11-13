import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Equipment, EquipmentProfile, InjuryFlag } from './types'

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:8000/api'

export function useEquipment() {
  return useQuery({
    queryKey: queryKeys.equipment.all,
    // Through the client, so the request is the athlete's: the list then
    // includes the implements their own packages add.
    queryFn: () => apiClient.get('/equipment') as unknown as Promise<Equipment[]>,
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

export function useEquipmentProfiles() {
  return useQuery({
    queryKey: queryKeys.constraints.equipmentProfiles,
    queryFn: async () => {
      const res = await fetch(`${API_BASE_URL}/constraints/equipment-profiles`)
      if (!res.ok) throw new Error('Failed to fetch equipment profiles')
      return res.json() as Promise<EquipmentProfile[]>
    },
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

export function useInjuryFlags() {
  return useQuery({
    queryKey: queryKeys.constraints.injuryFlags,
    queryFn: async () => {
      const res = await fetch(`${API_BASE_URL}/constraints/injury-flags`)
      if (!res.ok) throw new Error('Failed to fetch injury flags')
      return res.json() as Promise<InjuryFlag[]>
    },
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}
