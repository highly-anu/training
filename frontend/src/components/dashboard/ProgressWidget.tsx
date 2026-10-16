import { Link } from 'react-router-dom'
import { ChevronRight, TrendingDown, TrendingUp, Minus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useProgramAnalytics } from '@/api/analytics'
import { STATUS_STYLES } from '@/lib/statusColors'
import { COVERAGE_REASONS, statusLevel } from '@/components/analytics/status'
import { StatusBadge } from '@/components/analytics/StatusBadge'

/**
 * Today's progress card: is the training working, in the methodology's own
 * currency — load on the bar for Starting Strength, aerobic minutes for
 * Uphill, movements earned in Wildman's general practice. The headline of the
 * program's first methodology, worded by the server (`headlineSummary`), so
 * the phone's card says the same sentence. The whole card opens Analytics ▸
 * Progress.
 *
 * It used to show the progression review's score, which was the session
 * completion beside it until a measure had a trend. Adherence is the other
 * card; the score stays on the Progress tab.
 */
export function ProgressWidget() {
  const { data, isLoading } = useProgramAnalytics()
  const method = data?.methodologies?.[0]
  const h = method?.headlineSummary ?? null
  const name = data?.frame?.philosophies.find((p) => p.id === method?.philosophy)?.name
  const level = h ? statusLevel(h.status) : 'neutral'
  const ring = level === 'neutral' ? 'ring-border' : STATUS_STYLES[level].ring
  const TrendIcon = h?.trendDirection === 'improving' ? TrendingUp
    : h?.trendDirection === 'declining' ? TrendingDown : Minus

  return (
    <Link
      to="/analytics?tab=progress"
      aria-label="Open progress analytics"
      className={cn('h-full rounded-xl border bg-card p-4 space-y-3 ring-1 block transition-colors hover:border-primary/40', ring)}
    >
      <div className="flex items-center justify-between">
        <h2 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Progress</h2>
        <ChevronRight className="size-3.5 text-muted-foreground/60" aria-hidden="true" />
      </div>

      {isLoading && <p className="text-[11px] text-muted-foreground/70 italic">Measuring…</p>}

      {!isLoading && !h && (
        <p className="text-[11px] text-muted-foreground/70 italic">
          Complete a few sessions and this program's own measure appears here.
        </p>
      )}

      {h && (
        <div className="space-y-1.5">
          <div className="flex items-center justify-between gap-2">
            <p className="text-sm font-semibold text-foreground">{h.label}</p>
            {h.text && <StatusBadge status={h.status} />}
          </div>
          {name && <p className="text-[10px] text-muted-foreground">{name}</p>}
          {h.text ? (
            <>
              <p className="text-lg font-bold tabular-nums leading-tight">{h.text}</p>
              {h.trendText && (
                <p className="flex items-center gap-1 text-[11px] text-muted-foreground">
                  <TrendIcon className="size-3" aria-hidden="true" /> {h.trendText}
                </p>
              )}
            </>
          ) : (
            <p className="text-[11px] text-muted-foreground leading-snug">
              {h.inScope === 0
                ? 'None of the sessions it measures has been done yet.'
                : (h.reason && COVERAGE_REASONS[h.reason]) || 'Nothing logged for this measure yet.'}
            </p>
          )}
        </div>
      )}
    </Link>
  )
}
