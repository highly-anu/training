import { describe, it, expect } from 'vitest'
import { entrySentence, scopeText, expectedText } from './analyticsSpecText'
import type { ProgressSpecEntry, ProgressSpecScope } from '@/api/types'

const empty: ProgressSpecScope = {
  modalities: [], archetypes: [], frameworks: [], exercises: [],
  movementPatterns: [], slotTypes: [], slotRoles: [], excludeSlotRoles: [],
}
const base: ProgressSpecEntry = {
  id: 'x', label: 'X', primitive: 'set_load', headline: false, source: 'declared',
  scope: empty, expected: { kind: 'none' }, stall: null, benchmarks: [],
  targetLevel: null, rpmTarget: null, minSessions: 2, notes: null,
}
const vocab = { set_load: { label: 'Set load', measures: 'Best working set and estimated 1RM per session', unit: 'kg', needs: ['sets'], expectedKinds: [] },
  duration: { label: 'Duration', measures: 'Minutes per session and per week', unit: 'min', needs: ['minutes'], expectedKinds: [] },
  rate: { label: 'Cadence', measures: 'Reps per minute on a timed set', unit: 'rpm', needs: ['timed_reps'], expectedKinds: [] } }

describe('analyticsSpecText', () => {
  it('reads Starting Strength bar load as one sentence', () => {
    const e: ProgressSpecEntry = { ...base,
      scope: { ...empty, modalities: [{ id: 'max_strength', name: 'Max Strength' }], slotTypes: ['sets_reps'],
               excludeSlotRoles: ['*warm*', '*accessory*', '*prep*'] },
      expected: { kind: 'achieved_plus_increment' }, stall: { sessions: 3, tolerancePct: 1 } }
    expect(entrySentence(e, vocab.set_load)).toBe(
      "Best working set and estimated 1RM per session on max strength sessions sets × reps slots (not warm-up, accessory and prep), expected to rise by the exercise's increment every session; stalled after 3 flat sessions.")
  })

  it("reads Uphill's long day against the prescribed minutes", () => {
    const e: ProgressSpecEntry = { ...base, primitive: 'duration',
      scope: { ...empty, archetypes: [{ id: 'a', name: 'Long Zone 2' }, { id: 'b', name: 'Long Mountain Day' }, { id: 'c', name: 'Weighted Ruck Z2' }] },
      expected: { kind: 'load_field', field: 'duration_minutes' } }
    expect(entrySentence(e, vocab.duration)).toBe(
      'Minutes per session and per week on the long zone 2, long mountain day and weighted ruck z2 sessions, vs the prescribed minutes.')
  })

  it('reads a Wildman cadence target with its framework window', () => {
    const e: ProgressSpecEntry = { ...base, primitive: 'rate', rpmTarget: 20,
      scope: { ...empty, frameworks: [{ id: 'kb_pentathlon', name: 'KB Pentathlon' }],
               archetypes: [{ id: 'p', name: 'KB Pentathlon Training' }], exercises: [{ id: 'j', name: 'KB Jerk (single)' }] } }
    expect(entrySentence(e, vocab.rate)).toBe(
      'Reps per minute on a timed set on kb jerk (single) in the kb pentathlon training session during KB Pentathlon, target 20 rpm.')
  })

  it('handles an empty scope and a constant target', () => {
    expect(scopeText(empty)).toBe('')
    expect(expectedText({ kind: 'constant', value: 5, unit: 'rounds' })).toBe('target 5 rounds')
    expect(expectedText({ kind: 'framework_field', field: 'intensity_distribution' })).toBe("vs the framework's intensity distribution")
  })
})
