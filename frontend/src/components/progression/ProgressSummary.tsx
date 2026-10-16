import { useState } from 'react'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'
import { STATUS_STYLES } from '@/lib/statusColors'
import { bandRange, scoreBand } from '@/lib/progressionScore'
import type { ProgressionReview } from '@/api/types'

const BAND_DOT = { on_track: 'bg-emerald-500', mixed: 'bg-amber-500', off_track: 'bg-red-500' } as const

/**
 * The top of Analytics ▸ Progress: what the section is for, the score with
 * its band and why, the sum behind it, what the compliance covers, each
 * measure and how far it is from a trend, and the methodology's measures
 * still waiting for data. Every word comes from the review
 * (src/analytics/review.py), so the phone says the same.
 */
export function ProgressSummary({ review }: { review: ProgressionReview }) {
  const [open, setOpen] = useState(false)
  const band = scoreBand(review)
  const styles = STATUS_STYLES[band?.level ?? 'red']
  const breakdown = review.score_breakdown
  const status = review.score_status
  const findings = review.exercise_findings
  const pending = review.pending_measures ?? []

  return (
    <div className="space-y-3">
      {review.purpose && <p className="text-xs text-muted-foreground">{review.purpose}</p>}

      <div className={cn('rounded-xl border bg-card p-4 space-y-3 ring-1', band ? styles.ring : 'ring-border')}>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between sm:gap-3">
          <div className="space-y-1">
            {review.overall_score != null ? (
              <div className="flex items-end gap-2 whitespace-nowrap">
                <span className={cn('text-4xl font-bold tabular-nums', styles.score)}>{review.overall_score}</span>
                <span className="mb-1 text-sm text-muted-foreground">/ 100</span>
                {band && (
                  <span className={cn('mb-1.5 rounded-full border px-2 py-0.5 text-[10px] font-semibold', styles.badge)}>
                    {band.label}
                  </span>
                )}
              </div>
            ) : (
              <p className="text-sm font-medium text-muted-foreground">Not enough data yet</p>
            )}
            {status && <p className="text-sm">{status.reason}</p>}
          </div>
          <div className="shrink-0 sm:text-right">
            <p className="text-sm font-semibold tabular-nums">{review.compliance_pct}%</p>
            <p className="text-[11px] text-muted-foreground">Sessions done</p>
            {review.scope_label && <p className="text-[11px] text-muted-foreground">{review.scope_label}</p>}
          </div>
        </div>

        {(breakdown || status) && (
          <div className="space-y-2">
            <button
              type="button"
              onClick={() => setOpen((v) => !v)}
              aria-expanded={open}
              className="flex items-center gap-1 text-xs font-medium text-primary hover:underline underline-offset-2"
            >
              How is this scored?
              <ChevronDown className={cn('size-3.5 transition-transform', open && 'rotate-180')} aria-hidden="true" />
            </button>
            {open && (
              <div className="space-y-2 text-xs">
                {breakdown && <p className="text-muted-foreground">{breakdown.summary}</p>}
                {breakdown && breakdown.parts.length > 1 && (
                  <ul className="space-y-0.5">
                    {breakdown.parts.map((p) => (
                      <li key={p.id} className="flex justify-between gap-2">
                        <span>{p.label}</span>
                        <span className="tabular-nums">{p.value} × {p.weight} = {p.points}</span>
                      </li>
                    ))}
                  </ul>
                )}
                {status && (
                  <ul className="space-y-0.5 border-t border-border/40 pt-2">
                    {status.bands.map((b, i) => (
                      <li key={b.id} className="flex items-center justify-between gap-2">
                        <span className={cn('flex items-center gap-1.5', b.id === status.id && 'font-semibold')}>
                          <span className={cn('size-2 rounded-full', BAND_DOT[b.id])} aria-hidden="true" />
                          {b.label}
                        </span>
                        <span className="text-muted-foreground">{bandRange(status.bands, i)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {findings.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Measures</h3>
          {findings.map((f) => (
            <div key={f.exercise_id} className="rounded-xl border border-border/60 bg-card px-4 py-3 space-y-0.5">
              <div className="flex items-baseline justify-between gap-2">
                <p className="text-sm font-medium">{f.name}</p>
                <p className="text-[11px] text-muted-foreground tabular-nums">{f.change_summary}</p>
              </div>
              {f.description && <p className="text-[11px] text-muted-foreground">{f.description}</p>}
              {f.waiting_for && <p className="text-[11px]">{f.waiting_for}</p>}
            </div>
          ))}
        </div>
      )}

      {pending.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wider">Waiting for data</h3>
          {pending.map((m) => (
            <div key={m.id} className="rounded-xl border border-border/60 bg-card px-4 py-3 space-y-0.5">
              <p className="text-sm font-medium">{m.label}</p>
              {m.description && <p className="text-[11px] text-muted-foreground">{m.description}</p>}
              <p className="text-[11px]">{m.reason}</p>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
