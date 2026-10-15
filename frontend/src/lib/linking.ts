/**
 * Log ▸ Linking: recorded workouts and planned sessions side by side, one
 * card per calendar day — the current program's days and, before them, the
 * days of every earlier program that was in force (`GET
 * /api/programs/planned-sessions`, the effective rows of the archive).
 *
 * The suggestor here is the shared `scoreMatch`, run inside one day only — a
 * workout is only ever *suggested* for a session planned on its own date.
 * Linking across dates is the athlete's call (drag a workout onto any
 * session), never a suggestion. Server suggestions (Garmin webhook, Apple
 * Health relay) are kept when they name a session on the workout's date;
 * the rest of each day is filled one-to-one, best score first.
 *
 * Every session carries the `session_uid` the server stores with a match.
 * Without it the server resolves the legacy key on the *workout's* date,
 * which finds nothing for a link across days and the wrong program for a
 * finished block's key.
 *
 * Pure: no store, no fetch. `components/log/LinkingTab.tsx` lays it out.
 */
import rules from '@shared/matching_rules.json'
import { scoreMatch, sessionCalendarDate, sessionEquipment } from '@/lib/workoutMatcher'
import { belongsToVersion } from '@/lib/sessionMatching'
import { parseSessionKey } from '@/lib/sessionKeys'
import type {
  GeneratedProgram, ImportedWorkout, ModalityId, PendingMatch, PlannedSession, WorkoutMatch,
} from '@/api/types'

/** One planned session, of the current program or an earlier one, on the day it falls. */
export interface LinkSession {
  /** Unique on the page: the legacy key for the current program, the uid for an earlier one. */
  key: string
  /** `"3-Monday-0"`, what a match stores as `sessionKey`. */
  legacyKey: string
  /** The durable identity a match stores as `sessionUid`; null when the program is not archived yet. */
  uid: string | null
  date: string
  weekNumber: number
  dayName: string
  index: number
  modality: ModalityId
  name: string
  durationMinutes: number
  equipment: string[]
  /** From a program that is no longer active. */
  historical: boolean
  programVersionId: string | null
  /** Logged complete — read from the archive for an earlier program's session. */
  completedAt?: string | null
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
  /** The day belongs to an earlier program. */
  historical: boolean
  /** That program's version, for a label. */
  programVersionId: string | null
  /** Links touching this day — the workout, the session or both are on it. */
  links: LinkPair[]
  suggestions: LinkSuggestion[]
  /** This day's workouts in neither a link nor a suggestion. */
  workouts: ImportedWorkout[]
  /** This day's sessions in neither a link nor a suggestion. */
  sessions: LinkSession[]
  /** Workouts linked to a session this page does not have. */
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
  /** Effective planned sessions across programs; the current version's rows are skipped. */
  history?: PlannedSession[]
  /** YYYY-MM-DD; days after it are not shown. */
  today: string
  /** `"<workoutId>|<session key>"` pairs the athlete waved away. */
  dismissed?: ReadonlySet<string>
}

export const dismissKey = (workoutId: string, sessionKey: string) => `${workoutId}|${sessionKey}`

const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

/** Mirrors `program_history.session_uid`. */
export function sessionUid(versionId: string, weekIndex: number, dayName: string, index: number): string {
  return `${versionId}:w${weekIndex}-${dayName}-${index}`
}

/** Every planned session of the current program, by its per-session key. */
export function programSessions(
  program: GeneratedProgram, programStartDate: string, programVersionId?: string | null,
): Map<string, LinkSession> {
  const out = new Map<string, LinkSession>()
  program.weeks.forEach((week, weekIndex) => {
    for (const dayName of DAY_NAMES) {
      const daySessions = week.schedule[dayName]
      if (!daySessions) continue
      const date = sessionCalendarDate(programStartDate, weekIndex, dayName)
      daySessions.forEach((session, index) => {
        const key = `${week.week_number}-${dayName}-${index}`
        if (out.has(key)) return   // a repeated week number: the first one owns the key
        out.set(key, {
          key, legacyKey: key,
          uid: programVersionId ? sessionUid(programVersionId, weekIndex, dayName, index) : null,
          date, weekNumber: week.week_number, dayName, index,
          modality: session.modality,
          name: session.archetype?.name ?? session.modality.replace(/_/g, ' '),
          durationMinutes: session.archetype?.duration_estimate_minutes ?? rules.defaultSessionMinutes,
          equipment: sessionEquipment(session),
          historical: false,
          programVersionId: programVersionId ?? null,
        })
      })
    }
  })
  return out
}

/** An archived session as a page row. The archive keeps no equipment, so the activity gate caps it. */
export function historySession(row: PlannedSession): LinkSession {
  return {
    key: row.sessionUid, legacyKey: row.sessionKey, uid: row.sessionUid,
    date: row.date, weekNumber: row.weekNumber ?? row.weekIndex + 1, dayName: row.dayName, index: row.sessionIndex,
    modality: row.modality,
    name: row.archetypeName ?? row.modality.replace(/_/g, ' '),
    durationMinutes: row.durationMinutes || rules.defaultSessionMinutes,
    equipment: [],
    historical: true,
    programVersionId: row.programVersionId ?? row.sessionUid.split(':')[0] ?? null,
    completedAt: row.completedAt ?? null,
  }
}

