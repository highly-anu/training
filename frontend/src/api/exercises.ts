import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { Exercise, ExerciseFilters } from './types'
import exercisesData from '@/data/static/exercises.json'

const _exercises = exercisesData as Exercise[]

function applyFilters(exercises: Exercise[], filters?: ExerciseFilters): Exercise[] {
  if (!filters) return exercises
  let result = exercises

  if (filters.search) {
    const q = filters.search.toLowerCase()
    result = result.filter(
      (e) => e.name.toLowerCase().includes(q) || e.id.toLowerCase().includes(q)
    )
  }
  if (filters.modality?.length) {
    result = result.filter((e) => filters.modality!.some((m) => e.modality.includes(m)))
  }
  if (filters.category) {
    result = result.filter((e) => e.category === filters.category)
  }
  if (filters.effort?.length) {
    result = result.filter((e) => filters.effort!.includes(e.effort))
  }
  if (filters.equipment?.length) {
    result = result.filter((e) => filters.equipment!.some((eq) => e.equipment.includes(eq)))
  }

  return result
}

export function useExercises(filters?: ExerciseFilters) {
  return useQuery({
    queryKey: filters ? queryKeys.exercises.filtered(filters) : queryKeys.exercises.all,
    queryFn: () => Promise.resolve(_exercises),
    staleTime: Infinity,
    select: (data) => applyFilters(data, filters),
  })
}
