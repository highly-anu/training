import { cn } from '@/lib/utils'
import type {
  ExerciseFinding,
  ExerciseHistoryItem,
  ExerciseHistoryPoint,
  ProgressionMetricType,
  ProgressionStatus,
} from '@/api/types'

// ── Helpers ──────────────────────────────────────────────────────────────────

function primaryValue(pt: ExerciseHistoryPoint, metricType: ProgressionMetricType): number | null {
  switch (metricType) {
    case 'weight':   return pt.best_weight_kg
    case 'time':     return pt.duration_sec != null ? +(pt.duration_sec / 60).toFixed(1) : null
    case 'distance': return pt.distance_km
    case 'rounds':   return pt.rounds_completed
    case 'reps':     return pt.best_reps
    case 'volume':   return pt.total_volume
    default:         return pt.best_weight_kg
  }
}

const STATUS_BADGE: Record<ProgressionStatus, { label: string; className: string }> = {
  ahead:            { label: 'Ahead',       className: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30' },
  on_track:         { label: 'On track',    className: 'bg-emerald-500/10 text-emerald-700 dark:text-emerald-300 border-emerald-500/30' },
  behind:           { label: 'Behind',      className: 'bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30' },
  stalled:          { label: 'Stalled',     className: 'bg-red-500/10 text-red-700 dark:text-red-300 border-red-500/30' },
  insufficient_data:{ label: 'Not tracked', className: 'bg-muted/50 text-muted-foreground border-border' },
}

const STATUS_SPARKLINE_COLOR: Record<ProgressionStatus, string> = {
  ahead:            '#10b981',
  on_track:         '#10b981',
  behind:           '#f59e0b',
  stalled:          '#f87171',
  insufficient_data:'#6b7280',
}

const METRIC_LABELS: Record<ProgressionMetricType, string> = {
  weight:   'kg',
  volume:   'kg·reps',
  time:     'min',
  distance: 'km',
  rounds:   'rounds',
  reps:     'reps',
  complexity:'level',
}

// ── Sparkline ─────────────────────────────────────────────────────────────────

function Sparkline({
  values,
  color,
}: {
  values: number[]
  color: string
}) {
  if (values.length < 2) return null

  const W = 64
  const H = 24
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1

  const points = values
    .map((v, i) => {
      const x = (i / (values.length - 1)) * W
      const y = H - ((v - min) / range) * (H - 4) - 2
      return `${x},${y}`
    })
    .join(' ')

  return (
    <svg width={W} height={H} className="shrink-0">
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

// ── Card ─────────────────────────────────────────────────────────────────────

interface ExerciseProgressCardProps {
  item: ExerciseHistoryItem
  finding?: ExerciseFinding
}

export function ExerciseProgressCard({ item, finding }: ExerciseProgressCardProps) {
  const metricType: ProgressionMetricType =
    finding?.metric_type ?? item.expected[0]?.metric_type ?? 'weight'
  const unit = finding?.unit ?? item.expected[0]?.unit ?? METRIC_LABELS[metricType]

  const status: ProgressionStatus = finding?.status ?? 'insufficient_data'
  const badge = STATUS_BADGE[status]
  const sparkColor = STATUS_SPARKLINE_COLOR[status]

  // Sparkline values: primary metric extracted from each history point
  const sparkValues = item.history
    .map((pt) => primaryValue(pt, metricType))
    .filter((v): v is number => v !== null)

  const latestActual = finding?.actual_value ?? sparkValues[sparkValues.length - 1] ?? null
  const target = finding?.expected_value ?? item.expected.find((e) => e.expected_value != null)?.expected_value ?? null

  const hasData = latestActual !== null
  const fromImport = item.history.length > 0 && item.history.every((p) => p.source === 'matched_workout')

  const latestPoint = item.history[item.history.length - 1] ?? null
  const hrAvg = latestPoint?.hr_avg ?? null
  const hrMax = latestPoint?.hr_max ?? null

  // Hint for exercises not yet logged
  const logHint = `Log ${METRIC_LABELS[metricType]} to track`

  return (
    <div
      className={cn(
        'rounded-xl border bg-card p-4 space-y-2',
        status === 'insufficient_data'
          ? 'border-border/50 opacity-70'
          : 'border-border',
      )}
    >
      {/* Header: name + badge */}
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-1.5 min-w-0">
          <p className="text-sm font-medium text-foreground leading-tight truncate">{item.name}</p>
          {fromImport && (
            <span title="From imported workout" className="shrink-0 text-[9px] text-muted-foreground/60 border border-border/40 rounded px-1 py-px leading-none">
              GPS
            </span>
          )}
        </div>
        <span
          className={cn(
            'shrink-0 rounded-full border px-2 py-0.5 text-[10px] font-semibold',
            badge.className,
          )}
        >
          {badge.label}
        </span>
      </div>

      {/* Metric + sparkline */}
      <div className="flex items-end justify-between gap-3">
        <div className="space-y-0.5">
          {hasData ? (
            <>
              <p className="text-2xl font-bold tabular-nums text-foreground leading-none">
                {latestActual}
                <span className="text-sm font-normal text-muted-foreground ml-1">{unit}</span>
              </p>
              {target != null && (
                <p className="text-[11px] text-muted-foreground">
                  Target: {target} {unit}
                </p>
              )}
            </>
          ) : (
            <p className="text-[11px] text-muted-foreground italic">{logHint}</p>
          )}
        </div>

        {sparkValues.length >= 2 && (
          <Sparkline values={sparkValues} color={sparkColor} />
        )}
      </div>

      {/* HR from matched workouts */}
      {(hrAvg != null || hrMax != null) && (
        <p className="text-[11px] text-muted-foreground">
          ♥ {hrAvg != null ? `${hrAvg} avg` : ''}
          {hrAvg != null && hrMax != null ? ' · ' : ''}
          {hrMax != null ? `${hrMax} max` : ''} bpm
        </p>
      )}

      {/* Change summary */}
      {finding?.change_summary && status !== 'insufficient_data' && (
        <p className="text-[11px] text-muted-foreground">{finding.change_summary}</p>
      )}
    </div>
  )
}
