/**
 * Readiness types, as the server reports them.
 *
 * This file used to carry a client-side `computeReadiness` — a four-component
 * fork of the server's five-component score (no TSB) with no callers. The one
 * definition is GET /api/health/readiness; ReadinessWidget renders its result.
 */
export type ReadinessFlag =
  | 'elevated_rhr_3d'
  | 'suppressed_hrv_3d'
  | 'high_accumulated_fatigue'
  | 'insufficient_sleep'
  | 'poor_sleep_3d'
  | 'insufficient_data'
  | 'overreached'

export interface ReadinessResult {
  score: number // 0–100
  status: 'green' | 'yellow' | 'red'
  flags: ReadinessFlag[]
  components: { rhr: number; hrv: number; fatigue: number; sleep: number; tsb?: number }
}
