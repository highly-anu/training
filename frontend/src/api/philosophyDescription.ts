import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { PhilosophyDescription } from './types'

/** One philosophy as its package writes it (Explore ▸ Philosophies); static. */
export function usePhilosophyDescription(id: string | undefined) {
  return useQuery({
    queryKey: queryKeys.philosophyDescription(id ?? ''),
    queryFn: () => apiClient.get<PhilosophyDescription>(`/philosophies/${id}/describe`) as unknown as Promise<PhilosophyDescription>,
    enabled: !!id,
    staleTime: Infinity,
  })
}
