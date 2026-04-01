import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { Modality } from './types'
import modalitiesData from '@/data/static/modalities.json'

export function useModalities() {
  return useQuery({
    queryKey: queryKeys.modalities.all,
    queryFn: () => Promise.resolve(modalitiesData as Modality[]),
    staleTime: Infinity,
  })
}
