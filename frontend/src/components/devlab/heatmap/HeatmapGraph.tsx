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

const NODE_HEIGHT = 28
const NODE_PAD = 8
const MAX_NODE_WIDTH = 160
const SVG_PAD = 32

// Locked-mode layout
const LOCKED_EX_Y_OFFSET = 72   // gap from bottom of exercise_group row to exercise layer
const EX_NODE_HEIGHT = 22
const EX_CHAR_WIDTH = 5.0        // approx monospace width at font-size 8
const EX_PAD_H = 10
const EX_GAP = 5
const EX_ROW_GAP = 5
const NODE_CHAR_WIDTH = 6.5      // matches HeatmapNode truncation factor
const NODE_PAD_H = 20            // horizontal padding added to natural-width nodes

type LockedExItem = ExerciseInGroup & { groupId: string }

// ─── Types ───────────────────────────────────────────────────────────────────

interface NodePosition {
  x: number
  y: number
  width: number
  height: number
}

export type HeatmapSortMode = 'alpha' | 'heat-desc' | 'heat-asc'

interface HeatmapGraphProps {
  data: HeatmapGraphData
  highlightedNode: string | null
  selectedNodes: string[]  // all currently selected node IDs, ordered top-layer (philosophy) first
  lockedNode: string | null // 2nd-click node: drives layout centering (subset of selectedNodes)
  onHoverNode: (id: string | null) => void
  onClickNode: (id: string) => void
  sortMode?: HeatmapSortMode
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const LAYER_ORDER: LayerKind[] = ['philosophy', 'framework', 'modality', 'archetype', 'exercise_group']

export function getConnectedNodeIds(
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

/** When locked on a philosophy node, prune cross-package archetypes and every
 *  edge/node that hangs exclusively off them (both incoming and outgoing). */
export function prunePhilosophyScope(
  raw: Set<string>,
  pkg: string,
  nodes: HeatmapGraphData['nodes'],
  edges: HeatmapGraphData['edges'],
) {
  const nodeMap = new Map(nodes.map(n => [n.id, n]))

  // 1. Remove cross-package archetype nodes + their incident edges (both directions)
  for (const id of [...raw]) {
    if (!id.startsWith('archetype::')) continue
    const node = nodeMap.get(id)
    if (node?._package && node._package !== pkg) {
      raw.delete(id)
      for (const edge of edges) {
        if (edge.source === id || edge.target === id) raw.delete(edge.id)
      }
    }
  }

  // 2. Remove exercise_group nodes that no longer have any highlighted incoming edge
  for (const id of [...raw]) {
    if (!id.startsWith('exercise_group::')) continue
    const hasIncoming = edges.some(e => e.target === id && raw.has(e.id))
    if (!hasIncoming) raw.delete(id)
  }
}

// ─── Component ───────────────────────────────────────────────────────────────

export function HeatmapGraph({
  data,
  highlightedNode,
  selectedNodes,
  lockedNode,
  onHoverNode,
  onClickNode,
  sortMode = 'alpha',
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

  // Package derived from the selected philosophy node (if any) — used to scope exercises
  const activePackage = useMemo(() => {
    const philNode = selectedNodes.find(n => n.startsWith('philosophy::'))
    return philNode ? philNode.slice('philosophy::'.length) : null
  }, [selectedNodes])

  // Connected set for the locked node only (drives layout centering + connection-count sort).
  // Computed first so nodesByLayer can use it.
  const lockedConnectedSet = useMemo(() => {
    if (!lockedNode) return null
    const raw = getConnectedNodeIds(lockedNode, data.edges)
    if (lockedNode.startsWith('philosophy::')) {
      prunePhilosophyScope(raw, lockedNode.slice('philosophy::'.length), data.nodes, data.edges)
    }
    return raw
  }, [lockedNode, data.edges, data.nodes])

  // Group nodes by layer, sorted per sortMode.
  // When heat is zero (no program), sort by incoming-edge count from the layer above.
  // With a locked selection, only count edges inside the connected subgraph.
  const nodesByLayer = useMemo(() => {
    const map: Record<LayerKind, typeof data.nodes> = {
      philosophy: [], framework: [], modality: [], archetype: [], exercise_group: [],
    }
    for (const node of data.nodes) {
      map[node.layer].push(node)
    }

    if (sortMode !== 'alpha') {
      // Count incoming edges (from above) per node, scoped to the locked subgraph if active
      const incomingCount = new Map<string, number>()
      for (const edge of data.edges) {
        if (lockedConnectedSet && !lockedConnectedSet.has(edge.id)) continue
        incomingCount.set(edge.target, (incomingCount.get(edge.target) ?? 0) + 1)
      }
      // Sort key: heat when available (normalised 0–1), otherwise raw incoming-edge count
      const key = (n: (typeof data.nodes)[0]) =>
        n.heat > 0 ? n.heat : (incomingCount.get(n.id) ?? 0)

      for (const layer of LAYER_ORDER) {
        if (sortMode === 'heat-desc') {
          map[layer].sort((a, b) => key(b) - key(a) || a.label.localeCompare(b.label))
        } else {
          map[layer].sort((a, b) => key(a) - key(b) || a.label.localeCompare(b.label))
        }
      }
    } else {
      for (const layer of LAYER_ORDER) {
        map[layer].sort((a, b) => a.label.localeCompare(b.label))
      }
    }

    return map
  }, [data.nodes, data.edges, sortMode, lockedConnectedSet])

  // Calculate positions for all nodes
  const { positions, svgWidth, svgHeight, lockedExItems } = useMemo(() => {
    const availableWidth = Math.max(containerWidth - 2 * SVG_PAD, 200)
    const pos: Record<string, NodePosition> = {}
    let height = LAYER_Y.exercise_group + NODE_HEIGHT + SVG_PAD
    let maxUsedX = 0
    let exItems: LockedExItem[] = []

    if (lockedConnectedSet) {
      // ── Locked mode: connected nodes get natural label-sized width; unconnected are hidden ──
      for (const layer of LAYER_ORDER) {
        const connected = nodesByLayer[layer].filter(n => lockedConnectedSet.has(n.id))
        if (connected.length === 0) continue

        const widths = connected.map(n => {
          const raw = n.layer === 'exercise_group' ? n.label.replace(/\s*\(\d+\)$/, '').trim() : n.label
          return Math.max(64, Math.ceil(raw.length * NODE_CHAR_WIDTH + NODE_PAD_H))
        })
        const totalW = widths.reduce((s, w) => s + w, 0) + Math.max(0, connected.length - 1) * NODE_PAD
        const startX = SVG_PAD + Math.max(0, (availableWidth - totalW) / 2)
        let curX = startX
        for (let i = 0; i < connected.length; i++) {
          pos[connected[i].id] = { x: curX, y: LAYER_Y[layer], width: widths[i], height: NODE_HEIGHT }
          curX += widths[i] + NODE_PAD
        }
        maxUsedX = Math.max(maxUsedX, curX - NODE_PAD)
      }

      // ── Locked exercise layer: all exercises from connected exercise_groups, wrapped into rows ──
      for (const id of lockedConnectedSet) {
        if (!id.startsWith('exercise_group::')) continue
        const key = id.replace('exercise_group::', '')
        for (const ex of (data.exercisesByGroup[key] ?? [])) {
          if (activePackage && ex._package && ex._package !== activePackage) continue
          exItems.push({ ...ex, groupId: id })
        }
      }
      exItems.sort((a, b) => b.heat - a.heat || a.name.localeCompare(b.name))
      // Deduplicate by exercise ID — an exercise may match multiple groups
      const seenExIds = new Set<string>()
      exItems = exItems.filter(item => {
        if (seenExIds.has(item.id)) return false
        seenExIds.add(item.id)
        return true
      })

      if (exItems.length > 0) {
        const baseY = LAYER_Y.exercise_group + NODE_HEIGHT + LOCKED_EX_Y_OFFSET
        let rowX = SVG_PAD
        let rowY = baseY

        for (const item of exItems) {
          const w = Math.max(48, Math.ceil(item.name.length * EX_CHAR_WIDTH + EX_PAD_H))
          if (rowX + w > availableWidth + SVG_PAD && rowX > SVG_PAD) {
            rowX = SVG_PAD
            rowY += EX_NODE_HEIGHT + EX_ROW_GAP
          }
          pos[`locked_ex::${item.id}`] = { x: rowX, y: rowY, width: w, height: EX_NODE_HEIGHT }
          rowX += w + EX_GAP
          maxUsedX = Math.max(maxUsedX, rowX - EX_GAP)
        }
        height = rowY + EX_NODE_HEIGHT + SVG_PAD
      }

    } else {
      // ── Normal mode: fit all nodes of each layer into one equal-width row ──
      for (const layer of LAYER_ORDER) {
        let nodes = nodesByLayer[layer]
        const count = nodes.length
        if (count === 0) continue

        // Shrink nodes as needed so all fit in one row; cap at MAX_NODE_WIDTH; floor at 1
        const nodeWidth = Math.max(1, Math.min(
          MAX_NODE_WIDTH,
          (availableWidth - (count - 1) * NODE_PAD) / count
        ))
        const totalWidth = count * nodeWidth + (count - 1) * NODE_PAD
        const startX = SVG_PAD + (availableWidth - totalWidth) / 2
        const y = LAYER_Y[layer]

        for (let i = 0; i < nodes.length; i++) {
          pos[nodes[i].id] = { x: startX + i * (nodeWidth + NODE_PAD), y, width: nodeWidth, height: NODE_HEIGHT }
        }
      }

    }

    const minSvgW = containerWidth > 0 ? containerWidth : availableWidth + 2 * SVG_PAD
    const svgW = Math.max(minSvgW, maxUsedX + SVG_PAD)
    return { positions: pos, svgWidth: svgW, svgHeight: height, lockedExItems: exItems }
  }, [nodesByLayer, data.exercisesByGroup, containerWidth, lockedConnectedSet])

  // Intersection of all selected nodes' connected sets; fall back to hover when nothing selected
  const connectedSet = useMemo(() => {
    if (selectedNodes.length > 0) {
      let result: Set<string> | null = null
      for (const nodeId of selectedNodes) {
        const raw = getConnectedNodeIds(nodeId, data.edges)
        if (nodeId.startsWith('philosophy::')) {
          prunePhilosophyScope(raw, nodeId.slice('philosophy::'.length), data.nodes, data.edges)
        }
        if (result === null) {
          result = raw
        } else {
          for (const id of [...result]) {
            if (!raw.has(id)) result.delete(id)
          }
        }
      }
      return result
    }
    // No selection — fall back to hover
    if (!highlightedNode) return null
    return getConnectedNodeIds(highlightedNode, data.edges)
  }, [selectedNodes, highlightedNode, data.edges, data.nodes])

  const getHighlight = useCallback((id: string): boolean | null => {
    if (!connectedSet) return null
    return connectedSet.has(id)
  }, [connectedSet])

  // Build a set for O(1) isSelected checks
  const selectedSet = useMemo(() => new Set(selectedNodes), [selectedNodes])

  return (
    <div
      ref={containerRef}
      className="relative w-full bg-background rounded-lg border border-border"
      style={{ maxHeight: '80vh', overflow: 'auto', scrollbarGutter: 'stable' }}
    >
      <svg
        width={svgWidth}
        height={svgHeight}
        viewBox={`0 0 ${svgWidth} ${svgHeight}`}
        className="block w-full"
        onMouseLeave={() => onHoverNode(null)}
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
            {layer === 'exercise_group' ? 'movements' : layer}
          </text>
        ))}
        {lockedNode && lockedExItems.length > 0 && (
          <text
            x={12}
            y={LAYER_Y.exercise_group + NODE_HEIGHT + LOCKED_EX_Y_OFFSET + EX_NODE_HEIGHT / 2}
            fontSize={9}
            fontFamily="ui-monospace, monospace"
            fill="#64748b"
            fillOpacity={0.5}
            dominantBaseline="central"
          >
            exercises
          </text>
        )}

        {/* Edges (render behind nodes) */}
        {data.edges.map(edge => {
          const h = getHighlight(edge.id)
          // Don't draw lines to nodes hidden by the active selection filter
          if (h === false && connectedSet !== null) return null
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

        {/* Locked exercise layer edges + nodes */}
        {lockedNode && lockedExItems.map(item => {
          const groupPos = positions[item.groupId]
          const exPos = positions[`locked_ex::${item.id}`]
          if (!groupPos || !exPos) return null
          const groupNode = data.nodes.find(n => n.id === item.groupId)
          const color = groupNode?.modalityHint && groupNode.modalityHint in MODALITY_COLORS
            ? MODALITY_COLORS[groupNode.modalityHint as ModalityId].hex
            : '#94a3b8'
          const opacity = item.heat > 0 ? 0.08 + item.heat * 0.5 : 0.04
          const midY = (groupPos.y + groupPos.height + exPos.y) / 2
          const x1 = groupPos.x + groupPos.width / 2
          const x2 = exPos.x + exPos.width / 2
          return (
            <motion.path
              key={`locked_exedge::${item.id}`}
              d={`M ${x1} ${groupPos.y + groupPos.height} Q ${x1} ${midY}, ${(x1 + x2) / 2} ${midY} T ${x2} ${exPos.y}`}
              fill="none"
              stroke={color}
              initial={false}
              animate={{ strokeOpacity: opacity, strokeWidth: 0.5 + item.heat * 1.5 }}
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
              isSelected={selectedSet.has(node.id)}
              isLocked={node.id === lockedNode}
            />
          )
        })}

        {/* Locked exercise nodes — full label, sized to text */}
        {lockedNode && lockedExItems.map(item => {
          const pos = positions[`locked_ex::${item.id}`]
          if (!pos) return null
          const groupNode = data.nodes.find(n => n.id === item.groupId)
          const color = groupNode?.modalityHint && groupNode.modalityHint in MODALITY_COLORS
            ? MODALITY_COLORS[groupNode.modalityHint as ModalityId].hex
            : '#94a3b8'
          const baseOpacity = item.heat > 0 ? 0.15 + item.heat * 0.85 : 0.08
          return (
            <g
              key={`locked_exnode::${item.id}`}
              onMouseEnter={(e) => setTooltip({ x: e.clientX, y: e.clientY, text: `${item.name}${item.rawCount > 0 ? ` (×${item.rawCount})` : ''}` })}
              onMouseLeave={() => setTooltip(null)}
            >
              <rect x={pos.x} y={pos.y} width={pos.width} height={pos.height} rx={3}
                fill={color} fillOpacity={baseOpacity} stroke={color} strokeWidth={0.5}
                strokeOpacity={Math.max(0.1, baseOpacity)} />
              <text x={pos.x + pos.width / 2} y={pos.y + pos.height / 2}
                textAnchor="middle" dominantBaseline="central" fontSize={8}
                fontFamily="ui-monospace, monospace" fill={color} fillOpacity={Math.max(0.4, baseOpacity)}>
                {item.name}
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
