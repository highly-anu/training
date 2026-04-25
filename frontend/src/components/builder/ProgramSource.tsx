import { useState, useMemo } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { BookOpen, GitMerge, Sliders, ChevronRight } from 'lucide-react'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useBuilderStore } from '@/store/builderStore'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import type { Framework, ModalityId, Philosophy } from '@/api/types'
import type { SourceMode } from '@/store/builderStore'

// ─── Constants ────────────────────────────────────────────────────────────────

const MODALITY_ORDER: ModalityId[] = [
  'max_strength', 'relative_strength', 'strength_endurance', 'power',
  'aerobic_base', 'anaerobic_intervals', 'mixed_modal_conditioning',
  'durability', 'mobility', 'movement_skill', 'combat_sport', 'rehab',
]

const DEFAULT_PRIORITIES = Object.fromEntries(
  MODALITY_ORDER.map((id) => [id, 1 / MODALITY_ORDER.length])
) as Record<ModalityId, number>

const MODES: { id: SourceMode; label: string; sub: string; color: string; Icon: React.FC<{ className?: string }> }[] = [
  {
    id: 'philosophy',
    label: 'From a Philosophy',
    sub: 'One source methodology drives the program',
    color: '#8b5cf6',
    Icon: BookOpen,
  },
  {
    id: 'blend',
    label: 'Blend Philosophies',
    sub: 'Mix 2–4 systems with custom weights',
    color: '#6366f1',
    Icon: GitMerge,
  },
  {
    id: 'custom',
    label: 'Custom Priorities',
    sub: 'Set modality emphasis directly from scratch',
    color: '#10b981',
    Icon: Sliders,
  },
]

// ─── Priority derivation ──────────────────────────────────────────────────────

/**
 * Derive a normalized priority vector from a philosophy's primary framework.
 * Falls back to equal-weight bias modalities if no framework is found.
 */
function derivePhilosophyPriorities(
  phil: Philosophy,
  frameworks: Framework[]
): Record<ModalityId, number> {
  const philFrameworks = frameworks.filter((f) => f.source_philosophy === phil.id)
  const sessions = philFrameworks[0]?.sessions_per_week

  if (sessions && Object.keys(sessions).length > 0) {
    const total = Object.values(sessions).reduce((s, v) => s + (v ?? 0), 0)
    if (total > 0) {
      return Object.fromEntries(
        MODALITY_ORDER.map((id) => [id, (sessions[id as ModalityId] ?? 0) / total])
      ) as Record<ModalityId, number>
    }
  }

  // Fallback: equal weight across bias modalities
  const biasIds = (phil.bias ?? []).filter((b): b is ModalityId => b in MODALITY_COLORS)
  const n = biasIds.length || 1
  return Object.fromEntries(
    MODALITY_ORDER.map((id) => [id, biasIds.includes(id) ? 1 / n : 0])
  ) as Record<ModalityId, number>
}

/**
 * Weighted average of priorities across multiple philosophies.
 */
function deriveBlendedPriorities(
  philIds: string[],
  philWeights: Record<string, number>,
  philosophies: Philosophy[],
  frameworks: Framework[]
): Record<ModalityId, number> {
  const totalW = philIds.reduce((s, id) => s + (philWeights[id] ?? 50), 0)
  const blended = Object.fromEntries(MODALITY_ORDER.map((id) => [id, 0])) as Record<ModalityId, number>

  for (const philId of philIds) {
    const phil = philosophies.find((p) => p.id === philId)
    if (!phil) continue
    const w = (philWeights[philId] ?? 50) / totalW
    const priorities = derivePhilosophyPriorities(phil, frameworks)
    for (const id of MODALITY_ORDER) {
      blended[id] += priorities[id] * w
    }
  }

  const sum = Object.values(blended).reduce((s, v) => s + v, 0)
  if (sum === 0) return DEFAULT_PRIORITIES
  return Object.fromEntries(MODALITY_ORDER.map((id) => [id, blended[id] / sum])) as Record<ModalityId, number>
}

function normalizePriorities(raw: Record<ModalityId, number>): Record<ModalityId, number> {
  const total = Object.values(raw).reduce((s, v) => s + v, 0)
  if (total === 0) return raw
  return Object.fromEntries(Object.entries(raw).map(([k, v]) => [k, v / total])) as Record<ModalityId, number>
}

// ─── Philosophy card ──────────────────────────────────────────────────────────

