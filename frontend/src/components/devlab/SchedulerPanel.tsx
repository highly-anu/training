import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import type { ModalityId, TrainingPhase, WeekTrace } from '@/api/types'

interface Props {
  weeks: WeekTrace[]
}

const DAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

export function SchedulerPanel({ weeks }: Props) {
  return (
    <div className="space-y-4">
      {weeks.map(week => {
        const fw = week.scheduler.framework_selection
        const alloc = week.scheduler.allocation
        const assign = week.scheduler.day_assignment

        return (
          <Card key={week.week_number}>
            <CardHeader className="pb-2">
              <CardTitle className="flex flex-wrap items-center gap-2 text-sm">
                <span>Week {week.week_number}</span>
                <PhaseBadge phase={week.phase as TrainingPhase} />
                {week.is_deload && <Badge variant="outline" className="text-xs">Deload</Badge>}
                <Badge variant="secondary" className="font-mono text-xs">{fw.selected_id}</Badge>
                <span className="text-xs text-muted-foreground ml-auto">{fw.selection_reason}</span>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              {/* Allocation */}
              <div>
                <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-2">
                  Session Allocation
                </p>
                <div className="flex flex-wrap gap-2">
                  {Object.entries(alloc.final).map(([mod, count]) => {
                    const raw = alloc.raw[mod] ?? 0
                    return (
                      <div
                        key={mod}
                        className="flex items-center gap-1.5 bg-muted/40 rounded-md px-2 py-1"
                      >
                        <ModalityBadge modality={mod as ModalityId} size="sm" />
                        <span className="text-xs font-mono text-muted-foreground">
                          ({raw.toFixed(2)} →
                        </span>
                        <span className="text-xs font-bold">{count})</span>
                      </div>
                    )
                  })}
                </div>
              </div>

              {/* Day Grid */}
              <div>
                <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-widest mb-2">
                  Day Assignment
                </p>
                <div className="grid grid-cols-7 gap-1">
                  {DAY_LABELS.map(dayLabel => {
                    const mods = assign.assignments[dayLabel] ?? []
                    return (
                      <div key={dayLabel} className="text-center">
                        <p className="text-[10px] text-muted-foreground mb-1">{dayLabel}</p>
                        <div className="min-h-[28px] space-y-0.5">
                          {mods.length > 0 ? (
                            mods.map(mod => (
                              <div
                                key={mod}
                                className="rounded px-1 py-0.5 text-[9px] font-medium truncate bg-primary/10 text-primary"
                                title={mod}
                              >
                                {mod.replace(/_/g, ' ').slice(0, 10)}
                              </div>
                            ))
                          ) : (
                            <div className="rounded px-1 py-1 text-[9px] text-muted-foreground/30 text-center">
                              —
                            </div>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
                <p className="text-[10px] text-muted-foreground mt-1">
                  Day pool: [{assign.day_pool.join(', ')}] · Modality order: {assign.modality_order.join(' → ')}
                </p>
              </div>

              {/* Framework details (collapsible) */}
              <details className="text-xs">
                <summary className="cursor-pointer select-none text-muted-foreground hover:text-foreground transition-colors">
                  Framework selection details
                </summary>
                <div className="mt-2 space-y-1 pl-3 border-l border-border">
                  {fw.forced_override ? (
                    <p>Forced override: <code className="bg-muted px-1 rounded">{fw.forced_override}</code></p>
                  ) : (
                    <>
                      <p>Default: <code className="bg-muted px-1 rounded">{fw.default_id}</code></p>
                      {fw.alternatives_checked.map((alt, i) => (
                        <p key={i} className={alt.matched ? 'text-green-500' : 'text-muted-foreground'}>
                          {alt.matched ? '✓' : '○'}{' '}
                          <code className="bg-muted px-1 rounded">{alt.condition}</code>{' '}
                          → {alt.framework_id}
                        </p>
                      ))}
                    </>
                  )}
                  {fw.days_constraint && (
                    <p className="text-muted-foreground">
                      Days constraint: athlete={fw.days_constraint.athlete_days},
                      fw=[{fw.days_constraint.framework_min}–{fw.days_constraint.framework_max}]
                      {fw.days_constraint.days_fallback && ` → fallback: ${fw.days_constraint.days_fallback}`}
                    </p>
                  )}
                </div>
              </details>

              {/* Raw vs rounded allocation */}
              <details className="text-xs">
                <summary className="cursor-pointer select-none text-muted-foreground hover:text-foreground transition-colors">
                  Priority → raw allocation
                </summary>
                <div className="mt-2 overflow-x-auto">
                  <table className="text-xs w-full">
                    <thead>
                      <tr className="text-muted-foreground text-left">
                        <th className="pr-4 pb-1">Modality</th>
                        <th className="pr-4 pb-1">Priority</th>
                        <th className="pr-4 pb-1">Raw</th>
                        <th className="pb-1">Final</th>
                      </tr>
                    </thead>
                    <tbody>
                      {Object.entries(alloc.phase_priorities)
                        .filter(([, v]) => v > 0)
                        .sort(([, a], [, b]) => b - a)
                        .map(([mod, prio]) => (
                          <tr key={mod} className="border-t border-border/20">
                            <td className="pr-4 py-0.5">{mod}</td>
                            <td className="pr-4 py-0.5 font-mono">{(prio * 100).toFixed(0)}%</td>
                            <td className="pr-4 py-0.5 font-mono">{(alloc.raw[mod] ?? 0).toFixed(2)}</td>
                            <td className="py-0.5 font-mono">{alloc.final[mod] ?? 0}</td>
                          </tr>
                        ))}
                    </tbody>
                  </table>
                </div>
              </details>
            </CardContent>
          </Card>
        )
      })}
    </div>
  )
}
