import { Network } from 'lucide-react'
import { CrossRefBadge } from '../CrossRefBadge'
import type { Modality, Archetype, GoalProfile } from '@/api/types'
import type { NavigateToFn, OpenInOntologyFn } from '../types'

interface ModalityDetailProps {
  modality: Modality
  archetypes: Archetype[]
  goals: GoalProfile[]
  navigateTo: NavigateToFn
  onOpenInOntology?: OpenInOntologyFn
}

export function ModalityDetail({ modality: m, archetypes, goals, navigateTo, onOpenInOntology }: ModalityDetailProps) {
  const implementedBy = archetypes.filter(a => a.modality === m.id)
  const weightedBy = goals.filter(g => (g.priorities[m.id] ?? 0) > 0)

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">{m.name}</h2>
          <p className="text-xs text-muted-foreground font-mono mt-0.5">{m.id}</p>
        </div>
        {onOpenInOntology && (
          <button
            onClick={() => onOpenInOntology(`modality::${m.id}`)}
            className="shrink-0 flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
          >
            <Network className="size-3" />
            Ontology
          </button>
        )}
      </div>

      {m.description && (
        <p className="text-sm text-muted-foreground">{m.description}</p>
      )}

      {/* Recovery */}
      <dl className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Recovery Cost</dt>
          <dd className="mt-0.5 capitalize">{m.recovery_cost}</dd>
        </div>
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Recovery Hours Min</dt>
          <dd className="mt-0.5">{m.recovery_hours_min}h</dd>
        </div>
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Session Position</dt>
          <dd className="mt-0.5">{m.session_position}</dd>
        </div>
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Weekly Volume</dt>
          <dd className="mt-0.5">{m.min_weekly_minutes}–{m.max_weekly_minutes} min</dd>
        </div>
        {m.typical_session_minutes && (
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Typical Session</dt>
            <dd className="mt-0.5">{m.typical_session_minutes.min}–{m.typical_session_minutes.max} min</dd>
          </div>
        )}
        <div>
          <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Progression Model</dt>
          <dd className="mt-0.5 font-mono text-xs">{m.progression_model}</dd>
        </div>
      </dl>

      {/* Compatibility */}
      {m.compatible_in_session_with?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Compatible With</p>
          <div className="flex flex-wrap gap-1">
            {m.compatible_in_session_with.map(id => (
              <CrossRefBadge key={id} label={id} type="modalities" id={id} navigateTo={navigateTo} />
            ))}
          </div>
        </div>
      ) : null}

      {m.incompatible_in_session_with?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Incompatible With</p>
          <div className="flex flex-wrap gap-1">
            {m.incompatible_in_session_with.map(id => (
              <CrossRefBadge key={id} label={id} type="modalities" id={id} navigateTo={navigateTo} />
            ))}
          </div>
        </div>
      ) : null}

      {/* Intensity zones */}
      {m.intensity_zones?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Intensity Zones</p>
          <div className="space-y-1">
            {m.intensity_zones.map((z, i) => (
              <div key={i} className="flex items-start gap-2 text-xs">
                <span className="font-medium w-20 shrink-0">{z.label}</span>
                <span className="text-muted-foreground">{z.description}</span>
                {z.hr_pct_range && (
                  <span className="font-mono text-muted-foreground ml-auto shrink-0">
                    {z.hr_pct_range[0]}–{z.hr_pct_range[1]}%
                  </span>
                )}
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {/* Reverse refs */}
      <div className="space-y-3 pt-2 border-t">
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Related</p>

        {implementedBy.length > 0 && (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Implemented by archetypes ({implementedBy.length})</p>
            <div className="flex flex-wrap gap-1">
              {implementedBy.map(a => (
                <CrossRefBadge key={a.id} label={a.name} type="archetypes" id={a.id} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        )}

        {weightedBy.length > 0 && (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Weighted by goals</p>
            <div className="flex flex-wrap gap-1">
              {weightedBy.map(g => (
                <CrossRefBadge key={g.id} label={g.name} type="goals" id={g.id} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        )}
      </div>

      {m.notes && (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Notes</p>
          <p className="text-xs text-muted-foreground">{m.notes}</p>
        </div>
      )}
    </div>
  )
}
