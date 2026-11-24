/**
 * The manual session builder's draft (docs/roadmap.md item 24): what a block
 * kind takes, what an exercise becomes when it is dropped, every edit as a
 * pure function, and the search that narrows as the athlete types.
 *
 * The wire shape is the server's (src/manual_builder.py). A draft adds only a
 * `uid` to each block and movement, for React keys and drag ids; `toWire`
 * takes them off. The server words every prescription; nothing here does.
 */
import { differenceInCalendarDays, parseISO } from 'date-fns'
import type { Exercise } from '@/api/types'
import { DAY_NAMES } from '@/lib/workoutMatcher'

export type BlockKind =
  | 'sets' | 'superset' | 'alternate' | 'rounds' | 'amrap' | 'emom'
  | 'for_time' | 'interval' | 'timed' | 'distance' | 'hold' | 'practice'

export type BlockStage = 'prep' | 'main' | 'finisher' | 'cooldown'

export interface ProgressRule {
  add_kg?: number
  add_reps?: number
  top_reps?: number
  add_sec?: number
  add_m?: number
  add_rounds?: number
  every_weeks?: number
}

export interface ManualMovement {
  exercise_id: string
  sets?: number
  reps?: number | string
  rep_scheme?: number[]
  distance_m?: number
  seconds?: number
  hold_sec?: number
  start_kg?: number
  load_text?: string
  rest_sec?: number
  note?: string
  progress?: ProgressRule
}

export interface ManualBlock {
  kind: BlockKind
  stage: BlockStage
  rounds?: number
  minutes?: number
  cap_min?: number
  work_sec?: number
  rest_sec?: number
  rest_until_hr_pct?: number
  intensity?: string
  note?: string
  progress?: ProgressRule
  movements: ManualMovement[]
}

export interface ManualSession {
  id?: string
  name: string
  modality: string
  notes?: string
  minutes?: number
  blocks: ManualBlock[]
}

export interface DraftMovement extends ManualMovement { uid: string }
export interface DraftBlock extends Omit<ManualBlock, 'movements'> { uid: string; movements: DraftMovement[] }
export interface DraftSession extends Omit<ManualSession, 'blocks'> { blocks: DraftBlock[] }

export type BlockField = 'rounds' | 'minutes' | 'cap_min' | 'work_sec' | 'rest_sec' | 'rest_until_hr_pct'
export type MovementField = 'sets' | 'reps' | 'count' | 'distance_m' | 'hold_sec' | 'start_kg' | 'load_text' | 'rest_sec'
export type ProgressField = keyof ProgressRule

interface KindSpec {
  label: string
  /** What it is, for the Add block menu. */
  hint: string
  /** Its movements after the first belong to the first (an AMRAP's, a round's). */
  piece: boolean
  /** The most movements it takes (undefined: as many as a block may). */
  max?: number
  block: BlockField[]
  movement: MovementField[]
  /** Which intensities it offers: zones, load words, or none. */
  intensity: 'zone' | 'load' | 'both' | null
  /** The steps a movement (or, for a piece, the block) may take each week. */
  progress: ProgressField[]
  blockProgress?: ProgressField[]
}

