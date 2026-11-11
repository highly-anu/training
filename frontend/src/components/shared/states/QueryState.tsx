import type { ReactNode } from 'react'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { FailedState } from './FailedState'
import { LoadingState, type LoadingShape } from './LoadingState'
import { loadPhase, reloadFailed } from './loadPhase'

/** What `useQuery` returns, as far as a screen's state needs it. */
interface QueryLike<T> {
  data: T | undefined
  isLoading: boolean
  error: unknown
  refetch?: () => unknown
}

interface QueryStateProps<T> {
  query: QueryLike<T>
  /** Whether the answer has anything to show. Default: it arrived, and is not an empty list. */
  hasContent?: (data: T) => boolean
  loading?: LoadingShape
  loadingCount?: number
  /** "Could not load program history". */
  failedTitle?: string
  /** The empty view — an `EmptyState` with the way forward. Nothing when omitted. */
  empty?: ReactNode
  /** Padding around the loading, failed and empty views, which have no page of their own. */
  className?: string
  size?: 'default' | 'compact'
  children: (data: T) => ReactNode
}

const some = (data: unknown) => (Array.isArray(data) ? data.length > 0 : data != null)

/**
 * A query's three states before its content (docs/frontend-design.md §11):
 * skeletons, a failure with Try again, the empty view — and once there is
 * content, a failed reload said above it, never in its place.
 */
export function QueryState<T>({
  query, hasContent = some, loading = 'cards', loadingCount, failedTitle, empty = null, className, size, children,
}: QueryStateProps<T>) {
  const { data, isLoading, error, refetch } = query
  const has = data !== undefined && hasContent(data)
  const retry = refetch ? () => { void refetch() } : undefined
  switch (loadPhase(has, isLoading, error)) {
    case 'loading':
      return <LoadingState shape={loading} count={loadingCount} className={className} />
    case 'failed':
      return <FailedState title={failedTitle} error={error} onRetry={retry} size={size} className={className} />
    case 'empty':
      return empty ? <div className={className}>{empty}</div> : null
    case 'content':
      return (
        <>
          {reloadFailed(has, error) && (
            <div className={className}>
              <ErrorBanner error={error} title="Could not refresh" onRetry={retry} />
            </div>
          )}
          {children(data as T)}
        </>
      )
  }
}
