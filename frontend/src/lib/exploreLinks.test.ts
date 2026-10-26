import { describe, it, expect } from 'vitest'
import { indexLinks, lineageOf, progressionOf, type LineageNames } from '@/lib/exploreLinks'
import type { ExploreLinks } from '@/api/types'

const LINKS: ExploreLinks = {
  movements: [
    { id: 'squat', name: 'Squat', exerciseCount: 2, filterGroups: [], rollup: 'squat' },
    { id: 'hip_hinge', name: 'Hip hinge', exerciseCount: 1, filterGroups: ['hinge', 'swing'], rollup: 'hinge' },
  ],
  links: {
    philosophyFramework: [
      { philosophy: 'wk', framework: 'gp', owner: true,
        phases: [{ trackId: 't', trackName: 'General Practice', trackIndex: 0, phaseId: 'p1', phaseName: 'Phase I', order: 0 },
                 { trackId: 't', trackName: 'General Practice', trackIndex: 0, phaseId: 'p2', phaseName: 'Phase II', order: 1 }] },
      { philosophy: 'wk', framework: 'loose', owner: true, phases: [] },
      { philosophy: 'wk', framework: 'pent', owner: true,
        phases: [{ trackId: 'u', trackName: 'Pentathlon', trackIndex: 1, phaseId: 'q1', phaseName: 'Timed Sets', order: 0 }] },
    ],
    frameworkModality: [
      { framework: 'gp', modality: 'strength', sessionsPerWeek: 3, tier: 'committed' },
      { framework: 'gp', modality: 'mobility', sessionsPerWeek: null, tier: 'core' },
    ],
    modalityArchetype: [{ modality: 'strength', archetype: 'kb_day', package: 'wk' }],
    archetypeExercise: [
      { archetype: 'kb_day', exercise: 'goblet', slots: ['main', 'finisher'], via: 'listed' },
      { archetype: 'kb_day', exercise: 'swing', slots: ['main'], via: 'filter' },
    ],
    exerciseMovement: [
      { exercise: 'goblet', movement: 'squat' }, { exercise: 'front', movement: 'squat' },
      { exercise: 'swing', movement: 'hip_hinge' },
    ],
    exerciseProgression: [{ from: 'goblet', to: 'front', declaredBy: ['requires', 'unlocks'] },
                          { from: 'deadlift', to: 'swing', declaredBy: ['unlocks'] }],
    exerciseConcepts: [{ exercise: 'swing', concept: 'hip_hinge_pattern' }],
  },
}

const NAMES: LineageNames = {
  philosophies: { wk: 'Wildman' },
  frameworks: { gp: 'General Practice', loose: 'Loose', pent: 'Pentathlon' },
  modalities: { strength: 'Strength', mobility: 'Mobility' },
  archetypes: { kb_day: 'Kettlebell day' },
  exercises: { goblet: 'Goblet squat', front: 'Front squat', swing: 'Swing', deadlift: 'Deadlift' },
}

const ix = indexLinks(LINKS, { goblet: 'wk', front: 'wk', swing: 'wk' })
const labels = (groups: { label: string; items: { name: string; note?: string }[] }[]) =>
  groups.map((g) => [g.label, g.items.map((i) => (i.note ? `${i.name} (${i.note})` : i.name))])

describe('lineageOf', () => {
  it('a philosophy: nothing above, its frameworks by track then the rest', () => {
    const l = lineageOf(ix, 'philosophies', 'wk', NAMES)
    expect(l.up).toEqual([])
    expect(labels(l.down)).toEqual([
      ['General Practice', ['General Practice (Phase I · Phase II)']],
      ['Pentathlon', ['Pentathlon (Timed Sets)']],
      ['Also offers', ['Loose']],
    ])
  })

  it('a framework: its philosophy and phases above, modalities by sessions below', () => {
    const l = lineageOf(ix, 'frameworks', 'gp', NAMES)
    expect(labels(l.up)).toEqual([['Philosophy', ['Wildman (General Practice › Phase I, General Practice › Phase II)']]])
    expect(labels(l.down)).toEqual([['Modalities', ['Strength (3/wk · committed)', 'Mobility (core)']]])
  })

  it('a modality: frameworks above and archetypes below, grouped by philosophy', () => {
    const l = lineageOf(ix, 'modalities', 'strength', NAMES)
    expect(labels(l.up)).toEqual([['Frameworks · Wildman', ['General Practice (3/wk · committed)']]])
    expect(labels(l.down)).toEqual([['Archetypes · Wildman', ['Kettlebell day']]])
  })

  it('an archetype: philosophy, framework, modality above; exercises per slot below', () => {
    const l = lineageOf(ix, 'archetypes', 'kb_day', NAMES)
    expect(l.up.map((g) => g.label)).toEqual(['Philosophy', 'Framework', 'Modality'])
    expect(labels(l.down)).toEqual([
      ['Main', ['Goblet squat', 'Swing (by pattern)']],
      ['Finisher', ['Goblet squat']],
    ])
    expect(l.down[0].items[0]).toMatchObject({ topic: 'exercises', id: 'goblet' })
  })

  it('an exercise: the archetypes that take it above, its movements below', () => {
    const l = lineageOf(ix, 'exercises', 'goblet', NAMES)
    expect(labels(l.up)).toEqual([['Archetypes · Wildman', ['Kettlebell day (Main, Finisher)']]])
    expect(l.down[0].items).toEqual([{ topic: 'movements', id: 'squat', name: 'Squat' }])
  })

  it('a movement: its exercises above, its filter groups and rollup as plain items below', () => {
    const l = lineageOf(ix, 'movements', 'hip_hinge', NAMES)
    expect(labels(l.up)).toEqual([['Exercises · Wildman', ['Swing']]])
    expect(labels(l.down)).toEqual([['Slot filters', ['Hinge', 'Swing']], ['Counted as', ['Hinge']]])
    expect(l.down.flatMap((g) => g.items).every((i) => i.topic === undefined)).toBe(true)
  })
})

describe('progressionOf', () => {
  it('reads requires and unlocks from both ends, a concept as a plain item', () => {
    const p = progressionOf(ix, 'swing', ['kb_deadlift', 'goblet'], NAMES)
    expect(p.before).toEqual([
      { topic: 'exercises', id: 'deadlift', name: 'Deadlift' },
      { id: 'hip_hinge_pattern', name: 'Hip hinge pattern', note: 'concept' },
    ])
    expect(p.after).toEqual([])
    // An easier version that is an exercise links; one that is not stays text.
    expect(p.easier).toEqual([{ id: 'kb_deadlift', name: 'Kb deadlift' },
                              { topic: 'exercises', id: 'goblet', name: 'Goblet squat' }])
    expect(progressionOf(ix, 'goblet', [], NAMES).after.map((i) => i.id)).toEqual(['front'])
  })
})
