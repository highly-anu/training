import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { PhilosophyDescription, PhilosophyGlance } from './types'

/** One philosophy as its package writes it (Explore ▸ Philosophies); static. */
export function usePhilosophyDescription(id: string | undefined) {
  return useQuery({
    queryKey: queryKeys.philosophyDescription(id ?? ''),
    queryFn: () => apiClient.get<PhilosophyDescription>(`/philosophies/${id}/describe`) as unknown as Promise<PhilosophyDescription>,
    enabled: !!id,
    staleTime: Infinity,
  })
}

/** Every philosophy's comparable facts (the landing, comparing); static. */
export function usePhilosophyGlances() {
  return useQuery({
    queryKey: queryKeys.philosophyGlances,
    queryFn: () => apiClient.get<PhilosophyGlance[]>('/philosophies/glance') as unknown as Promise<PhilosophyGlance[]>,
    staleTime: Infinity,
  })
}
