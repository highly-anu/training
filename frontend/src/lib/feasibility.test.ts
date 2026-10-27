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
  tracks: [{
    id: 't1',
    name: 'Track',
    phases: [
      { id: 'a', name: 'A', kind: 'base',  framework_id: 'fw-base', weeks: 2 },
      { id: 'b', name: 'B', kind: 'build', framework_id: 'fw-gone', weeks: 10 },
      { id: 'c', name: 'C', kind: 'peak',  framework_id: 'fw-peak', weeks: 2 },
    ],
  }, {
    id: 'single',
    name: 'One block',
    phases: [{ id: 'blk', name: 'Block', kind: 'base', framework_id: 'fw-base', weeks: 12 }],
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

  it('takes a one-phase track straight from its framework', () => {
    const blended = blendExpectations([], [], {}, any_({
      ...opts([{ id: 'fw-base', expectations: expectations(3) }]),
      selectedTrackId: 'single',
    }))
    expect(blended?.min_weeks).toBe(4)
    expect(blended?.ideal_days_per_week).toBe(3)
  })
})

// The builder's schedule step recommended rest on every day for a blend of
// several tracks: the expectations came back null, since a blend had no one
// track to read them from.
describe('blendExpectations with several tracks', () => {
  const two = any_({
    id: 'p2',
    tracks: [{ id: 'lift', name: 'Lift', phases: [{ id: 'l', name: 'L', kind: 'base', framework_id: 'fw-lift', weeks: 12 }] }],
  })
  const frameworks = [
    { id: 'fw-base', expectations: { ...expectations(4), ideal_long_session_minutes: 120, supports_split_days: true } },
    { id: 'fw-lift', expectations: { ...expectations(3), min_weeks: 6, ideal_weeks: 12, ideal_session_minutes: 75 } },
  ]
  const opts = (lanes: unknown[]) => any_({
    sourceMode: 'blend', frameworks, philosophies: [philosophy, two], selectedPhilosophyIds: ['p1', 'p2'], lanes,
  })

  it('asks for every track\'s days, each session and long day, and the longest track\'s weeks', () => {
    const exp = blendExpectations([], [], {}, opts([
      { philosophyId: 'p1', trackId: 'single', weight: 60 },
      { philosophyId: 'p2', trackId: null, weight: 40 },
    ]))
    expect(exp?.ideal_days_per_week).toBe(7)
    expect(exp?.min_days_per_week).toBe(4)
    expect(exp?.ideal_session_minutes).toBe(75)
    expect(exp?.ideal_long_session_minutes).toBe(120)
    expect(exp?.ideal_weeks).toBe(12)
    expect(exp?.supports_split_days).toBe(true)
  })

  it('never asks for more than seven days', () => {
    const exp = blendExpectations([], [], {}, opts([
      { philosophyId: 'p1', trackId: 'single', weight: 50 },
      { philosophyId: 'p1', trackId: 'single', weight: 50 },
      { philosophyId: 'p2', trackId: 'lift', weight: 50 },
    ]))
    expect(exp?.ideal_days_per_week).toBe(7)
  })

  it('reads one track as before', () => {
    const exp = blendExpectations([], [], {}, any_({ ...opts([{ philosophyId: 'p2', trackId: 'lift', weight: 100 }]),
      sourceMode: 'philosophy', selectedPhilosophyIds: ['p2'] }))
    expect(exp?.ideal_days_per_week).toBe(3)
  })
})
