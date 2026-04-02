import { useMemo } from 'react'
import type { OntologyData, TracedProgram, ModalityId } from '@/api/types'

// ─── Graph types ─────────────────────────────────────────────────────────────

export type LayerKind = 'philosophy' | 'framework' | 'modality' | 'archetype' | 'exercise_group'

export interface HeatNode {
  id: string
  label: string
  layer: LayerKind
  /** Modality this node is associated with (for coloring) */
  modalityHint?: ModalityId
  heat: number        // 0–1 normalized
  rawCount: number    // absolute usage count
}

export interface HeatEdge {
  id: string
  source: string      // node id (upper layer)
  target: string      // node id (lower layer)
  sourceLayer: LayerKind
  targetLayer: LayerKind
  modalityHint?: ModalityId
  heat: number
  rawCount: number
}

export interface ExerciseInGroup {
  id: string
  name: string
  heat: number
  rawCount: number
}

export interface HeatmapGraphData {
  nodes: HeatNode[]
  edges: HeatEdge[]
  /** Individual exercises within each modality group */
  exercisesByGroup: Record<string, ExerciseInGroup[]>
  maxHeat: number
  totalExerciseUsages: number
  uniqueExercisesUsed: number
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function nodeId(layer: LayerKind, id: string) {
  return `${layer}::${id}`
}

function edgeId(sourceLayer: LayerKind, sourceId: string, targetLayer: LayerKind, targetId: string) {
  return `${sourceLayer}::${sourceId}--${targetLayer}::${targetId}`
}

// ─── Build static graph from ontology ────────────────────────────────────────

function buildStaticGraph(ontology: OntologyData) {
  const nodes: Map<string, HeatNode> = new Map()
  const edges: Map<string, HeatEdge> = new Map()

  // Layer 0: Philosophies
  for (const p of ontology.philosophies) {
    nodes.set(nodeId('philosophy', p.id), {
      id: nodeId('philosophy', p.id),
      label: p.name,
      layer: 'philosophy',
      heat: 0,
      rawCount: 0,
    })
  }

  // Layer 1: Frameworks + edges to philosophies
  for (const fw of ontology.frameworks) {
    nodes.set(nodeId('framework', fw.id), {
      id: nodeId('framework', fw.id),
      label: fw.name,
      layer: 'framework',
      heat: 0,
      rawCount: 0,
    })
    if (fw.source_philosophy) {
      const eid = edgeId('philosophy', fw.source_philosophy, 'framework', fw.id)
      edges.set(eid, {
        id: eid,
        source: nodeId('philosophy', fw.source_philosophy),
        target: nodeId('framework', fw.id),
        sourceLayer: 'philosophy',
        targetLayer: 'framework',
        heat: 0,
        rawCount: 0,
      })
    }
  }

  // Layer 2: Modalities + edges from frameworks
  for (const m of ontology.modalities) {
    nodes.set(nodeId('modality', m.id), {
      id: nodeId('modality', m.id),
      label: m.name,
      layer: 'modality',
      modalityHint: m.id,
      heat: 0,
      rawCount: 0,
    })
  }
  for (const fw of ontology.frameworks) {
    const keys = Object.keys(fw.sessions_per_week ?? {}) as ModalityId[]
    for (const modId of keys) {
      const eid = edgeId('framework', fw.id, 'modality', modId)
      if (!edges.has(eid)) {
        edges.set(eid, {
          id: eid,
          source: nodeId('framework', fw.id),
          target: nodeId('modality', modId),
          sourceLayer: 'framework',
          targetLayer: 'modality',
          modalityHint: modId,
          heat: 0,
          rawCount: 0,
        })
      }
    }
  }

  // Layer 3: Archetypes + edges from modalities
  for (const arch of ontology.archetypes) {
    const modHint = arch.modality as ModalityId | undefined
    nodes.set(nodeId('archetype', arch.id), {
      id: nodeId('archetype', arch.id),
      label: arch.name,
      layer: 'archetype',
      modalityHint: modHint,
      heat: 0,
      rawCount: 0,
    })
    if (modHint) {
      const eid = edgeId('modality', modHint, 'archetype', arch.id)
      edges.set(eid, {
        id: eid,
        source: nodeId('modality', modHint),
        target: nodeId('archetype', arch.id),
        sourceLayer: 'modality',
        targetLayer: 'archetype',
        modalityHint: modHint,
        heat: 0,
        rawCount: 0,
      })
    }
  }

  // Layer 4: Exercise groups (one per modality)
  // Build a map of modality → exercises for the group expansion
  const exercisesByGroup: Record<string, ExerciseInGroup[]> = {}
  const exerciseModality: Map<string, ModalityId[]> = new Map()

  for (const ex of ontology.exercises) {
    const mods = (Array.isArray(ex.modality) ? ex.modality : [ex.modality]).filter(Boolean) as ModalityId[]
    exerciseModality.set(ex.id, mods)
    for (const mod of mods) {
      const groupId = `exgroup_${mod}`
      if (!exercisesByGroup[groupId]) exercisesByGroup[groupId] = []
      exercisesByGroup[groupId].push({ id: ex.id, name: ex.name, heat: 0, rawCount: 0 })
    }
  }

  // Create group nodes + edges from archetypes to groups
  const modalityIds = new Set(ontology.modalities.map(m => m.id))
  for (const modId of modalityIds) {
    const groupId = `exgroup_${modId}`
    const count = exercisesByGroup[groupId]?.length ?? 0
    nodes.set(nodeId('exercise_group', groupId), {
      id: nodeId('exercise_group', groupId),
      label: `${count} exercises`,
      layer: 'exercise_group',
      modalityHint: modId,
      heat: 0,
      rawCount: 0,
    })
    // Edge from each archetype of this modality to the group
    for (const arch of ontology.archetypes) {
      if (arch.modality === modId) {
        const eid = edgeId('archetype', arch.id, 'exercise_group', groupId)
        edges.set(eid, {
          id: eid,
          source: nodeId('archetype', arch.id),
          target: nodeId('exercise_group', groupId),
          sourceLayer: 'archetype',
          targetLayer: 'exercise_group',
          modalityHint: modId,
          heat: 0,
          rawCount: 0,
        })
      }
    }
  }

  return { nodes, edges, exercisesByGroup, exerciseModality }
}

// ─── Apply heat from program ─────────────────────────────────────────────────

function applyHeat(
  nodes: Map<string, HeatNode>,
  edges: Map<string, HeatEdge>,
  exercisesByGroup: Record<string, ExerciseInGroup[]>,
  exerciseModality: Map<string, ModalityId[]>,
  program: TracedProgram,
  weekRange: [number, number],
  frameworkLookup: Map<string, string | undefined>, // framework_id -> source_philosophy
) {
  let totalUsages = 0
  const usedExercises = new Set<string>()

  for (const week of program.weeks) {
    if (week.week_number < weekRange[0] || week.week_number > weekRange[1]) continue

    const frameworkId = week.framework
    const philosophyId = frameworkId ? frameworkLookup.get(frameworkId) : undefined

    for (const sessions of Object.values(week.schedule)) {
      for (const session of sessions) {
        const modality = session.modality
        const archetypeId = session.archetype?.id

        for (const assignment of session.exercises ?? []) {
          if (assignment.meta || !assignment.exercise) continue
          const exId = assignment.exercise.id
          totalUsages++
          usedExercises.add(exId)

          // Heat the exercise group
          const exMods = exerciseModality.get(exId) ?? [modality]
          for (const mod of exMods) {
            const groupId = `exgroup_${mod}`
            const group = exercisesByGroup[groupId]
            if (group) {
              const item = group.find(e => e.id === exId)
              if (item) item.rawCount++
            }
            // Group node heat
            const gNodeId = nodeId('exercise_group', groupId)
            const gNode = nodes.get(gNodeId)
            if (gNode) gNode.rawCount++
          }

          // Heat the archetype
          if (archetypeId) {
            const aNodeId = nodeId('archetype', archetypeId)
            const aNode = nodes.get(aNodeId)
            if (aNode) aNode.rawCount++

            // Edge: archetype → exercise_group
            const groupId = `exgroup_${modality}`
            const aeEdgeId = edgeId('archetype', archetypeId, 'exercise_group', groupId)
            const aeEdge = edges.get(aeEdgeId)
            if (aeEdge) aeEdge.rawCount++
          }

          // Heat the modality
          const mNodeId = nodeId('modality', modality)
          const mNode = nodes.get(mNodeId)
          if (mNode) mNode.rawCount++

          // Edge: modality → archetype
          if (archetypeId) {
            const maEdgeId = edgeId('modality', modality, 'archetype', archetypeId)
            const maEdge = edges.get(maEdgeId)
            if (maEdge) maEdge.rawCount++
          }

          // Heat the framework
          if (frameworkId) {
            const fNodeId = nodeId('framework', frameworkId)
            const fNode = nodes.get(fNodeId)
            if (fNode) fNode.rawCount++

            // Edge: framework → modality
            const fmEdgeId = edgeId('framework', frameworkId, 'modality', modality)
            const fmEdge = edges.get(fmEdgeId)
            if (fmEdge) fmEdge.rawCount++
          }

          // Heat the philosophy
          if (philosophyId) {
            const pNodeId = nodeId('philosophy', philosophyId)
            const pNode = nodes.get(pNodeId)
            if (pNode) pNode.rawCount++

            // Edge: philosophy → framework
            if (frameworkId) {
              const pfEdgeId = edgeId('philosophy', philosophyId, 'framework', frameworkId)
              const pfEdge = edges.get(pfEdgeId)
              if (pfEdge) pfEdge.rawCount++
            }
          }
        }
      }
    }
  }

  // Normalize heat values per layer
  const layerMaxes: Record<string, number> = {}
  for (const node of nodes.values()) {
    const key = node.layer
    layerMaxes[key] = Math.max(layerMaxes[key] ?? 0, node.rawCount)
  }
  for (const node of nodes.values()) {
    const max = layerMaxes[node.layer] ?? 1
    node.heat = max > 0 ? node.rawCount / max : 0
  }

  let edgeMax = 0
  for (const edge of edges.values()) {
    edgeMax = Math.max(edgeMax, edge.rawCount)
  }
  for (const edge of edges.values()) {
    edge.heat = edgeMax > 0 ? edge.rawCount / edgeMax : 0
  }

  // Normalize exercise heat within groups
  for (const group of Object.values(exercisesByGroup)) {
    const max = Math.max(...group.map(e => e.rawCount), 1)
    for (const ex of group) {
      ex.heat = ex.rawCount / max
    }
  }

  return {
    maxHeat: Math.max(edgeMax, ...Object.values(layerMaxes)),
    totalExerciseUsages: totalUsages,
    uniqueExercisesUsed: usedExercises.size,
  }
}

// ─── Main hook ───────────────────────────────────────────────────────────────

export function useHeatmapData(
  ontology: OntologyData | undefined,
  program: TracedProgram | null,
  weekRange?: [number, number],
): HeatmapGraphData | undefined {
  return useMemo(() => {
    if (!ontology) return undefined

    const { nodes, edges, exercisesByGroup, exerciseModality } = buildStaticGraph(ontology)

    // Build framework → philosophy lookup
    const frameworkLookup = new Map<string, string | undefined>()
    for (const fw of ontology.frameworks) {
      frameworkLookup.set(fw.id, fw.source_philosophy)
    }

    let maxHeat = 0
    let totalExerciseUsages = 0
    let uniqueExercisesUsed = 0

    if (program) {
      const totalWeeks = program.weeks.length
      const range: [number, number] = weekRange ?? [1, totalWeeks]
      const result = applyHeat(nodes, edges, exercisesByGroup, exerciseModality, program, range, frameworkLookup)
      maxHeat = result.maxHeat
      totalExerciseUsages = result.totalExerciseUsages
      uniqueExercisesUsed = result.uniqueExercisesUsed
    }

    return {
      nodes: Array.from(nodes.values()),
      edges: Array.from(edges.values()),
      exercisesByGroup,
      maxHeat,
      totalExerciseUsages,
      uniqueExercisesUsed,
    }
  }, [ontology, program, weekRange])
}
