import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiClient } from './client'
import { queryKeys } from './queryKeys'
import { useProgramStore } from '@/store/programStore'
import { useUiStore } from '@/store/uiStore'
import { spliceRegenerated, tailResume } from '@/lib/programSource'
import type { AthleteConstraints, ConstraintChangeResult, ConstraintImpact, CustomInjuryFlag, FatigueState, GeneratedProgram, ModalityId, Session, TrainingLevel, TrainingPhase, TracedProgram, ExerciseAlternative, AdjustResult, ProgressionAdjustment } from './types'

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

export interface GenerateParams {
  // Philosophy-based program generation
  philosophyId?: string
  philosophyIds?: string[]
  philosophyWeights?: Record<string, number>
  constraints: AthleteConstraints
  eventDate?: string
  startDate?: string | null
  numWeeks?: number
  /**
   * `week_number` of the first generated week — a partial regenerate passes
   * the kept head's length + 1 so its tail continues the numbering instead
   * of restarting at 1 (which made a program read 1, 1, 2, 3).
   */
  weekInProgram?: number
  customInjuryFlags?: CustomInjuryFlag[]
  /** The track to run (null = the philosophy's primary track). */
  trackId?: string | null
  /** The track phase to start at (null = its first phase). */
  startPhaseId?: string | null
  /** Legacy: a framework pick, mapped server-side to its track and phase. */
  frameworkId?: string | null
  priorityOverrides?: Partial<Record<ModalityId, number>> | null
  /**
   * A regenerate only: sessions dated before this (YYYY-MM-DD, the athlete's
   * day) keep what they had, so the days already behind them in the week the
   * tail starts at are not rewritten (`spliceRegenerated`).
   */
  keepBefore?: string
}

export function buildPostBody(params: GenerateParams) {
  const multiPhil = params.philosophyIds && params.philosophyIds.length > 1
  const single = params.philosophyId ?? params.philosophyIds?.[0]
  if (!multiPhil && !single) {
    throw new Error("This program doesn't record which methodology built it. Build a new one from Program ▸ New.")
  }

  return {
    // Philosophy path
    ...(multiPhil
      ? { philosophy_ids: params.philosophyIds, philosophy_weights: params.philosophyWeights }
      : { philosophy_id: single }),
    constraints: params.constraints,
    ...(params.eventDate ? { event_date: params.eventDate } : {}),
    ...(params.startDate ? { start_date: params.startDate } : {}),
    ...(params.numWeeks ? { num_weeks: params.numWeeks } : {}),
    ...(params.weekInProgram ? { week_in_program: params.weekInProgram } : {}),
    ...(params.trackId ? { track_id: params.trackId } : {}),
    ...(params.startPhaseId ? { start_phase: params.startPhaseId } : {}),
    ...(params.frameworkId ? { framework_id: params.frameworkId } : {}),
    ...(params.priorityOverrides ? { priority_overrides: params.priorityOverrides } : {}),
    custom_injury_flags: params.customInjuryFlags ?? [],
  }
}

/** A generate the server could not build: the validator's refusal, or a
 *  training contract that cannot run as written. Shown, never saved. */
export function isInfeasible(program: GeneratedProgram | null | undefined): boolean {
  return !program || program.validation?.feasible === false || !(program.weeks?.length)
}

/**
 * Generate a draft: posts and returns, and writes nothing. The builder's
 * preview holds it until the athlete starts it (`commitProgram`).
 *
 * The builder used to save in this mutation's onSuccess, so a program
 * replaced the active one the moment it existed — and an infeasible answer
 * (200, no weeks) was PUT over it too.
 */
export function useGenerateDraft() {
  return useMutation({
    mutationFn: (params: GenerateParams) =>
      apiClient.post('/programs/generate', buildPostBody(params)) as unknown as Promise<GeneratedProgram>,
  })
}

