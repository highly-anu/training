import { describe, it, expect } from 'vitest'
import { nextDropTarget, type Box } from './dndKeyboard'

// Seven day columns, 100 wide with a 10 px gap, as the week grid lays them out.
const columns: (Box & { day: number })[] = Array.from({ length: 7 }, (_, day) => ({
  day, left: day * 110, top: 0, width: 100, height: 300,
}))
const cardIn = (day: number): Box => ({ left: day * 110 + 5, top: 40, width: 90, height: 80 })

describe('nextDropTarget', () => {
  it('moves one column at a time', () => {
    expect(nextDropTarget(cardIn(2), columns, 'right')?.day).toBe(3)
    expect(nextDropTarget(cardIn(2), columns, 'left')?.day).toBe(1)
  })

  it('stays at the edge', () => {
    expect(nextDropTarget(cardIn(0), columns, 'left')).toBeUndefined()
    expect(nextDropTarget(cardIn(6), columns, 'right')).toBeUndefined()
  })

  it('does not count the target the item is centred on', () => {
    expect(nextDropTarget(columns[3], columns, 'right')?.day).toBe(4)
  })

  it('prefers the target straight ahead over a nearer diagonal one', () => {
    const rows: (Box & { id: string })[] = [
      { id: 'below', left: 0, top: 200, width: 100, height: 40 },
      { id: 'diagonal', left: 150, top: 120, width: 100, height: 40 },
    ]
    const from: Box = { left: 0, top: 0, width: 100, height: 40 }
    expect(nextDropTarget(from, rows, 'down')?.id).toBe('below')
  })

  it('walks a list of rows up and down', () => {
    const rows = [0, 1, 2].map((i) => ({ i, left: 0, top: i * 50, width: 200, height: 40 }))
    expect(nextDropTarget(rows[1], rows, 'down')?.i).toBe(2)
    expect(nextDropTarget(rows[1], rows, 'up')?.i).toBe(0)
    expect(nextDropTarget(rows[0], rows, 'up')).toBeUndefined()
  })
})
