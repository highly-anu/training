/**
 * How to name the source a workout came from.
 *
 * This replaces five inline ternaries that had drifted apart — the same
 * `fit_file` workout read as ".fit file" on a session card and "FIT" in an
 * analytics filter pill, and two of the five fell through to naming an unknown
 * source "Strava" or "GPS", which is how a `garmin` workout (written by the
 * Connect IQ app for months) ended up mislabelled.
 *
 * Three forms, because the call sites genuinely need three:
 *   label  — prose, for cards and dialogs        (".fit file")
 *   short  — filter pills and chips              ("FIT")
 *   badge  — the 9px inline badge on dense rows  ("FIT")
 * Keeping `badge` separate is what lets tight rows stay tight; don't collapse
 * it into `short` without checking MatchedSessionCard at a narrow width.
 */

export interface SourceMeta {
  label: string
  short: string
  badge: string
}

const SOURCE_META: Record<string, SourceMeta> = {
  garmin: { label: 'Garmin', short: 'Garmin', badge: 'GRMN' },
  fit_file: { label: '.fit file', short: 'FIT', badge: 'FIT' },
  strava: { label: 'Strava', short: 'Strava', badge: 'Strava' },
  apple_health: { label: 'Apple Health', short: 'Apple Health', badge: 'GPS' },
  apple_watch_live: { label: 'Apple Watch Live', short: 'Apple Health', badge: 'GPS' },
  watch: { label: 'Watch', short: 'Watch', badge: 'GPS' },
  manual: { label: 'Manual', short: 'Manual', badge: 'Manual' },
}

/** An unrecognised source shows its raw value rather than being mislabelled as
 *  a specific service — that is the bug this module exists to stop. */
function meta(source: string): SourceMeta {
  return SOURCE_META[source] ?? { label: source, short: source, badge: 'GPS' }
}

export function sourceLabel(source: string): string {
  return meta(source).label
}

export function sourceShortLabel(source: string): string {
  return meta(source).short
}

export function sourceBadgeLabel(source: string): string {
  return meta(source).badge
}

/** Sources the athlete can connect and auto-import from, in display order.
 *  Keys match `integrations.sources` in the server profile. */
export const CONNECTABLE_SOURCES = [
  {
    key: 'garmin' as const,
    name: 'Garmin',
    description: 'Activities recorded on your Garmin watch, pushed here as soon as they sync.',
  },
  {
    key: 'strava' as const,
    name: 'Strava',
    description: 'Anything that reaches Strava, including Garmin, Suunto and Polar.',
  },
  {
    key: 'appleHealth' as const,
    name: 'Apple Health',
    description: 'Workouts other apps write to Apple Health. Imported by the iPhone app.',
  },
]

export type ConnectableSource = (typeof CONNECTABLE_SOURCES)[number]['key']
