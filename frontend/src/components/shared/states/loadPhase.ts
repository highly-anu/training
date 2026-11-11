/**
 * Which of the four states a screen is in (docs/frontend-design.md §11).
 *
 * Content wins: once something is on screen, a reload — or its failure — never
 * takes it away. A failed reload is said beside the content (`reloadFailed`),
 * as the phone's `AppLoadPhase.resolve` does.
 */
export type LoadPhase = 'content' | 'loading' | 'failed' | 'empty'

export function loadPhase(hasContent: boolean, isLoading: boolean, error: unknown): LoadPhase {
  if (hasContent) return 'content'
  if (isLoading) return 'loading'
  if (error) return 'failed'
  return 'empty'
}

/** A reload failed while content is on screen: say so above it, keep it. */
export function reloadFailed(hasContent: boolean, error: unknown): boolean {
  return hasContent && Boolean(error)
}

/** What a failure says. A thrown string or an object with no message says nothing useful. */
export function errorMessage(error: unknown): string | undefined {
  if (error instanceof Error) return error.message || undefined
  if (typeof error === 'string') return error || undefined
  return undefined
}
