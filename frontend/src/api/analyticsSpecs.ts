import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { AnalyticsSpecs } from '@/api/types'

/**
 * What every philosophy tracks and measures — its analytics spec described,
 * not run. Static package data, so it never goes stale within a session.
 */
export function useAnalyticsSpecs() {
  return useQuery({
    queryKey: queryKeys.analytics.specs,
    queryFn: () => apiClient.get('/analytics/specs') as unknown as Promise<AnalyticsSpecs>,
    staleTime: Infinity,
  })
}
