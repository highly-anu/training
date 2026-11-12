import { useState, type ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { tabVariants } from '@/lib/motion'
import { tabDomId } from '@/components/layout/SubTabs'

interface TabPanelsProps<T extends string> {
  /** The selected tab. */
  active: T
  /** Every tab id in the order the selector shows them. */
  order: readonly T[]
  /** The `id` given to `<SubTabs>`, so the panel is labelled by its tab. */
  tabsId?: string
  /** The panel's own classes (its height and scroll). */
  className?: string
  children: ReactNode
}

/**
 * The body under a `<SubTabs>`: the panel leaving fades out and the new one
 * comes in from the side of the tab that was picked, so a switch reads as
 * moving along the row (docs/frontend-design.md §11.9). Nothing moves on first
 * paint.
 */
export function TabPanels<T extends string>({ active, order, tabsId, className, children }: TabPanelsProps<T>) {
  const [shown, setShown] = useState(active)
  const [direction, setDirection] = useState(1)
  if (shown !== active) {
    setDirection(order.indexOf(active) < order.indexOf(shown) ? -1 : 1)
    setShown(active)
  }

  return (
    <AnimatePresence mode="wait" initial={false} custom={direction}>
      <motion.div
        key={active}
        role="tabpanel"
        aria-labelledby={tabsId ? tabDomId(tabsId, active) : undefined}
        custom={direction}
        variants={tabVariants}
        initial="enter"
        animate="center"
        exit="exit"
        className={className}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  )
}
