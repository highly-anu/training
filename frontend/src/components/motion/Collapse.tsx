import type { ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { collapseMotion } from '@/lib/motion'
import { cn } from '@/lib/utils'

/**
 * A block that opens downward under its trigger and closes again, the rows
 * below moving with it (docs/frontend-design.md §11.9). The trigger carries
 * `aria-expanded`; this is only the body.
 */
export function Collapse({ open, children, className }: { open: boolean; children: ReactNode; className?: string }) {
  return (
    <AnimatePresence initial={false}>
      {open && (
        <motion.div {...collapseMotion} className={cn('overflow-hidden', className)}>
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  )
}
