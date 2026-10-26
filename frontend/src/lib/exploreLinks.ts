// What leads into an Explore entity and what follows from it, from the links
// GET /api/explore/links computes (src/explore_links.py). The levels run
// Philosophy → Framework → Modality → Archetype → Exercise → Movement; an
// exercise also has its own progression (comes before / after, easier). This
// is the one place the edges become what a detail shows.
import type { ExploreLinks } from '@/api/types'
import { movementColor } from '@/lib/movementColors'

export type ExploreTopic =
  | 'philosophies' | 'frameworks' | 'modalities' | 'archetypes' | 'exercises' | 'movements' | 'equipment' | 'standards'

/** The topics that are levels with details; Equipment and Standards are not. */
export type LinkedTopic = Exclude<ExploreTopic, 'standards' | 'equipment'>

export interface LineageItem {
  /** Absent for a plain item that opens nothing (a concept, a filter group). */
  topic?: LinkedTopic
  id: string
  name: string
  note?: string
  /** Its level's colour (lib/exploreColors.ts): the pill's left border. */
  color?: string
}

export interface LineageGroup {
  label: string
  items: LineageItem[]
}

export interface Lineage {
  up: LineageGroup[]
  down: LineageGroup[]
}

export interface ExerciseProgression {
  before: LineageItem[]
  after: LineageItem[]
  easier: LineageItem[]
}

/** Display names by level; a missing id falls back to a prettified one. */
export interface LineageNames {
  philosophies: Record<string, string>
  frameworks: Record<string, string>
  modalities: Record<string, string>
  archetypes: Record<string, string>
  exercises: Record<string, string>
}

/** Each level's colours by id, stamped onto the items (`color`). */
export type LineageColors = Partial<Record<LinkedTopic, Record<string, string>>>

function paint(items: LineageItem[], colors?: LineageColors): LineageItem[] {
  if (!colors) return items
  return items.map((i) => {
    const color = i.topic ? colors[i.topic]?.[i.id] : undefined
    return color ? { ...i, color } : i
  })
}

type L = ExploreLinks['links']

export interface LinkIndex {
  doc: ExploreLinks
  movementNames: Record<string, string>
  fwOwner: Record<string, string>
  archPackage: Record<string, string>
  archModality: Record<string, string>
  exercisePackages: Record<string, string>
}

