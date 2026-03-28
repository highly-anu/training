import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import type { Framework, ModalityId } from '@/api/types'

interface FrameworkDetailModalProps {
  framework: Framework | null
  open: boolean
  onClose: () => void
}

const INTENSITY_LABELS: Record<string, string> = {
  zone1_2_pct: 'Zone 1–2 (easy)',
  zone3_pct: 'Zone 3 (tempo)',
  zone4_5_pct: 'Zone 4–5 (hard)',
  max_effort_pct: 'Max effort',
}

export function FrameworkDetailModal({ framework, open, onClose }: FrameworkDetailModalProps) {
  if (!framework) return null

  const incompatible = (framework as any).incompatible_with as Array<{
    framework_id: string
    reason?: string
    interference_level?: string
    mitigation?: string
  }> | undefined

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="text-lg font-semibold">{framework.name}</DialogTitle>
        </DialogHeader>

        {/* Meta row */}
        <div className="flex flex-wrap gap-2">
          {framework.progression_model && (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
              {framework.progression_model.replace(/_/g, ' ')}
            </span>
          )}
          {framework.source_philosophy && (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
              {framework.source_philosophy.replace(/_/g, ' ')}
            </span>
          )}
          {framework.applicable_when?.days_per_week_min !== undefined && (
            <span className="text-[10px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
              {framework.applicable_when.days_per_week_min}–{framework.applicable_when.days_per_week_max} days/wk
            </span>
          )}
          {framework.applicable_when?.training_level?.map((lvl) => (
            <span key={lvl} className="text-[10px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground capitalize">
              {lvl}
            </span>
          ))}
        </div>

        {/* Notes */}
        {framework.notes && (
          <p className="text-sm text-muted-foreground leading-relaxed">{framework.notes}</p>
        )}

        {/* Sessions per week */}
        {framework.sessions_per_week && Object.keys(framework.sessions_per_week).length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Sessions per Week
            </h4>
            <div className="space-y-1.5">
              {Object.entries(framework.sessions_per_week).map(([mod, count]) => {
                const c = MODALITY_COLORS[mod as ModalityId]
                if (!c || !count) return null
                return (
                  <div key={mod} className="flex items-center justify-between text-xs">
                    <span style={{ color: c.hex }}>{c.label}</span>
                    <span className="font-medium text-foreground">{count}×</span>
                  </div>
                )
              })}
            </div>
          </section>
        )}

        {/* Intensity distribution */}
        {framework.intensity_distribution && Object.keys(framework.intensity_distribution).length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Intensity Distribution
            </h4>
            <div className="space-y-2">
              {Object.entries(framework.intensity_distribution).map(([key, pct]) => {
                const label = INTENSITY_LABELS[key] ?? key.replace(/_/g, ' ')
                const width = Math.round((pct ?? 0) * 100)
                return (
                  <div key={key} className="flex items-center gap-3">
                    <span className="w-32 shrink-0 text-xs text-foreground">{label}</span>
                    <div className="flex-1 h-2 rounded-full bg-border overflow-hidden">
                      <div
                        className="h-full rounded-full bg-primary"
                        style={{ width: `${width}%` }}
                      />
                    </div>
                    <span className="w-8 shrink-0 text-right text-xs text-muted-foreground">{width}%</span>
                  </div>
                )
              })}
            </div>
          </section>
        )}

        {/* Deload protocol */}
        {framework.deload_protocol && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Deload Protocol
            </h4>
            <dl className="space-y-1 text-xs">
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Frequency</dt>
                <dd className="font-medium text-foreground">Every {framework.deload_protocol.frequency_weeks} weeks</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Volume reduction</dt>
                <dd className="font-medium text-foreground">{Math.round(framework.deload_protocol.volume_reduction_pct * 100)}%</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-muted-foreground">Intensity</dt>
                <dd className="font-medium text-foreground capitalize">{framework.deload_protocol.intensity_change.replace(/_/g, ' ')}</dd>
              </div>
            </dl>
          </section>
        )}

        {/* Incompatibilities */}
        {incompatible && incompatible.length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Incompatible With
            </h4>
            <ul className="space-y-3">
              {incompatible.map((entry) => (
                <li key={entry.framework_id} className="text-xs space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="px-2 py-0.5 rounded-full bg-destructive/10 text-destructive font-medium">
                      {entry.framework_id.replace(/_/g, ' ')}
                    </span>
                    {entry.interference_level && (
                      <span className="text-muted-foreground capitalize">{entry.interference_level} interference</span>
                    )}
                  </div>
                  {entry.reason && (
                    <p className="text-muted-foreground leading-relaxed pl-1">{entry.reason.trim()}</p>
                  )}
                  {entry.mitigation && (
                    <p className="text-emerald-600 dark:text-emerald-400 leading-relaxed pl-1">
                      <span className="font-medium">Mitigation: </span>{entry.mitigation.trim()}
                    </p>
                  )}
                </li>
              ))}
            </ul>
          </section>
        )}

        {/* Sources */}
        {framework.sources && framework.sources.length > 0 && (
          <section>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground mb-2">
              Sources
            </h4>
            <ul className="space-y-0.5">
              {framework.sources.map((src, i) => (
                <li key={i} className="text-xs text-muted-foreground">{src}</li>
              ))}
            </ul>
          </section>
        )}
      </DialogContent>
    </Dialog>
  )
}
