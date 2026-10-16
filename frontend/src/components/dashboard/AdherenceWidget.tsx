import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { TrendingUp, TrendingDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useProgramAnalytics } from '@/api/analytics'
import { queryKeys } from '@/api/queryKeys'
import { useBioStore } from '@/store/bioStore'
import { STATUS_STYLES } from '@/lib/statusColors'
import { statusLabel, statusLevel } from '@/components/analytics/status'

/** Per-week bar colour: the phone's thresholds (TodayView), 70 % and 45 %. */
function statusFor(pct: number): 'green' | 'yellow' | 'red' {
  return pct >= 70 ? 'green' : pct >= 45 ? 'yellow' : 'red'
}

/**
 * Today's adherence card: am I doing the plan? The program scorecard
 * (`/analytics/program`) — completion so far, this week, the last four weeks —
 * and the scorecard's own verdict: under 70 % of the committed work is off
 * plan whatever the total says. A session counts when it was logged complete
 * or has a matched workout; only sessions whose day has come are due.
 *
 * Called Development until 2026-10-16, beside a Progress card whose score was
 * this same completion until a measure had a trend — two cards, one number.
 * Progress now shows the methodology's own currency (ProgressWidget), and the
 * badge here is the scorecard's verdict rather than a threshold on the total,
 * which could read "On Track" while the Program tab said off plan.
 */
export function AdherenceWidget() {
  const { data, isLoading } = useProgramAnalytics()
  const sc = data?.scorecard

  // A completion, an undo or a match changes the scorecard: refetch rather
  // than wait out the query's staleTime.
  const queryClient = useQueryClient()
  const completions = useBioStore((s) =>
    Object.values(s.sessionPerformanceLogs).filter((l) => l?.completedAt).length)
  const matches = useBioStore((s) => s.workoutMatches.length)
  useEffect(() => {
    void queryClient.invalidateQueries({ queryKey: queryKeys.analytics.program })
  }, [completions, matches, queryClient])

  if (isLoading) {
    return (
      <div className="h-full rounded-xl border bg-card p-4 ring-1 ring-border">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Adherence</h2>
      </div>
    )
  }

  if (!sc || !sc.plannedSessions) {
    return (
      <div className="h-full rounded-xl border bg-card p-4 space-y-3 ring-1 ring-border">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Adherence
        </h2>
        <p className="text-[11px] text-muted-foreground/70 italic">
          Complete or log a planned session and its share of the program shows here.
        </p>
        <Link
          to="/analytics?tab=blocks"
          className="block text-[10px] text-muted-foreground hover:text-primary transition-colors"
        >
          Every block →
        </Link>
      </div>
    )
  }

  const overall = Math.round(sc.overallPct ?? 0)
  const level = statusLevel(sc.headline)
  const styles = STATUS_STYLES[level === 'neutral' ? 'yellow' : level]
  const weeks = (sc.weeks ?? []).map((w) => ({ weekIndex: w.weekIndex, weekNumber: w.weekNumber, pct: Math.round(w.pct ?? 0) }))
  const trend = weeks.length >= 2 ? weeks[weeks.length - 1].pct - weeks[weeks.length - 2].pct : null
  const cw = sc.currentWeek

  return (
    <div className={cn('h-full rounded-xl border bg-card p-4 space-y-3 ring-1', styles.ring)}>
      <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
        Development
      </h2>

      <div className="space-y-1.5">
        <div className="flex items-baseline gap-1 whitespace-nowrap">
          <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>{overall}</span>
          <span className="text-xs text-muted-foreground">% compliance</span>
        </div>
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-muted-foreground">
          <span className={cn('rounded-full border px-2 py-0.5 text-[10px] font-semibold whitespace-nowrap', styles.badge)}>
            {statusLabel(sc.headline)}
          </span>
          <span className="tabular-nums whitespace-nowrap">{sc.completedSessions ?? 0} / {sc.plannedSessions} done</span>
          {trend != null && (
            <span className="flex items-center gap-1 whitespace-nowrap">
              {trend >= 0
                ? <TrendingUp className="size-3 text-emerald-600 dark:text-emerald-400" />
                : <TrendingDown className="size-3 text-amber-600 dark:text-amber-400" />}
              vs last week
            </span>
          )}
        </div>
      </div>

      {cw && (
        <p className="text-[11px] text-muted-foreground tabular-nums">
          This week: <span className="font-semibold text-foreground">{cw.completed} of {cw.due}</span> due so far
          {' · '}{cw.total} in the week{cw.isDeload ? ' · deload' : ''}
        </p>
      )}

      {/* The last four weeks, as on the phone. */}
      {weeks.length > 0 && (
        <div className="space-y-1 border-t pt-2">
          {weeks.slice(-4).map((w) => (
            <div key={w.weekIndex} className="flex items-center gap-2">
              <span className="w-10 text-[10px] text-muted-foreground tabular-nums">Wk {w.weekNumber}</span>
              <div className="h-1.5 flex-1 rounded-full bg-muted overflow-hidden">
                <div
                  className={cn('h-full rounded-full', statusFor(w.pct) === 'green' ? 'bg-emerald-500' : statusFor(w.pct) === 'yellow' ? 'bg-amber-500' : 'bg-red-500')}
                  style={{ width: `${Math.min(100, w.pct)}%` }}
                />
              </div>
              <span className="w-8 text-right text-[10px] tabular-nums text-muted-foreground">{w.pct}%</span>
            </div>
          ))}
        </div>
      )}

      {/* This card is the current program; the span of every program is a tab. */}
      <div className="flex items-center justify-between text-[10px]">
        <Link to="/analytics" className="text-muted-foreground hover:text-primary transition-colors">
          Scorecard →
        </Link>
        <Link to="/analytics?tab=blocks" className="text-muted-foreground hover:text-primary transition-colors">
          Every block →
        </Link>
      </div>
    </div>
  )
}
