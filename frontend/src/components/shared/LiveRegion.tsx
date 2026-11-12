import { useEffect, useState } from 'react'
import { onAnnounce } from '@/lib/announce'

/**
 * The page's one polite live region: whatever `announce()` says is read out
 * once and seen by nobody. Mounted once, in App.
 */
export function LiveRegion() {
  // The key changes with every message, so the same sentence twice is read twice.
  const [said, setSaid] = useState<{ id: number; message: string }>({ id: 0, message: '' })

  useEffect(() => onAnnounce((message) => setSaid((s) => ({ id: s.id + 1, message }))), [])

  return (
    <div aria-live="polite" aria-atomic="true" className="sr-only">
      <span key={said.id}>{said.message}</span>
    </div>
  )
}