/**
 * The session a stored key names among one day's sessions. A day-level key
 * ("3-Monday") names that day's session only when it has just one, as on the
 * server (`program_history._by_legacy_key`).
 */
function byLegacyKey(sessions: LinkSession[], key: string): LinkSession | undefined {
  const exact = sessions.filter((s) => s.legacyKey === key)
  if (exact.length) return exact.length === 1 ? exact[0] : undefined
  const parsed = parseSessionKey(key)
  if (!parsed || parsed.sessionIndex != null) return undefined
  const day = sessions.filter((s) => s.legacyKey.startsWith(`${key}-`))
  return day.length === 1 ? day[0] : undefined
}

function linkScore(workout: ImportedWorkout, s: LinkSession): number {
  return scoreMatch(workout, s.modality, s.durationMinutes, s.equipment)
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

const addDays = (date: string, n: number) => {
  const d = new Date(`${date}T12:00:00Z`)
  d.setUTCDate(d.getUTCDate() + n)
  return d.toISOString().slice(0, 10)
}

/** One card per day from the first program's first day to today, newest first. */
export function buildLinkingDays(input: LinkingInput): LinkingDay[] {
  const { workouts, matches, pending, program, programStartDate, programVersionId, today } = input
  const dismissed = input.dismissed ?? new Set<string>()

  const current = program && programStartDate
    ? programSessions(program, programStartDate, programVersionId)
    : new Map<string, LinkSession>()
  const currentFirst = [...current.values()].reduce<string | null>(
    (min, s) => (min == null || s.date < min ? s.date : min), programStartDate && program ? programStartDate : null)

  // An earlier program's rows; the current version's own are the program above,
  // which may carry edits the archive has not seen yet.
  const past = (input.history ?? [])
    .filter((r) => !(programVersionId && r.programVersionId === programVersionId))
    .map(historySession)
  const pastByUid = new Map(past.map((s) => [s.uid!, s]))

  const all = [...current.values(), ...past]
  if (all.length === 0) return []
  const firstDate = all.reduce((min, s) => (s.date < min ? s.date : min), all[0].date)
  const inRange = (d: string) => d >= firstDate && d <= today

  // A day an earlier program was in force on is that program's day, as in the
  // server matcher's index (history overwrites the dates it covers): a program
  // generated midweek starts on its Monday, but the days before it was
  // activated still belong to the plan that ran them. Links to the current
  // program's sessions on such a day still show — they come from the matches.
  const byDate = new Map<string, LinkSession[]>()
  for (const s of past) byDate.set(s.date, [...(byDate.get(s.date) ?? []), s])
  const pastDates = new Set(byDate.keys())
  for (const s of current.values()) {
    if (!pastDates.has(s.date)) byDate.set(s.date, [...(byDate.get(s.date) ?? []), s])
  }
  for (const list of byDate.values()) list.sort((a, b) => a.index - b.index)

  /** The session a stored match names, on this page; undefined when it is not here. */
  const sessionOf = (m: WorkoutMatch, workoutDate: string): LinkSession | undefined => {
    if (m.sessionUid && pastByUid.has(m.sessionUid)) return pastByUid.get(m.sessionUid)
    if (belongsToVersion(m, programVersionId)) {
      const s = current.get(m.sessionKey) ?? (parseSessionKey(m.sessionKey)?.sessionIndex == null
        ? current.get(`${m.sessionKey}-0`) : undefined)
      if (s) return s
    }
    if (m.sessionUid) return undefined          // a version this page has no rows for
    // Unscoped and not the current program's: the key on the workout's date,
    // then a day either side (the server's `widen`, for display only).
    const pastOn = (d: string) => (byDate.get(d) ?? []).filter((s) => s.historical)
    return byLegacyKey(pastOn(workoutDate), m.sessionKey)
      ?? byLegacyKey([...pastOn(addDays(workoutDate, -1)), ...pastOn(addDays(workoutDate, 1))], m.sessionKey)
  }

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
    const session = sessionOf(m, workout.date)
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
      const first = byDate.get(date)?.[0]
      const historical = first ? first.historical : !(currentFirst && date >= currentFirst)
      d = {
        date, historical, programVersionId: first?.programVersionId ?? (historical ? null : programVersionId ?? null),
        links: [], suggestions: [], workouts: [], sessions: [], elsewhere: [], declined: [], needsAttention: false,
      }
      days.set(date, d)
    }
    return d
  }

  for (const date of byDate.keys()) if (inRange(date)) day(date)
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
    let freeS = (byDate.get(d.date) ?? []).filter((s) => !linkedSessionKeys.has(s.key))

    // Pending suggestions first, when they stay inside the day.
    for (const w of freeW) {
      const key = pendingFor.get(w.id)
      const s = key ? byLegacyKey(freeS, key) : undefined
      if (!s || dismissed.has(dismissKey(w.id, s.key))) continue
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
