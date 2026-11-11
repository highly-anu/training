import { useState, type ReactNode } from 'react'
import { useLocation } from 'react-router-dom'
import { useIsPresent } from 'framer-motion'
import { useScrollRestore } from '@/lib/useScrollRestore'
import { cn } from '@/lib/utils'

interface ScrollPanelProps {
  /** Tells two panels of one page apart (a list and the detail it opens). */
  part?: string
  className?: string
  children: ReactNode
}

/**
 * A panel that fills its place and scrolls, keeping its position per history
 * entry (docs/frontend-design.md §11.10): Back from a detail finds the list
 * where it was left. For a tab's or a topic's body that scrolls by itself
 * under a header that stays put; a page whose one scroller sits in the page
 * component takes `useScrollRestore` directly.
 */
export function ScrollPanel({ part = 'panel', className, children }: ScrollPanelProps) {
  // A panel on its way out keeps the entry it was shown in, or it would jump
  // to the next entry's position while it fades.
  const present = useIsPresent()
  const { key } = useLocation()
  const [entry, setEntry] = useState(key)
  if (present && entry !== key) setEntry(key)
  const scroller = useScrollRestore<HTMLDivElement>(part, entry)

  return (
    <div ref={scroller} className={cn('h-full overflow-y-auto', className)}>
      {children}
    </div>
  )
}
