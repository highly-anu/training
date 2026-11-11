import { useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { rollMotion } from '@/lib/motion'
import { cn } from '@/lib/utils'

interface RollingNumberProps {
  /** What is shown: "3/5", "72", "4:58". */
  value: string | number
  /** What decides the direction when `value` is text; defaults to `value` itself. */
  order?: number
  className?: string
}

/**
 * A number that changes on screen rolls to its new value — up when it grew,
 * down when it fell — so the eye sees *that* it changed and which way
 * (docs/frontend-design.md §11.9). Only for a value that changes while it is
 * looked at: done of due, readiness, a total under a period switch. A number
 * that is simply there is plain text.
 *
 * It does not roll on first paint, and under Reduce Motion the old value fades
 * to the new one (`MotionConfig` drops the movement).
 */
export function RollingNumber({ value, order, className }: RollingNumberProps) {
  const rank = order ?? (typeof value === 'number' ? value : Number.parseFloat(value))
  const [shown, setShown] = useState({ value, rank })
  const [direction, setDirection] = useState<1 | -1>(1)
  if (shown.value !== value) {
    setDirection(Number.isFinite(rank) && Number.isFinite(shown.rank) && rank < shown.rank ? -1 : 1)
    setShown({ value, rank })
  }

  return (
    <span className={cn('relative inline-flex overflow-hidden tabular-nums align-bottom', className)}>
      <AnimatePresence mode="popLayout" initial={false}>
        <motion.span key={String(value)} className="inline-block" {...rollMotion(direction)}>
          {value}
        </motion.span>
      </AnimatePresence>
    </span>
  )
}
