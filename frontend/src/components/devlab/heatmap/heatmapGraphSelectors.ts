/**
 * Pure graph selectors used by the heatmap.
 *
 * These live outside HeatmapGraph.tsx so that file exports only components:
 * mixing helpers in defeats React Fast Refresh, which then does a full reload
 * on every edit instead of preserving state.
 */
import type { HeatmapGraphData } from './useHeatmapData'

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
