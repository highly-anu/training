import { describe, expect, it } from 'vitest'
import { rollRank } from './rollRank'

describe('rollRank', () => {
  it('reads a number, grouped or not', () => {
    expect(rollRank(72)).toBe(72)
    expect(rollRank('72')).toBe(72)
    expect(rollRank('1,234')).toBe(1234)
    expect(rollRank('3/5')).toBe(3)
  })

  it('reads a clock as seconds', () => {
    expect(rollRank('4:58')).toBe(298)
    expect(rollRank('10:02')).toBeGreaterThan(rollRank('9:58'))
    expect(rollRank('1:00:05')).toBe(3605)
  })

  it('is NaN for text', () => {
    expect(rollRank('—')).toBeNaN()
  })
})
