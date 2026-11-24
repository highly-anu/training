import { describe, expect, it } from 'vitest'
import type { Exercise } from '@/api/types'
import {
  addExercise, blockFor, blocksOfStage, countText, emptyBlock, emptyDraft, fromWire, insertBlock, kindFor, moveBlock,
  nudgeBlock, parseCount, programSlot, removeMovement, searchExercises, searchScore, setKind, suggestModality, toWire,
  updateMovement, withCount, type DraftSession,
} from './sessionBuilder'

const ex = (id: string, name: string, more: Partial<Exercise> = {}): Exercise => ({
  id, name, category: 'barbell', modality: ['max_strength'], equipment: ['barbell'], effort: 'high', bilateral: true,
  movement_patterns: ['squat'], requires: [], unlocks: [], contraindicated_with: [], progressions: {}, sources: [],
  ...more,
} as Exercise)

const squat = ex('back_squat', 'Back Squat', { typical_volume: { sets: 3, reps: 5 }, starting_load_kg: { intermediate: 60 } })
const front = ex('front_squat', 'Front Squat')
const pullUp = ex('pull_up', 'Pull-Up', { category: 'bodyweight', equipment: ['pull_up_bar'], movement_patterns: ['vertical_pull'], modality: ['relative_strength'] })
const row = ex('row_easy', 'Easy Row', { category: 'aerobic', equipment: ['rower'], modality: ['aerobic_base'], movement_patterns: ['cyclical'], typical_volume: { duration_sec: 1800 } })
const run = ex('run_400', '400 m Run', { category: 'aerobic', equipment: [], modality: ['anaerobic_intervals'], movement_patterns: ['locomotion'], typical_volume: { distance_m: 400 } })
const plank = ex('plank', 'Plank', { category: 'bodyweight', equipment: [], movement_patterns: ['isometric'], typical_volume: { duration_sec: 45 } })
const stretch = ex('couch_stretch', 'Couch Stretch', { category: 'mobility', equipment: [], modality: ['mobility'], movement_patterns: ['hip_flexor'] })
const ALL = [squat, front, pullUp, row, run, plank, stretch]
const CATALOG = Object.fromEntries(ALL.map((e) => [e.id, e]))

const withBlock = (exercise: Exercise, draft: DraftSession = emptyDraft()) => insertBlock(draft, blockFor(exercise, 'main'), 'main')

describe('what an exercise becomes', () => {
  it('reads the kind from the exercise', () => {
    expect(ALL.map(kindFor)).toEqual(['sets', 'sets', 'sets', 'timed', 'distance', 'hold', 'practice'])
  })
  it('starts from its usual volume and its catalog weight', () => {
    const block = blockFor(squat, 'main')
    expect(block.movements[0]).toMatchObject({ exercise_id: 'back_squat', sets: 3, reps: 5, start_kg: 60 })
    expect(blockFor(row, 'cooldown')).toMatchObject({ kind: 'timed', stage: 'cooldown', minutes: 30, intensity: 'zone2' })
    expect(blockFor(plank, 'main').movements[0]).toMatchObject({ sets: 3, hold_sec: 45 })
    expect(blockFor(run, 'main').movements[0]).toMatchObject({ distance_m: 400 })
  })
})

