import { createContext, useContext } from 'react'

/** How a week's module reaches its session in the page's browser: whether the
 *  package writes one under that id, and the way to it. */
export interface SessionLink {
  has: (id: string) => boolean
  open: (id: string) => void
}

export const SessionLinkContext = createContext<SessionLink | null>(null)

export const useSessionLink = (): SessionLink | null => useContext(SessionLinkContext)
