import { useCallback, useSyncExternalStore } from 'react'

/** Whether a media query matches, kept current; false where there is no window to ask. */
export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback((changed: () => void) => {
    const list = typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(query) : null
    list?.addEventListener('change', changed)
    return () => list?.removeEventListener('change', changed)
  }, [query])
  return useSyncExternalStore(
    subscribe,
    () => (typeof window !== 'undefined' && window.matchMedia ? window.matchMedia(query).matches : false),
    () => false,
  )
}
