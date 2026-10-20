import { create } from 'zustand'
import type {
  ImportedWorkout,
  SessionPerformanceLog,
  DailyBioLog,
  WorkoutMatch,
  PendingMatch,
  MatchSuggestion,
  SetPerformance,
  ExercisePerformance,
  FatigueRating,
  MatchConfidence,
} from '@/api/types'
import * as healthApi from '@/api/health'
import type { HealthSnapshot } from '@/api/health'
import { useProfileStore } from '@/store/profileStore'
import { findSessionMatch } from '@/lib/sessionMatching'
import { parseSessionKey } from '@/lib/sessionKeys'
import { useProgramStore } from '@/store/programStore'

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
  /**
   * `sessionUid` names the session exactly — Log ▸ Linking sends it, because the
   * server otherwise resolves the key on the workout's own date and finds
   * nothing for a link across days. `markComplete: false` for a session of an
   * earlier program: its key would tick this program's session of that name.
   */
  confirmMatch: (importedWorkoutId: string, sessionKey: string,
    opts?: { sessionUid?: string | null; markComplete?: boolean }) => void
  rejectMatch: (importedWorkoutId: string) => void
  /**
   * Server-side weak matches (Garmin webhook, iOS Apple Health relay) merged
   * into the pending list. Browser state is not persisted, so these are the
   * only pending matches that survive a reload.
   */
  mergeServerSuggestions: (suggestions: MatchSuggestion[]) => void
  /** Drop a suggestion without deciding the workout; the server forgets it too. */
  dismissSuggestion: (importedWorkoutId: string) => void
  dismissPending: (importedWorkoutId: string) => void

  // Session performance
  upsertSessionPerformance: (log: SessionPerformanceLog) => void
  /**
   * Undo "mark complete". The server's upsert keeps the later completed_at,
   * so this is its own route; sets, notes and HR stay.
   */
  clearSessionCompletion: (sessionKey: string) => void
  setSetPerformance: (sessionKey: string, exerciseId: string, setPerf: SetPerformance) => void
  /** Outcome of a non-set slot — rounds, minutes, kilometres — the fields the analytics engine reads. */
  setExerciseOutcome: (sessionKey: string, exerciseId: string,
    outcome: { rounds?: number; durationSec?: number; distanceKm?: number; reps?: number; holdSec?: number; rpe?: ExercisePerformance['rpe']; weightKg?: number }) => void
  /** Tick (or untick) a skill as practised clean. */
  setExerciseClean: (sessionKey: string, exerciseId: string, clean: boolean) => void
  /** What the server wrote for a session's "done as written" — applied here, not saved again. */
  applyConfirmation: (sessionKey: string, exercises: Record<string, ExercisePerformance>, completedAt?: string) => void
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
  matchConfidence: MatchConfidence,
  sessionUid?: string | null,
): WorkoutMatch[] {
  const match: WorkoutMatch = { importedWorkoutId, sessionKey, matchConfidence, matchedAt: new Date().toISOString() }
  if (sessionUid) match.sessionUid = sessionUid
  return [...matches.filter((m) => m.importedWorkoutId !== importedWorkoutId), match]
}

function emptyLog(sessionKey: string): SessionPerformanceLog {
  return { sessionKey, exercises: {}, notes: '', completedAt: '' }
}

// "weekNum-DayName-sessionIdx" → { dayKey, sessionIdx }; null for a day-level key.
function parsePerSessionKey(key: string): { dayKey: string; sessionIdx: number } | null {
  const parsed = parseSessionKey(key)
  if (!parsed || parsed.sessionIndex == null) return null
  return { dayKey: parsed.dayKey, sessionIdx: parsed.sessionIndex }
}

// Prevents concurrent recalculation calls if init() fires multiple times
// (re-auth, token refresh) before the first round-trip completes.
let _elevationRecalcInFlight = false

