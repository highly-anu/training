import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { AthleteConstraints, Framework, ModalityId, Philosophy } from '@/api/types'
import { derivePhilosophyPriorities, philosophyHasSequentialPhases, primaryFrameworkFor } from '@/lib/philosophyPriorities'

type Step = 1 | 2 | 3 | 4
type Direction = 'forward' | 'backward'
export type SourceMode = 'philosophy' | 'blend' | 'custom'

interface BuilderStore {
  step: Step
  direction: Direction
  sourceMode: SourceMode | null
  selectedGoalIds: string[]
  goalWeights: Record<string, number>
  // Philosophy IDs selected in ProgramSource (modes 1 + 2)
  selectedPhilosophyIds: string[]
  // Blend weights for mode 2: philosophyId → weight (0–100 raw, normalized at generate time)
  philosophyWeights: Record<string, number>
  // The "original" priorities set by ProgramSource — used as reset baseline in ProgramTuner
  sourcePriorities: Partial<Record<ModalityId, number>> | null
  constraints: Partial<AthleteConstraints>
  eventDate: string | null
  startDate: string | null

  // Step 2 — tune
  selectedFrameworkId: string | null
  priorityOverrides: Partial<Record<ModalityId, number>> | null
  numWeeks: number | null

  setStep: (step: Step, dir?: Direction) => void
  setSourceMode: (mode: SourceMode | null) => void
  setGoalIds: (ids: string[]) => void
  setGoalWeightsBulk: (weights: Record<string, number>) => void
  setPhilosophyIds: (ids: string[]) => void
  setPhilosophyWeights: (weights: Record<string, number>) => void
  setSourcePriorities: (p: Partial<Record<ModalityId, number>> | null) => void
  toggleGoal: (id: string) => void
  setGoalWeight: (id: string, weight: number) => void
  updateConstraints: (patch: Partial<AthleteConstraints>) => void
  setEventDate: (date: string | null) => void
  setStartDate: (date: string | null) => void
  setFramework: (id: string | null) => void
  setPriorityOverrides: (overrides: Partial<Record<ModalityId, number>> | null) => void
  setNumWeeks: (n: number | null) => void
  reset: () => void
  /**
   * Explore → Builder. Starts a fresh draft at step 2 with the philosophy as
   * the source, exactly as picking it in step 1 would — the step is persisted,
   * so a stale half-finished wizard is cleared first.
   */
  prefillFromPhilosophy: (phil: Philosophy, frameworks: Framework[]) => void
  /** Same, with the framework fixed rather than left to the phase sequence. */
  prefillFromFramework: (fw: Framework, phil: Philosophy, frameworks: Framework[]) => void
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

const freshState = () => ({
  step: 1 as Step,
  direction: 'forward' as Direction,
  sourceMode: null as SourceMode | null,
  selectedGoalIds: [] as string[],
  goalWeights: {} as Record<string, number>,
  selectedPhilosophyIds: [] as string[],
  philosophyWeights: {} as Record<string, number>,
  sourcePriorities: null as Partial<Record<ModalityId, number>> | null,
  constraints: defaultConstraints,
  eventDate: null as string | null,
  startDate: null as string | null,
  selectedFrameworkId: null as string | null,
  priorityOverrides: null as Partial<Record<ModalityId, number>> | null,
  numWeeks: null as number | null,
})

function prefilled(phil: Philosophy, frameworks: Framework[], frameworkId: string | null) {
  const priorities = derivePhilosophyPriorities(phil, frameworks)
  return {
    ...freshState(),
    step: 2 as Step,
    sourceMode: 'philosophy' as SourceMode,
    selectedGoalIds: ['general_gpp'],
    selectedPhilosophyIds: [phil.id],
    sourcePriorities: priorities,
    priorityOverrides: priorities,
    selectedFrameworkId: frameworkId,
  }
}

export const useBuilderStore = create<BuilderStore>()(
  persist(
    (set) => ({
      step: 1,
      direction: 'forward',
      sourceMode: null,
      selectedGoalIds: [],
      goalWeights: {},
      selectedPhilosophyIds: [],
      philosophyWeights: {},
      sourcePriorities: null,
      constraints: defaultConstraints,
      eventDate: null,
      startDate: null,
      selectedFrameworkId: null,
      priorityOverrides: null,
      numWeeks: null,

      setStep: (step, dir = 'forward') => set({ step, direction: dir }),
      // Clearing source mode also resets philosophy context
      setSourceMode: (mode) => set({ sourceMode: mode, selectedPhilosophyIds: [], philosophyWeights: {}, sourcePriorities: null }),
      setGoalIds: (ids) => set({ selectedGoalIds: ids, selectedFrameworkId: null, priorityOverrides: null, numWeeks: null }),
      setGoalWeightsBulk: (weights) => set({ goalWeights: weights }),
      setPhilosophyIds: (ids) => set({ selectedPhilosophyIds: ids, selectedFrameworkId: null, priorityOverrides: null }),
      setPhilosophyWeights: (weights) => set({ philosophyWeights: weights }),
      setSourcePriorities: (p) => set({ sourcePriorities: p }),
      toggleGoal: (id) =>
        set((s) => ({
          selectedGoalIds: s.selectedGoalIds.includes(id)
            ? s.selectedGoalIds.filter((gid) => gid !== id)
            : [...s.selectedGoalIds, id],
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
      reset: () => set(freshState()),
      prefillFromPhilosophy: (phil, frameworks) =>
        set(prefilled(
          phil, frameworks,
          // A sequential-phase philosophy runs as a Full Program with no fixed framework.
          philosophyHasSequentialPhases(phil) ? null : (primaryFrameworkFor(phil, frameworks)?.id ?? null),
        )),
      prefillFromFramework: (fw, phil, frameworks) => set(prefilled(phil, frameworks, fw.id)),
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
      name: 'training-builder-v2',
      partialize: (s) => ({
        step: s.step,
        sourceMode: s.sourceMode,
        selectedGoalIds: s.selectedGoalIds,
        goalWeights: s.goalWeights,
        selectedPhilosophyIds: s.selectedPhilosophyIds,
        philosophyWeights: s.philosophyWeights,
        sourcePriorities: s.sourcePriorities,
        eventDate: s.eventDate,
        selectedFrameworkId: s.selectedFrameworkId,
        priorityOverrides: s.priorityOverrides,
        numWeeks: s.numWeeks,
      }),
    }
  )
)
