import type { GPSPoint, HRSample, HRZoneDistribution } from '@/api/types'

// Friel/Coggan zone upper boundaries as fraction of max HR
// Z1: <60%, Z2: 60-70%, Z3: 70-80%, Z4: 80-90%, Z5: 90%+
export const DEFAULT_ZONE_BOUNDARIES = [0.60, 0.70, 0.80, 0.90]

/**
 * The five-zone ramp — single source of truth for zone colour and naming.
 *
 * Unlike MODALITY_COLORS/PHASE_COLORS these encode a *measured* quantity, so the
 * ramp must read as ordered (cool at rest → hot at max) rather than categorical.
 * Near-collisions with modality colours are intentional and the two systems never
 * co-occur on the same mark. See docs/frontend-design.md §8.7.
 *
 * `bg` is the faint band fill used behind timeline plots.
 */
export const ZONES = [
  { key: 'z1', label: 'Z1', description: 'Recovery',  color: '#94a3b8', bg: 'rgba(148,163,184,0.06)' },
  { key: 'z2', label: 'Z2', description: 'Aerobic',   color: '#38bdf8', bg: 'rgba(56,189,248,0.06)'  },
  { key: 'z3', label: 'Z3', description: 'Tempo',     color: '#fbbf24', bg: 'rgba(251,191,36,0.06)'  },
  { key: 'z4', label: 'Z4', description: 'Threshold', color: '#f97316', bg: 'rgba(249,115,22,0.06)'  },
  { key: 'z5', label: 'Z5', description: 'Max',       color: '#ef4444', bg: 'rgba(239,68,68,0.06)'   },
] as const

/** Zone colours, indexed 0-4 (Z1–Z5). Derived from ZONES — do not re-declare locally. */
export const ZONE_COLORS: readonly string[] = ZONES.map((z) => z.color)

/** Faint zone band fills, indexed 0-4 (Z1–Z5). */
export const ZONE_BG: readonly string[] = ZONES.map((z) => z.bg)

