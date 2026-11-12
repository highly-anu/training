/**
 * Says a result to a screen reader, once (docs/frontend-design.md §11.7).
 *
 * A change the eye catches — a stripe turning to done, a row leaving — is
 * silent to someone who is not looking at it. `announce` puts one sentence in
 * the page's live region (`components/shared/LiveRegion.tsx`, mounted once in
 * App). Not for things that already speak: a `role="status"` line, an alert, a
 * toast.
 */
type Listener = (message: string) => void

const listeners = new Set<Listener>()

export function announce(message: string): void {
  listeners.forEach((l) => l(message))
}

export function onAnnounce(listener: Listener): () => void {
  listeners.add(listener)
  return () => { listeners.delete(listener) }
}
