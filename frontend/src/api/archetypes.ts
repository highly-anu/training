import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Archetype } from './types'

export function useArchetypes() {
  return useQuery({
    queryKey: queryKeys.archetypes.all,
    queryFn: () => apiClient.get<Archetype[]>('/archetypes') as unknown as Promise<Archetype[]>,
    staleTime: Infinity,
  })
}

export function useCreateArchetype() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (archetype: Partial<Archetype>) =>
      apiClient.post('/archetypes', archetype) as unknown as Promise<Archetype>,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.archetypes.all })
    },
  })
}
