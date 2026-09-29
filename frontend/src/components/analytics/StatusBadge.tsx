import { cn } from '@/lib/utils'
import { STATUS_STYLES } from '@/lib/statusColors'
import { statusLabel, statusLevel } from './status'

export function StatusBadge({ status, className }: { status: string; className?: string }) {
  const level = statusLevel(status)
  const style = level === 'neutral'
    ? 'bg-muted text-muted-foreground border-border'
    : STATUS_STYLES[level].badge
  return (
    <span className={cn('inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-semibold', style, className)}>
      {statusLabel(status)}
    </span>
  )
}
