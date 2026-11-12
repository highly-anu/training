import { AlertCircle, RotateCw } from 'lucide-react'
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { errorMessage } from '@/components/shared/states/loadPhase'

interface ErrorBannerProps {
  error: unknown
  title?: string
  /** Try again — offered whenever the thing that failed can be asked for again. */
  onRetry?: () => void
}

/**
 * A failure said beside content that stays on screen: a reload that failed, a
 * section of a document the server could not build. With nothing on screen it
 * is `FailedState` (docs/frontend-design.md §11.3).
 */
export function ErrorBanner({ error, title = 'Something went wrong', onRetry }: ErrorBannerProps) {
  if (!error) return null

  return (
    <Alert variant="destructive">
      <AlertCircle className="size-4" />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription>{errorMessage(error)}</AlertDescription>
      {onRetry && (
        <Button variant="outline" size="sm" onClick={onRetry} className="mt-3 text-foreground">
          <RotateCw aria-hidden="true" className="size-3.5" />
          Try again
        </Button>
      )}
    </Alert>
  )
}
