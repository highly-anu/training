import { motion } from 'framer-motion'
import type { HeatEdge } from './useHeatmapData'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'

interface HeatmapEdgeProps {
  edge: HeatEdge
  x1: number
  y1: number
  x2: number
  y2: number
  highlighted: boolean | null // null = no highlight mode, true = highlighted, false = dimmed
}

export function HeatmapEdge({ edge, x1, y1, x2, y2, highlighted }: HeatmapEdgeProps) {
  let color = '#94a3b8'
  if (edge.modalityHint && edge.modalityHint in MODALITY_COLORS) {
    color = MODALITY_COLORS[edge.modalityHint as ModalityId].hex
  }

  const dimmed = highlighted === false
  const bright = highlighted === true

  const baseOpacity = edge.heat > 0 ? 0.08 + edge.heat * 0.92 : 0.04
  const strokeOpacity = dimmed ? 0.02 : bright ? Math.max(0.5, baseOpacity) : baseOpacity
  const strokeWidth = dimmed ? 0.3 : 0.5 + edge.heat * 2.5

  const midY = (y1 + y2) / 2
  const d = `M ${x1} ${y1} Q ${x1} ${midY}, ${(x1 + x2) / 2} ${midY} T ${x2} ${y2}`

  return (
    <motion.path
      fill="none"
      stroke={color}
      initial={false}
      animate={{ d, strokeOpacity, strokeWidth }}
      transition={{
        d: { type: 'spring', damping: 25, stiffness: 180 },
        strokeOpacity: { duration: 0.2 },
        strokeWidth: { duration: 0.2 },
      }}
    />
  )
}
