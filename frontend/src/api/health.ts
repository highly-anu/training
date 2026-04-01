import { apiClient } from './client'
import type {
  ImportedWorkout,
  SessionPerformanceLog,
  DailyBioLog,
  WorkoutMatch,
} from '@/api/types'

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

export function saveWorkouts(workouts: ImportedWorkout[]): void {
  void apiClient.post(`${BASE}/workouts`, { workouts })
}

export function removeWorkout(id: string): void {
  void apiClient.delete(`${BASE}/workouts/${id}`)
}

export function saveSessionLog(log: SessionPerformanceLog): void {
  void apiClient.put(`${BASE}/sessions/${encodeURIComponent(log.sessionKey)}`, log)
}

export function saveDailyBio(entry: DailyBioLog): void {
  void apiClient.put(`${BASE}/bio/${entry.date}`, entry)
}

export function saveMatch(match: WorkoutMatch): void {
  void apiClient.post(`${BASE}/matches`, match)
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
