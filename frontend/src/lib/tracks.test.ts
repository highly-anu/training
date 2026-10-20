/**
 * The track the builder previews when none is picked is the one the server
 * will run: `track_for_level` for the athlete's level (Starting Strength's
 * intermediate gets the Texas Method), else the primary track.
 */
import { describe, it, expect } from 'vitest'
import type { Philosophy } from '@/api/types'
import { builderTrack, primaryTrack } from './tracks'

const ss = {
  id: 'starting_strength',
  name: 'Starting Strength',
  primary_track_id: 'linear_progression',
  track_for_level: { novice: 'linear_progression', intermediate: 'texas_method' },
  tracks: [
    { id: 'linear_progression', name: 'Linear Progression Program', phases: [] },
    { id: 'texas_method', name: 'Texas Method', phases: [] },
  ],
} as unknown as Philosophy

describe('primaryTrack', () => {
  it('follows the athlete\'s level where the philosophy says', () => {
    expect(primaryTrack(ss, 'intermediate')?.id).toBe('texas_method')
    expect(primaryTrack(ss, 'novice')?.id).toBe('linear_progression')
  })

  it('falls back to the primary track', () => {
    expect(primaryTrack(ss, 'elite')?.id).toBe('linear_progression')
    expect(primaryTrack(ss)?.id).toBe('linear_progression')
  })
})

describe('builderTrack', () => {
  it('previews the level\'s track when none is picked, and the picked one when it is', () => {
    expect(builderTrack([ss], ['starting_strength'], null, 'intermediate')?.track.id).toBe('texas_method')
    expect(builderTrack([ss], ['starting_strength'], 'linear_progression', 'intermediate')?.track.id)
      .toBe('linear_progression')
  })
})
