import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { PortabilityReport } from '@/api/types'

/**
 * What each package brings in its own folder and what it still needs outside
 * it, with the gaps no package can close yet (src/portability.py). Local dev
 * or AUTHORING_ENABLED only; package files change only between deploys.
 */
export function usePortability() {
  return useQuery({
    queryKey: queryKeys.dev.portability,
    queryFn: () => apiClient.get('/dev/portability') as unknown as Promise<PortabilityReport>,
    staleTime: Infinity,
    retry: false,
  })
}
