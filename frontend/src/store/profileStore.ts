import { create } from 'zustand'
import type { CustomInjuryFlag, Day, DaySchedule, EquipmentId, HRConfig, InjuryFlagId, IntegrationSettings, TrainingLevel, Sex } from '@/api/types'
import { fetchProfile, saveProfile } from '@/api/userdata'

/** Mirrors default_integrations() in api.py. Auto-import defaults on, but a
 *  source only imports once it is also connected, so this changes nothing
 *  until the athlete connects something. */
export const DEFAULT_INTEGRATIONS: IntegrationSettings = {
  autoImport: true,
  sources: {
    garmin: { enabled: true },
    strava: { enabled: true },
    appleHealth: { enabled: true },
  },
}

interface ProfileStore {
  trainingLevel: TrainingLevel
  equipment: EquipmentId[]
  injuryFlags: InjuryFlagId[]
  customInjuryFlags: CustomInjuryFlag[]
  sessionLogs: Record<string, boolean[]>
  activeGoalId: string | null
  dateOfBirth: string | null // YYYY-MM-DD, used for max HR estimation
  /** Which standards' tables apply. Null until the athlete says. */
  sex: Sex | null
  /** IANA zone used to date imported FIT files; null means UTC. */
  timezone: string | null
  weeklySchedule: Record<Day, DaySchedule> | null
  hrConfig: HRConfig
  integrations: IntegrationSettings

  setTrainingLevel: (level: TrainingLevel) => void
  setEquipment: (equipment: EquipmentId[]) => void
  toggleInjuryFlag: (flag: InjuryFlagId) => void
  addCustomInjuryFlag: (flag: CustomInjuryFlag) => void
  removeCustomInjuryFlag: (id: string) => void
  setActiveGoalId: (id: string | null) => void
  setSessionLog: (key: string, completed: boolean[]) => void
  setDateOfBirth: (dob: string | null) => void
  setSex: (sex: Sex | null) => void
  setTimezone: (timezone: string | null) => void
  setWeeklySchedule: (schedule: Record<Day, DaySchedule>) => void
  setHRConfig: (config: HRConfig) => void
  setIntegrations: (settings: IntegrationSettings) => void
  // Hydrate session completion from server health snapshot
  initSessionLogs: (sessionLogs: Record<string, boolean[]>) => void
  // Load full profile from server (called on login)
  loadFromServer: () => Promise<void>
}

function _sync(state: Omit<ProfileStore, keyof { loadFromServer: unknown; setSessionLog: unknown } & Record<string, unknown>>) {
  saveProfile({
    trainingLevel:      state.trainingLevel,
    equipment:          state.equipment,
    injuryFlags:        state.injuryFlags,
    customInjuryFlags:  state.customInjuryFlags,
    activeGoalId:       state.activeGoalId,
    dateOfBirth:        state.dateOfBirth,
    sex:                state.sex,
    timezone:           state.timezone,
    weeklySchedule:     state.weeklySchedule,
    hrConfig:           state.hrConfig,
    integrations:       state.integrations,
  })
}

export const useProfileStore = create<ProfileStore>()((set, get) => ({
  trainingLevel: 'intermediate',
  equipment: [],
  injuryFlags: [],
  customInjuryFlags: [],
  sessionLogs: {},
  activeGoalId: null,
  dateOfBirth: null,
  sex: null,
  timezone: null,
  weeklySchedule: null,
  hrConfig: {},
  integrations: DEFAULT_INTEGRATIONS,

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
  setSessionLog: (key, completed) =>
    set((s) => ({ sessionLogs: { ...s.sessionLogs, [key]: completed } })),
  setDateOfBirth: (dateOfBirth) => {
    set({ dateOfBirth })
    _sync({ ...get(), dateOfBirth })
  },
  setSex: (sex) => {
    set({ sex })
    _sync({ ...get(), sex })
  },
  setTimezone: (timezone) => {
    set({ timezone })
    _sync({ ...get(), timezone })
  },
  setWeeklySchedule: (weeklySchedule) => {
    set({ weeklySchedule })
    _sync({ ...get(), weeklySchedule })
  },
  setHRConfig: (hrConfig) => {
    set({ hrConfig })
    _sync({ ...get(), hrConfig })
  },

  setIntegrations: (integrations) => {
    set({ integrations })
    _sync({ ...get(), integrations })
  },
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
      sex:               data.sex ?? null,
      timezone:          data.timezone ?? null,
      weeklySchedule:    data.weeklySchedule ?? null,
      hrConfig:          data.hrConfig ?? {},
      integrations:      data.integrations ?? DEFAULT_INTEGRATIONS,
    })
  },
}))
