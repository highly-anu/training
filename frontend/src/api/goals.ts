import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import type { GoalProfile } from './types'
import goalsData from '@/data/static/goals.json'

const _goals = goalsData as unknown as GoalProfile[]

export function useGoals() {
  return useQuery({
    queryKey: queryKeys.goals.all,
    queryFn: () => Promise.resolve(_goals),
    staleTime: Infinity,
  })
}

export function useGoal(id: string | null) {
  return useQuery({
    queryKey: queryKeys.goals.detail(id ?? ''),
    queryFn: () => {
      const goal = _goals.find((g) => g.id === id)
      if (!goal) throw new Error(`Goal not found: ${id}`)
      return Promise.resolve(goal)
    },
    enabled: !!id,
    staleTime: Infinity,
  })
}
