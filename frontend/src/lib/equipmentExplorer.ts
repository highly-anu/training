// Explore ▸ Equipment: what a set of equipment enables, by the generator's
// rule. GET /api/explore/links says what each exercise and archetype needs
// (src/explore_links.py); a set enables one when it covers the list:
//   exercise   — every item of its equipment (open space and 'none' are free)
//   archetype  — every item of its required_equipment (open space is free)
//   modality   — some enabled archetype has it
//   framework  — every modality it schedules has an enabled archetype of its
//                own package (partly, when only some have)
//   movement   — a pattern of an enabled exercise
// The four lists are facets: an item picked in one narrows the others to what
// connects to it, through the archetypes that take each exercise. Picks
// combine with OR within a list and AND across lists, and a list ignores its
// own picks, so a second item can still be added to it.
// With `bodyweight: false` the lists keep only what uses the chosen equipment:
// an exercise that needs some of it, a session that needs some or takes such
// an exercise. A framework's completeness still counts every session, since
// the generator would.
import type { ExploreLinks } from '@/api/types'
import { prettify, type LineageColors, type LineageNames } from '@/lib/exploreLinks'

export const FACETS = ['modalities', 'frameworks', 'movements', 'exercises'] as const
export type Facet = typeof FACETS[number]
export type Picked = Record<Facet, string[]>

export const NOTHING_PICKED: Picked = { modalities: [], frameworks: [], movements: [], exercises: [] }

export interface FacetItem {
  id: string
  name: string
  color?: string
  note?: string
  picked: boolean
  /** A framework only some of whose scheduled modalities are enabled. */
  partial?: boolean
  /** Picked, but the equipment no longer enables it. */
  unavailable?: boolean
  /** Picked, enabled, but ruled out by the picks in the other lists. */
  unmatched?: boolean
}

export type FacetLists = Record<Facet, FacetItem[]>

export interface ExploreOptions {
  /** Count what needs nothing (bodyweight, open space). On by default. */
  bodyweight?: boolean
}

export interface EquipmentIndex {
  vocabulary: string[]
  /** Equipment some exercise or archetype needs — the rest enable nothing. */
  used: Set<string>
  exNeeds: Record<string, string[]>
  archNeeds: Record<string, string[]>
  archModality: Record<string, string>
  archPackage: Record<string, string>
  archExercises: Record<string, string[]>
  exMovements: Record<string, string[]>
  /** Framework → the modalities it schedules, and its owning philosophy. */
  fwModalities: Record<string, string[]>
  fwOwner: Record<string, string>
  movementNames: Record<string, string>
}

const push = (m: Record<string, string[]>, k: string, v: string) => { (m[k] ??= []).push(v) }

export function indexEquipment(doc: ExploreLinks): EquipmentIndex {
  const l = doc.links
  const archModality: Record<string, string> = {}
  const archPackage: Record<string, string> = {}
  for (const e of l.modalityArchetype) {
    archModality[e.archetype] = e.modality
    if (e.package) archPackage[e.archetype] = e.package
  }
  const archExercises: Record<string, string[]> = {}
  for (const e of l.archetypeExercise) push(archExercises, e.archetype, e.exercise)
  const exMovements: Record<string, string[]> = {}
  for (const e of l.exerciseMovement) push(exMovements, e.exercise, e.movement)
  const fwModalities: Record<string, string[]> = {}
  for (const e of l.frameworkModality) push(fwModalities, e.framework, e.modality)
  const fwOwner: Record<string, string> = {}
  for (const e of l.philosophyFramework) if (e.owner) fwOwner[e.framework] = e.philosophy
  const used = new Set<string>([
    ...Object.values(doc.equipment.exercises).flat(),
    ...Object.values(doc.equipment.archetypes).flat(),
  ])
  return {
    vocabulary: doc.equipment.vocabulary.filter((e) => e !== 'open_space'),
    used,
    exNeeds: doc.equipment.exercises,
    archNeeds: doc.equipment.archetypes,
    archModality, archPackage, archExercises, exMovements, fwModalities, fwOwner,
    movementNames: Object.fromEntries(doc.movements.map((m) => [m.id, m.name])),
  }
}

const covers = (have: Set<string>, needs: string[] | undefined) => (needs ?? []).every((n) => have.has(n))

interface Counted { ids: Map<string, number> }

function tally(): Counted { return { ids: new Map() } }
function bump(c: Counted, id: string) { c.ids.set(id, (c.ids.get(id) ?? 0) + 1) }