export const BLOCK_KINDS: Record<BlockKind, KindSpec> = {
  sets: { label: 'Sets × reps', hint: 'One exercise, straight sets', piece: false, max: 1, block: [],
    movement: ['sets', 'reps', 'start_kg', 'load_text', 'rest_sec'], intensity: 'load', progress: ['add_kg', 'add_reps', 'top_reps'] },
  superset: { label: 'Superset', hint: 'Two or more exercises back to back', piece: false, block: ['rounds', 'rest_sec'],
    movement: ['reps', 'start_kg', 'load_text'], intensity: 'load', progress: ['add_kg', 'add_reps', 'top_reps'] },
  alternate: { label: 'Alternating sets', hint: 'A set of one, rest, a set of the other', piece: false, block: ['rounds', 'rest_sec'],
    movement: ['reps', 'start_kg', 'load_text'], intensity: 'load', progress: ['add_kg', 'add_reps', 'top_reps'] },
  rounds: { label: 'Rounds', hint: 'A circuit, with a rest between rounds', piece: true, block: ['rounds', 'rest_sec'],
    movement: ['count', 'start_kg', 'load_text'], intensity: 'both', progress: [], blockProgress: ['add_rounds'] },
  amrap: { label: 'AMRAP', hint: 'As many rounds as possible in a time', piece: true, block: ['minutes'],
    movement: ['count', 'start_kg', 'load_text'], intensity: 'both', progress: [] },
  emom: { label: 'EMOM', hint: 'Every minute on the minute', piece: true, block: ['minutes'],
    movement: ['count', 'start_kg', 'load_text'], intensity: 'both', progress: [] },
  for_time: { label: 'For time', hint: 'Rounds against the clock', piece: true, block: ['rounds', 'cap_min'],
    movement: ['count', 'start_kg', 'load_text'], intensity: 'both', progress: [], blockProgress: ['add_rounds'] },
  interval: { label: 'Intervals', hint: 'Work and rest, repeated', piece: true, block: ['rounds', 'work_sec', 'rest_sec', 'rest_until_hr_pct'],
    movement: ['start_kg', 'load_text'], intensity: 'zone', progress: [], blockProgress: ['add_rounds', 'add_sec'] },
  timed: { label: 'Timed / zone', hint: 'Minutes at a heart-rate zone', piece: false, max: 1, block: ['minutes'],
    movement: [], intensity: 'zone', progress: ['add_sec'] },
  distance: { label: 'Distance', hint: 'Metres, once or in repeats', piece: false, max: 1, block: ['rest_sec'],
    movement: ['distance_m', 'sets'], intensity: 'zone', progress: ['add_m'] },
  hold: { label: 'Hold', hint: 'Seconds held, in sets', piece: false, max: 1, block: ['rest_sec'],
    movement: ['sets', 'hold_sec'], intensity: null, progress: ['add_sec'] },
  practice: { label: 'Practice', hint: 'Minutes of a skill or mobility work', piece: false, max: 1, block: ['minutes'],
    movement: [], intensity: null, progress: [] },
}

export const KIND_ORDER = Object.keys(BLOCK_KINDS) as BlockKind[]

export const STAGES: { id: BlockStage; label: string }[] = [
  { id: 'prep', label: 'Start' },
  { id: 'main', label: 'Main work' },
  { id: 'finisher', label: 'Finisher' },
  { id: 'cooldown', label: 'Cool-down' },
]
const STAGE_RANK: Record<BlockStage, number> = { prep: 0, main: 1, finisher: 2, cooldown: 3 }

export const ZONE_INTENSITIES = ['zone1', 'zone2', 'zone3', 'zone4', 'zone5'] as const
export const LOAD_INTENSITIES = ['light', 'moderate', 'heavy', 'max_effort'] as const
export const INTENSITY_LABELS: Record<string, string> = {
  zone1: 'Zone 1', zone2: 'Zone 2', zone3: 'Zone 3', zone4: 'Zone 4', zone5: 'Zone 5',
  light: 'Light', moderate: 'Moderate', heavy: 'Heavy', max_effort: 'Max effort',
}

export const FIELD_LABELS: Record<BlockField | MovementField | ProgressField, string> = {
  rounds: 'Rounds', minutes: 'Minutes', cap_min: 'Time cap (min)', work_sec: 'Work (s)', rest_sec: 'Rest (s)',
  rest_until_hr_pct: 'Rest until HR under (% of max)', sets: 'Sets', reps: 'Reps', count: 'Each round',
  distance_m: 'Metres', hold_sec: 'Hold (s)', start_kg: 'Start (kg)', load_text: 'Load, in words',
  add_kg: '+ kg', add_reps: '+ reps', top_reps: 'up to reps', add_sec: '+ seconds', add_m: '+ metres',
  add_rounds: '+ rounds', every_weeks: 'every weeks',
}

let counter = 0
/** A key no other block or movement of the draft has. */
export function uid(): string {
  counter += 1
  return `${Date.now().toString(36)}-${counter}`
}

export const emptyDraft = (): DraftSession => ({ name: '', modality: '', blocks: [] })

// ─── What an exercise becomes ────────────────────────────────────────────────

const ZONE_CATEGORIES = new Set(['aerobic'])
const PRACTICE_CATEGORIES = new Set(['mobility', 'skill', 'rehab'])

