import { useQuery } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import type { GoalProfile } from './types'

export function useGoals() {
  return useQuery({
    queryKey: queryKeys.goals.all,
    queryFn: () => apiClient.get('/goals') as unknown as Promise<GoalProfile[]>,
    staleTime: Infinity,
  })
}

export function useGoal(id: string | null) {
  return useQuery({
    queryKey: queryKeys.goals.detail(id ?? ''),
    queryFn: () => apiClient.get(`/goals/${id}`) as unknown as Promise<GoalProfile>,
    enabled: !!id,
    staleTime: Infinity,
  })
}
