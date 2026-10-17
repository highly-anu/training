/**
 * The plan-against-recorded rows and the sentence for a session whose
 * programming prescribes load: the same cases as the phone's.
 */
import { describe, it, expect } from 'vitest'
import { untrackedText, zonePlanRows } from './zonePlan'
import type { WorkoutPlanned } from '@/api/types'

describe('zonePlanRows', () => {
  it('keeps only the zones with either side', () => {
    // Today's KB Ballistic Power: planned Z1–4, recorded Z1–2.
    expect(zonePlanRows([7.5, 12.5, 15, 10, 0], [22.88, 15.98, 0.13, 0, 0]).map((r) => r.label))
      .toEqual(['Z1', 'Z2', 'Z3', 'Z4'])
    expect(zonePlanRows([0, 0, 0, 0, 0], [0, 0, 0, 0, 0])).toEqual([])
  })
})

describe('untrackedText', () => {
  const plan = (over: Partial<WorkoutPlanned>): WorkoutPlanned => ({
    track: false, source: 'slots', plannedMinutes: [0, 0, 0, 0, 0], notZoned: ['main: heavy'],
    sessionName: 'Workout A', modality: 'max_strength', ...over })
  it('says what the programming prescribes instead', () => {
    expect(untrackedText(plan({}))).toContain('(main: heavy)')
    expect(untrackedText(plan({ source: 'declared', notZoned: [] }))).toContain("doesn't track heart rate")
  })
})
