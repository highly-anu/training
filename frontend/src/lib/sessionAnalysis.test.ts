/**
 * A session with no archetype must not crash the analysis.
 *
 * `Session.archetype` is null whenever the philosophy package could not fill
 * that slot — a documented coverage gap, not corrupt data. A real 18-week
 * program had 14 such sessions out of 72, and four unguarded
 * `s.archetype.duration_estimate_minutes` reads inside reduces threw
 * "Cannot read properties of null", taking down the whole program view.
 *
 * The fixture is two sessions lifted verbatim from that stored program.
 */
import { describe, it, expect } from 'vitest'
import fixture from './__fixtures__/coverage-gap-sessions.json'
import { computeSessionInsight, computeWeekInsights } from './sessionAnalysis'
import type { Session, ImportedWorkout, ModalityId } from '@/api/types'

const gapSession = fixture.gapSession as unknown as Session
const normalSession = fixture.normalSession as unknown as Session

function workout(overrides: Partial<ImportedWorkout> = {}): ImportedWorkout {
  return {
    id: 'garmin-test',
    source: 'garmin',
    date: '2026-09-22',
    startTime: '2026-09-22T08:00:00+00:00',
    endTime: '2026-09-22T09:00:00+00:00',
    durationMinutes: 60,
    activityType: 'Running',
    inferredModalityId: 'aerobic_base' as ModalityId,
    heartRate: { avg: 140, max: 170, samples: [] },
    rawData: {},
    ...overrides,
  } as ImportedWorkout
}

describe('sessions with no archetype (coverage gaps)', () => {
  it('the fixture really is a gap session', () => {
    expect(gapSession.archetype).toBeNull()
    expect(normalSession.archetype).not.toBeNull()
  })

  it('computeSessionInsight survives a gap session', () => {
    expect(() => computeSessionInsight([gapSession], workout(), undefined, 190))
      .not.toThrow()
  })

  it('computeSessionInsight survives a gap mixed with a normal session', () => {
    expect(() =>
      computeSessionInsight([normalSession, gapSession], workout(), undefined, 190)
    ).not.toThrow()
  })

  it('covers every modality family, since each has its own reduce', () => {
    // analyzeAerobic / analyzeStrength / analyzeIntervals / the default branch
    // each dereference the archetype separately.
    for (const modality of ['aerobic_base', 'max_strength', 'anaerobic_intervals',
                            'mobility', 'movement_skill'] as ModalityId[]) {
      const s = { ...gapSession, modality }
      expect(() => computeSessionInsight([s], workout({ inferredModalityId: modality }),
                                         undefined, 190),
      ).not.toThrow()
    }
  })

  it('computeWeekInsights survives a week containing gap sessions', () => {
    const week = {
      week_number: 1,
      phase: 'base',
      schedule: { Monday: [gapSession], Tuesday: [normalSession] },
    }
    expect(() =>
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      computeWeekInsights(week as any, [], {} as any, 190),
    ).not.toThrow()
  })

  it('a gap session contributes no prescribed duration rather than NaN', () => {
    const insight = computeSessionInsight([gapSession], workout(), undefined, 190)
    const text = JSON.stringify(insight)
    expect(text).not.toContain('NaN')
    expect(text).not.toContain('null min')
  })
})
