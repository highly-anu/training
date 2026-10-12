import type { GeneratedProgram } from '@/api/types'

/**
 * Which philosophies a regenerate asks for: the stored envelope's
 * `sourceGoalIds`, else the program's own goal. A program saved without its
 * ids (an older phone build, a blend whose envelope lost them) used to send
 * neither `philosophy_id` nor `philosophy_ids`, and building the request died
 * on `philosophyIds![0]`. The goal says it too: `primary_sources` on every
 * synthetic goal, and `_phil_<id>` for a single philosophy.
 */
export function regenerateSource(
  sourceGoalIds: string[],
  sourceGoalWeights: Record<string, number>,
  program: Pick<GeneratedProgram, 'goal'> | null | undefined,
): { philosophyId?: string; philosophyIds?: string[]; philosophyWeights?: Record<string, number> } {
  let ids = sourceGoalIds.filter((id) => id && id !== '_blended')
  if (ids.length === 0) {
    const goal = program?.goal
    ids = (goal?.primary_sources ?? []).filter(Boolean)
    if (ids.length === 0 && goal?.id?.startsWith('_phil_') && goal.id !== '_phil_blend') {
      ids = [goal.id.slice('_phil_'.length)]
    }
  }
  if (ids.length === 1) return { philosophyId: ids[0] }
  if (ids.length > 1) return { philosophyIds: ids, philosophyWeights: sourceGoalWeights }
  return {}
}