export function prettify(id: string) {
  const s = id.replace(/_/g, ' ')
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function by<T>(rows: T[], key: (r: T) => string): Map<string, T[]> {
  const m = new Map<string, T[]>()
  for (const r of rows) {
    const k = key(r)
    const list = m.get(k)
    if (list) list.push(r); else m.set(k, [r])
  }
  return m
}

/** `exercisePackage`: each exercise's first declaring package, to group by. */
export function indexLinks(doc: ExploreLinks, exercisePackage: Record<string, string> = {}): LinkIndex {
  const fwOwner: Record<string, string> = {}
  for (const e of doc.links.philosophyFramework) if (e.owner) fwOwner[e.framework] = e.philosophy
  const archPackage: Record<string, string> = {}
  const archModality: Record<string, string> = {}
  for (const e of doc.links.modalityArchetype) {
    archModality[e.archetype] = e.modality
    if (e.package) archPackage[e.archetype] = e.package
  }
  return {
    doc,
    movementNames: Object.fromEntries(doc.movements.map((m) => [m.id, m.name])),
    fwOwner, archPackage, archModality,
    exercisePackages: exercisePackage,
  }
}

function name(map: Record<string, string>, id: string) {
  return map[id] ?? prettify(id)
}

function perWeek(e: L['frameworkModality'][number]) {
  return [e.sessionsPerWeek != null ? `${e.sessionsPerWeek}/wk` : null, e.tier].filter(Boolean).join(' · ') || undefined
}

/** Groups keyed by a package (a philosophy id), labelled by its name, in name order. */
function groupByPhilosophy<T>(rows: T[], pkgOf: (r: T) => string | undefined, item: (r: T) => LineageItem,
                              names: LineageNames, single: string): LineageGroup[] {
  const groups = by(rows, (r) => pkgOf(r) ?? '')
  const out = [...groups.entries()].map(([pkg, list]) => ({
    label: pkg ? name(names.philosophies, pkg) : 'Other',
    items: list.map(item).sort((a, b) => a.name.localeCompare(b.name)),
  })).sort((a, b) => (a.label === 'Other' ? 1 : b.label === 'Other' ? -1 : a.label.localeCompare(b.label)))
  // One philosophy: label the group by what it holds instead.
  if (out.length === 1) out[0] = { ...out[0], label: `${single} · ${out[0].label}` }
  return out
}

export function lineageOf(ix: LinkIndex, topic: LinkedTopic, id: string, names: LineageNames,
                          colors?: LineageColors): Lineage {
  const { up, down } = lineageUncoloured(ix, topic, id, names)
  const each = (groups: LineageGroup[]) => groups.map((g) => ({ ...g, items: paint(g.items, colors) }))
  return { up: each(up), down: each(down) }
}

function lineageUncoloured(ix: LinkIndex, topic: LinkedTopic, id: string, names: LineageNames): Lineage {
  const l = ix.doc.links
  switch (topic) {
    case 'philosophies': {
      // Frameworks by track, in the philosophy's track order and each track's
      // phase order; one the philosophy owns but runs in no phase comes last.
      const edges = l.philosophyFramework.filter((e) => e.philosophy === id)
      const tracks = new Map<string, LineageGroup>()
      const loose: LineageItem[] = []
      const phases = edges.flatMap((e) => e.phases.map((p) => ({ ...p, framework: e.framework })))
        .sort((a, b) => a.trackIndex - b.trackIndex || a.order - b.order)
      for (const p of phases) {
        const g = tracks.get(p.trackId) ?? { label: p.trackName, items: [] }
        tracks.set(p.trackId, g)
        const existing = g.items.find((i) => i.id === p.framework)
        if (existing) existing.note = `${existing.note} · ${p.phaseName}`
        else g.items.push({ topic: 'frameworks', id: p.framework, name: name(names.frameworks, p.framework), note: p.phaseName })
      }
      for (const e of edges) {
        if (e.phases.length === 0) loose.push({ topic: 'frameworks', id: e.framework, name: name(names.frameworks, e.framework) })
      }
      const down = [...tracks.values()]
      if (loose.length) down.push({ label: down.length ? 'Also offers' : 'Frameworks', items: loose })
      return { up: [], down }
    }
    case 'frameworks': {
      const owners = l.philosophyFramework.filter((e) => e.framework === id)
        .sort((a, b) => Number(b.owner) - Number(a.owner))
      const up: LineageGroup[] = owners.length ? [{
        label: owners.length > 1 ? 'Philosophies' : 'Philosophy',
        items: owners.map((e) => ({
          topic: 'philosophies' as const, id: e.philosophy, name: name(names.philosophies, e.philosophy),
          note: e.phases.map((p) => `${p.trackName} › ${p.phaseName}`).join(', ') || undefined,
        })),
      }] : []
      const mods = l.frameworkModality.filter((e) => e.framework === id)
        .sort((a, b) => (b.sessionsPerWeek ?? 0) - (a.sessionsPerWeek ?? 0))
      return {
        up,
        down: mods.length ? [{ label: 'Modalities', items: mods.map((e) => ({
          topic: 'modalities' as const, id: e.modality, name: name(names.modalities, e.modality), note: perWeek(e),
        })) }] : [],
      }
    }
    case 'modalities': {
      const fws = l.frameworkModality.filter((e) => e.modality === id)
      const archs = l.modalityArchetype.filter((e) => e.modality === id)
      return {
        up: groupByPhilosophy(fws, (e) => ix.fwOwner[e.framework], (e) => ({
          topic: 'frameworks', id: e.framework, name: name(names.frameworks, e.framework), note: perWeek(e),
        }), names, 'Frameworks'),
        down: groupByPhilosophy(archs, (e) => e.package ?? undefined, (e) => ({
          topic: 'archetypes', id: e.archetype, name: name(names.archetypes, e.archetype),
        }), names, 'Archetypes'),
      }
    }
    case 'archetypes': {
      const pkg = ix.archPackage[id]
      const mod = ix.archModality[id]
      const up: LineageGroup[] = []
      if (pkg) up.push({ label: 'Philosophy', items: [{ topic: 'philosophies', id: pkg, name: name(names.philosophies, pkg) }] })
      const fws = l.frameworkModality.filter((e) => e.modality === mod && ix.fwOwner[e.framework] === pkg)
      if (fws.length) up.push({ label: fws.length > 1 ? 'Frameworks' : 'Framework', items: fws.map((e) => ({
        topic: 'frameworks' as const, id: e.framework, name: name(names.frameworks, e.framework), note: perWeek(e),
      })) })
      if (mod) up.push({ label: 'Modality', items: [{ topic: 'modalities', id: mod, name: name(names.modalities, mod) }] })
      // Exercises by the slot that takes them, in the slots' order of first appearance.
      const roles = new Map<string, LineageItem[]>()
      for (const e of l.archetypeExercise.filter((e) => e.archetype === id)) {
        for (const role of e.slots.length ? e.slots : ['']) {
          const list = roles.get(role) ?? []
          roles.set(role, list)
          list.push({ topic: 'exercises', id: e.exercise, name: name(names.exercises, e.exercise),
                      note: e.via === 'filter' ? 'by pattern' : undefined })
        }
      }
      return { up, down: [...roles.entries()].map(([role, items]) => ({ label: role ? prettify(role) : 'Exercises', items })) }
    }
    case 'exercises': {
      const uses = l.archetypeExercise.filter((e) => e.exercise === id)
      return {
        up: groupByPhilosophy(uses, (e) => ix.archPackage[e.archetype], (e) => ({
          topic: 'archetypes', id: e.archetype, name: name(names.archetypes, e.archetype),
          note: e.slots.map(prettify).join(', ') || undefined,
        }), names, 'Archetypes'),
        down: (() => {
          const moves = l.exerciseMovement.filter((e) => e.exercise === id)
          return moves.length ? [{ label: 'Movements', items: moves.map((e) => ({
            topic: 'movements' as const, id: e.movement, name: name(ix.movementNames, e.movement),
          })) }] : []
        })(),
      }
    }
    case 'movements': {
      const tagged = l.exerciseMovement.filter((e) => e.movement === id)
      const move = ix.doc.movements.find((m) => m.id === id)
      const down: LineageGroup[] = []
      if (move?.filterGroups.length) {
        down.push({ label: 'Slot filters', items: move.filterGroups.map((g) => ({ id: g, name: prettify(g) })) })
      }
      if (move?.rollup) {
        down.push({ label: 'Counted as', items: [{ id: move.rollup, name: prettify(move.rollup), color: movementColor(move.rollup).hex }] })
      }
      return {
        up: groupByPhilosophy(tagged, (e) => ix.exercisePackages[e.exercise], (e) => ({
          topic: 'exercises', id: e.exercise, name: name(names.exercises, e.exercise),
        }), names, 'Exercises'),
        down,
      }
    }
  }
}

/** An exercise's progression: `requires` and `unlocks` read from both ends,
 *  a prerequisite concept as a plain item, and its easier versions. */
export function progressionOf(ix: LinkIndex, id: string, scalingDown: string[] | undefined,
                              names: LineageNames, colors?: LineageColors): ExerciseProgression {
  const l = ix.doc.links
  const ex = (i: string): LineageItem => ({ topic: 'exercises', id: i, name: name(names.exercises, i) })
  const p = {
    before: [
      ...l.exerciseProgression.filter((e) => e.to === id).map((e) => ex(e.from)),
      ...l.exerciseConcepts.filter((e) => e.exercise === id).map((e) => ({ id: e.concept, name: prettify(e.concept), note: 'concept' })),
    ],
    after: l.exerciseProgression.filter((e) => e.from === id).map((e) => ex(e.to)),
    easier: (scalingDown ?? []).map((s) => (names.exercises[s] ? ex(s) : { id: s, name: prettify(s) })),
  }
  return { before: paint(p.before, colors), after: paint(p.after, colors), easier: paint(p.easier, colors) }
}
