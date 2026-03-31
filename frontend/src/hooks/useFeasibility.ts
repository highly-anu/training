import { useMemo } from 'react'
import { useBuilderStore } from '@/store/builderStore'
import { useGoals } from '@/api/goals'
import { computeFeasibility } from '@/lib/feasibility'
import type { FeasibilitySignal } from '@/lib/feasibility'

export function useFeasibility(): FeasibilitySignal[] {
  const selectedGoalIds = useBuilderStore((s) => s.selectedGoalIds)
  const goalWeights     = useBuilderStore((s) => s.goalWeights)
  const constraints     = useBuilderStore((s) => s.constraints)
  const numWeeks        = useBuilderStore((s) => s.numWeeks)

  const { data: goals } = useGoals()

  return useMemo(() => {
    if (!goals || !selectedGoalIds.length) return []
    return computeFeasibility(goals, selectedGoalIds, goalWeights, constraints, numWeeks)
  }, [goals, selectedGoalIds, goalWeights, constraints, numWeeks])
}
