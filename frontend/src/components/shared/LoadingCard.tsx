import { Skeleton } from '@/components/ui/skeleton'
import { cn } from '@/lib/utils'

interface LoadingCardProps {
  lines?: number
  className?: string
}

export function LoadingCard({ lines = 3, className }: LoadingCardProps) {
  return (
    <div className={cn('rounded-lg border bg-card p-4 space-y-3', className)}>
      <Skeleton className="h-4 w-2/3" />
      {Array.from({ length: lines - 1 }).map((_, i) => (
        <Skeleton key={i} className={cn('h-3', i === lines - 2 ? 'w-1/2' : 'w-full')} />
      ))}
    </div>
  )
}

export function LoadingGrid({ count = 6 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {Array.from({ length: count }).map((_, i) => (
        <LoadingCard key={i} lines={4} />
      ))}
    </div>
  )
}
