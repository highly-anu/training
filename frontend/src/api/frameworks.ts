import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Framework } from './types'

export function useFrameworks() {
  return useQuery({
    queryKey: queryKeys.frameworks.all,
    queryFn: () => apiClient.get('/frameworks') as unknown as Promise<Framework[]>,
    staleTime: Infinity,
  })
}