describe('edits', () => {
  it('keeps blocks in stage order whatever order they were added in', () => {
    let d = insertBlock(emptyDraft(), blockFor(row, 'cooldown'), 'cooldown')
    d = insertBlock(d, blockFor(squat, 'main'), 'main')
    d = insertBlock(d, blockFor(stretch, 'prep'), 'prep')
    expect(d.blocks.map((b) => b.stage)).toEqual(['prep', 'main', 'cooldown'])
  })
  it('inserts at a place of a stage and moves between stages', () => {
    let d = withBlock(squat)
    d = insertBlock(d, blockFor(pullUp, 'main'), 'main', 0)
    expect(blocksOfStage(d, 'main').map((b) => b.movements[0].exercise_id)).toEqual(['pull_up', 'back_squat'])
    d = moveBlock(d, d.blocks[0].uid, 'finisher')
    expect(d.blocks.map((b) => [b.stage, b.movements[0].exercise_id])).toEqual([['main', 'back_squat'], ['finisher', 'pull_up']])
  })
  it('nudges within a stage, then into the next one', () => {
    let d = withBlock(pullUp, withBlock(squat))
    const first = d.blocks[0].uid
    d = nudgeBlock(d, first, 1)
    expect(blocksOfStage(d, 'main').map((b) => b.uid)[1]).toBe(first)
    d = nudgeBlock(d, first, 1)
    expect(d.blocks.find((b) => b.uid === first)?.stage).toBe('finisher')
    expect(nudgeBlock(d, first, -1).blocks.find((b) => b.uid === first)?.stage).toBe('main')
  })
  it('makes straight sets a superset when a second exercise is dropped on them', () => {
    const d = withBlock(squat)
    const out = addExercise(d, d.blocks[0].uid, pullUp)
    expect(out.blocks).toHaveLength(1)
    expect(out.blocks[0]).toMatchObject({ kind: 'superset', rounds: 3, rest_sec: 90 })
    expect(out.blocks[0].movements.map((m) => m.exercise_id)).toEqual(['back_squat', 'pull_up'])
    expect(out.blocks[0].movements[0]).not.toHaveProperty('sets')
  })
  it('adds to a piece, and puts a new block after one that takes a single exercise', () => {
    let d = insertBlock(emptyDraft(), emptyBlock('amrap', 'main'), 'main')
    d = addExercise(addExercise(d, d.blocks[0].uid, pullUp), d.blocks[0].uid, squat)
    expect(d.blocks[0].movements.map((m) => [m.exercise_id, m.reps])).toEqual([['pull_up', 10], ['back_squat', 5]])
    let t = withBlock(row)
    t = addExercise(t, t.blocks[0].uid, run)
    expect(t.blocks.map((b) => b.kind)).toEqual(['timed', 'distance'])
  })
  it('changes a block\'s kind and keeps its exercises', () => {
    let d = withBlock(squat)
    d = addExercise(d, d.blocks[0].uid, pullUp)
    const amrap = setKind(d, d.blocks[0].uid, 'amrap', CATALOG)
    expect(amrap.blocks[0]).toMatchObject({ kind: 'amrap', minutes: 12 })
    expect(amrap.blocks[0].movements.map((m) => m.exercise_id)).toEqual(['back_squat', 'pull_up'])
    expect(amrap.blocks[0].movements[0].start_kg).toBe(60)
    const split = setKind(d, d.blocks[0].uid, 'sets', CATALOG)
    expect(split.blocks.map((b) => [b.kind, b.movements.map((m) => m.exercise_id)])).toEqual([['sets', ['back_squat']], ['sets', ['pull_up']]])
  })
  it('drops a cleared field and an emptied progress rule', () => {
    let d = withBlock(squat)
    const [b] = d.blocks
    d = updateMovement(d, b.uid, b.movements[0].uid, { progress: { add_kg: 2.5 } })
    expect(d.blocks[0].movements[0].progress).toEqual({ add_kg: 2.5 })
    d = updateMovement(d, b.uid, b.movements[0].uid, { start_kg: undefined, progress: { add_kg: undefined } })
    expect(d.blocks[0].movements[0]).not.toHaveProperty('start_kg')
    expect(d.blocks[0].movements[0]).not.toHaveProperty('progress')
    expect(removeMovement(d, b.uid, b.movements[0].uid).blocks[0].movements).toEqual([])
  })
})

