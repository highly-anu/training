/**
 * Blending phased framework expectations must weight each phase by ITS OWN
 * duration.
 *
 * `phaseFrameworks` used to be a filtered array of frameworks indexed
 * alongside the unfiltered `phases`, so a phase whose framework was missing
 * shifted every later phase onto the wrong duration. Typing the file (it was
 * `any[]`) is what exposed it.
 */
import { describe, it, expect } from 'vitest'
import { blendExpectations } from './feasibility'
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const any_ = (v: unknown) => v as any

const expectations = (days: number) => ({
  min_weeks: 4, ideal_weeks: 8,
  min_days_per_week: days, ideal_days_per_week: days,
  min_session_minutes: 30, ideal_session_minutes: 60,
})

const philosophy = any_({
  id: 'p1',
  framework_groups: [{
    type: 'sequential',
    canonical_phase_sequence: [
      { phase: 'base',     framework_id: 'fw-base',  weeks: 2 },
      { phase: 'missing',  framework_id: 'fw-gone',  weeks: 10 },
      { phase: 'peak',     framework_id: 'fw-peak',  weeks: 2 },
    ],
  }],
})

describe('blendExpectations with a phased philosophy', () => {
  const opts = (frameworks: unknown[]) => any_({
    sourceMode: 'philosophy',
    selectedPhilosophyIds: ['p1'],
    philosophies: [philosophy],
    frameworks,
  })

  it('weights each phase by its own duration', () => {
    // Every phase resolves: 2wk@3d, 10wk@6d, 2wk@3d over 14wk = 5.14 -> 5
    const all = [
      { id: 'fw-base', expectations: expectations(3) },
      { id: 'fw-gone', expectations: expectations(6) },
      { id: 'fw-peak', expectations: expectations(3) },
    ]
    const blended = blendExpectations([], [], {}, opts(all))
    expect(blended?.ideal_days_per_week).toBe(5)
  })

  it('does not misalign the remaining phases when one framework is missing', () => {
    // fw-gone is absent, so only base (2wk) and peak (2wk) contribute, both at
    // 3 days. The answer must be 3 — not a value pulled from the 10-week
    // phase's duration, which is what the index drift produced.
    const missing = [
      { id: 'fw-base', expectations: expectations(3) },
      { id: 'fw-peak', expectations: expectations(3) },
    ]
    const blended = blendExpectations([], [], {}, opts(missing))
    expect(blended?.ideal_days_per_week).toBe(3)
  })

  it('still reports the full program length, including phases it could not resolve', () => {
    const missing = [
      { id: 'fw-base', expectations: expectations(3) },
      { id: 'fw-peak', expectations: expectations(3) },
    ]
    const blended = blendExpectations([], [], {}, opts(missing))
    // 2 + 10 + 2 — the athlete's program is still 14 weeks long.
    expect(blended?.ideal_weeks).toBe(14)
  })
})
