import { cn } from '@/lib/utils'

/**
 * The link under text that is shortened: "More…" shows the rest, "Less" hides
 * it again. Every clamped paragraph and folded note uses this one, so the two
 * words are the same everywhere (docs/frontend-design.md §13.7).
 */
export function MoreToggle({ open, onToggle, className }: {
  open: boolean; onToggle: () => void; className?: string
}) {
  return (
    <button type="button" onClick={onToggle} aria-expanded={open}
      className={cn('text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline', className)}>
      {open ? 'Less' : 'More…'}
    </button>
  )
}
