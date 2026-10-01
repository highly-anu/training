import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import { useProgramStore } from '@/store/programStore'
import { useUiStore } from '@/store/uiStore'
import type { AthleteConstraints, CustomInjuryFlag, FatigueState, GeneratedProgram, ModalityId, Session, TrainingLevel, TrainingPhase, TracedProgram, ExerciseAlternative, AdjustResult, ProgressionAdjustment } from './types'

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
  // Philosophy-based program generation
  philosophyId?: string
  philosophyIds?: string[]
  philosophyWeights?: Record<string, number>
  constraints: AthleteConstraints
  eventDate?: string
  startDate?: string | null
  numWeeks?: number
  customInjuryFlags?: CustomInjuryFlag[]
  frameworkId?: string | null
  priorityOverrides?: Partial<Record<ModalityId, number>> | null
}

function buildPostBody(params: GenerateParams) {
  const multiPhil = params.philosophyIds && params.philosophyIds.length > 1

  return {
    // Philosophy path
    ...(multiPhil
      ? { philosophy_ids: params.philosophyIds, philosophy_weights: params.philosophyWeights }
      : { philosophy_id: params.philosophyId ?? params.philosophyIds![0] }),
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
      const startMonday = data.program_start_date ?? getMondayOf(new Date())
      // Single atomic update + server persist
      useProgramStore.getState().setFullProgram(
        data,
        params.eventDate ?? null,
        startMonday,
        params.philosophyIds ?? [params.philosophyId ?? ''],
        params.philosophyWeights ?? {}
      )
      // Note: reset() is NOT called here — ReviewGenerate calls it after navigation
      // so infeasible results don't silently bounce the user back to step 1.
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
      // Only replace the whole program when there is nothing to keep.
      //
      // This used to also fall through when numWeeks was undefined, saving just
      // the regenerated TAIL and discarding every earlier week — which is how a
      // program ends up stored as 16 weeks numbered 16...31 with no weeks 1-15.
      // Without numWeeks we cannot know the split point, so keep the existing
      // weeks the new run does not cover rather than dropping them.
      if (!current) {
        queryClient.setQueryData(queryKeys.programs.current, newPartial)
        useProgramStore.getState().setCurrentProgram(newPartial)
        return
      }
      if (params.numWeeks === undefined) {
        const keep = Math.max(0, current.weeks.length - newPartial.weeks.length)
        const merged: GeneratedProgram = {
          ...newPartial,
          weeks: [...current.weeks.slice(0, keep), ...newPartial.weeks],
          volume_summary: [
            ...(current.volume_summary ?? []).slice(0, keep),
            ...(newPartial.volume_summary ?? []),
          ],
        }
        queryClient.setQueryData(queryKeys.programs.current, merged)
        useProgramStore.getState().setCurrentProgram(merged)
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
  primarySources?: string[]  // Philosophy IDs to prefer archetypes from
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
        primary_sources: p.primarySources ?? [],
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

// ── Exercise-level swap ────────────────────────────────────────────────────────

export interface SubstituteParams {
  archetypeId: string
  slotRole: string
  exerciseId: string
  modality: string
  constraints: AthleteConstraints
  philosophyIds: string[]
  phase: string
  weekInPhase: number
  isDeload: boolean
  exclude?: string[]
  limit?: number
}

/**
 * Ranked alternatives for one exercise in one slot. The server runs the
 * selector's own filter and score, so a swap respects the same package,
 * equipment, injury and level rules as a generate; the client replaces the
 * assignment and saves through the revision-checked PUT.
 */
export function useSubstituteExercise() {
  return useMutation({
    mutationFn: (p: SubstituteParams) =>
      apiClient.post('/exercises/substitute', {
        archetype_id: p.archetypeId,
        slot_role: p.slotRole,
        exercise_id: p.exerciseId,
        modality: p.modality,
        constraints: p.constraints,
        philosophy_ids: p.philosophyIds,
        phase: p.phase,
        week_in_phase: p.weekInPhase,
        is_deload: p.isDeload,
        exclude: p.exclude ?? [],
        limit: p.limit ?? 8,
      }) as unknown as Promise<{ alternatives: ExerciseAlternative[] }>,
  })
}

// ── Applying a progression adjustment ──────────────────────────────────────────

/**
 * Apply one of the review's suggested adjustments to the stored program from
 * a week onward. Sends the loaded revision so a stale copy is refused (409)
 * rather than overwriting newer work; reloads the program on success.
 */
export function useApplyAdjustment() {
  return useMutation({
    mutationFn: (p: { adjustment: ProgressionAdjustment; fromWeekIndex: number | null }) =>
      apiClient.post('/programs/adjust', {
        adjustment: { type: p.adjustment.type, target: p.adjustment.target, magnitude: p.adjustment.magnitude },
        from_week_index: p.fromWeekIndex,
        baseRevision: useProgramStore.getState().revision,
      }) as unknown as Promise<AdjustResult>,
    onSuccess: () => {
      void useProgramStore.getState().loadFromServer()
    },
  })
}
