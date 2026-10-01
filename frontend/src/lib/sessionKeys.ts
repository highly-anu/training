/**
 * Program-relative session keys.
 *
 * Two spellings are in use: the day key `"3-Monday"` and the per-session key
 * `"3-Monday-1"` (week number, day name, index within the day). Parsing lives
 * here; *resolving* a key against a program version — whether a stored match
 * still names the session on screen — is lib/sessionMatching.ts.
 */
export interface ParsedSessionKey {
  weekNumber: number
  dayName: string
  /** Null for a day-level key. */
  sessionIndex: number | null
  /** The `"week-Day"` prefix, with any session index removed. */
  dayKey: string
}

export function parseSessionKey(key: string): ParsedSessionKey | null {
  const firstDash = key.indexOf('-')
  if (firstDash <= 0) return null
  const weekNumber = parseInt(key.slice(0, firstDash), 10)
  if (isNaN(weekNumber)) return null
  let rest = key.slice(firstDash + 1)
  let sessionIndex: number | null = null
  const lastDash = rest.lastIndexOf('-')
  if (lastDash >= 0) {
    const tail = rest.slice(lastDash + 1)
    const idx = parseInt(tail, 10)
    if (!isNaN(idx) && String(idx) === tail) {
      sessionIndex = idx
      rest = rest.slice(0, lastDash)
    }
  }
  if (!rest) return null
  return { weekNumber, dayName: rest, sessionIndex, dayKey: `${weekNumber}-${rest}` }
}

/** "Week 3 — Monday", plus "· session 2" when the key names a second session that day. */
export function sessionLabel(key: string): string {
  const parsed = parseSessionKey(key)
  if (!parsed) return key
  const base = `Week ${parsed.weekNumber} — ${parsed.dayName}`
  return parsed.sessionIndex != null && parsed.sessionIndex > 0
    ? `${base} · session ${parsed.sessionIndex + 1}`
    : base
}
