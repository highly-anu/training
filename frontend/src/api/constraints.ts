import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { EquipmentProfile, InjuryFlag } from './types'
import equipmentProfilesData from '@/data/static/equipment_profiles.json'
import injuryFlagsData from '@/data/static/injury_flags.json'

export function useEquipmentProfiles() {
  return useQuery({
    queryKey: queryKeys.constraints.equipmentProfiles,
    queryFn: () => Promise.resolve(equipmentProfilesData as EquipmentProfile[]),
    staleTime: Infinity,
  })
}

export function useInjuryFlags() {
  return useQuery({
    queryKey: queryKeys.constraints.injuryFlags,
    queryFn: () => Promise.resolve(injuryFlagsData as InjuryFlag[]),
    staleTime: Infinity,
  })
}
