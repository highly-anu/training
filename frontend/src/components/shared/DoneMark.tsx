import { AnimatePresence, motion } from 'framer-motion'
import { doneIn } from '@/lib/motion'

/**
 * The completion moment (docs/frontend-design.md §11.8): the mark of a thing
 * that has just been done scales in, once, where the athlete is looking. It
 * does not play for what was already done when the screen opened, and undoing
 * it puts the open mark back without ceremony.
 *
 *   <DoneMark done={complete} doneIcon={<CheckCircle2 />} openIcon={<Circle />} />
 */
export function DoneMark({ done, doneIcon, openIcon = null, className }: {
  done: boolean
  doneIcon: React.ReactNode
  /** What stands there while it is not done; nothing by default. */
  openIcon?: React.ReactNode
  className?: string
}) {
  return (
    <AnimatePresence initial={false} mode="popLayout">
      {done
        ? <motion.span key="done" className={className ?? 'inline-flex'} {...doneIn}>{doneIcon}</motion.span>
        : openIcon != null && <span key="open" className={className ?? 'inline-flex'}>{openIcon}</span>}
    </AnimatePresence>
  )
}
