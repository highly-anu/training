import { describe, it, expect } from 'vitest'
import { formatLoad } from './formatLoad'
import type { ExerciseLoad } from '@/api/types'

describe('formatLoad rounds', () => {
  it('says one round, not "1 rounds" (Murph, Angie)', () => {
    expect(formatLoad({ target_rounds: 1, format: 'FOR TIME' } as ExerciseLoad)).toBe('1 round · FOR TIME')
  })

  it('carries a round\'s own count (the first movement of a couplet)', () => {
    expect(formatLoad({ target_rounds: 5, reps_per_round: 5, format: 'FOR TIME' } as ExerciseLoad))
      .toBe('5 rounds × 5 reps · FOR TIME')
  })

  it('writes a rep scheme as the source does (Fran)', () => {
    expect(formatLoad({ target_rounds: 3, rep_scheme: [21, 15, 9], format: 'FOR TIME' } as ExerciseLoad))
      .toBe('21-15-9 reps · FOR TIME')
    expect(formatLoad({ rep_scheme: [21, 15, 9] } as ExerciseLoad)).toBe('21-15-9 reps')
  })
})
