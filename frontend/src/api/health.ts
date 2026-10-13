import { apiClient } from './client'
import type {
  ImportedWorkout,
  SessionPerformanceLog,
  DailyBioLog,
  WorkoutMatch,
  MatchSuggestion,
  WorkoutAnalysis,
  HRZoneDistribution,
} from '@/api/types'
import type { ReadinessResult } from '@/lib/readiness'
import type { RecentSessionLog } from '@/lib/logSessions'
import { useQuery } from '@tanstack/react-query'
import { queryKeys } from './queryKeys'

export interface HealthSnapshot {
  workouts: ImportedWorkout[]
  sessionLogs: Record<string, SessionPerformanceLog>
  dailyBio: Record<string, DailyBioLog>
  matches: WorkoutMatch[]
  performanceLogs: Record<string, Array<{ value: number; date: string }>>
}

const BASE = '/health'

export async function fetchHealthSnapshot(): Promise<HealthSnapshot> {
  return apiClient.get(`${BASE}/snapshot`) as unknown as Promise<HealthSnapshot>
}

/** Every session log, each named by the server from the plan it was logged
 *  against — Log ▸ Sessions, as on the phone. */
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

export function saveSessionLog(log: SessionPerformanceLog): void {
  void apiClient.put(`${BASE}/sessions/${encodeURIComponent(log.sessionKey)}`, log)
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

export function savePerformanceEntry(
  benchmarkId: string,
  value: number,
  loggedAt: string
): void {
  void apiClient.post(`${BASE}/performance`, { benchmarkId, value, loggedAt })
}

export function deletePerformanceLog(benchmarkId: string): void {
  void apiClient.delete(`${BASE}/performance/${encodeURIComponent(benchmarkId)}`)
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
