import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Philosophy } from './types'

export function usePhilosophies() {
  return useQuery({
    queryKey: queryKeys.philosophies.all,
    queryFn: () => apiClient.get('/philosophies') as unknown as Promise<Philosophy[]>,
    staleTime: Infinity,
  })
}
