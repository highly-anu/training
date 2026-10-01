import type { AthleteConstraints, Day, DaySchedule, EquipmentId, InjuryFlagId, TrainingLevel } from '@/api/types'

/**
 * What the profile says now versus what the active program was built for.
 *
 * A program carries the constraints it was generated from; the profile moves
 * on (new equipment, a level change, a different week). Until the two were
 * compared, only an injury change could offer a regenerate — equipment and
 * level changes silently left the plan asking for a rack the athlete no
 * longer has. The shared comparison lives here so Profile and the Program
 * settings sheet say the same thing.
 */
export interface ConstraintDifference {
  field: 'training_level' | 'equipment' | 'days_per_week' | 'injury_flags'
  label: string
  /** What the program was built for. */
  program: string
  /** What the profile says now. */
  profile: string
}

export interface ProfileForConstraints {
  trainingLevel: TrainingLevel
  equipment: EquipmentId[]
  injuryFlags: InjuryFlagId[]
  weeklySchedule: Record<Day, DaySchedule> | null
}

/** Days with at least one non-rest session; null when no schedule is set. */
export function daysPerWeekOf(schedule: Record<Day, DaySchedule> | null | undefined): number | null {
  if (!schedule) return null
  const days = Object.values(schedule).filter((d) =>
    [d.session1, d.session2, d.session3, d.session4].some((s) => s && s !== 'rest')
  ).length
  return days
}

function sameSet(a: readonly string[] = [], b: readonly string[] = []): boolean {
  if (a.length !== b.length) return false
  const sa = new Set(a)
  return b.every((x) => sa.has(x))
}

function setChange(from: readonly string[] = [], to: readonly string[] = []): string {
  const fromSet = new Set(from)
  const toSet = new Set(to)
  const added = to.filter((x) => !fromSet.has(x)).length
  const removed = from.filter((x) => !toSet.has(x)).length
  const parts: string[] = []
  if (added) parts.push(`${added} added`)
  if (removed) parts.push(`${removed} removed`)
  return parts.join(', ') || 'unchanged'
}

export function constraintDifferences(
  constraints: AthleteConstraints | undefined | null,
  profile: ProfileForConstraints,
): ConstraintDifference[] {
  if (!constraints) return []
  const out: ConstraintDifference[] = []
  if (constraints.training_level && profile.trainingLevel && constraints.training_level !== profile.trainingLevel) {
    out.push({ field: 'training_level', label: 'Training level',
               program: constraints.training_level, profile: profile.trainingLevel })
  }
  if (profile.equipment.length > 0 && !sameSet(constraints.equipment ?? [], profile.equipment)) {
    out.push({ field: 'equipment', label: 'Equipment',
               program: `${(constraints.equipment ?? []).length} items`,
               profile: setChange(constraints.equipment ?? [], profile.equipment) })
  }
  const days = daysPerWeekOf(profile.weeklySchedule)
  if (days != null && days > 0 && constraints.days_per_week && days !== constraints.days_per_week) {
    out.push({ field: 'days_per_week', label: 'Days per week',
               program: String(constraints.days_per_week), profile: String(days) })
  }
  if (!sameSet(constraints.injury_flags ?? [], profile.injuryFlags)) {
    out.push({ field: 'injury_flags', label: 'Injuries',
               program: `${(constraints.injury_flags ?? []).length} flagged`,
               profile: setChange(constraints.injury_flags ?? [], profile.injuryFlags) })
  }
  return out
}

/** The program's constraints with the profile's current values applied. */
export function mergedConstraints(
  constraints: AthleteConstraints,
  profile: ProfileForConstraints,
  periodizationWeek?: number | null,
): AthleteConstraints {
  const days = daysPerWeekOf(profile.weeklySchedule)
  return {
    ...constraints,
    training_level: profile.trainingLevel ?? constraints.training_level,
    equipment: profile.equipment.length > 0 ? profile.equipment : constraints.equipment,
    injury_flags: profile.injuryFlags,
    ...(days != null && days > 0 ? { days_per_week: days } : {}),
    ...(periodizationWeek != null ? { periodization_week: periodizationWeek } : {}),
  }
}
