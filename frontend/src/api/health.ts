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

const BASE = '/api/health'

export async function fetchHealthSnapshot(): Promise<HealthSnapshot> {
  const res = await fetch(`${BASE}/snapshot`)
  if (!res.ok) throw new Error('Failed to load health data')
  return res.json()
}

export function saveWorkouts(workouts: ImportedWorkout[]): void {
  void fetch(`${BASE}/workouts`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ workouts }),
  })
}

export function removeWorkout(id: string): void {
  void fetch(`${BASE}/workouts/${id}`, { method: 'DELETE' })
}

export function saveSessionLog(log: SessionPerformanceLog): void {
  void fetch(`${BASE}/sessions/${encodeURIComponent(log.sessionKey)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(log),
  })
}

export function saveDailyBio(entry: DailyBioLog): void {
  void fetch(`${BASE}/bio/${entry.date}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(entry),
  })
}

export function saveMatch(match: WorkoutMatch): void {
  void fetch(`${BASE}/matches`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(match),
  })
}

export function savePerformanceEntry(
  benchmarkId: string,
  value: number,
  loggedAt: string
): void {
  void fetch(`${BASE}/performance`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ benchmarkId, value, loggedAt }),
  })
}

export function deletePerformanceLog(benchmarkId: string): void {
  void fetch(`${BASE}/performance/${encodeURIComponent(benchmarkId)}`, {
    method: 'DELETE',
  })
}
