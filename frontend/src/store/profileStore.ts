import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { CustomInjuryFlag, EquipmentId, InjuryFlagId, TrainingLevel } from '@/api/types'
import * as healthApi from '@/api/health'

interface PerformanceEntry {
  value: number
  date: string
}

interface ProfileStore {
  trainingLevel: TrainingLevel
  equipment: EquipmentId[]
  injuryFlags: InjuryFlagId[]
  customInjuryFlags: CustomInjuryFlag[]
  performanceLogs: Record<string, PerformanceEntry[]>
  sessionLogs: Record<string, boolean[]>
  activeGoalId: string | null
  dateOfBirth: string | null // YYYY-MM-DD, used for max HR estimation

  setTrainingLevel: (level: TrainingLevel) => void
  setEquipment: (equipment: EquipmentId[]) => void
  toggleInjuryFlag: (flag: InjuryFlagId) => void
  addCustomInjuryFlag: (flag: CustomInjuryFlag) => void
  removeCustomInjuryFlag: (id: string) => void
  setActiveGoalId: (id: string | null) => void
  logPerformance: (benchmarkId: string, value: number) => void
  removePerformanceLog: (benchmarkId: string) => void
  setSessionLog: (key: string, completed: boolean[]) => void
  setDateOfBirth: (dob: string | null) => void
  // Hydrate performance logs from server snapshot
  initPerformanceLogs: (logs: Record<string, PerformanceEntry[]>) => void
}

export const useProfileStore = create<ProfileStore>()(
  persist(
    (set) => ({
      trainingLevel: 'intermediate',
      equipment: [],
      injuryFlags: [],
      customInjuryFlags: [],
      performanceLogs: {},
      sessionLogs: {},
      activeGoalId: null,
      dateOfBirth: null,

      setTrainingLevel: (level) => set({ trainingLevel: level }),
      setEquipment: (equipment) => set({ equipment }),
      toggleInjuryFlag: (flag) =>
        set((s) => ({
          injuryFlags: s.injuryFlags.includes(flag)
            ? s.injuryFlags.filter((f) => f !== flag)
            : [...s.injuryFlags, flag],
        })),
      addCustomInjuryFlag: (flag) =>
        set((s) => ({ customInjuryFlags: [...s.customInjuryFlags, flag] })),
      removeCustomInjuryFlag: (id) =>
        set((s) => ({ customInjuryFlags: s.customInjuryFlags.filter((f) => f.id !== id) })),
      setActiveGoalId: (id) => set({ activeGoalId: id }),
      logPerformance: (benchmarkId, value) => {
        const loggedAt = new Date().toISOString()
        healthApi.savePerformanceEntry(benchmarkId, value, loggedAt)
        set((s) => ({
          performanceLogs: {
            ...s.performanceLogs,
            [benchmarkId]: [
              ...(s.performanceLogs[benchmarkId] ?? []),
              { value, date: loggedAt },
            ],
          },
        }))
      },
      removePerformanceLog: (benchmarkId) => {
        healthApi.deletePerformanceLog(benchmarkId)
        set((s) => {
          // eslint-disable-next-line @typescript-eslint/no-unused-vars
          const { [benchmarkId]: _removed, ...rest } = s.performanceLogs
          return { performanceLogs: rest }
        })
      },
      setSessionLog: (key, completed) =>
        set((s) => ({ sessionLogs: { ...s.sessionLogs, [key]: completed } })),
      setDateOfBirth: (dob) => set({ dateOfBirth: dob }),
      initPerformanceLogs: (logs) => set({ performanceLogs: logs }),
    }),
    { name: 'training-profile' }
  )
)
