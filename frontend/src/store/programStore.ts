import { create } from 'zustand'
import type { AthleteConstraints, ExerciseAssignment, GeneratedProgram, Session } from '@/api/types'
import { fetchUserProgram, saveUserProgram, lastProgramSaveError } from '@/api/userdata'
import { withExerciseReplaced, withSessionAdded, withSessionRemoved, withSessionReplaced } from '@/lib/programEdits'

interface ProgramStore {
  currentProgram: GeneratedProgram | null
  programLoadState: 'idle' | 'loading' | 'loaded' | 'error'
  /** Which account the loaded program belongs to, so a switch clears it. */
  loadedForUserId: string | null
  /**
   * Why the last program save failed, or null when it succeeded.
   *
   * Every mutation persists fire-and-forget, so without this a failed save is
   * invisible: the browser shows a program the server never received, and it
   * disappears on reload. 'stale_revision' means someone else's copy won.
   */
  programSaveError: string | null
  programStartDate: string | null // YYYY-MM-DD
  eventDate: string | null        // YYYY-MM-DD — the race/event/goal date
  sourceGoalIds: string[]
  sourceGoalWeights: Record<string, number>
  /** Revision of the server copy this state was loaded from; sent on save so a
   *  stale write is rejected instead of clobbering newer work. */
  revision: string | null
  /**
   * Which archived program version the loaded program is.
   *
   * What makes it possible to tell a match on *this* week 3 Monday from one
   * recorded against a plan that has since been replaced — see
   * lib/sessionMatching.ts. Read-only: the server derives it.
   */
  programVersionId: string | null
  setCurrentProgram: (program: GeneratedProgram | null) => void
  /** Set program + all metadata atomically and persist to server. Use after generation. */
  setFullProgram: (
    program: GeneratedProgram,
    eventDate: string | null,
    startDate: string | null,
    sourceGoalIds: string[],
    sourceGoalWeights: Record<string, number>,
    /** keepDaysBehind: a previewed program's Start — a rebuild of the same
     *  block keeps the days already behind the athlete (server-side). */
    options?: { keepDaysBehind?: boolean },
  ) => void
  setProgramStartDate: (date: string | null) => void
  setEventDate: (date: string | null) => void
  setSourceGoals: (ids: string[], weights: Record<string, number>) => void
  /** Move a session from one day to another within the same week. Pure client-side override. */
  moveSession: (weekIndex: number, fromDay: string, toDay: string, sessionIndex: number) => void
  /** Replace a single session at the given position with a new one. */
  replaceSession: (weekIndex: number, day: string, sessionIndex: number, newSession: Session) => void
  /** A session the athlete adds on the fly (today or later), then saved. */
  addSession: (weekIndex: number, day: string, newSession: Session) => void
  /** Removes a session the athlete added, then saved. */
  removeSession: (weekIndex: number, day: string, sessionIndex: number) => void
  /** Replace one exercise inside a session (the swap flow). */
  replaceExercise: (weekIndex: number, day: string, sessionIndex: number, exerciseIndex: number, assignment: ExerciseAssignment) => void
  /**
   * The server recorded the profile's constraints on the program
   * (PATCH /user/program/constraints): take them and the new revision, with
   * no save of our own.
   */
  adoptConstraints: (constraints: AthleteConstraints, revision: string) => void
  /** Load program from server (called on login). */
  loadFromServer: (userId?: string) => Promise<void>
}

/**
 * Persist the program and remember whether it worked.
 *
 * saveUserProgram already retries once and returns false on failure, but every
 * caller discarded that boolean and `lastProgramSaveError` was exported and
 * read by nothing — so a transient 5xx after a generate left the browser
 * showing a program the server never received, with no signal, until a reload
 * silently lost it.
 */
