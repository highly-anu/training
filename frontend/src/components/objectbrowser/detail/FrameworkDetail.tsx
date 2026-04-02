import { Network } from 'lucide-react'
import { CrossRefBadge } from '../CrossRefBadge'
import type { Framework } from '@/api/types'
import type { NavigateToFn, OpenInOntologyFn } from '../types'

interface FrameworkDetailProps {
  framework: Framework
  navigateTo: NavigateToFn
  onOpenInOntology?: OpenInOntologyFn
}

export function FrameworkDetail({ framework: fw, navigateTo, onOpenInOntology }: FrameworkDetailProps) {
  const sessionsPerWeek = fw.sessions_per_week
    ? Object.entries(fw.sessions_per_week).sort(([, a], [, b]) => (b ?? 0) - (a ?? 0))
    : []

  const intensityEntries = fw.intensity_distribution
    ? Object.entries(fw.intensity_distribution)
    : []

  const incompatible = (fw as { incompatible_with?: Array<{ framework_id: string; reason?: string }> }).incompatible_with ?? []

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-base font-semibold">{fw.name}</h2>
          <p className="text-xs text-muted-foreground font-mono mt-0.5">{fw.id}</p>
        </div>
        {onOpenInOntology && (
          <button
            onClick={() => onOpenInOntology(`framework::${fw.id}`)}
            className="shrink-0 flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
          >
            <Network className="size-3" />
            Ontology
          </button>
        )}
      </div>

      {/* Source philosophy */}
      {fw.source_philosophy && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Source Philosophy</p>
          <CrossRefBadge label={fw.source_philosophy} type="philosophies" id={fw.source_philosophy} navigateTo={navigateTo} />
        </div>
      )}

      {/* Progression model */}
      {(fw as { progression_model?: string }).progression_model && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-0.5">Progression Model</p>
          <span className="text-sm font-mono">{(fw as { progression_model?: string }).progression_model}</span>
        </div>
      )}

      {/* Sessions per week */}
      {sessionsPerWeek.length > 0 && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Sessions / Week</p>
          <div className="space-y-1.5">
            {sessionsPerWeek.map(([mod, count]) => (
              <div key={mod} className="flex items-center gap-2 text-xs">
                <button
                  onClick={() => navigateTo('modalities', mod)}
                  className="w-40 truncate text-left text-muted-foreground hover:text-primary transition-colors"
                >
                  {mod.replace(/_/g, ' ')}
                </button>
                <div className="flex gap-0.5">
                  {Array.from({ length: count ?? 0 }).map((_, i) => (
                    <div key={i} className="size-2 rounded-full bg-primary/70" />
                  ))}
                </div>
                <span className="font-mono text-muted-foreground">{count}×/wk</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Intensity distribution */}
      {intensityEntries.length > 0 && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Intensity Distribution</p>
          <div className="space-y-1.5">
            {intensityEntries.map(([zone, pct]) => (
              <div key={zone} className="flex items-center gap-2">
                <span className="text-xs text-muted-foreground w-40 truncate">{zone.replace(/_/g, ' ')}</span>
                <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
                  <div className="h-full bg-primary/70 rounded-full" style={{ width: `${(pct ?? 0) * 100}%` }} />
                </div>
                <span className="text-xs font-mono text-muted-foreground w-8 text-right">
                  {((pct ?? 0) * 100).toFixed(0)}%
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Applicable when */}
      {fw.applicable_when && (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Applicable When</p>
          <dl className="grid grid-cols-2 gap-2 text-xs">
            {fw.applicable_when.training_level?.length && (
              <>
                <dt className="text-muted-foreground">Levels</dt>
                <dd>{fw.applicable_when.training_level.join(', ')}</dd>
              </>
            )}
            {fw.applicable_when.days_per_week_min != null && (
              <>
                <dt className="text-muted-foreground">Days/week</dt>
                <dd>{fw.applicable_when.days_per_week_min}–{fw.applicable_when.days_per_week_max}</dd>
              </>
            )}
          </dl>
        </div>
      )}

      {/* Goals served */}
      {fw.goals_served?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Goals Served (Modalities)</p>
          <div className="flex flex-wrap gap-1">
            {fw.goals_served.map(m => (
              <button
                key={m}
                onClick={() => navigateTo('modalities', m)}
                className="px-2 py-0.5 rounded text-xs bg-muted border border-border font-mono hover:border-primary/50 hover:bg-primary/5 transition-colors"
              >
                {m}
              </button>
            ))}
          </div>
        </div>
      ) : null}

      {/* Incompatible frameworks */}
      {incompatible.length > 0 && (
        <div className="pt-2 border-t">
          <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-1.5">Incompatible Frameworks</p>
          <div className="space-y-1">
            {incompatible.map((item) => (
              <div key={item.framework_id} className="flex items-start gap-2 text-xs">
                <CrossRefBadge label={item.framework_id} type="frameworks" id={item.framework_id} navigateTo={navigateTo} />
                {item.reason && <span className="text-muted-foreground">{item.reason}</span>}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