/** The block kind an exercise is usually done as. */
export function kindFor(exercise: Exercise): BlockKind {
  const volume = exercise.typical_volume ?? {}
  const patterns = exercise.movement_patterns ?? []
  if (volume.distance_m && !volume.reps) return 'distance'
  if (ZONE_CATEGORIES.has(exercise.category)) return 'timed'
  if (patterns.includes('isometric') || (volume.duration_sec && !volume.reps && volume.duration_sec <= 120)) return 'hold'
  if (PRACTICE_CATEGORIES.has(exercise.category)) return 'practice'
  return 'sets'
}

function movementFor(exercise: Exercise, kind: BlockKind): DraftMovement {
  const volume = exercise.typical_volume ?? {}
  const m: DraftMovement = { uid: uid(), exercise_id: exercise.id }
  const start = exercise.starting_load_kg?.intermediate
  if (kind === 'sets') return { ...m, sets: volume.sets ?? 3, reps: volume.reps ?? 8, rest_sec: 90, ...(start ? { start_kg: start } : {}) }
  if (kind === 'superset' || kind === 'alternate') return { ...m, reps: volume.reps ?? 10, ...(start ? { start_kg: start } : {}) }
  if (kind === 'hold') return { ...m, sets: volume.sets ?? 3, hold_sec: volume.duration_sec ?? 30 }
  if (kind === 'distance') return { ...m, distance_m: volume.distance_m ?? 400 }
  if (BLOCK_KINDS[kind].piece && kind !== 'interval') {
    return volume.distance_m && !volume.reps ? { ...m, distance_m: volume.distance_m } : { ...m, reps: volume.reps ?? 10 }
  }
  return m
}

function blockOf(kind: BlockKind, stage: BlockStage, movements: DraftMovement[], exercise?: Exercise): DraftBlock {
  const base: DraftBlock = { uid: uid(), kind, stage, movements }
  const minutes = exercise?.typical_volume?.duration_sec ? Math.max(1, Math.round(exercise.typical_volume.duration_sec / 60)) : undefined
  switch (kind) {
    case 'superset': case 'alternate': return { ...base, rounds: 3, rest_sec: 90 }
    case 'rounds': return { ...base, rounds: 3, rest_sec: 60 }
    case 'amrap': return { ...base, minutes: 12 }
    case 'emom': return { ...base, minutes: 10 }
    case 'for_time': return { ...base, rounds: 3 }
    case 'interval': return { ...base, rounds: 6, work_sec: 30, rest_sec: 60 }
    case 'timed': return { ...base, minutes: minutes && minutes >= 5 ? minutes : 30, intensity: 'zone2' }
    case 'practice': return { ...base, minutes: 5 }
    case 'hold': return { ...base, rest_sec: 30 }
    default: return base
  }
}

/** A new block for one exercise, of the kind it is usually done as (or `kind`). */
export function blockFor(exercise: Exercise, stage: BlockStage, kind: BlockKind = kindFor(exercise)): DraftBlock {
  return blockOf(kind, stage, [movementFor(exercise, kind)], exercise)
}

/** An empty block of a kind, to be filled from its own search field. */
export const emptyBlock = (kind: BlockKind, stage: BlockStage): DraftBlock => blockOf(kind, stage, [])

// ─── Edits ───────────────────────────────────────────────────────────────────

/** Blocks in stage order, each stage's in the order they were. */
function staged(blocks: DraftBlock[]): DraftBlock[] {
  return blocks.map((b, i) => ({ b, i })).sort((x, y) => STAGE_RANK[x.b.stage] - STAGE_RANK[y.b.stage] || x.i - y.i).map((x) => x.b)
}

const withBlocks = (draft: DraftSession, blocks: DraftBlock[]): DraftSession => ({ ...draft, blocks: staged(blocks) })

export const blocksOfStage = (draft: DraftSession, stage: BlockStage): DraftBlock[] => draft.blocks.filter((b) => b.stage === stage)

