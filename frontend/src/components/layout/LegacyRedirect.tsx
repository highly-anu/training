import { Navigate, useLocation, useParams } from 'react-router-dom'

interface LegacyRedirectProps {
  /** Target path, or a function of the matched route params. */
  to: string | ((params: Record<string, string | undefined>) => string)
  /** Query parameters to add when the old URL did not carry them. */
  params?: Record<string, string>
}

/**
 * Sends an old URL to its new home without losing anything the link carried:
 * the query (`?linkTo=`, `?tab=`) and the router state (`WorkoutDetail` reads
 * the workout from `location.state` to avoid a refetch).
 */
export function LegacyRedirect({ to, params }: LegacyRedirectProps) {
  const location = useLocation()
  const routeParams = useParams()
  const pathname = typeof to === 'function' ? to(routeParams) : to
  const search = new URLSearchParams(location.search)
  for (const [key, value] of Object.entries(params ?? {})) {
    if (!search.has(key)) search.set(key, value)
  }
  const qs = search.toString()
  return <Navigate to={{ pathname, search: qs ? `?${qs}` : '' }} state={location.state} replace />
}
