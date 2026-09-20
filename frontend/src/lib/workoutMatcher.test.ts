/**
 * Parity suite for the workout matcher.
 *
 * These are the SAME fixtures asserted by `test_workout_matcher.py` against the
 * Python implementation in `src/workout_matcher.py`. If this suite passes and
 * that one fails (or the reverse), the two matchers have drifted — which is
 * exactly what these fixtures exist to catch, because an automatic Garmin
 * import is matched by the Python one and a manual upload here by this one.
 *
 * Run: npm test -- src/lib/workoutMatcher.test.ts
 */
import { describe, it, expect } from 'vitest'
import fixtures from '@shared/matcher_fixtures.json'
import rules from '@shared/matching_rules.json'
import { scoreMatch, autoMatchWorkouts, sessionCalendarDate } from './workoutMatcher'
import type { ImportedWorkout, WorkoutMatch, GeneratedProgram, ModalityId } from '@/api/types'

describe('shared matching rules', () => {
  it('loads the rules the Python matcher also reads', () => {
    expect(rules.autoThreshold).toBeGreaterThan(rules.suggestThreshold)
    expect(Object.keys(rules.families).sort()).toEqual(
      ['cardio', 'durability', 'skill', 'strength']
    )
  })

  it('puts no modality in two families', () => {
    const seen = new Set<string>()
    const dupes: string[] = []
    for (const modalities of Object.values(rules.families)) {
      for (const m of modalities as string[]) {
        if (seen.has(m)) dupes.push(m)
        seen.add(m)
      }
    }
    expect(dupes).toEqual([])
  })
})

describe('scoreMatch — shared fixtures', () => {
  for (const c of fixtures.scoreCases) {
    it(c.name, () => {
      const score = scoreMatch(
        c.workout as unknown as ImportedWorkout,
        c.sessionModality as ModalityId,
        c.sessionDuration
      )
      expect(score).toBe(c.expectedScore)
    })
  }
})

describe('autoMatchWorkouts — shared fixtures', () => {
  for (const c of fixtures.matchCases) {
    it(c.name, () => {
      const { confirmed, pending } = autoMatchWorkouts(
        c.workouts as unknown as ImportedWorkout[],
        c.program as unknown as GeneratedProgram,
        c.programStartDate,
        c.existingMatches as unknown as WorkoutMatch[]
      )

      expect(confirmed.map((m) => [m.importedWorkoutId, m.sessionKey])).toEqual(
        c.expected.confirmed.map((m) => [m.importedWorkoutId, m.sessionKey])
      )
      // The Python side calls these "suggested"; here they are "pending", and
      // it carries the whole workout rather than just its id.
      expect(pending.map((p) => [p.importedWorkout.id, p.candidateSessionKeys[0]])).toEqual(
        c.expected.suggested.map((s) => [s.importedWorkoutId, s.sessionKey])
      )
      for (const m of confirmed) expect(m.matchConfidence).toBe('auto')
    })
  }
})

describe('sessionCalendarDate', () => {
  it('maps week 0 Monday to the start date', () => {
    expect(sessionCalendarDate('2026-03-02', 0, 'Monday')).toBe('2026-03-02')
  })
  it('maps week 0 Sunday to start + 6', () => {
    expect(sessionCalendarDate('2026-03-02', 0, 'Sunday')).toBe('2026-03-08')
  })
  it('maps week 1 Monday to start + 7', () => {
    expect(sessionCalendarDate('2026-03-02', 1, 'Monday')).toBe('2026-03-09')
  })
  it('returns empty for an unknown day name', () => {
    expect(sessionCalendarDate('2026-03-02', 0, 'Caturday')).toBe('')
  })
})
