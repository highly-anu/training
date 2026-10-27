import type { GeneratedProgram } from '@/api/types'
import type { LaneParam } from '@/api/programs'
import { DAY_NAMES, sessionCalendarDate } from '@/lib/workoutMatcher'

/**
 * A composed program's tracks as a request names them (src/composition.py):
 * from its `composition`, else its goal's `tracks`; none for one track.
 */
export function compositionLanes(
  program: Partial<Pick<GeneratedProgram, 'composition' | 'goal'>> | null | undefined,
): LaneParam[] | undefined {
  const lanes = program?.composition?.lanes?.map((l) => ({
    philosophyId: l.philosophy_id, trackId: l.track_id, weight: l.weight,
  })) ?? program?.goal?.tracks?.map((t) => ({ philosophyId: t.philosophy_id, trackId: t.id, weight: t.weight }))
  return lanes && lanes.length > 1 ? lanes : undefined
}

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
  program: Pick<GeneratedProgram, 'goal' | 'composition'> | null | undefined,
): { philosophyId?: string; philosophyIds?: string[]; philosophyWeights?: Record<string, number>; lanes?: LaneParam[] } {
  // A composed program regenerates as its tracks.
  const lanes = compositionLanes(program)
  if (lanes) return { lanes }
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
  program: Pick<GeneratedProgram, 'weeks' | 'constraints'> & Partial<Pick<GeneratedProgram, 'composition' | 'goal'>>,
  weekIndex: number,
): { trackId?: string; startPhaseId?: string; constraints: GeneratedProgram['constraints']; lanes?: LaneParam[] } {
  const week = program.weeks[weekIndex]
  const base = { ...(program.constraints ?? {}) } as GeneratedProgram['constraints']
  if (!week) return { constraints: base }
  // A composed program: every track resumes in its own phase and phase week.
  const lanes = compositionLanes(program)
  if (lanes && week.lanes?.length) {
    const constraints = { ...base }
    delete constraints.start_phase
    delete constraints.training_phase
    return {
      constraints,
      lanes: lanes.map((l) => {
        const at = week.lanes?.find((w) => w.lane_key === `${l.philosophyId}/${l.trackId}`)
        return at?.phase_id ? { ...l, startPhaseId: at.phase_id, periodizationWeek: at.week_in_phase } : l
      }),
    }
  }
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

/**
 * The weeks after a partial regenerate: the kept head, then the generated
 * tail — except that no session dated before `keepBefore` is replaced.
 *
 * A regenerate starts at a week, and the week it starts at is usually the one
 * the athlete is in. Splicing whole weeks rewrote that week's elapsed days too
 * ("from tomorrow" on a Saturday replaced Monday to Saturday), so the sessions
 * the athlete had done and matched were gone from the plan, and with them the
 * week's adherence. Those days keep the sessions they had; the server then
 * sees an unchanged past and carries the block on
 * (src/program_history.py, carry_over_until).
 */
export function spliceRegenerated(
  currentWeeks: GeneratedProgram['weeks'],
  generatedWeeks: GeneratedProgram['weeks'],
  keepCount: number,
  programStartDate?: string | null,
  keepBefore?: string | null,
): GeneratedProgram['weeks'] {
  const weeks = [...currentWeeks.slice(0, keepCount), ...generatedWeeks]
  if (!programStartDate || !keepBefore) return weeks
  return weeks.map((week, i) => {
    const old = currentWeeks[i]
    if (i < keepCount || !old) return week
    const kept = DAY_NAMES.filter((day) => sessionCalendarDate(programStartDate, i, day) < keepBefore)
    if (kept.length === 0) return week
    const schedule = { ...week.schedule }
    for (const day of kept) {
      if (old.schedule?.[day]?.length) schedule[day] = old.schedule[day]
      else delete schedule[day]
    }
    return { ...week, schedule }
  })
}

/** What makes two planned sessions the same: modality, archetype and movements. */
function sessionSignature(session: GeneratedProgram['weeks'][number]['schedule'][string][number]): string {
  const exercises = (session.exercises ?? []).map((ea) => ea.exercise?.id ?? '').join(',')
  return `${session.modality}|${session.archetype?.id ?? ''}|${session.archetype?.name ?? ''}|${exercises}`
}

/**
 * The sessions a regenerated tail plans differently from the program it
 * replaces, as `${tailIndex}|${day}|${sessionIndex}` — the keys the preview
 * marks. `startIdx` is the week of the current program the tail's first week
 * stands in for. A day the tail leaves empty that had sessions is marked on
 * its first one, so a removed session is never silent.
 */
export function changedSessionKeys(
  currentWeeks: GeneratedProgram['weeks'],
  tailWeeks: GeneratedProgram['weeks'],
  startIdx: number,
): string[] {
  const keys: string[] = []
  tailWeeks.forEach((week, i) => {
    const old = currentWeeks[startIdx + i]
    for (const day of DAY_NAMES) {
      const now = week.schedule?.[day] ?? []
      const was = old?.schedule?.[day] ?? []
      const n = Math.max(now.length, was.length)
      for (let s = 0; s < n; s++) {
        const a = now[s] ? sessionSignature(now[s]) : null
        const b = was[s] ? sessionSignature(was[s]) : null
        if (a !== b) keys.push(`${i}|${day}|${Math.min(s, Math.max(0, now.length - 1))}`)
      }
    }
  })
  return [...new Set(keys)]
}
