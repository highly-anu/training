import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { ExploreLinks } from './types'

/** Explore's links between levels and its movements; static, like the modalities. */
export function useExploreLinks() {
  return useQuery({
    queryKey: queryKeys.exploreLinks,
    queryFn: () => apiClient.get<ExploreLinks>('/explore/links') as unknown as Promise<ExploreLinks>,
    staleTime: Infinity,
  })
}
