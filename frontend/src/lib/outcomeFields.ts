/**
 * Which outcome fields a slot can log. Shared by the OutcomeLogger and by
 * ExerciseRow, which decides whether to mount it; the phone's copy is
 * `SessionLogging.outcomeFields` — change both.
 *
 * Mostly the slot type decides. Two exercise rules on top, so each package's
 * declared measures can be fed (tools/check_analytics.py proves they apply;
 * this is what lets them measure):
 *  - a kettlebell in a timed slot logs reps beside minutes — reps per minute
 *    is Wildman's cadence (`rate`), and km of a swing means nothing;
 *  - an isometric in a skill-practice slot logs the hold in seconds — Ido's
 *    handstand and L-sit holds (`hold_seconds`).
 */
export type OutcomeField = 'rounds' | 'minutes' | 'km' | 'reps' | 'seconds'

const FIELDS_FOR: Record<string, OutcomeField[]> = {
  time_domain:     ['minutes', 'km'],
  skill_practice:  ['minutes'],
  for_time:        ['minutes'],
  distance:        ['km', 'minutes'],
  amrap:           ['rounds', 'reps'],
  emom:            ['rounds'],
  rounds_for_time: ['minutes', 'rounds'],
  amrap_movement:  ['reps'],
}

export interface OutcomeExercise {
  category?: string | null
  movement_patterns?: string[] | null
}

export function outcomeFieldsFor(slotType: string | undefined, exercise?: OutcomeExercise | null): OutcomeField[] {
  const base = FIELDS_FOR[slotType ?? ''] ?? []
  if (slotType === 'time_domain' && exercise?.category === 'kettlebell') return ['minutes', 'reps']
  if (slotType === 'skill_practice' && exercise?.movement_patterns?.includes('isometric')) return ['minutes', 'seconds']
  return base
}

/** A slot logged per set whose sets are holds: seconds, not reps. */
export function isHoldSlot(slotType: string | undefined, load: { hold_seconds?: number | null }): boolean {
  return slotType === 'static_hold' || load.hold_seconds != null
}
