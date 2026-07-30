/**
 * Completion state — one colour owns "done" across the whole app: emerald.
 *
 * Previously written inline at ~20 call sites with no shared module, which is
 * how the light-mode contrast bug went unnoticed: the bare `text-emerald-500`
 * measures 2.33:1 on a /10 emerald tint over white, against a WCAG AA floor of
 * 4.5:1. Text shades are a PAIR pulling away from their own background — -700
 * for light, -300 for dark. See docs/frontend-design.md §8.3.
 *
 * Do not use these for "good / positive / on track" verdicts — that is a
 * separate axis with its own module (lib/statusColors.ts). Completion means the
 * work is finished, not that it went well.
 */
export const COMPLETION = {
  /** Card/panel surface for a completed item. */
  border: 'border-emerald-500/30',
  bg: 'bg-emerald-500/5',
  /** Stronger fill for interactive completed elements (buttons, toggles). */
  bgStrong: 'bg-emerald-500/10',
  hover: 'hover:bg-emerald-500/20',
  /** Text + icon colour. Always use this rather than a bare emerald class. */
  text: 'text-emerald-700 dark:text-emerald-300',
  /** Chart/SVG fills and inline styles, where a Tailwind class won't do. */
  hex: '#10b981',
} as const

/** Complete-state surface for a card: border + subtle fill + text. */
export const COMPLETION_SURFACE = `${COMPLETION.border} ${COMPLETION.bg} ${COMPLETION.text}`

/** Complete-state surface for an interactive control: stronger fill + hover. */
export const COMPLETION_INTERACTIVE =
  `${COMPLETION.border} ${COMPLETION.bgStrong} ${COMPLETION.text} ${COMPLETION.hover}`
