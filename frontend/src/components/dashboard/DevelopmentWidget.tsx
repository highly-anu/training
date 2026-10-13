import { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { TrendingUp, TrendingDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useProgramAnalytics } from '@/api/analytics'
import { queryKeys } from '@/api/queryKeys'
import { useBioStore } from '@/store/bioStore'
import { STATUS_STYLES } from '@/lib/statusColors'

const STATUS_LABEL = { green: 'On Track', yellow: 'Mixed', red: 'Off Track' } as const

/** The phone's thresholds (TodayView): 70 % and 45 %. */
function statusFor(pct: number): 'green' | 'yellow' | 'red' {
  return pct >= 70 ? 'green' : pct >= 45 ? 'yellow' : 'red'
}

/**
 * Today's development card: how much of the program so far was done — the
 * program scorecard's completion (`/analytics/program`), the same card and
 * numbers as the phone's Today. A session counts when it was logged complete
 * or has a matched workout; only sessions whose day has come are scheduled.
 *
 * Until 2026-10-13 this card scored how closely matched workouts followed
 * their prescription (lib/sessionAnalysis), under the same name as the
 * phone's completion card — two different numbers called "Development".
 * The prescription comparison lives on each session and workout.
 */
export function DevelopmentWidget() {
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
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Development</h2>
      </div>
    )
  }

  if (!sc || !sc.plannedSessions) {
    return (
      <div className="h-full rounded-xl border bg-card p-4 space-y-3 ring-1 ring-border">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Development
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
  const status = statusFor(overall)
  const styles = STATUS_STYLES[status]
  const weeks = (sc.weeks ?? []).map((w) => ({ weekIndex: w.weekIndex, weekNumber: w.weekNumber, pct: Math.round(w.pct ?? 0) }))
  const trend = weeks.length >= 2 ? weeks[weeks.length - 1].pct - weeks[weeks.length - 2].pct : null

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
            {STATUS_LABEL[status]}
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
