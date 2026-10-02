import { describe, it, expect } from 'vitest'
import { blockBands, blockColor, currencySeries, formatDelta, liftSeries, BLOCK_PALETTE } from './developmentShaping'
import type { DevelopmentBlock, DevelopmentLift, DevelopmentCurrency } from '@/api/types'

const blocks: DevelopmentBlock[] = [
  { id: 1, versionId: 'vA', label: 'A', methodologies: [{ id: 'a', name: 'Wildman' }, { id: 'b', name: 'SS' }],
    from: '2026-08-10', to: '2026-09-06', isActive: false, weeks: 6, plannedTotal: 6, planned: 4, completed: 3, completionPct: 75, source: 'put' },
  { id: 2, versionId: 'vB', label: 'B', methodologies: [{ id: 'b', name: 'SS' }],
    from: '2026-09-07', to: null, isActive: true, weeks: 4, plannedTotal: 3, planned: 3, completed: 3, completionPct: 100, source: 'generate' },
]

describe('developmentShaping', () => {
  it('gives each block a band, the active one running to today', () => {
    const bands = blockBands(blocks, '2026-10-01')
    expect(bands.map((b) => b.label)).toEqual(['Wildman + SS', 'SS'])
    expect(bands[0].x1).toBeLessThan(bands[0].x2)
    expect(bands[1].x2).toBe(new Date('2026-10-01T00:00:00').getTime())
    expect(bands[1].isActive).toBe(true)
    expect(bands[0].color).toBe(BLOCK_PALETTE[0])
    expect(bands[1].color).toBe(BLOCK_PALETTE[1])
    expect(blockColor(blocks, 99)).toBe('#9ca3af')
  })

  it('puts a lift on the time axis with est-1RM, else the weight', () => {
    const lift: DevelopmentLift = {
      exerciseId: 'back_squat', name: 'Back Squat', unit: 'kg', blocks: 2,
      points: [
        { date: '2026-08-10', blockId: 1, weight: 80, reps: 5, est1rm: 93.3, isDeload: false },
        { date: '2026-08-24', blockId: 1, weight: 70, reps: null, est1rm: null, isDeload: true },
      ],
      perBlock: [], trend: { direction: 'improving', slopePct: 2, pointsUsed: 2 },
    }
    const s = liftSeries(lift)
    expect(s.map((p) => p.value)).toEqual([93.3, 70])
    expect(s[1].isDeload).toBe(true)
    expect(s[0].x).toBeLessThan(s[1].x)
  })

  it('shapes a currency and formats deltas', () => {
    const run: DevelopmentCurrency = {
      exerciseId: 'run_easy', name: 'Easy Run', metric: 'minutes',
      points: [{ date: '2026-08-10', blockId: 1, value: 25, isDeload: false }],
      perBlock: [], trend: { direction: 'insufficient_data', slopePct: 0, pointsUsed: 1 },
    }
    expect(currencySeries(run)[0].value).toBe(25)
    expect(formatDelta(12.5)).toBe('+12.5')
    expect(formatDelta(-3)).toBe('−3')
    expect(formatDelta(0)).toBe('0')
  })
})