export const useBioStore = create<BioStore>()((set, get) => ({
  importedWorkouts: [],
  sessionPerformanceLogs: {},
  dailyBioLogs: {},
  workoutMatches: [],
  pendingMatches: [],

  init: (snapshot) => {
    set({
      importedWorkouts:       snapshot.workouts,
      sessionPerformanceLogs: snapshot.sessionLogs,
      dailyBioLogs:           snapshot.dailyBio,
      workoutMatches:         snapshot.matches,
    })
    // One-time migration: recalculate stored elevation from GPS tracks so
    // sidebar/analytics values match what WorkoutDetail computes.
    if (!_elevationRecalcInFlight &&
        typeof localStorage !== 'undefined' &&
        !localStorage.getItem('elevationRecalcV1')) {
      _elevationRecalcInFlight = true
      healthApi.recalculateElevation().then(({ updated }) => {
        localStorage.setItem('elevationRecalcV1', '1')
        if (updated > 0) {
          // Refresh snapshot so corrected values populate the store
          healthApi.fetchHealthSnapshot().then((fresh) => {
            set({
              importedWorkouts:       fresh.workouts,
              sessionPerformanceLogs: fresh.sessionLogs,
              dailyBioLogs:           fresh.dailyBio,
              workoutMatches:         fresh.matches,
            })
          }).catch(() => {})
        }
      }).catch(() => {
        // Server error → flag not set → will retry next session
      }).finally(() => {
        _elevationRecalcInFlight = false
      })
    }
  },

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
    // Per-session key "weekNum-Day-si": mark that specific index in the day-level log
    const parsed = parsePerSessionKey(sessionKey)
    if (parsed) {
      const { dayKey, sessionIdx } = parsed
      const current = useProfileStore.getState().sessionLogs[dayKey] ?? []
      const next = [...current]; next[sessionIdx] = true
      useProfileStore.getState().setSessionLog(dayKey, next)
    } else {
      useProfileStore.getState().setSessionLog(sessionKey, [true])
    }
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const updated = existing.completedAt ? existing : { ...existing, completedAt: new Date().toISOString() }
      if (!existing.completedAt) healthApi.saveSessionLog(updated)
      return {
        workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, sessionKey, 'auto'),
        sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated },
      }
    })
  },

  confirmMatch: (importedWorkoutId, sessionKey, opts) => {
    const match: WorkoutMatch = {
      importedWorkoutId,
      sessionKey,
      matchConfidence: 'manual',
      matchedAt: new Date().toISOString(),
    }
    if (opts?.sessionUid) match.sessionUid = opts.sessionUid
    healthApi.saveMatch(match)
    if (opts?.markComplete === false) {
      set((s) => ({
        workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, sessionKey, 'manual', opts.sessionUid),
        pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
      }))
      return
    }
    const parsed = parsePerSessionKey(sessionKey)
    if (parsed) {
      const { dayKey, sessionIdx } = parsed
      const current = useProfileStore.getState().sessionLogs[dayKey] ?? []
      const next = [...current]; next[sessionIdx] = true
      useProfileStore.getState().setSessionLog(dayKey, next)
    } else {
      useProfileStore.getState().setSessionLog(sessionKey, [true])
    }
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const updated = existing.completedAt ? existing : { ...existing, completedAt: new Date().toISOString() }
      if (!existing.completedAt) healthApi.saveSessionLog(updated)
      return {
        workoutMatches: upsertMatch(s.workoutMatches, importedWorkoutId, sessionKey, 'manual', opts?.sessionUid),
        pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
        sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated },
      }
    })
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

  mergeServerSuggestions: (suggestions) =>
    set((s) => {
      // The server already drops suggestions for decided workouts, but the
      // local lists can be ahead of it by one round-trip.
      const decided = new Set(s.workoutMatches.map((m) => m.importedWorkoutId))
      const pending = new Set(s.pendingMatches.map((p) => p.importedWorkout.id))
      const byId = new Map(s.importedWorkouts.map((w) => [w.id, w]))
      const added: PendingMatch[] = []
      for (const sug of suggestions) {
        if (decided.has(sug.importedWorkoutId) || pending.has(sug.importedWorkoutId)) continue
        const workout = byId.get(sug.importedWorkoutId)
        if (!workout) continue
        pending.add(sug.importedWorkoutId)
        added.push({ importedWorkout: workout, candidateSessionKeys: [sug.sessionKey] })
      }
      return added.length > 0 ? { pendingMatches: [...s.pendingMatches, ...added] } : {}
    }),

  dismissSuggestion: (importedWorkoutId) => {
    healthApi.dismissMatchSuggestion(importedWorkoutId)
    set((s) => ({
      pendingMatches: s.pendingMatches.filter((p) => p.importedWorkout.id !== importedWorkoutId),
    }))
  },

  clearSessionCompletion: (sessionKey) => {
    healthApi.clearSessionCompletion(sessionKey)
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey]
      if (!existing) return {}
      return {
        sessionPerformanceLogs: {
          ...s.sessionPerformanceLogs,
          [sessionKey]: { ...existing, completedAt: '' },
        },
      }
    })
  },

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

  setExerciseClean: (sessionKey, exerciseId, clean) =>
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const existingEx = existing.exercises[exerciseId] ?? { sets: [] }
      const updated: SessionPerformanceLog = {
        ...existing,
        exercises: { ...existing.exercises, [exerciseId]: { ...existingEx, clean } },
      }
      healthApi.saveSessionLog(updated)
      return { sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated } }
    }),

  setExerciseOutcome: (sessionKey, exerciseId, outcome) =>
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const existingEx = existing.exercises[exerciseId] ?? { sets: [] }
      // Reps in a window and a hold's seconds live on the first set, where the
      // rate and hold primitives read them; one does not wipe the other.
      const sets = outcome.reps != null || outcome.holdSec != null
        ? [{
            ...(existingEx.sets[0] ?? {}),
            setIndex: 0, completed: true,
            ...(outcome.reps != null ? { repsActual: outcome.reps } : {}),
            ...(outcome.holdSec != null ? { durationSeconds: outcome.holdSec } : {}),
          }, ...existingEx.sets.slice(1)]
        : existingEx.sets
      const updated: SessionPerformanceLog = {
        ...existing,
        exercises: {
          ...existing.exercises,
          [exerciseId]: {
            ...existingEx,
            sets,
            ...('rounds' in outcome ? { rounds: outcome.rounds } : {}),
            ...('durationSec' in outcome ? { durationSec: outcome.durationSec } : {}),
            ...('distanceKm' in outcome ? { distanceKm: outcome.distanceKm } : {}),
            ...('rpe' in outcome ? { rpe: outcome.rpe } : {}),
            ...('weightKg' in outcome ? { weightKg: outcome.weightKg } : {}),
          },
        },
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
    // Resolution lives in lib/sessionMatching so that every screen rejects a
    // match belonging to a replaced program the same way. On the key alone, a
    // finished block's run showed up as this block's session.
    const match = findSessionMatch(
      workoutMatches,
      [sessionKey],
      useProgramStore.getState().programVersionId
    )
    if (!match) return undefined
    return importedWorkouts.find((w) => w.id === match.importedWorkoutId)
  },

  applyConfirmation: (sessionKey, exercises, completedAt) =>
    set((s) => {
      const existing = s.sessionPerformanceLogs[sessionKey] ?? emptyLog(sessionKey)
      const updated: SessionPerformanceLog = {
        ...existing,
        completedAt: existing.completedAt || completedAt || new Date().toISOString(),
        exercises: { ...existing.exercises, ...exercises },
      }
      return { sessionPerformanceLogs: { ...s.sessionPerformanceLogs, [sessionKey]: updated } }
    }),

  getPerformanceLog: (sessionKey) => get().sessionPerformanceLogs[sessionKey],

  getDailyBio: (date) => get().dailyBioLogs[date],
}))
