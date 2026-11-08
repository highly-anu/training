/**
 * A prescription done at the athlete's level: the server's `rx` and
 * `scaled_from_name`, worded (src/level_scaling.py).
 */
import { describe, it, expect } from 'vitest'
import { scaledFor, scaledFromText, scaledLoadText } from './levelScaling'
import type { ExerciseAssignment } from '@/api/types'

const fran = {
  exercise: { id: 'thruster', name: 'Thruster' },
  load: {
    rep_scheme: [11, 8, 5], target_rounds: 3, weight_kg: 15,
    rx: { rep_scheme: [21, 15, 9], weight_kg: 30 },
    level_scaled: { level: 'novice', from: 'elite', shares: { load: 0.5, volume: 0.5, time: 0.5, distance: 0.5 },
                    sources: { load: 'track', volume: 'track', time: 'track', distance: 'track' } },
  },
} as unknown as ExerciseAssignment

describe('scaledLoadText', () => {
  it('says the level and what was written', () => {
    expect(scaledLoadText(fran)).toBe('Scaled for Novice · Rx 21-15-9 reps · 30kg')
  })
  it('says a ladder and an interval as written', () => {
    const level_scaled = fran.load.level_scaled
    expect(scaledLoadText({ ...fran, load: { sets: 5, reps: '13-10-8-5-3', rx: { reps: '25-20-15-10-5' }, level_scaled } }))
      .toBe('Scaled for Novice · Rx 5×25-20-15-10-5')
    expect(scaledLoadText({ ...fran, load: { target_rounds: 50, work_sec: 30, time_minutes: 25,
                                             rx: { target_rounds: 100, time_minutes: 50 }, level_scaled } }))
      .toBe('Scaled for Novice · Rx 100 × 30s · 50 min')
  })
  it('says nothing for a prescription done as written', () => {
    expect(scaledLoadText({ ...fran, load: { rep_scheme: [21, 15, 9] } } as ExerciseAssignment)).toBeNull()
  })
})

describe('scaledFromText', () => {
  it('names the movement a scale stands for', () => {
    expect(scaledFromText({ ...fran, scaled_from: 'pull_up', scaled_from_name: 'Pull-Up (Overhand)' }))
      .toBe('In place of Pull-Up (Overhand)')
    expect(scaledFromText(fran)).toBeNull()
  })
})

describe('scaledFor', () => {
  it('says a track is scaled below the level it is written for', () => {
    expect(scaledFor({ authored_level: 'elite' }, 'novice')).toBe('Written for Elite · scaled for Novice')
    expect(scaledFor({ authored_level: 'elite' }, 'elite')).toBeNull()
    expect(scaledFor({}, 'novice')).toBeNull()
  })
})
