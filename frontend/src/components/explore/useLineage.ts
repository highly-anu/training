import { useMemo } from 'react'
import { useExploreLinks } from '@/api/exploreLinks'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useModalities } from '@/api/modalities'
import { useArchetypes } from '@/api/archetypes'
import { useExercises } from '@/api/exercises'
import { indexLinks, type LineageNames, type LinkIndex } from '@/lib/exploreLinks'

const names = <T extends { id: string; name: string }>(rows: T[]) =>
  Object.fromEntries(rows.map((r) => [r.id, r.name]))

/** The link index and every level's names, for lineageOf / progressionOf.
 *  Null until the links have loaded. */
export function useLinkIndex(): { index: LinkIndex | null; names: LineageNames } {
  const { data: links } = useExploreLinks()
  const { data: philosophies = [] } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: modalities = [] } = useModalities()
  const { data: archetypes = [] } = useArchetypes()
  const { data: exercises = [] } = useExercises()
  const lineageNames = useMemo<LineageNames>(() => ({
    philosophies: names(philosophies),
    frameworks: names(frameworks),
    modalities: names(modalities),
    archetypes: names(archetypes),
    exercises: names(exercises),
  }), [philosophies, frameworks, modalities, archetypes, exercises])
  const index = useMemo(() => links
    ? indexLinks(links, Object.fromEntries(exercises.map((e) => [e.id, e._package ?? ''])))
    : null, [links, exercises])
  return { index, names: lineageNames }
}
