import type { ProgressSpecEntry, ProgressSpecExpected, ProgressSpecScope, PrimitiveVocabulary } from '@/api/types'

/**
 * A progress-spec entry in one sentence: what is measured, over which
 * sessions, against what, and when it counts as stalled. Pure, so the
 * Explore cards and the framework "measured by" rows read identically.
 */

const LOAD_FIELD_WORDS: Record<string, string> = {
  duration_minutes: 'the prescribed minutes',
  target_rounds: 'the prescribed rounds',
  hold_seconds: 'the prescribed hold',
  distance_km: 'the prescribed distance',
  weight_kg: 'the prescribed load',
  pack_load_kg: 'the prescribed pack load',
}

const SLOT_TYPE_WORDS: Record<string, string> = {
  sets_reps: 'sets × reps',
  time_domain: 'timed',
  distance: 'distance',
  amrap: 'AMRAP',
  emom: 'EMOM',
  for_time: 'for-time',
  static_hold: 'hold',
  skill_practice: 'skill',
}

function list(items: string[]): string {
  if (items.length <= 1) return items.join('')
  if (items.length === 2) return `${items[0]} and ${items[1]}`
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`
}

function roleWords(globs: string[]): string[] {
  // "*warm*" → "warm-up", "*accessory*" → "accessory": the glob's word, tidied.
  return globs.map((g) => g.replace(/\*/g, '')).map((w) => (w === 'warm' ? 'warm-up' : w === 'cool' ? 'cool-down' : w))
}

export function scopeText(scope: ProgressSpecScope): string {
  const parts: string[] = []
  const on: string[] = []
  if (scope.exercises.length) on.push(list(scope.exercises.map((e) => e.name.toLowerCase())))
  if (scope.archetypes.length) on.push(`the ${list(scope.archetypes.map((a) => a.name.toLowerCase()))} session${scope.archetypes.length > 1 ? 's' : ''}`)
  if (scope.modalities.length) on.push(`${list(scope.modalities.map((m) => m.name.toLowerCase()))} sessions`)
  if (scope.movementPatterns.length) on.push(`${list(scope.movementPatterns.map((p) => p.replace(/_/g, ' ')))} movements`)
  if (on.length) parts.push(`on ${on.join(' in ')}`)
  if (scope.slotTypes.length) parts.push(`${list(scope.slotTypes.map((t) => SLOT_TYPE_WORDS[t] ?? t.replace(/_/g, ' ')))} slots`)
  if (scope.slotRoles.length) parts.push(`(${list(roleWords(scope.slotRoles))} roles)`)
  if (scope.excludeSlotRoles.length) parts.push(`(not ${list(roleWords(scope.excludeSlotRoles))})`)
  if (scope.frameworks.length) parts.push(`during ${list(scope.frameworks.map((f) => f.name))}`)
  return parts.join(' ')
}

export function expectedText(expected: ProgressSpecExpected, entry?: Pick<ProgressSpecEntry, 'rpmTarget' | 'targetLevel'>): string {
  if (entry?.rpmTarget != null) return `target ${entry.rpmTarget} rpm`
  if (entry?.targetLevel) return `target level ${entry.targetLevel}`
  switch (expected.kind) {
    case 'prescribed': return 'vs the prescribed load'
    case 'achieved_plus_increment': return "expected to rise by the exercise's increment every session"
    case 'load_field': return `vs ${LOAD_FIELD_WORDS[expected.field] ?? `the prescribed ${expected.field.replace(/_/g, ' ')}`}`
    case 'framework_field': return `vs the framework's ${expected.field.replace(/_/g, ' ')}`
    case 'constant': return `target ${expected.value}${expected.unit ? ` ${expected.unit}` : ''}`
    default: return ''
  }
}

export function stallText(stall: ProgressSpecEntry['stall']): string {
  if (!stall) return ''
  return `stalled after ${stall.sessions} flat session${stall.sessions === 1 ? '' : 's'}`
}

export function entrySentence(entry: ProgressSpecEntry, vocab: PrimitiveVocabulary | undefined): string {
  const head = vocab?.measures ?? entry.primitive.replace(/_/g, ' ')
  const scope = scopeText(entry.scope)
  const expected = expectedText(entry.expected, entry)
  const stall = stallText(entry.stall)
  let s = head
  if (scope) s += ` ${scope}`
  if (expected) s += `, ${expected}`
  if (stall) s += `; ${stall}`
  return `${s}.`
}
