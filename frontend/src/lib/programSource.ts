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

/**
 * Where a regenerated tail resumes: the target week's own track, phase and
 * week in that phase. All three regenerate paths used to resend the program's
 * original start phase, so a tail from week 10 of base(8) + build(6) restarted
 * at base week 2. A program stored before tracks has no phase id; its week's
 * kind is sent instead, which the server maps to the first phase of that kind.
 */
export function tailResume(
  program: Pick<GeneratedProgram, 'weeks' | 'constraints'>,
  weekIndex: number,
): { trackId?: string; startPhaseId?: string; constraints: GeneratedProgram['constraints'] } {
  const week = program.weeks[weekIndex]
  const base = { ...(program.constraints ?? {}) } as GeneratedProgram['constraints']
  if (!week) return { constraints: base }
  const constraints = { ...base, periodization_week: week.week_in_phase }
  if (week.phase_id) {
    delete constraints.training_phase
    return {
      trackId: week.track_id ?? base.track_id,
      startPhaseId: week.phase_id,
      constraints: { ...constraints, start_phase: week.phase_id },
    }
  }
  delete constraints.start_phase
  return { constraints: { ...constraints, training_phase: week.phase } }
}
