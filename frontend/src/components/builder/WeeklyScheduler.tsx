import { useMemo } from 'react'
import { Switch } from '@/components/ui/switch'
import { cn } from '@/lib/utils'
import { useBuilderStore } from '@/store/builderStore'
import { useGoals } from '@/api/goals'
import { blendExpectations } from '@/lib/feasibility'
import type { DayConfig } from '@/api/types'

// ── Constants ─────────────────────────────────────────────────────────────────

const DAYS = [
  { day: 1, short: 'Mon', label: 'Monday' },
  { day: 2, short: 'Tue', label: 'Tuesday' },
  { day: 3, short: 'Wed', label: 'Wednesday' },
  { day: 4, short: 'Thu', label: 'Thursday' },
  { day: 5, short: 'Fri', label: 'Friday' },
  { day: 6, short: 'Sat', label: 'Saturday' },
  { day: 7, short: 'Sun', label: 'Sunday' },
] as const

// Value 0 = Rest sentinel
const TIME_OPTIONS = [0, 30, 45, 60, 75, 90, 120, 150, 180] as const

function fmtOption(m: number): string {
  if (m === 0)   return 'Rest'
  if (m === 180) return '3h+'
  const h = Math.floor(m / 60)
  const rem = m % 60
  if (h === 0) return `${rem}m`
  return rem > 0 ? `${h}h ${rem}m` : `${h}h`
}

