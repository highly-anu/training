/**
 * What a training-contract session's answer earns. A module moves on only on
 * a clean session at or below its own RPE (`training_contract.clean_shortfall`
 * on the server, the one reading); this is that rule for the words the web
 * writes beside a log, with the ceiling read from the session's module record,
 * never a literal. The phone's `ModuleVerdict.swift` says the same; change both.
 */
import type { Session } from '@/api/types'

export type ModuleReading = 'clean' | 'over_rpe' | 'not_clean'

/** The RPE at or below which a clean session moves on the module this exercise's progress rides on. */
export function moduleCeiling(session: Session, exerciseId: string): number | null {
  for (const record of session.modules ?? []) {
    if (record.exercise_ids?.includes(exerciseId) && typeof record.max_rpe === 'number') return record.max_rpe
  }
  return null
}

export function readVerdict(clean: boolean, rpe: number | null | undefined, ceiling: number | null): ModuleReading {
  if (!clean) return 'not_clean'
  return rpe != null && ceiling != null && rpe > ceiling ? 'over_rpe' : 'clean'
}

/** The verdict in one line, as the session's Progress row says it. */
export function verdictWords(clean: boolean, rpe: number | null | undefined, ceiling: number | null): string {
  switch (readVerdict(clean, rpe, ceiling)) {
    case 'clean': return `Clean, as written${rpe != null ? ` · RPE ${rpe}` : ''}`
    case 'over_rpe': return `Clean · RPE ${rpe} — over RPE ${ceiling}, the cycle holds here`
    default: return 'Not clean — the cycle holds here'
  }
}

/** "RPE 7 or below", in the module's own number. */
export function belowWords(ceiling: number | null): string {
  return ceiling != null ? `RPE ${ceiling} or below` : "the module's RPE or below"
}
