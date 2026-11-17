import { cn } from '@/lib/utils'

export function SectionTitle({ children }: { children: React.ReactNode }) {
  return <h3 className="col-span-full pt-4 pb-1 text-sm font-semibold"><span className="sticky left-0">{children}</span></h3>
}

/** A line across every column (shared chips, a note, a button): it stays in
 *  view and wraps at the screen's width while the grid scrolls sideways. */
export function WideLine({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <div className="col-span-full border-t border-border/40">
      <div className={cn('sticky left-0 max-w-[calc(100vw-2rem)] py-2', className)}>{children}</div>
    </div>
  )
}

/** One row: its label (sticky when the grid scrolls sideways) and a cell per
 *  column. `same` rows fade, and hide under "Only differences". */
export function Row({ label, same, hidden, children }: {
  label: React.ReactNode; same?: boolean; hidden?: boolean; children: React.ReactNode
}) {
  if (hidden) return null
  return (
    <>
      <div className="sticky left-0 z-10 border-t border-border/40 bg-background py-2 pr-2 text-[11px] text-muted-foreground">
        {label}
        {same && <span className="block text-[9px] text-muted-foreground/60">same for all</span>}
      </div>
      {children}
    </>
  )
}

export function Cell({ children, className }: { children: React.ReactNode; className?: string }) {
  return <div className={cn('min-w-0 border-t border-border/40 py-2 text-xs', className)}>{children}</div>
}
