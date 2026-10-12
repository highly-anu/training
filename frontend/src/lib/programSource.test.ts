import { describe, it, expect } from 'vitest'
import { regenerateSource } from './programSource'
import type { GeneratedProgram } from '@/api/types'

const goal = (g: Record<string, unknown>) => ({ goal: g } as unknown as Pick<GeneratedProgram, 'goal'>)

describe('regenerateSource', () => {
  it('uses the stored ids', () => {
    expect(regenerateSource(['wildman_kettlebell'], {}, null)).toEqual({ philosophyId: 'wildman_kettlebell' })
    expect(regenerateSource(['a', 'b'], { a: 0.7, b: 0.3 }, null))
      .toEqual({ philosophyIds: ['a', 'b'], philosophyWeights: { a: 0.7, b: 0.3 } })
  })

  it('skips the _blended marker', () => {
    expect(regenerateSource(['_blended', 'a'], {}, null)).toEqual({ philosophyId: 'a' })
  })

  it("falls back to the goal's primary_sources", () => {
    expect(regenerateSource([], {}, goal({ id: '_phil_blend', primary_sources: ['a', 'b'] })))
      .toEqual({ philosophyIds: ['a', 'b'], philosophyWeights: {} })
    expect(regenerateSource(['_blended'], {}, goal({ id: '_phil_x', primary_sources: ['x'] })))
      .toEqual({ philosophyId: 'x' })
  })

  it('reads a single philosophy from the goal id', () => {
    expect(regenerateSource([], {}, goal({ id: '_phil_uphill_athlete' }))).toEqual({ philosophyId: 'uphill_athlete' })
    expect(regenerateSource([], {}, goal({ id: '_phil_blend' }))).toEqual({})
  })
})
