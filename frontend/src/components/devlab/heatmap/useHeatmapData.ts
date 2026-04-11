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
  /** Package this node belongs to (set on archetype nodes) */
  _package?: string
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
  movement_patterns: string[]
  _package?: string
}

export interface HeatmapGraphData {
  nodes: HeatNode[]
  edges: HeatEdge[]
  /** Individual exercises within each slot-pattern group */
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

// ─── Pattern matching — mirrors selector.py _PATTERN_ALIASES ─────────────────
//
// Each archetype slot has an exercise_filter.movement_pattern that determines
// which exercises can fill it. This table is the exact same alias map as
// selector.py so the heatmap reflects what the engine actually does.

const PATTERN_ALIASES: Record<string, { mode: 'or' | 'and' | 'category'; patterns: string[] }> = {
  squat:           { mode: 'or',      patterns: ['squat'] },
  hinge:           { mode: 'or',      patterns: ['hip_hinge'] },
  hip_hinge:       { mode: 'or',      patterns: ['hip_hinge'] },
  carry:           { mode: 'or',      patterns: ['loaded_carry'] },
  loaded_carry:    { mode: 'or',      patterns: ['loaded_carry'] },
  rotation:        { mode: 'or',      patterns: ['rotation'] },
  locomotion:      { mode: 'or',      patterns: ['locomotion'] },
  ballistic:       { mode: 'or',      patterns: ['ballistic'] },
  olympic:         { mode: 'or',      patterns: ['olympic_lift'] },
  olympic_lift:    { mode: 'or',      patterns: ['olympic_lift'] },
  isometric:       { mode: 'or',      patterns: ['isometric'] },
  horizontal_push: { mode: 'or',      patterns: ['horizontal_push'] },
  vertical_push:   { mode: 'or',      patterns: ['vertical_push'] },
  horizontal_pull: { mode: 'or',      patterns: ['horizontal_pull'] },
  vertical_pull:   { mode: 'or',      patterns: ['vertical_pull'] },
  press:           { mode: 'or',      patterns: ['horizontal_push', 'vertical_push'] },
  push:            { mode: 'or',      patterns: ['horizontal_push', 'vertical_push'] },
  pull:            { mode: 'or',      patterns: ['horizontal_pull', 'vertical_pull'] },
  aerobic:         { mode: 'or',      patterns: ['aerobic_monostructural', 'locomotion'] },
  swing:           { mode: 'and',     patterns: ['hip_hinge', 'ballistic'] },
  clean:           { mode: 'and',     patterns: ['hip_hinge', 'olympic_lift'] },
  jerk:            { mode: 'and',     patterns: ['vertical_push', 'ballistic'] },
  snatch:          { mode: 'and',     patterns: ['hip_hinge', 'ballistic', 'olympic_lift'] },
  tgu:             { mode: 'and',     patterns: ['isometric', 'vertical_push'] },
  ruck:            { mode: 'and',     patterns: ['locomotion', 'loaded_carry'] },
  skill:           { mode: 'category', patterns: ['skill'] },
  farmer_carry:    { mode: 'or',      patterns: ['farmer_carry'] },
  rack_carry:      { mode: 'or',      patterns: ['rack_carry'] },
  step_up:         { mode: 'or',      patterns: ['step_up'] },
}

function exerciseMatchesPattern(
  exMovementPatterns: string[],
  exCategory: string,
  slotPattern: string,
): boolean {
  const alias = PATTERN_ALIASES[slotPattern]
  if (!alias) return exMovementPatterns.includes(slotPattern)
  const { mode, patterns } = alias
  if (mode === 'or')       return patterns.some(p => exMovementPatterns.includes(p))
  if (mode === 'and')      return patterns.every(p => exMovementPatterns.includes(p))
  if (mode === 'category') return patterns.includes(exCategory)
  return false
}

// Turn a pattern key (possibly "cat:skill") into a display label
function patternLabel(patternKey: string): string {
  return patternKey.replace('cat:', '').replace(/_/g, ' ')
}

// Stable group ID from a pattern key
function groupId(patternKey: string): string {
  return `slotpat_${patternKey.replace(':', '_')}`
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
      _package: arch._package,
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

  // Layer 4: Exercise groups — one per unique slot movement_pattern (or category fallback).
  //
  // This replaces the old "one group per modality" scheme. Now each node represents
  // the actual exercise pool that a slot filter can draw from — matching what
  // selector.py does when it resolves exercise_filter.movement_pattern through
  // _PATTERN_ALIASES. Each archetype only connects to the slot patterns its slots
  // actually declare, not every exercise in its modality.

  // Collect every unique slot pattern declared across all archetypes
  const slotPatternKeys = new Map<string, string>()   // patternKey → display label
  const patternToModalities = new Map<string, Set<ModalityId>>()  // for color hinting

  for (const arch of ontology.archetypes) {
    for (const slot of arch.slots ?? []) {
      if (slot.skip_exercise) continue
      const ef = slot.exercise_filter
      if (!ef) continue
      const mp = ef.movement_pattern
      const cat = ef.category
      const key = mp ?? (cat ? `cat:${cat}` : null)
      if (!key) continue
      if (!slotPatternKeys.has(key)) {
        slotPatternKeys.set(key, patternLabel(key))
      }
      if (!patternToModalities.has(key)) patternToModalities.set(key, new Set())
      if (arch.modality) patternToModalities.get(key)!.add(arch.modality as ModalityId)
    }
  }

  // Create exercise_group nodes
  const exercisesByGroup: Record<string, ExerciseInGroup[]> = {}
  for (const [patternKey, label] of slotPatternKeys) {
    const gId = groupId(patternKey)
    // Use the most common modality hint for coloring
    const mods = patternToModalities.get(patternKey)
    const modHint = mods && mods.size === 1 ? [...mods][0] : undefined
    nodes.set(nodeId('exercise_group', gId), {
      id: nodeId('exercise_group', gId),
      label,
      layer: 'exercise_group',
      modalityHint: modHint,
      heat: 0,
      rawCount: 0,
    })
    exercisesByGroup[gId] = []
  }

  // Create archetype → exercise_group edges (one per unique slot pattern per archetype)
  for (const arch of ontology.archetypes) {
    const seenPatterns = new Set<string>()
    for (const slot of arch.slots ?? []) {
      if (slot.skip_exercise) continue
      const ef = slot.exercise_filter
      if (!ef) continue
      const mp = ef.movement_pattern
      const cat = ef.category
      const key = mp ?? (cat ? `cat:${cat}` : null)
      if (!key || seenPatterns.has(key) || !slotPatternKeys.has(key)) continue
      seenPatterns.add(key)

      const gId = groupId(key)
      const eid = edgeId('archetype', arch.id, 'exercise_group', gId)
      edges.set(eid, {
        id: eid,
        source: nodeId('archetype', arch.id),
        target: nodeId('exercise_group', gId),
        sourceLayer: 'archetype',
        targetLayer: 'exercise_group',
        modalityHint: arch.modality as ModalityId | undefined,
        heat: 0,
        rawCount: 0,
      })
    }
  }

  // Map each exercise to the groups whose slot pattern it satisfies.
  // This is the same filter logic as selector.py _matches_slot_filter.
  const exerciseToGroups = new Map<string, string[]>()

  for (const ex of ontology.exercises) {
    const exPatterns = (ex.movement_patterns ?? []) as string[]
    const exCategory = (ex.category ?? '') as string
    const groups: string[] = []

    for (const [patternKey] of slotPatternKeys) {
      const gId = groupId(patternKey)
      const isCategory = patternKey.startsWith('cat:')
      const matches = isCategory
        ? exCategory === patternKey.replace('cat:', '')
        : exerciseMatchesPattern(exPatterns, exCategory, patternKey)

      if (matches) {
        exercisesByGroup[gId].push({ id: ex.id, name: ex.name, heat: 0, rawCount: 0, movement_patterns: exPatterns, _package: (ex as any)._package })
        groups.push(gId)
      }
    }

    exerciseToGroups.set(ex.id, groups)
  }

  // Suffix group labels with exercise count
  for (const [patternKey] of slotPatternKeys) {
    const gId = groupId(patternKey)
    const node = nodes.get(nodeId('exercise_group', gId))
    if (node) {
      const count = exercisesByGroup[gId]?.length ?? 0
      node.label = `${patternLabel(patternKey)} (${count})`
    }
  }

  return { nodes, edges, exercisesByGroup, exerciseToGroups }
}

// ─── Apply heat from program ─────────────────────────────────────────────────

function applyHeat(
  nodes: Map<string, HeatNode>,
  edges: Map<string, HeatEdge>,
  exercisesByGroup: Record<string, ExerciseInGroup[]>,
  exerciseToGroups: Map<string, string[]>,
  program: TracedProgram,
  weekRange: [number, number],
  frameworkLookup: Map<string, string | undefined>,
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
        const archetypeSlots = session.archetype?.slots ?? []

        for (const assignment of session.exercises ?? []) {
          if (assignment.meta || !assignment.exercise) continue
          const exId = assignment.exercise.id
          totalUsages++
          usedExercises.add(exId)

          // Find the slot that produced this assignment so we can heat the
          // correct pattern group — the same logic selector.py uses.
          const slotRole = assignment.slot_role
          const slot = slotRole
            ? archetypeSlots.find(s => s.role === slotRole)
            : undefined
          const ef = slot?.exercise_filter
          const mp = ef?.movement_pattern
          const cat = ef?.category
          const patternKey = mp ?? (cat ? `cat:${cat}` : null)
          const targetGroupId = patternKey ? groupId(patternKey) : null

          // Heat the exercise_group node and individual exercise
          const groupsToHeat = targetGroupId
            ? [targetGroupId]
            : (exerciseToGroups.get(exId) ?? [])  // fallback if slot info missing

          for (const gId of groupsToHeat) {
            const gNode = nodes.get(nodeId('exercise_group', gId))
            if (gNode) gNode.rawCount++
            const group = exercisesByGroup[gId]
            if (group) {
              const item = group.find(e => e.id === exId)
              if (item) item.rawCount++
            }
          }

          // Heat archetype → exercise_group edge (specific slot pattern)
          if (archetypeId && targetGroupId) {
            const aeEdgeId = edgeId('archetype', archetypeId, 'exercise_group', targetGroupId)
            const aeEdge = edges.get(aeEdgeId)
            if (aeEdge) aeEdge.rawCount++
          }

          // Heat the archetype node
          if (archetypeId) {
            const aNode = nodes.get(nodeId('archetype', archetypeId))
            if (aNode) aNode.rawCount++
          }

          // Heat the modality node and framework→modality edge
          const mNode = nodes.get(nodeId('modality', modality))
          if (mNode) mNode.rawCount++

          if (archetypeId) {
            const maEdgeId = edgeId('modality', modality, 'archetype', archetypeId)
            const maEdge = edges.get(maEdgeId)
            if (maEdge) maEdge.rawCount++
          }

          if (frameworkId) {
            const fNode = nodes.get(nodeId('framework', frameworkId))
            if (fNode) fNode.rawCount++
            const fmEdgeId = edgeId('framework', frameworkId, 'modality', modality)
            const fmEdge = edges.get(fmEdgeId)
            if (fmEdge) fmEdge.rawCount++
          }

          if (philosophyId) {
            const pNode = nodes.get(nodeId('philosophy', philosophyId))
            if (pNode) pNode.rawCount++
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

  // Normalize heat per layer
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

    const { nodes, edges, exercisesByGroup, exerciseToGroups } = buildStaticGraph(ontology)

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
      const result = applyHeat(
        nodes, edges, exercisesByGroup, exerciseToGroups,
        program, range, frameworkLookup,
      )
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