async function persistProgram(
  set: (partial: Partial<ProgramStore>) => void,
  payload: Parameters<typeof saveUserProgram>[0],
) {
  const ok = await saveUserProgram(payload)
  set({
    programSaveError: ok ? null : (lastProgramSaveError ?? 'save_failed'),
    // saveUserProgram advances the revision in place on success.
    revision: payload.revision ?? null,
  })
  // The server put back days already behind the athlete (a Start with
  // keepDaysBehind): what it stored is not what is on screen, so read it.
  if (ok && (payload.keptDays ?? 0) > 0) {
    await useProgramStore.getState().loadFromServer()
    return
  }
  // The server's summary of the weeks just saved (a move, a swap, a spliced
  // regenerate). Applied only while that copy is still the one on screen.
  const current = useProgramStore.getState().currentProgram
  if (ok && payload.phaseSummary && current && current === payload.currentProgram) {
    set({ currentProgram: { ...current, phase_summary: payload.phaseSummary } })
  }
}

/** The fields a program load owns, in their empty form. */
const EMPTY_PROGRAM_STATE = {
  currentProgram: null,
  programStartDate: null,
  eventDate: null,
  sourceGoalIds: [] as string[],
  sourceGoalWeights: {} as Record<string, number>,
  revision: null,
  programVersionId: null,
} as const

