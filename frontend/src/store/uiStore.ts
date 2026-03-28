import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { ExerciseFilters, ModalityId } from '@/api/types'

interface UiStore {
  sidebarOpen: boolean
  selectedExerciseId: string | null
  exerciseFilters: ExerciseFilters
  activeModalityFilter: ModalityId[]
  selectedWeekIndex: number

  setSidebarOpen: (open: boolean) => void
  toggleSidebar: () => void
  setSelectedExercise: (id: string | null) => void
  setExerciseFilters: (filters: ExerciseFilters) => void
  setActiveModalityFilter: (modalities: ModalityId[]) => void
  setSelectedWeekIndex: (index: number) => void
}

export const useUiStore = create<UiStore>()(
  persist(
    (set) => ({
      sidebarOpen: true,
      selectedExerciseId: null,
      exerciseFilters: {},
      activeModalityFilter: [],
      selectedWeekIndex: 0,

      setSidebarOpen: (open) => set({ sidebarOpen: open }),
      toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
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
