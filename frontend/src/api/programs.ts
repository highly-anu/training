import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import { useProgramStore } from '@/store/programStore'
import { useBuilderStore } from '@/store/builderStore'
import { useUiStore } from '@/store/uiStore'
import type { AthleteConstraints, CustomInjuryFlag, FatigueState, GeneratedProgram, ModalityId, Session, TrainingLevel, TrainingPhase, TracedProgram } from './types'

function getMondayOf(date: Date): string {
  const d = new Date(date)
  const day = d.getDay() // 0=Sun
  d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day))
  // Use local date parts to avoid UTC offset shifting the day
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

interface GenerateParams {
  goalId: string
  goalIds?: string[]
  goalWeights?: Record<string, number>
  constraints: AthleteConstraints
  eventDate?: string
  startDate?: string | null
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
    ...(params.startDate ? { start_date: params.startDate } : {}),
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
      const ids = (params.goalIds ?? [params.goalId]).filter((id) => id !== '_blended')
      const startMonday = data.program_start_date ?? getMondayOf(new Date())
      // Single atomic update + server persist
      useProgramStore.getState().setFullProgram(
        data,
        params.eventDate ?? null,
        startMonday,
        ids,
        params.goalWeights ?? {}
      )
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
      const keepCount = Math.max(0, current.weeks.length - params.numWeeks)
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

export interface GenerateSessionParams {
  goalId: string
  modality: ModalityId
  phase: TrainingPhase
  weekInPhase: number
  isDeload: boolean
  constraints: {
    session_time_minutes: number
    equipment: string[]
    injury_flags: string[]
    training_level: TrainingLevel
    fatigue_state: FatigueState
  }
  customInjuryFlags?: CustomInjuryFlag[]
  archetypeId?: string
}

export function useGenerateSession() {
  return useMutation({
    mutationFn: (p: GenerateSessionParams) =>
      apiClient.post('/sessions/generate', {
        goal_id: p.goalId,
        modality: p.modality,
        phase: p.phase,
        week_in_phase: p.weekInPhase,
        is_deload: p.isDeload,
        constraints: p.constraints,
        custom_injury_flags: p.customInjuryFlags ?? [],
        ...(p.archetypeId ? { archetype_id: p.archetypeId } : {}),
      }) as unknown as Promise<Session>,
  })
}

// Dev-only: generates with full trace, does NOT update the program store
export function useGenerateWithTrace() {
  return useMutation({
    mutationFn: (params: GenerateParams) =>
      apiClient.post('/programs/generate?trace=1', buildPostBody(params)) as unknown as Promise<TracedProgram>,
  })
}
