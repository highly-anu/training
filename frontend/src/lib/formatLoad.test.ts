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
})
