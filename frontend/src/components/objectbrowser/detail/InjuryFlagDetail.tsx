import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { CrossRefBadge } from '../CrossRefBadge'
import type { InjuryFlag } from '@/api/types'
import type { NavigateToFn } from '../types'

interface InjuryFlagDetailProps {
  flag: InjuryFlag
  navigateTo: NavigateToFn
}

export function InjuryFlagDetail({ flag: f, navigateTo }: InjuryFlagDetailProps) {
  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">{f.name}</h2>
        <p className="text-xs text-muted-foreground font-mono mt-0.5">{f.id}</p>
      </div>

      {f.description && (
        <p className="text-sm text-muted-foreground">{f.description}</p>
      )}

      {f.training_phase_forced && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Forces Phase</p>
          <PhaseBadge phase={f.training_phase_forced} />
        </div>
      )}

      {f.excluded_movement_patterns?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Excluded Movement Patterns</p>
          <div className="flex flex-wrap gap-1">
            {f.excluded_movement_patterns.map(p => (
              <span key={p} className="px-2 py-0.5 rounded text-xs bg-destructive/10 border border-destructive/30 font-mono text-destructive">
                {p}
              </span>
            ))}
          </div>
        </div>
      ) : null}

      {f.excluded_exercises?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">
            Excluded Exercises ({f.excluded_exercises.length})
          </p>
          <div className="flex flex-wrap gap-1">
            {f.excluded_exercises.map(id => (
              <CrossRefBadge key={id} label={id} type="exercises" id={id} navigateTo={navigateTo} />
            ))}
          </div>
        </div>
      ) : null}

      {f.modified_exercises?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Substitutions</p>
          <div className="space-y-1.5">
            {f.modified_exercises.map((mod, i) => (
              <div key={i} className="flex items-center gap-2 text-xs">
                <CrossRefBadge label={mod.instead_of} type="exercises" id={mod.instead_of} navigateTo={navigateTo} />
                <span className="text-muted-foreground">→</span>
                <CrossRefBadge label={mod.use} type="exercises" id={mod.use} navigateTo={navigateTo} />
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {f.notes && (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Notes</p>
          <p className="text-xs text-muted-foreground">{f.notes}</p>
        </div>
      )}
    </div>
  )
}
