import type {
  ExerciseFinding,
  ExerciseHistoryPoint,
  ProgressionAdjustment,
  ProgressionStatus,
  TrendDirection,
} from '@/api/types'

// ── Trend helpers ─────────────────────────────────────────────────────────────

export function getExerciseTrend(history: ExerciseHistoryPoint[]): {
  slope: number
  direction: TrendDirection
} {
  const vals = history
    .map((p) => p.best_weight_kg ?? p.duration_sec ?? p.distance_km ?? p.rounds_completed)
    .filter((v): v is number => v !== null && v !== undefined)

  if (vals.length < 2) return { slope: 0, direction: 'stable' }

  // Simple linear regression slope
  const n = vals.length
  const xs = vals.map((_, i) => i)
  const sumX  = xs.reduce((a, b) => a + b, 0)
  const sumY  = vals.reduce((a, b) => a + b, 0)
  const sumXY = xs.reduce((a, x, i) => a + x * vals[i], 0)
  const sumX2 = xs.reduce((a, x) => a + x * x, 0)
  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX || 1)

  const relativeDelta = Math.abs(slope) / (Math.abs(vals[0]) || 1)
  const direction: TrendDirection =
    relativeDelta < 0.02
      ? 'stable'
      : slope > 0
      ? 'improving'
      : 'declining'

  return { slope, direction }
}

// ── Display helpers ───────────────────────────────────────────────────────────

const STATUS_LABELS: Record<ProgressionStatus, string> = {
  ahead:            'Ahead',
  on_track:         'On track',
  behind:           'Behind',
  stalled:          'Stalled',
  insufficient_data:'Not enough data',
}

export function formatFinding(finding: ExerciseFinding): string {
  const status = STATUS_LABELS[finding.status] ?? finding.status
  if (finding.actual_value !== null && finding.expected_value !== null) {
    return `${finding.name}: ${finding.actual_value}${finding.unit} (expected ${finding.expected_value}${finding.unit}) — ${status}`
  }
  return `${finding.name}: ${status}. ${finding.change_summary}`
}

// ── Adjustment priority ───────────────────────────────────────────────────────

const ADJUSTMENT_PRIORITY: Record<string, number> = {
  hold_load:          0,
  early_deload:       1,
  reduce_volume_10pct:2,
  rebuild_habit:      3,
  increase_increment: 4,
  advance_complexity: 5,
  reduce_complexity:  5,
}

export function getAdjustmentPriority(
  adjustments: ProgressionAdjustment[],
): ProgressionAdjustment[] {
  return [...adjustments].sort(
    (a, b) =>
      (ADJUSTMENT_PRIORITY[a.type] ?? 99) - (ADJUSTMENT_PRIORITY[b.type] ?? 99),
  )
}

// ── Score → status ────────────────────────────────────────────────────────────

export function scoreToStatus(score: number | null): 'green' | 'yellow' | 'red' {
  if (score === null) return 'red'
  if (score >= 70) return 'green'
  if (score >= 45) return 'yellow'
  return 'red'
}

// ── Status icon text (used in list items) ────────────────────────────────────

export function statusIcon(status: ProgressionStatus): string {
  switch (status) {
    case 'ahead':            return '↑'
    case 'on_track':         return '✓'
    case 'behind':           return '↓'
    case 'stalled':          return '⚠'
    case 'insufficient_data':return '–'
  }
}
