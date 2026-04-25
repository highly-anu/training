import { useEffect, useMemo, useRef, useState } from 'react'
import { Check, Info, Layers } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useBuilderStore } from '@/store/builderStore'
// Goals removed - now philosophy-based only
import { useFrameworks } from '@/api/frameworks'
import { usePhilosophies } from '@/api/philosophies'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { sortPriorities } from '@/lib/prioritySort'
import { frameworkImpliedPriorities } from '@/lib/frameworkPriorities'
import { FrameworkDetailModal } from './FrameworkDetailModal'
import type { Framework, ModalityId } from '@/api/types'

const SECTION_LABEL = 'text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium'

export function ProgramTuner() {
  const {
    selectedGoalIds,
    selectedFrameworkId,
    selectedPhilosophyIds,
    sourcePriorities,
    sourceMode,
    priorityOverrides,
    numWeeks,
    eventDate,
    setFramework,
    setPriorityOverrides,
    setNumWeeks,
    setEventDate,
  } = useBuilderStore()

  const { data: frameworks } = useFrameworks()
  const { data: philosophies } = usePhilosophies()
  const [detailFramework, setDetailFramework] = useState<Framework | null>(null)

  // Get active philosophy and its framework groups
  const activePhilosophy = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
  const frameworkGroups = activePhilosophy?.framework_groups ?? []

  // ── Blended priorities ─────────────────────────────────────────────────────
  // Use the priorities that ProgramSource computed (philosophy-based)
  const blendedPriorities = useMemo(() => {
    return sourcePriorities ?? {}
  }, [sourcePriorities])

  // Default priority sliders to goal/source priorities on first mount
  useEffect(() => {
    if (!priorityOverrides) {
      setPriorityOverrides({ ...blendedPriorities })
    }
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // ── Framework options ──────────────────────────────────────────────────────
  const relevantFrameworks = useMemo(() => {
    if (!frameworks) return []
    if (sourceMode === 'philosophy') {
      return frameworks.filter((f) => f.source_philosophy === selectedPhilosophyIds[0])
    }
    if (sourceMode === 'blend') {
      return frameworks.filter((f) =>
        selectedPhilosophyIds.includes(f.source_philosophy ?? '')
      )
    }
    if (sourceMode === 'custom') {
      // No philosophy-specific frameworks; show all
      return frameworks
    }
    // No source mode selected - show no frameworks
    return []
  }, [frameworks, sourceMode, selectedPhilosophyIds])

  // Default framework for this source mode
  const defaultFrameworkId = useMemo(() => {
    if (sourceMode === 'philosophy') {
      return frameworks?.find((f) => f.source_philosophy === selectedPhilosophyIds[0])?.id ?? null
    }
    return null
  }, [frameworks, sourceMode, selectedPhilosophyIds])

  // When the user picks a different framework, suggest its implied priorities.
  const isMounted = useRef(false)
  const prevFwId = useRef(selectedFrameworkId)
  useEffect(() => {
    if (!isMounted.current) { isMounted.current = true; return }
    if (selectedFrameworkId === prevFwId.current) return
    prevFwId.current = selectedFrameworkId

    if (selectedFrameworkId === null) {
      setPriorityOverrides({ ...blendedPriorities })
    } else {
      const fw = frameworks?.find((f) => f.id === selectedFrameworkId)
      if (fw) {
        setPriorityOverrides(frameworkImpliedPriorities(fw, blendedPriorities))
      }
    }
  }, [selectedFrameworkId, frameworks, blendedPriorities]) // eslint-disable-line react-hooks/exhaustive-deps

  // The active framework object
  const activeFw = frameworks?.find(
    (f) => f.id === (selectedFrameworkId ?? defaultFrameworkId),
  ) ?? null

  // Detect if "Full Program (All Phases)" is selected
  // Full program mode means: no specific framework selected + philosophy has sequential phases
  const isFullProgram = useMemo(() => {
    if (selectedFrameworkId !== null) return false
    if (sourceMode !== 'philosophy') return false

    const phil = philosophies?.find((p) => p.id === selectedPhilosophyIds[0])
    if (!phil) return false

    // Check if philosophy has sequential framework groups or canonical_phase_sequence
    const hasSequential = phil.framework_groups?.some((g) => g.type === 'sequential')
    const hasCanonical = phil.canonical_phase_sequence && phil.canonical_phase_sequence.length > 0

    return hasSequential || hasCanonical
  }, [selectedFrameworkId, sourceMode, selectedPhilosophyIds, philosophies])

  // Get expectations to display (philosophy-level for full program, framework-level otherwise)
  const displayExpectations = useMemo(() => {
    if (isFullProgram && activePhilosophy?.expectations) {
      return activePhilosophy.expectations
    }
    return activeFw?.expectations ?? null
  }, [isFullProgram, activePhilosophy, activeFw])

  // Framework-implied defaults for the reset button
  const fwDefaultPriorities = useMemo(() => {
    if (!activeFw?.sessions_per_week) return null
    return frameworkImpliedPriorities(activeFw, blendedPriorities)
  }, [activeFw, blendedPriorities])

  const activePriorities = priorityOverrides ?? blendedPriorities
  const sortedPriorities = sortPriorities(activePriorities)
  const totalRaw = Object.values(activePriorities).reduce((s, v) => s + (v ?? 0), 0) || 1

  function updatePriority(mod: ModalityId, rawValue: number) {
    setPriorityOverrides({ ...activePriorities, [mod]: rawValue })
  }

  // ── Duration + event date ──────────────────────────────────────────────────
  const defaultNumWeeks = useMemo(() => {
    // If full program is selected, use total from phases
    if (isFullProgram && activePhilosophy) {
      const phaseSeq = activePhilosophy.framework_groups?.find((g) => g.type === 'sequential')?.canonical_phase_sequence
                       ?? activePhilosophy.canonical_phase_sequence
      if (phaseSeq) {
        return phaseSeq.reduce((sum, p) => sum + (p.weeks ?? 0), 0)
      }
    }
    // Otherwise use expectations or fallback to 12
    return displayExpectations?.ideal_weeks ?? 12
  }, [isFullProgram, activePhilosophy, displayExpectations])

  const effectiveNumWeeks = numWeeks ?? defaultNumWeeks

  const weeksUntilEvent = useMemo(() => {
    if (!eventDate) return null
    const today = new Date()
    const event = new Date(eventDate)
    return Math.max(1, Math.round((event.getTime() - today.getTime()) / (7 * 24 * 60 * 60 * 1000)))
  }, [eventDate])

  const eventIsTight = weeksUntilEvent !== null && weeksUntilEvent < defaultNumWeeks

  // "Tight" state: which option did the user choose
  type TightChoice = 'fit' | 'full'
  const [tightChoice, setTightChoice] = useState<TightChoice>('fit')

  // Propagate tight choice to numWeeks
  useEffect(() => {
    if (!eventIsTight) return
    if (tightChoice === 'fit') {
      setNumWeeks(weeksUntilEvent!)
    } else {
      setNumWeeks(defaultNumWeeks)
    }
  }, [tightChoice, eventIsTight, weeksUntilEvent, defaultNumWeeks]) // eslint-disable-line react-hooks/exhaustive-deps

  // Reset tight choice when event date is removed
  useEffect(() => {
    if (!eventDate) setTightChoice('fit')
  }, [eventDate])

  // Reset label
  const resetLabel = 'Source default'

  return (
    <div className="space-y-8 max-w-3xl mx-auto px-8">

      {/* Header */}
      <div className="space-y-3">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
          Program configuration
        </p>
        <h2 className="text-2xl font-semibold leading-snug">
          Tune your program.
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          Select framework, adjust modality priorities, and set program duration.
        </p>
      </div>

      {/* Program recommendations */}
      {displayExpectations && (
        <div className="rounded-xl border border-primary/20 bg-primary/5 p-4">
          <p className="text-[10px] uppercase tracking-widest text-primary/70 font-medium mb-2">
            {isFullProgram ? 'Full program recommendations' : 'Framework recommendations'}
          </p>
          <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-xs">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Ideal duration</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_weeks ?? 12} weeks
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Training days</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_days_per_week} days/week
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Session length</span>
              <span className="font-semibold text-foreground">
                {displayExpectations.ideal_session_minutes} min
              </span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted-foreground">Weekly workload</span>
              <span className="font-semibold text-foreground">
                {(displayExpectations.ideal_days_per_week * displayExpectations.ideal_session_minutes)} min/week
              </span>
            </div>
          </div>
        </div>
      )}

      {/* ── Framework selection ── */}
      <section className="space-y-3">
        <div>
          <p className={SECTION_LABEL}>Periodization</p>
          <h2 className="text-sm font-semibold text-foreground mt-0.5">Programming Framework</h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            {frameworkGroups.length > 1
              ? 'This philosophy offers multiple training approaches — choose one below.'
              : 'Controls how sessions are structured and periodized each week.'}
          </p>
        </div>

        {frameworkGroups.length > 0 ? (
          <div className="space-y-4">
            {frameworkGroups.map((group) => {
              const groupFrameworks = relevantFrameworks.filter((f) =>
                group.frameworks.includes(f.id)
              )

              return (
                <div key={group.id} className="space-y-2">
                  <p className="text-xs font-medium text-foreground">{group.name}</p>

                  {group.type === 'sequential' ? (
                    // Sequential group: Show "Full Program" button
                    <button
                      onClick={() => {
                        setFramework(null)
                        // Reset numWeeks to null so effectiveNumWeeks = defaultNumWeeks
                        // (the full phase total). Don't pass the hardcoded total here —
                        // the tightChoice effect owns numWeeks when event date is set.
                        if (!eventDate) setNumWeeks(null)
                      }}
                      className={cn(
                        'w-full rounded-xl border p-4 text-left transition-all',
                        'bg-card hover:shadow-md',
                        selectedFrameworkId === null
                          ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                          : 'border-border hover:border-primary/50'
                      )}
                    >
                      <div className="flex items-start gap-3">
                        {selectedFrameworkId === null && (
                          <span className="flex size-5 items-center justify-center rounded-full bg-primary shrink-0 mt-0.5">
                            <Check className="size-3 text-primary-foreground" />
                          </span>
                        )}
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-semibold text-foreground">Full Program (All Phases)</p>
                          <p className="text-[10px] text-muted-foreground mt-1 leading-relaxed">
                            Includes all sequential phases: {group.canonical_phase_sequence?.map((p) => p.phase).join(' → ')}
                          </p>
                          <div className="flex flex-wrap gap-2 mt-2">
                            {group.canonical_phase_sequence?.map((phase) => (
                              <span key={phase.phase} className="text-[9px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
                                {phase.phase}: {phase.weeks}w
                              </span>
                            ))}
                          </div>
                        </div>
                      </div>
                    </button>
                  ) : (
                    // Alternatives group: Show framework picker
                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                      {groupFrameworks.map((fw) => {
                        const isDefault = fw.id === (defaultFrameworkId)
                        const isSelected = selectedFrameworkId === fw.id

                        return (
                          <div
                            key={fw.id}
                            className={cn(
                              'relative flex flex-col gap-1.5 rounded-xl border p-4 transition-shadow',
                              'bg-card hover:shadow-md',
                              isSelected
                                ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                                : 'border-border hover:border-primary/50'
                            )}
                          >
                            {isSelected && (
                              <span className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-primary">
                                <Check className="size-3 text-primary-foreground" />
                              </span>
                            )}

                            <button
                              onClick={() => setFramework(isSelected ? null : fw.id)}
                              className="flex items-start gap-2 pr-6 text-left"
                            >
                              <Layers className="size-3.5 mt-0.5 shrink-0 text-muted-foreground" />
                              <div>
                                <p className="text-xs font-semibold text-foreground">{fw.name}</p>
                                {isDefault && (
                                  <span className="text-[9px] text-primary font-medium">
                                    Primary for this philosophy
                                  </span>
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
                  )}
                </div>
              )
            })}
          </div>
        ) : relevantFrameworks.length === 0 ? (
          <div className="rounded-xl border border-border/50 bg-muted/20 px-4 py-3 text-xs text-muted-foreground">
            No framework filter applied — framework will be auto-selected based on your constraints.
          </div>
        ) : activePhilosophy?.canonical_phase_sequence ? (
          // Legacy fallback: Philosophy has canonical_phase_sequence but no framework_groups
          <div className="space-y-3">
            <button
              onClick={() => {
                setFramework(null)
                if (!eventDate) setNumWeeks(null)
              }}
              className={cn(
                'w-full rounded-xl border p-4 text-left transition-all',
                'bg-card hover:shadow-md',
                selectedFrameworkId === null
                  ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                  : 'border-border hover:border-primary/50'
              )}
            >
              <div className="flex items-start gap-3">
                {selectedFrameworkId === null && (
                  <span className="flex size-5 items-center justify-center rounded-full bg-primary shrink-0 mt-0.5">
                    <Check className="size-3 text-primary-foreground" />
                  </span>
                )}
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-semibold text-foreground">Full Program (All Phases)</p>
                  <p className="text-[10px] text-muted-foreground mt-1 leading-relaxed">
                    Includes all sequential phases: {activePhilosophy.canonical_phase_sequence.map((p) => p.phase).join(' → ')}
                  </p>
                  <div className="flex flex-wrap gap-2 mt-2">
                    {activePhilosophy.canonical_phase_sequence.map((phase) => (
                      <span key={phase.phase} className="text-[9px] px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
                        {phase.phase}: {phase.weeks}w
                      </span>
                    ))}
                  </div>
                </div>
              </div>
            </button>

            <details className="group">
              <summary className="text-[10px] text-muted-foreground cursor-pointer hover:text-foreground transition-colors">
                Advanced: Override with single phase
              </summary>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 mt-3">
                {relevantFrameworks.map((fw) => {
                  const isSelected = selectedFrameworkId === fw.id
                  return (
                    <button
                      key={fw.id}
                      onClick={() => setFramework(isSelected ? null : fw.id)}
                      className={cn(
                        'relative flex flex-col gap-1.5 rounded-xl border p-3 transition-shadow text-left',
                        'bg-card hover:shadow-md',
                        isSelected
                          ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                          : 'border-border hover:border-primary/50'
                      )}
                    >
                      {isSelected && (
                        <span className="absolute right-2 top-2 flex size-4 items-center justify-center rounded-full bg-primary">
                          <Check className="size-2.5 text-primary-foreground" />
                        </span>
                      )}
                      <p className="text-xs font-medium pr-6">{fw.name}</p>
                      <p className="text-[9px] text-muted-foreground">{fw.notes?.slice(0, 80)}...</p>
                    </button>
                  )
                })}
              </div>
            </details>
          </div>
        ) : (
          // Standard framework picker for philosophies without groups or phases
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {relevantFrameworks.map((fw) => {
              const isDefault = fw.id === (defaultFrameworkId)
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

                  <button
                    onClick={() => setFramework(isSelected ? null : fw.id)}
                    className="flex items-start gap-2 pr-6 text-left"
                  >
                    <Layers className="size-3.5 mt-0.5 shrink-0 text-muted-foreground" />
                    <div>
                      <p className="text-xs font-semibold text-foreground">{fw.name}</p>
                      {isDefault && (
                        <span className="text-[9px] text-primary font-medium">
                          {sourceMode === 'philosophy' ? 'Primary for this philosophy' : 'Default for this goal'}
                        </span>
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
        )}

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
        <div className="flex items-baseline justify-between gap-4">
          <div>
            <p className={SECTION_LABEL}>Emphasis</p>
            <h2 className="text-sm font-semibold text-foreground mt-0.5">Training Priorities</h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              {sourceMode === 'blend'
                ? 'Blended from your philosophy mix. Adjust to fine-tune.'
                : sourceMode === 'philosophy'
                ? 'Derived from this philosophy\'s framework. Adjust to fine-tune.'
                : sourceMode === 'custom'
                ? 'Set by you. Adjust sliders to update.'
                : selectedGoalIds.length > 1
                ? 'Blended from your goal mix. Adjust to further fine-tune.'
                : 'Override the default emphasis for each domain.'}
            </p>
          </div>
          <div className="flex items-center gap-3 shrink-0">
            {fwDefaultPriorities && (
              <button
                onClick={() => setPriorityOverrides(fwDefaultPriorities)}
                className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
              >
                Framework default
              </button>
            )}
            <button
              onClick={() => {
                const base = sourcePriorities ?? blendedPriorities
                setPriorityOverrides({ ...base })
              }}
              className="text-[10px] text-muted-foreground hover:text-foreground underline underline-offset-2"
            >
              {resetLabel}
            </button>
          </div>
        </div>

        <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-3">
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
          <p className={SECTION_LABEL}>Timeline</p>
          <h2 className="text-sm font-semibold text-foreground mt-0.5">Program Duration</h2>
        </div>

        {/* Event date — always shown first so the context is set before duration decisions */}
        <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-3">
          <div>
            <p className="text-xs font-medium text-foreground">
              Target event <span className="text-muted-foreground font-normal">(optional)</span>
            </p>
            <p className="text-[10px] text-muted-foreground mt-0.5">
              Set a date to auto-compute phase lengths and program fit.
            </p>
          </div>
          <div className="flex flex-wrap gap-1.5">
            {[
              { label: '4 wks',  weeks: 4  },
              { label: '8 wks',  weeks: 8  },
              { label: '12 wks', weeks: 12 },
              { label: '16 wks', weeks: 16 },
              { label: '6 mo',   weeks: 26 },
              { label: '1 yr',   weeks: 52 },
            ].map(({ label, weeks }) => {
              const d = new Date()
              d.setDate(d.getDate() + weeks * 7)
              const iso = d.toISOString().split('T')[0]
              const active = eventDate === iso
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => setEventDate(active ? null : iso)}
                  className={cn(
                    'rounded-md border px-2.5 py-1 text-xs transition-colors',
                    active
                      ? 'border-primary bg-primary/10 text-primary font-medium'
                      : 'border-border text-muted-foreground hover:border-primary/50 hover:text-foreground'
                  )}
                >
                  {label}
                </button>
              )
            })}
          </div>
          <input
            type="date"
            className="flex h-9 w-full max-w-xs rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            value={eventDate ?? ''}
            min={new Date().toISOString().split('T')[0]}
            onChange={(e) => setEventDate(e.target.value || null)}
          />
        </div>

        {eventDate && eventIsTight ? (
          <>
            <div className="rounded-xl border border-amber-500/30 bg-amber-500/5 px-4 py-3 text-xs text-amber-600 dark:text-amber-400">
              Your event is in <span className="font-semibold">{weeksUntilEvent}w</span>, but a full program is{' '}
              <span className="font-semibold">{defaultNumWeeks}w</span>. Choose how to handle this:
            </div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <button
                onClick={() => setTightChoice('fit')}
                className={cn(
                  'text-left rounded-xl border p-4 transition-all',
                  tightChoice === 'fit'
                    ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                    : 'border-border bg-card hover:border-primary/40 hover:shadow-md'
                )}
              >
                <div className="flex items-center justify-between mb-1">
                  <p className="text-xs font-semibold text-foreground">
                    Fit to event — {weeksUntilEvent}w
                  </p>
                  {tightChoice === 'fit' && (
                    <span className="flex size-4 items-center justify-center rounded-full bg-primary">
                      <Check className="size-2.5 text-primary-foreground" />
                    </span>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Compress the program phases into {weeksUntilEvent} weeks. Peaks closest to your event date.
                </p>
              </button>

              <button
                onClick={() => setTightChoice('full')}
                className={cn(
                  'text-left rounded-xl border p-4 transition-all',
                  tightChoice === 'full'
                    ? 'border-primary ring-2 ring-primary/20 bg-primary/5'
                    : 'border-border bg-card hover:border-primary/40 hover:shadow-md'
                )}
              >
                <div className="flex items-center justify-between mb-1">
                  <p className="text-xs font-semibold text-foreground">
                    Full periodization — {defaultNumWeeks}w
                  </p>
                  {tightChoice === 'full' && (
                    <span className="flex size-4 items-center justify-center rounded-full bg-primary">
                      <Check className="size-2.5 text-primary-foreground" />
                    </span>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Run the complete program. The event falls within the program — use it as a mid-cycle check.
                </p>
              </button>
            </div>
          </>
        ) : eventDate && !eventIsTight ? (
          <div className="rounded-xl border border-border/50 bg-card/30 px-4 py-3 text-xs text-muted-foreground">
            Event in <span className="font-semibold text-foreground">{weeksUntilEvent}w</span> — the full{' '}
            {defaultNumWeeks}w program fits comfortably before your event date.{' '}
            <span className="text-muted-foreground">Duration locked to <span className="font-medium text-foreground">{defaultNumWeeks}w</span>.</span>
          </div>
        ) : (
          <div className="rounded-xl border border-border/50 bg-card/30 p-4 space-y-2">
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
              <span className="text-primary">{defaultNumWeeks}w (default)</span>
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
