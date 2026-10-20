import { format, parseISO, isValid } from 'date-fns'
import type { ExercisePerformance, GeneratedProgram, Session } from '@/api/types'
import { outcomeFieldsFor } from '@/lib/outcomeFields'

/**
 * Log ▸ Activity's sessions: what was logged against planned sessions, across programs.
 * Pure — rows are built from the server's session logs and the current
 * program, so a test pins order and wording without a page. The web port of
 * the phone's `LogSessions.rows` (ios/TrainingCompanion/LogSessions.swift);
 * the two lists read the same.
 */

/** One row of `GET /api/health/sessions/recent`. */
export interface RecentSessionLog {
  session_key: string
  session_uid?: string | null
  completed_at: string | null
  source?: string | null
  notes?: string
  fatigue_rating?: number | null
  matched_workout_id?: string | null
  exercises?: Record<string, ExercisePerformance>
  /** Named by the server from `planned_sessions` when the uid resolves. */
  planned_name?: string | null
  planned_modality?: string | null
  planned_date?: string | null
  program_version_id?: string | null
  week_index?: number | null
  day_name?: string | null
}

export interface LocatedSession {
  session: Session
  weekIndex: number
  weekNumber: number
  dayName: string
  sessionIndex: number
}

export interface LogSessionRow {
  key: string
  title: string
  subtitle: string
  /** One line per exercise with something logged ("Back Squat — 3 sets · 3×5 @ 80 kg"). */
  lines: string[]
  isComplete: boolean
  completedAt: Date | null
  /** Where the row opens: the session in the current program, or the earlier version. */
  href: string | null
}

/** Find `"{week_number}-{Day}-{index}"` in a program — the first match, as the phone does. */
export function locateSession(program: GeneratedProgram | null | undefined, key: string): LocatedSession | null {
  if (!program) return null
  for (let wi = 0; wi < program.weeks.length; wi++) {
    const week = program.weeks[wi]
    for (const [day, sessions] of Object.entries(week.schedule)) {
      for (let si = 0; si < sessions.length; si++) {
        if (`${week.week_number}-${day}-${si}` === key) {
          return { session: sessions[si], weekIndex: wi, weekNumber: week.week_number, dayName: day, sessionIndex: si }
        }
      }
    }
  }
  return null
}

/** The server writes "2026-09-28 18:00:00+02:00"; clients write ISO 8601. */
export function parseServerDate(value: string | null | undefined): Date | null {
  if (!value) return null
  const d = parseISO(value.includes('T') ? value : value.replace(' ', 'T'))
  return isValid(d) ? d : null
}

