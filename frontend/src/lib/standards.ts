/**
 * Words and shapes for the standards, shared by every screen that draws one.
 * Levels are computed by the server (src/standards.py); nothing here does maths.
 */

export const STANDARD_LEVELS = ['entry', 'intermediate', 'advanced', 'elite'] as const
export type StandardLevel = typeof STANDARD_LEVELS[number]

/** A level as words: "Advanced", or "Below entry" for a result under the first rung. */
export function levelName(level: string | null | undefined): string {
  if (!level) return 'Below entry'
  return level.charAt(0).toUpperCase() + level.slice(1)
}

/**
 * The thresholds as the server prints them. Older cached documents carry only
 * numbers, so fall back to number + unit for those.
 */
export function thresholdTexts(
  text: Partial<Record<string, string | null>> | undefined,
  values: Partial<Record<string, number | null>> | undefined,
  unit = '',
): Partial<Record<StandardLevel, string>> {
  const out: Partial<Record<StandardLevel, string>> = {}
  for (const lvl of STANDARD_LEVELS) {
    const t = text?.[lvl]
    const v = values?.[lvl]
    if (t) out[lvl] = t
    else if (v != null) out[lvl] = `${v}${unit}`
  }
  return out
}
