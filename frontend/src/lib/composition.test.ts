import { describe, it, expect, vi } from 'vitest'

vi.mock('@/api/client', () => ({ apiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }))

import { buildPostBody, sourcesOf } from '@/api/programs'
import { builderGenerateParams } from '@/lib/builderParams'
import { compositionLanes, regenerateSource, tailResume } from '@/lib/programSource'
import { mergedEntryRequirements, trackImplements, implementCount } from '@/lib/tracks'
import { laneSegments } from '@/hooks/usePhaseCalendar'
import type { AthleteConstraints, GeneratedProgram, Track, WeekData } from '@/api/types'

const constraints = { training_level: 'intermediate', equipment: [], days_per_week: 6 } as unknown as AthleteConstraints

const lanes = [
  { philosophyId: 'uphill_athlete', trackId: 'full_program', weight: 0.6 },
  { philosophyId: 'starting_strength', trackId: 'texas_method', weight: 0.4 },
]

function week(n: number, uphill: string, ss: string): WeekData {
  return {
    week_number: n, week_in_phase: n, phase: 'base', phase_id: uphill, is_deload: false, schedule: {},
    lanes: [
      { lane_key: 'uphill_athlete/full_program', track_id: 'full_program', phase: 'base', phase_id: uphill,
        week_in_phase: n, is_deload: false, sessions: 4 },
      { lane_key: 'starting_strength/texas_method', track_id: 'texas_method', phase: 'build', phase_id: ss,
        week_in_phase: n + 2, is_deload: false, sessions: 3 },
    ],
  } as WeekData
}

const composed = {
  constraints,
  goal: { tracks: [] },
  composition: { days: [1, 2, 3, 4, 5, 6], lanes: lanes.map((l) => ({
    key: `${l.philosophyId}/${l.trackId}`, kind: 'contract', philosophy_id: l.philosophyId, track_id: l.trackId,
    name: l.philosophyId, weight: l.weight, days: 3, reserved_days: [], cuts: { optional: false, volume: 1, exposures: {} },
  })) },
  weeks: [week(1, 'transition', 'texas_method'), week(2, 'base', 'texas_method')],
} as unknown as GeneratedProgram

describe('a composition request', () => {
  it('sends its tracks, not a philosophy or a track', () => {
    const body = buildPostBody({ lanes: [{ ...lanes[0], startPhaseId: 'base', periodizationWeek: 2 }, lanes[1]],
      constraints, numWeeks: 8 })
    expect(body).toMatchObject({ num_weeks: 8, lanes: [
      { philosophy_id: 'uphill_athlete', track_id: 'full_program', weight: 0.6, start_phase: 'base', periodization_week: 2 },
      { philosophy_id: 'starting_strength', track_id: 'texas_method', weight: 0.4 },
    ] })
    expect(body).not.toHaveProperty('philosophy_id')
    expect(body).not.toHaveProperty('track_id')
  })

  it('stores each philosophy once, its tracks weights summed', () => {
    expect(sourcesOf({ lanes: [
      { philosophyId: 'a', weight: 2 }, { philosophyId: 'a', weight: 1 }, { philosophyId: 'b', weight: 1 }] }))
      .toEqual({ ids: ['a', 'b'], weights: { a: 0.75, b: 0.25 } })
  })

  it('is what a blend of several tracks asks for in the builder', () => {
    const params = builderGenerateParams({
      sourceMode: 'blend', selectedPhilosophyIds: ['uphill_athlete', 'starting_strength'], philosophyWeights: {},
      constraints, eventDate: null, startDate: null, numWeeks: null, selectedTrackId: null, startPhaseId: null,
      priorityOverrides: null,
      lanes: [{ philosophyId: 'uphill_athlete', trackId: null, weight: 60, startPhaseId: 'base' },
              { philosophyId: 'starting_strength', trackId: 'texas_method', weight: 40, startPhaseId: null }],
    }, null, [])
    expect(params.lanes).toEqual([
      { philosophyId: 'uphill_athlete', trackId: null, weight: 0.6, startPhaseId: 'base' },
      { philosophyId: 'starting_strength', trackId: 'texas_method', weight: 0.4, startPhaseId: null },
    ])
    expect(params.philosophyIds).toBeUndefined()
  })
})

describe('regenerating a composition', () => {
  it('asks for its tracks', () => {
    expect(compositionLanes(composed)).toEqual(lanes)
    expect(regenerateSource(['uphill_athlete', 'starting_strength'], {}, composed)).toEqual({ lanes })
  })

  it('resumes each track in its own phase and phase week', () => {
    const resume = tailResume(composed, 1)
    expect(resume.lanes).toEqual([
      { ...lanes[0], startPhaseId: 'base', periodizationWeek: 2 },
      { ...lanes[1], startPhaseId: 'texas_method', periodizationWeek: 4 },
    ])
    expect(resume.trackId).toBeUndefined()
    expect(resume.constraints).not.toHaveProperty('start_phase')
  })
})

describe('a composition on the page', () => {
  it('groups each track’s weeks by its own phase', () => {
    expect(laneSegments(composed.weeks, 'uphill_athlete/full_program').map((s) => [s.phaseId, s.weeks]))
      .toEqual([['transition', 1], ['base', 1]])
    expect(laneSegments(composed.weeks, 'starting_strength/texas_method').map((s) => [s.phaseId, s.weeks]))
      .toEqual([['texas_method', 2]])
  })

  it('asks what any track asks before it runs', () => {
    const req = (levels: string[], mastered: string[], bells: number, loads: string[]) => ({
      entry_requirements: { training_levels: levels, mastered_exercises: mastered, kettlebell_count: bells,
                            starting_loads: loads.map((id) => ({ id, name: id })) },
    }) as unknown as Track
    const merged = mergedEntryRequirements([req(['intermediate', 'advanced'], ['clean'], 1, ['squat']),
                                            req(['novice', 'intermediate'], ['press'], 2, ['squat', 'deadlift']),
                                            undefined], 'intermediate')
    expect(merged).toMatchObject({ training_levels: ['intermediate'], mastered_exercises: ['clean', 'press'],
                                   kettlebell_count: 2 })
    expect(merged?.starting_loads?.map((l) => l.id)).toEqual(['squat', 'deadlift'])
    expect(mergedEntryRequirements([undefined], 'intermediate')).toBeUndefined()
  })

  it('asks for every implement any track needs, at the most any asks', () => {
    const dumbbells = { equipment: 'dumbbell', count: 2, countKey: 'dumbbell_count', number: 'two', plural: 'dumbbells' }
    const tracks = [
      // A build of the server that said only kettlebell_count.
      { entry_requirements: { training_levels: ['intermediate'], mastered_exercises: [], kettlebell_count: 2 } },
      { entry_requirements: { training_levels: ['intermediate'], mastered_exercises: [], kettlebell_count: 1,
                              implements: [dumbbells] } },
    ] as unknown as Track[]
    const merged = mergedEntryRequirements(tracks, 'intermediate')
    expect(trackImplements(merged).map((i) => i.countKey).sort()).toEqual(['dumbbell_count', 'kettlebell_count'])
    expect(implementCount({ dumbbell_count: 2 }, 'dumbbell_count')).toBe(2)
    expect(implementCount({}, 'dumbbell_count')).toBe(0)
  })
})
