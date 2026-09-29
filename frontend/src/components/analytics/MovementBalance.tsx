import type { AnalyticsMovement } from '@/api/types'
import { cn } from '@/lib/utils'

function Bars({ title, rollups, unit }: { title: string; rollups: Record<string, { planned: number; done: number }>; unit: string }) {
  const rows = Object.entries(rollups).sort(([, a], [, b]) => b.planned - a.planned)
  if (rows.length === 0) return null
  const max = Math.max(...rows.map(([, r]) => Math.max(r.planned, r.done)), 1)
  return (
    <div className="space-y-1.5">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground">{title}</p>
      {rows.map(([pattern, r]) => (
        <div key={pattern} className="grid grid-cols-[72px_1fr_auto] items-center gap-2 text-[11px]">
          <span className="capitalize text-muted-foreground">{pattern}</span>
          <div className="relative h-2 rounded-full bg-muted" role="img" aria-label={`${pattern}: ${r.done} of ${r.planned} ${unit}`}>
            <div className="absolute inset-y-0 left-0 rounded-full bg-border" style={{ width: `${(r.planned / max) * 100}%` }} />
            <div className="absolute inset-y-0 left-0 rounded-full bg-primary" style={{ width: `${(r.done / max) * 100}%` }} />
          </div>
          <span className="tabular-nums text-muted-foreground"><span className="text-foreground">{r.done}</span>/{r.planned}</span>
        </div>
      ))}
    </div>
  )
}

/** What you moved, by pattern, against what was prescribed. */
export function MovementBalance({ movement }: { movement: AnalyticsMovement }) {
  return (
    <div className="rounded-lg border bg-card p-4 space-y-4">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Movement</p>
        <p className="text-xs text-muted-foreground">Done against planned, by pattern. Sets and minutes are kept apart.</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <Bars title="Sets" rollups={movement.sets.rollups} unit="sets" />
        <Bars title="Minutes" rollups={movement.minutes.rollups} unit="minutes" />
      </div>
      {movement.balance.length > 0 && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px]">
          {movement.balance.map((b) => (
            <span key={`${b.a}:${b.b}`} className={cn('text-muted-foreground', b.level === 'warning' && 'text-amber-800 dark:text-amber-300 font-medium')}>
              {b.a}:{b.b} {b.ratio ?? '—'}{b.level === 'warning' ? ` (outside ${b.min}–${b.max})` : ''}
            </span>
          ))}
          {movement.unilateralShare.done != null && (
            <span className="text-muted-foreground">unilateral {movement.unilateralShare.done}%</span>
          )}
        </div>
      )}
      {movement.minutes.assumed > 0 && (
        <p className="text-[10px] text-muted-foreground">{movement.minutes.assumed} min assumed from completed-but-unmatched sessions.</p>
      )}
    </div>
  )
}