function modalityLabel(id: string): string {
  return id.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

/** The phone's `LoadFormat.kilograms`: whole numbers bare, else one decimal. */
function kg(v: number): string {
  return Number.isInteger(v) ? String(v) : v.toFixed(1)
}

/** One exercise's log as one phrase — the phone's `SessionLogging.summary`. */
export function performanceSummary(perf: ExercisePerformance, slotType: string): string | null {
  // A slot with no outcome currency logs sets — the phone's `logsSets`.
  if (outcomeFieldsFor(slotType).length === 0) {
    const done = perf.sets.filter((s) => s.completed)
    if (done.length === 0) return null
    if (slotType === 'static_hold') {
      const secs = done.map((s) => String(s.durationSeconds ?? 0))
      return new Set(secs).size === 1
        ? `${done.length}×${secs[0]} s hold`
        : `${done.length} hold${done.length === 1 ? '' : 's'} · ${secs.join(', ')} s`
    }
    const reps = done.map((s) => (s.repsActual != null ? String(s.repsActual) : '?'))
    const kgs = done.map((s) => (s.weightKg != null ? kg(s.weightKg) : null))
    const count = `${done.length} set${done.length === 1 ? '' : 's'}`
    if (new Set(reps).size === 1 && new Set(kgs.map((k) => k ?? '')).size === 1) {
      return `${count} · ${done.length}×${reps[0]}${kgs[0] ? ` @ ${kgs[0]} kg` : ''}`
    }
    const pairs = reps.map((r, i) => (kgs[i] ? `${r}×${kgs[i]}` : r))
    return `${count} · ${pairs.join(', ')}${kgs.some((k) => k != null) ? ' kg' : ''}`
  }
  const parts: string[] = []
  if (perf.durationSec && perf.durationSec > 0) parts.push(`${Math.round(perf.durationSec / 60)} min`)
  if (perf.distanceKm && perf.distanceKm > 0) parts.push(`${kg(perf.distanceKm)} km`)
  if (perf.rounds && perf.rounds > 0) parts.push(`${perf.rounds} round${perf.rounds === 1 ? '' : 's'}`)
  const firstReps = perf.sets[0]?.repsActual
  if (firstReps && firstReps > 0 && outcomeFieldsFor(slotType).includes('reps')) parts.push(`${firstReps} reps`)
  return parts.length ? parts.join(' · ') : null
}

/**
 * A log whose planned date precedes the current program's start belongs to an
 * earlier program even when its legacy key ("3-Friday-0") resolves in this
 * one — the key is program-relative and not unique across versions.
 */
export function buildLogSessionRows(
  logs: RecentSessionLog[],
  program: GeneratedProgram | null | undefined,
  programStartDate: string | null,
  exerciseNames: Record<string, string> = {},
): LogSessionRow[] {
  const currentStart = programStartDate ? parseServerDate(programStartDate) : null
  const rows: LogSessionRow[] = []
  for (const log of logs) {
    const logged = Object.entries(log.exercises ?? {}).filter(([, p]) =>
      (p.sets?.length ?? 0) > 0 || p.rounds != null || p.durationSec != null || p.distanceKm != null)
    const isComplete = log.completed_at != null
    if (!isComplete && logged.length === 0) continue
    const plannedDay = parseServerDate(log.planned_date)
    const precedesCurrent = plannedDay != null && currentStart != null && plannedDay < currentStart
    const located = precedesCurrent ? null : locateSession(program, log.session_key)
    const session = located?.session
    const title = (session ? session.archetype?.name ?? modalityLabel(session.modality) : null)
      ?? log.planned_name
      ?? (log.planned_modality ? modalityLabel(log.planned_modality) : null)
      ?? `Session ${log.session_key}`
    const completedAt = parseServerDate(log.completed_at)
    const parts: string[] = []
    if (completedAt) {
      parts.push(format(completedAt, 'd MMM yyyy, HH:mm'))
    } else if (plannedDay) {
      parts.push(`planned ${format(plannedDay, 'd MMM yyyy')}`)
      if (!isComplete) parts.push('not completed')
    } else if (!isComplete) {
      parts.push('not completed')
    }
    if (log.source && !['web', 'manual'].includes(log.source)) parts.push(log.source.replace(/_/g, ' '))
    const earlier = !located && (log.planned_name != null || log.planned_modality != null)
    if (located) {
      parts.push(`week ${located.weekIndex + 1} · ${located.dayName}`)
    } else if (earlier) {
      parts.push('earlier program')
      if (log.week_index != null && log.day_name) parts.push(`week ${log.week_index + 1} · ${log.day_name}`)
    }
    const lines = logged
      .sort(([a], [b]) => a.localeCompare(b))
      .flatMap(([id, perf]) => {
        const assignment = session?.exercises.find((e) => e.exercise?.id === id)
        const slotType = assignment?.slot_type ?? (perf.sets?.length ? 'sets_reps' : 'time_domain')
        const summary = performanceSummary({ ...perf, sets: perf.sets ?? [] }, slotType)
        if (!summary) return []
        const name = assignment?.exercise?.name ?? exerciseNames[id] ?? modalityLabel(id)
        return [`${name} — ${summary}`]
      })
    const href = located
      ? `/program/${located.weekNumber}/${located.dayName}`
      : earlier && log.program_version_id ? `/program/history/${log.program_version_id}` : null
    rows.push({ key: log.session_key, title, subtitle: parts.join(' · '), lines, isComplete, completedAt, href })
  }
  return rows.sort((a, b) => {
    if (a.completedAt && b.completedAt) return b.completedAt.getTime() - a.completedAt.getTime()
    if (!a.completedAt && !b.completedAt) return a.key.localeCompare(b.key)
    return a.completedAt ? -1 : 1
  })
}

/** Log ▸ Activity's type filter (the phone's `LogEntryKind`). */
export type LogShow = 'all' | 'workouts' | 'sessions'

export type LogEntry<W> =
  | { kind: 'workout'; at: number | null; workout: W }
  | { kind: 'session'; at: number | null; row: LogSessionRow }

/**
 * Log ▸ Activity: recorded workouts and session logs in one list, newest
 * first — a workout by its start, a log by its completion — and what has no
 * time last. `show` keeps one type. Workouts and Sessions were two sub-tabs
 * until 2026-10-20; the phone's `LogActivity.entries` merges the same way.
 */
export function mergeLogEntries<W extends { id: string; date: string; startTime?: string | null }>(
  workouts: W[],
  rows: LogSessionRow[],
  show: LogShow = 'all',
): LogEntry<W>[] {
  const time = (value: string | null | undefined) => {
    const t = value ? Date.parse(value) : NaN
    return Number.isNaN(t) ? null : t
  }
  const entries: LogEntry<W>[] = [
    ...(show === 'sessions' ? [] : workouts.map((workout) => ({
      kind: 'workout' as const, at: time(workout.startTime) ?? time(workout.date), workout }))),
    ...(show === 'workouts' ? [] : rows.map((row) => ({
      kind: 'session' as const, at: row.completedAt?.getTime() ?? null, row }))),
  ]
  // A stable sort keeps each type's own order among equal or missing times.
  return entries.sort((a, b) => {
    if (a.at != null && b.at != null) return b.at - a.at
    if (a.at == null && b.at == null) return 0
    return a.at != null ? -1 : 1
  })
}
