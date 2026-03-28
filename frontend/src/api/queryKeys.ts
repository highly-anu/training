import type { ExerciseFilters } from './types'

export const queryKeys = {
  goals: {
    all: ['goals'] as const,
    detail: (id: string) => ['goals', id] as const,
  },
  exercises: {
    all: ['exercises'] as const,
    filtered: (filters: ExerciseFilters) => ['exercises', 'filtered', filters] as const,
  },
  modalities: {
    all: ['modalities'] as const,
  },
  benchmarks: {
    all: ['benchmarks'] as const,
  },
  constraints: {
    equipmentProfiles: ['constraints', 'equipmentProfiles'] as const,
    injuryFlags: ['constraints', 'injuryFlags'] as const,
  },
  programs: {
    current: ['programs', 'current'] as const,
  },
  philosophies: {
    all: ['philosophies'] as const,
  },
  frameworks: {
    all: ['frameworks'] as const,
  },
} as const
