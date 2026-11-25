import { describe, expect, it } from 'vitest'
import { draftFromRecipe } from './shareRecipe'

describe('draftFromRecipe', () => {
  it('one method: its track, start phase, length and a contract\'s options', () => {
    expect(draftFromRecipe({ philosophy_id: 'alpha', track_id: 't1', start_phase: 'p1', num_weeks: 8, contract_options: { swing: 'c' } }))
      .toEqual({
        sourceMode: 'philosophy', selectedGoalIds: ['general_gpp'], selectedPhilosophyIds: ['alpha'], philosophyWeights: {},
        selectedTrackId: 't1', startPhaseId: 'p1', numWeeks: 8, lanes: [], contractOptions: { swing: 'c' },
      })
  })

  it('a composition: each track with its own start, weights on the builder\'s scale', () => {
    const d = draftFromRecipe({ num_weeks: 12, lanes: [
      { philosophy_id: 'alpha', track_id: 't1', weight: 0.6, start_phase: 'a' },
      { philosophy_id: 'alpha', track_id: 't2', weight: 0.25 },
      { philosophy_id: 'beta', track_id: null, weight: 0.15 },
    ] })!
    expect(d.sourceMode).toBe('blend')
    expect(d.selectedPhilosophyIds).toEqual(['alpha', 'beta'])
    expect(d.lanes).toEqual([
      { philosophyId: 'alpha', trackId: 't1', weight: 60, startPhaseId: 'a' },
      { philosophyId: 'alpha', trackId: 't2', weight: 25, startPhaseId: null },
      { philosophyId: 'beta', trackId: null, weight: 15, startPhaseId: null },
    ])
    expect(d.selectedTrackId).toBeNull()
  })

  it('the old blend shape keeps its weights and its owner\'s track', () => {
    const d = draftFromRecipe({ philosophy_ids: ['alpha', 'beta'], philosophy_weights: { alpha: 0.7, beta: 0.3 }, track_id: 't1' })!
    expect(d.sourceMode).toBe('blend')
    expect(d.philosophyWeights).toEqual({ alpha: 70, beta: 30 })
    expect(d.selectedTrackId).toBe('t1')
    expect(d.lanes).toEqual([])
  })

  it('nothing to build from', () => {
    expect(draftFromRecipe(null)).toBeNull()
    expect(draftFromRecipe({ num_weeks: 4 })).toBeNull()
  })
})
