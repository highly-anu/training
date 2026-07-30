/**
 * Traffic-light status for score widgets — readiness, development, progression.
 *
 * This is a distinct axis from completion (lib/completionColors.ts): it says how
 * well something is going, not whether it is finished. Green here and emerald
 * there are deliberately the same hue family — both read as "no action needed" —
 * but they are never rendered on the same mark.
 *
 * Extracted after finding this exact triplet duplicated verbatim in
 * ReadinessWidget, DevelopmentWidget and ProgressionReviewCard. `label` stays
 * with the consumer: the scale is shared, the vocabulary is not ("Ready" vs
 * "On Track" vs "Ahead").
 *
 * Text shades pair -700 (light) with -300 (dark) — see docs/frontend-design.md
 * §8.8 for the contrast measurements that forced this.
 */
export type StatusLevel = 'green' | 'yellow' | 'red'

export interface StatusStyle {
  /** Ring around the score dial. */
  ring: string
  /** Large numeric score. Pair with `tabular-nums` so digits don't jitter. */
  score: string
  /** Pill badge beside the score. */
  badge: string
}

export const STATUS_STYLES: Record<StatusLevel, StatusStyle> = {
  green: {
    ring: 'ring-emerald-500/30',
    score: 'text-emerald-700 dark:text-emerald-300',
    badge: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30',
  },
  yellow: {
    ring: 'ring-amber-500/30',
    score: 'text-amber-700 dark:text-amber-300',
    badge: 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30',
  },
  red: {
    ring: 'ring-red-500/30',
    score: 'text-red-700 dark:text-red-300',
    badge: 'bg-red-500/10 text-red-700 dark:text-red-300 border-red-500/30',
  },
}

/** Bare text colour for a status, when only the text is being tinted. */
export const STATUS_TEXT: Record<StatusLevel, string> = {
  green: 'text-emerald-700 dark:text-emerald-300',
  yellow: 'text-amber-700 dark:text-amber-300',
  red: 'text-red-700 dark:text-red-300',
}
