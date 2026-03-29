import { create } from 'zustand'
import type {
  ImportedWorkout,
  SessionPerformanceLog,
  DailyBioLog,
  WorkoutMatch,
  PendingMatch,
  SetPerformance,
  FatigueRating,
  MatchConfidence,
} from '@/api/types'
import * as healthApi from '@/api/health'
import type { HealthSnapshot } from '@/api/health'

interface BioStore {
  importedWorkouts: ImportedWorkout[]
  sessionPerformanceLogs: Record<string, SessionPerformanceLog>
  dailyBioLogs: Record<string, DailyBioLog>
  workoutMatches: WorkoutMatch[]
  pendingMatches: PendingMatch[]

  // Hydration from server
  init: (snapshot: HealthSnapshot) => void

  // Import
  addImportedWorkouts: (workouts: ImportedWorkout[]) => void
  removeImportedWorkout: (id: string) => void

  // Matching
  setPendingMatches: (pending: PendingMatch[]) => void
  addAutoMatch: (importedWorkoutId: string, sessionKey: string) => void
  confirmMatch: (importedWorkoutId: string, sessionKey: string) => void
  rejectMatch: (importedWorkoutId: string) => void
  dismissPending: (importedWorkoutId: string) => void

  // Session performance
  upsertSessionPerformance: (log: SessionPerformanceLog) => void
  setSetPerformance: (sessionKey: string, exerciseId: string, setPerf: SetPerformance) => void
  setSessionNotes: (sessionKey: string, notes: string, fatigueRating?: FatigueRating) => void

  // Daily bio
  upsertDailyBio: (entry: DailyBioLog) => void

  // Selectors
  getMatchedWorkout: (sessionKey: string) => ImportedWorkout | undefined
  getPerformanceLog: (sessionKey: string) => SessionPerformanceLog | undefined
  getDailyBio: (date: string) => DailyBioLog | undefined
}

function upsertMatch(
  matches: WorkoutMatch[],
  importedWorkoutId: string,
  sessionKey: string,
  matchConfidence: MatchConfidence
): WorkoutMatch[] {
  return [
    ...matches.filter((m) => m.importedWorkoutId !== importedWorkoutId),
    { importedWorkoutId, sessionKey, matchConfidence, matchedAt: new Date().toISOString() },
  ]
}

function emptyLog(sessionKey: string): SessionPerformanceLog {
  return { sessionKey, exercises: {}, notes: '', completedAt: '' }
}

export const useBioStore = create<BioStore>()((set, get) => ({
  importedWorkouts: [],
  sessionPerformanceLogs: {},
  dailyBioLogs: {},
  workoutMatches: [],
  pendingMatches: [],

  init: (snapshot) =>
    set({
      importedWorkouts:       snapshot.workouts,
      sessionPerformanceLogs: snapshot.sessionLogs,
      dailyBioLogs:           snapshot.dailyBio,
      workoutMatches:         snapshot.matches,
    }),

  addImportedWorkouts: (workouts) => {
    set((s) => {
      const existingIds = new Set(s.importedWorkouts.map((w) => w.id))
      const novel = workouts.filter((w) => !existingIds.has(w.id))
      if (novel.length === 0) return s
      healthApi.saveWorkouts(novel)
      return { importedWorkouts: [...s.importedWorkouts, ...novel] }
    })
  },

  removeImportedWorkout: (id) => {
    healthApi.removeWorkout(id)
    set((s) => ({
      importedWorkouts: s.importedWorkouts.filter((w) => w.id !== id),
      workoutMatches:   s.workoutMatches.filter((m) => m.importedWorkoutId !== id),
    }))
  },

  setPendingMatches: (pending) => set({ pendingMatches: pending }),

  addAutoMatch: (importedWorkoutId, sessionKey) => {
    const match: WorkoutMatch = {
      importedWorkoutId,
      sessionKey,
      matchConfidence: 'auto',
      matchedAt: new Date().toISOString(),
    }
    healthApi.saveMatch(match)
    set((s) => ({ workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, sessionKey, 'auto') }))
  },

  confirmMatch: (importedWorkoutId, sessionKey) => {
    const match: WorkoutMatch = {
      importedWorkoutId,
      sessionKey,
      matchConfidence: 'manual',
      matchedAt: new Date().toISOString(),
    }
    healthApi.saveMatch(match)
    set((s) => ({
      workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, sessionKey, 'manual'),
      pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
    }))
  },

  rejectMatch: (importedWorkoutId) => {
    const match: WorkoutMatch = {
      importedWorkoutId,
      sessionKey: '',
      matchConfidence: 'rejected',
      matchedAt: new Date().toISOString(),
    }
    healthApi.saveMatch(match)
    set((s) => ({
      workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, '', 'rejected'),
      pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
    }))
  },

  dismissPending: (importedWorkoutId) =>
    set((s) => ({
      pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
    })),

  upsertSessionPerformance: (log) => {
    healthApi.saveSessionLog(log)
    set((s) => ({
      sessionPerformanceLogs: {
        ...s.sessionPerformanceLogs,
        [log.sessionKey]: { ...(s.sessionPerformanceLogs[log.sessionKey] ?? {}), ...log },
      },
    }))
  },

  setSetPerformance: (sessionKey, exerciseId, setPerf) =>
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const existingEx = existing.exercises[exerciseId] ?? { sets: [] }
      const sets = [...existingEx.sets]
      sets[setPerf.setIndex] = setPerf
      const updated: SessionPerformanceLog = {
        ...existing,
        exercises: { ...existing.exercises, [exerciseId]: { ...existingEx, sets } },
      }
      healthApi.saveSessionLog(updated)
      return {
        sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated },
      }
    }),

  setSessionNotes: (sessionKey, notes, fatigueRating) =>
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const updated: SessionPerformanceLog = {
        ...existing,
        notes,
        ...(fatigueRating !== undefined ? { fatigueRating } : {}),
      }
      healthApi.saveSessionLog(updated)
      return {
        sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated },
      }
    }),

  upsertDailyBio: (entry) => {
    healthApi.saveDailyBio(entry)
    set((s) => ({ dailyBioLogs: { ...s.dailyBioLogs, [entry.date]: entry } }))
  },

  getMatchedWorkout: (sessionKey) => {
    const { workoutMatches, importedWorkouts } = get()
    const match = workoutMatches.find(
      (m) => m.sessionKey === sessionKey && m.matchConfidence !== 'rejected'
    )
    if (!match) return undefined
    return importedWorkouts.find((w) => w.id === match.importedWorkoutId)
  },

  getPerformanceLog: (sessionKey) => get().sessionPerformanceLogs[sessionKey],

  getDailyBio: (date) => get().dailyBioLogs[date],
}))
