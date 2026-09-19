import { create } from 'zustand'
import type { GeneratedProgram, Session } from '@/api/types'
import { fetchUserProgram, saveUserProgram } from '@/api/userdata'

interface ProgramStore {
  currentProgram: GeneratedProgram | null
  programLoadState: 'idle' | 'loading' | 'loaded'
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
  loadFromServer: () => Promise<void>
}

export const useProgramStore = create<ProgramStore>()((set, get) => ({
  currentProgram: null,
  programLoadState: 'idle',
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

  loadFromServer: async () => {
    set({
      programLoadState: 'loading',
      currentProgram: null,
      programStartDate: null,
      eventDate: null,
      sourceGoalIds: [],
      sourceGoalWeights: {},
      revision: null,
    })
    try {
      const data = await fetchUserProgram()
      set({
        programLoadState:  'loaded',
        currentProgram:    data?.currentProgram ?? null,
        programStartDate:  data?.programStartDate ?? null,
        eventDate:         data?.eventDate ?? null,
        sourceGoalIds:     data?.sourceGoalIds ?? [],
        sourceGoalWeights: data?.sourceGoalWeights ?? {},
        revision:          data?.revision ?? null,
      })
    } catch {
      set({ programLoadState: 'loaded' })
    }
  },
}))