/** Make a previewed draft the active program and save it (revision-checked PUT). */
export function commitProgram(
  queryClient: ReturnType<typeof useQueryClient>,
  draft: GeneratedProgram,
  params: Pick<GenerateParams, 'eventDate' | 'philosophyId' | 'philosophyIds' | 'philosophyWeights'>,
): boolean {
  if (isInfeasible(draft)) return false
  queryClient.setQueryData(queryKeys.programs.current, draft)
  const startMonday = draft.program_start_date ?? getMondayOf(new Date())
  // Single atomic update + server persist
  useProgramStore.getState().setFullProgram(
    draft,
    params.eventDate ?? null,
    startMonday,
    params.philosophyIds ?? [params.philosophyId ?? ''],
    params.philosophyWeights ?? {},
    // A rebuild of the same block keeps the days already behind the athlete.
    { keepDaysBehind: true },
  )
  useUiStore.getState().setSelectedWeekIndex(0)
  return true
}

/**
 * The active program with a regenerated tail in place: the kept head, then
 * the tail, never a day before `keepBefore` (`spliceRegenerated`). Null when
 * the tail is infeasible — splicing an empty answer used to drop every week
 * after the kept head.
 */
export function applyRegeneratedTail(
  current: GeneratedProgram | null,
  tail: GeneratedProgram,
  params: Pick<GenerateParams, 'numWeeks' | 'keepBefore'>,
  programStartDate: string | null,
): GeneratedProgram | null {
  if (isInfeasible(tail)) return null
  // Only replace the whole program when there is nothing to keep.
  if (!current) return tail
  // Without numWeeks the split point is unknown, so keep the existing weeks
  // the new run does not cover rather than dropping them — saving the bare
  // tail is how a program ended up as 16 weeks numbered 16...31.
  if (params.numWeeks === undefined) {
    const keep = Math.max(0, current.weeks.length - tail.weeks.length)
    return {
      ...tail,
      // The response summarised the tail alone; the save answers with the
      // summary of the spliced weeks.
      phase_summary: undefined,
      weeks: [...current.weeks.slice(0, keep), ...tail.weeks],
      volume_summary: [
        ...(current.volume_summary ?? []).slice(0, keep),
        ...(tail.volume_summary ?? []),
      ],
    }
  }
  const keepCount = Math.max(0, current.weeks.length - params.numWeeks)
  return {
    ...tail,
    phase_summary: undefined,  // the tail's alone; the save answers with the whole
    weeks: spliceRegenerated(current.weeks, tail.weeks, keepCount, programStartDate, params.keepBefore),
    volume_summary: [
      ...(current.volume_summary ?? []).slice(0, keepCount),
      ...(tail.volume_summary ?? []),
    ],
  }
}

/** Splice a regenerated tail into the active program and save it. False when it could not apply. */
export function commitRegeneratedTail(
  queryClient: ReturnType<typeof useQueryClient>,
  tail: GeneratedProgram,
  params: Pick<GenerateParams, 'numWeeks' | 'keepBefore'>,
): boolean {
  const s = useProgramStore.getState()
  const spliced = applyRegeneratedTail(s.currentProgram, tail, params, s.programStartDate)
  if (!spliced) return false
  queryClient.setQueryData(queryKeys.programs.current, spliced)
  s.setCurrentProgram(spliced)
  return true
}

export function useRegenerateFromWeek() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async (params: GenerateParams) => {
      const tail = await (apiClient.post('/programs/generate', buildPostBody(params)) as unknown as Promise<GeneratedProgram>)
      if (isInfeasible(tail)) {
        throw new Error(tail.validation?.errors?.[0]?.message ?? 'These settings cannot build the rest of the program.')
      }
      return tail
    },
    onSuccess: (tail, params) => {
      commitRegeneratedTail(queryClient, tail, params)
    },
  })
}

// ── Preview: what the constraints hold back, and whether a change matters ────

/** The heavy routes answer 429 while another run is in flight; wait and ask again. */
function retryBusy(failureCount: number, error: unknown): boolean {
  return (error as { status?: number })?.status === 429 && failureCount < 8
}

/**
 * Held back's request for a draft: the draft's own first track, phase and
 * week in phase and its length (the comparison runs at most 12 weeks), never
 * the event date. Sent as the builder's request, the impact sized itself by
 * defaults — 4 weeks from the track's first phase — and described another
 * program than an event-dated 20-week draft. A refused draft has no weeks:
 * its request, without the event date, at most 12 weeks.
 */
