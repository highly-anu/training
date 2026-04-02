import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { HeatmapNode } from './HeatmapNode'
import { HeatmapEdge } from './HeatmapEdge'
import type { HeatmapGraphData, LayerKind, ExerciseInGroup } from './useHeatmapData'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { ModalityId } from '@/api/types'
import { motion } from 'framer-motion'

// ─── Layout constants ────────────────────────────────────────────────────────

const LAYER_Y: Record<LayerKind, number> = {
  philosophy: 30,
  framework: 180,
  modality: 330,
  archetype: 480,
  exercise_group: 630,
}

const EXPANDED_EXERCISES_Y = 750
const NODE_HEIGHT = 28
const NODE_PAD = 8
const MAX_NODE_WIDTH = 160
const SVG_PAD = 32

// ─── Types ───────────────────────────────────────────────────────────────────

interface NodePosition {
  x: number
  y: number
  width: number
  height: number
}

interface HeatmapGraphProps {
  data: HeatmapGraphData
  highlightedNode: string | null
  lockedNode: string | null
  onHoverNode: (id: string | null) => void
  onClickNode: (id: string) => void
  expandedGroup: string | null
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const LAYER_ORDER: LayerKind[] = ['philosophy', 'framework', 'modality', 'archetype', 'exercise_group']

function getConnectedNodeIds(
  nodeId: string,
  edges: HeatmapGraphData['edges'],
): Set<string> {
  const connected = new Set<string>()
  connected.add(nodeId)

  // Walk upward
  const queue = [nodeId]
  const visited = new Set<string>()
  while (queue.length > 0) {
    const current = queue.pop()!
    if (visited.has(current)) continue
    visited.add(current)
    for (const edge of edges) {
      if (edge.target === current) {
        connected.add(edge.source)
        connected.add(edge.id)
        queue.push(edge.source)
      }
    }
  }

  // Walk downward
  const queue2 = [nodeId]
  const visited2 = new Set<string>()
  while (queue2.length > 0) {
    const current = queue2.pop()!
    if (visited2.has(current)) continue
    visited2.add(current)
    for (const edge of edges) {
      if (edge.source === current) {
        connected.add(edge.target)
        connected.add(edge.id)
        queue2.push(edge.target)
      }
    }
  }

  return connected
}

// ─── Component ───────────────────────────────────────────────────────────────

export function HeatmapGraph({
  data,
  highlightedNode,
  lockedNode,
  onHoverNode,
  onClickNode,
  expandedGroup,
}: HeatmapGraphProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [tooltip, setTooltip] = useState<{ x: number; y: number; text: string } | null>(null)
  const [containerWidth, setContainerWidth] = useState(0)

  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    setContainerWidth(el.clientWidth)
    const ro = new ResizeObserver(([entry]) => {
      setContainerWidth(entry.contentRect.width)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  // Group nodes by layer
  const nodesByLayer = useMemo(() => {
    const map: Record<LayerKind, typeof data.nodes> = {
      philosophy: [], framework: [], modality: [], archetype: [], exercise_group: [],
    }
    for (const node of data.nodes) {
      map[node.layer].push(node)
    }
    // Sort each layer: hot nodes toward center for visual appeal
    for (const layer of LAYER_ORDER) {
      map[layer].sort((a, b) => a.label.localeCompare(b.label))
    }
    return map
  }, [data.nodes])

  // Calculate positions for all nodes — fit every layer within the container width
  const { positions, svgWidth, svgHeight } = useMemo(() => {
    const availableWidth = Math.max(containerWidth - 2 * SVG_PAD, 200)
    const pos: Record<string, NodePosition> = {}

    for (const layer of LAYER_ORDER) {
      const nodes = nodesByLayer[layer]
      const count = nodes.length
      if (count === 0) continue
      // Shrink nodes as needed so all fit in one row; cap at MAX_NODE_WIDTH
      const nodeWidth = Math.min(
        MAX_NODE_WIDTH,
        (availableWidth - (count - 1) * NODE_PAD) / count
      )
      const totalWidth = count * nodeWidth + (count - 1) * NODE_PAD
      const startX = SVG_PAD + (availableWidth - totalWidth) / 2
      const y = LAYER_Y[layer]

      for (let i = 0; i < nodes.length; i++) {
        const x = startX + i * (nodeWidth + NODE_PAD)
        pos[nodes[i].id] = { x, y, width: nodeWidth, height: NODE_HEIGHT }
      }
    }

    // Position expanded exercise nodes if a group is expanded
    let height = LAYER_Y.exercise_group + NODE_HEIGHT + SVG_PAD
    if (expandedGroup && data.exercisesByGroup[expandedGroup.replace('exercise_group::', '')]) {
      const groupKey = expandedGroup.replace('exercise_group::', '')
      const exercises = data.exercisesByGroup[groupKey]
      if (exercises) {
        const exWidth = Math.min(
          100,
          (availableWidth - (exercises.length - 1) * 6) / exercises.length
        )
        const totalExWidth = exercises.length * exWidth + (exercises.length - 1) * 6
        const startX = SVG_PAD + (availableWidth - totalExWidth) / 2
        for (let i = 0; i < exercises.length; i++) {
          const x = startX + i * (exWidth + 6)
          pos[`exercise::${exercises[i].id}`] = { x, y: EXPANDED_EXERCISES_Y, width: exWidth, height: NODE_HEIGHT }
        }
        height = EXPANDED_EXERCISES_Y + NODE_HEIGHT + SVG_PAD
      }
    }

    const svgW = containerWidth > 0 ? containerWidth : availableWidth + 2 * SVG_PAD
    return { positions: pos, svgWidth: svgW, svgHeight: height }
  }, [nodesByLayer, expandedGroup, data.exercisesByGroup, containerWidth])

  // Determine which nodes/edges are highlighted
  const activeNode = lockedNode ?? highlightedNode
  const connectedSet = useMemo(() => {
    if (!activeNode) return null
    return getConnectedNodeIds(activeNode, data.edges)
  }, [activeNode, data.edges])

  const getHighlight = useCallback((id: string): boolean | null => {
    if (!connectedSet) return null
    return connectedSet.has(id)
  }, [connectedSet])

  // Get expanded exercises for rendering
  const expandedExercises = useMemo<ExerciseInGroup[]>(() => {
    if (!expandedGroup) return []
    const groupKey = expandedGroup.replace('exercise_group::', '')
    return data.exercisesByGroup[groupKey] ?? []
  }, [expandedGroup, data.exercisesByGroup])

  return (
    <div
      ref={containerRef}
      className="relative w-full overflow-x-hidden bg-background rounded-lg border border-border"
      style={{ maxHeight: '80vh', overflowY: 'auto' }}
    >
      <svg
        width={svgWidth}
        height={svgHeight}
        viewBox={`0 0 ${svgWidth} ${svgHeight}`}
        className="block w-full"
      >
        <defs>
          <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation="4" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* Layer labels */}
        {LAYER_ORDER.map(layer => (
          <text
            key={layer}
            x={12}
            y={LAYER_Y[layer] + NODE_HEIGHT / 2}
            fontSize={9}
            fontFamily="ui-monospace, monospace"
            fill="#64748b"
            fillOpacity={0.5}
            dominantBaseline="central"
          >
            {layer === 'exercise_group' ? 'exercises' : layer}
          </text>
        ))}

        {/* Edges (render behind nodes) */}
        {data.edges.map(edge => {
          const h = getHighlight(edge.id)
          const sourcePos = positions[edge.source]
          const targetPos = positions[edge.target]
          if (!sourcePos || !targetPos) return null
          return (
            <HeatmapEdge
              key={edge.id}
              edge={edge}
              x1={sourcePos.x + sourcePos.width / 2}
              y1={sourcePos.y + sourcePos.height}
              x2={targetPos.x + targetPos.width / 2}
              y2={targetPos.y}
              highlighted={h}
            />
          )
        })}

        {/* Edges from group to expanded exercises */}
        {expandedGroup && expandedExercises.map(ex => {
          const groupPos = positions[expandedGroup]
          const exPos = positions[`exercise::${ex.id}`]
          if (!groupPos || !exPos) return null
          const modId = expandedGroup.replace('exercise_group::exgroup_', '') as ModalityId
          const color = MODALITY_COLORS[modId]?.hex ?? '#94a3b8'
          const opacity = ex.heat > 0 ? 0.1 + ex.heat * 0.9 : 0.04
          const midY = (groupPos.y + groupPos.height + exPos.y) / 2
          const x1 = groupPos.x + groupPos.width / 2
          const x2 = exPos.x + exPos.width / 2
          return (
            <motion.path
              key={`exedge::${ex.id}`}
              d={`M ${x1} ${groupPos.y + groupPos.height} Q ${x1} ${midY}, ${(x1 + x2) / 2} ${midY} T ${x2} ${exPos.y}`}
              fill="none"
              stroke={color}
              initial={false}
              animate={{ strokeOpacity: opacity, strokeWidth: 0.5 + ex.heat * 2 }}
              transition={{ duration: 0.2 }}
            />
          )
        })}

        {/* Nodes */}
        {data.nodes.map(node => {
          const h = getHighlight(node.id)
          const pos = positions[node.id]
          if (!pos) return null
          return (
            <HeatmapNode
              key={node.id}
              node={node}
              x={pos.x}
              y={pos.y}
              width={pos.width}
              height={pos.height}
              highlighted={h}
              onClick={onClickNode}
              onHover={onHoverNode}
              isExpanded={node.id === expandedGroup}
            />
          )
        })}

        {/* Expanded exercise nodes */}
        {expandedExercises.map(ex => {
          const pos = positions[`exercise::${ex.id}`]
          if (!pos) return null
          const modId = expandedGroup?.replace('exercise_group::exgroup_', '') as ModalityId
          const color = MODALITY_COLORS[modId]?.hex ?? '#94a3b8'
          const baseOpacity = ex.heat > 0 ? 0.15 + ex.heat * 0.85 : 0.08
          const maxChars = Math.floor(pos.width / 6)
          const label = ex.name.length > maxChars ? ex.name.slice(0, maxChars - 1) + '…' : ex.name

          return (
            <g
              key={`exnode::${ex.id}`}
              onMouseEnter={(e) => setTooltip({ x: e.clientX, y: e.clientY, text: `${ex.name} (${ex.rawCount})` })}
              onMouseLeave={() => setTooltip(null)}
            >
              <rect
                x={pos.x}
                y={pos.y}
                width={pos.width}
                height={pos.height}
                rx={3}
                fill={color}
                fillOpacity={baseOpacity}
                stroke={color}
                strokeWidth={0.5}
                strokeOpacity={Math.max(0.1, baseOpacity)}
              />
              <text
                x={pos.x + pos.width / 2}
                y={pos.y + pos.height / 2}
                textAnchor="middle"
                dominantBaseline="central"
                fontSize={8}
                fontFamily="ui-monospace, monospace"
                fill={color}
                fillOpacity={Math.max(0.35, baseOpacity)}
              >
                {label}
              </text>
            </g>
          )
        })}
      </svg>

      {/* Floating tooltip */}
      {tooltip && (
        <div
          className="fixed z-50 px-2 py-1 text-xs rounded bg-popover text-popover-foreground border border-border shadow-md pointer-events-none"
          style={{ left: tooltip.x + 12, top: tooltip.y - 8 }}
        >
          {tooltip.text}
        </div>
      )}
    </div>
  )
}
