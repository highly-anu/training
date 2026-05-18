import { useNavigate } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { MatchedSessionSummary } from '@/api/types'

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(n: number, decimals = 1) {
  return n % 1 === 0 ? String(n) : n.toFixed(decimals)
}

function DurationDelta({ pct }: { pct: number | null }) {
  if (pct === null) return null
  const abs = Math.abs(pct)
  const sign = pct > 0 ? '+' : '−'
  const color =
    abs <= 15 ? 'text-emerald-500 border-emerald-500/30 bg-emerald-500/10'
    : abs <= 30 ? 'text-amber-500 border-amber-500/30 bg-amber-500/10'
    : pct < 0   ? 'text-red-400 border-red-500/30 bg-red-500/10'
    :             'text-muted-foreground border-border bg-muted/40'
  return (
    <span className={cn('shrink-0 rounded border px-1.5 py-px text-[10px] font-semibold tabular-nums', color)}>
      {sign}{abs}%
    </span>
  )
}

function SourceBadge({ source, confidence }: { source: string; confidence: string }) {
  const label =
    source === 'strava'           ? 'Strava'
    : source === 'apple_health' || source === 'apple_watch_live' ? 'GPS'
    : source === 'fit_file'       ? 'FIT'
    : source === 'manual'         ? 'Manual'
    : 'GPS'
  return (
    <span className="shrink-0 text-[9px] text-muted-foreground/60 border border-border/40 rounded px-1 py-px leading-none">
      {confidence === 'manual' ? '⊙' : ''}{label}
    </span>
  )
}

// ── Card ─────────────────────────────────────────────────────────────────────

interface MatchedSessionCardProps {
  item: MatchedSessionSummary
}

export function MatchedSessionCard({ item }: MatchedSessionCardProps) {
  const navigate = useNavigate()
  const { archetype, workout, durationDeltaPct, relevantMetrics } = item
  const dayAbbr = item.dayName.slice(0, 3)

  // Build metric chips in relevantMetrics order (max 3)
  const chips: { label: string; value: string }[] = []
  for (const metric of relevantMetrics) {
    if (chips.length >= 3) break
    if (metric === 'duration' && workout.durationMinutes) {
      chips.push({ label: '', value: `${fmt(workout.durationMinutes, 0)} min` })
    } else if (metric === 'distance' && workout.distanceKm) {
      chips.push({ label: '', value: `${fmt(workout.distanceKm)} km` })
    } else if (metric === 'hr' && (workout.hrAvg || workout.hrMax)) {
      const parts = [
        workout.hrAvg  ? `${workout.hrAvg} avg` : null,
        workout.hrMax  ? `${workout.hrMax} max` : null,
      ].filter(Boolean).join(' · ')
      chips.push({ label: '♥ ', value: parts })
    } else if (metric === 'elevation' && workout.elevationGainM) {
      chips.push({ label: '↑ ', value: `${Math.round(workout.elevationGainM)}m` })
    }
  }

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => item.importedWorkoutId && navigate(`/import/${encodeURIComponent(item.importedWorkoutId)}`)}
      onKeyDown={(e) => e.key === 'Enter' && item.importedWorkoutId && navigate(`/import/${encodeURIComponent(item.importedWorkoutId)}`)}
      className={cn(
        'rounded-xl border border-border/60 bg-card px-4 py-3 space-y-1.5',
        item.importedWorkoutId && 'cursor-pointer hover:border-primary/40 hover:bg-card/80 transition-colors',
      )}
    >
      {/* Row 1: week/day label · archetype name · source badge · chevron */}
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <span className="shrink-0 text-[10px] text-muted-foreground/70 tabular-nums">
            Wk {item.weekNumber} · {dayAbbr}
          </span>
          <p className="text-sm font-medium text-foreground truncate leading-tight">
            {archetype.name}
          </p>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <SourceBadge source={workout.source} confidence={item.matchConfidence} />
          {item.importedWorkoutId && <ChevronRight className="size-3.5 text-muted-foreground/50" />}
        </div>
      </div>

      {/* Row 2: metrics + duration delta */}
      <div className="flex items-center gap-2 flex-wrap">
        {chips.map((c, i) => (
          <span key={i} className="text-[11px] text-muted-foreground">
            {c.label}{c.value}
          </span>
        ))}
        <DurationDelta pct={durationDeltaPct} />
      </div>
    </div>
  )
}
