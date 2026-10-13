import { describe, it, expect } from 'vitest'
import fx from '@shared/workout_analysis_fixture.json'
import { computeHRZones, normalCDF } from './hrZones'

describe('normalCDF', () => {
  it('is the normal CDF', () => {
    // It used to return ≈ 0 at the mean (erf of z, not z/√2, read as Φ).
    expect(normalCDF(140, 140, 8)).toBeCloseTo(0.5, 6)
    expect(normalCDF(148, 140, 8)).toBeCloseTo(0.8413, 3)
    expect(normalCDF(132, 140, 8)).toBeCloseTo(0.1587, 3)
  })

  it('gives the summary estimate the server gives (test_workout_analysis.py)', () => {
    const s = fx.summary as { heartRate: { avg: number; max: number } }
    const z = computeHRZones(fx.maxHr, [], s.heartRate.avg, undefined, s.heartRate.max)
    expect([z.z1, z.z2, z.z3, z.z4, z.z5]).toEqual([0, 52, 46, 2, 0])
    const c = computeHRZones(fx.maxHr, [], s.heartRate.avg, [0.6, 0.7, 0.8, 0.9], s.heartRate.max)
    expect([c.z1, c.z2, c.z3, c.z4, c.z5]).toEqual([0, 4, 65, 31, 0])
  })
})