export function impactParams(params: GenerateParams, draft: GeneratedProgram | null | undefined): GenerateParams {
  const weeks = draft?.weeks ?? []
  const base: GenerateParams = { ...params, eventDate: undefined }
  if (weeks.length === 0) return { ...base, numWeeks: Math.min(params.numWeeks ?? 12, 12) }
  const resume = tailResume({ weeks, constraints: params.constraints }, 0)
  return {
    ...base,
    trackId: resume.trackId ?? params.trackId,
    startPhaseId: resume.startPhaseId ?? params.startPhaseId,
    constraints: resume.constraints,
    numWeeks: Math.min(weeks.length, 12),
  }
}

/**
 * The preview's "Held back": the program against a reference with nothing
 * in the way, and what each constraint changes (POST /programs/impact; up to
 * seven generations, so it loads after the draft is on screen). `params`
 * null disables the query.
 */
export function useProgramImpact(params: GenerateParams | null) {
  const body = params ? buildPostBody(params) : null
  return useQuery({
    queryKey: ['programs', 'impact', body],
    enabled: !!body,
    staleTime: Infinity,
    retry: retryBusy,
    retryDelay: 3000,
    queryFn: () =>
      apiClient.post('/programs/impact', body, { timeout: 120_000 }) as unknown as Promise<ConstraintImpact>,
  })
}

/**
 * Does a profile change change the program? Generates the remaining weeks
 * with the program's constraints and with the profile's, and compares
 * (POST /programs/constraint-change). `params` is the regenerate the profile
 * would ask for; `baseline` the program's own constraints for it.
 */
export function useConstraintChangeCheck(
  params: GenerateParams | null,
  baseline: AthleteConstraints | null,
  revision: string | null,
) {
  const body = params && baseline
    ? { ...buildPostBody(params), baseline_constraints: baseline }
    : null
  return useQuery({
    queryKey: ['programs', 'constraint-change', revision, body],
    enabled: !!body,
    staleTime: Infinity,
    retry: retryBusy,
    retryDelay: 3000,
    queryFn: () =>
      apiClient.post('/programs/constraint-change', body, { timeout: 120_000 }) as unknown as Promise<ConstraintChangeResult>,
  })
}

/**
 * The program holds for the profile's new constraints: record them on it so
 * the profile stops offering a regenerate (PATCH /user/program/constraints,
 * revision-checked). Updates the loaded copy without another PUT.
 */
export async function adoptProgramConstraints(
  constraints: Partial<Pick<AthleteConstraints, 'equipment' | 'training_level' | 'injury_flags' | 'days_per_week'>>,
  customInjuryFlags?: CustomInjuryFlag[],
): Promise<'adopted' | 'stale' | 'failed'> {
  const s = useProgramStore.getState()
  if (!s.currentProgram) return 'failed'
  try {
    const res = await (apiClient.patch('/user/program/constraints', {
      baseRevision: s.revision,
      constraints,
      ...(customInjuryFlags ? { custom_injury_flags: customInjuryFlags } : {}),
    }) as unknown as Promise<{ saved: boolean; revision: string; constraints: AthleteConstraints }>)
    if (!res.saved) return 'failed'
    s.adoptConstraints(res.constraints, res.revision)
    return 'adopted'
  } catch (err) {
    // Another copy saved since: read it; its revision asks the check again.
    if ((err as { status?: number })?.status === 409) {
      await s.loadFromServer()
      return 'stale'
    }
    return 'failed'
  }
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
  /** The week's phase and framework, so the server applies the phase's
   *  exclude_exercises and the framework's deload share. */
  phaseId?: string
  frameworkId?: string
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
        ...(p.phaseId ? { phase_id: p.phaseId } : {}),
        ...(p.frameworkId ? { framework_id: p.frameworkId } : {}),
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
  /** The week's phase and framework (see GenerateSessionParams). */
  phaseId?: string
  frameworkId?: string
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
        ...(p.phaseId ? { phase_id: p.phaseId } : {}),
        ...(p.frameworkId ? { framework_id: p.frameworkId } : {}),
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
