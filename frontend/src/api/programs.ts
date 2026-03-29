import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import { useProgramStore } from '@/store/programStore'
import { useBuilderStore } from '@/store/builderStore'
import { useUiStore } from '@/store/uiStore'
import type { AthleteConstraints, CustomInjuryFlag, GeneratedProgram, ModalityId, TracedProgram } from './types'

interface GenerateParams {
  goalId: string
  goalIds?: string[]
  goalWeights?: Record<string, number>
  constraints: AthleteConstraints
  eventDate?: string
  numWeeks?: number
  customInjuryFlags?: CustomInjuryFlag[]
  frameworkId?: string | null
  priorityOverrides?: Partial<Record<ModalityId, number>> | null
}

function buildPostBody(params: GenerateParams) {
  const multi = params.goalIds && params.goalIds.length > 1
  return {
    ...(multi
      ? { goal_ids: params.goalIds, goal_weights: params.goalWeights }
      : { goal_id: params.goalId }),
    constraints: params.constraints,
    ...(params.eventDate ? { event_date: params.eventDate } : {}),
    ...(params.numWeeks ? { num_weeks: params.numWeeks } : {}),
    ...(params.frameworkId ? { framework_id: params.frameworkId } : {}),
    ...(params.priorityOverrides ? { priority_overrides: params.priorityOverrides } : {}),
    custom_injury_flags: params.customInjuryFlags ?? [],
  }
}

export function useGenerateProgram() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (params: GenerateParams) =>
      apiClient.post('/programs/generate', buildPostBody(params)) as unknown as Promise<GeneratedProgram>,
    onSuccess: (data, params) => {
      queryClient.setQueryData(queryKeys.programs.current, data)
      const store = useProgramStore.getState()
      store.setCurrentProgram(data)
      store.setEventDate(params.eventDate ?? null)
      const ids = (params.goalIds ?? [params.goalId]).filter((id) => id !== '_blended')
      store.setSourceGoals(ids, params.goalWeights ?? {})
      if (!store.programStartDate) {
        store.setProgramStartDate(new Date().toISOString().slice(0, 10))
      }
      useBuilderStore.getState().reset()
      useUiStore.getState().setSelectedWeekIndex(0)
    },
  })
}

export function useRegenerateFromWeek() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (params: GenerateParams) =>
      apiClient.post('/programs/generate', buildPostBody(params)) as unknown as Promise<GeneratedProgram>,
    onSuccess: (newPartial, params) => {
      const current = useProgramStore.getState().currentProgram
      if (!current || params.numWeeks === undefined) {
        queryClient.setQueryData(queryKeys.programs.current, newPartial)
        useProgramStore.getState().setCurrentProgram(newPartial)
        return
      }
      const keepCount = current.weeks.length - params.numWeeks
      const spliced: GeneratedProgram = {
        ...newPartial,
        weeks: [...current.weeks.slice(0, keepCount), ...newPartial.weeks],
        volume_summary: [
          ...(current.volume_summary ?? []).slice(0, keepCount),
          ...(newPartial.volume_summary ?? []),
        ],
      }
      queryClient.setQueryData(queryKeys.programs.current, spliced)
      useProgramStore.getState().setCurrentProgram(spliced)
    },
  })
}

export function useCurrentProgram(): GeneratedProgram | undefined {
  return useProgramStore((s) => s.currentProgram) ?? undefined
}

// Dev-only: generates with full trace, does NOT update the program store
export function useGenerateWithTrace() {
  return useMutation({
    mutationFn: (params: GenerateParams) =>
      apiClient.post('/programs/generate?trace=1', buildPostBody(params)) as unknown as Promise<TracedProgram>,
  })
}
