import { useExercises } from '@/api/exercises'
import { useArchetypes } from '@/api/archetypes'
import { useModalities } from '@/api/modalities'
import { useGoals } from '@/api/goals'
import { useFrameworks } from '@/api/frameworks'
import { usePhilosophies } from '@/api/philosophies'
import { useBenchmarks } from '@/api/benchmarks'
import { useInjuryFlags, useEquipmentProfiles } from '@/api/constraints'

export function useAllData() {
  const exercises = useExercises()
  const archetypes = useArchetypes()
  const modalities = useModalities()
  const goals = useGoals()
  const frameworks = useFrameworks()
  const philosophies = usePhilosophies()
  const benchmarks = useBenchmarks()
  const injuryFlags = useInjuryFlags()
  const equipmentProfiles = useEquipmentProfiles()

  const isLoading =
    exercises.isLoading ||
    archetypes.isLoading ||
    modalities.isLoading ||
    goals.isLoading ||
    frameworks.isLoading ||
    philosophies.isLoading ||
    benchmarks.isLoading ||
    injuryFlags.isLoading ||
    equipmentProfiles.isLoading

  return {
    exercises: exercises.data ?? [],
    archetypes: archetypes.data ?? [],
    modalities: modalities.data ?? [],
    goals: goals.data ?? [],
    frameworks: frameworks.data ?? [],
    philosophies: philosophies.data ?? [],
    benchmarks: benchmarks.data ?? [],
    injuryFlags: injuryFlags.data ?? [],
    equipmentProfiles: equipmentProfiles.data ?? [],
    isLoading,
    archetypesError: archetypes.error,
  }
}
