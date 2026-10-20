import { useMemo } from 'react'
import { useExercises } from '@/api/exercises'
import { useInjuryFlags } from '@/api/constraints'
import type { NameLookup } from '@/lib/heldBack'

/** Exercise and injury-flag names for lib/heldBack's wording. */
export function useHeldBackNames(): NameLookup {
  const { data: exercises } = useExercises()
  const { data: flags } = useInjuryFlags()
  return useMemo(() => {
    const ex = new Map((exercises ?? []).map((e) => [e.id, e.name]))
    const fl = new Map((flags ?? []).map((f) => [f.id as string, f.name]))
    return { exercise: (id) => ex.get(id), flag: (id) => fl.get(id) }
  }, [exercises, flags])
}
