import { Trophy } from 'lucide-react'
import type { SessionTest } from '@/api/types'

/** Marks a session that tests the phase's standards (a scheduled test). */
export function TestBadge({ test, size = 'sm' }: { test: SessionTest; size?: 'sm' | 'md' }) {
  const instead = test.instead_of?.name
  return (
    <span
      title={instead ? `A test of this phase's standards, in place of ${instead}` : "A test of this phase's standards"}
      className={size === 'sm'
        ? 'inline-flex items-center gap-0.5 rounded-full bg-primary/15 px-1.5 py-0.5 text-[9px] font-semibold text-foreground'
        : 'inline-flex items-center gap-1 rounded-full bg-primary/15 px-2 py-0.5 text-xs font-semibold text-foreground'}
    >
      <Trophy className={size === 'sm' ? 'size-2.5' : 'size-3'} aria-hidden="true" /> Test
    </span>
  )
}
