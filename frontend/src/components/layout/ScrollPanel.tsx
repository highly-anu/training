import { useState, type ReactNode } from 'react'
import { useLocation, useNavigationType } from 'react-router-dom'
import { useIsPresent } from 'framer-motion'
import { carryScroll, useScrollRestore } from '@/lib/useScrollRestore'
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
 *
 * A replace is the same place under a new key, so the position goes with it:
 * a sheet that writes `?standard=` leaves the list where it was, and a back
 * button that replaces names the entry it returns to (`state.scrollFrom`).
 */
export function ScrollPanel({ part = 'panel', className, children }: ScrollPanelProps) {
  // A panel on its way out keeps the entry it was shown in, or it would jump
  // to the next entry's position while it fades.
  const present = useIsPresent()
  const { key, state } = useLocation()
  const replaced = useNavigationType() === 'REPLACE'
  const [entry, setEntry] = useState(() => {
    const from = (state as { scrollFrom?: unknown } | null)?.scrollFrom
    if (typeof from === 'string') carryScroll(from, key, part)
    return key
  })
  if (present && entry !== key) {
    if (replaced) carryScroll(entry, key, part)
    setEntry(key)
  }
  const scroller = useScrollRestore<HTMLDivElement>(part, entry)

  return (
    <div ref={scroller} className={cn('h-full overflow-y-auto', className)}>
      {children}
    </div>
  )
}
