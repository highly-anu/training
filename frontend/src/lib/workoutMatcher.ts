import { addDays, parseISO, format } from 'date-fns'
import type {
  ImportedWorkout,
  WorkoutMatch,
  PendingMatch,
  GeneratedProgram,
  ModalityId,
} from '@/api/types'

const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

const STRENGTH_MODALITIES: ModalityId[] = ['max_strength', 'relative_strength', 'strength_endurance', 'power']
const CARDIO_MODALITIES: ModalityId[] = ['aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning']
const DURABILITY_MODALITIES: ModalityId[] = ['durability']
const SKILL_MODALITIES: ModalityId[] = ['movement_skill', 'mobility', 'rehab']

function modalityFamily(modality: ModalityId): string {
  if (STRENGTH_MODALITIES.includes(modality)) return 'strength'
  if (CARDIO_MODALITIES.includes(modality)) return 'cardio'
  if (DURABILITY_MODALITIES.includes(modality)) return 'durability'
  if (SKILL_MODALITIES.includes(modality)) return 'skill'
  return 'other'
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

export function scoreMatch(workout: ImportedWorkout, sessionModality: ModalityId, sessionDuration: number): number {
  let score = 0

  if (workout.inferredModalityId) {
    if (workout.inferredModalityId === sessionModality) {
      score += 3
    } else if (modalityFamily(workout.inferredModalityId) === modalityFamily(sessionModality)) {
      score += 1
    }
  }

  const durDiff = Math.abs(workout.durationMinutes - sessionDuration)
  if (durDiff <= 15) score += 2
  else if (durDiff <= 30) score += 1

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
  const dateIndex: Map<string, { sessionKey: string; modality: ModalityId; duration: number }[]> =
    new Map()

  for (let weekIndex = 0; weekIndex < program.weeks.length; weekIndex++) {
    const week = program.weeks[weekIndex]
    for (const [dayName, sessions] of Object.entries(week.schedule)) {
      const calDate = sessionCalendarDate(programStartDate, weekIndex, dayName)
      if (!calDate) continue
      const sessionKey = `${week.week_number}-${dayName}`
      for (const session of sessions) {
        const entry = {
          sessionKey,
          modality: session.modality,
          duration: session.archetype?.duration_estimate_minutes ?? 60,
        }
        const existing = dateIndex.get(calDate) ?? []
        existing.push(entry)
        dateIndex.set(calDate, existing)
      }
    }
  }

  for (const workout of workouts) {
    if (existingIds.has(workout.id)) continue

    const candidates = dateIndex.get(workout.date) ?? []
    if (candidates.length === 0) continue

    if (candidates.length === 1) {
      const c = candidates[0]
      const score = scoreMatch(workout, c.modality, c.duration)
      if (score >= 4) {
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
      score: scoreMatch(workout, c.modality, c.duration),
    }))
    const best = scored.reduce((a, b) => (a.score >= b.score ? a : b))

    if (best.score >= 4 && scored.filter((s) => s.score >= 4).length === 1) {
      confirmed.push({
        importedWorkoutId: workout.id,
        sessionKey: best.sessionKey,
        matchConfidence: 'auto',
        matchedAt: new Date().toISOString(),
      })
    } else if (best.score >= 2) {
      pending.push({
        importedWorkout: workout,
        candidateSessionKeys: [best.sessionKey],
      })
    }
  }

  return { confirmed, pending }
}
