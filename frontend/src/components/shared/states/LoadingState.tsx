import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

/** `block` fills the box `className` sizes — a chart or map inside a card that is already there. */
export type LoadingShape = 'cards' | 'grid' | 'list' | 'chart' | 'lines' | 'block' | 'tiles'

interface LoadingStateProps {
  /** The shape of what is coming, so nothing jumps when it arrives. */
  shape?: LoadingShape
  /** Cards, rows or lines. */
  count?: number
  /** Said to a screen reader; nothing is written on screen. */
  label?: string
  className?: string
}

const DEFAULT_COUNT: Record<LoadingShape, number> = { cards: 2, grid: 6, list: 5, chart: 1, lines: 2, block: 1, tiles: 6 }

function Card({ lines }: { lines: number }) {
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <Skeleton className="h-4 w-2/3" />
      {Array.from({ length: lines - 1 }).map((_, i) => (
        <Skeleton key={i} className={cn('h-3', i === lines - 2 ? 'w-1/2' : 'w-full')} />
      ))}
    </div>
  )
}

/**
 * The one loading look (docs/frontend-design.md §11.1): skeletons in the shape
 * of the content. No spinner and no "Loading…" stands in for a screen.
 */
export function LoadingState({ shape = 'cards', count, label = 'Loading', className }: LoadingStateProps) {
  const items = Array.from({ length: count ?? DEFAULT_COUNT[shape] })
  return (
    <div role="status" aria-busy="true" className={className}>
      <span className="sr-only">{label}</span>
      {shape === 'cards' && (
        <div className="space-y-3">{items.map((_, i) => <Card key={i} lines={i === 0 ? 4 : 5} />)}</div>
      )}
      {shape === 'grid' && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {items.map((_, i) => <Card key={i} lines={4} />)}
        </div>
      )}
      {shape === 'list' && (
        <div className="divide-y divide-border/50 rounded-lg border bg-card">
          {items.map((_, i) => (
            <div key={i} className="flex items-center gap-3 px-4 py-3">
              <Skeleton className="size-8 rounded-md" />
              <div className="flex-1 space-y-2">
                <Skeleton className="h-3 w-1/3" />
                <Skeleton className="h-3 w-1/2" />
              </div>
              <Skeleton className="h-3 w-10" />
            </div>
          ))}
        </div>
      )}
      {shape === 'chart' && (
        <div className="rounded-lg border bg-card p-4 space-y-3">
          <Skeleton className="h-4 w-1/4" />
          <Skeleton className="h-40 w-full" />
        </div>
      )}
      {shape === 'block' && <Skeleton className="h-full w-full" />}
      {shape === 'tiles' && (
        <div className="grid grid-cols-2 gap-2">
          {items.map((_, i) => <Skeleton key={i} className="h-12 rounded-lg" />)}
        </div>
      )}
      {shape === 'lines' && (
        <div className="space-y-2">
          {items.map((_, i) => <Skeleton key={i} className={cn('h-3', i % 2 ? 'w-1/2' : 'w-2/3')} />)}
        </div>
      )}
    </div>
  )
}
