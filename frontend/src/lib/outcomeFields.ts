/**
 * Which outcome fields a slot type can log. Shared by the OutcomeLogger and by
 * ExerciseRow, which decides whether to mount it.
 */
export type OutcomeField = 'rounds' | 'minutes' | 'km' | 'reps'

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

export function outcomeFieldsFor(slotType: string | undefined): OutcomeField[] {
  return FIELDS_FOR[slotType ?? ''] ?? []
}
