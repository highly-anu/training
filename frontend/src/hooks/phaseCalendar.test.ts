import { describe, it, expect } from 'vitest'
import { buildPhaseCalendar } from './usePhaseCalendar'
import type { GoalProfile, WeekData } from '@/api/types'

const week = (n: number, phase: WeekData['phase']): WeekData =>
  ({ week_number: n, week_in_phase: n, is_deload: false, phase, schedule: {} }) as unknown as WeekData

const goal = {
  phase_sequence: [
    { phase: 'base', weeks: 8, focus: 'Build the base' },
    { phase: 'build', weeks: 6 },
    { phase: 'peak', weeks: 4 },
  ],
} as unknown as GoalProfile

describe('buildPhaseCalendar', () => {
  it('is the stored weeks, not the methodology\'s canonical plan', () => {
    const cal = buildPhaseCalendar([week(1, 'base'), week(2, 'base'), week(3, 'base'), week(4, 'base')], goal, 2)
    expect(cal.totalWeeks).toBe(4)
    expect(cal.segments).toEqual([{ phase: 'base', weeks: 4, focus: 'Build the base', startWeek: 1, endWeek: 4 }])
    expect(cal.currentPhase).toBe('base')
  })

  it('groups consecutive weeks by phase in order', () => {
    const cal = buildPhaseCalendar(
      [week(1, 'base'), week(2, 'base'), week(3, 'build'), week(4, 'peak'), week(5, 'peak')], goal, 4)
    expect(cal.segments.map((s) => [s.phase, s.weeks, s.startWeek, s.endWeek])).toEqual([
      ['base', 2, 1, 2], ['build', 1, 3, 3], ['peak', 2, 4, 5],
    ])
    expect(cal.totalWeeks).toBe(5)
    expect(cal.currentPhase).toBe('peak')
  })

  it('falls back to the methodology\'s plan when there are no weeks', () => {
    const cal = buildPhaseCalendar([], goal, 1)
    expect(cal.totalWeeks).toBe(18)
    expect(cal.segments.map((s) => s.phase)).toEqual(['base', 'build', 'peak'])
    expect(buildPhaseCalendar(undefined, undefined).totalWeeks).toBe(0)
  })
})
