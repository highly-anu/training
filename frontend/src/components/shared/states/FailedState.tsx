import { AlertCircle, RotateCw } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { errorMessage } from './loadPhase'

interface FailedStateProps {
  /** What did not load: "Could not load program history". */
  title?: string
  error?: unknown
  /** Try again. A failure the athlete cannot retry is rare; say why in `title`. */
  onRetry?: () => void
  retryLabel?: string
  size?: 'default' | 'compact'
  className?: string
}

/**
 * Nothing on screen and the load failed (docs/frontend-design.md §11.3): what
 * failed, why if the server said, and Try again. With content on screen a
 * failed reload is an `ErrorBanner` above it instead.
 */
export function FailedState({
  title = 'Could not load', error, onRetry, retryLabel = 'Try again', size = 'default', className,
}: FailedStateProps) {
  const compact = size === 'compact'
  const message = errorMessage(error)
  return (
    <div
      role="alert"
      className={cn(
        'flex flex-col items-center justify-center rounded-lg border bg-card/50 text-center',
        compact ? 'p-6' : 'p-12',
        className,
      )}
    >
      <AlertCircle aria-hidden="true" className={cn('text-destructive', compact ? 'size-5 mb-2' : 'size-7 mb-4')} />
      <h3 className={cn('font-semibold text-foreground', compact ? 'text-sm' : 'text-base')}>{title}</h3>
      {message && (
        <p className={cn('mt-1 max-w-sm text-muted-foreground', compact ? 'text-xs' : 'text-sm')}>{message}</p>
      )}
      {onRetry && (
        <Button variant="outline" size={compact ? 'sm' : 'default'} onClick={onRetry} className={compact ? 'mt-3' : 'mt-4'}>
          <RotateCw aria-hidden="true" className="size-3.5" />
          {retryLabel}
        </Button>
      )}
    </div>
  )
}
