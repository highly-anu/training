import { useEffect, useMemo, useState } from 'react'
import { Check, Info, Layers } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useBuilderStore } from '@/store/builderStore'
import { useGoals } from '@/api/goals'
import { useFrameworks } from '@/api/frameworks'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { sortPriorities } from '@/lib/prioritySort'
import { FrameworkDetailModal } from './FrameworkDetailModal'
import type { Framework, ModalityId } from '@/api/types'

export function ProgramTuner() {
  const {
    selectedGoalIds,
    goalWeights,
    selectedFrameworkId,
    priorityOverrides,
    numWeeks,
    setFramework,
    setPriorityOverrides,
    setNumWeeks,
  } = useBuilderStore()

  const { data: goals } = useGoals()
  const { data: frameworks } = useFrameworks()
  const [detailFramework, setDetailFramework] = useState<Framework | null>(null)

  const eventDate = useBuilderStore((s) => s.eventDate)
  const isMultiGoal = selectedGoalIds.length > 1

  // Derive the "effective" blended goal priorities from selected goals + weights
  const blendedPriorities = useMemo(() => {
    if (!goals) return {}
    const totalRaw = selectedGoalIds.reduce((s, id) => s + (goalWeights[id] ?? 50), 0)
    const result: Partial<Record<ModalityId, number>> = {}
    for (const gid of selectedGoalIds) {
      const g = goals.find((g) => g.id === gid)
      if (!g) continue
      const w = (goalWeights[gid] ?? 50) / totalRaw
      for (const [mod, val] of Object.entries(g.priorities)) {
        const m = mod as ModalityId
        result[m] = (result[m] ?? 0) + (val ?? 0) * w
      }
    }
    // Normalize
    const total = Object.values(result).reduce((s, v) => s + (v ?? 0), 0) || 1
    return Object.fromEntries(
      Object.entries(result).map(([k, v]) => [k, (v ?? 0) / total])
    ) as Partial<Record<ModalityId, number>>
  }, [goals, selectedGoalIds, goalWeights])

  // Default priority sliders to the goal's priorities (only on first mount for this goal set)
  useEffect(() => {
    if (!priorityOverrides) {
      setPriorityOverrides({ ...blendedPriorities })
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const activePriorities = priorityOverrides ?? blendedPriorities
  const sortedPriorities = sortPriorities(activePriorities)

  // Total raw for normalization display
  const totalRaw = Object.values(activePriorities).reduce((s, v) => s + (v ?? 0), 0) || 1

  function updatePriority(mod: ModalityId, rawValue: number) {
    setPriorityOverrides({ ...activePriorities, [mod]: rawValue })
  }

  function resetPriorities() {
    setPriorityOverrides({ ...blendedPriorities })
  }

  // Determine which goal(s) to use for framework options
  const primaryGoal = goals?.find((g) => g.id === selectedGoalIds[0])
  const goalFrameworkSel = primaryGoal?.framework_selection

  // All framework IDs relevant to the selected goal(s) (default + alternatives)
  const relevantFrameworkIds = useMemo(() => {
    const ids = new Set<string>()
    for (const gid of selectedGoalIds) {
      const g = goals?.find((x) => x.id === gid)
      if (!g) continue
      if (g.framework_selection.default_framework) ids.add(g.framework_selection.default_framework)
      for (const alt of g.framework_selection.alternatives ?? []) {
        if (alt.framework_id) ids.add(alt.framework_id)
      }
    }
    return [...ids]
  }, [goals, selectedGoalIds])

  const relevantFrameworks = frameworks?.filter((f) => relevantFrameworkIds.includes(f.id)) ?? []

  // Total phase weeks for the primary goal
  const defaultNumWeeks = useMemo(() => {
    if (!primaryGoal) return 12
    return primaryGoal.phase_sequence.reduce((s, p) => s + (p.weeks ?? 0), 0) || 12
  }, [primaryGoal])

  const effectiveNumWeeks = numWeeks ?? defaultNumWeeks

  return (
    <div className="space-y-8 max-w-3xl">

      {/* ── Framework selection ── */}
      <section className="space-y-3">
        <div>
          <h2 className="text-sm font-semibold text-foreground">Programming Framework</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            Controls how sessions are structured and periodized each week.
          </p>
        </div>

        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {relevantFrameworks.map((fw) => {
            const isDefault = fw.id === goalFrameworkSel?.default_framework
            const alt = goalFrameworkSel?.alternatives?.find((a) => a.framework_id === fw.id)
            const isSelected = selectedFrameworkId === fw.id
            const isAuto = selectedFrameworkId === null && isDefault

            return (
              <div
                key={fw.id}
                className={cn(
                  'relative flex flex-col gap-1.5 rounded-xl border p-4 transition-shadow',
                  'bg-card hover:shadow-md',
                  isSelected || isAuto
                    ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                    : 'border-border hover:border-primary/50'
                )}
              >
                {(isSelected || isAuto) && (
                  <span className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-primary">
                    <Check className="size-3 text-primary-foreground" />
                  </span>
                )}

                {/* Clickable header selects the framework */}
                <button
                  onClick={() => setFramework(isSelected ? null : fw.id)}
                  className="flex items-start gap-2 pr-6 text-left"
                >
                  <Layers className="size-3.5 mt-0.5 shrink-0 text-muted-foreground" />
                  <div>
                    <p className="text-xs font-semibold text-foreground">{fw.name}</p>
                    {isDefault && (
                      <span className="text-[9px] text-primary font-medium">Default for this goal</span>
                    )}
                    {alt && (
                      <span className="text-[9px] text-muted-foreground">Alt: {alt.condition}</span>
                    )}
                  </div>
                </button>

                {fw.notes && (
                  <button onClick={() => setFramework(isSelected ? null : fw.id)} className="text-left">
                    <p className="text-[10px] text-muted-foreground leading-relaxed line-clamp-3">
                      {fw.notes}
                    </p>
                  </button>
                )}

                {/* Footer: chips + details button */}
                <div className="flex items-end justify-between gap-2 mt-1">
                  <div className="flex flex-wrap gap-2">
                    {fw.applicable_when?.training_level && (
                      <span className="text-[9px] text-muted-foreground">
                        Level: {fw.applicable_when.training_level.join(', ')}
                      </span>
                    )}
                    {fw.applicable_when?.days_per_week_min !== undefined && (
                      <span className="text-[9px] text-muted-foreground">
                        {fw.applicable_when.days_per_week_min}–{fw.applicable_when.days_per_week_max} days/wk
                      </span>
                    )}
                    {fw.progression_model && (
                      <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">
                        {fw.progression_model.replace(/_/g, ' ')}
                      </span>
                    )}
                  </div>

                  <button
                    onClick={(e) => {
                      e.stopPropagation()
                      setDetailFramework(fw)
                    }}
                    className="flex-none flex items-center gap-1 text-[10px] font-medium rounded-md px-2 py-1 text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                  >
                    <Info className="size-3" />
                    Details
                  </button>
                </div>
              </div>
            )
          })}
        </div>

        {selectedFrameworkId && (
          <button
            onClick={() => setFramework(null)}
            className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
          >
            Reset to auto-select
          </button>
        )}
      </section>

      {/* ── Priority weights ── */}
      <section className="space-y-3">
        <div className="flex items-baseline justify-between">
          <div>
            <h2 className="text-sm font-semibold text-foreground">Training Priorities</h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              {isMultiGoal
                ? 'Blended from your goal mix. Adjust to further fine-tune.'
                : 'Override the default emphasis for each domain.'}
            </p>
          </div>
          <button
            onClick={resetPriorities}
            className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2 shrink-0 ml-4"
          >
            Reset to goal default
          </button>
        </div>

        <div className="rounded-xl border border-border bg-card p-4 space-y-3">
          {sortedPriorities.map(({ modality, weight }) => {
            const c = MODALITY_COLORS[modality]
            const pct = Math.round((weight / totalRaw) * 100)
            const rawVal = activePriorities[modality] ?? weight

            return (
              <div key={modality} className="space-y-1">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-medium" style={{ color: c.hex }}>{c.label}</span>
                  <span className="text-muted-foreground font-medium">{pct}%</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex-1 h-1.5 rounded-full bg-border overflow-hidden">
                    <div
                      className="h-full rounded-full transition-all duration-150"
                      style={{ width: `${pct}%`, backgroundColor: c.hex }}
                    />
                  </div>
                  <input
                    type="range"
                    min={0}
                    max={100}
                    step={5}
                    value={Math.round(rawVal * 100)}
                    onChange={(e) => updatePriority(modality, parseInt(e.target.value) / 100)}
                    className="w-24 accent-primary"
                  />
                </div>
              </div>
            )
          })}
        </div>
      </section>

      <FrameworkDetailModal
        framework={detailFramework}
        open={detailFramework !== null}
        onClose={() => setDetailFramework(null)}
      />

      {/* ── Program duration ── */}
      <section className="space-y-3">
        <div>
          <h2 className="text-sm font-semibold text-foreground">Program Duration</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            {eventDate
              ? <>Duration is driven by your event date — the program will cover exactly the weeks from today to <span className="font-medium text-foreground">{eventDate}</span>. Remove the event date in Constraints to set a manual duration.</>
              : <>Full phase sequence is {defaultNumWeeks} weeks. Shorten to generate a subset, extend to repeat the final phase.</>
            }
          </p>
        </div>

        {eventDate ? (
          <div className="rounded-xl border border-border bg-muted/40 px-4 py-3 text-xs text-muted-foreground italic">
            Controlled by event date — slider disabled.
          </div>
        ) : (
          <div className="rounded-xl border border-border bg-card p-4 space-y-2">
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">Weeks to generate</span>
              <span className="font-semibold text-foreground text-sm">{effectiveNumWeeks}w</span>
            </div>
            <input
              type="range"
              min={2}
              max={Math.max(36, defaultNumWeeks + 8)}
              step={1}
              value={effectiveNumWeeks}
              onChange={(e) => setNumWeeks(parseInt(e.target.value))}
              className="w-full accent-primary"
            />
            <div className="flex justify-between text-[10px] text-muted-foreground">
              <span>2w</span>
              <span className="text-primary">{defaultNumWeeks}w (goal default)</span>
              <span>{Math.max(36, defaultNumWeeks + 8)}w</span>
            </div>
            {numWeeks !== null && numWeeks !== defaultNumWeeks && (
              <button
                onClick={() => setNumWeeks(null)}
                className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
              >
                Reset to {defaultNumWeeks}w
              </button>
            )}
          </div>
        )}
      </section>
    </div>
  )
}
