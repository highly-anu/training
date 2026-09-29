import type { AnalyticsArchetypeRow } from '@/api/types'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { cn } from '@/lib/utils'

/** Per session shape: how each archetype in the block is going. */
export function ArchetypeTable({ rows }: { rows: AnalyticsArchetypeRow[] }) {
  if (rows.length === 0) return null
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Session shapes</p>
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead className="text-[10px] uppercase tracking-wider text-muted-foreground">
            <tr className="text-left">
              <th className="py-1 pr-2 font-medium">Archetype</th>
              <th className="py-1 pr-2 font-medium">Done</th>
              <th className="py-1 pr-2 font-medium">Duration Δ</th>
              <th className="py-1 pr-2 font-medium">HR</th>
              <th className="py-1 font-medium">Lead lift</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.archetypeId} className="border-t border-border/60">
                <td className="py-1.5 pr-2">
                  <div className="flex items-center gap-2"><span className="font-medium">{r.name}</span><ModalityBadge modality={r.modality} size="sm" /></div>
                </td>
                <td className="py-1.5 pr-2 tabular-nums">{r.completed}/{r.scheduled}</td>
                <td className={cn('py-1.5 pr-2 tabular-nums', r.meanDurationDeltaPct != null && Math.abs(r.meanDurationDeltaPct) > 25 && 'text-amber-800 dark:text-amber-300')}>
                  {r.meanDurationDeltaPct != null ? `${r.meanDurationDeltaPct > 0 ? '+' : ''}${r.meanDurationDeltaPct}%` : '—'}
                </td>
                <td className="py-1.5 pr-2 tabular-nums text-muted-foreground">{r.hr ? `${r.hr.avg} / ${r.hr.max}` : '—'}</td>
                <td className="py-1.5 tabular-nums text-muted-foreground">
                  {r.leadLift ? `${r.leadLift.exerciseId.replace(/_/g, ' ')} ${r.leadLift.firstEst1rm} → ${r.leadLift.latestEst1rm} est 1RM` : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
