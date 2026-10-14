/**
 * Matching imported workouts to planned sessions, in the browser.
 *
 * There is a second implementation of this in `src/workout_matcher.py`, because
 * the automatic import paths have no browser — a Garmin webhook fires while
 * nobody is logged in, and the iOS app has no matcher of its own.
 *
 * The two share their thresholds (`data/matching_rules.json`, imported below)
 * and their golden fixtures (`data/matcher_fixtures.json`, asserted by
 * `workoutMatcher.test.ts` here and `test_workout_matcher.py` there). Change
 * the scoring in the JSON, not in either implementation, and run both suites.
 */
import { addDays, parseISO, format } from 'date-fns'
import rules from '@shared/matching_rules.json'
import type {
  ImportedWorkout,
  WorkoutMatch,
  PendingMatch,
  GeneratedProgram,
  ModalityId,
} from '@/api/types'

const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

/** modality id → family name, inverted once from the shared rules file. */
const FAMILY_OF: Record<string, string> = Object.fromEntries(
  Object.entries(rules.families).flatMap(([family, modalities]) =>
    (modalities as string[]).map((m) => [m, family])
  )
)

function modalityFamily(modality: ModalityId | string): string {
  return FAMILY_OF[modality] ?? 'other'
}

/**
 * Compute the calendar date for a given week/day in the program.
 * @param programStartDate YYYY-MM-DD — the date the program started (auto-set to "today" on generation)
 * @param weekIndex 0-based array position in program.weeks (NOT week_number)
 * @param dayName 'Monday' | ... | 'Sunday'
 */
export function sessionCalendarDate(programStartDate: string, weekIndex: number, dayName: string): string {
  const dayIndex = DAY_NAMES.indexOf(dayName)
  if (dayIndex < 0) return ''
  const start = parseISO(programStartDate)
  const offset = weekIndex * 7 + dayIndex
  return format(addDays(start, offset), 'yyyy-MM-dd')
}

type ActivityGate = { activity: string[]; equipment: string[] }

/** The rules' activity gate a workout falls under (cycling, rowing, swimming). */
function activityGate(workout: Pick<ImportedWorkout, 'activityType'>): ActivityGate | null {
  const activity = (workout.activityType ?? '').toLowerCase()
  if (!activity) return null
  for (const gate of Object.values(rules.activityGates) as ActivityGate[]) {
    if (gate.activity.some((k) => activity.includes(k))) return gate
  }
  return null
}

/** Every piece of equipment the session's exercises need. */
export function sessionEquipment(session: { exercises?: { exercise?: { equipment?: string[] } }[] }): string[] {
  const out = new Set<string>()
  for (const ea of session.exercises ?? []) {
    for (const e of ea?.exercise?.equipment ?? []) out.add(e)
  }
  return [...out].sort()
}

/**
 * 0-5. A cycling, rowing or swimming workout scores at most one below the auto
 * threshold against a session none of whose exercises needs a bike, a rower or
 * a pool (`rules.activityGates`) — sharing a modality with a kettlebell session
 * does not make a bike ride that session.
 */
export function scoreMatch(
  workout: ImportedWorkout,
  sessionModality: ModalityId,
  sessionDuration: number,
  equipment: readonly string[] = [],
): number {
  const score = baseScore(workout, sessionModality, sessionDuration)
  const gate = activityGate(workout)
  if (gate && !gate.equipment.some((e) => equipment.includes(e))) {
    return Math.min(score, rules.autoThreshold - 1)
  }
  return score
}

function baseScore(workout: ImportedWorkout, sessionModality: ModalityId, sessionDuration: number): number {
  let score = 0

  if (workout.inferredModalityId) {
    if (workout.inferredModalityId === sessionModality) {
      score += rules.modalityExactPoints
    } else if (modalityFamily(workout.inferredModalityId) === modalityFamily(sessionModality)) {
      score += rules.familyPoints
    }
  }

  const durDiff = Math.abs(workout.durationMinutes - sessionDuration)
  for (const [maxDelta, points] of rules.durationTiers) {
    if (durDiff <= maxDelta) {
      score += points
      break
    }
  }

  return score
}

interface MatchResult {
  confirmed: WorkoutMatch[]
  pending: PendingMatch[]
}

export function autoMatchWorkouts(
  workouts: ImportedWorkout[],
  program: GeneratedProgram,
  programStartDate: string,
  existingMatches: WorkoutMatch[]
): MatchResult {
  const confirmed: WorkoutMatch[] = []
  const pending: PendingMatch[] = []

  const existingIds = new Set(existingMatches.map((m) => m.importedWorkoutId))

  // Build date → { sessionKey, modality, duration }[] index
  const dateIndex: Map<string, { sessionKey: string; modality: ModalityId; duration: number; equipment: string[] }[]> =
    new Map()

  for (let weekIndex = 0; weekIndex < program.weeks.length; weekIndex++) {
    const week = program.weeks[weekIndex]
    for (const [dayName, sessions] of Object.entries(week.schedule)) {
      const calDate = sessionCalendarDate(programStartDate, weekIndex, dayName)
      if (!calDate) continue
      sessions.forEach((session, si) => {
        const sessionKey = `${week.week_number}-${dayName}-${si}`
        const entry = {
          sessionKey,
          modality: session.modality,
          duration: session.archetype?.duration_estimate_minutes ?? rules.defaultSessionMinutes,
          equipment: sessionEquipment(session),
        }
        const existing = dateIndex.get(calDate) ?? []
        existing.push(entry)
        dateIndex.set(calDate, existing)
      })
    }
  }

  for (const workout of workouts) {
    if (existingIds.has(workout.id)) continue

    const candidates = dateIndex.get(workout.date) ?? []
    if (candidates.length === 0) continue

    if (candidates.length === 1) {
      const c = candidates[0]
      const score = scoreMatch(workout, c.modality, c.duration, c.equipment)
      if (score >= rules.autoThreshold) {
        confirmed.push({
          importedWorkoutId: workout.id,
          sessionKey: c.sessionKey,
          matchConfidence: 'auto',
          matchedAt: new Date().toISOString(),
        })
        continue
      }
    }

    // Score all candidates and pick best or surface for manual confirmation
    const scored = candidates.map((c) => ({
      ...c,
      score: scoreMatch(workout, c.modality, c.duration, c.equipment),
    }))
    const best = scored.reduce((a, b) => (a.score >= b.score ? a : b))

    if (best.score >= rules.autoThreshold &&
        scored.filter((s) => s.score >= rules.autoThreshold).length === 1) {
      confirmed.push({
        importedWorkoutId: workout.id,
        sessionKey: best.sessionKey,
        matchConfidence: 'auto',
        matchedAt: new Date().toISOString(),
      })
    } else if (best.score >= rules.suggestThreshold) {
      pending.push({
        importedWorkout: workout,
        candidateSessionKeys: [best.sessionKey],
      })
    }
  }

  return { confirmed, pending }
}
