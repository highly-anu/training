/**
 * Log ▸ Linking: recorded workouts and planned sessions side by side, one
 * card per calendar day of the current program.
 *
 * The suggestor here is the shared `scoreMatch`, run inside one day only — a
 * workout is only ever *suggested* for a session planned on its own date.
 * Linking across dates is the athlete's call (drag a workout onto any
 * session), never a suggestion. Server suggestions (Garmin webhook, Apple
 * Health relay) are kept when they name a session on the workout's date;
 * the rest of each day is filled one-to-one, best score first.
 *
 * Pure: no store, no fetch. `components/log/LinkingTab.tsx` lays it out.
 */
import rules from '@shared/matching_rules.json'
import { scoreMatch, sessionCalendarDate, sessionEquipment } from '@/lib/workoutMatcher'
import { belongsToVersion } from '@/lib/sessionMatching'
import type { GeneratedProgram, ImportedWorkout, PendingMatch, Session, WorkoutMatch } from '@/api/types'

/** One planned session of the current program, on the day it falls. */
export interface LinkSession {
  /** Per-session key, `"3-Monday-0"`. */
  key: string
  date: string
  weekNumber: number
  dayName: string
  index: number
  session: Session
  name: string
  durationMinutes: number
}

export interface LinkPair {
  workout: ImportedWorkout
  session: LinkSession
}

export interface LinkSuggestion extends LinkPair {
  score: number
  /** True when it came from the server or an upload, false when scored here. */
  fromPending: boolean
}

export interface LinkingDay {
  date: string
  /** Links touching this day — the workout, the session or both are on it. */
  links: LinkPair[]
  suggestions: LinkSuggestion[]
  /** This day's workouts in neither a link nor a suggestion. */
  workouts: ImportedWorkout[]
  /** This day's sessions in neither a link nor a suggestion. */
  sessions: LinkSession[]
  /** Workouts linked elsewhere: to an earlier program, or a key this program lacks. */
  elsewhere: { workout: ImportedWorkout; sessionKey: string }[]
  /** Workouts the athlete said belong to no session. */
  declined: ImportedWorkout[]
  /** An unlinked workout, or a suggestion, is waiting. */
  needsAttention: boolean
}

export interface LinkingInput {
  workouts: ImportedWorkout[]
  matches: WorkoutMatch[]
  pending: PendingMatch[]
  program: GeneratedProgram | null | undefined
  programStartDate: string | null
  programVersionId?: string | null
  /** YYYY-MM-DD; days after it are not shown. */
  today: string
  /** `"<workoutId>|<sessionKey>"` pairs the athlete waved away. */
  dismissed?: ReadonlySet<string>
}

export const dismissKey = (workoutId: string, sessionKey: string) => `${workoutId}|${sessionKey}`

/** Every planned session of the program, by its per-session key. */
export function programSessions(program: GeneratedProgram, programStartDate: string): Map<string, LinkSession> {
  const out = new Map<string, LinkSession>()
  program.weeks.forEach((week, weekIndex) => {
    for (const [dayName, daySessions] of Object.entries(week.schedule)) {
      const date = sessionCalendarDate(programStartDate, weekIndex, dayName)
      if (!date) continue
      daySessions.forEach((session, index) => {
        const key = `${week.week_number}-${dayName}-${index}`
        if (out.has(key)) return   // a repeated week number: the first one owns the key
        out.set(key, {
          key, date, weekNumber: week.week_number, dayName, index, session,
          name: session.archetype?.name ?? session.modality.replace(/_/g, ' '),
          durationMinutes: session.archetype?.duration_estimate_minutes ?? rules.defaultSessionMinutes,
        })
      })
    }
  })
  return out
}

/** A day-level key ("3-Monday") names that day's first session. */
function resolveKey(key: string, sessions: Map<string, LinkSession>): LinkSession | undefined {
  return sessions.get(key) ?? sessions.get(`${key}-0`)
}

function linkScore(workout: ImportedWorkout, s: LinkSession): number {
  return scoreMatch(workout, s.session.modality, s.durationMinutes, sessionEquipment(s.session))
}

/**
 * The day's suggestions, one-to-one: every (workout, session) pair at or above
 * the suggest threshold, best first, each side used once. Ties keep the
 * earlier workout and the earlier session.
 */
