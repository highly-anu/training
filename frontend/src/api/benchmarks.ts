import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { BenchmarkStandard } from './types'
import benchmarksData from '@/data/static/benchmarks.json'

export function useBenchmarks() {
  return useQuery({
    queryKey: queryKeys.benchmarks.all,
    queryFn: () => Promise.resolve(benchmarksData as BenchmarkStandard[]),
    staleTime: Infinity,
  })
}
