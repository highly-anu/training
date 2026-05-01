import { create } from 'zustand'
import type { CustomInjuryFlag, Day, DaySchedule, EquipmentId, InjuryFlagId, TrainingLevel } from '@/api/types'
import * as healthApi from '@/api/health'
import { fetchProfile, saveProfile } from '@/api/userdata'

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
  weeklySchedule: Record<Day, DaySchedule> | null

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
  setWeeklySchedule: (schedule: Record<Day, DaySchedule>) => void
  // Hydrate performance logs from server health snapshot
  initPerformanceLogs: (logs: Record<string, PerformanceEntry[]>) => void
  // Hydrate session completion from server health snapshot
  initSessionLogs: (sessionLogs: Record<string, boolean[]>) => void
  // Load full profile from server (called on login)
  loadFromServer: () => Promise<void>
}

function _sync(state: Omit<ProfileStore, keyof { loadFromServer: unknown; initPerformanceLogs: unknown; logPerformance: unknown; removePerformanceLog: unknown; setSessionLog: unknown } & Record<string, unknown>>) {
  saveProfile({
    trainingLevel:      state.trainingLevel,
    equipment:          state.equipment,
    injuryFlags:        state.injuryFlags,
    customInjuryFlags:  state.customInjuryFlags,
    activeGoalId:       state.activeGoalId,
    dateOfBirth:        state.dateOfBirth,
    weeklySchedule:     state.weeklySchedule,
  })
}

export const useProfileStore = create<ProfileStore>()((set, get) => ({
  trainingLevel: 'intermediate',
  equipment: [],
  injuryFlags: [],
  customInjuryFlags: [],
  performanceLogs: {},
  sessionLogs: {},
  activeGoalId: null,
  dateOfBirth: null,
  weeklySchedule: null,

  setTrainingLevel: (trainingLevel) => {
    set({ trainingLevel })
    _sync({ ...get(), trainingLevel })
  },
  setEquipment: (equipment) => {
    set({ equipment })
    _sync({ ...get(), equipment })
  },
  toggleInjuryFlag: (flag) => {
    const injuryFlags = get().injuryFlags.includes(flag)
      ? get().injuryFlags.filter((f) => f !== flag)
      : [...get().injuryFlags, flag]
    set({ injuryFlags })
    _sync({ ...get(), injuryFlags })
  },
  addCustomInjuryFlag: (flag) => {
    const customInjuryFlags = [...get().customInjuryFlags, flag]
    set({ customInjuryFlags })
    _sync({ ...get(), customInjuryFlags })
  },
  removeCustomInjuryFlag: (id) => {
    const customInjuryFlags = get().customInjuryFlags.filter((f) => f.id !== id)
    set({ customInjuryFlags })
    _sync({ ...get(), customInjuryFlags })
  },
  setActiveGoalId: (activeGoalId) => {
    set({ activeGoalId })
    _sync({ ...get(), activeGoalId })
  },
  logPerformance: (benchmarkId, value) => {
    const loggedAt = new Date().toISOString()
    healthApi.savePerformanceEntry(benchmarkId, value, loggedAt)
    set((s) => ({
      performanceLogs: {
        ...s.performanceLogs,
        [benchmarkId]: [...(s.performanceLogs[benchmarkId] ?? []), { value, date: loggedAt }],
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
  setDateOfBirth: (dateOfBirth) => {
    set({ dateOfBirth })
    _sync({ ...get(), dateOfBirth })
  },
  setWeeklySchedule: (weeklySchedule) => {
    set({ weeklySchedule })
    _sync({ ...get(), weeklySchedule })
  },
  initPerformanceLogs: (logs) => set({ performanceLogs: logs }),
  initSessionLogs: (logs) => set({ sessionLogs: logs }),

  loadFromServer: async () => {
    const data = await fetchProfile()
    if (!data) return
    set({
      trainingLevel:     data.trainingLevel ?? 'intermediate',
      equipment:         data.equipment ?? [],
      injuryFlags:       data.injuryFlags ?? [],
      customInjuryFlags: data.customInjuryFlags ?? [],
      activeGoalId:      data.activeGoalId ?? null,
      dateOfBirth:       data.dateOfBirth ?? null,
      weeklySchedule:    data.weeklySchedule ?? null,
    })
  },
}))
