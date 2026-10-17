import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { BenchmarkStandard, StandardResults } from './types'
import { useProfileStore } from '@/store/profileStore'
import benchmarksData from '@/data/static/benchmarks.json'

/**
 * The standards' ladders for this athlete. `GET /api/standards?sex=` serves
 * the female or male tables; the bundled JSON (male values, the same shape —
 * `scripts/dump_static_data.py`) is the fallback when the API is unreachable.
 */
export function useStandards() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.standards.all, sex],
    queryFn: async () => {
      try {
        return await (apiClient.get(`/standards?sex=${sex}`) as unknown as Promise<BenchmarkStandard[]>)
      } catch {
        return benchmarksData as BenchmarkStandard[]
      }
    },
    staleTime: Infinity,
  })
}

/**
 * The athlete's results: per standard the current and best result with the
 * level the server worked out, and every entry. No client computes a level.
 */
export function useStandardResults() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.standards.results, sex],
    queryFn: () => apiClient.get('/standards/results') as unknown as Promise<StandardResults>,
    staleTime: 60_000,
  })
}

/**
 * Log one result (or a bodyweight). `text` is what the athlete typed — "4:58"
 * for a time — and the server parses it. Refreshes everything that reads results.
 */
export function useLogResult() {
  const qc = useQueryClient()
  return useMutation<{ saved: string; id: number }, Error, { benchmarkId: string; text: string }>({
    mutationFn: ({ benchmarkId, text }) =>
      apiClient.post('/health/performance', { benchmarkId, text, loggedAt: new Date().toISOString() }) as unknown as Promise<{ saved: string; id: number }>,
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: queryKeys.standards.results })
      void qc.invalidateQueries({ queryKey: queryKeys.analytics.program })
      void qc.invalidateQueries({ queryKey: queryKeys.analytics.development })
    },
  })
}
