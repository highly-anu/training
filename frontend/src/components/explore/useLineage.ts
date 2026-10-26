import { useMemo } from 'react'
import { useExploreLinks } from '@/api/exploreLinks'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useModalities } from '@/api/modalities'
import { useArchetypes } from '@/api/archetypes'
import { useExercises } from '@/api/exercises'
import { indexLinks, type LineageColors, type LineageNames, type LinkIndex } from '@/lib/exploreLinks'
import { ARCH_CAT_COLORS, EX_CATEGORY_COLORS, philosophyHex } from '@/lib/exploreColors'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { movementColor } from '@/lib/movementColors'
import type { ModalityId } from '@/api/types'

const names = <T extends { id: string; name: string }>(rows: T[]) =>
  Object.fromEntries(rows.map((r) => [r.id, r.name]))

const hexes = <T extends { id: string }>(rows: T[], hex: (r: T) => string | undefined) =>
  Object.fromEntries(rows.flatMap((r) => { const h = hex(r); return h ? [[r.id, h]] : [] }))

/** The link index, every level's names and colours, for lineageOf /
 *  progressionOf. The index is null until the links have loaded. */
export function useLinkIndex(): { index: LinkIndex | null; names: LineageNames; colors: LineageColors } {
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
  // The colours the levels' own landings and details use.
  const colors = useMemo<LineageColors>(() => {
    const bias = Object.fromEntries(philosophies.map((p) => [p.id, p.bias]))
    return {
      philosophies: hexes(philosophies, (p) => philosophyHex(p.bias)),
      frameworks: hexes(frameworks, (f) => (f.source_philosophy ? philosophyHex(bias[f.source_philosophy]) : undefined)),
      modalities: hexes(modalities, (m) => MODALITY_COLORS[m.id as ModalityId]?.hex),
      // With the landings' own fallbacks, so a pill matches its card.
      archetypes: hexes(archetypes, (a) => ARCH_CAT_COLORS[a.category] ?? '#94a3b8'),
      exercises: hexes(exercises, (e) => EX_CATEGORY_COLORS[e.category] ?? '#6366f1'),
      movements: hexes(links?.movements ?? [], (m) => movementColor(m.rollup).hex),
    }
  }, [philosophies, frameworks, modalities, archetypes, exercises, links])
  const index = useMemo(() => links
    ? indexLinks(links, Object.fromEntries(exercises.map((e) => [e.id, e._package ?? ''])))
    : null, [links, exercises])
  return { index, names: lineageNames, colors }
}
