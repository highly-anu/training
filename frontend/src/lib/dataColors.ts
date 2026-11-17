/**
 * Data colours that are not a modality, a phase, a heart-rate zone or a
 * movement — those have their own modules. Hue here is data: a series, a
 * scale step, a category. It never says "done" (`--done`,
 * lib/completionColors.ts) and never gives a verdict (`--good` / `--warn` /
 * `--bad`, lib/statusColors.ts).
 *
 * A component writes no hex of its own (docs/frontend-design.md §8.12): a new
 * series or scale gets a name here.
 */

/** A category the tables do not know. */
export const FALLBACK_HEX = '#6366f1'
/** No category at all: unassigned, other, a missing phase. */
export const NEUTRAL_HEX = '#94a3b8'
export const UNASSIGNED_HEX = '#475569'

/** A week's load against the athlete's median, and a week's session count. */
export const LOAD_STEPS = [
  { key: 'light', label: 'Light', hex: '#10b981' },
  { key: 'normal', label: 'Normal', hex: '#38bdf8' },
  { key: 'heavy', label: 'Heavy', hex: '#f59e0b' },
  { key: 'overload', label: 'Overload', hex: '#ef4444' },
] as const

/** An exercise's effort, low → max. */
export const EFFORT_HEX: Record<string, string> = {
  low: '#10b981',
  medium: '#f59e0b',
  high: '#f97316',
  max: '#ef4444',
}

/** A modality's recovery cost. */
export const RECOVERY_COST_HEX: Record<string, string> = {
  low: '#10b981',
  medium: '#f59e0b',
  high: '#ef4444',
}

/** A framework's priority tiers. */
export const TIER_HEX: Record<string, string> = {
  committed: '#ef4444',
  core: '#f97316',
  supplementary: '#64748b',
}

/** The volume summary's four buckets. */
export const VOLUME_HEX = {
  Strength: '#ef4444',
  Conditioning: '#0ea5e9',
  Durability: '#f59e0b',
  Mobility: '#10b981',
} as const

/** Chart series, by what they measure. */
export const SERIES = {
  hrv: '#38bdf8',
  hrvBaseline: '#0ea5e9',
  restingHr: '#ef4444',
  fitness: '#3b82f6',
  fatigue: '#f97316',
  elevation: '#14b8a6',
  threshold: '#f97316',
  planned: '#6366f1',
  result: '#10b981',
  sleepDeep: '#1d4ed8',
  sleepRem: '#7c3aed',
  sleepLight: '#38bdf8',
  sleepAwake: '#6b7280',
  /** The hover band behind a bar. */
  cursor: '#888888',
} as const

/** A recorded route: the track, where it starts and where it ends. */
export const ROUTE = {
  track: '#38bdf8',
  start: '#22c55e',
  end: '#ef4444',
} as const

/** The builder's three ways to start. */
export const SOURCE_MODE_HEX = {
  philosophy: '#8b5cf6',
  blend: '#6366f1',
  custom: '#10b981',
} as const

/** Another company's mark, in its colour. */
export const BRAND = {
  strava: '#FC4C02',
  onStrava: '#ffffff',
} as const

/** An exercise category, as text. The hexes are lib/exploreColors.ts's. */
export const EXERCISE_CATEGORY_TEXT: Record<string, string> = {
  barbell: 'text-red-700 dark:text-red-300',
  kettlebell: 'text-orange-700 dark:text-orange-300',
  bodyweight: 'text-emerald-700 dark:text-emerald-300',
  aerobic: 'text-sky-700 dark:text-sky-300',
  carries: 'text-amber-700 dark:text-amber-300',
  sandbag: 'text-yellow-700 dark:text-yellow-300',
  mobility: 'text-teal-700 dark:text-teal-300',
  skill: 'text-violet-700 dark:text-violet-300',
  rehab: 'text-lime-700 dark:text-lime-300',
}

/** The five-step fatigue rating, 1 fresh → 5 cooked. */
export const FATIGUE_STEP: Record<1 | 2 | 3 | 4 | 5, string> = {
  1: 'border-emerald-500 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300',
  2: 'border-green-500 bg-green-500/10 text-green-700 dark:text-green-300',
  3: 'border-amber-500 bg-amber-500/10 text-amber-700 dark:text-amber-300',
  4: 'border-orange-500 bg-orange-500/10 text-orange-700 dark:text-orange-300',
  5: 'border-red-500 bg-red-500/10 text-red-700 dark:text-red-300',
}

/** A low / medium / high scale as a badge (recovery cost). */
export const SCALE_BADGE: Record<'low' | 'medium' | 'high', string> = {
  low: 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300',
  medium: 'bg-amber-500/15 text-amber-700 dark:text-amber-300',
  high: 'bg-red-500/15 text-red-700 dark:text-red-300',
}

/** The Log's totals, one hue a quantity. */
export const KPI_TEXT = {
  time: 'text-sky-700 dark:text-sky-300',
  distance: 'text-emerald-700 dark:text-emerald-300',
  ascended: 'text-amber-700 dark:text-amber-300',
  descended: 'text-rose-700 dark:text-rose-300',
  calories: 'text-orange-700 dark:text-orange-300',
} as const

/** A recorded workout's figures, one hue an icon: the quantity, never a verdict. */
export const METRIC_ICON = {
  heartRate: 'text-red-700 dark:text-red-300',
  effort: 'text-amber-700 dark:text-amber-300',
  calories: 'text-orange-700 dark:text-orange-300',
  distance: 'text-blue-700 dark:text-blue-300',
  descent: 'text-rose-700 dark:text-rose-300',
} as const
