import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { Framework } from './types'
import frameworksData from '@/data/static/frameworks.json'

export function useFrameworks() {
  return useQuery({
    queryKey: queryKeys.frameworks.all,
    queryFn: () => Promise.resolve(frameworksData as Framework[]),
    staleTime: Infinity,
  })
}
