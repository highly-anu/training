import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { GeneratedProgram } from '@/api/types'

interface ProgramStore {
  currentProgram: GeneratedProgram | null
  programStartDate: string | null // YYYY-MM-DD
  eventDate: string | null        // YYYY-MM-DD — the race/event/goal date
  // Original goal IDs used to generate the program (may differ from program.goal.id when blended)
  sourceGoalIds: string[]
  sourceGoalWeights: Record<string, number>
  setCurrentProgram: (program: GeneratedProgram | null) => void
  setProgramStartDate: (date: string | null) => void
  setEventDate: (date: string | null) => void
  setSourceGoals: (ids: string[], weights: Record<string, number>) => void
  /** Move a session from one day to another within the same week. Pure client-side override. */
  moveSession: (weekIndex: number, fromDay: string, toDay: string, sessionIndex: number) => void
}

export const useProgramStore = create<ProgramStore>()(
  persist(
    (set) => ({
      currentProgram: null,
      programStartDate: null,
      eventDate: null,
      sourceGoalIds: [],
      sourceGoalWeights: {},
      setCurrentProgram: (program) => set({ currentProgram: program }),
      setProgramStartDate: (date) => set({ programStartDate: date }),
      setEventDate: (date) => set({ eventDate: date }),
      setSourceGoals: (ids, weights) => set({ sourceGoalIds: ids, sourceGoalWeights: weights }),
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
      },
    }),
    { name: 'training-program' }
  )
)
