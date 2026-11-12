import type { Key, ReactNode } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { rowMotion } from '@/lib/motion'
import { cn } from '@/lib/utils'

interface PresenceListProps<T> {
  items: T[]
  keyOf: (item: T) => Key
  children: (item: T, index: number) => ReactNode
  className?: string
  itemClassName?: string
}

/**
 * A list whose rows come and go while it is on screen: a row that leaves
 * closes, a row that joins opens, and the others move to their new places
 * rather than jumping (docs/frontend-design.md §11.9). The first paint is not
 * animated — the list was already like that.
 */
export function PresenceList<T>({ items, keyOf, children, className, itemClassName }: PresenceListProps<T>) {
  return (
    <div className={className}>
      <AnimatePresence initial={false}>
        {items.map((item, i) => (
          <motion.div key={keyOf(item)} {...rowMotion} className={cn('overflow-hidden', itemClassName)}>
            {children(item, i)}
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  )
}
