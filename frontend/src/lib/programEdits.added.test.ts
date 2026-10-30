import { describe, it, expect } from 'vitest'
import { withSessionAdded, withSessionRemoved } from '@/lib/programEdits'
import type { GeneratedProgram, Session } from '@/api/types'

const session = (modality: string, extra: Partial<Session> = {}) =>
  ({ modality, archetype: { id: modality }, exercises: [], ...extra }) as unknown as Session

const program = {
  weeks: [{ week_number: 1, schedule: { Monday: [session('max_strength')], Tuesday: [] } }],
} as unknown as GeneratedProgram

// A session the athlete adds on the fly (a rest day's mobility), and removes.
describe('withSessionAdded', () => {
  it("goes after the day's others, marked added", () => {
    const out = withSessionAdded(program, 0, 'Monday', session('mobility'))
    expect(out.weeks[0].schedule.Monday.map((s) => s.modality)).toEqual(['max_strength', 'mobility'])
    expect(out.weeks[0].schedule.Monday[1].added).toBe(true)
    expect(out.weeks[0].schedule.Monday[0].added).toBeUndefined()
  })

  it("is an empty day's first", () => {
    const out = withSessionAdded(program, 0, 'Wednesday', session('mobility'))
    expect(out.weeks[0].schedule.Wednesday).toHaveLength(1)
  })

  it('leaves a program alone for a week it does not have', () => {
    expect(withSessionAdded(program, 3, 'Monday', session('mobility'))).toBe(program)
  })
})

describe('withSessionRemoved', () => {
  it('removes an added session', () => {
    const added = withSessionAdded(program, 0, 'Monday', session('mobility'))
    expect(withSessionRemoved(added, 0, 'Monday', 1).weeks[0].schedule.Monday).toHaveLength(1)
  })

  it("never removes the plan's own session", () => {
    expect(withSessionRemoved(program, 0, 'Monday', 0).weeks[0].schedule.Monday).toHaveLength(1)
  })
})