function PhilCard({
  phil,
  isSelected,
  isDisabled,
  onClick,
}: {
  phil: Philosophy
  isSelected: boolean
  isDisabled: boolean
  onClick: () => void
}) {
  const hex = MODALITY_COLORS[phil.bias?.[0] as ModalityId]?.hex ?? '#6366f1'

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={isDisabled}
      className={cn(
        'flex items-start gap-2.5 rounded-lg border px-3 py-2.5 text-left',
        'transition-all group cursor-pointer',
        isDisabled && 'opacity-40 cursor-not-allowed',
        !isDisabled && !isSelected && 'border-border/30 bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20',
        isSelected && 'shadow-md',
      )}
      style={isSelected
        ? { borderColor: hex, borderWidth: 2, backgroundColor: `${hex}12` }
        : { borderLeftColor: hex, borderLeftWidth: 2 }
      }
    >
      <div className="min-w-0 flex-1">
        <p className={cn(
          'text-xs font-medium leading-snug truncate transition-colors',
          isSelected ? 'text-foreground' : 'group-hover:text-primary',
        )}>
          {phil.name}
        </p>
        <p className="text-[10px] text-muted-foreground/60 mt-0.5">
          {phil.bias?.length ?? 0} modalities · {phil.core_principles?.length ?? 0} principles
        </p>
      </div>
    </button>
  )
}

// ─── Weight allocation bar (Mode 2) ───────────────────────────────────────────

function PhilWeightBar({
  selectedIds,
  weights,
  philosophies,
  onChange,
}: {
  selectedIds: string[]
  weights: Record<string, number>
  philosophies: Philosophy[]
  onChange: (id: string, w: number) => void
}) {
  const total = selectedIds.reduce((s, id) => s + (weights[id] ?? 50), 0)

  return (
    <div className="space-y-3 pt-1">
      <div className="flex rounded overflow-hidden h-2 gap-px">
        {selectedIds.map((id) => {
          const phil = philosophies.find((p) => p.id === id)
          const hex = MODALITY_COLORS[(phil?.bias?.[0] ?? '') as ModalityId]?.hex ?? '#6366f1'
          const pct = ((weights[id] ?? 50) / total) * 100
          return (
            <div
              key={id}
              title={phil?.name ?? id}
              style={{ flex: pct, backgroundColor: hex, opacity: 0.75 }}
            />
          )
        })}
      </div>

      <div className="space-y-2.5">
        {selectedIds.map((id) => {
          const phil = philosophies.find((p) => p.id === id)
          const hex = MODALITY_COLORS[(phil?.bias?.[0] ?? '') as ModalityId]?.hex ?? '#6366f1'
          const pct = Math.round(((weights[id] ?? 50) / total) * 100)
          return (
            <div key={id} className="space-y-1">
              <div className="flex items-center justify-between text-xs">
                <div className="flex items-center gap-1.5 min-w-0">
                  <span className="size-2 rounded-full shrink-0" style={{ backgroundColor: hex }} />
                  <span className="truncate">{phil?.name ?? id}</span>
                </div>
                <span className="font-semibold ml-2 shrink-0 tabular-nums">{pct}%</span>
              </div>
              <input
                type="range" min={5} max={95} step={5}
                value={weights[id] ?? 50}
                onChange={(e) => onChange(id, parseInt(e.target.value))}
                style={{ accentColor: hex }}
                className="w-full"
              />
            </div>
          )
        })}
      </div>

      <p className="text-[10px] text-muted-foreground/50">
        Weights control how much each philosophy's modality distribution shapes the blended program.
      </p>
    </div>
  )
}

// ─── Modality priority sliders (Mode 3) ──────────────────────────────────────