export const useProgramStore = create<ProgramStore>()((set, get) => ({
  currentProgram: null,
  programLoadState: 'idle',
  loadedForUserId: null,
  programSaveError: null,
  programStartDate: null,
  eventDate: null,
  sourceGoalIds: [],
  sourceGoalWeights: {},
  revision: null,
  programVersionId: null,

  setCurrentProgram: (currentProgram) => {
    set({ currentProgram })
    const s = get()
    void persistProgram(set, {
      currentProgram,
      programStartDate: s.programStartDate,
      eventDate: s.eventDate,
      sourceGoalIds: s.sourceGoalIds,
      sourceGoalWeights: s.sourceGoalWeights,
      revision: s.revision,
    })
  },

  setFullProgram: (program, eventDate, startDate, sourceGoalIds, sourceGoalWeights, options) => {
    set({
      currentProgram:     program,
      programLoadState:   'loaded',
      eventDate,
      programStartDate:   startDate,
      sourceGoalIds,
      sourceGoalWeights,
      revision: get().revision,
    })
    void persistProgram(set, {
      currentProgram:     program,
      programStartDate:   startDate,
      eventDate,
      sourceGoalIds,
      sourceGoalWeights,
      revision: get().revision,
      ...(options?.keepDaysBehind ? { keepDaysBehind: true } : {}),
    })
  },

  setProgramStartDate: (programStartDate) => set({ programStartDate }),
  setEventDate: (eventDate) => set({ eventDate }),
  setSourceGoals: (sourceGoalIds, sourceGoalWeights) => set({ sourceGoalIds, sourceGoalWeights }),

  moveSession: (weekIndex, fromDay, toDay, sessionIndex) => {
    set((state) => {
      if (!state.currentProgram) return {}
      const weeks = state.currentProgram.weeks.map((week, i) => {
        if (i !== weekIndex) return week
        const fromSessions = [...(week.schedule[fromDay] ?? [])]
        const [session] = fromSessions.splice(sessionIndex, 1)
        if (!session) return week
        const toSessions = [...(week.schedule[toDay] ?? []), session]
        return {
          ...week,
          schedule: { ...week.schedule, [fromDay]: fromSessions, [toDay]: toSessions },
        }
      })
      return { currentProgram: { ...state.currentProgram, weeks } }
    })
    const s = get()
    if (s.currentProgram) {
      void persistProgram(set, {
        currentProgram:     s.currentProgram,
        programStartDate:   s.programStartDate,
        eventDate:          s.eventDate,
        sourceGoalIds:      s.sourceGoalIds,
        sourceGoalWeights:  s.sourceGoalWeights,
        revision:           s.revision,
      })
    }
  },

  // Both saves send the loaded revision: without it the PUT went unchecked
  // and persistProgram then cleared the revision, so every later save from
  // this tab was unchecked too.
  replaceSession: (weekIndex, day, sessionIndex, newSession) => {
    set((state) => state.currentProgram
      ? { currentProgram: withSessionReplaced(state.currentProgram, weekIndex, day, sessionIndex, newSession) }
      : {})
    const s = get()
    if (s.currentProgram) {
      void persistProgram(set, {
        currentProgram:    s.currentProgram,
        programStartDate:  s.programStartDate,
        eventDate:         s.eventDate,
        sourceGoalIds:     s.sourceGoalIds,
        sourceGoalWeights: s.sourceGoalWeights,
        revision:          s.revision,
      })
    }
  },

  addSession: (weekIndex, day, newSession) => {
    set((state) => state.currentProgram
      ? { currentProgram: withSessionAdded(state.currentProgram, weekIndex, day, newSession) }
      : {})
    const s = get()
    if (s.currentProgram) {
      void persistProgram(set, {
        currentProgram:    s.currentProgram,
        programStartDate:  s.programStartDate,
        eventDate:         s.eventDate,
        sourceGoalIds:     s.sourceGoalIds,
        sourceGoalWeights: s.sourceGoalWeights,
        revision:          s.revision,
      })
    }
  },

  removeSession: (weekIndex, day, sessionIndex) => {
    set((state) => state.currentProgram
      ? { currentProgram: withSessionRemoved(state.currentProgram, weekIndex, day, sessionIndex) }
      : {})
    const s = get()
    if (s.currentProgram) {
      void persistProgram(set, {
        currentProgram:    s.currentProgram,
        programStartDate:  s.programStartDate,
        eventDate:         s.eventDate,
        sourceGoalIds:     s.sourceGoalIds,
        sourceGoalWeights: s.sourceGoalWeights,
        revision:          s.revision,
      })
    }
  },

  replaceExercise: (weekIndex, day, sessionIndex, exerciseIndex, assignment) => {
    set((state) => state.currentProgram
      ? { currentProgram: withExerciseReplaced(state.currentProgram, weekIndex, day, sessionIndex,
                                               exerciseIndex, assignment) }
      : {})
    const s = get()
    if (s.currentProgram) {
      void persistProgram(set, {
        currentProgram:    s.currentProgram,
        programStartDate:  s.programStartDate,
        eventDate:         s.eventDate,
        sourceGoalIds:     s.sourceGoalIds,
        sourceGoalWeights: s.sourceGoalWeights,
        revision:          s.revision,
      })
    }
  },

  adoptConstraints: (constraints, revision) => {
    set((state) => state.currentProgram
      ? { currentProgram: { ...state.currentProgram, constraints }, revision }
      : {})
  },

  loadFromServer: async (userId?: string) => {
    // Blank the store only when the ACCOUNT changed, not on every load.
    //
    // Blanking every time made React StrictMode's double-invoke flash the
    // empty state — the dashboard visibly alternated between "Retrieving your
    // program..." and "no program". Never blanking was worse: nothing else
    // clears this store on sign-out or account switch, so account A's program
    // and revision survived into account B's session until the fetch
    // resolved, and any save in that window PUT A's program into B's row.
    const previousUser = get().loadedForUserId
    if (userId !== undefined && userId !== previousUser) {
      set({ ...EMPTY_PROGRAM_STATE, loadedForUserId: userId })
    }

    set({ programLoadState: 'loading' })
    try {
      const data = await fetchUserProgram()
      set({
        programLoadState:  'loaded',
        loadedForUserId:   userId ?? get().loadedForUserId,
        currentProgram:    data?.currentProgram ?? null,
        programStartDate:  data?.programStartDate ?? null,
        eventDate:         data?.eventDate ?? null,
        sourceGoalIds:     data?.sourceGoalIds ?? [],
        sourceGoalWeights: data?.sourceGoalWeights ?? {},
        revision:          data?.revision ?? null,
        programVersionId:  data?.programVersionId ?? null,
      })
    } catch (err) {
      // The request failed — which is NOT the same as having no program.
      // Staying in 'error' keeps the "build your first program" offer off the
      // screen, because acting on it would overwrite a program that is
      // probably still there.
      console.error('[program] load failed', err)
      set({ ...EMPTY_PROGRAM_STATE, loadedForUserId: userId ?? previousUser,
            programLoadState: 'error' })
    }
  },
}))
