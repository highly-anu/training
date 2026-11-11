/**
 * A page's scroll position, kept per history entry (docs/frontend-design.md
 * §11.10): Back returns to where the list was left, a link followed afresh
 * starts at the top.
 *
 * The pages scroll in their own containers (the header stays put above them),
 * so the browser's own restoration, which watches the window, restores
 * nothing. The key is the router's `location.key` — one per history entry —
 * so a `?tab=` change is a new entry at the top and Back to the old tab finds
 * its place.
 *
 *   const scroller = useScrollRestore<HTMLDivElement>()
 *   <div ref={scroller} className="flex-1 overflow-y-auto">
 */
import { useLayoutEffect, useRef, type RefObject } from 'react'
import { useLocation } from 'react-router-dom'

const MAX_ENTRIES = 50
const positions = new Map<string, number>()

/** Remember `top` for `id`, forgetting the oldest entry past the cap. */
export function rememberScroll(id: string, top: number, store: Map<string, number> = positions, max = MAX_ENTRIES): void {
  store.delete(id)
  store.set(id, top)
  if (store.size > max) store.delete(store.keys().next().value as string)
}

/**
 * `part` tells two scrollers on one page apart. `entry` pins the scroller to
 * one history entry: a tab panel on its way out must not take the next
 * entry's place.
 */
export function useScrollRestore<T extends HTMLElement = HTMLDivElement>(part = '', entry?: string): RefObject<T | null> {
  const ref = useRef<T>(null)
  const { key } = useLocation()
  const id = `${entry ?? key}|${part}`

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    const want = positions.get(id) ?? 0
    el.scrollTop = want
    // Content that arrives a moment later (a cached query, a panel's entry)
    // makes the place reachable; try for half a second, then leave it be.
    let frame = 0
    let tries = 0
    const settle = () => {
      if (el.scrollTop >= want - 1 || tries++ > 30) return
      el.scrollTop = want
      frame = requestAnimationFrame(settle)
    }
    if (want > 0) frame = requestAnimationFrame(settle)
    const stop = () => cancelAnimationFrame(frame)
    const onScroll = () => rememberScroll(id, el.scrollTop)
    el.addEventListener('scroll', onScroll, { passive: true })
    el.addEventListener('wheel', stop, { passive: true })
    el.addEventListener('touchstart', stop, { passive: true })
    return () => {
      stop()
      el.removeEventListener('scroll', onScroll)
      el.removeEventListener('wheel', stop)
      el.removeEventListener('touchstart', stop)
    }
  }, [id])

  return ref
}
