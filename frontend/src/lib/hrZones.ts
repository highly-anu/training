import type { HRSample, HRZoneDistribution } from '@/api/types'

// Friel/Coggan zone boundaries (% of max HR)
const ZONE_UPPER = [0.60, 0.70, 0.80, 0.90, Infinity]

function assignZone(bpm: number, maxHR: number): 0 | 1 | 2 | 3 | 4 {
  const pct = bpm / maxHR
  for (let i = 0; i < ZONE_UPPER.length; i++) {
    if (pct < ZONE_UPPER[i]) return i as 0 | 1 | 2 | 3 | 4
  }
  return 4
}

/** Parse zone number from a zone_target string like "Zone 2 — HR < 135 bpm". Returns 1-5 or null. */
export function parseZoneTarget(zoneTarget: string): number | null {
  const m = zoneTarget.match(/Zone\s*(\d)/i)
  return m ? parseInt(m[1], 10) : null
}

/** Compute zone compliance: returns true when the prescribed zone accounts for ≥50% of session time. */
export function isZoneCompliant(zones: HRZoneDistribution, prescribedZone: number): boolean {
  const key = `z${prescribedZone}` as keyof HRZoneDistribution
  const val = zones[key]
  return typeof val === 'number' && val >= 50
}

// ── Normal CDF approximation (Abramowitz and Stegun) ──────────────────────────

function normalCDF(x: number, mean: number, std: number): number {
  const z = (x - mean) / std
  const t = 1 / (1 + 0.3275911 * Math.abs(z))
  const poly =
    t *
    (0.254829592 +
      t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
  const p = 1 - poly * Math.exp((-z * z) / 2)
  return z >= 0 ? p : 1 - p
}

function estimateZonesFromSummary(maxHR: number, avg: number, max: number): HRZoneDistribution {
  const std = Math.max((max - avg) / 2.5, 1)
  const boundaries = [0, ...ZONE_UPPER.slice(0, -1).map((f) => f * maxHR), Infinity]
  const raw: number[] = []
  for (let i = 0; i < 5; i++) {
    const lo = boundaries[i]
    const hi = boundaries[i + 1]
    const pLo = lo === 0 ? 0 : normalCDF(lo, avg, std)
    const pHi = hi === Infinity ? 1 : normalCDF(hi, avg, std)
    raw.push(Math.max(0, pHi - pLo))
  }
  const total = raw.reduce((a, b) => a + b, 0) || 1
  const pct = raw.map((v) => Math.round((v / total) * 100))
  // Fix rounding so sum is exactly 100
  const diff = 100 - pct.reduce((a, b) => a + b, 0)
  pct[pct.indexOf(Math.max(...pct))] += diff
  return { z1: pct[0], z2: pct[1], z3: pct[2], z4: pct[3], z5: pct[4], method: 'summary_estimate' }
}

/**
 * Compute HR zone distribution.
 * @param maxHR  Maximum heart rate in bpm
 * @param samples  Time-series HR samples (may be empty)
 * @param avgHR  Fallback average HR when samples are unavailable
 */
export function computeHRZones(
  maxHR: number,
  samples: HRSample[],
  avgHR?: number
): HRZoneDistribution {
  if (samples.length >= 2) {
    const sorted = [...samples].sort((a, b) => a.timestamp.localeCompare(b.timestamp))
    const zoneTimes = [0, 0, 0, 0, 0]
    let total = 0
    for (let i = 0; i < sorted.length - 1; i++) {
      const tA = new Date(sorted[i].timestamp).getTime()
      const tB = new Date(sorted[i + 1].timestamp).getTime()
      const interval = Math.min((tB - tA) / 1000, 60) // seconds, cap gaps at 60 s
      if (interval <= 0) continue
      const z = assignZone(sorted[i].bpm, maxHR)
      zoneTimes[z] += interval
      total += interval
    }
    if (total > 0) {
      const pct = zoneTimes.map((t) => Math.round((t / total) * 100))
      const diff = 100 - pct.reduce((a, b) => a + b, 0)
      pct[pct.indexOf(Math.max(...pct))] += diff
      return { z1: pct[0], z2: pct[1], z3: pct[2], z4: pct[3], z5: pct[4], method: 'samples' }
    }
  }

  // Fall back to summary estimate
  const avg = avgHR ?? maxHR * 0.72
  const max = samples[0]?.bpm ?? maxHR
  return estimateZonesFromSummary(maxHR, avg, max)
}

/** Derive max HR from date of birth. Returns undefined if dob is null. */
export function maxHRFromDOB(dob: string | null): number | undefined {
  if (!dob) return undefined
  const birthYear = new Date(dob).getFullYear()
  const age = new Date().getFullYear() - birthYear
  return 220 - age
}
