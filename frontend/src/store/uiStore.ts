import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { ExerciseFilters, ModalityId } from '@/api/types'

interface UiStore {
  /** The navigation drawer under `md`; never open on load. */
  mobileNavOpen: boolean
  selectedExerciseId: string | null
  exerciseFilters: ExerciseFilters
  activeModalityFilter: ModalityId[]
  selectedWeekIndex: number

  setMobileNavOpen: (open: boolean) => void
  setSelectedExercise: (id: string | null) => void
  setExerciseFilters: (filters: ExerciseFilters) => void
  setActiveModalityFilter: (modalities: ModalityId[]) => void
  setSelectedWeekIndex: (index: number) => void
}

export const useUiStore = create<UiStore>()(
  persist(
    (set) => ({
      mobileNavOpen: false,
      selectedExerciseId: null,
      exerciseFilters: {},
      activeModalityFilter: [],
      selectedWeekIndex: 0,

      setMobileNavOpen: (open) => set({ mobileNavOpen: open }),
      setSelectedExercise: (id) => set({ selectedExerciseId: id }),
      setExerciseFilters: (filters) => set({ exerciseFilters: filters }),
      setActiveModalityFilter: (modalities) => set({ activeModalityFilter: modalities }),
      setSelectedWeekIndex: (index) => set({ selectedWeekIndex: index }),
    }),
    {
      name: 'training-ui',
      partialize: (s) => ({ selectedWeekIndex: s.selectedWeekIndex }),
    }
  )
)