// Default spread per days_per_week count
const DEFAULT_SPREADS: Record<number, number[]> = {
  2: [1, 5],
  3: [1, 4, 7],
  4: [1, 3, 5, 7],
  5: [1, 2, 4, 6, 7],
  6: [1, 2, 3, 5, 6, 7],
  7: [1, 2, 3, 4, 5, 6, 7],
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtMin(m: number): string {
  if (m === 180) return '3h+'
  if (m <= 0) return 'Rest'
  const h = Math.floor(m / 60)
  const rem = m % 60
  if (h === 0) return `${rem}m`
  return rem > 0 ? `${h}h ${rem}m` : `${h}h`
}

function weeklyTotalFromConfigs(configs: Record<number, DayConfig>): number {
  return Object.values(configs).reduce((sum, c) => sum + (c.minutes > 0 ? c.minutes : 0), 0)
}

function buildDefaultConfigs(
  days: number[],
  weekdayMin: number,
  weekendMin: number,
): Record<number, DayConfig> {
  const configs: Record<number, DayConfig> = {}
  for (const d of days) {
    configs[d] = { minutes: d <= 5 ? weekdayMin : weekendMin, has_secondary: false }
  }
  return configs
}

// ── Component ─────────────────────────────────────────────────────────────────

export function WeeklyScheduler() {
  const { constraints, updateConstraints, selectedGoalIds, goalWeights } = useBuilderStore()
  const { data: goals = [] } = useGoals()

  const exp = useMemo(
    () => blendExpectations(goals, selectedGoalIds, goalWeights),
    [goals, selectedGoalIds, goalWeights],
  )

  const dayConfigs: Record<number, DayConfig> = useMemo(() => {
    if (constraints.day_configs && Object.keys(constraints.day_configs).length > 0) {
      return constraints.day_configs
    }
    const activeDays = constraints.preferred_days?.length
      ? constraints.preferred_days
      : DEFAULT_SPREADS[constraints.days_per_week ?? 4] ?? DEFAULT_SPREADS[4]
    return buildDefaultConfigs(
      activeDays,
      constraints.weekday_session_minutes ?? 60,
      constraints.weekend_session_minutes ?? 90,
    )
  }, [constraints])

  const weeklyTotal = weeklyTotalFromConfigs(dayConfigs)
  // When a goal has a long day, account for it: (days-1) × typical + 1 × long
  const idealWeeklyTotal = exp
    ? exp.ideal_long_session_minutes != null
      ? (exp.ideal_days_per_week - 1) * exp.ideal_session_minutes + exp.ideal_long_session_minutes
      : exp.ideal_days_per_week * exp.ideal_session_minutes
    : null
  const coverage =
    idealWeeklyTotal && idealWeeklyTotal > 0
      ? Math.min(weeklyTotal / idealWeeklyTotal, 1.5)
      : null

  const coverageColor =
    coverage == null ? 'bg-muted'
      : coverage >= 1   ? 'bg-emerald-500'
      : coverage >= 0.8 ? 'bg-sky-500'
      : coverage >= 0.6 ? 'bg-amber-500'
      : 'bg-destructive'

  const coveragePct = coverage != null ? Math.min(Math.round(coverage * 100), 100) : 0

  // ── Handlers ────────────────────────────────────────────────────────────────

  function applyDayConfigs(next: Record<number, DayConfig>) {
    const newActiveDays = Object.entries(next)
      .filter(([, c]) => c.minutes > 0)
      .map(([d]) => Number(d))
      .sort((a, b) => a - b)
    const secondaryDays = Object.entries(next)
      .filter(([, c]) => c.has_secondary)
      .map(([d]) => Number(d))
    updateConstraints({
      day_configs: next,
      days_per_week: newActiveDays.length,
      preferred_days: newActiveDays,
      secondary_days: secondaryDays,
      allow_split_sessions: secondaryDays.length > 0,
    })
  }

  function setDayMinutes(day: number, minutes: number) {
    const existing = dayConfigs[day] ?? { minutes: 0, has_secondary: false }
    applyDayConfigs({ ...dayConfigs, [day]: { ...existing, minutes } })
  }

  function toggleSecondary(day: number) {
    const existing = dayConfigs[day] ?? { minutes: 0, has_secondary: false }
    applyDayConfigs({
      ...dayConfigs,
      [day]: { ...existing, has_secondary: !existing.has_secondary },
    })
  }

  // true when every active training day has a secondary session
  const allSecondaryOn = DAYS.every(({ day }) => {
    const c = dayConfigs[day]
    if (!c || c.minutes === 0) return true // rest days don't count
    return c.has_secondary
  })

  function setAllSecondary(enabled: boolean) {
    const next = { ...dayConfigs }
    for (const { day } of DAYS) {
      const c = next[day] ?? { minutes: 0, has_secondary: false }
      next[day] = { ...c, has_secondary: c.minutes > 0 ? enabled : c.has_secondary }
    }
    applyDayConfigs(next)
  }

  function applyIdeal() {
    if (!exp) return
    const spread = DEFAULT_SPREADS[exp.ideal_days_per_week] ?? DEFAULT_SPREADS[4]
    const next = buildDefaultConfigs(spread, exp.ideal_session_minutes, exp.ideal_session_minutes)
    const longDay = exp.ideal_long_session_minutes != null ? spread[spread.length - 1] : null
    if (longDay != null) {
      next[longDay] = { minutes: 180, has_secondary: false } // long day — no secondary
    }
    if (exp.supports_split_days) {
      for (const day of spread) {
        if (day !== longDay) next[day] = { ...next[day], has_secondary: true }
      }
    }
    const secondaryDays = Object.entries(next)
      .filter(([, c]) => c.has_secondary)
      .map(([d]) => Number(d))
    updateConstraints({
      day_configs: next,
      days_per_week: spread.length,
      preferred_days: spread,
      weekday_session_minutes: exp.ideal_session_minutes,
      weekend_session_minutes: exp.ideal_session_minutes,
      session_time_minutes: exp.ideal_session_minutes,
      secondary_days: secondaryDays,
      allow_split_sessions: secondaryDays.length > 0,
    })
  }

  function applyMinimum() {
    if (!exp) return
    const spread = DEFAULT_SPREADS[exp.min_days_per_week] ?? DEFAULT_SPREADS[3]
    const next = buildDefaultConfigs(spread, exp.min_session_minutes, exp.min_session_minutes)
    updateConstraints({
      day_configs: next,
      days_per_week: spread.length,
      preferred_days: spread,
      weekday_session_minutes: exp.min_session_minutes,
      weekend_session_minutes: exp.min_session_minutes,
      session_time_minutes: exp.min_session_minutes,
      secondary_days: [],
      allow_split_sessions: false,
    })
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-5">
      {/* Ideal banner */}
      {exp && (
        <div className="rounded-lg border border-dashed border-border bg-muted/20 px-4 py-3 flex flex-wrap items-center justify-between gap-3">
          <div className="space-y-0.5">
            <p className="text-xs font-semibold text-foreground/70 uppercase tracking-wider">Ideal for this goal</p>
            <p className="text-sm text-foreground">
              <span className="font-semibold">{exp.ideal_days_per_week} days</span>
              {' · '}
              <span className="font-semibold">{exp.ideal_session_minutes} min</span> typical
              {exp.ideal_long_session_minutes != null && (
                <> {' · '}<span className="font-semibold">{fmtMin(exp.ideal_long_session_minutes)}</span> long effort</>
              )}
              {' · '}
              <span className="font-semibold">{fmtMin(idealWeeklyTotal ?? exp.ideal_days_per_week * exp.ideal_session_minutes)}</span>/week
            </p>
            {exp.notes && (
              <p className="text-[11px] text-muted-foreground leading-relaxed max-w-sm">{exp.notes}</p>
            )}
            {exp.supports_split_days && (
              <label className="flex items-center gap-2 cursor-pointer pt-1">
                <Switch
                  checked={allSecondaryOn}
                  onCheckedChange={setAllSecondary}
                  className="scale-75 origin-left"
                />
                <span className="text-[11px] text-muted-foreground">
                  Secondary session after every training day
                </span>
              </label>
            )}
          </div>
          <div className="flex gap-2 shrink-0">
            <button
              type="button"
              onClick={applyMinimum}
              className="text-xs px-3 py-1.5 rounded-md border border-border text-muted-foreground hover:text-foreground hover:border-primary/50 transition-colors"
            >
              Set minimum
            </button>
            <button
              type="button"
              onClick={applyIdeal}
              className="text-xs px-3 py-1.5 rounded-md border border-primary bg-primary/10 text-primary font-medium hover:bg-primary/20 transition-colors"
            >
              Match ideal
            </button>
          </div>
        </div>
      )}

      {/* Per-day list — all 7 days always shown */}
      <div className="space-y-1.5">
        {DAYS.map(({ day, short }) => {
          const config = dayConfigs[day] ?? { minutes: 0, has_secondary: false }
          const isActive = config.minutes > 0
          const isWeekend = day >= 6
          const idealMin = exp?.ideal_session_minutes

          return (
            <div key={day} className="flex flex-wrap items-center gap-1.5">
              {/* Day label */}
              <span className={cn(
                'text-[11px] font-semibold w-8 shrink-0',
                isActive
                  ? isWeekend ? 'text-sky-600 dark:text-sky-400' : 'text-primary'
                  : 'text-muted-foreground',
              )}>
                {short}
              </span>

              {/* Time + Rest pills */}
              {TIME_OPTIONS.map((t) => {
                const isRest = t === 0
                const isSelected = isRest ? !isActive : (isActive && config.minutes === t)
                const isIdeal = !isRest && idealMin === t && !isSelected

                return (
                  <button
                    key={t}
                    type="button"
                    onClick={() => setDayMinutes(day, t)}
                    title={isIdeal ? 'Ideal for this goal' : undefined}
                    className={cn(
                      'h-6 px-2 rounded-md text-[11px] font-medium border transition-colors',
                      isSelected && isRest
                        ? 'bg-muted text-muted-foreground border-border cursor-default'
                        : isSelected
                          ? isWeekend
                            ? 'bg-sky-500 text-white border-sky-500'
                            : 'bg-primary text-primary-foreground border-primary'
                          : isIdeal
                            ? 'border-primary/40 text-primary/80 bg-primary/5 hover:bg-primary/15'
                            : isRest
                              ? 'border-border text-muted-foreground/60 hover:border-destructive/40 hover:text-destructive'
                              : 'border-border text-muted-foreground hover:border-primary/40 hover:text-foreground',
                    )}
                  >
                    {fmtOption(t)}
                  </button>
                )
              })}

              {/* Mobility toggle */}
              {exp?.supports_split_days && (
                <button
                  type="button"
                  onClick={() => toggleSecondary(day)}
                  title={isActive
                    ? 'Add a secondary support session on this day'
                    : 'Add a secondary support session on this rest day'}
                  className={cn(
                    'ml-1 text-[10px] px-2 py-0.5 rounded-md border transition-colors',
                    config.has_secondary
                      ? 'border-emerald-500/50 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
                      : 'border-border text-muted-foreground/50 hover:border-emerald-400/60 hover:text-emerald-600/80',
                  )}
                >
                  + sec
                </button>
              )}
            </div>
          )
        })}
      </div>

      {/* Coverage bar */}
      <div className="space-y-1.5">
        <div className="flex items-center justify-between text-[11px]">
          <span className="text-muted-foreground">
            Weekly training — <span className="font-medium text-foreground">{fmtMin(weeklyTotal)}</span>
            {idealWeeklyTotal != null && (
              <span className="text-muted-foreground"> of {fmtMin(idealWeeklyTotal)} ideal</span>
            )}
          </span>
          {coverage != null && (
            <span className={cn(
              'font-semibold',
              coverage >= 1   ? 'text-emerald-600 dark:text-emerald-400'
                : coverage >= 0.8 ? 'text-sky-600 dark:text-sky-400'
                : coverage >= 0.6 ? 'text-amber-600 dark:text-amber-400'
                : 'text-destructive',
            )}>
              {Math.round(coverage * 100)}%
            </span>
          )}
        </div>
        <div className="h-1.5 w-full rounded-full bg-muted overflow-hidden">
          <div
            className={cn('h-full rounded-full transition-all duration-300', coverageColor)}
            style={{ width: `${coveragePct}%` }}
          />
        </div>
        {coverage != null && coverage < 0.6 && (
          <p className="text-[11px] text-destructive">
            Below 60% of ideal volume — consider adding more days or time.
          </p>
        )}
      </div>
    </div>
  )
}
