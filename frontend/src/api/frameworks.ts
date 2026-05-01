import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { Framework } from './types'

export function useFrameworks() {
  return useQuery({
    queryKey: queryKeys.frameworks.all,
    queryFn: () => apiClient.get<Framework[]>('/frameworks') as unknown as Promise<Framework[]>,
    staleTime: 60_000,
  })
}

export function useUpdateFramework() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, ...data }: Partial<Framework> & { id: string }) =>
      apiClient.put(`/frameworks/${id}`, data) as unknown as Promise<Framework>,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.frameworks.all })
    },
  })
}
