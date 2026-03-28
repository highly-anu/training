import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { sortPriorities } from '@/lib/prioritySort'
import type { GoalProfile } from '@/api/types'

interface GoalDetailModalProps {
  goal: GoalProfile | null
  open: boolean
  onClose: () => void
}

export function GoalDetailModal({ goal, open, onClose }: GoalDetailModalProps) {
  if (!goal) return null

  const priorities = sortPriorities(goal.priorities)

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-lg font-semibold">{goal.name}</DialogTitle>
        </DialogHeader>

        <p className="text-sm text-muted-foreground leading-relaxed">{goal.description}</p>

        {goal.notes && (
          <p className="text-xs text-muted-foreground italic border-l-2 border-border pl-3">
            {goal.notes}
          </p>
        )}

        {/* Priority breakdown */}
        <section>
          <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
            Training Priorities
          </h4>
          <div className="space-y-2">
            {priorities.map(({ modality, weight }) => {
              const c = MODALITY_COLORS[modality]
              return (
                <div key={modality} className="flex items-center gap-3">
                  <span className="w-36 shrink-0 text-xs text-foreground">{c.label}</span>
                  <div className="flex-1 h-2 rounded-full bg-border overflow-hidden">
                    <div
                      className="h-full rounded-full"
                      style={{ width: `${weight * 100}%`, backgroundColor: c.hex }}
                    />
                  </div>
                  <span className="w-8 shrink-0 text-right text-xs text-muted-foreground">
                    {Math.round(weight * 100)}%
                  </span>
                </div>
              )
            })}
          </div>
        </section>

        {/* Phase sequence */}
        <section>
          <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
            Phase Sequence
          </h4>
          <div className="rounded-lg border border-border overflow-hidden">
            <table className="w-full text-xs">
              <thead className="bg-muted/50">
                <tr>
                  <th className="text-left px-3 py-2 font-medium text-muted-foreground">Phase</th>
                  <th className="text-left px-3 py-2 font-medium text-muted-foreground">Weeks</th>
                  <th className="text-left px-3 py-2 font-medium text-muted-foreground">Focus</th>
                </tr>
              </thead>
              <tbody>
                {goal.phase_sequence.map((p, i) => (
                  <tr key={i} className="border-t border-border">
                    <td className="px-3 py-2 font-medium capitalize">{p.phase.replace(/_/g, ' ')}</td>
                    <td className="px-3 py-2 text-muted-foreground">{p.weeks}w</td>
                    <td className="px-3 py-2 text-muted-foreground">{p.focus}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {/* Framework */}
        <section>
          <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
            Framework
          </h4>
          <p className="text-xs text-foreground mb-1">
            Default:{' '}
            <span className="font-medium">
              {goal.framework_selection.default_framework.replace(/_/g, ' ')}
            </span>
          </p>
          {goal.framework_selection.alternatives.length > 0 && (
            <ul className="space-y-0.5">
              {goal.framework_selection.alternatives.map((alt, i) => (
                <li key={i} className="text-xs text-muted-foreground">
                  <span className="font-medium text-foreground">
                    {alt.framework_id.replace(/_/g, ' ')}
                  </span>{' '}
                  — {alt.condition}
                </li>
              ))}
            </ul>
          )}
        </section>

        {/* Prerequisites */}
        {Object.keys(goal.minimum_prerequisites).length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Minimum Prerequisites
            </h4>
            <ul className="space-y-0.5">
              {Object.entries(goal.minimum_prerequisites).map(([k, v]) => (
                <li key={k} className="text-xs text-muted-foreground">
                  <span className="font-medium text-foreground">{k.replace(/_/g, ' ')}</span>:{' '}
                  {v}
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* Incompatibilities */}
        {goal.incompatible_with.length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Incompatible With
            </h4>
            <ul className="space-y-1">
              {(goal.incompatible_with as Array<{ goal_id: string; reason?: string } | string>).map((entry) => {
                const id = typeof entry === 'string' ? entry : entry.goal_id
                const reason = typeof entry === 'string' ? undefined : entry.reason
                return (
                  <li key={id} className="text-xs">
                    <span className="inline-flex px-2 py-0.5 rounded-full bg-destructive/10 text-destructive mr-2">
                      {id.replace(/_/g, ' ')}
                    </span>
                    {reason && <span className="text-muted-foreground">{reason}</span>}
                  </li>
                )
              })}
            </ul>
          </section>
        )}

        {/* Sources */}
        <section>
          <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
            Sources
          </h4>
          <div className="flex flex-wrap gap-1">
            {goal.primary_sources.map((src) => (
              <span
                key={src}
                className="inline-flex text-[10px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground"
              >
                {src.replace(/_/g, ' ')}
              </span>
            ))}
          </div>
        </section>
      </DialogContent>
    </Dialog>
  )
}
