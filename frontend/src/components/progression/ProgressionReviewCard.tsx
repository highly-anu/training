import { AlertTriangle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { scoreToStatus, statusIcon, getAdjustmentPriority } from '@/lib/progressionAnalysis'
import type { ProgressionReview } from '@/api/types'

const STATUS_STYLES = {
  green: {
    ring:  'ring-emerald-500/30',
    score: 'text-emerald-500',
    badge: 'bg-emerald-500/10 text-emerald-500 border-emerald-500/30',
    label: 'On Track',
  },
  yellow: {
    ring:  'ring-amber-500/30',
    score: 'text-amber-500',
    badge: 'bg-amber-500/10 text-amber-500 border-amber-500/30',
    label: 'Mixed',
  },
  red: {
    ring:  'ring-red-500/30',
    score: 'text-red-500',
    badge: 'bg-red-500/10 text-red-500 border-red-500/30',
    label: 'Off Track',
  },
} as const

const STATUS_ICON_COLOR: Record<string, string> = {
  ahead:            'text-emerald-500',
  on_track:         'text-emerald-500',
  behind:           'text-amber-500',
  stalled:          'text-red-400',
  insufficient_data:'text-muted-foreground',
}

export function ProgressionReviewCard({ review }: { review: ProgressionReview }) {
  const status = scoreToStatus(review.overall_score)
  const styles = STATUS_STYLES[status]
  const prioritised = getAdjustmentPriority(review.adjustments)

  const isInsufficient =
    review.overall_score === null || review.flags.includes('insufficient_data')

  return (
    <div className={cn('rounded-xl border bg-card p-4 space-y-3 ring-1', styles.ring)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Progression
        </h2>
        <span className="text-[10px] text-muted-foreground">
          {review.period_type === 'biweekly' ? 'Bi-weekly' : 'Weekly'} · {review.period_key}
        </span>
      </div>

      {isInsufficient ? (
        <p className="text-[11px] text-muted-foreground/70 italic">
          {review.recommendations[0] ?? 'Log more sessions to see progression analysis.'}
        </p>
      ) : (
        <>
          {/* Score row */}
          <div className="flex items-end gap-3">
            <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>
              {review.overall_score}
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
              <p className="text-[10px] text-muted-foreground">
                {review.compliance_pct}% sessions completed
              </p>
            </div>
          </div>

          {/* Exercise findings */}
          {review.exercise_findings.length > 0 && (
            <div className="space-y-1">
              {review.exercise_findings.slice(0, 6).map((f) => (
                <div key={f.exercise_id} className="flex items-start gap-2 text-[11px]">
                  <span
                    className={cn(
                      'shrink-0 font-semibold w-3',
                      STATUS_ICON_COLOR[f.status] ?? 'text-muted-foreground',
                    )}
                  >
                    {statusIcon(f.status)}
                  </span>
                  <span className="text-foreground font-medium min-w-0 truncate">
                    {f.name}
                  </span>
                  <span className="text-muted-foreground ml-auto shrink-0">
                    {f.change_summary}
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* Recommendations */}
          {review.recommendations.length > 0 && (
            <div className="space-y-1 pt-1 border-t border-border/50">
              {review.recommendations.slice(0, 3).map((rec, i) => (
                <p key={i} className="text-[11px] text-muted-foreground">
                  · {rec}
                </p>
              ))}
            </div>
          )}

          {/* Adjustments */}
          {prioritised.length > 0 && (
            <div className="space-y-1">
              {prioritised.slice(0, 2).map((adj, i) => (
                <div key={i} className="flex items-start gap-1.5 text-[11px] text-orange-400">
                  <AlertTriangle className="size-3 mt-0.5 shrink-0" />
                  <span>{adj.reason}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}
