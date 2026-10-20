import type { ExerciseAssignment, GeneratedProgram, Session, SlotBlocker } from '@/api/types'

/**
 * Plain words for what the athlete's constraints held back in a program —
 * the slot's `blocked_by` and the session's `substituted_for` /
 * `equipment_scaled`, all set by the generator. Shared by the session card,
 * the preview's session sheet and its Held back tab.
 */

export function idLabel(id: string): string {
  return id.replace(/_/g, ' ')
}

export interface NameLookup {
  exercise?: (id: string) => string | undefined
  flag?: (id: string) => string | undefined
}

/** "Back squat needs barbell, rack" — what emptied one slot. */
export function blockerText(b: SlotBlocker, names: NameLookup = {}): string {
  const ex = b.exercise ? (names.exercise?.(b.exercise) ?? idLabel(b.exercise)) : null
  const flags = (b.flags ?? []).map((f) => names.flag?.(f) ?? idLabel(f)).join(', ')
  switch (b.cause) {
    case 'equipment':
      return `${ex ?? 'It'} needs ${(b.needs ?? []).map(idLabel).join(', ') || 'equipment you have not listed'}`
    case 'injury':
      return `${ex ?? 'It'} is ruled out by ${flags || 'an injury flag'}`
    case 'level': {
      const needs = (b.requires ?? []).map((r) => names.exercise?.(r) ?? idLabel(r))
      return `${ex ?? 'It'} is not unlocked at ${b.level ?? 'your level'}`
        + (needs.length ? ` (needs ${needs.join(', ')})` : '')
    }
    case 'phase':
      return `${ex ?? 'Its lift'} comes in a later phase`
    case 'coverage':
      return "The methodology's own library has nothing for this slot"
  }
}

/** Why an empty slot is empty, from its blocker or the older flags. */
export function emptySlotText(ea: ExerciseAssignment, names: NameLookup = {}): string | null {
  if (ea.exercise || ea.meta || ea.skip_exercise) return null
  if (ea.blocked_by) return blockerText(ea.blocked_by, names)
  if (ea.injury_skip) return 'Ruled out by an injury flag'
  if (ea.equipment_gap) return 'Nothing fits your equipment'
  if (ea.coverage_gap) return "The methodology's own library has nothing for this slot"
  return null
}

/** The slots of a session its constraints left empty. */
export function heldBackSlots(session: Session): ExerciseAssignment[] {
  return (session.exercises ?? []).filter((ea) => emptySlotText(ea) !== null)
}

/** Session-level notes: another modality in its place, or scaled for missing equipment. */
export function sessionNotes(session: Session): string[] {
  const out: string[] = []
  if (session.substituted_for) {
    const why = session.substitution_cause === 'level' ? ' (none written for your level)'
      : session.substitution_cause === 'phase' ? ' (none for this phase)' : ''
    out.push(`In place of ${idLabel(session.substituted_for)}${why}`)
  }
  if (session.equipment_scaled?.length) {
    out.push(`Scaled: written for ${session.equipment_scaled.map(idLabel).join(', ')}`)
  }
  if (!session.archetype && session.error) out.push(session.error)
  return out
}

/** How much of a program its constraints held back: the server's count
 *  (`held_back`, src/blockers.held_back, on every generate), else — a program
 *  stored before it, or a draft whose session was replaced — counted here. */
export function heldBackSummary(program: GeneratedProgram): { slots: number; sessions: number } {
  return program.held_back ?? heldBackCounts(program)
}

/** The same count from the weeks, for a program without the server's. */
export function heldBackCounts(program: GeneratedProgram): { slots: number; sessions: number } {
  let slots = 0
  let sessions = 0
  for (const week of program.weeks ?? []) {
    for (const list of Object.values(week.schedule ?? {})) {
      for (const s of list ?? []) {
        const n = heldBackSlots(s).length
        slots += n
        if (n > 0 || sessionNotes(s).length > 0) sessions += 1
      }
    }
  }
  return { slots, sessions }
}
