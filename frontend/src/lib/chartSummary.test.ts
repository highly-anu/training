import { describe, expect, it } from 'vitest'
import { join, named, range, series, shares } from './chartSummary'

describe('chartSummary', () => {
  it('says a recording as its average and its span', () => {
    expect(range([98, 171, 157], 'bpm')).toBe('Average 142 bpm, from 98 to 171')
    expect(range([60, 60], 'bpm')).toBe('60 bpm throughout')
    expect(range([])).toBeNull()
  })

  it('says a series by its latest point first', () => {
    expect(series([1, 5, 2, 4], 'sessions')).toBe('Latest 4 sessions, average 3, from 1 to 5')
    expect(series([7], 'h')).toBe('7 h')
    expect(series([null, undefined, NaN])).toBeNull()
  })

  it('skips the gaps in a series', () => {
    expect(series([40, null, 50])).toBe('Latest 50, average 45, from 40 to 50')
  })

  it('formats with the caller’s format', () => {
    expect(series([1.25, 1.75], '×BW', (v) => v.toFixed(2))).toBe('Latest 1.75 ×BW, average 1.50, from 1.25 to 1.75')
  })

  it('says shares largest first and leaves zeros out', () => {
    expect(shares([
      { name: 'Zone 3', value: 20 }, { name: 'Zone 2', value: 62 }, { name: 'Zone 5', value: 0 }, { name: 'Zone 1', value: 18 },
    ])).toBe('Zone 2 62 percent, Zone 3 20 percent, Zone 1 18 percent')
    expect(shares([{ name: 'a', value: 0 }])).toBeNull()
  })

  it('joins what there is to say', () => {
    expect(join(named('Fitness', series([30, 45])), null, named('Fatigue', null))).toBe('Fitness: latest 45, average 38, from 30 to 45')
    expect(join(null, false)).toBeNull()
  })
})
