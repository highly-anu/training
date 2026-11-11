import { describe, expect, it } from 'vitest'
import { chartEntryProps } from './chartMotion'
import { CHART_ENTRY_MS } from './motion'

describe('chartEntryProps', () => {
  it('draws once, decelerating, in the chart entry time', () => {
    expect(chartEntryProps(false)).toEqual({
      isAnimationActive: true,
      animationBegin: 0,
      animationDuration: CHART_ENTRY_MS,
      animationEasing: 'ease-out',
    })
  })
  it('does not draw under Reduce Motion', () => {
    expect(chartEntryProps(true).isAnimationActive).toBe(false)
  })
})