/** The ids each facet would list, with how many things connect to each. */
function compute(ix: EquipmentIndex, equipment: Set<string>, picked: Picked, { bodyweight = true }: ExploreOptions = {}) {
  const P = Object.fromEntries(FACETS.map((f) => [f, new Set(picked[f])])) as Record<Facet, Set<string>>
  const needsSome = (needs: string[] | undefined) => bodyweight || (needs ?? []).length > 0
  const exercises = Object.keys(ix.exNeeds)
    .filter((x) => covers(equipment, ix.exNeeds[x]) && needsSome(ix.exNeeds[x]))
  const exOn = new Set(exercises)
  const archs = Object.keys(ix.archNeeds).filter((a) => covers(equipment, ix.archNeeds[a]) && ix.archModality[a])

  // Each enabled archetype: its modality, the frameworks of its package that
  // schedule it, and the enabled exercises its slots take.
  const allHub = archs.map((a) => {
    const m = ix.archModality[a]
    const pkg = ix.archPackage[a]
    return {
      id: a, m,
      fws: Object.keys(ix.fwModalities).filter((f) => ix.fwOwner[f] === pkg && ix.fwModalities[f].includes(m)),
      xs: (ix.archExercises[a] ?? []).filter((x) => exOn.has(x)),
    }
  })
  const hub = bodyweight ? allHub : allHub.filter((h) => needsSome(ix.archNeeds[h.id]) || h.xs.length > 0)

  const mOk = (h: typeof hub[number]) => P.modalities.size === 0 || P.modalities.has(h.m)
  const fOk = (h: typeof hub[number]) => P.frameworks.size === 0 || h.fws.some((f) => P.frameworks.has(f))
  const vOk = (x: string) => P.movements.size === 0 || (ix.exMovements[x] ?? []).some((v) => P.movements.has(v))
  const xOk = (x: string) => P.exercises.size === 0 || P.exercises.has(x)
  const throughMF = P.modalities.size > 0 || P.frameworks.size > 0
  // The exercises a modality or framework pick still allows (null: no such pick).
  const allowedByMF = throughMF
    ? new Set(hub.filter((h) => mOk(h) && fOk(h)).flatMap((h) => h.xs))
    : null

  const modalities = tally()
  const frameworks = tally()
  for (const h of hub) {
    const exerciseFits = (P.movements.size === 0 && P.exercises.size === 0) || h.xs.some((x) => vOk(x) && xOk(x))
    if (!exerciseFits) continue
    if (fOk(h)) bump(modalities, h.m)
    if (mOk(h)) for (const f of h.fws) bump(frameworks, f)
  }
  const movements = tally()
  const exerciseList = tally()
  for (const x of exercises) {
    if (allowedByMF && !allowedByMF.has(x)) continue
    if (xOk(x)) for (const v of ix.exMovements[x] ?? []) bump(movements, v)
    if (vOk(x)) bump(exerciseList, x)
  }

  // A framework is whole when each modality it schedules has an enabled
  // archetype of its own package, whatever is picked or left out.
  const covered = new Map<string, Set<string>>()
  for (const h of allHub) for (const f of h.fws) (covered.get(f) ?? covered.set(f, new Set()).get(f)!).add(h.m)

  return { modalities, frameworks, movements, exercises: exerciseList, covered }
}

export function explore(ix: EquipmentIndex, equipment: Set<string>, picked: Picked,
                        names: LineageNames, colors: LineageColors = {}, opts: ExploreOptions = {}): FacetLists {
  const c = compute(ix, equipment, picked, opts)
  const bare = picked === NOTHING_PICKED ? c : compute(ix, equipment, NOTHING_PICKED, opts)
  const nameOf: Record<Facet, (id: string) => string> = {
    modalities: (id) => names.modalities[id] ?? prettify(id),
    frameworks: (id) => names.frameworks[id] ?? prettify(id),
    movements: (id) => ix.movementNames[id] ?? prettify(id),
    exercises: (id) => names.exercises[id] ?? prettify(id),
  }
  const noteOf: Record<Facet, (id: string, n: number) => string | undefined> = {
    modalities: (_id, n) => `${n} session${n === 1 ? '' : 's'}`,
    frameworks: (id) => {
      const all = new Set(ix.fwModalities[id] ?? []).size
      const have = c.covered.get(id)?.size ?? 0
      if (have < all) return `${have} of ${all} modalities`
      return all === 1 ? '1 modality' : `all ${all} modalities`
    },
    movements: (_id, n) => `${n} ex`,
    exercises: () => undefined,
  }
  const out = {} as FacetLists
  for (const f of FACETS) {
    const counts = c[f].ids
    const items: FacetItem[] = [...counts.entries()].map(([id, n]) => {
      const partial = f === 'frameworks'
        && (c.covered.get(id)?.size ?? 0) < new Set(ix.fwModalities[id] ?? []).size
      return {
        id, name: nameOf[f](id), color: colors[f]?.[id], note: noteOf[f](id, n),
        picked: picked[f].includes(id), ...(partial ? { partial } : {}),
      }
    })
    items.sort((a, b) => {
      if (f === 'frameworks' && !!a.partial !== !!b.partial) return a.partial ? 1 : -1
      if (f === 'modalities' || f === 'movements') return (counts.get(b.id)! - counts.get(a.id)!) || a.name.localeCompare(b.name)
      return a.name.localeCompare(b.name)
    })
    // A pick the list no longer holds stays, so it can be unpicked: the
    // equipment no longer enables it, or the other lists' picks rule it out.
    for (const id of picked[f]) {
      if (counts.has(id)) continue
      const why = bare[f].ids.has(id) ? { unmatched: true } : { unavailable: true }
      items.push({ id, name: nameOf[f](id), color: colors[f]?.[id], picked: true, ...why })
    }
    out[f] = items
  }
  return out
}

export interface Unlock {
  total: number
  byFacet: Record<Facet, number>
}

/** For each piece of equipment not yet chosen (and used by something), how
 *  many more items each list would hold with it added. */
export function unlocks(ix: EquipmentIndex, equipment: Set<string>, picked: Picked,
                        opts: ExploreOptions = {}): Record<string, Unlock> {
  const size = (eq: Set<string>) => {
    const c = compute(ix, eq, picked, opts)
    return Object.fromEntries(FACETS.map((f) => [f, c[f].ids.size])) as Record<Facet, number>
  }
  const base = size(equipment)
  const out: Record<string, Unlock> = {}
  for (const e of ix.vocabulary) {
    if (equipment.has(e) || !ix.used.has(e)) continue
    const next = size(new Set([...equipment, e]))
    const byFacet = Object.fromEntries(FACETS.map((f) => [f, next[f] - base[f]])) as Record<Facet, number>
    out[e] = { byFacet, total: FACETS.reduce((s, f) => s + byFacet[f], 0) }
  }
  return out
}
