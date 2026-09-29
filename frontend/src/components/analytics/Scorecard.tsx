import type { AnalyticsScorecard, AnalyticsScorecardRow } from '@/api/types'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { cn } from '@/lib/utils'
import { StatusBadge } from './StatusBadge'

const TIER_LABEL: Record<string, string> = {
  committed: 'committed', core: 'core', supplementary: 'supplementary', unscheduled: '—',
}
const DOSE_LABEL: Record<string, string> = { under: 'under dose', on: 'in range', over: 'over dose', unknown: '' }

function Row({ row }: { row: AnalyticsScorecardRow }) {
  const colour = MODALITY_COLORS[row.modality]?.hex ?? 'var(--color-border)'
  const pct = row.completionPct ?? 0
  return (
    <div className="space-y-1.5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <ModalityBadge modality={row.modality} size="sm" />
          <span className="text-[10px] uppercase tracking-wider text-muted-foreground">{TIER_LABEL[row.tier]}</span>
        </div>
        <span className="text-xs text-muted-foreground">
          <span className="font-semibold text-foreground">{row.completedSessions}</span> / {row.plannedSessions} sessions
          {row.completionPct != null && <> · {row.completionPct}%</>}
        </span>
      </div>
      {/* Completion, as a share of what was planned to date. Colour is the modality's; the length is the number. */}
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted" role="img"
           aria-label={`${row.modality} ${row.completedSessions} of ${row.plannedSessions} planned sessions completed`}>
        <div className="h-full rounded-full" style={{ width: `${Math.min(100, pct)}%`, backgroundColor: colour }} />
      </div>
      <div className="flex flex-wrap gap-x-3 text-[10px] text-muted-foreground">
        <span>{row.weeklyActualMinutes} min/wk actual · {row.weeklyPlannedMinutes} planned</span>
        {row.minWeeklyMinutes != null && (
          <span className={cn(row.doseStatus === 'under' && 'text-amber-800 dark:text-amber-300',
                              row.doseStatus === 'over' && 'text-red-700 dark:text-red-300')}>
            {DOSE_LABEL[row.doseStatus]} ({row.minWeeklyMinutes}–{row.maxWeeklyMinutes} min/wk)
            {row.planDoseStatus === 'under' && ' — the plan itself is under the minimum'}
          </span>
        )}
      </div>
    </div>
  )
}

/** Did you train what this program is for. */
export function Scorecard({ scorecard }: { scorecard: AnalyticsScorecard }) {
  const committed = scorecard.tiers.committed
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Scorecard</p>
          <p className="text-xs text-muted-foreground">
            {scorecard.elapsedWeeks} week{scorecard.elapsedWeeks === 1 ? '' : 's'} elapsed
            {committed && <> · committed work {committed.completed}/{committed.planned}</>}
            {scorecard.overallPct != null && <> · {scorecard.overallPct}% overall</>}
          </p>
        </div>
        <StatusBadge status={scorecard.headline} />
      </div>
      {scorecard.headline === 'off_plan' && (
        <p className="text-xs text-amber-800 dark:text-amber-300">
          Under 70% of the committed work has been done. Everything else is secondary to that.
        </p>
      )}
      <div className="space-y-3">
        {scorecard.modalities.map((row) => <Row key={row.modality} row={row} />)}
      </div>
    </div>
  )
}
