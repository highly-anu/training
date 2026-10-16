import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import { fetchProgressionReview } from '@/api/progression'
import { STATUS_STYLES } from '@/lib/statusColors'
import { scoreBand } from '@/lib/progressionScore'

/**
 * The headline of the weekly progression review, as a card whose whole
 * surface opens Analytics ▸ Progress. Shares the review query with the tab.
 */
export function ProgressionWidget() {
  const { data: review, isLoading } = useQuery({
    queryKey: ['progression', 'review', 'weekly'],
    queryFn: () => fetchProgressionReview('weekly'),
    staleTime: 5 * 60 * 1000,
  })

  const score = review?.overall_score ?? null
  const band = scoreBand(review)
  const status = band?.level ?? null
  const styles = STATUS_STYLES[status ?? 'red']
  const recommendation = review?.recommendations?.[0] ?? null

  return (
    <Link
      to="/analytics?tab=progress"
      aria-label="Open progress analytics"
      className={cn(
        'h-full rounded-xl border bg-card p-4 space-y-3 ring-1 block transition-colors hover:border-primary/40',
        status ? styles.ring : 'ring-border'
      )}
    >
      <div className="flex items-center justify-between">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">
          Progression
        </h2>
        <ChevronRight className="size-3.5 text-muted-foreground/60" aria-hidden="true" />
      </div>

      {isLoading && <p className="text-[11px] text-muted-foreground/70 italic">Reviewing…</p>}

      {!isLoading && score == null && (
        <p className="text-[11px] text-muted-foreground/70 italic">
          Complete a few sessions and the weekly review appears here.
        </p>
      )}

      {score != null && status && (
        <>
          <div className="flex items-end gap-3">
            <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>{Math.round(score)}</span>
            <div className="mb-0.5 space-y-0.5">
              <span className={cn('inline-block rounded-full px-2 py-0.5 text-[10px] font-semibold', styles.badge)}>
                {band?.label}
              </span>
              <p className="text-[10px] text-muted-foreground">
                {review?.scope_label ?? `${Math.round(review?.compliance_pct ?? 0)}% compliance`}
              </p>
            </div>
          </div>
          {review?.score_status?.reason && (
            <p className="text-[11px] text-muted-foreground leading-snug">{review.score_status.reason}</p>
          )}
          {recommendation && (
            <p className="text-[11px] text-muted-foreground leading-snug line-clamp-2">{recommendation}</p>
          )}
        </>
      )}
    </Link>
  )
}
