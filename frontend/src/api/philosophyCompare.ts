import { useQueries, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { PhilosophyCompare, PhilosophyForMe } from './types'

/** Two or three philosophies side by side (Explore ▸ Philosophies ▸ Compare); static. */
export function usePhilosophyCompare(ids: string[]) {
  return useQuery({
    queryKey: queryKeys.philosophyCompare(ids),
    queryFn: () => apiClient.get<PhilosophyCompare>('/philosophies/compare', { params: { ids: ids.join(',') } }) as unknown as Promise<PhilosophyCompare>,
    enabled: ids.length >= 2,
    staleTime: Infinity,
  })
}

export interface ForMeColumn { id: string; trackId: string | null }

const isBusy = (err: unknown) => (err as { status?: number } | null)?.status === 429

/**
 * Each column generated on the athlete's profile, one after another: every
 * column is a heavy run on the server, which answers 429 while the athlete's
 * previous one is in flight. A column waits until the one before it has
 * settled; a 429 is retried. Nothing runs until `enabled`.
 */
export function usePhilosophyForMe(columns: ForMeColumn[], enabled: boolean) {
  const client = useQueryClient()
  const keys = columns.map((c) => queryKeys.philosophyForMe(c.id, c.trackId ?? ''))
  return useQueries({
    queries: columns.map((c, i) => ({
      queryKey: keys[i],
      queryFn: () => apiClient.post<PhilosophyForMe>(`/philosophies/${c.id}/for-me`,
        c.trackId ? { track_id: c.trackId } : {}) as unknown as Promise<PhilosophyForMe>,
      enabled: enabled && keys.slice(0, i).every((k) => {
        const status = client.getQueryState(k)?.status
        return status === 'success' || status === 'error'
      }),
      retry: (failures: number, err: unknown) => isBusy(err) && failures < 6,
      retryDelay: 1500,
      staleTime: 10 * 60_000,
    })),
  })
}
