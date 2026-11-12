/**
 * Completion state — one colour owns "done" across the whole app: the `--done`
 * token (emerald, tuned per theme in styles/globals.css).
 *
 * Previously written inline at ~130 call sites as raw emerald classes, which is
 * how the light-mode contrast bug went unnoticed and how emerald came to mean
 * six other things. A component writes `text-done` / `bg-done/10` or takes a
 * constant from here; a raw emerald or green class fails the design test
 * (docs/frontend-design.md §8.3, §8.12).
 *
 * Do not use these for "good / positive / on track" verdicts — that is a
 * separate axis with its own module (lib/statusColors.ts). Completion means the
 * work is finished, not that it went well.
 */
export const COMPLETION = {
  /** Card/panel surface for a completed item. */
  border: 'border-done/30',
  bg: 'bg-done/5',
  /** Stronger fill for interactive completed elements (buttons, toggles). */
  bgStrong: 'bg-done/10',
  hover: 'hover:bg-done/20',
  /** Text + icon colour. */
  text: 'text-done',
  /** Chart/SVG fills and inline styles, where a Tailwind class won't do. */
  css: 'var(--done)',
} as const

/** Complete-state surface for a card: border + subtle fill + text. */
export const COMPLETION_SURFACE = `${COMPLETION.border} ${COMPLETION.bg} ${COMPLETION.text}`

/** Complete-state surface for an interactive control: stronger fill + hover. */
export const COMPLETION_INTERACTIVE =
  `${COMPLETION.border} ${COMPLETION.bgStrong} ${COMPLETION.text} ${COMPLETION.hover}`
