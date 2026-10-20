import type { GenerateParams } from '@/api/programs'
import type { AthleteConstraints, CustomInjuryFlag, Day, DaySchedule } from '@/api/types'
import type { useBuilderStore } from '@/store/builderStore'
import { scheduleToConstraints } from '@/lib/scheduleToConstraints'

type BuilderState = ReturnType<typeof useBuilderStore.getState>

/**
 * The generate request the builder's choices make: the source (one
 * philosophy or a normalised blend), the track and start phase, and the
 * constraints with the saved weekly schedule laid over them — the schedule
 * wins over stale persisted day counts, so the request and the summary both
 * read the actual training days. Shared by Review & Generate and the
 * preview, which asks again with edited constraints.
 */
export function builderGenerateParams(
  b: Pick<BuilderState, 'sourceMode' | 'selectedPhilosophyIds' | 'philosophyWeights' | 'constraints'
    | 'eventDate' | 'startDate' | 'numWeeks' | 'selectedTrackId' | 'startPhaseId' | 'priorityOverrides'>,
  weeklySchedule: Record<Day, DaySchedule> | null,
  customInjuryFlags: CustomInjuryFlag[],
): GenerateParams {
  const blendTotal = b.selectedPhilosophyIds.reduce((s, id) => s + (b.philosophyWeights[id] ?? 50), 0) || 1
  const normalizedPhilWeights = Object.fromEntries(
    b.selectedPhilosophyIds.map((id) => [id, (b.philosophyWeights[id] ?? 50) / blendTotal])
  )
  const scheduleOverride = weeklySchedule ? scheduleToConstraints(weeklySchedule) : {}
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
