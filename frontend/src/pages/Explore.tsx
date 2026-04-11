import { useState, useMemo } from 'react'
import { motion } from 'framer-motion'
import { BookOpen, Compass, Dumbbell, Search, X, Zap } from 'lucide-react'
import { LoadingCard } from '@/components/shared/LoadingCard'
import { ErrorBanner } from '@/components/shared/ErrorBanner'
import { ModalityBadge } from '@/components/shared/ModalityBadge'
import { PrereqChain } from '@/components/exercises/PrereqChain'
import { usePhilosophies } from '@/api/philosophies'
import { useFrameworks } from '@/api/frameworks'
import { useModalities } from '@/api/modalities'
import { useArchetypes } from '@/api/archetypes'
import { useExercises } from '@/api/exercises'
import { useDebounce } from '@/hooks/useDebounce'
import { MODALITY_COLORS } from '@/lib/modalityColors'
import { cn } from '@/lib/utils'
import { PhilosophyExplorerPanel } from '@/components/devlab/PhilosophyExplorerPanel'
import { HeatmapPanel } from '@/components/devlab/heatmap/HeatmapPanel'
import type { Philosophy, Modality, Archetype, ModalityId, Exercise } from '@/api/types'

// ─── Intensity zone definitions (HR % thresholds) ────────────────────────────

const HR_ZONES = [
  { id: 'z1', label: 'Z1', min: 55, max: 65 },
  { id: 'z2', label: 'Z2', min: 65, max: 75 },
  { id: 'z3', label: 'Z3', min: 75, max: 85 },
  { id: 'z4', label: 'Z4', min: 85, max: 92 },
  { id: 'z5', label: 'Z5', min: 92, max: 100 },
]

// ─── Helpers ─────────────────────────────────────────────────────────────────

function prettify(id: string) {
  return id.split('_').map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
}

function BiasChip({ id }: { id: string }) {
  const color = MODALITY_COLORS[id as ModalityId]
  return (
    <span className={cn(
      'inline-block px-1.5 py-0.5 rounded text-[10px] font-medium',
      color ? `${color.bg} ${color.text}` : 'bg-muted/50 text-muted-foreground'
    )}>
      {color?.label ?? prettify(id)}
    </span>
  )
}

function RecoveryCostBadge({ cost }: { cost: 'low' | 'medium' | 'high' }) {
  const styles = {
    low: 'bg-emerald-500/15 text-emerald-400',
    medium: 'bg-amber-500/15 text-amber-400',
    high: 'bg-red-500/15 text-red-400',
  }
  return (
    <span className={cn('inline-block px-1.5 py-0.5 rounded text-[10px] font-medium', styles[cost])}>
      {cost} recovery
    </span>
  )
}

// ─── Topic Selector ───────────────────────────────────────────────────────────

type Topic = 'philosophies' | 'modalities' | 'exercises'

interface TopicTab {
  id: Topic
  label: string
  Icon: React.ElementType
}

const TOPICS: TopicTab[] = [
  { id: 'philosophies', label: 'Philosophies', Icon: BookOpen },
  { id: 'modalities',   label: 'Modalities',   Icon: Zap },
  { id: 'exercises',    label: 'Exercises',     Icon: Dumbbell },
]

function TopicSelector({
  active,
  onChange,
}: {
  active: Topic
  onChange: (t: Topic) => void
}) {
  return (
    <div className="flex shrink-0 px-2 pt-2">
      {TOPICS.map((tab, i) => {
        const isActive = tab.id === active
        return (
          <button
            key={tab.id}
            type="button"
            onClick={() => onChange(tab.id)}
            className={cn(
              'flex items-center gap-1.5 px-3 py-1.5 text-[11px] font-medium rounded-t-md border border-b-0',
              'transition-colors focus-visible:outline-none',
              isActive
                ? 'bg-card text-foreground border-border/60 z-10 shadow-sm'
                : 'bg-muted/30 text-muted-foreground border-border/30 hover:text-foreground hover:bg-muted/50',
            )}
            style={{ marginLeft: i === 0 ? 0 : -1, position: 'relative', zIndex: isActive ? 10 : 1 }}
          >
            <tab.Icon className="size-3 shrink-0" />
            {tab.label}
          </button>
        )
      })}
      {/* Bottom border line that sits under inactive tabs */}
      <div className="flex-1 border-b border-border/60" />
    </div>
  )
}

// ─── Philosophy card ──────────────────────────────────────────────────────────