/** Put a block at position `at` of a stage (its end by default). */
export function insertBlock(draft: DraftSession, block: DraftBlock, stage: BlockStage, at?: number): DraftSession {
  const others = draft.blocks.filter((b) => b.uid !== block.uid)
  const inStage = others.filter((b) => b.stage === stage)
  const k = Math.max(0, Math.min(at ?? inStage.length, inStage.length))
  const placed = [...inStage.slice(0, k), { ...block, stage }, ...inStage.slice(k)]
  return withBlocks(draft, [...others.filter((b) => b.stage !== stage), ...placed])
}

/** Move a block to position `at` of a stage; `at` counts the stage without it. */
export function moveBlock(draft: DraftSession, blockUid: string, stage: BlockStage, at?: number): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  return block ? insertBlock(draft, block, stage, at) : draft
}

/** One place earlier or later, crossing into the neighbouring stage at an edge. */
export function nudgeBlock(draft: DraftSession, blockUid: string, by: -1 | 1): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  if (!block) return draft
  const inStage = blocksOfStage(draft, block.stage)
  const at = inStage.findIndex((b) => b.uid === blockUid)
  const to = at + by
  if (to >= 0 && to < inStage.length) return moveBlock(draft, blockUid, block.stage, to)
  const next = STAGES[STAGE_RANK[block.stage] + by]
  if (!next) return draft
  return moveBlock(draft, blockUid, next.id, by === 1 ? 0 : undefined)
}

export const removeBlock = (draft: DraftSession, blockUid: string): DraftSession =>
  withBlocks(draft, draft.blocks.filter((b) => b.uid !== blockUid))

export function updateBlock(draft: DraftSession, blockUid: string, patch: Partial<DraftBlock>): DraftSession {
  return withBlocks(draft, draft.blocks.map((b) => (b.uid === blockUid ? clean({ ...b, ...patch }) : b)))
}

export function updateMovement(draft: DraftSession, blockUid: string, movementUid: string, patch: Partial<DraftMovement>): DraftSession {
  return withBlocks(draft, draft.blocks.map((b) => b.uid !== blockUid ? b
    : { ...b, movements: b.movements.map((m) => (m.uid === movementUid ? clean({ ...m, ...patch }) : m)) }))
}

/** Undefined, empty and NaN values are not part of a draft. */
function clean<T extends object>(value: T): T {
  const out = { ...value } as Record<string, unknown>
  for (const [k, v] of Object.entries(out)) {
    if (v === undefined || v === '' || (typeof v === 'number' && Number.isNaN(v))) delete out[k]
    else if (k === 'progress' && v && typeof v === 'object') {
      const rule = clean(v as object)
      if (Object.keys(rule).length) out[k] = rule
      else delete out[k]
    }
  }
  return out as T
}

/**
 * An exercise dropped on a block. A piece, a superset and an empty block take
 * it; straight sets become a superset with it; a block that takes one exercise
 * gets a new block after it.
 */
export function addExercise(draft: DraftSession, blockUid: string, exercise: Exercise): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  if (!block) return draft
  const spec = BLOCK_KINDS[block.kind]
  if (block.movements.length === 0) {
    return updateBlock(draft, blockUid, { movements: [movementFor(exercise, block.kind)] })
  }
  if (block.kind === 'sets') {
    const first = block.movements[0]
    const { sets, rest_sec, ...kept } = first
    return updateBlock(draft, blockUid, {
      kind: 'superset', rounds: sets ?? 3, rest_sec: rest_sec ?? 90,
      movements: [kept as DraftMovement, movementFor(exercise, 'superset')],
    })
  }
  if (spec.max === 1) {
    const inStage = blocksOfStage(draft, block.stage)
    return insertBlock(draft, blockFor(exercise, block.stage), block.stage, inStage.findIndex((b) => b.uid === blockUid) + 1)
  }
  return updateBlock(draft, blockUid, { movements: [...block.movements, movementFor(exercise, block.kind)] })
}

export function removeMovement(draft: DraftSession, blockUid: string, movementUid: string): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  if (!block) return draft
  return updateBlock(draft, blockUid, { movements: block.movements.filter((m) => m.uid !== movementUid) })
}

export function nudgeMovement(draft: DraftSession, blockUid: string, movementUid: string, by: -1 | 1): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  if (!block) return draft
  const at = block.movements.findIndex((m) => m.uid === movementUid)
  const to = at + by
  if (at < 0 || to < 0 || to >= block.movements.length) return draft
  const movements = [...block.movements]
  ;[movements[at], movements[to]] = [movements[to], movements[at]]
  return updateBlock(draft, blockUid, { movements })
}

