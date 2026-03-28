import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Modality } from './types'

export function useModalities() {
  return useQuery({
    queryKey: queryKeys.modalities.all,
    queryFn: () => apiClient.get('/modalities') as unknown as Promise<Modality[]>,
    staleTime: Infinity,
  })
}
