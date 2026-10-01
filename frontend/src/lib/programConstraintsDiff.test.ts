import { describe, it, expect } from 'vitest'
import { constraintDifferences, daysPerWeekOf, mergedConstraints } from './programConstraintsDiff'
import type { AthleteConstraints, Day, DaySchedule } from '@/api/types'

const base: AthleteConstraints = {
  equipment: ['barbell', 'rack', 'plates'],
  days_per_week: 3,
  session_time_minutes: 75,
  training_level: 'intermediate',
  injury_flags: [],
  avoid_movements: [],
  training_phase: 'base',
  periodization_week: 1,
  fatigue_state: 'fresh',
}

const day = (s1: DaySchedule['session1'], s2: DaySchedule['session2'] = 'rest'): DaySchedule =>
  ({ session1: s1, session2: s2, session3: 'rest', session4: 'rest' })

const fourDays: Record<Day, DaySchedule> = {
  Monday: day('long'), Tuesday: day('rest'), Wednesday: day('short'), Thursday: day('rest', 'mobility'),
  Friday: day('long'), Saturday: day('rest'), Sunday: day('rest'),
}

describe('programConstraintsDiff', () => {
  it('reports nothing when the profile matches the program', () => {
    expect(constraintDifferences(base, {
      trainingLevel: 'intermediate', equipment: ['plates', 'rack', 'barbell'], injuryFlags: [], weeklySchedule: null,
    })).toEqual([])
  })

  it('names each field that moved on', () => {
    const diffs = constraintDifferences(base, {
      trainingLevel: 'advanced', equipment: ['barbell', 'rack', 'kettlebell'], injuryFlags: ['lumbar_disc'],
      weeklySchedule: fourDays,
    })
    expect(diffs.map((d) => d.field)).toEqual(['training_level', 'equipment', 'days_per_week', 'injury_flags'])
    expect(diffs[0]).toMatchObject({ program: 'intermediate', profile: 'advanced' })
    expect(diffs[1].profile).toBe('1 added, 1 removed')
    expect(diffs[2]).toMatchObject({ program: '3', profile: '4' })
    expect(diffs[3].profile).toBe('1 added')
  })

  it('ignores an empty equipment list and a missing schedule', () => {
    expect(constraintDifferences(base, {
      trainingLevel: 'intermediate', equipment: [], injuryFlags: [], weeklySchedule: null,
    })).toEqual([])
    expect(constraintDifferences(undefined, {
      trainingLevel: 'advanced', equipment: [], injuryFlags: [], weeklySchedule: null,
    })).toEqual([])
  })

  it('counts a day as training when any of its sessions is not rest', () => {
    expect(daysPerWeekOf(fourDays)).toBe(4)
    expect(daysPerWeekOf(null)).toBeNull()
  })

  it('merges the profile onto the program constraints', () => {
    const merged = mergedConstraints(base, {
      trainingLevel: 'advanced', equipment: ['kettlebell'], injuryFlags: ['shoulder_impingement'], weeklySchedule: fourDays,
    }, 2)
    expect(merged).toMatchObject({
      training_level: 'advanced', equipment: ['kettlebell'], injury_flags: ['shoulder_impingement'],
      days_per_week: 4, periodization_week: 2, session_time_minutes: 75,
    })
  })
})
