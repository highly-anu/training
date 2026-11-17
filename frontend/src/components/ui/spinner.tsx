import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * The one spinner. It belongs inside a control that is working, or beside one
 * line that says what is being worked out — never in place of a screen's
 * content, which is `LoadingState` (docs/frontend-design.md §11.1).
 */
export function Spinner({ className }: { className?: string }) {
  return <Loader2 aria-hidden="true" className={cn('size-4 shrink-0 animate-spin', className)} />
}

/** A line of work in progress: the spinner and what it is doing, announced once. */
export function Working({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <p role="status" className={cn('flex items-center gap-2 text-sm text-muted-foreground', className)}>
      <Spinner />
      <span>{children}</span>
    </p>
  )
}
