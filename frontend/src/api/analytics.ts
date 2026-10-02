import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { DevelopmentAnalytics, ProgramAnalytics } from '@/api/types'

/**
 * Program-specific analytics: how the athlete is doing against what the active
 * program is for, per methodology, in that methodology's own currency. One
 * document, computed and cached server-side (src/analytics).
 */
export async function fetchProgramAnalytics(fresh = false): Promise<ProgramAnalytics> {
  return apiClient.get(`/analytics/program${fresh ? '?fresh=1' : ''}`) as unknown as Promise<ProgramAnalytics>
}

export function useProgramAnalytics() {
  return useQuery({
    queryKey: queryKeys.analytics.program,
    queryFn: () => fetchProgramAnalytics(),
    staleTime: 5 * 60 * 1000,
  })
}

/**
 * Development across programs: the history tables read as one document —
 * blocks, lifts across the span, currencies, load by block, standards over
 * time. Twelve months by default; computed and cached server-side.
 */
export async function fetchDevelopmentAnalytics(fresh = false): Promise<DevelopmentAnalytics> {
  return apiClient.get(`/analytics/development${fresh ? '?fresh=1' : ''}`) as unknown as Promise<DevelopmentAnalytics>
}

export function useDevelopmentAnalytics() {
  return useQuery({
    queryKey: queryKeys.analytics.development,
    queryFn: () => fetchDevelopmentAnalytics(),
    staleTime: 5 * 60 * 1000,
  })
}
