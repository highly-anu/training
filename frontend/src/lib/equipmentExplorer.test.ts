import { describe, it, expect } from 'vitest'
import { explore, indexEquipment, unlocks, NOTHING_PICKED, type Picked } from '@/lib/equipmentExplorer'
import type { LineageNames } from '@/lib/exploreLinks'
import type { ExploreLinks } from '@/api/types'

// Two philosophies. `kb` runs one framework of two modalities; `bb` one of one.
const DOC: ExploreLinks = {
  movements: [
    { id: 'hip_hinge', name: 'Hip hinge', exerciseCount: 2, filterGroups: [], rollup: 'hinge' },
    { id: 'squat', name: 'Squat', exerciseCount: 2, filterGroups: [], rollup: 'squat' },
  ],
  equipment: {
    vocabulary: ['barbell', 'kettlebell', 'open_space', 'rower', 'ski_erg'],
    exercises: { swing: ['kettlebell'], goblet: ['kettlebell'], back_squat: ['barbell'], air_squat: [], row: ['rower'] },
    archetypes: { kb_power: ['kettlebell'], kb_cond: ['kettlebell', 'rower'], bb_day: ['barbell'], bw_day: [] },
  },
  links: {
    philosophyFramework: [
      { philosophy: 'kb', framework: 'kb_fw', owner: true, phases: [] },
      { philosophy: 'bb', framework: 'bb_fw', owner: true, phases: [] },
    ],
    frameworkModality: [
      { framework: 'kb_fw', modality: 'power', sessionsPerWeek: 2, tier: 'core' },
      { framework: 'kb_fw', modality: 'conditioning', sessionsPerWeek: 1, tier: null },
      { framework: 'bb_fw', modality: 'strength', sessionsPerWeek: 3, tier: 'committed' },
    ],
    modalityArchetype: [
      { modality: 'power', archetype: 'kb_power', package: 'kb' },
      { modality: 'conditioning', archetype: 'kb_cond', package: 'kb' },
      { modality: 'strength', archetype: 'bb_day', package: 'bb' },
      { modality: 'strength', archetype: 'bw_day', package: 'bb' },
    ],
    archetypeExercise: [
      { archetype: 'kb_power', exercise: 'swing', slots: ['main'], via: 'listed' },
      { archetype: 'kb_power', exercise: 'goblet', slots: ['finisher'], via: 'listed' },
      { archetype: 'kb_cond', exercise: 'row', slots: ['main'], via: 'listed' },
      { archetype: 'bb_day', exercise: 'back_squat', slots: ['main'], via: 'listed' },
      { archetype: 'bw_day', exercise: 'air_squat', slots: ['main'], via: 'listed' },
    ],
    exerciseMovement: [
      { exercise: 'swing', movement: 'hip_hinge' }, { exercise: 'goblet', movement: 'squat' },
      { exercise: 'back_squat', movement: 'squat' }, { exercise: 'air_squat', movement: 'squat' },
    ],
    exerciseProgression: [], exerciseConcepts: [],
  },
}

const NAMES: LineageNames = {
  philosophies: {}, archetypes: {},
  frameworks: { kb_fw: 'KB Practice', bb_fw: 'Barbell Block' },
  modalities: { power: 'Power', conditioning: 'Conditioning', strength: 'Strength' },
  exercises: { swing: 'Swing', goblet: 'Goblet squat', back_squat: 'Back squat', air_squat: 'Air squat', row: 'Row' },
}

const ix = indexEquipment(DOC)
const ids = (items: { id: string }[]) => items.map((i) => i.id)
const pick = (p: Partial<Picked>): Picked => ({ ...NOTHING_PICKED, ...p })