function PriorityBuilder({
  priorities,
  onChange,
}: {
  priorities: Record<ModalityId, number>
  onChange: (p: Record<ModalityId, number>) => void
}) {
  function handleSlider(id: ModalityId, pct: number) {
    const newVal = pct / 100
    const others = MODALITY_ORDER.filter((k) => k !== id)
    const othersSum = others.reduce((s, k) => s + (priorities[k] ?? 0), 0)
    const budget = 1 - newVal

    const next = { ...priorities, [id]: newVal }
    if (othersSum === 0) {
      const even = budget / others.length
      for (const k of others) next[k] = even
    } else {
      const scale = budget / othersSum
      for (const k of others) next[k] = Math.max(0, (priorities[k] ?? 0) * scale)
    }
    onChange(normalizePriorities(next))
  }

  const nonZero = useMemo(
    () => MODALITY_ORDER.filter((id) => (priorities[id] ?? 0) > 0.005),
    [priorities]
  )

  return (
    <div className="space-y-4">
      <div>
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/40 font-medium mb-1.5">
          Modality distribution
        </p>
        <div className="flex rounded overflow-hidden h-2.5 gap-px">
          {nonZero.map((id) => (
            <div
              key={id}
              title={MODALITY_COLORS[id].label}
              style={{ flex: (priorities[id] ?? 0) * 100, backgroundColor: MODALITY_COLORS[id].hex, opacity: 0.8 }}
            />
          ))}
        </div>
        <div className="flex flex-wrap gap-x-3 gap-y-1 pt-2">
          {nonZero.filter((id) => (priorities[id] ?? 0) > 0.02).map((id) => (
            <div key={id} className="flex items-center gap-1">
              <div className="size-1.5 rounded-full" style={{ backgroundColor: MODALITY_COLORS[id].hex }} />
              <span className="text-[9px] text-muted-foreground/60">{MODALITY_COLORS[id].label}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="space-y-1.5">
        {MODALITY_ORDER.map((id) => {
          const pct = Math.round((priorities[id] ?? 0) * 100)
          const hex = MODALITY_COLORS[id].hex
          return (
            <div key={id} className="flex items-center gap-3">
              <div className="w-36 shrink-0 flex items-center gap-1.5">
                <span className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: hex }} />
                <span className="text-[10px] text-muted-foreground truncate">
                  {MODALITY_COLORS[id].label}
                </span>
              </div>
              <input
                type="range" min={0} max={100} step={1}
                value={pct}
                onChange={(e) => handleSlider(id, parseInt(e.target.value))}
                style={{ accentColor: hex }}
                className="flex-1"
              />
              <span className="text-[10px] font-mono w-7 text-right tabular-nums text-muted-foreground/70">
                {pct}%
              </span>
            </div>
          )
        })}
      </div>

      <p className="text-[10px] text-muted-foreground/50">
        Your priority distribution drives session selection and volume allocation directly.
      </p>
    </div>
  )
}

// ─── Main component ───────────────────────────────────────────────────────────

export function ProgramSource() {
  const [activeMode, setActiveMode] = useState<SourceMode | null>(null)
  const [selectedPhilIds, setSelectedPhilIds] = useState<string[]>([])
  const [philWeights, setPhilWeights] = useState<Record<string, number>>({})
  const [customPriorities, setCustomPriorities] = useState<Record<ModalityId, number>>(DEFAULT_PRIORITIES)

  const { data: philosophies = [], isLoading: philLoading } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()

  const {
    setSourceMode, setGoalIds, setGoalWeightsBulk, setPriorityOverrides,
    setFramework, setPhilosophyIds, setPhilosophyWeights, setSourcePriorities,
  } = useBuilderStore()

  function activateMode(mode: SourceMode) {
    const next = mode === activeMode ? null : mode
    setActiveMode(next)
    setSourceMode(next)
    setSelectedPhilIds([])
    setPhilWeights({})
    setPriorityOverrides(null)
    setSourcePriorities(null)
    setPhilosophyIds([])
    setFramework(null)

    // Custom mode has no selection step — seed goal + priorities immediately so Next is enabled
    if (next === 'custom') {
      setGoalIds(['general_gpp'])
      setPriorityOverrides(DEFAULT_PRIORITIES)
      setSourcePriorities(DEFAULT_PRIORITIES)
    } else {
      setGoalIds([])
      setGoalWeightsBulk({})
    }
  }

  // ── Mode 1: single philosophy ──
  function handleSelectPhilosophy(phil: Philosophy) {
    const isDeselect = selectedPhilIds[0] === phil.id
    if (isDeselect) {
      setSelectedPhilIds([])
      setGoalIds([])
      setGoalWeightsBulk({})
      setPriorityOverrides(null)
      setSourcePriorities(null)
      setPhilosophyIds([])
      setFramework(null)
      return
    }

    setSelectedPhilIds([phil.id])

    const priorities = derivePhilosophyPriorities(phil, frameworks)
    const primaryFramework = frameworks.find((f) => f.source_philosophy === phil.id)

    // Check if philosophy has sequential phases (Full Program mode)
    const hasSequentialPhases = phil.framework_groups?.some((g) => g.type === 'sequential')
      || (phil.canonical_phase_sequence && phil.canonical_phase_sequence.length > 0)

    setGoalIds(['general_gpp'])
    setGoalWeightsBulk({})
    setPriorityOverrides(priorities)
    setSourcePriorities(priorities)
    setPhilosophyIds([phil.id])
    // For philosophies with sequential phases, leave framework as null to enable Full Program mode
    setFramework(hasSequentialPhases ? null : (primaryFramework?.id ?? null))
  }

  // ── Mode 2: multi philosophy blend ──
  function handleTogglePhilosophy(phil: Philosophy) {
    const alreadySelected = selectedPhilIds.includes(phil.id)
    if (!alreadySelected && selectedPhilIds.length >= 4) return

    const nextIds = alreadySelected
      ? selectedPhilIds.filter((id) => id !== phil.id)
      : [...selectedPhilIds, phil.id]

    const nextWeights = alreadySelected
      ? philWeights
      : { ...philWeights, [phil.id]: philWeights[phil.id] ?? 50 }

    setSelectedPhilIds(nextIds)
    setPhilWeights(nextWeights)
    applyBlend(nextIds, nextWeights)
  }

  function handlePhilWeightChange(philId: string, w: number) {
    const next = { ...philWeights, [philId]: w }
    setPhilWeights(next)
    applyBlend(selectedPhilIds, next)
  }

  function applyBlend(philIds: string[], weights: Record<string, number>) {
    if (philIds.length === 0) {
      setGoalIds([])
      setGoalWeightsBulk({})
      setPriorityOverrides(null)
      setSourcePriorities(null)
      setPhilosophyIds([])
      setPhilosophyWeights({})
      setFramework(null)
      return
    }
    const priorities = deriveBlendedPriorities(philIds, weights, philosophies, frameworks)
    setGoalIds(['general_gpp'])
    setGoalWeightsBulk({})
    setPriorityOverrides(priorities)
    setSourcePriorities(priorities)
    setPhilosophyIds(philIds)
    setPhilosophyWeights(weights)
    setFramework(null)
  }

  // ── Mode 3: custom priorities ──
  function handlePriorityChange(p: Record<ModalityId, number>) {
    setCustomPriorities(p)
    setGoalIds(['general_gpp'])
    setGoalWeightsBulk({})
    setPriorityOverrides(p)
    setSourcePriorities(p)
    setPhilosophyIds([])
    setFramework(null)
  }

  // Priority preview for the selected philosophy (Mode 1)
  const mode1Preview = useMemo(() => {
    if (activeMode !== 'philosophy' || selectedPhilIds.length === 0) return null
    const phil = philosophies.find((p) => p.id === selectedPhilIds[0])
    if (!phil) return null
    const priorities = derivePhilosophyPriorities(phil, frameworks)
    return MODALITY_ORDER
      .filter((id) => priorities[id] > 0.02)
      .sort((a, b) => priorities[b] - priorities[a])
      .slice(0, 5)
      .map((id) => ({ id, pct: Math.round(priorities[id] * 100) }))
  }, [activeMode, selectedPhilIds, philosophies, frameworks])

  const isLoading = philLoading

  return (
    <div className="max-w-3xl mx-auto px-8 py-10 space-y-8">
      {/* Header */}
      <div className="space-y-3">
        <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
          Training ontology
        </p>
        <h2 className="text-2xl font-semibold leading-snug">
          How do you want to program?
        </h2>
        <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
          From a single source methodology, a blend of philosophies, or built from first principles.
        </p>
      </div>

      {/* Mode cards */}
      <div className="grid grid-cols-3 gap-3">
        {MODES.map(({ id, label, sub, color, Icon }) => {
          const isActive = activeMode === id
          return (
            <button
              key={id}
              type="button"
              onClick={() => activateMode(id)}
              className={cn(
                'text-left rounded-xl border px-4 py-4 transition-all cursor-pointer group',
                !isActive && 'bg-card/40 hover:border-primary/40 hover:shadow-md hover:-translate-y-px hover:bg-muted/20',
              )}
              style={isActive
                ? { borderColor: color, borderWidth: 2, backgroundColor: `${color}12` }
                : { borderLeftColor: color, borderLeftWidth: 3 }
              }
            >
              <div className="flex items-start justify-between gap-2">
                <Icon className={cn('size-4 shrink-0 mt-0.5', isActive ? '' : 'text-muted-foreground')} />
                <ChevronRight
                  className={cn(
                    'size-3 shrink-0 mt-1 transition-transform',
                    isActive ? 'rotate-90' : 'text-muted-foreground/30 group-hover:text-muted-foreground/60',
                  )}
                />
              </div>
              <p className={cn(
                'text-xs font-semibold mt-2 leading-snug transition-colors',
                isActive ? 'text-foreground' : 'group-hover:text-primary',
              )}>
                {label}
              </p>
              <p className="text-[10px] text-muted-foreground/60 mt-1 leading-snug">{sub}</p>
            </button>
          )
        })}
      </div>

      {/* Inline configuration panel */}
      <AnimatePresence mode="wait">
        {activeMode && (
          <motion.div
            key={activeMode}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0, transition: { duration: 0.22, ease: [0.25, 0.1, 0.25, 1] } }}
            exit={{ opacity: 0, y: -4, transition: { duration: 0.15 } }}
            className="rounded-xl border border-border/50 bg-card/30 p-5 space-y-4"
          >
            {/* ── Mode 1: single philosophy ── */}
            {activeMode === 'philosophy' && (
              <>
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
                  Select a philosophy
                </p>
                {isLoading ? (
                  <div className="grid grid-cols-2 gap-2">
                    {Array.from({ length: 6 }).map((_, i) => (
                      <div key={i} className="h-12 rounded-lg bg-muted/20 animate-pulse" />
                    ))}
                  </div>
                ) : (
                  <div className="grid grid-cols-2 gap-2">
                    {philosophies.map((phil) => (
                      <PhilCard
                        key={phil.id}
                        phil={phil}
                        isSelected={selectedPhilIds[0] === phil.id}
                        isDisabled={false}
                        onClick={() => handleSelectPhilosophy(phil)}
                      />
                    ))}
                  </div>
                )}

                {mode1Preview && (
                  <div className="pt-2 border-t border-border/20 space-y-1.5">
                    <p className="text-[10px] uppercase tracking-widest text-muted-foreground/40 font-medium">
                      Modality emphasis
                    </p>
                    <div className="flex flex-wrap gap-1.5">
                      {mode1Preview.map(({ id, pct }) => (
                        <span
                          key={id}
                          className="text-[10px] font-mono px-2 py-0.5 rounded-full"
                          style={{
                            backgroundColor: `${MODALITY_COLORS[id].hex}20`,
                            color: MODALITY_COLORS[id].hex,
                            border: `1px solid ${MODALITY_COLORS[id].hex}40`,
                          }}
                        >
                          {MODALITY_COLORS[id].label} {pct}%
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </>
            )}

            {/* ── Mode 2: blend ── */}
            {activeMode === 'blend' && (
              <>
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
                  Select up to 4 philosophies
                </p>
                {isLoading ? (
                  <div className="grid grid-cols-2 gap-2">
                    {Array.from({ length: 6 }).map((_, i) => (
                      <div key={i} className="h-12 rounded-lg bg-muted/20 animate-pulse" />
                    ))}
                  </div>
                ) : (
                  <div className="grid grid-cols-2 gap-2">
                    {philosophies.map((phil) => (
                      <PhilCard
                        key={phil.id}
                        phil={phil}
                        isSelected={selectedPhilIds.includes(phil.id)}
                        isDisabled={!selectedPhilIds.includes(phil.id) && selectedPhilIds.length >= 4}
                        onClick={() => handleTogglePhilosophy(phil)}
                      />
                    ))}
                  </div>
                )}

                {selectedPhilIds.length >= 2 && (
                  <div className="pt-3 border-t border-border/20">
                    <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium mb-3">
                      Blend weights
                    </p>
                    <PhilWeightBar
                      selectedIds={selectedPhilIds}
                      weights={philWeights}
                      philosophies={philosophies}
                      onChange={handlePhilWeightChange}
                    />
                  </div>
                )}

                {selectedPhilIds.length === 1 && (
                  <p className="text-[10px] text-muted-foreground/50 pt-1">
                    Select at least one more philosophy to configure blend weights.
                  </p>
                )}
              </>
            )}

            {/* ── Mode 3: custom ── */}
            {activeMode === 'custom' && (
              <div>
                <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium mb-4">
                  Modality priorities
                </p>
                <PriorityBuilder
                  priorities={customPriorities}
                  onChange={handlePriorityChange}
                />
              </div>
            )}
          </motion.div>
        )}
      </AnimatePresence>

      <p className="text-[10px] text-muted-foreground/30 text-center pb-2">
        Select a source to configure your program — then continue to constraints.
      </p>
    </div>
  )
}
