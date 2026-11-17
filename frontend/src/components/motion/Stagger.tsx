import { Children, type ReactNode } from 'react'
import { motion } from 'framer-motion'
import { riseIn, type StaggerDensity } from '@/lib/motion'

interface StaggerProps {
  children: ReactNode
  density?: StaggerDensity
  /** The list's own classes (its grid or stack). */
  className?: string
  /** Each item's wrapper. */
  itemClassName?: string
}

/**
 * A list arriving: each child rises in after the one before it, and past the
 * eighth they arrive together (`stagger` in lib/motion). For the first paint of
 * a screen's cards — a row that joins later is `PresenceList`'s.
 */
export function Stagger({ children, density = 'normal', className, itemClassName }: StaggerProps) {
  return (
    <div className={className}>
      {Children.toArray(children).map((child, i) => (
        <motion.div key={(child as { key?: string | null }).key ?? i} {...riseIn(i, density)} className={itemClassName}>
          {child}
        </motion.div>
      ))}
    </div>
  )
}