describe('a count as typed', () => {
  it('reads reps, a scheme, metres and seconds', () => {
    expect(parseCount('10')).toEqual({ reps: 10 })
    expect(parseCount('21-15-9')).toEqual({ rep_scheme: [21, 15, 9] })
    expect(parseCount('400 m')).toEqual({ distance_m: 400 })
    expect(parseCount('1.5km')).toEqual({ distance_m: 1500 })
    expect(parseCount('30 s')).toEqual({ seconds: 30 })
    expect(parseCount('max')).toEqual({ reps: 'max' })
    expect(parseCount(' ')).toEqual({})
  })
  it('shows what it read and replaces the count whole', () => {
    const m = withCount({ exercise_id: 'x', reps: 10, start_kg: 20 }, '21-15-9')
    expect(m).toEqual({ exercise_id: 'x', start_kg: 20, rep_scheme: [21, 15, 9] })
    expect(countText(m)).toBe('21-15-9')
    expect(countText(withCount(m, '400m'))).toBe('400 m')
  })
})

describe('the wire', () => {
  it('sends no client keys and reads back the same session', () => {
    let d = withBlock(squat)
    d = { ...d, name: '  Squat day ', modality: 'max_strength', notes: ' ' }
    const wire = toWire(d)
    expect(JSON.stringify(wire)).not.toContain('uid')
    expect(wire).toMatchObject({ name: 'Squat day', modality: 'max_strength' })
    expect(wire).not.toHaveProperty('notes')
    expect(toWire(fromWire({ ...wire, id: 'u1_ms_squat_day' }))).toEqual({ ...wire, id: 'u1_ms_squat_day' })
  })
})

describe('search', () => {
  it('narrows with every word and ranks the name first', () => {
    expect(searchExercises(ALL, { query: 'sq', categories: [] }).map((e) => e.id)).toEqual(['back_squat', 'front_squat'])
    expect(searchExercises(ALL, { query: 'back sq', categories: [] }).map((e) => e.id)).toEqual(['back_squat'])
    expect(searchExercises(ALL, { query: 'row', categories: [] })[0].id).toBe('row_easy')
    expect(searchExercises(ALL, { query: 'zzz', categories: [] })).toEqual([])
  })
  it('finds an exercise by its movement, category or equipment, after the names', () => {
    const byPattern = searchExercises(ALL, { query: 'pull', categories: [] })
    expect(byPattern[0].id).toBe('pull_up')
    expect(searchExercises(ALL, { query: 'rower', categories: [] }).map((e) => e.id)).toEqual(['row_easy'])
    expect(searchScore(row, 'rower')).toBeLessThan(searchScore(row, 'row'))
  })
  it('filters by category and by the equipment owned', () => {
    expect(searchExercises(ALL, { query: '', categories: ['aerobic'] }).map((e) => e.id).sort()).toEqual(['row_easy', 'run_400'])
    expect(searchExercises(ALL, { query: '', categories: [], equipment: ['pull_up_bar'] }).map((e) => e.id).sort())
      .toEqual(['couch_stretch', 'plank', 'pull_up', 'run_400'])
  })
})

describe('reading the session', () => {
  it('suggests the modality its main exercises list first', () => {
    let d = insertBlock(emptyDraft(), blockFor(stretch, 'prep'), 'prep')
    d = withBlock(front, withBlock(squat, d))
    expect(suggestModality(d, CATALOG)).toBe('max_strength')
    expect(suggestModality(emptyDraft(), CATALOG)).toBeNull()
  })
  it('places a date in the program, or says why it cannot', () => {
    expect(programSlot('2026-11-23', 4, '2026-11-25', '2026-11-24')).toEqual({ weekIndex: 0, day: 'Wednesday' })
    expect(programSlot('2026-11-23', 4, '2026-12-07', '2026-11-24')).toEqual({ weekIndex: 2, day: 'Monday' })
    expect(programSlot(null, 0, '2026-11-25', '2026-11-24')).toHaveProperty('reason')
    expect(programSlot('2026-11-23', 4, '2026-11-23', '2026-11-24')).toHaveProperty('reason')
    expect(programSlot('2026-11-23', 1, '2026-12-07', '2026-11-24')).toHaveProperty('reason')
    expect(programSlot('2026-12-01', 4, '2026-11-25', '2026-11-24')).toHaveProperty('reason')
  })
})
