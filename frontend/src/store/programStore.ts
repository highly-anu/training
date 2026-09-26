import { create } from 'zustand'
import type { GeneratedProgram, Session } from '@/api/types'
import { fetchUserProgram, saveUserProgram } from '@/api/userdata'

interface ProgramStore {
  currentProgram: GeneratedProgram | null
  programLoadState: 'idle' | 'loading' | 'loaded' | 'error'
  /** Which account the loaded program belongs to, so a switch clears it. */
  loadedForUserId: string | null
  programStartDate: string | null // YYYY-MM-DD
  eventDate: string | null        // YYYY-MM-DD — the race/event/goal date
  sourceGoalIds: string[]
  sourceGoalWeights: Record<string, number>
  /** Revision of the server copy this state was loaded from; sent on save so a
   *  stale write is rejected instead of clobbering newer work. */
  revision: string | null
  setCurrentProgram: (program: GeneratedProgram | null) => void
  /** Set program + all metadata atomically and persist to server. Use after generation. */
  setFullProgram: (
    program: GeneratedProgram,
    eventDate: string | null,
    startDate: string | null,
    sourceGoalIds: string[],
    sourceGoalWeights: Record<string, number>
  ) => void
  setProgramStartDate: (date: string | null) => void
  setEventDate: (date: string | null) => void
  setSourceGoals: (ids: string[], weights: Record<string, number>) => void
  /** Move a session from one day to another within the same week. Pure client-side override. */
  moveSession: (weekIndex: number, fromDay: string, toDay: string, sessionIndex: number) => void
  /** Replace a single session at the given position with a new one. */
  replaceSession: (weekIndex: number, day: string, sessionIndex: number, newSession: Session) => void
  /** Load program from server (called on login). */
  loadFromServer: (userId?: string) => Promise<void>
}

/** The fields a program load owns, in their empty form. */
const EMPTY_PROGRAM_STATE = {
  currentProgram: null,
  programStartDate: null,
  eventDate: null,
  sourceGoalIds: [] as string[],
  sourceGoalWeights: {} as Record<string, number>,
  revision: null,
} as const

export const useProgramStore = create<ProgramStore>()((set, get) => ({
  currentProgram: null,
  programLoadState: 'idle',
  loadedForUserId: null,
  programStartDate: null,
  eventDate: null,
  sourceGoalIds: [],
  sourceGoalWeights: {},
  revision: null,

  setCurrentProgram: (currentProgram) => {
    set({ currentProgram })
    const s = get()
    saveUserProgram({
      currentProgram,
      programStartDate: s.programStartDate,
      eventDate: s.eventDate,
      sourceGoalIds: s.sourceGoalIds,
      sourceGoalWeights: s.sourceGoalWeights,
      revision: s.revision,
    })
  },

  setFullProgram: (program, eventDate, startDate, sourceGoalIds, sourceGoalWeights) => {
    set({
      currentProgram:     program,
      programLoadState:   'loaded',
      eventDate,
      programStartDate:   startDate,
      sourceGoalIds,
      sourceGoalWeights,
      revision: get().revision,
    })
    saveUserProgram({
      currentProgram:     program,
      programStartDate:   startDate,
      eventDate,
      sourceGoalIds,
      sourceGoalWeights,
      revision: get().revision,
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
      saveUserProgram({
        currentProgram:     s.currentProgram,
        programStartDate:   s.programStartDate,
        eventDate:          s.eventDate,
        sourceGoalIds:      s.sourceGoalIds,
        sourceGoalWeights:  s.sourceGoalWeights,
        revision:           s.revision,
      })
    }
  },

  replaceSession: (weekIndex, day, sessionIndex, newSession) => {
    set((state) => {
      if (!state.currentProgram) return {}
      const weeks = state.currentProgram.weeks.map((week, i) => {
        if (i !== weekIndex) return week
        const sessions = [...(week.schedule[day] ?? [])]
        if (sessionIndex < 0 || sessionIndex >= sessions.length) return week
        sessions[sessionIndex] = newSession
        return { ...week, schedule: { ...week.schedule, [day]: sessions } }
      })
      return { currentProgram: { ...state.currentProgram, weeks } }
    })
    const s = get()
    if (s.currentProgram) {
      saveUserProgram({
        currentProgram:    s.currentProgram,
        programStartDate:  s.programStartDate,
        eventDate:         s.eventDate,
        sourceGoalIds:     s.sourceGoalIds,
        sourceGoalWeights: s.sourceGoalWeights,
      })
    }
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
