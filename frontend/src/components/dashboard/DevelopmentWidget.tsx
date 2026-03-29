import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { TrendingUp, TrendingDown, Minus, AlertTriangle } from 'lucide-react'
import { ResponsiveContainer, LineChart, Line, Tooltip } from 'recharts'
import { cn } from '@/lib/utils'
import { computeSessionInsight, computeWeekInsights, computeDevelopmentTrends } from '@/lib/sessionAnalysis'
import { maxHRFromDOB } from '@/lib/hrZones'
import { useBioStore } from '@/store/bioStore'
import { useProfileStore } from '@/store/profileStore'
import { useCurrentProgram } from '@/api/programs'
import type { SessionInsight, WeekInsightSummary } from '@/api/types'

const STATUS_STYLES = {
  green: {
    ring: 'ring-emerald-500/30',
    score: 'text-emerald-500',
    badge: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
    label: 'On Track',
  },
  yellow: {
    ring: 'ring-amber-500/30',
    score: 'text-amber-500',
    badge: 'bg-amber-500/10 text-amber-500 border-amber-500/30',
    label: 'Mixed',
  },
  red: {
    ring: 'ring-red-500/30',
    score: 'text-red-500',
    badge: 'bg-red-500/10 text-red-500 border-red-500/30',
    label: 'Off Track',
  },
} as const

const DIRECTION_ICON = {
  improving: TrendingUp,
  stable: Minus,
  declining: TrendingDown,
}

const DIRECTION_COLOR = {
  improving: 'text-emerald-500',
  stable: 'text-muted-foreground',
  declining: 'text-amber-500',
}

export function DevelopmentWidget() {
  const program = useCurrentProgram()
  const workoutMatches = useBioStore((s) => s.workoutMatches)
  const importedWorkouts = useBioStore((s) => s.importedWorkouts)
  const perfLogs = useBioStore((s) => s.sessionPerformanceLogs)
  const getMatchedWorkout = useBioStore((s) => s.getMatchedWorkout)
  const dob = useProfileStore((s) => s.dateOfBirth)

  const maxHR = maxHRFromDOB(dob) ?? 190

  const { weekSummaries, trends, overallCompliance, overallStatus } = useMemo(() => {
    if (!program || workoutMatches.length === 0) {
      return { weekSummaries: [], trends: [], overallCompliance: 0, overallStatus: 'red' as const }
    }

    const allInsights: SessionInsight[] = []
    const weekSummaries: WeekInsightSummary[] = []
    const weekDataMap = new Map(program.weeks.map((w) => [w.week_number, w]))

    for (const week of program.weeks) {
      const weekInsights: SessionInsight[] = []
      for (const [day, sessions] of Object.entries(week.schedule)) {
        const sessionKey = `${week.week_number}-${day}`
        const matched = getMatchedWorkout(sessionKey)
        if (!matched) continue
        const perfLog = perfLogs[sessionKey]
        const insight = computeSessionInsight(sessions, matched, perfLog, maxHR, sessionKey)
        weekInsights.push(insight)
        allInsights.push(insight)
      }
      if (weekInsights.length > 0) {
        weekSummaries.push(computeWeekInsights(week, weekInsights))
      }
    }

    const trends = computeDevelopmentTrends(weekSummaries, allInsights, importedWorkouts, weekDataMap)

    const overallCompliance =
      weekSummaries.length > 0
        ? Math.round(weekSummaries.reduce((s, w) => s + w.avgCompliance, 0) / weekSummaries.length)
        : 0
    const overallStatus = overallCompliance >= 70 ? 'green' as const : overallCompliance >= 45 ? 'yellow' as const : 'red' as const

    return { weekSummaries, trends, overallCompliance, overallStatus }
  }, [program, workoutMatches, importedWorkouts, perfLogs, getMatchedWorkout, maxHR])

  const styles = STATUS_STYLES[overallStatus]

  // Sparkline data
  const sparkData = weekSummaries.map((w) => ({
    week: `W${w.weekNumber}`,
    compliance: w.avgCompliance,
  }))

  const matchedCount = workoutMatches.filter((m) => m.matchConfidence !== 'rejected').length

  if (matchedCount === 0) {
    return (
      <div className="h-full rounded-xl border bg-card p-4 space-y-3 ring-1 ring-border">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Development
        </h2>
        <p className="text-[11px] text-muted-foreground/70 italic">
          Import workouts and match them to sessions to track your development.
        </p>
        <Link
          to="/import"
          className="text-[10px] text-primary hover:text-primary/80 transition-colors"
        >
          Import workouts &rarr;
        </Link>
      </div>
    )
  }

  // Top warning flags across all weeks
  const topFlags = weekSummaries
    .flatMap((w) => w.topFlags)
    .filter((f) => f.severity === 'warning')
    .slice(0, 2)

  return (
    <div className={cn('h-full rounded-xl border bg-card p-4 space-y-3 ring-1', styles.ring)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Development
        </h2>
        <span className="text-[10px] text-muted-foreground">
          {matchedCount} session{matchedCount !== 1 ? 's' : ''} tracked
        </span>
      </div>

      {/* Score + status */}
      <div className="flex items-end gap-3">
        <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>
          {overallCompliance}
        </span>
        <div className="mb-0.5 space-y-0.5">
          <span
            className={cn(
              'inline-block rounded-full border px-2 py-0.5 text-[10px] font-semibold',
              styles.badge,
            )}
          >
            {styles.label}
          </span>
          <p className="text-[10px] text-muted-foreground">compliance</p>
        </div>

        {/* Sparkline */}
        {sparkData.length > 1 && (
          <div className="flex-1 ml-2">
            <ResponsiveContainer width="100%" height={40}>
              <LineChart data={sparkData}>
                <Tooltip
                  content={({ active, payload }) =>
                    active && payload?.length ? (
                      <div className="rounded border border-border bg-card px-2 py-1 text-[10px]">
                        {payload[0].payload.week}: {payload[0].value}%
                      </div>
                    ) : null
                  }
                />
                <Line
                  type="monotone"
                  dataKey="compliance"
                  stroke={overallStatus === 'green' ? '#10b981' : overallStatus === 'yellow' ? '#f59e0b' : '#ef4444'}
                  strokeWidth={1.5}
                  dot={false}
                  connectNulls
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Trends */}
      {trends.length > 0 && (
        <div className="space-y-1.5">
          {trends.map((t) => {
            const DirIcon = DIRECTION_ICON[t.direction]
            const dirColor = DIRECTION_COLOR[t.direction]
            return (
              <div key={t.metric} className="flex items-start gap-1.5">
                <DirIcon className={`size-3 mt-0.5 shrink-0 ${dirColor}`} />
                <div className="min-w-0">
                  <p className={`text-[11px] font-medium ${dirColor}`}>{t.label}</p>
                  <p className="text-[10px] text-muted-foreground truncate">{t.detail}</p>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Warning flags */}
      {topFlags.length > 0 && (
        <div className="space-y-1">
          {topFlags.map((f, i) => (
            <div key={`${f.key}-${i}`} className="flex items-start gap-1.5 text-[11px] text-orange-400">
              <AlertTriangle className="size-3 mt-0.5 shrink-0" />
              {f.label}: {f.detail}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
