import { OUTCOME_RESULT_FIELD, OUTCOME_SLOT_TYPES, type OutcomeField } from '@/lib/gen/clientVocab'

/**
 * Which outcome fields a slot can log. Shared by the OutcomeLogger and by
 * ExerciseRow, which decides whether to mount it; the phone's
 * `SessionLogging.outcomeFields` reads the same generated table.
 *
 * Mostly the slot type decides. Two exercise rules on top, so each package's
 * declared measures can be fed (tools/check_analytics.py proves they apply;
 * this is what lets them measure):
 *  - a kettlebell in a timed slot logs reps beside minutes — reps per minute
 *    is Wildman's cadence (`rate`), and km of a swing means nothing;
 *  - an isometric in a skill-practice slot logs the hold in seconds — Ido's
 *    handstand and L-sit holds (`hold_seconds`).
 * A for-time slot is scored to the second, so it logs a clock (`time`, m:ss),
 * not whole minutes. And a test's scored slot asks first for the number its
 * standard needs (`standard.result`, src/standard_tests.RESULTS): reps for
 * push-ups in three minutes, which a timed bodyweight slot would otherwise
 * log as minutes and km.
 */
export type { OutcomeField } from '@/lib/gen/clientVocab'

export interface OutcomeExercise {
  category?: string | null
  movement_patterns?: string[] | null
}

// The table and its rules are data: data/commons/outcome_fields.yaml, through
// tools/gen_client_vocab.py, which writes the phone's SessionLogging table too.
export function outcomeFieldsFor(slotType: string | undefined, exercise?: OutcomeExercise | null,
                                 standard?: { result?: string | null } | null): OutcomeField[] {
  const slot = OUTCOME_SLOT_TYPES[slotType ?? '']
  let base: OutcomeField[] = slot?.fields ?? []
  const rule = slot?.when.find((r) =>
    (!r.exerciseCategory || exercise?.category === r.exerciseCategory)
    && (!r.movementPattern || !!exercise?.movement_patterns?.includes(r.movementPattern)))
  if (rule) base = rule.fields
  if (slot?.clock) base = base.map((f) => (f === 'minutes' ? 'time' : f))
  const want = standard?.result ? OUTCOME_RESULT_FIELD[standard.result] : undefined
  if (!want) return base
  if (want === 'time') base = base.map((f) => (f === 'minutes' ? 'time' : f))
  return [want, ...base.filter((f) => f !== want && (f !== 'km' || want === 'km'))]
}

/** A clock as typed — "7:32", "1:02:30", or plain minutes ("7.5") — in seconds;
 *  undefined when it is not one. */
export function parseClock(raw: string): number | undefined {
  const t = raw.trim()
  if (!t) return undefined
  if (t.includes(':')) {
    const parts = t.split(':').map((p) => Number(p))
    if (parts.length > 3 || parts.some((n) => !Number.isFinite(n) || n < 0)) return undefined
    if (parts.slice(1).some((n) => n >= 60)) return undefined
    const sec = parts.reduce((acc, n) => acc * 60 + n, 0)
    return sec > 0 ? Math.round(sec) : undefined
  }
  const min = Number(t.replace(',', '.'))
  return Number.isFinite(min) && min > 0 ? Math.round(min * 60) : undefined
}

/** Seconds as a clock: 452 → "7:32", 3750 → "1:02:30". */
export function formatClock(sec: number): string {
  const s = Math.round(sec)
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`
}

/** A slot logged per set whose sets are holds: seconds, not reps — a static
 *  hold, or an isometric practised in sets (Ido's skill ladders prescribe
 *  `sets: 3`, so they get the set logger, and it must ask for seconds). */
export function isHoldSlot(slotType: string | undefined, load: { hold_seconds?: number | null },
                           exercise?: OutcomeExercise | null): boolean {
  return slotType === 'static_hold' || load.hold_seconds != null
    || (slotType === 'skill_practice' && !!exercise?.movement_patterns?.includes('isometric'))
}
