/**
 * Traffic-light status for score widgets — readiness, development, progression.
 *
 * This is a distinct axis from completion (lib/completionColors.ts): it says how
 * well something is going, not whether it is finished. Green here and emerald
 * there are deliberately the same hue family — both read as "no action needed" —
 * but they are never rendered on the same mark.
 *
 * Extracted after finding this exact triplet duplicated verbatim in
 * ReadinessWidget, AdherenceWidget and ProgressionReviewCard. `label` stays
 * with the consumer: the scale is shared, the vocabulary is not ("Ready" vs
 * "On Track" vs "Ahead").
 *
 * The colours are the `--good` / `--warn` / `--bad` tokens (styles/globals.css),
 * each theme's own and AA as text on its page — docs/frontend-design.md §8.12.
 * A component writes `text-good`, `bg-warn/10`, or takes a constant from here.
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
    ring: 'ring-good/30',
    score: 'text-good',
    badge: 'bg-good/10 text-good border-good/30',
  },
  yellow: {
    ring: 'ring-warn/30',
    score: 'text-warn',
    badge: 'bg-warn/10 text-warn border-warn/30',
  },
  red: {
    ring: 'ring-bad/30',
    score: 'text-bad',
    badge: 'bg-bad/10 text-bad border-bad/30',
  },
}

/** Bare text colour for a status, when only the text is being tinted. */
export const STATUS_TEXT: Record<StatusLevel, string> = {
  green: 'text-good',
  yellow: 'text-warn',
  red: 'text-bad',
}

/** A status dot or bar fill. Always beside a word: colour is never the only sign. */
export const STATUS_FILL: Record<StatusLevel, string> = {
  green: 'bg-good',
  yellow: 'bg-warn',
  red: 'bg-bad',
}

/** The same three in SVG and inline styles, where a class cannot reach. */
export const STATUS_CSS: Record<StatusLevel, string> = {
  green: 'var(--good)',
  yellow: 'var(--warn)',
  red: 'var(--bad)',
}
