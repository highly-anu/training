/**
 * Motion — the one file that writes a duration, an easing or a spring.
 *
 * The presets carry the phone's names and feel (ios/docs/design-system.md §7,
 * `AppAnimation`), so a card settles the same way on both clients. A component
 * picks a preset by what the motion is *for*; it never types a number.
 * `test/designRules.test.ts` fails on a `transition` literal anywhere else.
 *
 * Motion has three jobs (docs/frontend-design.md §1.7): it orients (where did
 * this come from), it answers (your tap was taken), it shows what changed.
 * Anything that does none of them is not animated.
 *
 * Reduce Motion: `<MotionConfig reducedMotion="user">` (App.tsx) drops every
 * transform and keeps opacity, so each preset below degrades to a fade by
 * itself. CSS transitions and tw-animate are handled by the one
 * `prefers-reduced-motion` block in styles/globals.css.
 *
 * The CSS twins of the durations and easings are `--motion-fast|base|slow` and
 * `--ease-standard|exit` in globals.css; keep the two in step.
 */
import type { Transition, Variants } from 'framer-motion'

// ── durations and easings (seconds; CSS twins in globals.css) ───────────────

const FAST = 0.15
const BASE = 0.25
const SLOW = 0.4

/** Decelerate into place: things arriving, state changing. */
const EASE_STANDARD = [0.2, 0, 0, 1] as const
/** Accelerate away: things leaving. */
const EASE_EXIT = [0.4, 0, 1, 1] as const

// ── transitions ─────────────────────────────────────────────────────────────

/** Most state changes: a card settling, a detail opening. */
export const springStandard: Transition = { type: 'spring', duration: 0.45, bounce: 0.18 }

/** Small, quick answers: a press, a toggle, a check. */
export const springSnappy: Transition = { type: 'spring', duration: 0.35, bounce: 0.14 }

/** Size and position changes: a row expanding, a panel opening, a list reordering. */
export const layoutChange: Transition = { type: 'spring', duration: 0.5, bounce: 0.12 }

/** Content swapping in place. Also what every spring becomes under Reduce Motion. */
export const crossfade: Transition = { duration: 0.2, ease: 'easeInOut' }

/** A chart or bar drawing once: no bounce — data never overshoots. */
export const chartEntry: Transition = { type: 'spring', duration: 0.7, bounce: 0 }

/** The same draw for a library that takes milliseconds (Recharts, through lib/chartMotion.ts). */
export const CHART_ENTRY_MS = 700

/** A page arriving and leaving. */
export const pageEnter: Transition = { duration: BASE, ease: EASE_STANDARD }
export const pageExit: Transition = { duration: FAST, ease: EASE_EXIT }

/** An endless indicator (the loader's travelling stroke), one lap in `seconds`. */
export function loop(seconds: number): Transition {
  return { duration: seconds, repeat: Infinity, ease: 'linear' }
}

// ── props, spread onto a motion element ─────────────────────────────────────

/** A page root: rises in, leaves upward. `components/layout/Page.tsx` carries it. */
export const pageMotion = {
  initial: { opacity: 0, y: 16 },
  animate: { opacity: 1, y: 0, transition: pageEnter },
  exit: { opacity: 0, y: -8, transition: pageExit },
} as const

/** A page root that only fades (a loading screen: nothing has arrived yet). */
export const fadeMotion = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: crossfade },
  exit: { opacity: 0, transition: pageExit },
} as const

/** How tightly a list's items follow one another. */
export type StaggerDensity = 'tight' | 'normal' | 'loose'
const STAGGER_STEP: Record<StaggerDensity, number> = { tight: 0.03, normal: 0.04, loose: 0.06 }
/** Past this many items the rest arrive together: a long list never makes you wait. */
const STAGGER_CAP = 8

/** The delay before item `index` of a list arrives. */
export function stagger(index: number, density: StaggerDensity = 'normal'): number {
  return Math.min(Math.max(index, 0), STAGGER_CAP) * STAGGER_STEP[density]
}

/** One item arriving: fades and rises, after its place in the list. */
export function riseIn(index = 0, density: StaggerDensity = 'normal') {
  return {
    initial: { opacity: 0, y: 8 },
    animate: { opacity: 1, y: 0, transition: { ...pageEnter, delay: stagger(index, density) } },
  } as const
}

