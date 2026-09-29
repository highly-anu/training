import type {
  ExerciseFinding,
  ProgressionAdjustment,
  ProgressionStatus,
} from '@/api/types'

// ── Trend helpers ─────────────────────────────────────────────────────────────

// getExerciseTrend (a least-squares slope with no callers) moved to the server:
// src/analytics/trend.py fits the slope over non-deload points and the analytics
// document carries it as `trend.slopePct`.

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
