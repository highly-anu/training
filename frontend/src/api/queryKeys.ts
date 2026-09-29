import type { ExerciseFilters } from './types'

export const queryKeys = {
  goals: {
    all: ['goals'] as const,
    detail: (id: string) => ['goals', id] as const,
  },
  exercises: {
    all: ['exercises'] as const,
    filtered: (filters: ExerciseFilters) => ['exercises', 'filtered', filters] as const,
    media: (id: string) => ['exercises', 'media', id] as const,
  },
  modalities: {
    all: ['modalities'] as const,
  },
  benchmarks: {
    all: ['benchmarks'] as const,
  },
  equipment: {
    all: ['equipment'] as const,
  },
  constraints: {
    equipmentProfiles: ['constraints', 'equipmentProfiles'] as const,
    injuryFlags: ['constraints', 'injuryFlags'] as const,
  },
  programs: {
    current: ['programs', 'current'] as const,
    history: ['programs', 'history'] as const,
    version: (id: string) => ['programs', 'history', id] as const,
    plannedSessions: (from?: string, to?: string) =>
      ['programs', 'plannedSessions', from ?? '', to ?? ''] as const,
  },
  analytics: {
    program: ['analytics', 'program'] as const,
    specs: ['analytics', 'specs'] as const,
  },
  philosophies: {
    all: ['philosophies'] as const,
  },
  frameworks: {
    all: ['frameworks'] as const,
  },
  archetypes: {
    all: ['archetypes'] as const,
  },
  similarity: {
    all: ['similarity'] as const,
  },
} as const
