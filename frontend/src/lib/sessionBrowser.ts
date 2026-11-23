import type { DescribedSession, DescribedSessionGroup, TrainingLevel } from '@/api/types'
import { modalityLabel } from '@/lib/modalityColors'

/** What the session browser's toolbar narrows the list by. */
export interface BrowseFilter {
  query?: string
  /** A group's key (`groupKey`); null or absent for every group. */
  group?: string | null
  level?: TrainingLevel | null
}

export interface BrowsedGroup {
  key: string
  label: string
  group: DescribedSessionGroup
  sessions: DescribedSession[]
}

export const groupKey = (g: DescribedSessionGroup): string => `${g.kind}-${g.id}`

/** A group's name as the method writes it, else its modality's. */
export function groupLabel(g: DescribedSessionGroup): string {
  return g.name || modalityLabel(g.modality) || 'Other'
}

/** Everything a search can find a session by: its name, its group's, its movements and their exercises. */
function haystack(s: DescribedSession, label: string): string {
  const words = [s.name, label]
  for (const b of s.blocks ?? []) {
    words.push(b.title)
    for (const m of b.movements) words.push(m.name, ...m.exercises.map((e) => e.name))
  }
  for (const slot of s.slots) words.push(slot.name, ...slot.exercises.map((e) => e.name))
  return words.join(' ').toLowerCase()
}

/**
 * The groups and sessions a filter leaves, in the server's order (the method's
 * own: a template's categories as the source runs them, a contract's modules,
 * the rest by modality, tests last). Every word of the query must be found; a
 * session written for no level in particular passes any level.
 */
export function browse(
  groups: DescribedSessionGroup[],
  sessions: Record<string, DescribedSession>,
  filter: BrowseFilter = {},
): BrowsedGroup[] {
  const words = (filter.query ?? '').toLowerCase().split(/\s+/).filter(Boolean)
  const out: BrowsedGroup[] = []
  for (const group of groups) {
    const key = groupKey(group)
    if (filter.group && filter.group !== key) continue
    const label = groupLabel(group)
    const rows = group.sessions.flatMap((id) => {
      const s = sessions[id]
      if (!s) return []
      if (filter.level && s.levels.length > 0 && !s.levels.includes(filter.level)) return []
      if (words.length > 0) {
        const hay = haystack(s, label)
        if (!words.every((w) => hay.includes(w))) return []
      }
      return [s]
    })
    if (rows.length > 0) out.push({ key, label, group, sessions: rows })
  }
  return out
}

/** The session one step down (1) or up (-1) the visible list; null at its ends, the first when `id` is not in it. */
export function neighbour(visible: BrowsedGroup[], id: string | null, step: 1 | -1): string | null {
  const ids = visible.flatMap((g) => g.sessions.map((s) => s.id))
  if (ids.length === 0) return null
  const at = id ? ids.indexOf(id) : -1
  if (at < 0) return ids[0]
  return ids[at + step] ?? null
}

/** The levels a filter is worth offering for: those some session is written for and another is not. */
export function levelChoices(sessions: Record<string, DescribedSession>, order: readonly TrainingLevel[]): TrainingLevel[] {
  const all = Object.values(sessions)
  return order.filter((l) => {
    const n = all.filter((s) => s.levels.includes(l)).length
    return n > 0 && n < all.filter((s) => s.levels.length > 0).length
  })
}

/** The group a session is filed under. */
export function groupOf(groups: DescribedSessionGroup[], id: string): DescribedSessionGroup | undefined {
  return groups.find((g) => g.sessions.includes(id))
}
