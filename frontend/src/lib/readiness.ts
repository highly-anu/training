import { parseISO, subDays, isAfter } from 'date-fns'
import type { DailyBioLog, SessionPerformanceLog } from '@/api/types'

export type ReadinessFlag =
  | 'elevated_rhr_3d'
  | 'suppressed_hrv_3d'
  | 'high_accumulated_fatigue'
  | 'insufficient_sleep'
  | 'poor_sleep_3d'
  | 'insufficient_data'

export interface ReadinessResult {
  score: number // 0–100
  status: 'green' | 'yellow' | 'red'
  flags: ReadinessFlag[]
  components: { rhr: number; hrv: number; fatigue: number; sleep: number }
}

function recent<T>(items: T[], days: number, getDate: (item: T) => string): T[] {
  const cutoff = subDays(new Date(), days)
  return items.filter((item) => isAfter(parseISO(getDate(item)), cutoff))
}

function rollingMean(values: number[]): number {
  if (values.length === 0) return 0
  return values.reduce((a, b) => a + b, 0) / values.length
}

// ── Component 1: Resting HR (0–35 pts) ────────────────────────────────────────

function scoreRHR(bioLogs: DailyBioLog[], flags: ReadinessFlag[]): number {
  const logs = recent(bioLogs, 14, (l) => l.date).filter((l) => l.restingHR != null)
  if (logs.length < 3) {
    flags.push('insufficient_data')
    return 17
  }
  const baseline = rollingMean(logs.slice(0, -1).map((l) => l.restingHR!))
  const today = logs[logs.length - 1].restingHR!
  const delta = today - baseline

  // Check 3-day streak
  const last5 = logs.slice(-5)
  const elevated = last5.filter((l) => l.restingHR! - baseline > 5).length
  if (elevated >= 3) flags.push('elevated_rhr_3d')

  if (delta <= 0) return 35
  if (delta <= 3) return Math.round(35 - (delta / 3) * 9)
  if (delta <= 7) return Math.round(26 - ((delta - 3) / 4) * 13)
  return Math.max(0, Math.round(13 - (delta - 7) * 2))
}

// ── Component 2: HRV (0–35 pts) ───────────────────────────────────────────────

function scoreHRV(bioLogs: DailyBioLog[], flags: ReadinessFlag[]): number {
  const logs = recent(bioLogs, 14, (l) => l.date).filter((l) => l.hrv != null)
  if (logs.length < 3) {
    if (!flags.includes('insufficient_data')) flags.push('insufficient_data')
    return 17
  }
  const baseline = rollingMean(logs.slice(0, -1).map((l) => l.hrv!))
  const today = logs[logs.length - 1].hrv!
  const pct = baseline > 0 ? ((today - baseline) / baseline) * 100 : 0

  // Check 3-day suppression
  const last5 = logs.slice(-5)
  const suppressed = last5.filter((l) => l.hrv! < baseline * 0.85).length
  if (suppressed >= 3) flags.push('suppressed_hrv_3d')

  if (pct >= 5) return 35
  if (pct >= -5) return 30
  if (pct >= -10) return 21
  if (pct >= -20) return 13
  return 4
}

// ── Component 3: Sleep (0–15 pts) ─────────────────────────────────────────────

function scoreSleep(bioLogs: DailyBioLog[], flags: ReadinessFlag[]): number {
  const logs = recent(bioLogs, 7, (l) => l.date).filter((l) => l.sleepDurationMin != null)
  if (logs.length === 0) return 8 // neutral — no data

  const sorted = [...logs].sort((a, b) => a.date.localeCompare(b.date))
  const lastNight = sorted[sorted.length - 1].sleepDurationMin!
  const hours = lastNight / 60

  // Check 3-night streak of poor sleep (<6h)
  const poor = sorted.slice(-3).filter((l) => l.sleepDurationMin! / 60 < 6).length
  if (poor >= 3) flags.push('poor_sleep_3d')
  if (hours < 5) flags.push('insufficient_sleep')

  if (hours < 5) return 0
  if (hours < 6) return 5
  if (hours < 7) return 10
  if (hours <= 9) return 15
  return 12 // mild penalty for excessive sleep
}

// ── Component 4: Session fatigue (0–15 pts) ───────────────────────────────────

function scoreFatigue(
  sessionLogs: Record<string, SessionPerformanceLog>,
  flags: ReadinessFlag[]
): number {
  const logs = Object.values(sessionLogs)
    .filter((l) => l.completedAt && l.fatigueRating != null)
    .sort((a, b) => a.completedAt.localeCompare(b.completedAt))
    .slice(-3)

  if (logs.length === 0) return 8 // neutral

  const avg = rollingMean(logs.map((l) => l.fatigueRating!))
  if (avg > 4.5) {
    flags.push('high_accumulated_fatigue')
    return 1
  }
  if (avg > 3.5) return 4
  if (avg > 2.5) return 8
  if (avg > 1.5) return 12
  return 15
}

// ── Main ──────────────────────────────────────────────────────────────────────

export function computeReadiness(
  bioLogs: DailyBioLog[],
  sessionLogs: Record<string, SessionPerformanceLog>
): ReadinessResult {
  const flags: ReadinessFlag[] = []

  const rhr = scoreRHR(bioLogs, flags)
  const hrv = scoreHRV(bioLogs, flags)
  const sleep = scoreSleep(bioLogs, flags)
  const fatigue = scoreFatigue(sessionLogs, flags)

  const score = Math.min(100, Math.max(0, rhr + hrv + sleep + fatigue))
  const status = score >= 70 ? 'green' : score >= 45 ? 'yellow' : 'red'

  return { score, status, flags, components: { rhr, hrv, sleep, fatigue } }
}
