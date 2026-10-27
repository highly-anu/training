import type { GenerateParams } from '@/api/programs'
import type { AthleteConstraints, CustomInjuryFlag, Day, DaySchedule } from '@/api/types'
import type { useBuilderStore } from '@/store/builderStore'
import { scheduleToConstraints } from '@/lib/scheduleToConstraints'

type BuilderState = ReturnType<typeof useBuilderStore.getState>

/**
 * The generate request the builder's choices make: the source (one
 * philosophy, or a blend's tracks with normalised weights), the track and
 * start phase, and the
 * constraints with the saved weekly schedule laid over them — the schedule
 * wins over stale persisted day counts, so the request and the summary both
 * read the actual training days. Shared by Review & Generate and the
 * preview, which asks again with edited constraints.
 */
export function builderGenerateParams(
  b: Pick<BuilderState, 'sourceMode' | 'selectedPhilosophyIds' | 'philosophyWeights' | 'constraints'
    | 'eventDate' | 'startDate' | 'numWeeks' | 'selectedTrackId' | 'startPhaseId' | 'priorityOverrides'>
    & Partial<Pick<BuilderState, 'lanes'>>,
  weeklySchedule: Record<Day, DaySchedule> | null,
  customInjuryFlags: CustomInjuryFlag[],
): GenerateParams {
  const blendTotal = b.selectedPhilosophyIds.reduce((s, id) => s + (b.philosophyWeights[id] ?? 50), 0) || 1
  const normalizedPhilWeights = Object.fromEntries(
    b.selectedPhilosophyIds.map((id) => [id, (b.philosophyWeights[id] ?? 50) / blendTotal])
  )
  const scheduleOverride = weeklySchedule ? scheduleToConstraints(weeklySchedule) : {}
  const lanes = b.lanes ?? []
  if (b.sourceMode === 'blend' && lanes.length > 1) {
    // Several tracks compose one program (src/composition.py): each its own
    // track and start phase (none with an event date, which places every
    // track's last phase on it), weights normalised.
    const total = lanes.reduce((s, l) => s + l.weight, 0) || 1
    return {
      lanes: lanes.map((l) => ({
        philosophyId: l.philosophyId,
        trackId: l.trackId,
        weight: l.weight / total,
        startPhaseId: b.eventDate ? null : l.startPhaseId,
      })),
      constraints: { ...b.constraints, ...scheduleOverride } as AthleteConstraints,
      eventDate: b.eventDate ?? undefined,
      startDate: b.startDate ?? undefined,
      numWeeks: b.numWeeks ?? undefined,
      customInjuryFlags,
    }
  }
  return {
    ...(b.sourceMode === 'blend' && b.selectedPhilosophyIds.length > 1
      ? { philosophyIds: b.selectedPhilosophyIds, philosophyWeights: normalizedPhilWeights }
      : { philosophyId: b.selectedPhilosophyIds[0] }),
    constraints: { ...b.constraints, ...scheduleOverride } as AthleteConstraints,
    eventDate: b.eventDate ?? undefined,
    startDate: b.startDate ?? undefined,
    numWeeks: b.numWeeks ?? undefined,
    trackId: b.selectedTrackId,
    startPhaseId: b.startPhaseId,
    priorityOverrides: b.priorityOverrides,
    customInjuryFlags,
  }
}