function PhilCard({
  phil,
  isSelected,
  onSelect,
}: {
  phil: Philosophy
  isSelected: boolean
  onSelect: (p: Philosophy | null) => void
}) {
  const accentColor = MODALITY_COLORS[phil.bias[0] as ModalityId]?.hex ?? '#6366f1'

  return (
    <button
      type="button"
      onClick={() => onSelect(isSelected ? null : phil)}
      className={cn(
        'w-full text-left rounded-xl border bg-card transition-colors',
        !isSelected && 'hover:border-primary/40',
        'px-3 py-2.5 space-y-1',
      )}
      style={isSelected
        ? { borderColor: accentColor, borderLeftWidth: 3, borderWidth: 2, backgroundColor: `${accentColor}12` }
        : { borderLeftColor: accentColor, borderLeftWidth: 3 }
      }
    >
      <p className="text-xs font-semibold leading-snug">{phil.name}</p>
      <div className="flex flex-wrap gap-1 mt-1">
        {phil.bias.slice(0, 3).map((b) => <BiasChip key={b} id={b} />)}
      </div>
    </button>
  )
}

// ─── Modality card (in left list) ────────────────────────────────────────────

function ModalityCard({
  mod,
  isSelected,
  onSelect,
}: {
  mod: Modality
  isSelected: boolean
  onSelect: (m: Modality | null) => void
}) {
  const color = MODALITY_COLORS[mod.id]
  const accentHex = color?.hex ?? '#6366f1'

  return (
    <button
      type="button"
      onClick={() => onSelect(isSelected ? null : mod)}
      className={cn(
        'w-full text-left rounded-xl border bg-card transition-colors',
        !isSelected && 'hover:border-primary/40',
        'px-3 py-2.5 space-y-1',
      )}
      style={isSelected
        ? { borderColor: accentHex, borderLeftWidth: 3, borderWidth: 2, backgroundColor: `${accentHex}12` }
        : { borderLeftColor: accentHex, borderLeftWidth: 3 }
      }
    >
      <p className="text-xs font-semibold leading-snug">{mod.name}</p>
      <div className="flex items-center gap-1.5 mt-1">
        <RecoveryCostBadge cost={mod.recovery_cost} />
      </div>
    </button>
  )
}

// ─── Philosophy overview (nothing selected) ───────────────────────────────────

