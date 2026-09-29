import type { AnalyticsFrame } from '@/api/types'
import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { cn } from '@/lib/utils'
import type { TrainingPhase } from '@/api/types'

const FIDELITY_STYLE: Record<string, string> = {
  meets_ideal:   'text-emerald-700 dark:text-emerald-300',
  below_ideal:   'text-amber-800 dark:text-amber-300',
  below_minimum: 'text-red-700 dark:text-red-300',
}

/** What this program is, and where the athlete is in it. */
export function ProgramFrame({ frame }: { frame: AnalyticsFrame }) {
  const phil = frame.philosophies[0]
  return (
    <div className="rounded-lg border bg-card p-4 space-y-3">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">Program</p>
          <h2 className="truncate text-lg font-semibold text-foreground">
            {frame.philosophies.map((p) => p.name).join(' + ')}
          </h2>
          {phil?.progressionPhilosophy && (
            <p className="text-xs text-muted-foreground">
              Progresses by <span className="font-medium text-foreground">{phil.progressionPhilosophy.replace(/_/g, ' ')}</span>
              {phil.intensityModel && <> · {phil.intensityModel.replace(/_/g, ' ')}</>}
            </p>
          )}
        </div>
        {frame.phase && (
          <div className="text-right">
            <div className="flex items-center justify-end gap-2">
              <PhaseBadge phase={frame.phase.name as TrainingPhase} />
              {frame.phase.isDeload && (
                <span className="rounded-full border border-border px-2 py-0.5 text-[10px] text-muted-foreground">deload</span>
              )}
            </div>
            <p className="mt-1 text-xs text-muted-foreground">
              Week {frame.phase.weekInProgram} of {frame.phase.totalWeeks}
            </p>
          </div>
        )}
      </div>

      {frame.phase?.focus && (
        <p className="text-sm text-muted-foreground leading-relaxed">{frame.phase.focus}</p>
      )}

      {frame.planFidelity.length > 0 && (
        <div className="flex flex-wrap gap-x-4 gap-y-1 text-[11px]">
          {frame.planFidelity.map((f) => (
            <span key={f.field} className="text-muted-foreground">
              {f.field.replace(/_/g, ' ')}:{' '}
              <span className={cn('font-medium', FIDELITY_STYLE[f.status])}>
                {f.actual}{f.unit === 'wk' ? ' wk' : ''} / {f.ideal} ideal
              </span>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