/**
 * Another kind for a block, its exercises kept: each movement is read again
 * for the new kind, and where the new kind takes one exercise the others
 * become blocks of their own after it.
 */
export function setKind(draft: DraftSession, blockUid: string, kind: BlockKind, exercises: Record<string, Exercise>): DraftSession {
  const block = draft.blocks.find((b) => b.uid === blockUid)
  if (!block || block.kind === kind) return draft
  const rebuilt = block.movements.map((m) => {
    const ex = exercises[m.exercise_id]
    const fresh = ex ? movementFor(ex, kind) : ({ uid: uid(), exercise_id: m.exercise_id } as DraftMovement)
    const carried: Partial<DraftMovement> = { uid: m.uid }
    if (m.start_kg !== undefined) carried.start_kg = m.start_kg
    if (m.load_text) carried.load_text = m.load_text
    if (m.note) carried.note = m.note
    if (typeof m.reps === 'number' && 'reps' in fresh) carried.reps = m.reps
    return { ...fresh, ...carried }
  })
  const spec = BLOCK_KINDS[kind]
  const shell = blockOf(kind, block.stage, [])
  const first: DraftBlock = { ...shell, uid: block.uid, note: block.note, movements: spec.max === 1 ? rebuilt.slice(0, 1) : rebuilt }
  if (block.rounds && spec.block.includes('rounds')) first.rounds = block.rounds
  if (block.minutes && spec.block.includes('minutes')) first.minutes = block.minutes
  const rest = spec.max === 1 ? rebuilt.slice(1).map((m) => ({ ...blockOf(kind, block.stage, [m]) })) : []
  const blocks = draft.blocks.flatMap((b) => (b.uid === blockUid ? [clean(first), ...rest] : [b]))
  return withBlocks(draft, blocks)
}

// ─── A count as the athlete types it ─────────────────────────────────────────

/** "10", "21-15-9", "400 m" or "30 s" → the movement's count. */
export function parseCount(text: string): Pick<ManualMovement, 'reps' | 'rep_scheme' | 'distance_m' | 'seconds'> {
  const t = text.trim().toLowerCase()
  if (!t) return {}
  const metres = t.match(/^(\d+(?:\.\d+)?)\s*(m|km)$/)
  if (metres) return { distance_m: Math.round(Number(metres[1]) * (metres[2] === 'km' ? 1000 : 1)) }
  const seconds = t.match(/^(\d+)\s*(s|sec|min)$/)
  if (seconds) return { seconds: Number(seconds[1]) * (seconds[2] === 'min' ? 60 : 1) }
  if (/^\d+$/.test(t)) return { reps: Number(t) }
  const scheme = t.split(/[^0-9]+/).filter(Boolean).map(Number)
  if (scheme.length >= 2 && /^[\d\s,\-–/]+$/.test(t)) return { rep_scheme: scheme }
  return { reps: text.trim() }
}

export function countText(m: ManualMovement): string {
  if (m.rep_scheme?.length) return m.rep_scheme.join('-')
  if (m.distance_m) return `${m.distance_m} m`
  if (m.seconds) return `${m.seconds} s`
  return m.reps === undefined ? '' : String(m.reps)
}

/** A movement with its count replaced by what was typed. */
export function withCount<T extends ManualMovement>(m: T, text: string): T {
  const { reps: _r, rep_scheme: _s, distance_m: _d, seconds: _t, ...rest } = m
  return { ...(rest as T), ...parseCount(text) }
}

// ─── To and from the server ──────────────────────────────────────────────────

export function toWire(draft: DraftSession): ManualSession {
  return {
    ...(draft.id ? { id: draft.id } : {}),
    name: draft.name.trim(), modality: draft.modality,
    ...(draft.notes?.trim() ? { notes: draft.notes.trim() } : {}),
    blocks: draft.blocks.map(({ uid: _b, movements, ...block }) => ({
      ...block, movements: movements.map(({ uid: _m, ...movement }) => movement),
    })),
  }
}

