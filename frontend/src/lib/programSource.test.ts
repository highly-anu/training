import { describe, it, expect } from 'vitest'
import { regenerateSource, spliceRegenerated } from './programSource'
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

describe('spliceRegenerated', () => {
  const s = (modality: string) => ({ modality }) as unknown as GeneratedProgram['weeks'][number]['schedule'][string][number]
  const week = (n: number, schedule: Record<string, string[]>) => ({
    week_number: n,
    schedule: Object.fromEntries(Object.entries(schedule).map(([d, ms]) => [d, ms.map(s)])),
  }) as unknown as GeneratedProgram['weeks'][number]
  const current = [
    week(1, { Monday: ['run'], Wednesday: ['lift'], Saturday: ['long'] }),
    week(2, { Monday: ['run'], Thursday: ['lift'] }),
  ]
  const generated = [
    week(1, { Tuesday: ['bike'], Saturday: ['ruck'], Sunday: ['mobility'] }),
    week(2, { Tuesday: ['bike'] }),
  ]

  it('keeps the elapsed days of the week the tail starts at', () => {
    // Program started Monday 2026-10-12; regenerate from tomorrow, Sunday the 18th.
    const out = spliceRegenerated(current, generated, 0, '2026-10-12', '2026-10-18')
    const days = Object.fromEntries(Object.entries(out[0].schedule).map(([d, ss]) => [d, ss.map((x) => x.modality)]))
    expect(days).toEqual({ Monday: ['run'], Wednesday: ['lift'], Saturday: ['long'], Sunday: ['mobility'] })
    expect(out[0].week_number).toBe(1)
    expect(out[1]).toBe(generated[1])
  })

  it('rewrites today when the cutoff is today', () => {
    const out = spliceRegenerated(current, generated, 0, '2026-10-12', '2026-10-17')
    expect(out[0].schedule.Saturday.map((x) => x.modality)).toEqual(['ruck'])
    expect(out[0].schedule.Monday.map((x) => x.modality)).toEqual(['run'])
    expect(out[0].schedule.Tuesday).toBeUndefined()
  })

  it('splices whole weeks without a cutoff, and keeps the head', () => {
    const out = spliceRegenerated(current, generated.slice(1), 1, '2026-10-12')
    expect(out).toEqual([current[0], generated[1]])
  })
})
