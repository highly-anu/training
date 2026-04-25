import type { GoalProfile, AthleteConstraints, GoalExpectations } from '@/api/types'

export interface FeasibilitySignal {
  code: string
  severity: 'error' | 'warning' | 'info'
  label: string        // short pill label
  message: string
  suggestion?: string
  quickFix?: {
    label: string
    constraintPatch?: Partial<AthleteConstraints>
    numWeeks?: number
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

export function blendExpectations(
  goals: GoalProfile[],
  selectedGoalIds: string[],
  goalWeights: Record<string, number>,
  opts?: {
    sourceMode?: 'philosophy' | 'blend' | 'custom' | null
    frameworks?: any[]
    selectedFrameworkId?: string | null
    selectedPhilosophyIds?: string[]
    philosophies?: any[]
  },
): GoalExpectations | null {
  // For philosophy mode with sequential framework group, aggregate framework expectations
  if (opts?.sourceMode === 'philosophy' && opts.philosophies && opts.frameworks) {
    const phil = opts.philosophies.find((p: any) => p.id === opts.selectedPhilosophyIds?.[0])

    // Find sequential group (new approach)
    const sequentialGroup = phil?.framework_groups?.find((g: any) => g.type === 'sequential')
    const phases = sequentialGroup?.canonical_phase_sequence
      || (phil?.frameworks_are_phases && phil.canonical_phase_sequence)  // Legacy fallback

    if (phases) {
      const phaseFrameworks = phases
        .map((phase: any) => opts.frameworks!.find((f: any) => f.id === phase.framework_id))
        .filter((f: any) => f?.expectations)

      if (phaseFrameworks.length > 0) {
        const totalWeeks = phases.reduce((s: number, p: any) => s + (p.weeks ?? 0), 0)
        const weighted = (fn: (e: GoalExpectations) => number): number => {
          let sum = 0
          for (let i = 0; i < phaseFrameworks.length; i++) {
            const fw = phaseFrameworks[i]
            const phaseWeeks = phases[i]?.weeks ?? 0
            const weight = phaseWeeks / totalWeeks
            if (fw.expectations) sum += fn(fw.expectations) * weight
          }
          return sum
        }

        const longDays = phaseFrameworks.filter((f: any) => f.expectations?.ideal_long_session_minutes != null)

        return {
          min_weeks: totalWeeks,
          ideal_weeks: totalWeeks,
          min_days_per_week: Math.round(weighted((e) => e.min_days_per_week)),
          ideal_days_per_week: Math.round(weighted((e) => e.ideal_days_per_week)),
          min_session_minutes: Math.round(weighted((e) => e.min_session_minutes)),
          ideal_session_minutes: Math.round(weighted((e) => e.ideal_session_minutes)),
          ideal_long_session_minutes: longDays.length
            ? Math.round(longDays.reduce((s: number, f: any) => s + f.expectations!.ideal_long_session_minutes!, 0) / longDays.length)
            : undefined,
          supports_split_days: phaseFrameworks.some((f: any) => f.expectations?.supports_split_days),
        }
      }
    }

    // Single framework override or primary framework
    if (opts.selectedFrameworkId) {
      const fw = opts.frameworks.find((f: any) => f.id === opts.selectedFrameworkId)
      if (fw?.expectations) return fw.expectations
    }
  }

  // Fall back to goal-based expectations
  const selected = goals.filter((g) => selectedGoalIds.includes(g.id))
  if (!selected.length) return null

  const total = selected.reduce((s, g) => s + (goalWeights[g.id] ?? 1), 0)
  const weighted = (fn: (e: GoalExpectations) => number): number =>
    selected.reduce((sum, g) => {
      const w = (goalWeights[g.id] ?? 1) / total
      return sum + (g.expectations ? fn(g.expectations) * w : 0)
    }, 0)

  const withExp = selected.filter((g) => g.expectations)
  if (!withExp.length) return null

  const longDays = withExp.filter((g) => g.expectations!.ideal_long_session_minutes != null)

  return {
    min_weeks:           Math.round(weighted((e) => e.min_weeks)),
    ideal_weeks:         Math.round(weighted((e) => e.ideal_weeks)),
    min_days_per_week:   Math.round(weighted((e) => e.min_days_per_week)),
    ideal_days_per_week: Math.round(weighted((e) => e.ideal_days_per_week)),
    min_session_minutes: Math.round(weighted((e) => e.min_session_minutes)),
    ideal_session_minutes: Math.round(weighted((e) => e.ideal_session_minutes)),
    ideal_long_session_minutes: longDays.length
      ? Math.round(longDays.reduce((s, g) => s + g.expectations!.ideal_long_session_minutes!, 0) / longDays.length)
      : undefined,
    supports_split_days: withExp.some((g) => g.expectations!.supports_split_days),
  }
}

function effectiveSessionTime(constraints: Partial<AthleteConstraints>): number {
  const wd = constraints.weekday_session_minutes
  const we = constraints.weekend_session_minutes
  if (wd && we) return Math.round((wd * 5 + we * 2) / 7)
  return constraints.session_time_minutes ?? 60
}

// ── Main export ────────────────────────────────────────────────────────────────

export function computeFeasibility(
  goals: GoalProfile[],
  selectedGoalIds: string[],
  goalWeights: Record<string, number>,
  constraints: Partial<AthleteConstraints>,
  numWeeks: number | null,
): FeasibilitySignal[] {
  if (!selectedGoalIds.length) return []

  const signals: FeasibilitySignal[] = []
  const exp = blendExpectations(goals, selectedGoalIds, goalWeights)
  if (!exp) return []

  const selectedGoals = goals.filter((g) => selectedGoalIds.includes(g.id))

  // 1. Goal incompatibility
  for (const g of selectedGoals) {
    const incompatIds = (g.incompatible_with ?? []) as string[]
    for (const otherId of incompatIds) {
      if (selectedGoalIds.includes(otherId)) {
        const other = goals.find((x) => x.id === otherId)
        signals.push({
          code: 'GOAL_INCOMPATIBLE',
          severity: 'error',
          label: 'Conflicting goals',
          message: `"${g.name}" and "${other?.name ?? otherId}" are incompatible — pursuing both produces suboptimal results in each domain.`,
          suggestion: 'Remove one of the conflicting goals, or reduce its weight significantly.',
        })
      }
    }
  }

  // 2. Program duration
  const weeks = numWeeks ?? 0
  if (weeks > 0) {
    if (weeks < exp.min_weeks) {
      signals.push({
        code: 'DURATION_TOO_SHORT',
        severity: 'error',
        label: `${weeks}w (min ${exp.min_weeks}w)`,
        message: `${weeks} weeks is too short for this goal — you need at least ${exp.min_weeks} weeks to complete meaningful adaptation cycles.`,
        suggestion: `Extend to at least ${exp.min_weeks} weeks. The full program is ${exp.ideal_weeks} weeks.`,
        quickFix: { label: `Set to ${exp.min_weeks} weeks`, numWeeks: exp.min_weeks },
      })
    } else if (weeks < exp.ideal_weeks) {
      signals.push({
        code: 'DURATION_SHORT',
        severity: 'warning',
        label: `${weeks}w (ideal ${exp.ideal_weeks}w)`,
        message: `${weeks} weeks will work but the full program is ${exp.ideal_weeks} weeks — some phases may be compressed.`,
        suggestion: `Consider extending to ${exp.ideal_weeks} weeks for the complete phase arc.`,
        quickFix: { label: `Set to ${exp.ideal_weeks} weeks`, numWeeks: exp.ideal_weeks },
      })
    } else {
      signals.push({
        code: 'DURATION_OK',
        severity: 'info',
        label: `${weeks}w ✓`,
        message: `Program duration of ${weeks} weeks covers the full phase sequence.`,
      })
    }
  }

  // 3. Days per week
  const days = constraints.days_per_week ?? 4
  if (days < exp.min_days_per_week) {
    signals.push({
      code: 'DAYS_TOO_FEW',
      severity: 'error',
      label: `${days} days (min ${exp.min_days_per_week})`,
      message: `${days} days/week is below the minimum ${exp.min_days_per_week} needed to schedule this goal's required modalities.`,
      suggestion: `Increase to at least ${exp.min_days_per_week} days/week.`,
      quickFix: { label: `Set to ${exp.min_days_per_week} days`, constraintPatch: { days_per_week: exp.min_days_per_week } },
    })
  } else if (days < exp.ideal_days_per_week) {
    signals.push({
      code: 'DAYS_BELOW_IDEAL',
      severity: 'warning',
      label: `${days} days (ideal ${exp.ideal_days_per_week})`,
      message: `${days} days/week will work but lower-priority modalities may be dropped. Ideal is ${exp.ideal_days_per_week} days.`,
      suggestion: `Add ${exp.ideal_days_per_week - days} more training day(s) to cover all goal modalities.`,
      quickFix: { label: `Set to ${exp.ideal_days_per_week} days`, constraintPatch: { days_per_week: exp.ideal_days_per_week } },
    })
  } else {
    signals.push({
      code: 'DAYS_OK',
      severity: 'info',
      label: `${days} days ✓`,
      message: `${days} days/week meets the goal's scheduling requirements.`,
    })
  }

  // 4. Session time
  const effectiveTime = effectiveSessionTime(constraints)
  if (effectiveTime < exp.min_session_minutes) {
    signals.push({
      code: 'SESSION_TIME_TOO_SHORT',
      severity: 'error',
      label: `${effectiveTime}m (min ${exp.min_session_minutes}m)`,
      message: `Effective session time of ~${effectiveTime} min is below the minimum ${exp.min_session_minutes} min needed for primary archetypes.`,
      suggestion: `Increase weekday time to at least ${exp.min_session_minutes} min.`,
      quickFix: {
        label: `Set to ${exp.min_session_minutes} min`,
        constraintPatch: {
          session_time_minutes: exp.min_session_minutes,
          weekday_session_minutes: exp.min_session_minutes,
          weekend_session_minutes: Math.max(constraints.weekend_session_minutes ?? 90, exp.ideal_session_minutes),
        },
      },
    })
  } else if (effectiveTime < exp.ideal_session_minutes) {
    signals.push({
      code: 'SESSION_TIME_SHORT',
      severity: 'warning',
      label: `~${effectiveTime}m (ideal ${exp.ideal_session_minutes}m)`,
      message: `Sessions average ~${effectiveTime} min — some archetypes (e.g. Zone 2 runs, barbell strength) work best at ${exp.ideal_session_minutes}+ min.`,
      suggestion: `Consider ${exp.ideal_session_minutes} min on primary days, or enable longer weekend sessions.`,
    })
  } else {
    signals.push({
      code: 'SESSION_TIME_OK',
      severity: 'info',
      label: `${effectiveTime}m ✓`,
      message: `Session length is adequate for this goal's primary archetypes.`,
    })
  }

  // 5. Split sessions opportunity
  if (exp.supports_split_days && !constraints.allow_split_sessions) {
    signals.push({
      code: 'SPLIT_SESSIONS_AVAILABLE',
      severity: 'info',
      label: 'Secondary sessions off',
      message: `This goal benefits from short secondary sessions (mobility/skill work, 15–20 min) paired with primary training days.`,
      suggestion: 'Enable "Add recovery sessions" to have the scheduler pair mobility work with strength and conditioning days.',
      quickFix: { label: 'Enable recovery sessions', constraintPatch: { allow_split_sessions: true } },
    })
  }

  return signals
}