/** A block swapping for another in place (a builder panel, an inline form). */
export const swapMotion = {
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0, transition: pageEnter },
  exit: { opacity: 0, y: -4, transition: pageExit },
} as const

/** Something sliding in beside its trigger (a "next week" chip). */
export const nudgeIn = {
  initial: { opacity: 0, x: 8 },
  animate: { opacity: 1, x: 0, transition: springSnappy },
} as const

/** A floating panel over a canvas (Dev Lab): fades and rises a little, both ways. */
export const floatMotion = {
  initial: { opacity: 0, y: 6 },
  animate: { opacity: 1, y: 0, transition: crossfade },
  exit: { opacity: 0, y: 6, transition: pageExit },
} as const

/** Content appearing with no movement (a media frame once it has loaded). */
export const fadeIn = {
  initial: { opacity: 0 },
  animate: { opacity: 1, transition: { duration: SLOW, ease: EASE_STANDARD } },
} as const

/** A row opening downward and closing again. Wrap in `AnimatePresence`. */
export const collapseMotion = {
  initial: { opacity: 0, height: 0 },
  animate: { opacity: 1, height: 'auto' },
  exit: { opacity: 0, height: 0 },
  transition: layoutChange,
} as const

/** A side panel opening to `width` px beside the content. Wrap in `AnimatePresence`. */
export function panelMotion(width: number) {
  return {
    initial: { width: 0 },
    animate: { width },
    exit: { width: 0 },
    transition: layoutChange,
  } as const
}

/** A card that opens something: lifts under the pointer, gives under the press. */
export const pressMotion = {
  whileHover: { scale: 1.02 },
  whileTap: { scale: 0.98 },
  transition: springSnappy,
} as const

/** The mark of something just done: scales in once, in the standard spring. */
export const doneIn = {
  initial: { scale: 0.4, opacity: 0 },
  animate: { scale: 1, opacity: 1 },
  transition: springStandard,
} as const

/** A small control that is ticked (a set's check): pops under the press. */
export const tickMotion = {
  whileTap: { scale: 1.3 },
  transition: springSnappy,
} as const

/** The selected tab's pill sliding to its new place (a shared `layoutId`). */
export const pillMotion = { transition: springSnappy } as const

/** A row joining or leaving a list: the others close the gap. Wrap in `AnimatePresence`. */
export const rowMotion = {
  layout: true,
  initial: { opacity: 0, height: 0 },
  animate: { opacity: 1, height: 'auto' },
  exit: { opacity: 0, height: 0 },
  transition: layoutChange,
} as const

/** A number replaced by its new value: the new one comes from the side it moved to. */
export function rollMotion(direction: 1 | -1) {
  return {
    initial: { y: 8 * direction, opacity: 0 },
    animate: { y: 0, opacity: 1, transition: springSnappy },
    exit: { y: -8 * direction, opacity: 0, transition: pageExit },
  } as const
}

// ── variants ────────────────────────────────────────────────────────────────

/** A tab's panel: comes from the side of the tab that was picked (`custom` = 1 | -1). */
export const tabVariants: Variants = {
  enter: (direction: number) => ({ opacity: 0, x: 12 * direction }),
  center: { opacity: 1, x: 0, transition: pageEnter },
  exit: (direction: number) => ({ opacity: 0, x: -12 * direction, transition: pageExit }),
}

/** A list whose children arrive one after another: `initial="hidden" animate="visible"`. */
export function staggerVariants(density: StaggerDensity = 'normal'): { list: Variants; item: Variants } {
  return {
    list: { hidden: {}, visible: { transition: { staggerChildren: STAGGER_STEP[density] } } },
    item: { hidden: { opacity: 0, x: -8 }, visible: { opacity: 1, x: 0, transition: pageEnter } },
  }
}

/** A wizard step: the next one comes from the side you are heading to. */
export function stepVariants(direction: 'forward' | 'backward'): Variants {
  const from = direction === 'forward' ? 60 : -60
  return {
    enter: { x: from, opacity: 0 },
    center: { x: 0, opacity: 1, transition: pageEnter },
    exit: { x: -from, opacity: 0, transition: pageExit },
  }
}
