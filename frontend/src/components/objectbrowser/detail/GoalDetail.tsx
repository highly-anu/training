import { PhaseBadge } from '@/components/shared/PhaseBadge'
import { CrossRefBadge } from '../CrossRefBadge'
import type { GoalProfile } from '@/api/types'
import type { NavigateToFn } from '../types'

interface GoalDetailProps {
  goal: GoalProfile
  navigateTo: NavigateToFn
}

export function GoalDetail({ goal: g, navigateTo }: GoalDetailProps) {
  const sortedPriorities = Object.entries(g.priorities)
    .filter(([, v]) => v > 0)
    .sort(([, a], [, b]) => b - a)

  return (
    <div className="space-y-5">
      <div>
        <h2 className="text-base font-semibold">{g.name}</h2>
        <p className="text-xs text-muted-foreground font-mono mt-0.5">{g.id}</p>
      </div>

      {g.description && (
        <p className="text-sm text-muted-foreground">{g.description}</p>
      )}

      {/* Priority bars */}
      <div>
        <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-2">Modality Priorities</p>
        <div className="space-y-1.5">
          {sortedPriorities.map(([mod, prio]) => (
            <div key={mod} className="flex items-center gap-2">
              <button
                onClick={() => navigateTo('modalities', mod)}
                className="text-xs text-muted-foreground w-36 truncate text-left hover:text-primary transition-colors"
              >
                {mod.replace(/_/g, ' ')}
              </button>
              <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
                <div
                  className="h-full bg-primary rounded-full transition-all"
                  style={{ width: `${prio * 100}%` }}
                />
              </div>
              <span className="text-xs font-mono text-muted-foreground w-8 text-right">
                {(prio * 100).toFixed(0)}%
              </span>
            </div>
          ))}
        </div>
      </div>

      {/* Phase sequence */}
      {g.phase_sequence?.length ? (
        <div>
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Phase Sequence</p>
          <div className="flex flex-wrap gap-1.5">
            {g.phase_sequence.map((p, i) => (
              <div key={i} className="flex items-center gap-1">
                <PhaseBadge phase={p.phase} />
                <span className="text-[10px] text-muted-foreground">{p.weeks}w</span>
              </div>
            ))}
          </div>
        </div>
      ) : null}

      {/* Expectations */}
      {g.expectations && (
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Min Weeks</dt>
            <dd className="mt-0.5">{g.expectations.min_weeks}</dd>
          </div>
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Ideal Weeks</dt>
            <dd className="mt-0.5">{g.expectations.ideal_weeks}</dd>
          </div>
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Days/week</dt>
            <dd className="mt-0.5">{g.expectations.min_days_per_week}–{g.expectations.ideal_days_per_week}</dd>
          </div>
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Session (min)</dt>
            <dd className="mt-0.5">{g.expectations.min_session_minutes}–{g.expectations.ideal_session_minutes}</dd>
          </div>
          <div>
            <dt className="text-[10px] text-muted-foreground uppercase tracking-wider">Split Days</dt>
            <dd className="mt-0.5">{g.expectations.supports_split_days ? 'Yes' : 'No'}</dd>
          </div>
        </dl>
      )}

      {/* Framework & sources */}
      <div className="space-y-3 pt-2 border-t">
        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">Related</p>

        {g.framework_selection && (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Framework</p>
            <div className="flex flex-wrap gap-1">
              <CrossRefBadge
                label={g.framework_selection.default_framework}
                type="frameworks"
                id={g.framework_selection.default_framework}
                navigateTo={navigateTo}
              />
              {g.framework_selection.alternatives?.map(alt => (
                <CrossRefBadge
                  key={alt.framework_id}
                  label={`${alt.framework_id} (if ${alt.condition})`}
                  type="frameworks"
                  id={alt.framework_id}
                  navigateTo={navigateTo}
                />
              ))}
            </div>
          </div>
        )}

        {g.primary_sources?.length ? (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Philosophies</p>
            <div className="flex flex-wrap gap-1">
              {g.primary_sources.map(src => (
                <CrossRefBadge key={src} label={src} type="philosophies" id={src} navigateTo={navigateTo} />
              ))}
            </div>
          </div>
        ) : null}

        {g.incompatible_with?.length ? (
          <div>
            <p className="text-xs text-muted-foreground mb-1">Incompatible goals</p>
            <div className="flex flex-wrap gap-1">
              {g.incompatible_with.map((item, i) => {
                const id = typeof item === 'string' ? item : item.goal_id
                return <CrossRefBadge key={i} label={id} type="goals" id={id} navigateTo={navigateTo} />
              })}
            </div>
          </div>
        ) : null}
      </div>

      {g.notes && (
        <div className="pt-2 border-t">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wider mb-1.5">Notes</p>
          <p className="text-xs text-muted-foreground">{g.notes}</p>
        </div>
      )}
    </div>
  )
}