export function suggestForDay(
  workouts: ImportedWorkout[],
  sessions: LinkSession[],
  dismissed: ReadonlySet<string> = new Set(),
): LinkSuggestion[] {
  const pairs: LinkSuggestion[] = []
  workouts.forEach((workout) => {
    sessions.forEach((session) => {
      if (dismissed.has(dismissKey(workout.id, session.key))) return
      const score = linkScore(workout, session)
      if (score >= rules.suggestThreshold) pairs.push({ workout, session, score, fromPending: false })
    })
  })
  pairs.sort((a, b) => b.score - a.score)
  const usedW = new Set<string>()
  const usedS = new Set<string>()
  const out: LinkSuggestion[] = []
  for (const p of pairs) {
    if (usedW.has(p.workout.id) || usedS.has(p.session.key)) continue
    usedW.add(p.workout.id)
    usedS.add(p.session.key)
    out.push(p)
  }
  return out
}

/** One card per day from the program's first day to today, newest first. */
export function buildLinkingDays(input: LinkingInput): LinkingDay[] {
  const { workouts, matches, pending, program, programStartDate, programVersionId, today } = input
  const dismissed = input.dismissed ?? new Set<string>()
  if (!program || !programStartDate) return []

  const sessions = programSessions(program, programStartDate)
  const firstDate = [...sessions.values()].reduce((min, s) => (s.date < min ? s.date : min), programStartDate)
  const inRange = (d: string) => d >= firstDate && d <= today

  const matchOf = new Map(matches.map((m) => [m.importedWorkoutId, m]))
  const linkedSessionKeys = new Set<string>()
  const links: LinkPair[] = []
  const unlinked: ImportedWorkout[] = []
  const elsewhere: { workout: ImportedWorkout; sessionKey: string }[] = []
  const declined: ImportedWorkout[] = []

  for (const workout of workouts) {
    const m = matchOf.get(workout.id)
    if (!m) { if (inRange(workout.date)) unlinked.push(workout); continue }
    if (m.matchConfidence === 'rejected') { if (inRange(workout.date)) declined.push(workout); continue }
    const session = belongsToVersion(m, programVersionId) ? resolveKey(m.sessionKey, sessions) : undefined
    if (session) {
      linkedSessionKeys.add(session.key)
      if (inRange(workout.date) || inRange(session.date)) links.push({ workout, session })
    } else if (inRange(workout.date)) {
      elsewhere.push({ workout, sessionKey: m.sessionKey })
    }
  }

  const days = new Map<string, LinkingDay>()
  const day = (date: string): LinkingDay => {
    let d = days.get(date)
    if (!d) {
      d = { date, links: [], suggestions: [], workouts: [], sessions: [], elsewhere: [], declined: [], needsAttention: false }
      days.set(date, d)
    }
    return d
  }

  for (const s of sessions.values()) if (inRange(s.date)) day(s.date)
  for (const w of unlinked) day(w.date)
  for (const l of links) {
    if (inRange(l.workout.date)) day(l.workout.date).links.push(l)
    if (l.session.date !== l.workout.date && inRange(l.session.date)) day(l.session.date).links.push(l)
  }
  for (const e of elsewhere) day(e.workout.date).elsewhere.push(e)
  for (const w of declined) day(w.date).declined.push(w)

  const pendingFor = new Map(pending.map((p) => [p.importedWorkout.id, p.candidateSessionKeys[0]]))

  for (const d of days.values()) {
    let freeW = unlinked.filter((w) => w.date === d.date)
    let freeS = [...sessions.values()].filter((s) => s.date === d.date && !linkedSessionKeys.has(s.key))

    // Pending suggestions first, when they stay inside the day.
    for (const w of freeW) {
      const key = pendingFor.get(w.id)
      const s = key ? resolveKey(key, sessions) : undefined
      if (!s || s.date !== d.date || !freeS.includes(s) || dismissed.has(dismissKey(w.id, s.key))) continue
      d.suggestions.push({ workout: w, session: s, score: linkScore(w, s), fromPending: true })
      freeS = freeS.filter((x) => x !== s)
    }
    freeW = freeW.filter((w) => !d.suggestions.some((p) => p.workout.id === w.id))

    const scored = suggestForDay(freeW, freeS, dismissed)
    d.suggestions.push(...scored)
    d.workouts = freeW.filter((w) => !scored.some((p) => p.workout.id === w.id))
    d.sessions = freeS.filter((s) => !scored.some((p) => p.session.key === s.key))
    d.needsAttention = d.suggestions.length > 0 || d.workouts.length > 0
  }

  return [...days.values()].sort((a, b) => b.date.localeCompare(a.date))
}
