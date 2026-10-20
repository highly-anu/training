import { apiClient } from './client'
import type {
  ImportedWorkout,
  SessionPerformanceLog,
  DailyBioLog,
  WorkoutMatch,
  MatchSuggestion,
  WorkoutAnalysis,
  HRZoneDistribution,
  SessionLogStandards,
  ExercisePerformance,
} from '@/api/types'
import type { ReadinessResult } from '@/lib/readiness'
import type { RecentSessionLog } from '@/lib/logSessions'
import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'
import { queryClient } from '@/lib/queryClient'

export interface HealthSnapshot {
  workouts: ImportedWorkout[]
  sessionLogs: Record<string, SessionPerformanceLog>
  dailyBio: Record<string, DailyBioLog>
  matches: WorkoutMatch[]
  /** Results on the standards — read through GET /standards/results instead,
   *  which places each on its ladder. */
  performanceLogs: Record<string, Array<{ id?: number; value: number; date: string }>>
}

const BASE = '/health'

export async function fetchHealthSnapshot(): Promise<HealthSnapshot> {
  return apiClient.get(`${BASE}/snapshot`) as unknown as Promise<HealthSnapshot>
}

/** Every session log, each named by the server from the plan it was logged
 *  against — Log ▸ Activity's sessions, as on the phone. */
export async function fetchRecentSessionLogs(): Promise<RecentSessionLog[]> {
  return apiClient.get(`${BASE}/sessions/recent`) as unknown as Promise<RecentSessionLog[]>
}

/** One workout with its series and the server's `analysis`. Shared by the
 *  workout page and a session's matched-workout card, so both read one fetch. */
export function useWorkoutDetail(workoutId: string | null | undefined) {
  return useQuery<ImportedWorkout | null>({
    queryKey: ['workout', workoutId],
    queryFn: async () => {
      try {
        return await apiClient.get(`${BASE}/workouts/${encodeURIComponent(workoutId!)}`) as unknown as ImportedWorkout
      } catch {
        return null
      }
    },
    enabled: !!workoutId,
    staleTime: 5 * 60 * 1000,
  })
}

/** The zone split in the shape the charts take. */
export function zonesFromAnalysis(a: WorkoutAnalysis | undefined | null): HRZoneDistribution | null {
  const z = a?.zones
  if (!z) return null
  return { z1: z.pct[0], z2: z.pct[1], z3: z.pct[2], z4: z.pct[3], z5: z.pct[4], method: z.method }
}

/** Analytics ▸ Load's totals, mixes, consistency and zone minutes for a
 *  period (src/analytics/load_summary.py) — the phone reads the same. */
export interface LoadSummary {
  period: string
  from: string
  to: string
  maxHr: number
  totals: LoadTotals
  prior: LoadTotals | null
  modalities: { id: string | null; minutes: number; pct: number }[]
  activities: { activityType: string; minutes: number; sessions: number; modalityId: string | null }[]
  consistency: { weekStart: string; sessions: number }[]
  zones: { minutes: number[]; workoutsMeasured: number; workoutsEstimated: number } | null
  focus28d: { base: number; threshold: number; anaerobic: number }
}

export interface LoadTotals {
  sessions: number
  minutes: number
  distanceKm: number | null
  elevationGainM: number | null
  elevationLossM: number | null
  calories: number | null
}

export function useLoadSummary(period: string) {
  // The athlete's day, not the server's (UTC).
  const today = new Date().toLocaleDateString('en-CA')
  return useQuery({
    queryKey: ['health', 'loadSummary', period, today],
    queryFn: () =>
      apiClient.get(`${BASE}/load/summary?period=${encodeURIComponent(period)}&today=${today}`) as unknown as Promise<LoadSummary>,
    staleTime: 60_000,
  })
}

export function useRecentSessionLogs() {
  return useQuery({
    queryKey: queryKeys.health.recentSessions,
    queryFn: fetchRecentSessionLogs,
    staleTime: 30_000,
  })
}

export function saveWorkouts(workouts: ImportedWorkout[]): void {
  void apiClient.post(`${BASE}/workouts`, { workouts })
}

export function removeWorkout(id: string): void {
  void apiClient.delete(`${BASE}/workouts/${id}`)
}

/**
 * "Done as written" for a training-contract session: the server writes each
 * progressing exercise's prescribed rounds with `clean` and `rpe`, merged into
 * the log, and answers with what it wrote. A watch-recorded or linked session
 * logs no per-exercise outcome, so this is what a regenerate counts.
 */
export async function confirmSession(
  sessionKey: string,
  clean: boolean,
  rpe?: number,
  /** A loaded lift's outcome (Starting Strength): the ones not named were made. */
  lifts?: Record<string, { made: boolean; weightKg?: number }>,
): Promise<{
  exercises: Record<string, ExercisePerformance>
  completedAt?: string
}> {
  const body: Record<string, unknown> = { clean }
  if (rpe != null) body.rpe = rpe
  if (lifts) body.lifts = lifts
  const res = await apiClient.post(`${BASE}/sessions/${encodeURIComponent(sessionKey)}/confirm`, body)
  return res as unknown as { exercises: Record<string, ExercisePerformance>; completedAt?: string }
}

export function saveSessionLog(log: SessionPerformanceLog): void {
  void (apiClient.put(`${BASE}/sessions/${encodeURIComponent(log.sessionKey)}`, log) as unknown as
    Promise<{ standards?: SessionLogStandards }>)
    .then((res) => {
      // A logged test slot (or a single on a derived lift) came back as a
      // suggestion: refresh "To confirm" wherever it is shown.
      if (res?.standards) void queryClient.invalidateQueries({ queryKey: queryKeys.standards.suggestions })
    })
}

/** Undo "mark complete" for one session; the upsert cannot clear completed_at. */
export function clearSessionCompletion(sessionKey: string): void {
  void apiClient.delete(`${BASE}/sessions/${encodeURIComponent(sessionKey)}/completion`)
}

export function saveDailyBio(entry: DailyBioLog): void {
  void apiClient.put(`${BASE}/bio/${entry.date}`, entry)
}

export function saveMatch(match: WorkoutMatch): void {
  void apiClient.post(`${BASE}/matches`, match)
}

/** Weak matches from the server-side importers, waiting for a decision. */
export async function fetchMatchSuggestions(): Promise<MatchSuggestion[]> {
  return apiClient.get(`${BASE}/matches/suggestions`) as unknown as Promise<MatchSuggestion[]>
}

/** Forget a suggestion without deciding the workout. */
export function dismissMatchSuggestion(workoutId: string): void {
  void apiClient.delete(`${BASE}/matches/suggestions/${encodeURIComponent(workoutId)}`)
}


export async function fetchReadiness(): Promise<ReadinessResult> {
  return apiClient.get(`${BASE}/readiness`) as unknown as Promise<ReadinessResult>
}

export async function recalculateElevation(): Promise<{ updated: number; skipped: number }> {
  return apiClient.post(`${BASE}/workouts/recalculate-elevation`, {}) as unknown as Promise<{
    updated: number
    skipped: number
  }>
}
