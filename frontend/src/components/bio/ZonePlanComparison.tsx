import type { WorkoutAnalysis } from '@/api/types'
import { ZONE_COLORS } from '@/lib/hrZones'
import { untrackedText, zonePlanRows, type ZonePlanRow } from '@/lib/zonePlan'

/**
 * Planned against recorded minutes per heart-rate zone: what the programming
 * planned as an outline, what the heart rate recorded filled over it, both
 * against the largest value. Analytics ▸ Program's intensity split draws it
 * over the block; the workout page draws it for one session (`PlannedZones`).
 * The phone's is `ZonePlanComparison.swift` (design-system §6.35).
 */
export function ZonePlanComparison({ rows }: { rows: ZonePlanRow[] }) {
  const top = Math.max(1, ...rows.map((r) => Math.max(r.planned, r.recorded)))
  return (
    <div className="space-y-2">
      {rows.map((r) => {
        const color = ZONE_COLORS[Number(r.zone.slice(1)) - 1] ?? ZONE_COLORS[4]
        return (
          <div key={r.zone} className="flex items-center gap-2 text-xs"
               aria-label={`${r.label}: ${Math.round(r.recorded)} minutes recorded, ${Math.round(r.planned)} planned`}>
            <span className="w-8 font-medium">{r.label}</span>
            <div className="relative h-[18px] flex-1">
              {r.planned > 0 && (
                <div className="absolute inset-y-0 left-0 rounded" style={{
                  width: `max(6px, ${(100 * r.planned) / top}%)`, border: `1.5px solid ${color}` }} />
              )}
              {r.recorded > 0 && (
                <div className="absolute left-0 top-[3px] bottom-[3px] rounded" style={{
                  width: `max(4px, ${(100 * r.recorded) / top}%)`, backgroundColor: color, opacity: 0.85 }} />
              )}
            </div>
            <span className="w-20 text-right tabular-nums text-muted-foreground">
              {Math.round(r.recorded)}/{Math.round(r.planned)} min
            </span>
          </div>
        )
      })}
      <div className="flex gap-4 text-[11px] text-muted-foreground" aria-hidden="true">
        <span className="inline-flex items-center gap-1"><span className="inline-block h-2 w-3.5 rounded-sm bg-muted-foreground" />Recorded</span>
        <span className="inline-flex items-center gap-1"><span className="inline-block h-2.5 w-3.5 rounded-sm border-[1.5px] border-muted-foreground" />Planned</span>
      </div>
    </div>
  )
}

/** One workout against what its session planned; nothing when it is linked to no session. */
export function PlannedZones({ analysis }: { analysis: WorkoutAnalysis }) {
  const plan = analysis.planned
  if (!plan) return null
  return (
    <div className="space-y-2">
      <p className="text-xs font-semibold text-muted-foreground">Planned for {plan.sessionName ?? 'the session'}</p>
      {plan.track && analysis.zones
        ? <ZonePlanComparison rows={zonePlanRows(plan.plannedMinutes, analysis.zones.minutes)} />
        : <p className="text-xs text-muted-foreground">
            {plan.track ? 'No heart rate was recorded to compare.' : untrackedText(plan)}
          </p>}
    </div>
  )
}
