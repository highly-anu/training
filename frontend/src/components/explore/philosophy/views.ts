import { BookOpen, GitBranch, LayoutGrid, ListTree } from 'lucide-react'

/** The philosophy page's sections, in order; the URL's `view` (docs/frontend-design.md §13.7). */
export const PHILOSOPHY_VIEWS = [
  { id: 'overview', label: 'Overview', Icon: LayoutGrid },
  { id: 'program', label: 'Program', Icon: GitBranch },
  { id: 'sessions', label: 'Sessions', Icon: ListTree },
  { id: 'method', label: 'Method', Icon: BookOpen },
] as const

export type PhilosophyView = typeof PHILOSOPHY_VIEWS[number]['id']

/** The view a URL asks for: its `view`, a `session` alone meaning Sessions, else Overview. */
export function parseView(view: string | null, session: string | null): PhilosophyView {
  const known = PHILOSOPHY_VIEWS.find((v) => v.id === view)?.id
  return known ?? (session ? 'sessions' : 'overview')
}
