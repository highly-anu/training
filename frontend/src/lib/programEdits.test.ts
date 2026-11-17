import { describe, expect, it } from 'vitest'
import { withSessionAdded, withSessionRemoved } from './programEdits'
import type { GeneratedProgram, Session } from '@/api/types'

const session = (name: string, added = false) => ({ archetype: { name }, added } as unknown as Session)
const names = (p: GeneratedProgram) => p.weeks[0].schedule.Monday.map((s) => s.archetype?.name)

describe('withSessionAdded', () => {
  const program = {
    weeks: [{ schedule: { Monday: [session('planned'), session('extra one', true), session('extra two', true)] } }],
  } as unknown as GeneratedProgram

  it('appends after the day\'s others', () => {
    expect(names(withSessionAdded(program, 0, 'Monday', session('new')))).toEqual(
      ['planned', 'extra one', 'extra two', 'new'])
  })

  it('puts an undone removal back in its own place', () => {
    const removed = withSessionRemoved(program, 0, 'Monday', 1)
    expect(names(removed)).toEqual(['planned', 'extra two'])
    const restored = withSessionAdded(removed, 0, 'Monday', program.weeks[0].schedule.Monday[1], 1)
    expect(names(restored)).toEqual(['planned', 'extra one', 'extra two'])
  })

  it('keeps an index past the end inside the day', () => {
    expect(names(withSessionAdded(program, 0, 'Monday', session('new'), 9)).at(-1)).toBe('new')
  })
})
