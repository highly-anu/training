import { useReducedMotion } from 'framer-motion'
import { CHART_ENTRY_MS } from '@/lib/motion'

/** What a Recharts series (`Line`, `Bar`, `Area`, `Pie`) takes to draw itself. */
export interface ChartEntry {
  isAnimationActive: boolean
  animationBegin: number
  animationDuration: number
  animationEasing: 'ease-out'
}

/** The entry for a reduce-motion setting; pure, so it can be tested. */
export function chartEntryProps(reduceMotion: boolean): ChartEntry {
  return {
    isAnimationActive: !reduceMotion,
    animationBegin: 0,
    animationDuration: CHART_ENTRY_MS,
    animationEasing: 'ease-out',
  }
}

/**
 * How every chart draws (docs/frontend-design.md §12): once, in `chartEntry`'s
 * time, decelerating with no bounce — data never overshoots — and not at all
 * under Reduce Motion, which Recharts does not read by itself. Spread it on
 * each series: `<Line {...entry} />`. No chart writes `isAnimationActive` or an
 * `animationDuration` of its own.
 */
export function useChartEntry(): ChartEntry {
  return chartEntryProps(useReducedMotion() ?? false)
}
