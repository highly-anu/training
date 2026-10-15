import { useEffect, useState } from 'react'

/**
 * Log ▸ Linking's "not this" — (workout, session) pairs the athlete waved
 * away, kept in this browser only. A scored suggestion is recomputed on every
 * render, so without this it would come straight back; a server suggestion is
 * also dismissed on the server.
 */

const KEY = 'linkingDismissed'
const EVENT = 'linking-dismissed'

function read(): Set<string> {
  try {
    const raw = localStorage.getItem(KEY)
    return new Set(raw ? (JSON.parse(raw) as string[]) : [])
  } catch { return new Set() }
}

export function dismissLink(key: string) {
  const next = read()
  next.add(key)
  try { localStorage.setItem(KEY, JSON.stringify([...next])) } catch { /* private mode */ }
  window.dispatchEvent(new Event(EVENT))
}

export function useDismissedLinks(): Set<string> {
  const [dismissed, setDismissed] = useState(read)
  useEffect(() => {
    const onChange = () => setDismissed(read())
    window.addEventListener(EVENT, onChange)
    return () => window.removeEventListener(EVENT, onChange)
  }, [])
  return dismissed
}
