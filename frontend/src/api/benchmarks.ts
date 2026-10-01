import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { BenchmarkStandard } from './types'
import { useProfileStore } from '@/store/profileStore'
import benchmarksData from '@/data/static/benchmarks.json'

/**
 * The benchmark ladders for this athlete. `GET /api/benchmarks?sex=` serves
 * the female or male tables; the bundled JSON (male values only) is the
 * fallback when the API is unreachable, which is what every athlete used to
 * get regardless of sex.
 */
export function useBenchmarks() {
  const sex = useProfileStore((s) => s.sex) ?? 'male'
  return useQuery({
    queryKey: [...queryKeys.benchmarks.all, sex],
    queryFn: async () => {
      try {
        return await (apiClient.get(`/benchmarks?sex=${sex}`) as unknown as Promise<BenchmarkStandard[]>)
      } catch {
        return benchmarksData as BenchmarkStandard[]
      }
    },
    staleTime: Infinity,
  })
}
