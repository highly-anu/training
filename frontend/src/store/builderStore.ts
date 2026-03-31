import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { AthleteConstraints, ModalityId } from '@/api/types'

type Step = 1 | 2 | 3 | 4
type Direction = 'forward' | 'backward'

interface BuilderStore {
  step: Step
  direction: Direction
  selectedGoalIds: string[]
  goalWeights: Record<string, number>
  constraints: Partial<AthleteConstraints>
  eventDate: string | null
  startDate: string | null

  // Step 2 — tune
  selectedFrameworkId: string | null
  priorityOverrides: Partial<Record<ModalityId, number>> | null
  numWeeks: number | null

  setStep: (step: Step, dir?: Direction) => void
  toggleGoal: (id: string) => void
  setGoalWeight: (id: string, weight: number) => void
  updateConstraints: (patch: Partial<AthleteConstraints>) => void
  setEventDate: (date: string | null) => void
  setStartDate: (date: string | null) => void
  setFramework: (id: string | null) => void
  setPriorityOverrides: (overrides: Partial<Record<ModalityId, number>> | null) => void
  setNumWeeks: (n: number | null) => void
  reset: () => void
  loadFromProgram: (opts: {
    goalIds: string[]
    goalWeights: Record<string, number>
    constraints: Partial<AthleteConstraints>
    numWeeks: number
    eventDate: string | null
  }) => void
}

const defaultConstraints: Partial<AthleteConstraints> = {
  days_per_week: 4,
  session_time_minutes: 60,
  weekday_session_minutes: 60,
  weekend_session_minutes: 90,
  allow_split_sessions: false,
  preferred_days: [1, 3, 5, 7],
  day_configs: {
    1: { minutes: 60, has_secondary: false },
    3: { minutes: 60, has_secondary: false },
    5: { minutes: 60, has_secondary: false },
    7: { minutes: 90, has_secondary: false },
  },
  training_level: 'intermediate',
  training_phase: 'base',
  periodization_week: 1,
  fatigue_state: 'normal',
  equipment: [],
  injury_flags: [],
  avoid_movements: [],
}

export const useBuilderStore = create<BuilderStore>()(
  persist(
    (set) => ({
      step: 1,
      direction: 'forward',
      selectedGoalIds: [],
      goalWeights: {},
      constraints: defaultConstraints,
      eventDate: null,
      startDate: null,
      selectedFrameworkId: null,
      priorityOverrides: null,
      numWeeks: null,

      setStep: (step, dir = 'forward') => set({ step, direction: dir }),
      toggleGoal: (id) =>
        set((s) => ({
          selectedGoalIds: s.selectedGoalIds.includes(id)
            ? s.selectedGoalIds.filter((gid) => gid !== id)
            : [...s.selectedGoalIds, id],
          // Reset tune state when goals change
          selectedFrameworkId: null,
          priorityOverrides: null,
          numWeeks: null,
        })),
      setGoalWeight: (id, weight) =>
        set((s) => ({ goalWeights: { ...s.goalWeights, [id]: weight } })),
      updateConstraints: (patch) =>
        set((s) => ({ constraints: { ...s.constraints, ...patch } })),
      setEventDate: (date) => set({ eventDate: date }),
      setStartDate: (date) => set({ startDate: date }),
      setFramework: (id) => set({ selectedFrameworkId: id }),
      setPriorityOverrides: (overrides) => set({ priorityOverrides: overrides }),
      setNumWeeks: (n) => set({ numWeeks: n }),
      reset: () =>
        set({
          step: 1,
          direction: 'forward',
          selectedGoalIds: [],
          goalWeights: {},
          constraints: defaultConstraints,
          eventDate: null,
          startDate: null,
          selectedFrameworkId: null,
          priorityOverrides: null,
          numWeeks: null,
        }),
      loadFromProgram: ({ goalIds, goalWeights, constraints, numWeeks, eventDate }) =>
        set({
          step: goalIds.length > 1 ? 2 : 3,
          direction: 'forward',
          selectedGoalIds: goalIds,
          goalWeights,
          constraints,
          eventDate,
          selectedFrameworkId: null,
          priorityOverrides: null,
          numWeeks,
        }),
    }),
    {
      name: 'training-builder',
      partialize: (s) => ({
        step: s.step,
        selectedGoalIds: s.selectedGoalIds,
        goalWeights: s.goalWeights,
        eventDate: s.eventDate,
        selectedFrameworkId: s.selectedFrameworkId,
        priorityOverrides: s.priorityOverrides,
        numWeeks: s.numWeeks,
      }),
    }
  )
)
