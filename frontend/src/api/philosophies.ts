import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { Philosophy } from './types'
import philosophiesData from '@/data/static/philosophies.json'

export function usePhilosophies() {
  return useQuery({
    queryKey: queryKeys.philosophies.all,
    queryFn: () => Promise.resolve(philosophiesData as Philosophy[]),
    staleTime: Infinity,
  })
}
