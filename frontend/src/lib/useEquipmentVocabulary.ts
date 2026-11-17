import { useMemo } from 'react'
import { useEquipment } from '@/api/constraints'
import { equipmentCategories, equipmentGroups } from '@/lib/equipment'

// The equipment an athlete can tick: the build's list (generated from the
// commons) and, last, the implements their own packages add, which only the
// server knows (GET /api/equipment). Until it answers — or offline — the
// build's list alone.

/** The pickers' groups (the builder's EquipmentPicker, Explore ▸ Equipment). */
export function useEquipmentGroups() {
  const { data } = useEquipment()
  return useMemo(() => equipmentGroups(data), [data])
}

/** The Profile's sections (Profile ▸ Equipment, the builder's constraints form). */
export function useEquipmentCategories() {
  const { data } = useEquipment()
  return useMemo(() => equipmentCategories(data), [data])
}
