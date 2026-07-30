import { AlertTriangle } from 'lucide-react'
import { cn } from '@/lib/utils'
import { scoreToStatus, statusIcon, getAdjustmentPriority } from '@/lib/progressionAnalysis'
import type { ProgressionReview } from '@/api/types'
import { STATUS_STYLES } from '@/lib/statusColors'


const STATUS_ICON_COLOR: Record<string, string> = {
  ahead:            'text-emerald-700 dark:text-emerald-300',
  on_track:         'text-emerald-700 dark:text-emerald-300',
  behind:           'text-amber-700 dark:text-amber-300',
  stalled:          'text-red-700 dark:text-red-300',
  insufficient_data:'text-muted-foreground',
}

const STATUS_LABEL = { green: 'On Track', yellow: 'Mixed', red: 'Off Track' } as const

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
        <div className="space-y-2">
          {review.compliance_pct > 0 ? (
            <p className="text-sm font-medium text-muted-foreground">
              {review.compliance_pct}% sessions completed
            </p>
          ) : (
            <p className="text-sm font-medium text-muted-foreground">No sessions logged yet</p>
          )}
          <p className="text-[11px] text-muted-foreground/70 leading-relaxed">
            {review.flags.includes('no_program')
              ? 'Generate a training program first.'
              : 'Open a session, expand each exercise, and log your sets (reps + weight). Matched workouts mark sessions complete but don\'t provide set data for progression tracking.'}
          </p>
        </div>
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
                {STATUS_LABEL[status]}
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
                <div key={i} className="flex items-start gap-1.5 text-[11px] text-orange-700 dark:text-orange-300">
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
