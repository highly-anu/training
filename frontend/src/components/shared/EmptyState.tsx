import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'

interface EmptyStateProps {
  title: string
  description?: string
  action?: { label: string; onClick: () => void }
  icon?: React.ReactNode
  className?: string
  /**
   * `compact` fits inside a chart card or a fixed-height slot: less padding,
   * smaller type, a small action button. The default is a page-level block.
   */
  size?: 'default' | 'compact'
}

/**
 * The one zero-data view (design doc §11.2). Always leave a path forward:
 * supply `action` whenever something the athlete can do resolves the state.
 */
export function EmptyState({ title, description, action, icon, className, size = 'default' }: EmptyStateProps) {
  const compact = size === 'compact'
  return (
    <div
      className={cn(
        'flex flex-col items-center justify-center rounded-lg border border-dashed bg-card/50 text-center',
        compact ? 'p-6' : 'p-12',
        className
      )}
    >
      {icon && <div className={cn('text-muted-foreground', compact ? 'mb-2' : 'mb-4')}>{icon}</div>}
      <h3 className={cn('font-semibold text-foreground', compact ? 'text-sm' : 'text-base')}>{title}</h3>
      {description && (
        <p className={cn('mt-1 text-muted-foreground max-w-sm', compact ? 'text-xs' : 'text-sm')}>{description}</p>
      )}
      {action && (
        <Button onClick={action.onClick} size={compact ? 'sm' : 'default'} className={compact ? 'mt-3' : 'mt-4'}>
          {action.label}
        </Button>
      )}
    </div>
  )
}