export function fromWire(session: ManualSession): DraftSession {
  return {
    id: session.id, name: session.name ?? '', modality: session.modality ?? '', notes: session.notes,
    blocks: staged((session.blocks ?? []).map((b) => ({
      ...b, stage: b.stage ?? 'main', uid: uid(), movements: (b.movements ?? []).map((m) => ({ ...m, uid: uid() })),
    }))),
  }
}

/** A copy to save as another session. */
export const duplicateOf = (session: ManualSession): DraftSession => {
  const copy = fromWire(session)
  return { ...copy, id: undefined, name: `${session.name} copy` }
}

export interface BuilderProblem { block: number | null; movement: number | null; field: string | null; message: string }

/** The problems of the block at `index` of the wire order (the draft's). */
export const problemsAt = (problems: BuilderProblem[], index: number): BuilderProblem[] => problems.filter((p) => p.block === index)
export const sessionProblems = (problems: BuilderProblem[]): BuilderProblem[] => problems.filter((p) => p.block === null)

/** What the athlete has still to do before the server is asked at all. */
export function isBlank(draft: DraftSession): boolean {
  return draft.blocks.every((b) => b.movements.length === 0)
}

// ─── Search ──────────────────────────────────────────────────────────────────

const words = (text: string) => text.toLowerCase().split(/[^a-z0-9]+/).filter(Boolean)

/**
 * How well an exercise answers what was typed: every word must be found, in
 * the name first (its start, a word's start, anywhere), then in its movement
 * patterns, category or equipment. 0 is no match.
 */
export function searchScore(exercise: Exercise, query: string): number {
  const asked = words(query)
  if (!asked.length) return 1
  const name = exercise.name.toLowerCase()
  const nameWords = words(exercise.name)
  const other = [...(exercise.movement_patterns ?? []), exercise.category, ...(exercise.equipment ?? []), exercise.id].flatMap(words)
  let score = 0
  for (const w of asked) {
    if (nameWords[0]?.startsWith(w)) score += 8
    else if (nameWords.some((n) => n.startsWith(w))) score += 6
    else if (name.includes(w)) score += 4
    else if (other.some((o) => o.startsWith(w))) score += 2
    else return 0
  }
  if (name.startsWith(query.trim().toLowerCase())) score += 4
  return score
}

export interface LibraryFilter { query: string; categories: string[]; equipment?: string[] | null }

/** The exercises that answer the filter, the best first, then by name. */
export function searchExercises(exercises: Exercise[], filter: LibraryFilter, limit = 60): Exercise[] {
  const owned = filter.equipment ? new Set([...filter.equipment, 'open_space', 'none']) : null
  return exercises
    .filter((e) => !filter.categories.length || filter.categories.includes(e.category))
    .filter((e) => !owned || (e.equipment ?? []).every((q) => owned.has(q)))
    .map((e) => ({ e, score: searchScore(e, filter.query) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score || a.e.name.localeCompare(b.e.name))
    .slice(0, limit)
    .map((x) => x.e)
}

/** The modality a session of these exercises most likely is: the one most of them list first. */
export function suggestModality(draft: DraftSession, exercises: Record<string, Exercise>): string | null {
  const votes = new Map<string, number>()
  for (const b of draft.blocks.filter((x) => x.stage === 'main' || draft.blocks.every((y) => y.stage !== 'main'))) {
    for (const m of b.movements) {
      const first = exercises[m.exercise_id]?.modality?.[0]
      if (first) votes.set(first, (votes.get(first) ?? 0) + 1)
    }
  }
  return [...votes.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null
}

// ─── Onto a day ──────────────────────────────────────────────────────────────

/** Where a date falls in the program: its week and day, or why it cannot take a session. */
export function programSlot(startDate: string | null, weeks: number, date: string, today: string):
  { weekIndex: number; day: string } | { reason: string } {
  if (!startDate || weeks === 0) return { reason: 'Start a program first: a session is added to one of its days.' }
  if (date < today) return { reason: 'Pick today or a later day.' }
  const days = differenceInCalendarDays(parseISO(date), parseISO(startDate))
  if (days < 0) return { reason: 'Your program has not started by then.' }
  const weekIndex = Math.floor(days / 7)
  if (weekIndex >= weeks) return { reason: 'Your program ends before then.' }
  return { weekIndex, day: DAY_NAMES[days % 7] }
}

