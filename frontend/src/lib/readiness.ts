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

/** Where a scored component's data came from: `daily_bio` is the Apple Health
 *  relay and the daily check-ins, `garmin_ciq` the Connect IQ watch. */
export type ReadinessSource = 'daily_bio' | 'garmin_ciq'

export interface ReadinessResult {
  score: number // 0–100
  status: 'green' | 'yellow' | 'red'
  flags: ReadinessFlag[]
  components: { rhr: number; hrv: number; fatigue: number; sleep: number; tsb?: number }
  /** Absent from servers older than the wellness merge. */
  sources?: { rhr: ReadinessSource | null; hrv: ReadinessSource | null; sleep: ReadinessSource | null }
}

const SOURCE_LABEL: Record<ReadinessSource, string> = {
  daily_bio: 'Apple Health and check-ins',
  // The watch's series is its overnight heart-rate low, not Garmin's daily
  // resting HR (the SDK does not expose that; src/wellness.merge_for_scoring).
  garmin_ciq: "your Garmin watch's heart-rate low",
}

/**
 * One line naming where readiness took its resting HR, HRV and sleep from, or
 * null when the server did not say or nothing was scored. Resting HR comes
 * from one series only (src/wellness.merge_for_scoring), so a watch and Apple
 * Health are never mixed — the footnote says which one won.
 */
export function readinessSourceNote(sources: ReadinessResult['sources']): string | null {
  if (!sources) return null
  const names = { rhr: 'resting HR', hrv: 'HRV', sleep: 'sleep' } as const
  const bySource = new Map<ReadinessSource, string[]>()
  for (const k of ['rhr', 'hrv', 'sleep'] as const) {
    const src = sources[k]
    if (src) bySource.set(src, [...(bySource.get(src) ?? []), names[k]])
  }
  if (bySource.size === 0) return null
  const list = (xs: string[]) => (xs.length > 1 ? `${xs.slice(0, -1).join(', ')} and ${xs[xs.length - 1]}` : xs[0])
  const text = [...bySource].map(([src, xs]) => `${list(xs)} from ${SOURCE_LABEL[src]}`).join('; ')
  return text.charAt(0).toUpperCase() + text.slice(1) + '.'
}
