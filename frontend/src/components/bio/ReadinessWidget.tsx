import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle } from 'lucide-react'
import { ResponsiveContainer, LineChart, Line, Tooltip } from 'recharts'
import { subDays, parseISO, isAfter, format } from 'date-fns'
import { cn } from '@/lib/utils'
import { computeReadiness, type ReadinessFlag } from '@/lib/readiness'
import { useBioStore } from '@/store/bioStore'

const FLAG_LABELS: Record<ReadinessFlag, string> = {
  elevated_rhr_3d: 'Elevated resting HR (3+ days)',
  suppressed_hrv_3d: 'Suppressed HRV (3+ days)',
  high_accumulated_fatigue: 'High accumulated fatigue',
  insufficient_data: 'Limited data — add daily check-ins',
}

const STATUS_STYLES = {
  green: {
    ring: 'ring-emerald-500/30',
    score: 'text-emerald-500',
    badge: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
    label: 'Ready',
  },
  yellow: {
    ring: 'ring-amber-500/30',
    score: 'text-amber-500',
    badge: 'bg-amber-500/10 text-amber-500 border-amber-500/30',
    label: 'Moderate',
  },
  red: {
    ring: 'ring-red-500/30',
    score: 'text-red-500',
    badge: 'bg-red-500/10 text-red-500 border-red-500/30',
    label: 'Low',
  },
}

export function ReadinessWidget() {
  const dailyBioLogs = useBioStore((s) => s.dailyBioLogs)
  const sessionPerformanceLogs = useBioStore((s) => s.sessionPerformanceLogs)

  const result = useMemo(
    () => computeReadiness(Object.values(dailyBioLogs), sessionPerformanceLogs),
    [dailyBioLogs, sessionPerformanceLogs]
  )

  // Sparkline data — last 7 days
  const sparkData = useMemo(() => {
    const cutoff = subDays(new Date(), 7)
    return Object.values(dailyBioLogs)
      .filter((l) => isAfter(parseISO(l.date), cutoff))
      .sort((a, b) => a.date.localeCompare(b.date))
      .map((l) => ({ date: format(parseISO(l.date), 'M/d'), rhr: l.restingHR }))
  }, [dailyBioLogs])

  const styles = STATUS_STYLES[result.status]
  const actionableFlags = result.flags.filter((f) => f !== 'insufficient_data')

  return (
    <div className={cn('h-full rounded-xl border bg-card p-4 space-y-3 ring-1', styles.ring)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Readiness
        </h2>
        <Link to="/bio" className="text-[10px] text-primary hover:text-primary/80 transition-colors">
          Log →
        </Link>
      </div>

      {/* Score + status */}
      <div className="flex items-end gap-3">
        <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>
          {result.score}
        </span>
        <div className="mb-0.5 space-y-0.5">
          <span
            className={cn(
              'inline-block rounded-full border px-2 py-0.5 text-[10px] font-semibold',
              styles.badge
            )}
          >
            {styles.label}
          </span>
          <p className="text-[10px] text-muted-foreground">out of 100</p>
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
                        {payload[0].value} bpm
                      </div>
                    ) : null
                  }
                />
                <Line
                  type="monotone"
                  dataKey="rhr"
                  stroke={result.status === 'green' ? '#10b981' : result.status === 'yellow' ? '#f59e0b' : '#ef4444'}
                  strokeWidth={1.5}
                  dot={false}
                  connectNulls
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        )}
      </div>

      {/* Flags */}
      {actionableFlags.length > 0 && (
        <div className="space-y-1">
          {actionableFlags.map((f) => (
            <div key={f} className="flex items-start gap-1.5 text-[11px] text-orange-400">
              <AlertTriangle className="size-3 mt-0.5 shrink-0" />
              {FLAG_LABELS[f]}
            </div>
          ))}
        </div>
      )}

      {result.flags.includes('insufficient_data') && actionableFlags.length === 0 && (
        <p className="text-[10px] text-muted-foreground/70 italic">
          Add daily resting HR + HRV check-ins to get accurate readiness scores.
        </p>
      )}
    </div>
  )
}
