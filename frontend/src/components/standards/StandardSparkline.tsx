import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'

/**
 * A block's results as a small line in the standard's modality colour: where
 * the block started (the first point) to where it stands. No axis — the words
 * beside it ("+1 level this block") carry the reading; the axis runs the way
 * the detail chart's does (a faster time is lower).
 */
export function StandardSparkline({ points, domain, label }: {
  points: Array<{ value: number }>; domain?: string | null; label: string
}) {
  if (points.length < 2) return null
  const w = 64, h = 18, pad = 2
  const values = points.map((p) => p.value)
  const lo = Math.min(...values), hi = Math.max(...values)
  const span = hi - lo || 1
  const xy = points.map((p, i) => [
    pad + (i / (points.length - 1)) * (w - 2 * pad),
    h - pad - ((p.value - lo) / span) * (h - 2 * pad),
  ])
  const color = (domain && MODALITY_COLORS[domain as ModalityId]?.hex) || 'var(--color-primary)'
  const [lx, ly] = xy[xy.length - 1]
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} role="img" aria-label={label} className="shrink-0">
      <polyline points={xy.map(([x, y]) => `${x},${y}`).join(' ')} fill="none" stroke={color}
                strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={lx} cy={ly} r={2.5} fill={color} />
    </svg>
  )
}
