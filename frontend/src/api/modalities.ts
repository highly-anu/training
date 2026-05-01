import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Modality } from './types'

export function useModalities() {
  return useQuery({
    queryKey: queryKeys.modalities.all,
    queryFn: () => apiClient.get<Modality[]>('/modalities') as unknown as Promise<Modality[]>,
    staleTime: Infinity,
  })
}

export function useCreateModality() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (modality: Partial<Modality>) =>
      apiClient.post('/modalities', modality) as unknown as Promise<Modality>,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.modalities.all })
    },
  })
}
