import type { AthleteConstraints, Framework } from '@/api/types'

/**
 * Whether a training style can actually run under the athlete's constraints.
 *
 * The builder picks a style at step 2 and constraints at step 3, so a style
 * chosen earlier can become invalid later. Nothing used to check this until
 * Generate, where the backend rejected the combination with a red alert.
 *
 * Mirrors the server-side checks in src/validator.py `_check_days` /
 * `_check_session_time`, so the two cannot drift silently.
 */

export type StyleIssueSeverity = 'error' | 'warning'

export interface StyleIssue {
  severity: StyleIssueSeverity
  /** Short reason shown on the style card, e.g. "Needs 4+ days/week". */
  label: string
  message: string
  constraintPatch?: Partial<AthleteConstraints>
}

export interface StyleCompatibility {
  /** False when a hard constraint rules the style out. */
  selectable: boolean
  issues: StyleIssue[]
}

function effectiveSessionTime(constraints: Partial<AthleteConstraints>): number {
  const wd = constraints.weekday_session_minutes
  const we = constraints.weekend_session_minutes
  if (wd && we) return Math.round((wd * 5 + we * 2) / 7)
  return constraints.session_time_minutes ?? 60
}

export function checkStyleCompatibility(
  framework: Framework,
  constraints: Partial<AthleteConstraints>,
): StyleCompatibility {
  const issues: StyleIssue[] = []
  const applicable = (framework.applicable_when ?? {}) as Record<string, any>
  const exp = framework.expectations

  const days = constraints.days_per_week ?? 4
  // applicable_when is the hard gate the backend enforces; expectations is the
  // authored recommendation. Take the stricter of the two for the minimum.
  const minDays = Math.max(
    applicable.days_per_week_min ?? 1,
    exp?.min_days_per_week ?? 1,
  )
  const maxDays = applicable.days_per_week_max ?? 7

  if (days < minDays) {
    issues.push({
      severity: 'error',
      label: `Needs ${minDays}+ days/week`,
      message: `${framework.name} requires at least ${minDays} training days per week; you have ${days}.`,
      constraintPatch: { days_per_week: minDays },
    })
  } else if (days > maxDays) {
    issues.push({
      severity: 'error',
      label: `Max ${maxDays} days/week`,
      message: `${framework.name} supports at most ${maxDays} training days per week; you have ${days}.`,
      constraintPatch: { days_per_week: maxDays },
    })
  }

  const minutes = effectiveSessionTime(constraints)
  if (exp?.min_session_minutes && minutes < exp.min_session_minutes) {
    issues.push({
      severity: 'error',
      label: `Needs ${exp.min_session_minutes}+ min`,
      message: `${framework.name} needs sessions of at least ${exp.min_session_minutes} min; yours average ~${minutes} min.`,
      constraintPatch: {
        session_time_minutes: exp.min_session_minutes,
        weekday_session_minutes: exp.min_session_minutes,
      },
    })
  }

  const levels: string[] = applicable.training_level ?? []
  const level = constraints.training_level
  if (levels.length && level && !levels.includes(level)) {
    // The backend warns rather than errors here, so keep the style selectable.
    issues.push({
      severity: 'warning',
      label: `For ${levels.join('/')} athletes`,
      message: `${framework.name} is written for ${levels.join(', ')} athletes; you are set to ${level}.`,
    })
  }

  return {
    selectable: !issues.some((i) => i.severity === 'error'),
    issues,
  }
}

/** The first blocking reason, for a one-line label on a disabled card. */
export function blockingReason(c: StyleCompatibility): StyleIssue | undefined {
  return c.issues.find((i) => i.severity === 'error')
}
