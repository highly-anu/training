import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { BenchmarkStandard } from './types'

export function useBenchmarks() {
  return useQuery({
    queryKey: queryKeys.benchmarks.all,
    queryFn: () => apiClient.get('/benchmarks') as unknown as Promise<BenchmarkStandard[]>,
    staleTime: Infinity,
  })
}
