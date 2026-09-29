import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { ProgramAnalytics } from '@/api/types'

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
