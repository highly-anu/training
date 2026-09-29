import type { WorkoutMatch } from '@/api/types'

/**
 * Deciding whether a stored match belongs to the session in front of you.
 *
 * `sessionKey` is program-relative — `"3-Monday-0"` names a different session in
 * every plan the athlete has ever had. So a match recorded against a program
 * that has since been replaced matched the *current* program's week 3 Monday on
 * key alone, and the UI showed a finished block's Zone 2 run as this block's
 * squat day, complete with a compliance score comparing the two.
 *
 * `sessionUid` (`"<programVersionId>:w<weekIndex>-<Day>-<index>"`, written by the
 * server — see src/program_history.py) names one session of one program version.
 * When a match has one and it belongs to another version, it is not a match for
 * this session and must be rejected outright.
 *
 * A match with no uid is kept on the legacy key path: it predates program
 * history, or nothing could resolve it without guessing. Silently dropping those
 * would hide real data, so they behave exactly as they always did.
 */

/** Both spellings of a session key in circulation: indexed, and day-level. */
export function sessionKeyVariants(dayKey: string, sessionIndex?: number): string[] {
  return sessionIndex == null ? [dayKey] : [`${dayKey}-${sessionIndex}`, dayKey]
}

function belongsToVersion(match: WorkoutMatch, programVersionId?: string | null): boolean {
  if (!match.sessionUid) return true          // predates history — trust the key
  if (!programVersionId) return true          // we do not know; do not hide data
  return match.sessionUid.startsWith(`${programVersionId}:`)
}

/**
 * The live match for a session of the program currently on screen.
 *
 * `keys` should be most-specific-first — a day-level key is shared by every
 * session on that day, so it must never win over an indexed one.
 */
export function findSessionMatch(
  matches: WorkoutMatch[],
  keys: string[],
  programVersionId?: string | null
): WorkoutMatch | undefined {
  const live = matches.filter(
    (m) => m.matchConfidence !== 'rejected' && belongsToVersion(m, programVersionId)
  )
  for (const key of keys) {
    const hit = live.find((m) => m.sessionKey === key)
    if (hit) return hit
  }
  // A day-level key standing in for whatever indexed variant exists.
  const prefix = `${keys[keys.length - 1]}-`
  return live.find((m) => m.sessionKey.startsWith(prefix))
}

/** Whether a session has an actual workout attached to it. */
export function hasSessionMatch(
  matches: WorkoutMatch[],
  keys: string[],
  programVersionId?: string | null
): boolean {
  return findSessionMatch(matches, keys, programVersionId) !== undefined
}

/**
 * Matches that point at a program the athlete is no longer running.
 *
 * Not an error — it is the record of a finished block. Screens that list a
 * session's history can label these rather than hide them.
 */
export function isFromAnotherProgram(
  match: WorkoutMatch,
  programVersionId?: string | null
): boolean {
  return Boolean(match.sessionUid) && Boolean(programVersionId) &&
    !match.sessionUid!.startsWith(`${programVersionId}:`)
}
