import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { GoalProfile } from './types'

export function useGoals() {
  return useQuery({
    queryKey: queryKeys.goals.all,
    queryFn: () => apiClient.get<GoalProfile[]>('/goals') as unknown as Promise<GoalProfile[]>,
    staleTime: Infinity,
  })
}

export function useGoal(id: string | null) {
  return useQuery({
    queryKey: queryKeys.goals.detail(id ?? ''),
    queryFn: () => apiClient.get<GoalProfile>(`/goals/${id}`) as unknown as Promise<GoalProfile>,
    enabled: !!id,
    staleTime: Infinity,
  })
}

export function useCreateGoal() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (goal: Partial<GoalProfile>) =>
      apiClient.post('/goals', goal) as unknown as Promise<GoalProfile>,
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: queryKeys.goals.all })
    },
  })
}
