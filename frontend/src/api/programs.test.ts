import { describe, it, expect, vi } from 'vitest'

vi.mock('./client', () => ({ apiClient: { get: vi.fn(), post: vi.fn(), put: vi.fn(), delete: vi.fn() } }))

import { buildPostBody } from './programs'
import type { AthleteConstraints } from './types'

const constraints = { training_level: 'intermediate', equipment: [], days_per_week: 3 } as unknown as AthleteConstraints

describe('buildPostBody', () => {
  it('names the first week of a partial regenerate', () => {
    const body = buildPostBody({ philosophyId: 'starting_strength', constraints, numWeeks: 3, weekInProgram: 2 })
    expect(body).toMatchObject({ philosophy_id: 'starting_strength', num_weeks: 3, week_in_program: 2 })
  })

  it('leaves a full generate numbered from 1', () => {
    const body = buildPostBody({ philosophyId: 'starting_strength', constraints, numWeeks: 4 })
    expect(body).not.toHaveProperty('week_in_program')
  })

  it('sends a blend as ids and weights', () => {
    const body = buildPostBody({ philosophyIds: ['a', 'b'], philosophyWeights: { a: 0.6, b: 0.4 }, constraints })
    expect(body).toMatchObject({ philosophy_ids: ['a', 'b'], philosophy_weights: { a: 0.6, b: 0.4 } })
    expect(body).not.toHaveProperty('philosophy_id')
  })
})