function PhilosophyOverview({ philosophies, frameworks }: {
  philosophies: Philosophy[]
  frameworks: { source_philosophy?: string; sessions_per_week?: Record<string, number> }[]
}) {
  const modalityStats = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const fw of frameworks) {
      for (const [mod, n] of Object.entries(fw.sessions_per_week ?? {})) {
        counts[mod] = (counts[mod] ?? 0) + (n as number)
      }
    }
    const max = Math.max(...Object.values(counts), 1)
    return (Object.keys(MODALITY_COLORS) as ModalityId[])
      .map(id => ({ id, pct: Math.round(((counts[id] ?? 0) / max) * 100) }))
      .sort((a, b) => b.pct - a.pct)
  }, [frameworks])

  const philSummaries = useMemo(() =>
    philosophies.map(p => ({
      p,
      fwCount: frameworks.filter(fw => fw.source_philosophy === p.id).length,
      color: MODALITY_COLORS[p.bias[0] as ModalityId]?.hex ?? '#6366f1',
    })),
    [philosophies, frameworks]
  )

  const uniqueModalities = modalityStats.filter(m => m.pct > 0).length

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-10">

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {philosophies.length} source philosophies.<br />
            <span className="text-muted-foreground font-normal">
              {uniqueModalities} modalities. One system.
            </span>
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Each philosophy encodes a distinct theory of adaptation — how to stress, recover, and progress.
            Select one to explore its frameworks, modality profile, archetypes, and exercise vocabulary.
          </p>
        </div>

        <div className="space-y-2">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/40 font-medium">
            Modality coverage across all philosophies
          </p>
          <div className="flex rounded-lg overflow-hidden h-3 gap-px">
            {modalityStats.filter(m => m.pct > 0).map(m => (
              <div
                key={m.id}
                title={MODALITY_COLORS[m.id].label}
                style={{ flex: m.pct, backgroundColor: MODALITY_COLORS[m.id].hex, opacity: 0.75 }}
              />
            ))}
          </div>
          <div className="flex flex-wrap gap-x-3 gap-y-1 pt-1">
            {modalityStats.filter(m => m.pct > 0).map(m => (
              <div key={m.id} className="flex items-center gap-1">
                <div className="size-1.5 rounded-full" style={{ backgroundColor: MODALITY_COLORS[m.id].hex }} />
                <span className="text-[9px] text-muted-foreground/60">{MODALITY_COLORS[m.id].label}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/40 font-medium">
            Sources
          </p>
          <div className="grid grid-cols-2 gap-2">
            {philSummaries.map(({ p, fwCount, color }) => (
              <div
                key={p.id}
                className="flex items-start gap-2.5 rounded-lg border border-border/30 bg-card/40 px-3 py-2.5"
                style={{ borderLeftColor: color, borderLeftWidth: 2 }}
              >
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-medium leading-snug truncate">{p.name}</p>
                  <p className="text-[10px] text-muted-foreground/60 mt-0.5">
                    {fwCount} framework{fwCount !== 1 ? 's' : ''} · {p.bias.length} bias{p.bias.length !== 1 ? 'es' : ''}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select a philosophy from the list to explore its full structure
        </p>
      </div>
    </div>
  )
}

// ─── Modality overview (nothing selected) ────────────────────────────────────

function ModalityOverview({
  modalities,
  onSelect,
}: {
  modalities: Modality[]
  onSelect: (m: Modality) => void
}) {
  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-8 py-12 space-y-8">
        <div className="space-y-3">
          <p className="text-[10px] uppercase tracking-widest text-muted-foreground/50 font-medium">
            Training ontology
          </p>
          <h2 className="text-2xl font-semibold leading-snug">
            {modalities.length} training modalities.
          </h2>
          <p className="text-sm text-muted-foreground leading-relaxed max-w-lg">
            Modalities define how the body is loaded — the what of each training session. Select any tile to explore its structure, intensity zones, compatibility, and featured philosophies.
          </p>
        </div>

        <div className="grid grid-cols-3 gap-2">
          {modalities.map((mod) => {
            const color = MODALITY_COLORS[mod.id]
            const hex = color?.hex ?? '#6366f1'
            return (
              <button
                key={mod.id}
                type="button"
                onClick={() => onSelect(mod)}
                className="text-left rounded-lg border border-border/40 bg-card/40 overflow-hidden hover:border-primary/40 transition-colors"
              >
                <div className="h-1 w-full" style={{ backgroundColor: hex, opacity: 0.7 }} />
                <div className="px-3 py-2.5 space-y-1.5">
                  <p className="text-[11px] font-semibold leading-snug" style={{ color: hex }}>{mod.name}</p>
                  <RecoveryCostBadge cost={mod.recovery_cost} />
                  <p className="text-[10px] text-muted-foreground leading-relaxed line-clamp-2">
                    {mod.description}
                  </p>
                </div>
              </button>
            )
          })}
        </div>

        <p className="text-[10px] text-muted-foreground/30 text-center pb-4">
          Select a modality to explore its full structure
        </p>
      </div>
    </div>
  )
}

// ─── Modality signature — intensity strip + volume / session range bars ────────

function ModalitySignature({ mod, allArchetypes }: { mod: Modality; allArchetypes: Archetype[] }) {
  const hex = MODALITY_COLORS[mod.id]?.hex ?? '#6366f1'

  // Which HR zones are active for this modality
  const activeZones = useMemo(() => {
    const zones = mod.intensity_zones ?? []
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const hasHrData = zones.some((z: any) => z.hr_pct_min != null)
    const active = new Set<string>()
    if (hasHrData) {
      for (const z of zones) {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const zz = z as any
        if (zz.hr_pct_min == null) continue
        for (const def of HR_ZONES) {
          if (zz.hr_pct_min < def.max && zz.hr_pct_max > def.min) active.add(def.id)
        }
      }
    } else {
      // Infer from recovery cost when no HR data available
      if (mod.recovery_cost === 'low')    { active.add('z1'); active.add('z2') }
      else if (mod.recovery_cost === 'medium') { active.add('z2'); active.add('z3') }
      else                                { active.add('z4'); active.add('z5') }
    }
    return active
  }, [mod])

  const recoveryLevel = { low: 1, medium: 2, high: 3 }[mod.recovery_cost] ?? 1
  const recoveryColor = { low: '#10b981', medium: '#f59e0b', high: '#ef4444' }[mod.recovery_cost]

  const VOL_MAX = 600
  const volMinPct = (mod.min_weekly_minutes / VOL_MAX) * 100
  const volRangePct = ((mod.max_weekly_minutes - mod.min_weekly_minutes) / VOL_MAX) * 100

  const SESS_MAX = 180
  const session = mod.typical_session_minutes
  const sessMinPct = session ? (session.min / SESS_MAX) * 100 : 0
  const sessRangePct = session ? Math.min(((session.max - session.min) / SESS_MAX) * 100, 100 - sessMinPct) : 0

  const archetypeCount = allArchetypes.filter(a => a.modality === mod.id).length

  return (
    <div className="flex flex-col gap-4">

      {/* Header: label + recovery meter */}
      <div className="flex items-center justify-between">
        <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Profile</p>
        <div className="flex items-center gap-1.5">
          <span className="text-[9px] font-mono text-muted-foreground/35 uppercase tracking-wider">recovery</span>
          <div className="flex gap-0.5">
            {[1, 2, 3].map(n => (
              <div key={n} className="size-2.5 rounded-full transition-all"
                style={{
                  backgroundColor: n <= recoveryLevel ? recoveryColor : 'transparent',
                  border: `1px solid ${n <= recoveryLevel ? recoveryColor : '#334155'}`,
                  opacity: n <= recoveryLevel ? (n === recoveryLevel ? 1 : 0.6) : 0.25,
                }} />
            ))}
          </div>
        </div>
      </div>

      {/* Intensity zone strip */}
      <div className="space-y-1.5">
        <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Intensity</p>
        <div className="flex gap-0.5">
          {HR_ZONES.map(def => {
            const active = activeZones.has(def.id)
            return (
              <div key={def.id} className="flex-1 flex items-center justify-center rounded py-1.5 transition-all"
                style={{
                  backgroundColor: active ? `${hex}cc` : 'transparent',
                  border: `1px solid ${active ? hex : '#1e293b'}`,
                }}>
                <span className="text-[9px] font-mono font-medium"
                  style={{ color: active ? '#fff' : '#334155' }}>
                  {def.label}
                </span>
              </div>
            )
          })}
        </div>
        <div className="flex justify-between px-0.5">
          <span className="text-[8px] font-mono text-muted-foreground/25">low</span>
          <span className="text-[8px] font-mono text-muted-foreground/25">high</span>
        </div>
      </div>

      {/* Weekly volume range */}
      <div className="space-y-1.5">
        <div className="flex items-baseline justify-between">
          <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Volume / week</p>
          <span className="text-[9px] font-mono tabular-nums text-muted-foreground/50">
            {mod.min_weekly_minutes}–{mod.max_weekly_minutes} min
          </span>
        </div>
        <div className="relative h-2 rounded-full bg-muted/20 overflow-hidden">
          <div className="absolute h-full rounded-full"
            style={{ left: `${volMinPct}%`, width: `${Math.max(volRangePct, 4)}%`, backgroundColor: hex, opacity: 0.65 }} />
        </div>
        <div className="flex justify-between px-0.5">
          <span className="text-[8px] font-mono text-muted-foreground/25">0</span>
          <span className="text-[8px] font-mono text-muted-foreground/25">600 min/wk</span>
        </div>
      </div>

      {/* Session duration range */}
      {session && (
        <div className="space-y-1.5">
          <div className="flex items-baseline justify-between">
            <p className="text-[9px] uppercase tracking-wider text-muted-foreground/35 font-medium">Session</p>
            <span className="text-[9px] font-mono tabular-nums text-muted-foreground/50">
              {session.min}–{session.max} min
            </span>
          </div>
          <div className="relative h-2 rounded-full bg-muted/20 overflow-hidden">
            <div className="absolute h-full rounded-full"
              style={{ left: `${sessMinPct}%`, width: `${Math.max(sessRangePct, 4)}%`, backgroundColor: hex, opacity: 0.65 }} />
          </div>
          <div className="flex justify-between px-0.5">
            <span className="text-[8px] font-mono text-muted-foreground/25">0</span>
            <span className="text-[8px] font-mono text-muted-foreground/25">180 min</span>
          </div>
        </div>
      )}

      {/* Footer: session position + archetype count */}
      <div className="flex items-center justify-between pt-0.5">
        <div className="flex gap-1">
          {(['first', 'standalone', 'any'] as const).map(pos => (
            <span key={pos}
              className="px-1.5 py-0.5 rounded text-[9px] font-mono transition-colors"
              style={{
                backgroundColor: mod.session_position === pos ? `${hex}20` : 'transparent',
                color: mod.session_position === pos ? hex : '#334155',
                border: `1px solid ${mod.session_position === pos ? `${hex}50` : '#1e293b'}`,
              }}>
              {pos}
            </span>
          ))}
        </div>
        {archetypeCount > 0 && (
          <span className="text-[9px] font-mono text-muted-foreground/35">
            {archetypeCount} archetype{archetypeCount !== 1 ? 's' : ''}
          </span>
        )}
      </div>

    </div>
  )
}

// ─── Modality detail ──────────────────────────────────────────────────────────

function ModalityDetail({
  mod,
  philosophies,
  allArchetypes,
}: {
  mod: Modality
  philosophies: Philosophy[]
  allArchetypes: Archetype[]
}) {
  const color = MODALITY_COLORS[mod.id]
  const hex = color?.hex ?? '#6366f1'

  const featuredIn = useMemo(
    () => philosophies.filter(p => p.bias.includes(mod.id)),
    [mod.id, philosophies]
  )

  return (
    <div className="h-full overflow-y-auto">
      <div className="px-4 py-4 space-y-4">

        {/* Header card — two-column layout matching philosophy explorer */}
        <div
          className="rounded-lg border p-4"
          style={{ borderColor: `${hex}40`, backgroundColor: `${hex}05` }}
        >
          <div className="flex gap-0 items-start">
            {/* Left: identity + stats */}
            <div className="flex-1 min-w-0 pr-5 space-y-3">
              <div className="space-y-1">
                <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Modality</p>
                <h2 className="text-base font-semibold" style={{ color: hex }}>{mod.name}</h2>
              </div>

              <div className="flex flex-wrap gap-1.5">
                <RecoveryCostBadge cost={mod.recovery_cost} />
                <span className="inline-block px-1.5 py-0.5 rounded text-[10px] font-medium bg-muted/50 text-muted-foreground">
                  {prettify(mod.progression_model)}
                </span>
              </div>

              <p className="text-[11px] text-muted-foreground leading-relaxed">{mod.description}</p>

              <div className="grid grid-cols-2 gap-2 pt-1">
                <StatCell label="Session position" value={prettify(mod.session_position)} />
                {mod.typical_session_minutes && (
                  <StatCell label="Typical session" value={`${mod.typical_session_minutes.min}–${mod.typical_session_minutes.max} min`} />
                )}
                <StatCell label="Weekly volume" value={`${mod.min_weekly_minutes}–${mod.max_weekly_minutes} min`} />
                <StatCell label="Recovery minimum" value={`${mod.recovery_hours_min}h`} />
              </div>
            </div>

            {/* Right: modality signature */}
            <div className="shrink-0 pl-5 border-l" style={{ borderColor: `${hex}20`, width: '36%', minWidth: 240 }}>
              <ModalitySignature mod={mod} allArchetypes={allArchetypes} />
            </div>
          </div>
        </div>

        {/* Intensity zones */}
        {mod.intensity_zones && mod.intensity_zones.length > 0 && (
          <Section label="Intensity zones">
            <div className="space-y-1.5">
              {mod.intensity_zones.map((zone, i) => (
                <div key={i} className="flex items-start gap-3 rounded-md border border-border/30 bg-card/30 px-3 py-2">
                  <div className="mt-0.5 size-1.5 rounded-full shrink-0" style={{ backgroundColor: hex, opacity: 0.7 }} />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-[11px] font-medium text-foreground">{zone.label}</span>
                      {zone.hr_pct_range && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted/50 text-muted-foreground font-mono">
                          {zone.hr_pct_range[0]}–{zone.hr_pct_range[1]}% HR
                        </span>
                      )}
                    </div>
                    {zone.description && (
                      <p className="text-[10px] text-muted-foreground mt-0.5 leading-relaxed">{zone.description}</p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </Section>
        )}

        {/* Compatibility */}
        {(mod.compatible_in_session_with.length > 0 || mod.incompatible_in_session_with.length > 0) && (
          <Section label="Compatibility">
            <div className="grid grid-cols-2 gap-3">
              {mod.compatible_in_session_with.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-[10px] text-emerald-400/70 font-medium">Pairs well with</p>
                  <div className="flex flex-wrap gap-1">
                    {mod.compatible_in_session_with.map((id) => {
                      const c = MODALITY_COLORS[id]
                      return (
                        <span key={id} className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] bg-emerald-500/10 text-emerald-300 border border-emerald-500/20">
                          <span className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: c?.hex ?? '#10b981' }} />
                          {c?.label ?? prettify(id)}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )}
              {mod.incompatible_in_session_with.length > 0 && (
                <div className="space-y-1.5">
                  <p className="text-[10px] text-red-400/70 font-medium">Avoid combining</p>
                  <div className="flex flex-wrap gap-1">
                    {mod.incompatible_in_session_with.map((id) => {
                      const c = MODALITY_COLORS[id]
                      return (
                        <span key={id} className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] bg-red-500/10 text-red-300 border border-red-500/20">
                          <span className="size-1.5 rounded-full shrink-0" style={{ backgroundColor: c?.hex ?? '#ef4444' }} />
                          {c?.label ?? prettify(id)}
                        </span>
                      )
                    })}
                  </div>
                </div>
              )}
            </div>
          </Section>
        )}

        {/* Featured in */}
        {featuredIn.length > 0 && (
          <Section label="Featured in">
            <div className="flex flex-wrap gap-1.5">
              {featuredIn.map((p) => {
                const phColor = MODALITY_COLORS[p.bias[0] as ModalityId]?.hex ?? '#6366f1'
                return (
                  <span key={p.id}
                    className="inline-block px-2 py-0.5 rounded-full text-[10px] border border-border/40 bg-card/40 text-muted-foreground"
                    style={{ borderLeftColor: phColor, borderLeftWidth: 2 }}>
                    {p.name}
                  </span>
                )
              })}
            </div>
          </Section>
        )}

        {/* Sources */}
        {mod.sources && mod.sources.length > 0 && (
          <Section label="Sources">
            <ul className="space-y-0.5">
              {mod.sources.map((s, i) => (
                <li key={i} className="text-[10px] text-muted-foreground/60 italic">{s}</li>
              ))}
            </ul>
          </Section>
        )}

        {/* Notes */}
        {mod.notes && (
          <Section label="Notes">
            <p className="text-[11px] text-muted-foreground leading-relaxed">{mod.notes}</p>
          </Section>
        )}
      </div>
    </div>
  )
}

// ─── Exercise components ──────────────────────────────────────────────────────

const EX_CATEGORY_COLORS: Record<string, string> = {
  barbell:     '#ef4444',
  kettlebell:  '#f97316',
  bodyweight:  '#10b981',
  aerobic:     '#0ea5e9',
  loaded_carry:'#f59e0b',
  sandbag:     '#ca8a04',
  mobility:    '#14b8a6',
  skill:       '#8b5cf6',
  rehab:       '#84cc16',
  gym_jones:   '#ec4899',
}

const EX_EFFORT_COLORS: Record<string, string> = {
  low: '#10b981', medium: '#f59e0b', high: '#f97316', max: '#ef4444',
}

const EX_CATEGORIES = [
  { id: '', label: 'All' },
  { id: 'barbell', label: 'Barbell' },
  { id: 'kettlebell', label: 'KB' },
  { id: 'bodyweight', label: 'BW' },
  { id: 'aerobic', label: 'Aerobic' },
  { id: 'loaded_carry', label: 'Carries' },
  { id: 'sandbag', label: 'Sandbag' },
  { id: 'mobility', label: 'Mobility' },
  { id: 'skill', label: 'Skill' },
  { id: 'rehab', label: 'Rehab' },
]

function ExerciseRow({
  exercise,
  isSelected,
  onSelect,
}: {
  exercise: Exercise
  isSelected: boolean
  onSelect: (e: Exercise | null) => void
}) {
  const accent = EX_CATEGORY_COLORS[exercise.category] ?? '#6366f1'
  return (
    <button
      type="button"
      onClick={() => onSelect(isSelected ? null : exercise)}
      className={cn(
        'w-full text-left rounded-lg border bg-card transition-colors px-3 py-2',
        !isSelected && 'hover:border-primary/40',
      )}
      style={isSelected
        ? { borderColor: accent, borderWidth: 2, backgroundColor: `${accent}10` }
        : { borderLeftColor: accent, borderLeftWidth: 3 }
      }
    >
      <div className="flex items-center gap-2 min-w-0">
        <p className="text-xs font-medium leading-snug flex-1 truncate">{exercise.name}</p>
        <div className="size-1.5 rounded-full shrink-0"
          style={{ backgroundColor: EX_EFFORT_COLORS[exercise.effort] ?? '#94a3b8' }}
          title={exercise.effort} />
      </div>
      <p className="text-[10px] mt-0.5" style={{ color: accent, opacity: 0.85 }}>
        {exercise.category.replace(/_/g, ' ')}
      </p>
    </button>
  )
}

function ExerciseOverview({ exercises }: { exercises: Exercise[] }) {
  const byCat = useMemo(() => {
    const counts: Record<string, number> = {}
    for (const e of exercises) counts[e.category] = (counts[e.category] ?? 0) + 1
    return Object.entries(counts).sort((a, b) => b[1] - a[1])
  }, [exercises])
  const max = byCat[0]?.[1] ?? 1

  return (
    <div className="h-full overflow-y-auto">
      <div className="px-8 py-10 max-w-lg space-y-6">
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-1">Total</p>
          <p className="text-3xl font-bold tabular-nums">{exercises.length}</p>
          <p className="text-xs text-muted-foreground mt-0.5">exercises in catalog</p>
        </div>
        <div className="space-y-2">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">By category</p>
          {byCat.map(([cat, count]) => {
            const color = EX_CATEGORY_COLORS[cat] ?? '#6366f1'
            return (
              <div key={cat} className="flex items-center gap-3">
                <div className="w-20 shrink-0">
                  <p className="text-[10px] text-muted-foreground capitalize">{cat.replace(/_/g, ' ')}</p>
                </div>
                <div className="flex-1 h-1.5 rounded-full bg-muted/20 overflow-hidden">
                  <div className="h-full rounded-full" style={{ width: `${(count / max) * 100}%`, backgroundColor: color, opacity: 0.7 }} />
                </div>
                <span className="text-[10px] font-mono tabular-nums text-muted-foreground/60 w-6 text-right">{count}</span>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}

function ExercisePanel({
  exercise,
  allExercises,
  onNavigate,
}: {
  exercise: Exercise
  allExercises: Exercise[]
  onNavigate: (id: string) => void
}) {
  return (
    <div className="h-full overflow-y-auto">
      <div className="px-6 py-5 space-y-5">

        {/* Header */}
        <div>
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-1">Exercise</p>
          <h2 className="text-base font-semibold"
            style={{ color: EX_CATEGORY_COLORS[exercise.category] ?? undefined }}>
            {exercise.name}
          </h2>
          <div className="flex flex-wrap gap-1 mt-2">
            {exercise.modality.map((m) => <ModalityBadge key={m} modality={m} />)}
          </div>
        </div>

        {/* Meta grid */}
        <div className="grid grid-cols-2 gap-2">
          {[
            { label: 'Category', value: exercise.category.replace(/_/g, ' ') },
            { label: 'Effort',   value: exercise.effort },
            { label: 'Bilateral', value: exercise.bilateral ? 'Yes' : 'No' },
            ...(exercise.typical_volume
              ? [{ label: 'Typical', value: `${exercise.typical_volume.sets}×${exercise.typical_volume.reps}` }]
              : []),
          ].map(({ label, value }) => (
            <div key={label} className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
              <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
              <p className="text-[11px] font-medium capitalize">{value}</p>
            </div>
          ))}
        </div>

        {/* Movement patterns */}
        {exercise.movement_patterns.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Patterns</p>
            <div className="flex flex-wrap gap-1">
              {exercise.movement_patterns.map((p) => (
                <span key={p} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground capitalize">
                  {p.replace(/_/g, ' ')}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Progressions */}
        {Object.keys(exercise.progressions).length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Progressions</p>
            <div className="space-y-1 text-xs text-muted-foreground">
              {exercise.progressions.load && <p><span className="text-foreground font-medium">Load:</span> {exercise.progressions.load}</p>}
              {exercise.progressions.volume && <p><span className="text-foreground font-medium">Volume:</span> {exercise.progressions.volume}</p>}
              {exercise.progressions.complexity && <p><span className="text-foreground font-medium">Complexity:</span> {exercise.progressions.complexity}</p>}
            </div>
          </div>
        )}

        {/* Scale down */}
        {exercise.scaling_down && exercise.scaling_down.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Scale Down To</p>
            <div className="flex flex-wrap gap-1">
              {exercise.scaling_down.map((s) => (
                <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">
                  {s.replace(/_/g, ' ')}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Notes */}
        {exercise.notes && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Coaching Notes</p>
            <p className="text-xs text-muted-foreground leading-relaxed">{exercise.notes}</p>
          </div>
        )}

        {/* Prereq chain */}
        <div className="space-y-2 border-t border-border/30 pt-4">
          <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Progression Chain</p>
          <PrereqChain
            exercise={exercise}
            allExercises={allExercises}
            onSelect={(id) => onNavigate(id)}
          />
        </div>

        {/* Sources */}
        {exercise.sources.length > 0 && (
          <div className="space-y-1.5">
            <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">Sources</p>
            <div className="flex flex-wrap gap-1">
              {exercise.sources.map((s) => (
                <span key={s} className="text-[10px] rounded-full bg-muted px-2 py-0.5 text-muted-foreground">{s}</span>
              ))}
            </div>
          </div>
        )}

      </div>
    </div>
  )
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <p className="text-[10px] uppercase tracking-wider text-muted-foreground/50 font-medium">{label}</p>
      {children}
    </div>
  )
}

function StatCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border/30 bg-card/30 px-2.5 py-2">
      <p className="text-[9px] uppercase tracking-wider text-muted-foreground/50 font-medium mb-0.5">{label}</p>
      <p className="text-[11px] font-medium text-foreground">{value}</p>
    </div>
  )
}

// ─── Page ─────────────────────────────────────────────────────────────────────

type ExploreSection = 'explorer' | 'ontology'

const EXPLORE_SECTIONS: { key: ExploreSection; label: string }[] = [
  { key: 'explorer', label: 'Explorer' },
  { key: 'ontology', label: 'Ontology' },
]

export function Explore() {
  const [section, setSection] = useState<ExploreSection>('explorer')
  const [topic, setTopic] = useState<Topic>('philosophies')
  const [selectedPhil, setSelectedPhil] = useState<Philosophy | null>(null)
  const [selectedMod, setSelectedMod] = useState<Modality | null>(null)
  const [selectedExercise, setSelectedExercise] = useState<Exercise | null>(null)
  const [exSearch, setExSearch] = useState('')
  const [exCategory, setExCategory] = useState('')
  const debouncedSearch = useDebounce(exSearch, 250)

  const { data: philosophies = [], isLoading: philLoading, error: philError } = usePhilosophies()
  const { data: frameworks = [] } = useFrameworks()
  const { data: modalities = [], isLoading: modLoading, error: modError } = useModalities()
  const { data: allArchetypes = [] } = useArchetypes()
  const { data: allExercises = [] } = useExercises()
  const { data: filteredExercises = [] } = useExercises(
    debouncedSearch || exCategory
      ? { search: debouncedSearch || undefined, category: exCategory || undefined }
      : undefined
  )

  function handleTopicChange(t: Topic) {
    setTopic(t)
    setSelectedPhil(null)
    setSelectedMod(null)
    setSelectedExercise(null)
  }

  function handleNavigateExercise(id: string) {
    const ex = allExercises.find((e) => e.id === id)
    if (ex) setSelectedExercise(ex)
  }

  const isLoading = topic === 'philosophies' ? philLoading : modLoading
  const error = topic === 'philosophies' ? philError : modError

  return (
    <motion.div
      key="explore"
      initial={{ opacity: 0, y: 16 }}
      animate={{ opacity: 1, y: 0, transition: { duration: 0.25 } }}
      exit={{ opacity: 0, y: -8, transition: { duration: 0.15 } }}
      className="flex h-full flex-col"
    >
      {/* Header */}
      <div className="flex items-center gap-3 border-b px-6 py-4 shrink-0">
        <Compass className="size-5 text-primary" />
        <h1 className="text-lg font-semibold">Explore</h1>
        <div className="ml-2 flex gap-1">
          {EXPLORE_SECTIONS.map(({ key, label }) => (
            <button
              key={key}
              onClick={() => setSection(key)}
              className={cn(
                'px-3 py-1 rounded text-xs border transition-colors',
                section === key
                  ? 'bg-primary/15 border-primary/40 text-primary'
                  : 'border-border text-muted-foreground hover:bg-muted'
              )}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {/* ── Explorer ── */}
      {section === 'explorer' && (
        topic !== 'exercises' && (isLoading
          ? <div className="flex-1 p-6"><LoadingCard /></div>
          : error
          ? <div className="flex-1 p-6"><ErrorBanner error={error as Error} /></div>
          : null)
      )}

      {section === 'explorer' && (topic === 'exercises' || (!isLoading && !error)) && (
        <div className="flex flex-1 min-h-0">
          {/* Left column */}
          <div className="shrink-0 flex flex-col border-r" style={{ width: 272 }}>
            <TopicSelector active={topic} onChange={handleTopicChange} />

            {topic !== 'exercises' && (
              <div className="flex-1 overflow-y-auto p-3 space-y-1.5">
                {topic === 'philosophies'
                  ? philosophies.map((phil) => (
                      <PhilCard
                        key={phil.id}
                        phil={phil}
                        isSelected={selectedPhil?.id === phil.id}
                        onSelect={setSelectedPhil}
                      />
                    ))
                  : modalities.map((mod) => (
                      <ModalityCard
                        key={mod.id}
                        mod={mod}
                        isSelected={selectedMod?.id === mod.id}
                        onSelect={setSelectedMod}
                      />
                    ))
                }
              </div>
            )}

            {topic === 'exercises' && (
              <div className="flex flex-col flex-1 min-h-0">
                {/* Search */}
                <div className="px-3 pt-2 pb-1">
                  <div className="relative">
                    <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 size-3 text-muted-foreground" />
                    <input
                      placeholder="Search…"
                      value={exSearch}
                      onChange={(e) => setExSearch(e.target.value)}
                      className="w-full rounded-md border border-border bg-background pl-7 pr-7 h-8 text-xs focus:outline-none focus:ring-1 focus:ring-primary/50"
                    />
                    {exSearch && (
                      <button onClick={() => setExSearch('')}
                        className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
                        <X className="size-3" />
                      </button>
                    )}
                  </div>
                </div>
                {/* Category pills */}
                <div className="px-3 pb-2 flex flex-wrap gap-1">
                  {EX_CATEGORIES.map(({ id, label }) => (
                    <button key={id} onClick={() => setExCategory(id)}
                      className={cn(
                        'px-2 py-0.5 rounded text-[10px] border transition-colors',
                        exCategory === id
                          ? 'bg-primary/15 border-primary/40 text-primary'
                          : 'border-border/50 text-muted-foreground hover:bg-muted/50'
                      )}>
                      {label}
                    </button>
                  ))}
                </div>
                {/* Count */}
                <div className="px-3 pb-1">
                  <span className="text-[10px] text-muted-foreground/50 font-mono">{filteredExercises.length} exercises</span>
                </div>
                {/* List */}
                <div className="flex-1 overflow-y-auto px-3 pb-3 space-y-1">
                  {filteredExercises.map((ex) => (
                    <ExerciseRow
                      key={ex.id}
                      exercise={ex}
                      isSelected={selectedExercise?.id === ex.id}
                      onSelect={setSelectedExercise}
                    />
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Right column */}
          <div className="flex-1 min-h-0 overflow-hidden">
            {topic === 'philosophies'
              ? selectedPhil
                ? <PhilosophyExplorerPanel controlledId={selectedPhil.id} />
                : <PhilosophyOverview philosophies={philosophies} frameworks={frameworks} />
              : topic === 'modalities'
              ? selectedMod
                ? <ModalityDetail mod={selectedMod} philosophies={philosophies} allArchetypes={allArchetypes} />
                : <ModalityOverview modalities={modalities} onSelect={setSelectedMod} />
              : selectedExercise
                ? <ExercisePanel exercise={selectedExercise} allExercises={allExercises} onNavigate={handleNavigateExercise} />
                : <ExerciseOverview exercises={allExercises} />
            }
          </div>
        </div>
      )}

      {/* ── Ontology ── */}
      {section === 'ontology' && (
        <div className="flex-1 overflow-y-auto px-6 py-4" style={{ scrollbarGutter: 'stable' }}>
          <HeatmapPanel program={null} />
        </div>
      )}
    </motion.div>
  )
}