function assignZone(
  bpm: number,
  maxHR: number,
  boundaries: number[] = DEFAULT_ZONE_BOUNDARIES
): 0 | 1 | 2 | 3 | 4 {
  const pct = bpm / maxHR
  for (let i = 0; i < boundaries.length; i++) {
    if (pct < boundaries[i]) return i as 0 | 1 | 2 | 3 | 4
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

/**
 * Banister zone-minute weights for the 5-zone Friel model.
 * Non-linear: higher zones impose disproportionately more physiological stress.
 */
export const BANISTER_ZONE_WEIGHTS = [1.0, 1.5, 2.0, 3.0, 4.5] as const

/**
 * Compute TRIMP (Training Impulse) using Banister zone-minute weighting.
 * Formula: Σ(minutes_in_zone_i × weight_i)
 */
export function computeTRIMP(zones: HRZoneDistribution, durationMin: number): number {
  const pcts = [zones.z1, zones.z2, zones.z3, zones.z4, zones.z5]
  return Math.round(
    pcts.reduce((sum, pct, i) => sum + (pct / 100) * durationMin * BANISTER_ZONE_WEIGHTS[i], 0)
  )
}

/**
 * Resolve effective max HR.
 * Priority: manual override → 220-age from DOB → 190 default.
 */
export function getEffectiveMaxHR(dob: string | null, override?: number | null): number {
  if (override != null && override > 0) return override
  return maxHRFromDOB(dob) ?? 190
}

/**
 * Convert zone boundary fractions to absolute bpm values.
 * Returns 4 bpm values (the upper edge of Z1, Z2, Z3, Z4).
 */
export function zoneBoundariesToBpm(
  maxHR: number,
  boundaries: number[] = DEFAULT_ZONE_BOUNDARIES
): number[] {
  return boundaries.map((b) => Math.round(b * maxHR))
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

function estimateZonesFromSummary(
  maxHR: number,
  avg: number,
  max: number,
  boundaries: number[]
): HRZoneDistribution {
  const std = Math.max((max - avg) / 2.5, 1)
  const bpmBounds = [0, ...boundaries.map((f) => f * maxHR), Infinity]
  const raw: number[] = []
  for (let i = 0; i < 5; i++) {
    const lo = bpmBounds[i]
    const hi = bpmBounds[i + 1]
    const pLo = lo === 0 ? 0 : normalCDF(lo, avg, std)
    const pHi = hi === Infinity ? 1 : normalCDF(hi, avg, std)
    raw.push(Math.max(0, pHi - pLo))
  }
  const total = raw.reduce((a, b) => a + b, 0) || 1
  const pct = raw.map((v) => Math.round((v / total) * 100))
  const diff = 100 - pct.reduce((a, b) => a + b, 0)
  pct[pct.indexOf(Math.max(...pct))] += diff
  return { z1: pct[0], z2: pct[1], z3: pct[2], z4: pct[3], z5: pct[4], method: 'summary_estimate' }
}

/**
 * Compute HR zone distribution.
 * @param maxHR            Maximum heart rate in bpm
 * @param samples          Time-series HR samples (may be empty)
 * @param avgHR            Fallback average HR when samples are unavailable
 * @param boundaries       Zone upper boundaries as fractions of maxHR (default: Friel 60/70/80/90%)
 * @param observedMaxHR    Workout peak HR (used as spread parameter in summary estimation instead of
 *                         the athlete ceiling, which would over-inflate Z4/Z5 for easy sessions)
 */
export function computeHRZones(
  maxHR: number,
  samples: HRSample[],
  avgHR?: number,
  boundaries: number[] = DEFAULT_ZONE_BOUNDARIES,
  observedMaxHR?: number
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
      const z = assignZone(sorted[i].bpm, maxHR, boundaries)
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

  const avg = avgHR ?? maxHR * 0.72
  const max = observedMaxHR ?? samples[0]?.bpm ?? maxHR
  return estimateZonesFromSummary(maxHR, avg, max, boundaries)
}

/** Derive max HR from date of birth using 220-age formula. Returns undefined if dob is null. */
export function maxHRFromDOB(dob: string | null): number | undefined {
  if (!dob) return undefined
  const birthYear = new Date(dob).getFullYear()
  const age = new Date().getFullYear() - birthYear
  return 220 - age
}

// ── Aerobic Decoupling ────────────────────────────────────────────────────────

export interface DecouplingResult {
  pct: number
  label: 'efficient' | 'moderate' | 'high'
  color: 'green' | 'amber' | 'red'
}

/**
 * Compute Aerobic Decoupling (Pa:HR — Pace:Heart Rate ratio drift).
 * Splits the workout into two halves by time, computes (avg pace / avg HR)
 * for each half, then measures the % drift between halves.
 *
 * Thresholds: <5% = efficient aerobic base, 5–10% = moderate drift, >10% = high drift.
 * Returns null when GPS speed data or HR samples are insufficient (<20 matched pairs).
 */
export function computeAerobicDecoupling(
  gpsTrack: GPSPoint[],
  hrSamples: HRSample[]
): DecouplingResult | null {
  const MIN_PAIRS_PER_HALF = 10
  const SPEED_THRESHOLD_MPS = 0.3   // ignore GPS points at near-standstill
  const HR_MATCH_WINDOW_S  = 10     // max seconds between GPS and HR sample timestamps

  // Build sorted timestamp index for HR samples (unix ms)
  const hrSorted = [...hrSamples]
    .map((s) => ({ ts: new Date(s.timestamp).getTime(), bpm: s.bpm }))
    .filter((s) => !isNaN(s.ts))
    .sort((a, b) => a.ts - b.ts)

  if (hrSorted.length === 0) return null

  // For each GPS point with valid speed, find the nearest HR sample within the window
  const pairs: { pace: number; hr: number }[] = []
  for (const pt of gpsTrack) {
    const speed = pt.speed ?? null
    if (speed === null || speed < SPEED_THRESHOLD_MPS) continue
    const ptTs = new Date(pt.timestamp).getTime()
    if (isNaN(ptTs)) continue

    // Binary-search for the closest HR sample
    let lo = 0
    let hi = hrSorted.length - 1
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (hrSorted[mid].ts < ptTs) lo = mid + 1
      else hi = mid
    }
    const candidates = [hrSorted[lo], lo > 0 ? hrSorted[lo - 1] : null].filter(Boolean) as typeof hrSorted
    const nearest = candidates.reduce((best, c) =>
      Math.abs(c.ts - ptTs) < Math.abs(best.ts - ptTs) ? c : best
    )
    if (Math.abs(nearest.ts - ptTs) > HR_MATCH_WINDOW_S * 1000) continue

    pairs.push({ pace: 1000 / speed, hr: nearest.bpm })
  }

  if (pairs.length < MIN_PAIRS_PER_HALF * 2) return null

  const mid = Math.floor(pairs.length / 2)
  const h1 = pairs.slice(0, mid)
  const h2 = pairs.slice(mid)

  const mean = (arr: number[]) => arr.reduce((s, v) => s + v, 0) / arr.length

  const ratio1 = mean(h1.map((p) => p.pace)) / mean(h1.map((p) => p.hr))
  const ratio2 = mean(h2.map((p) => p.pace)) / mean(h2.map((p) => p.hr))

  if (ratio2 === 0) return null

  const pct = Math.abs((ratio1 / ratio2 - 1) * 100)

  return {
    pct,
    label: pct < 5 ? 'efficient' : pct < 10 ? 'moderate' : 'high',
    color: pct < 5 ? 'green' : pct < 10 ? 'amber' : 'red',
  }
}
