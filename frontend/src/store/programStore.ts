import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { GeneratedProgram } from '@/api/types'

interface ProgramStore {
  currentProgram: GeneratedProgram | null
  setCurrentProgram: (program: GeneratedProgram | null) => void
}

export const useProgramStore = create<ProgramStore>()(
  persist(
    (set) => ({
      currentProgram: null,
      setCurrentProgram: (program) => set({ currentProgram: program }),
    }),
    { name: 'training-program' }
  )
)