describe('explore', () => {
  it('needs every item: a kettlebell alone enables power, not conditioning that also needs a rower', () => {
    const r = explore(ix, new Set(['kettlebell']), NOTHING_PICKED, NAMES)
    // Strength comes from the bodyweight day, which needs nothing.
    expect(ids(r.modalities)).toEqual(['power', 'strength'])
    expect(ids(r.exercises)).toEqual(['air_squat', 'goblet', 'swing'])
    expect(ids(r.movements)).toEqual(['squat', 'hip_hinge'])
  })

  it('a framework is partial when only some of its modalities are enabled', () => {
    const r = explore(ix, new Set(['kettlebell']), NOTHING_PICKED, NAMES)
    expect(r.frameworks.map((f) => [f.id, f.partial ?? false, f.note])).toEqual([
      ['bb_fw', false, '1 modality'],
      ['kb_fw', true, '1 of 2 modalities'],
    ])
    const full = explore(ix, new Set(['kettlebell', 'rower']), NOTHING_PICKED, NAMES)
    expect(full.frameworks.find((f) => f.id === 'kb_fw')?.partial).toBeUndefined()
  })

  it('a pick narrows the other lists, not its own', () => {
    const r = explore(ix, new Set(['kettlebell', 'barbell']), pick({ modalities: ['power'] }), NAMES)
    expect(ids(r.exercises)).toEqual(['goblet', 'swing'])
    expect(ids(r.movements).sort()).toEqual(['hip_hinge', 'squat'])
    expect(ids(r.frameworks)).toEqual(['kb_fw'])
    // Power is picked, and Strength can still be added to it.
    expect(r.modalities.map((m) => [m.id, m.picked]).sort()).toEqual([['power', true], ['strength', false]])
  })

  it('OR within a list, AND across lists', () => {
    const eq = new Set(['kettlebell', 'barbell'])
    const either = explore(ix, eq, pick({ modalities: ['power', 'strength'] }), NAMES)
    expect(ids(either.exercises)).toEqual(['air_squat', 'back_squat', 'goblet', 'swing'])
    const both = explore(ix, eq, pick({ modalities: ['power', 'strength'], movements: ['hip_hinge'] }), NAMES)
    expect(ids(both.exercises)).toEqual(['swing'])
    // The hinge pick narrows modalities to those with a hinge exercise; picked
    // Strength stays, marked as ruled out by the other picks.
    expect(both.modalities.map((m) => [m.id, m.unmatched ?? false])).toEqual([['power', false], ['strength', true]])
  })

  it('an exercise pick narrows modalities and movements to it', () => {
    const r = explore(ix, new Set(['kettlebell', 'barbell']), pick({ exercises: ['back_squat'] }), NAMES)
    expect(ids(r.modalities)).toEqual(['strength'])
    expect(ids(r.movements)).toEqual(['squat'])
    expect(r.exercises.find((x) => x.id === 'back_squat')?.picked).toBe(true)
  })

  it('without bodyweight, keeps only what uses the equipment', () => {
    const off = { bodyweight: false }
    const r = explore(ix, new Set(['kettlebell']), NOTHING_PICKED, NAMES, {}, off)
    // The air squat and the bodyweight day need nothing, so they go, and
    // Strength and the barbell framework with them.
    expect(ids(r.exercises)).toEqual(['goblet', 'swing'])
    expect(ids(r.modalities)).toEqual(['power'])
    expect(r.frameworks.map((f) => [f.id, f.note])).toEqual([['kb_fw', '1 of 2 modalities']])
    expect(ids(r.movements).sort()).toEqual(['hip_hinge', 'squat'])

    const none = explore(ix, new Set(), NOTHING_PICKED, NAMES, {}, off)
    expect(Object.values(none).every((l) => l.length === 0)).toBe(true)
    // Barbell adds its day, which brings Strength back.
    expect(unlocks(ix, new Set(['kettlebell']), NOTHING_PICKED, off).barbell.byFacet)
      .toEqual({ modalities: 1, frameworks: 1, movements: 0, exercises: 1 })
  })

  it('a pick the equipment no longer enables stays, marked, so it can be unpicked', () => {
    const r = explore(ix, new Set(['kettlebell']), pick({ exercises: ['back_squat'] }), NAMES)
    expect(r.exercises.at(-1)).toMatchObject({ id: 'back_squat', picked: true, unavailable: true })
  })
})

describe('unlocks', () => {
  it('counts what each unchosen, used item would add; unused and chosen ones are absent', () => {
    const u = unlocks(ix, new Set(['kettlebell']), NOTHING_PICKED)
    expect(Object.keys(u).sort()).toEqual(['barbell', 'rower'])
    expect(u.rower.byFacet).toEqual({ modalities: 1, frameworks: 0, movements: 0, exercises: 1 })
    expect(u.barbell).toEqual({ total: 1, byFacet: { modalities: 0, frameworks: 0, movements: 0, exercises: 1 } })
  })
})
