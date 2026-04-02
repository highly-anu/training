import { motion } from 'framer-motion'
import type { HeatNode } from './useHeatmapData'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'

interface HeatmapNodeProps {
  node: HeatNode
  x: number
  y: number
  width: number
  height: number
  highlighted: boolean | null // null = no highlight mode, true = highlighted, false = dimmed
  onClick: (nodeId: string) => void
  onHover: (nodeId: string | null) => void
  isExpanded?: boolean
}

function getNodeColor(node: HeatNode): string {
  if (node.modalityHint && node.modalityHint in MODALITY_COLORS) {
    return MODALITY_COLORS[node.modalityHint as ModalityId].hex
  }
  // Default colors by layer
  switch (node.layer) {
    case 'philosophy': return '#a78bfa'   // violet-400
    case 'framework': return '#60a5fa'    // blue-400
    default: return '#94a3b8'             // slate-400
  }
}

export function HeatmapNode({ node, x, y, width, height, highlighted, onClick, onHover, isExpanded }: HeatmapNodeProps) {
  const color = getNodeColor(node)
  const baseOpacity = node.heat > 0 ? 0.15 + node.heat * 0.85 : 0.08
  const dimmed = highlighted === false
  const bright = highlighted === true
  const fillOpacity = dimmed ? 0.04 : baseOpacity
  const strokeOpacity = dimmed ? 0.06 : Math.max(0.15, baseOpacity)
  const textOpacity = dimmed ? 0.2 : Math.max(0.4, baseOpacity)
  const glowRadius = bright && node.heat > 0.5 ? 6 : 0

  const label = node.layer === 'exercise_group'
    ? `${node.label}${isExpanded ? ' ▲' : ' ▼'}`
    : node.label

  // Truncate long labels
  const maxChars = Math.floor(width / 6.5)
  const displayLabel = label.length > maxChars ? label.slice(0, maxChars - 1) + '…' : label

  return (
    <motion.g
      onMouseEnter={() => onHover(node.id)}
      onMouseLeave={() => onHover(null)}
      onClick={() => onClick(node.id)}
      style={{ cursor: 'pointer' }}
      initial={false}
      animate={{ opacity: dimmed ? 0.3 : 1 }}
      transition={{ duration: 0.2 }}
    >
      {glowRadius > 0 && (
        <rect
          x={x - 2}
          y={y - 2}
          width={width + 4}
          height={height + 4}
          rx={6}
          fill="none"
          stroke={color}
          strokeWidth={1}
          opacity={0.3}
          filter="url(#glow)"
        />
      )}
      <rect
        x={x}
        y={y}
        width={width}
        height={height}
        rx={4}
        fill={color}
        fillOpacity={fillOpacity}
        stroke={color}
        strokeWidth={bright ? 1.5 : 0.5}
        strokeOpacity={strokeOpacity}
      />
      <text
        x={x + width / 2}
        y={y + height / 2}
        textAnchor="middle"
        dominantBaseline="central"
        fontSize={10}
        fontFamily="ui-monospace, monospace"
        fill={color}
        fillOpacity={textOpacity}
      >
        {displayLabel}
      </text>
      {node.rawCount > 0 && !dimmed && (
        <text
          x={x + width - 4}
          y={y + 8}
          textAnchor="end"
          fontSize={7}
          fontFamily="ui-monospace, monospace"
          fill={color}
          fillOpacity={0.6}
        >
          {node.rawCount}
        </text>
      )}
    </motion.g>
  )
}
